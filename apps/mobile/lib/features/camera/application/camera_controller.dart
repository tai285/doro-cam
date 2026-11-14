import 'dart:async';
import 'dart:io';

import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/intent_resolver.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:doro_cam/domain/experience/layers.dart';
import 'package:doro_cam/domain/experience/preset.dart';
import 'package:doro_cam/domain/experience/scenario.dart';
import 'package:doro_cam/features/camera/application/camera_mapping.dart';
import 'package:doro_cam/features/camera/application/camera_state.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:doro_cam/profiles/builtin_profiles.dart';
import 'package:doro_cam/profiles/lut.dart';
import 'package:doro_camera/doro_camera.dart' as cam;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings keys owned by the camera feature.
abstract final class CameraSettingKeys {
  static const experience = 'camera.experience';
  static const authentic = 'camera.authentic';
  static const frames = 'camera.film_frames';
  static String live(String experienceId) => 'camera.live.$experienceId';
}

/// Waits between countdown ticks. Replaced in tests so they do not sleep.
final cameraDelayProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (d) => Future<void>.delayed(d),
);

final profileRegistryProvider = Provider<ProfileRegistry>(
  (ref) => ProfileRegistry.builtIn(),
);

/// Compiled once per profile and kept: compiling a 33³ LUT is not free.
final compiledLutProvider = Provider.family<Lut3d, String>((ref, profileId) {
  final profile = ref.watch(profileRegistryProvider).resolve(profileId);
  return compileProfile(profile);
});

/// An IANA zone name for the device clock. Whole-hour offsets map to `Etc/GMT∓N` (valid everywhere, including
/// the server's formatter); anything else falls back to UTC rather than store something unparsable.
String timezoneFromOffset(Duration offset) {
  if (offset.inMinutes == 0 || offset.inMinutes % 60 != 0) {
    return 'UTC';
  }
  final hours = offset.inHours;
  return 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
}

final cameraControllerProvider =
    NotifierProvider<CameraController, CameraState>(CameraController.new);

class CameraController extends Notifier<CameraState> {
  StreamSubscription<Set<String>>? _disabledSub;
  StreamSubscription<cam.SessionEvent>? _eventSub;
  Timer? _recordingTimer;
  bool _disposed = false;

  /// The open session, mirrored here because `state` cannot be read while the provider is being disposed.
  cam.CameraSession? _openSession;

