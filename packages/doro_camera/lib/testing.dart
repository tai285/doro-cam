/// Test doubles for code that depends on the camera plugin. Import only from tests.
library;

import 'dart:async';

import 'package:doro_camera/doro_camera.dart';

/// A scriptable [CameraPlatform] for widget and unit tests: no hardware, no channels.
///
/// It records every call and answers with whatever the test configured, including failures. Capabilities are
/// whatever the test provides, so every permutation (no manual ISO, fixed focus, no flash, ...) can be exercised.
class FakeCameraPlatform implements CameraPlatform {
  FakeCameraPlatform({
    this.pingResult = const PingResult(
      echo: '',
      platform: 'fake',
      osVersion: '0',
      syntheticCameraCompiledIn: false,
    ),
    this.pingError,
    this.permissions = const CameraPermissions(camera: PermissionStatus.granted, microphone: PermissionStatus.granted),
    List<CameraDescriptor>? cameras,
    Map<String, CameraCapabilities>? capabilities,
  })  : cameras = cameras ?? <CameraDescriptor>[defaultDescriptor],
        capabilitiesById = capabilities ?? <String, CameraCapabilities>{defaultDescriptor.id: fullCapabilities(defaultDescriptor.id)};

  /// A back camera that supports every control, for tests that just need "a camera".
  static const CameraDescriptor defaultDescriptor = CameraDescriptor(
    id: 'fake:back',
    facing: CameraFacing.back,
    lensKind: LensKind.wide,
    isLogical: false,
    physicalIds: <String>[],
    sensorOrientation: 90,
    source: CameraSource.hardware,
    label: 'Back camera',
    focalLengthMm: 4.2,
    focalLength35mmEq: 26,
  );

  /// Capabilities with every control present.
  static CameraCapabilities fullCapabilities(String cameraId) => CameraCapabilities(
        cameraId: cameraId,
        iso: const IntRange(50, 3200),
        exposureTimeNs: const IntRange(100000, 1000000000),
        exposureBias: const ExposureBiasCapability(range: DoubleRange(-4, 4), step: 1 / 3),
        apertures: const <double>[1.8],
        focus: const FocusCapabilities(
          auto: true,
          continuous: true,
          tapToFocus: true,
          manual: ManualFocusCapability(minFocusDistanceDiopters: 10, calibration: FocusCalibration.approximate),
        ),
        whiteBalance: const WhiteBalanceCapabilities(
          presets: <WbPreset>[WbPreset.auto, WbPreset.daylight, WbPreset.cloudy, WbPreset.shade, WbPreset.tungsten, WbPreset.fluorescent],
          kelvin: IntRange(2000, 10000),
        ),
        zoom: const ZoomCapabilities(min: 1, max: 8, opticalSteps: <double>[1]),
        flash: const <FlashMode>[FlashMode.off, FlashMode.auto, FlashMode.on],
        torch: true,
        photoFormats: const <PhotoFormat>[PhotoFormat.jpeg],
        photoSizes: const <CameraSize>[CameraSize(4000, 3000), CameraSize(1920, 1080)],
        stabilization: const StabilizationCapabilities(
          photo: <StabilizationMode>[StabilizationMode.off],
          video: <StabilizationMode>[StabilizationMode.off],
        ),
        video: const VideoCapabilities(
          options: <VideoSizeOption>[VideoSizeOption(size: CameraSize(1920, 1080), fps: <int>[30])],
          audio: true,
        ),
        hdr: false,
        live: const LiveCapabilities(supported: true, maxPreBufferMs: 3000, audio: true),
        hardwareLevel: 'FULL',
      );

  /// Returned by [ping] with its `echo` replaced by the message that was sent.
  PingResult pingResult;

  /// When set, [ping] throws it instead of answering.
  Object? pingError;

  CameraPermissions permissions;

  /// Permissions after a call to [requestPermissions]; null = unchanged.
  CameraPermissions? permissionsAfterRequest;

  List<CameraDescriptor> cameras;
  Map<String, CameraCapabilities> capabilitiesById;

  /// When set, every session-level call throws it (for example `CameraException('camera_in_use')`).
  Object? error;

  /// Result of the next [capture]; defaults to a result derived from the request.
  CaptureResult? nextCaptureResult;

  /// Settings reported by [applySettings]; defaults to echoing the request.
  AppliedSettings Function(ResolvedCaptureSettings settings)? appliedBuilder;

  final List<String> pingCalls = <String>[];
  final List<String> calls = <String>[];
  final List<SessionConfig> opened = <SessionConfig>[];
  final List<ResolvedCaptureSettings> appliedSettings = <ResolvedCaptureSettings>[];
  final List<CaptureRequest> captures = <CaptureRequest>[];
  final List<(double, double)> focusPoints = <(double, double)>[];
  final List<VideoRequest> videos = <VideoRequest>[];
  final Set<int> openSessions = <int>{};
  int _nextSession = 1;
  final StreamController<SessionEvent> _events = StreamController<SessionEvent>.broadcast();

  /// Pushes an event to listeners, as native would.
  void emit(SessionEvent event) => _events.add(event);