  @override
  CameraState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_disabledSub?.cancel());
      unawaited(_eventSub?.cancel());
      _recordingTimer?.cancel();
      final session = _openSession;
      if (session != null) {
        unawaited(session.close());
      }
    });
    return const CameraState();
  }

  cam.CameraSession? get _session => state.session;

  void _set(CameraState next) {
    if (!_disposed) {
      state = next;
    }
  }

  // ---- start-up ------------------------------------------------------------------------------

  /// Checks permissions and opens the camera, or reports what is missing (CAM-052).
  Future<void> open({bool requestPermission = false}) async {
    _set(state.copyWith(phase: CameraPhase.initializing, clearError: true));
    try {
      final camera = ref.read(doroCameraProvider);
      var permissions = await camera.checkPermissions();
      if (requestPermission && !permissions.cameraGranted) {
        permissions = await camera.requestPermissions();
      }
      if (!permissions.cameraGranted) {
        _set(
          state.copyWith(
            phase: CameraPhase.needsPermission,
            permissions: permissions,
            clearSession: true,
          ),
        );
        return;
      }
      final settings = ref.read(settingsRepositoryProvider);
      final experience = Experiences.fromName(
        await settings.read(CameraSettingKeys.experience),
      );
      final authentic = await settings.readBool(
        CameraSettingKeys.authentic,
        fallback: false,
      );
      final frames =
          int.tryParse(await settings.read(CameraSettingKeys.frames) ?? '') ??
          0;
      final cameras = await camera.listCameras();
      if (cameras.isEmpty) {
        _set(
          state.copyWith(
            phase: CameraPhase.noCamera,
            permissions: permissions,
            cameras: cameras,
          ),
        );
        return;
      }
      final first = cameras.firstWhere(
        (c) =>
            c.facing == cam.CameraFacing.back &&
            c.source == cam.CameraSource.hardware,
        orElse: () => cameras.firstWhere(
          (c) => c.facing == cam.CameraFacing.back,
          orElse: () => cameras.first,
        ),
      );
      _set(
        state.copyWith(
          permissions: permissions,
          cameras: cameras,
          experience: experience,
          authentic: authentic,
          framesShot: frames,
          user: CaptureIntent(
            live:
                await settings.readBool(
                  CameraSettingKeys.live(experience.id.name),
                  fallback: false,
                )
                ? true
                : null,
          ),
        ),
      );
      await _openCamera(first);
    } on cam.CameraException catch (error) {
      _fail(error);
    } on Object catch (error) {
      _set(
        state.copyWith(
          phase: CameraPhase.failed,
          errorMessage: 'The camera could not start: $error',
        ),
      );
    }
  }

  void _fail(cam.CameraException error) {
    final message = switch (error.code) {
      'camera_in_use' =>
        'Another app is using the camera. Close it and try again.',
      'permission_denied' ||
      'permission_restricted' => 'Camera access is off for Doro Cam.',
      _ => error.message ?? 'The camera could not start (${error.code}).',
    };
    final permissionProblem = error.code.startsWith('permission');
    _set(
      state.copyWith(
        phase: permissionProblem
            ? CameraPhase.needsPermission
            : CameraPhase.failed,
        errorMessage: message,
        clearSession: true,
      ),
    );
  }

  Future<void> _openCamera(cam.CameraDescriptor descriptor) async {
    final platform = ref.read(doroCameraProvider);
    final old = state.session;
    if (old != null) {
      await _disabledSub?.cancel();
      await _eventSub?.cancel();
      await old.close();
    }
    final pluginCaps = await platform.capabilities(descriptor.id);
    final caps = toDomainCapabilities(pluginCaps);
    _openSession = null;
    _set(
      state.copyWith(
        camera: descriptor,
        pluginCaps: pluginCaps,
        caps: caps,
        clearSession: true,
        disabled: const <IntentField>{},
      ),
    );
    _recompute(applyToSession: false);
    final settings = state.settings;
    final permissions = state.permissions;
    final session = await platform.open(
      cam.SessionConfig(
        cameraId: descriptor.id,
        photoFormat: _pluginFormat(settings?.photoFormat),
        live: (settings?.live ?? false) && caps.live.supported,
        audio:
            (permissions?.microphoneGranted ?? false) &&
            !(settings?.muteAudio ?? false),
      ),
    );
    _openSession = session;
    _disabledSub = session.disabledControlsChanges.listen(_onDisabled);
    _eventSub = session.events.listen(_onEvent);
    _set(state.copyWith(phase: CameraPhase.ready, session: session));
    await _applyToSession();
  }

  cam.PhotoFormat _pluginFormat(Enum? format) =>
      cam.PhotoFormat.values.byName(format?.name ?? 'jpeg');

  void _onDisabled(Set<String> fields) {
    final mapped = <IntentField>{
      for (final field in IntentField.values)
        if (fields.contains(field.name) ||
            (field == IntentField.exposureTime && fields.contains('shutter')))
          field,
    };
    if (mapped.isEmpty) {
      return;
    }
    _set(
      state.copyWith(
        disabled: <IntentField>{...state.disabled, ...mapped},
        notice: 'This camera ignored a manual setting, so that control is switched off for this session.',
      ),
    );
  }

  void _onEvent(cam.SessionEvent event) {
    if (event.kind == cam.SessionEventKind.thermal && event.thermal != null) {
      _set(state.copyWith(thermal: event.thermal));
      if ((event.thermal == cam.ThermalState.serious ||
              event.thermal == cam.ThermalState.critical) &&
          state.liveOn) {
        unawaited(
          setLive(
            enabled: false,
            reason: 'The phone is getting hot, so LIVE was turned off.',
          ),
        );
      }
    }
    if (event.kind == cam.SessionEventKind.error &&
        event.errorMessage != null) {
      _set(state.copyWith(notice: event.errorMessage));
    }
  }

  /// Opens the system dialogs, or the settings page when the user already refused twice.
  Future<void> requestPermissions() async {
    final permissions = state.permissions;
    if (permissions != null && permissions.cameraPermanentlyDenied) {
      await ref.read(doroCameraProvider).openAppSettings();
      return;
    }
    await open(requestPermission: true);
  }

  Future<void> openSystemSettings() =>
      ref.read(doroCameraProvider).openAppSettings();

  // ---- resolution ----------------------------------------------------------------------------

  void _recompute({bool applyToSession = true}) {
    final s = state;
    final layered = layerIntents(
      experience: s.experience,
      scenario: s.scenario,
      preset: s.preset,
      user: _withoutDisabled(s.user, s.disabled),
    );
    final result = resolve(
      layered.intent,
      s.caps,
      experience: s.experience,
      authentic: s.authentic,
      framesShot: s.framesShot,
    );
    _set(s.copyWith(layered: layered, result: result));
    if (applyToSession) {
      unawaited(_applyToSession());
    }
  }

  CaptureIntent _withoutDisabled(
    CaptureIntent intent,
    Set<IntentField> disabled,
  ) => disabled.isEmpty ? intent : intent.without(disabled);

  Future<void> _applyToSession() async {
    final session = _session;
    final settings = state.settings;
    if (session == null || session.isClosed || settings == null) {
      return;
    }
    try {
      await session.apply(toPluginSettings(settings));
    } on cam.CameraException catch (error) {
      _set(
        state.copyWith(
          notice:
              error.message ??
              'The camera refused those settings (${error.code}).',
        ),
      );
    }
  }

  /// A user override of one or more fields (the top layer). Authentic Experiences refuse locked fields (EXP-003).
  void adjust(CaptureIntent Function(CaptureIntent user) change) {
    final next = change(state.user);
    _set(state.copyWith(user: next, clearNotice: true));
    _recompute();
  }

  /// Removes the user's overrides, back to the scenario or preset (ADR-0003).
  void resetOverrides() {
    final keepLive = state.user.live;
    _set(
      state.copyWith(user: CaptureIntent(live: keepLive), clearNotice: true),
    );
    _recompute();
  }

  Future<void> setExperience(Experience experience) async {
    if (experience.id == state.experience.id) {
      return;
    }
    final settings = ref.read(settingsRepositoryProvider);
    await settings.write(CameraSettingKeys.experience, experience.id.name);
    final live = await settings.readBool(
      CameraSettingKeys.live(experience.id.name),
      fallback: false,
    );
    _set(
      state.copyWith(
        experience: experience,
        clearScenario: true,
        clearPreset: true,
        user: CaptureIntent(live: live ? true : null),
        clearNotice: true,
      ),
    );
    _recompute();
    unawaited(_syncLiveWithSession());
  }

  void setScenario(Scenario? scenario) {
    _set(
      state.copyWith(
        scenario: scenario,
        clearScenario: scenario == null,
        clearPreset: true,
        clearNotice: true,
      ),
    );
    _recompute();
  }

  void setPreset(Preset? preset) {
    _set(
      state.copyWith(
        preset: preset,
        clearPreset: preset == null,
        clearScenario: true,
        clearNotice: true,
      ),
    );
    _recompute();
    unawaited(_syncLiveWithSession());
  }

  void setProfile(String profileId) =>
      adjust((u) => u.merge(CaptureIntent(profileId: profileId)));

  void setMode(CaptureMode mode) {
    if (state.recording || mode == state.mode) {
      return;
    }
    _set(state.copyWith(mode: mode));
  }

  Future<void> setAuthentic({required bool value}) async {
    await ref
        .read(settingsRepositoryProvider)
        .writeBool(CameraSettingKeys.authentic, value: value);
    _set(state.copyWith(authentic: value));
    _recompute();
  }

  Future<void> selectCamera(cam.CameraDescriptor descriptor) async {
    if (descriptor.id == state.camera?.id ||
        state.recording ||
        state.capturing) {
      return;
    }
    try {
      await _openCamera(descriptor);
    } on cam.CameraException catch (error) {
      _fail(error);
    }
  }

  /// Rear ⇄ front.
  Future<void> flip() async {
    final current = state.camera;
    if (current == null) {
      return;
    }
    final wantFront = current.facing == cam.CameraFacing.back;
    final target = state.cameras
        .where(
          (c) =>
              (c.facing == cam.CameraFacing.front) == wantFront &&
              c.source == current.source,
        )
        .toList();
    final fallback = state.cameras
        .where((c) => (c.facing == cam.CameraFacing.front) == wantFront)
        .toList();
    final choice = target.isNotEmpty
        ? target.first
        : (fallback.isNotEmpty ? fallback.first : null);
    if (choice == null) {
      _set(state.copyWith(notice: 'This device has only one camera.'));
      return;
    }
    await selectCamera(choice);
  }

  // ---- LIVE (Motion Memory) ------------------------------------------------------------------

  Future<void> setLive({required bool enabled, String? reason}) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.writeBool(
      CameraSettingKeys.live(state.experience.id.name),
      value: enabled,
    );
    _set(
      state.copyWith(
        user: state.user.merge(CaptureIntent(live: enabled)),
        notice: reason,
      ),
    );
    _recompute(applyToSession: false);
    await _syncLiveWithSession();
  }

  Future<void> _syncLiveWithSession() async {
    final session = _session;
    final want = state.settings?.live ?? false;
    if (session == null || session.isClosed || !state.caps.live.supported) {
      return;
    }
    try {
      await session.setLive(enabled: want);
    } on cam.CameraException catch (error) {
      _set(
        state.copyWith(
          notice: error.message ?? 'LIVE could not be changed (${error.code}).',
        ),
      );
    }
  }

  // ---- focus ---------------------------------------------------------------------------------

  Future<void> tapToFocus(double x, double y) async {
    final session = _session;
    if (session == null ||
        session.isClosed ||
        !state.caps.focus.tapToFocus ||
        state.disabled.contains(IntentField.focusMode)) {
      return;
    }
    _set(state.copyWith(focusPoint: (x, y)));
    try {
      await session.focusAt(x, y);
    } on cam.CameraException {
      // The focus ring simply fades; nothing to report for a missed tap.
    }
  }

  void clearFocusPoint() => _set(state.copyWith(clearFocusPoint: true));

  void dismissNotice() => _set(state.copyWith(clearNotice: true));

  void finishDeveloping() => _set(state.copyWith(clearDeveloping: true));

  // ---- lifecycle -----------------------------------------------------------------------------

  /// App went to the background: stop the preview and LIVE buffering (NFR-012).
  Future<void> suspend() async {
    final session = _session;
    if (session == null || session.isClosed) {
      return;
    }
    try {
      await session.suspend();
    } on cam.CameraException {
      // closing the session on dispose covers a failed suspend
    }
  }

  Future<void> resume() async {
    final session = _session;
    if (session == null || session.isClosed) {
      return;
    }
    try {
      await session.resume();
    } on cam.CameraException catch (error) {
      _fail(error);
    }
  }

  // ---- capture -------------------------------------------------------------------------------

  /// The shutter. Shows the self-timer, saves the Memory durably, then reports success (MEM-001, NFR-002).
  Future<MemoryView?> capture() async {
    final session = _session;
    final settings = state.settings;
    final result = state.result;
    if (session == null ||
        session.isClosed ||
        settings == null ||
        state.capturing ||
        state.recording ||
        state.camera == null) {
      return null;
    }
    if (result?.rejection != null) {
      _set(state.copyWith(notice: result!.rejection!.message));
      return null;
    }
    _set(
      state.copyWith(capturing: true, clearNotice: true, clearDeveloping: true),
    );
    final feedback = ref.read(feedbackServiceProvider);
    try {
      if (settings.timerSeconds > 0) {
        final delay = ref.read(cameraDelayProvider);
        for (var left = settings.timerSeconds; left > 0; left--) {
          _set(state.copyWith(countdown: left));
          await delay(const Duration(seconds: 1));
        }
        _set(state.copyWith(clearCountdown: true));
      }
      unawaited(
        feedback.shutter(
          sound: state.experience.workflow.shutterSoundByDefault,
        ),
      );
      final view = await _takeAndSave(session, settings);
      final frames = state.framesShot + 1;
      await ref
          .read(settingsRepositoryProvider)
          .write(CameraSettingKeys.frames, '$frames');
      _set(
        state.copyWith(
          capturing: false,
          lastCapture: view,
          developing: state.experience.workflow.developsAfterCapture
              ? view
              : null,
          framesShot: frames,
          flashPulse: state.flashPulse + 1,
        ),
      );
      _recompute(applyToSession: false);
      unawaited(
        ref
            .read(syncCoordinatorProvider)
            .syncOnce()
            .then<void>((_) {}, onError: (Object _) {}),
      );
      return view;
    } on cam.CameraException catch (error) {
      _set(
        state.copyWith(
          capturing: false,
          clearCountdown: true,
          notice: _captureError(error),
        ),
      );
      unawaited(feedback.warn());
      return null;
    } on Object catch (error) {
      _set(
        state.copyWith(
          capturing: false,
          clearCountdown: true,
          notice: 'The photo could not be saved: $error',
        ),
      );
      unawaited(feedback.warn());
      return null;
    }
  }

  String _captureError(cam.CameraException error) => switch (error.code) {
    'camera_in_use' =>
      'Another app took the camera. Nothing was lost; try again.',
    'storage_full' => 'There is not enough storage space to save a photo.',
    _ => error.message ?? 'The photo could not be taken (${error.code}).',
  };

  Future<MemoryView> _takeAndSave(
    cam.CameraSession session,
    ResolvedCaptureSettings settings,
  ) async {
    final ids = ref.read(idGeneratorProvider);
    final clock = ref.read(clockProvider);
    final memoryId = ids.newId();
    final tempRoot = await ref.read(captureTempDirProvider)();
    final dir = await Directory('${tempRoot.path}/$memoryId')
        .create(recursive: true);
    final registry = ref.read(profileRegistryProvider);
    final profile = registry.resolve(settings.profileId);
    final lut = ref.read(compiledLutProvider(profile.id));
    final location = await _locationFix();
    final now = clock();
    final live = settings.live && state.caps.live.supported;
    final request = cam.CaptureRequest(
      memoryId: memoryId,
      outputDir: dir.path,
      originalName: 'original.${_extension(session.info.photoFormat)}',
      renderedName: 'rendered.jpg',
      thumbnailName: 'thumbnail.jpg',
      displayName: 'display.jpg',
      motionName: live ? 'motion.mp4' : null,
      live: live,
      render: renderSpecFor(
        profile,
        lut,
        aspect: settings.aspect,
        crop: settings.cropNeeded,
      ),
      location: location,
      timestampEpochMs: now.millisecondsSinceEpoch,
    );
    final captured = await session.capture(request);
    final camera = state.camera!;
    final metadata = buildCaptureMetadata(
      camera: camera,
      result: captured,
      requested: settings,
      adjustments: state.result?.adjustments ?? const <Adjustment>[],
      platform: Platform.isIOS ? 'ios' : 'android',
      appVersion: ref.read(appVersionProvider),
    );
    final capturedAt = DateTime.fromMillisecondsSinceEpoch(
      captured.capturedAtEpochMs == 0
          ? now.millisecondsSinceEpoch
          : captured.capturedAtEpochMs,
      isUtc: true,
    );
    final draft = CaptureDraft(
      id: memoryId,
      kind: captured.motion != null ? MemoryKinds.motion : MemoryKinds.photo,
      capturedAt: capturedAt,
      capturedTz: timezoneFromOffset(DateTime.now().timeZoneOffset),
      experienceId: state.experience.id.name,
      capture: metadata,
      profileId: profile.id,
      profileVersion: profile.version,
      presetId: state.preset?.id,
      scenario: state.scenario?.id.name,
      lat: location?.latitude,
      lon: location?.longitude,
      locationAccuracyM: location?.accuracyM,
      aspectRatio: settings.aspect,
      assets: <DraftAsset>[
        DraftAsset(
          role: AssetRoles.photoOriginal,
          path: captured.originalPath,
          mime: captured.originalMime,
          width: captured.width,
          height: captured.height,
        ),
        if (captured.renderedPath != null && !captured.renderFailed)
          DraftAsset(
            role: AssetRoles.photoRendered,
            path: captured.renderedPath!,
            mime: 'image/jpeg',
            width: captured.width,
            height: captured.height,
          ),
        if (captured.displayPath != null)
          DraftAsset(
            role: AssetRoles.photoDisplay,
            path: captured.displayPath!,
            mime: 'image/jpeg',
          ),
        if (captured.thumbnailPath != null)
          DraftAsset(
            role: AssetRoles.thumbnail,
            path: captured.thumbnailPath!,
            mime: 'image/jpeg',
          ),
        if (captured.motion != null)
          DraftAsset(
            role: AssetRoles.motionClip,
            path: captured.motion!.path,
            mime: captured.motion!.mime,
            width: captured.motion!.width,
            height: captured.motion!.height,
            durationMs: captured.motion!.durationMs,
          ),
      ],
    );
    final view = await ref.read(memoryRepositoryProvider).commitCapture(draft);
    unawaited(
      dir.delete(recursive: true).then<void>((_) {}, onError: (Object _) {}),
    );
    return view;
  }

  String _extension(cam.PhotoFormat format) => switch (format) {
    cam.PhotoFormat.heif => 'heic',
    cam.PhotoFormat.dng => 'dng',
    cam.PhotoFormat.jpeg => 'jpg',
  };

  Future<cam.LocationFix?> _locationFix() async {
    if (!await ref.read(settingsRepositoryProvider).captureLocation()) {
      return null; // PRIV-001: off by default
    }
    final fix = await ref.read(locationServiceProvider).current();
    return fix == null
        ? null
        : cam.LocationFix(
            latitude: fix.latitude,
            longitude: fix.longitude,
            accuracyM: fix.accuracyM,
            altitudeM: fix.altitudeM,
          );
  }

  // ---- video ---------------------------------------------------------------------------------

  Future<void> startVideo() async {
    final session = _session;
    if (session == null ||
        session.isClosed ||
        state.recording ||
        state.capturing) {
      return;
    }
    try {
      final tempRoot = await ref.read(captureTempDirProvider)();
      final id = ref.read(idGeneratorProvider).newId();
      final dir = await Directory('${tempRoot.path}/$id')
          .create(recursive: true);
      _videoMemoryId = id;
      await session.startVideo(
        cam.VideoRequest(
          outputPath: '${dir.path}/video.mp4',
          audio:
              (state.permissions?.microphoneGranted ?? false) &&
              !(state.settings?.muteAudio ?? false),
        ),
      );
      _set(
        state.copyWith(recording: true, recordingSeconds: 0, clearNotice: true),
      );
      _recordingTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) =>
            _set(state.copyWith(recordingSeconds: state.recordingSeconds + 1)),
      );
    } on cam.CameraException catch (error) {
      _set(
        state.copyWith(
          notice: error.message ?? 'Recording could not start (${error.code}).',
        ),
      );
    }
  }

  String? _videoMemoryId;

  Future<MemoryView?> stopVideo() async {
    final session = _session;
    if (session == null || session.isClosed || !state.recording) {
      return null;
    }
    _recordingTimer?.cancel();
    try {
      final video = await session.stopVideo();
      final id = _videoMemoryId ?? ref.read(idGeneratorProvider).newId();
      final camera = state.camera!;
      final settings = state.settings;
      final profile = ref
          .read(profileRegistryProvider)
          .resolve(settings?.profileId);
      final now = ref.read(clockProvider)();
      final draft = CaptureDraft(
        id: id,
        kind: MemoryKinds.video,
        capturedAt: now,
        capturedTz: timezoneFromOffset(DateTime.now().timeZoneOffset),
        experienceId: state.experience.id.name,
        capture: <String, Object?>{
          'platform': Platform.isIOS ? 'ios' : 'android',
          'appVersion': ref.read(appVersionProvider),
          'cameraId': camera.id,
          'lensKind': camera.lensKind.name,
          'zoomFactor': settings?.zoom ?? 1,
          'widthPx': video.width,
          'heightPx': video.height,
          'durationMs': video.durationMs,
          'hasAudio': video.hasAudio,
          'format': video.mime,
        },
        profileId: profile.id,
        profileVersion: profile.version,
        presetId: state.preset?.id,
        scenario: state.scenario?.id.name,
        assets: <DraftAsset>[
          DraftAsset(
            role: AssetRoles.videoOriginal,
            path: video.path,
            mime: video.mime,
            width: video.width,
            height: video.height,
            durationMs: video.durationMs,
          ),
        ],
      );
      final view = await ref
          .read(memoryRepositoryProvider)
          .commitCapture(draft);
      _set(
        state.copyWith(
          recording: false,
          recordingSeconds: 0,
          lastCapture: view,
        ),
      );
      unawaited(
        ref
            .read(syncCoordinatorProvider)
            .syncOnce()
            .then<void>((_) {}, onError: (Object _) {}),
      );
      return view;
    } on cam.CameraException catch (error) {
      _set(
        state.copyWith(
          recording: false,
          notice:
              error.message ?? 'The video could not be saved (${error.code}).',
        ),
      );
      return null;
    } on Object catch (error) {
      _set(
        state.copyWith(
          recording: false,
          notice: 'The video could not be saved: $error',
        ),
      );
      return null;
    }
  }

  // ---- presets -------------------------------------------------------------------------------

  /// Saves the merged intent as a preset (custom mode, EXP-007).
  Future<void> saveAsPreset(String name) async {
    final layered = state.layered;
    if (layered == null) {
      return;
    }
    final preset = saveAsPresetFromLayers(
      name: name,
      experience: state.experience,
      layered: layered,
      now: ref.read(clockProvider)(),
    );
    await ref
        .read(presetRepositoryProvider)
        .save(
          name: preset.name,
          experienceId: preset.experienceId,
          intent: preset.intent.toJson(),
          profileId: preset.profile?.id,
          profileVersion: preset.profile?.version,
          live: preset.live,
        );
  }
}

Preset saveAsPresetFromLayers({
  required String name,
  required Experience experience,
  required LayeredIntent layered,
  required DateTime now,
}) => saveAsPreset(
  id: 'pending',
  name: name,
  experience: experience,
  layered: layered,
  now: now,
);