  void _check(String call) {
    calls.add(call);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<PingResult> ping(String message) async {
    pingCalls.add(message);
    final failure = pingError;
    if (failure != null) {
      throw failure;
    }
    return PingResult(
      echo: message,
      platform: pingResult.platform,
      osVersion: pingResult.osVersion,
      syntheticCameraCompiledIn: pingResult.syntheticCameraCompiledIn,
    );
  }

  @override
  Future<CameraPermissions> checkPermissions() async {
    _check('checkPermissions');
    return permissions;
  }

  @override
  Future<CameraPermissions> requestPermissions({bool camera = true, bool microphone = true}) async {
    _check('requestPermissions');
    permissions = permissionsAfterRequest ?? permissions;
    return permissions;
  }

  @override
  Future<void> openAppSettings() async => _check('openAppSettings');

  @override
  Future<List<CameraDescriptor>> listCameras() async {
    _check('listCameras');
    return cameras;
  }

  @override
  Future<CameraCapabilities> capabilities(String cameraId) async {
    _check('capabilities:$cameraId');
    final found = capabilitiesById[cameraId];
    if (found == null) {
      throw CameraException('unsupported_configuration', 'Unknown camera $cameraId');
    }
    return found;
  }

  @override
  Future<CameraSessionInfo> openSession(SessionConfig config) async {
    _check('openSession');
    if (!permissions.cameraGranted) {
      throw CameraException(permissions.cameraRestricted ? 'permission_restricted' : 'permission_denied', 'Camera permission was not granted');
    }
    opened.add(config);
    final id = _nextSession++;
    openSessions.add(id);
    return CameraSessionInfo(
      sessionId: id,
      textureId: 1000 + id,
      cameraId: config.cameraId,
      previewSize: const CameraSize(1280, 720),
      photoSize: config.photoSize ?? const CameraSize(4000, 3000),
      photoFormat: config.photoFormat,
      sensorOrientation: 90,
      source: config.cameraId.startsWith('synthetic') ? CameraSource.synthetic : CameraSource.hardware,
      liveActive: config.live,
      audioActive: config.live && config.audio && permissions.microphoneGranted,
    );
  }

  @override
  Future<void> closeSession(int sessionId) async {
    calls.add('closeSession');
    openSessions.remove(sessionId);
  }

  @override
  Future<AppliedSettings> applySettings(int sessionId, ResolvedCaptureSettings settings) async {
    _check('applySettings');
    appliedSettings.add(settings);
    return appliedBuilder?.call(settings) ?? _echo(settings);
  }

  static AppliedSettings _echo(ResolvedCaptureSettings s) => AppliedSettings(
        iso: s.iso,
        exposureTimeNs: s.exposureTimeNs,
        exposureBiasEv: s.exposureBiasEv,
        focusMode: s.focusMode,
        focusDistanceDiopters: s.focusDistanceDiopters,
        zoomRatio: s.zoomRatio,
        flash: s.flash,
        aeLocked: s.aeLock,
        afLocked: s.afLock,
      );

  @override
  Future<void> focusAt(int sessionId, double x, double y) async {
    _check('focusAt');
    focusPoints.add((x, y));
  }

  @override
  Future<void> setLive(int sessionId, {required bool enabled}) async => _check('setLive:$enabled');

  @override
  Future<CaptureResult> capture(int sessionId, CaptureRequest request) async {
    _check('capture');
    captures.add(request);
    return nextCaptureResult ??
        CaptureResult(
          memoryId: request.memoryId,
          originalPath: '${request.outputDir}/${request.originalName}',
          originalMime: 'image/jpeg',
          width: 4000,
          height: 3000,
          orientationDegrees: 0,
          applied: appliedSettings.isEmpty ? const AppliedSettings() : _echo(appliedSettings.last),
          capturedAtEpochMs: request.timestampEpochMs ?? 0,
          source: CameraSource.hardware,
          liveIncluded: request.live,
          mirrored: false,
          renderFailed: false,
          renderedPath: '${request.outputDir}/${request.renderedName}',
          thumbnailPath: '${request.outputDir}/${request.thumbnailName}',
          displayPath: '${request.outputDir}/${request.displayName}',
          motion: request.live
              ? MotionResult(
                  path: '${request.outputDir}/${request.motionName ?? 'motion.mp4'}',
                  durationMs: request.preRollMs + request.postRollMs,
                  preRollMs: request.preRollMs,
                  postRollMs: request.postRollMs,
                  keyFrameTimeMs: request.preRollMs,
                  hasAudio: true,
                  width: 1280,
                  height: 720,
                  orientationDegrees: 0,
                  mime: 'video/mp4',
                )
              : null,
        );
  }

  @override
  Future<void> startVideo(int sessionId, VideoRequest request) async {
    _check('startVideo');
    videos.add(request);
  }

  @override
  Future<VideoResult> stopVideo(int sessionId) async {
    _check('stopVideo');
    final request = videos.isEmpty ? null : videos.last;
    return VideoResult(
      path: request?.outputPath ?? '',
      durationMs: 1000,
      width: request?.size?.width ?? 1920,
      height: request?.size?.height ?? 1080,
      hasAudio: request?.audio ?? true,
      bytes: 1024,
      orientationDegrees: 0,
      mime: 'video/mp4',
    );
  }

  @override
  Future<void> suspendSession(int sessionId) async => _check('suspendSession');

  @override
  Future<void> resumeSession(int sessionId) async => _check('resumeSession');

  @override
  Stream<SessionEvent> get sessionEvents => _events.stream;
}
