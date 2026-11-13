import 'dart:typed_data';

import 'package:doro_camera/doro_camera.dart';
import 'package:doro_camera/src/mapping.dart';
import 'package:doro_camera/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

CameraCapabilitiesMessage fullCapsMessage() => CameraCapabilitiesMessage(
      cameraId: '0',
      iso: IntRangeMessage(min: 50, max: 3200),
      exposureTimeNs: IntRangeMessage(min: 100000, max: 1000000000),
      exposureBias: ExposureBiasCapabilityMessage(range: DoubleRangeMessage(min: -4, max: 4), step: 1 / 3),
      apertures: <double>[1.8],
      focus: FocusCapabilitiesMessage(
        auto: true,
        continuous: true,
        tapToFocus: true,
        manual: ManualFocusCapabilityMessage(
          minFocusDistanceDiopters: 10,
          calibration: FocusCalibrationMessage.calibrated,
        ),
      ),
      whiteBalance: WhiteBalanceCapabilitiesMessage(
        presets: <WbPresetMessage>[WbPresetMessage.auto, WbPresetMessage.tungsten],
        kelvin: IntRangeMessage(min: 2000, max: 10000),
      ),
      zoom: ZoomCapabilitiesMessage(min: 1, max: 8, opticalSteps: <double>[1, 2]),
      flash: <FlashModeMessage>[FlashModeMessage.off, FlashModeMessage.on],
      torch: true,
      photoFormats: <PhotoFormatMessage>[PhotoFormatMessage.heif, PhotoFormatMessage.jpeg],
      photoSizes: <SizeMessage>[SizeMessage(width: 4000, height: 3000)],
      stabilization: StabilizationCapabilitiesMessage(
        photo: <StabilizationModeMessage>[StabilizationModeMessage.off],
        video: <StabilizationModeMessage>[StabilizationModeMessage.off, StabilizationModeMessage.standard],
      ),
      video: VideoCapabilitiesMessage(
        options: <VideoSizeOptionMessage>[VideoSizeOptionMessage(size: SizeMessage(width: 1920, height: 1080), fps: <int>[24, 30])],
        audio: true,
      ),
      hdr: true,
      live: LiveCapabilitiesMessage(supported: true, maxPreBufferMs: 3000, audio: true),
      hardwareLevel: 'FULL',
    );

CameraCapabilitiesMessage bareCapsMessage() => CameraCapabilitiesMessage(
      cameraId: '1',
      apertures: <double>[],
      focus: FocusCapabilitiesMessage(auto: false, continuous: false, tapToFocus: false),
      whiteBalance: WhiteBalanceCapabilitiesMessage(presets: <WbPresetMessage>[WbPresetMessage.auto]),
      zoom: ZoomCapabilitiesMessage(min: 1, max: 1, opticalSteps: <double>[1]),
      flash: <FlashModeMessage>[],
      torch: false,
      photoFormats: <PhotoFormatMessage>[PhotoFormatMessage.jpeg],
      photoSizes: <SizeMessage>[],
      stabilization: StabilizationCapabilitiesMessage(photo: <StabilizationModeMessage>[], video: <StabilizationModeMessage>[]),
      video: VideoCapabilitiesMessage(options: <VideoSizeOptionMessage>[], audio: false),
      hdr: false,
      live: LiveCapabilitiesMessage(supported: false, maxPreBufferMs: 0, audio: false),
      hardwareLevel: 'LIMITED',
    );

AppliedSettingsMessage appliedMessage({List<String> mismatches = const <String>[]}) => AppliedSettingsMessage(
      iso: 400,
      exposureTimeNs: 8000000,
      exposureBiasEv: 0.33,
      aperture: 1.8,
      focalLengthMm: 4.2,
      focusDistanceDiopters: 2.5,
      focusMode: FocusModeMessage.manual,
      whiteBalanceMode: 'manual',
      whiteBalanceGains: <double>[1.5, 1, 1, 2.1],
      estimatedKelvin: 3200,
      aeLocked: true,
      afLocked: true,
      zoomRatio: 2,
      flashFired: false,
      flash: FlashModeMessage.auto,
      stabilization: StabilizationModeMessage.optical,
      mismatches: mismatches,
    );

void main() {
  // Contract: domain enums and message enums stay in step, because mapping goes by name.
  group('enum contract', () {
    void same(List<Enum> domain, List<Enum> message, String name) {
      expect(domain.map((e) => e.name).toList(), message.map((e) => e.name).toList(), reason: name);
    }

    test('every domain enum has exactly the values of its Pigeon message enum', () {
      same(CameraFacing.values, CameraFacingMessage.values, 'facing');
      same(LensKind.values, LensKindMessage.values, 'lens');
      same(CameraSource.values, CameraSourceMessage.values, 'source');
      same(PhotoFormat.values, PhotoFormatMessage.values, 'photoFormat');
      same(WbPreset.values, WbPresetMessage.values, 'wb');
      same(FlashMode.values, FlashModeMessage.values, 'flash');
      same(FocusMode.values, FocusModeMessage.values, 'focus');
      same(FocusCalibration.values, FocusCalibrationMessage.values, 'calibration');
      same(StabilizationMode.values, StabilizationModeMessage.values, 'stabilization');
      same(PermissionStatus.values, PermissionStatusMessage.values, 'permission');
      same(SessionState.values, SessionStateMessage.values, 'state');
      same(ThermalState.values, ThermalStateMessage.values, 'thermal');
      same(SessionEventKind.values, SessionEventKindMessage.values, 'eventKind');
    });
  });

  group('capabilities', () {
    test('[CAM-004] maps every range, set and flag of a fully capable camera', () {
      final caps = capabilitiesFromMessage(fullCapsMessage());
      expect(caps.cameraId, '0');
      expect(caps.iso, const IntRange(50, 3200));
      expect(caps.exposureTimeNs, const IntRange(100000, 1000000000));
      expect(caps.exposureBias, const ExposureBiasCapability(range: DoubleRange(-4, 4), step: 1 / 3));
      expect(caps.apertures, <double>[1.8]);
      expect(caps.focus.manual, const ManualFocusCapability(minFocusDistanceDiopters: 10, calibration: FocusCalibration.calibrated));
      expect(caps.focus.auto && caps.focus.continuous && caps.focus.tapToFocus, isTrue);
      expect(caps.whiteBalance, const WhiteBalanceCapabilities(presets: <WbPreset>[WbPreset.auto, WbPreset.tungsten], kelvin: IntRange(2000, 10000)));
      expect(caps.zoom, const ZoomCapabilities(min: 1, max: 8, opticalSteps: <double>[1, 2]));
      expect(caps.flash, <FlashMode>[FlashMode.off, FlashMode.on]);
      expect(caps.photoFormats, <PhotoFormat>[PhotoFormat.heif, PhotoFormat.jpeg]);
      expect(caps.photoSizes, <CameraSize>[const CameraSize(4000, 3000)]);
      expect(caps.stabilization.video, <StabilizationMode>[StabilizationMode.off, StabilizationMode.standard]);
      expect(caps.video.options.single.fps, <int>[24, 30]);
      expect(caps.video.supported, isTrue);
      expect(caps.hdr, isTrue);
      expect(caps.live, const LiveCapabilities(supported: true, maxPreBufferMs: 3000, audio: true));
      expect(caps.hardwareLevel, 'FULL');
    });

    test('[CAM-005] absent capabilities stay absent and the derived getters say so', () {
      final caps = capabilitiesFromMessage(bareCapsMessage());
      expect(caps.iso, isNull);
      expect(caps.exposureTimeNs, isNull);
      expect(caps.exposureBias, isNull);
      expect(caps.focus.manual, isNull);
      expect(caps.whiteBalance.kelvin, isNull);
      expect(caps.hasManualIso, isFalse);
      expect(caps.hasManualShutter, isFalse);
      expect(caps.hasManualExposure, isFalse);
      expect(caps.hasExposureBias, isFalse);
      expect(caps.hasManualFocus, isFalse);
      expect(caps.hasKelvin, isFalse);
      expect(caps.hasFlash, isFalse);
      expect(caps.apertureControllable, isFalse);
      expect(caps.hasDigitalZoom, isFalse);
      expect(caps.video.supported, isFalse);
    });

    test('[CAM-013] aperture is controllable only when the hardware reports several values; digital zoom is detected', () {
      final caps = capabilitiesFromMessage(fullCapsMessage());
      expect(caps.apertureControllable, isFalse);
      expect(caps.hasDigitalZoom, isTrue); // max 8 beyond the last optical step 2
      final multi = capabilitiesFromMessage(fullCapsMessage()..apertures = <double>[1.8, 2.8]);
      expect(multi.apertureControllable, isTrue);
      expect(capabilitiesFromMessage(fullCapsMessage()..zoom = ZoomCapabilitiesMessage(min: 1, max: 2, opticalSteps: <double>[1, 2])).hasDigitalZoom, isFalse);
      expect(capabilitiesFromMessage(fullCapsMessage()..zoom = ZoomCapabilitiesMessage(min: 1, max: 3, opticalSteps: <double>[])).hasDigitalZoom, isTrue);
    });

    test('mapped lists are unmodifiable so callers cannot corrupt a cached capability', () {
      final caps = capabilitiesFromMessage(fullCapsMessage());
      expect(() => caps.flash.add(FlashMode.auto), throwsUnsupportedError);
      expect(() => caps.apertures.add(2), throwsUnsupportedError);
    });

    test('value equality covers capabilities, so a cache can detect a change', () {
      expect(capabilitiesFromMessage(fullCapsMessage()), capabilitiesFromMessage(fullCapsMessage()));
      expect(capabilitiesFromMessage(fullCapsMessage()), isNot(capabilitiesFromMessage(bareCapsMessage())));
      expect(capabilitiesFromMessage(fullCapsMessage()).hashCode, capabilitiesFromMessage(fullCapsMessage()).hashCode);
      final original = capabilitiesFromMessage(fullCapsMessage());
      expect(original.copyWith(iso: () => null).hasManualIso, isFalse);
      expect(original.copyWith(exposureTimeNs: () => null).hasManualShutter, isFalse);
      expect(original.copyWith(exposureBias: () => null).hasExposureBias, isFalse);
      expect(original.copyWith(torch: false, flash: const <FlashMode>[]).hasFlash, isFalse);
      expect(original.copyWith(live: const LiveCapabilities(supported: false, maxPreBufferMs: 0, audio: false)).live.supported, isFalse);
      expect(original.copyWith(focus: const FocusCapabilities(auto: false, continuous: false, tapToFocus: false)).focus.auto, isFalse);
      expect(original.copyWith(whiteBalance: const WhiteBalanceCapabilities(presets: <WbPreset>[])).whiteBalance.presets, isEmpty);
    });

    test('range helpers clamp and test membership', () {
      expect(const IntRange(10, 20).clamp(5), 10);
      expect(const IntRange(10, 20).clamp(25), 20);
      expect(const IntRange(10, 20).clamp(15), 15);
      expect(const IntRange(10, 20).contains(20), isTrue);
      expect(const IntRange(10, 20).contains(21), isFalse);
      expect(const DoubleRange(-1, 1).clamp(3), 1);
      expect(const DoubleRange(-1, 1).clamp(-3), -1);
      expect(const DoubleRange(-1, 1).clamp(0.5), 0.5);
      expect(const DoubleRange(-1, 1).contains(1.1), isFalse);
      expect(const CameraSize(4, 3).aspectRatio, closeTo(1.333, 0.001));
      expect(const CameraSize(4, 3).pixels, 12);
      expect(const CameraSize(4, 3).toString(), '4x3');
      expect(const IntRange(1, 2).toString(), '1..2');
    });
  });

  group('descriptors, sessions, settings', () {
    test('[CAM-004] a descriptor keeps facing, lens, source and focal lengths', () {
      final d = descriptorFromMessage(
        CameraDescriptorMessage(
          id: 'synthetic:wide',
          facing: CameraFacingMessage.front,
          lensKind: LensKindMessage.ultraWide,
          isLogical: true,
          physicalIds: <String>['2', '3'],
          sensorOrientation: 270,
          source: CameraSourceMessage.synthetic,
          label: 'Test camera',
          focalLengthMm: 2.1,
          focalLength35mmEq: 14,
        ),
      );
      expect(d.facing, CameraFacing.front);
      expect(d.lensKind, LensKind.ultraWide);
      expect(d.isSynthetic, isTrue);
      expect(d.physicalIds, <String>['2', '3']);
      expect(d.sensorOrientation, 270);
      expect(d.focalLength35mmEq, 14);
      expect(d.hashCode, isA<int>());
      expect(
        d,
        descriptorFromMessage(
          CameraDescriptorMessage(
            id: 'synthetic:wide',
            facing: CameraFacingMessage.front,
            lensKind: LensKindMessage.ultraWide,
            isLogical: true,
            physicalIds: <String>['2', '3'],
            sensorOrientation: 270,
            source: CameraSourceMessage.synthetic,
            label: 'Test camera',
            focalLengthMm: 2.1,
            focalLength35mmEq: 14,
          ),
        ),
      );
    });

    test('a session config round-trips to its message', () {
      final m = configToMessage(const SessionConfig(cameraId: 'c', photoFormat: PhotoFormat.heif, live: true, audio: false, previewSize: CameraSize(1280, 720), photoSize: CameraSize(4000, 3000)));
      expect(m.cameraId, 'c');
      expect(m.photoFormat, PhotoFormatMessage.heif);
      expect(m.live, isTrue);
      expect(m.audio, isFalse);
      expect(m.previewSize!.width, 1280);
      expect(m.photoSize!.height, 3000);
      final minimal = configToMessage(const SessionConfig(cameraId: 'c'));
      expect(minimal.previewSize, isNull);
      expect(minimal.photoSize, isNull);
      expect(minimal.photoFormat, PhotoFormatMessage.jpeg);
      expect(minimal.audio, isTrue);
    });

    test('session info maps every field', () {
      final info = sessionInfoFromMessage(
        SessionInfoMessage(
          sessionId: 7,
          textureId: 42,
          cameraId: 'c',
          previewSize: SizeMessage(width: 1280, height: 720),
          photoSize: SizeMessage(width: 4000, height: 3000),
          photoFormat: PhotoFormatMessage.jpeg,
          sensorOrientation: 90,
          source: CameraSourceMessage.hardware,
          liveActive: true,
          audioActive: false,
        ),
      );
      expect(info.sessionId, 7);
      expect(info.textureId, 42);
      expect(info.previewSize, const CameraSize(1280, 720));
      expect(info.liveActive, isTrue);
      expect(info.audioActive, isFalse);
      final copy = info.copyWith(liveActive: false, audioActive: true);
      expect(copy.liveActive, isFalse);
      expect(copy.audioActive, isTrue);
      expect(copy.textureId, 42);
      expect(info.copyWith().liveActive, isTrue);
    });

    test('[CAM-050] resolved settings map to the wire, with optional fields left null', () {
      final m = settingsToMessage(
        const ResolvedCaptureSettings(
          iso: 400,
          exposureTimeNs: 8000000,
          exposureBiasEv: 0.5,
          aeLock: true,
          focusMode: FocusMode.manual,
          focusDistanceDiopters: 2,
          afLock: true,
          whiteBalancePreset: WbPreset.shade,
          kelvin: 4500,
          zoomRatio: 2.5,
          flash: FlashMode.on,
          torch: true,
          stabilization: StabilizationMode.optical,
        ),
      );
      expect(m.iso, 400);
      expect(m.exposureTimeNs, 8000000);
      expect(m.focusMode, FocusModeMessage.manual);
      expect(m.whiteBalancePreset, WbPresetMessage.shade);
      expect(m.kelvin, 4500);
      expect(m.flash, FlashModeMessage.on);
      expect(m.stabilization, StabilizationModeMessage.optical);
      final auto = settingsToMessage(const ResolvedCaptureSettings());
      expect(auto.iso, isNull);
      expect(auto.whiteBalancePreset, isNull);
      expect(auto.stabilization, isNull);
      expect(auto.focusMode, FocusModeMessage.continuous);
      expect(auto.zoomRatio, 1.0);
    });

    test('resolved settings have value equality', () {
      expect(const ResolvedCaptureSettings(iso: 100), const ResolvedCaptureSettings(iso: 100));
      expect(const ResolvedCaptureSettings(iso: 100), isNot(const ResolvedCaptureSettings(iso: 200)));
      expect(const ResolvedCaptureSettings(iso: 100).hashCode, const ResolvedCaptureSettings(iso: 100).hashCode);
    });

    test('[CAM-050] applied settings keep every reported value and the mismatch list', () {
      final a = appliedFromMessage(appliedMessage(mismatches: <String>['iso']));
      expect(a.iso, 400);
      expect(a.exposureTimeNs, 8000000);
      expect(a.exposureBiasEv, 0.33);
      expect(a.aperture, 1.8);
      expect(a.focalLengthMm, 4.2);
      expect(a.focusDistanceDiopters, 2.5);
      expect(a.focusMode, FocusMode.manual);
      expect(a.whiteBalanceMode, 'manual');
      expect(a.whiteBalanceGains, <double>[1.5, 1, 1, 2.1]);
      expect(a.estimatedKelvin, 3200);
      expect(a.aeLocked && a.afLocked, isTrue);
      expect(a.zoomRatio, 2);
      expect(a.flashFired, isFalse);
      expect(a.flash, FlashMode.auto);
      expect(a.stabilization, StabilizationMode.optical);
      expect(a.mismatches, <String>['iso']);
      expect(a.honouredRequest, isFalse);
      expect(appliedFromMessage(appliedMessage()).honouredRequest, isTrue);
      final sparse = appliedFromMessage(AppliedSettingsMessage(aeLocked: false, afLocked: false, zoomRatio: 1, mismatches: <String>[]));
      expect(sparse.iso, isNull);
      expect(sparse.focusMode, isNull);
      expect(sparse.whiteBalanceGains, isNull);
      expect(sparse.flash, isNull);
      expect(sparse.stabilization, isNull);
    });
  });

  group('capture, video, permissions, events', () {
    CaptureResultMessage resultMessage({bool withMotion = false, bool withRenditions = true}) => CaptureResultMessage(
          memoryId: 'm1',
          originalPath: '/o.jpg',
          originalMime: 'image/jpeg',
          width: 4000,
          height: 3000,
          orientationDegrees: 90,
          applied: appliedMessage(),
          capturedAtEpochMs: 1700000000000,
          source: CameraSourceMessage.synthetic,
          liveIncluded: withMotion,
          mirrored: false,
          renderFailed: !withRenditions,
          renderedPath: withRenditions ? '/r.jpg' : null,
          thumbnailPath: withRenditions ? '/t.jpg' : null,
          displayPath: withRenditions ? '/d.jpg' : null,
          motion: withMotion
              ? MotionResultMessage(
                  path: '/m.mp4',
                  durationMs: 3000,
                  preRollMs: 1500,
                  postRollMs: 1500,
                  keyFrameTimeMs: 1500,
                  hasAudio: true,
                  width: 1280,
                  height: 720,
                  orientationDegrees: 90,
                  mime: 'video/mp4',
                )
              : null,
        );

    test('[CAM-050] a capture request maps to the wire including the render spec and location', () {
      final lut = Uint8List.fromList(<int>[1, 2, 3]);
      final m = captureRequestToMessage(
        CaptureRequest(
          memoryId: 'm1',
          outputDir: '/dir',
          originalName: 'o.jpg',
          renderedName: 'r.jpg',
          thumbnailName: 't.jpg',
          displayName: 'd.jpg',
          motionName: 'm.mp4',
          live: true,
          preRollMs: 1000,
          postRollMs: 2000,
          jpegQuality: 90,
          render: RenderSpec(lut: lut, lutSize: 2, grain: 0.3, vignette: 0.2, aspectRatio: '3:2', profileId: 'warm-film'),
          location: const LocationFix(latitude: 3.1, longitude: 101.6, accuracyM: 5, altitudeM: 40),
          timestampEpochMs: 99,
        ),
      );
      expect(m.memoryId, 'm1');
      expect(m.outputDir, '/dir');
      expect(m.motionName, 'm.mp4');
      expect(m.live, isTrue);
      expect(m.preRollMs, 1000);
      expect(m.postRollMs, 2000);
      expect(m.jpegQuality, 90);
      expect(m.render!.lut, lut);
      expect(m.render!.lutSize, 2);
      expect(m.render!.aspectRatio, '3:2');
      expect(m.render!.profileId, 'warm-film');
      expect(m.location!.latitude, 3.1);
      expect(m.location!.altitudeM, 40);
      expect(m.timestampEpochMs, 99);
      final plain = captureRequestToMessage(const CaptureRequest(memoryId: 'm', outputDir: '/d', originalName: 'o', renderedName: 'r', thumbnailName: 't', displayName: 'd'));
      expect(plain.render, isNull);
      expect(plain.location, isNull);
      expect(plain.live, isFalse);
      expect(plain.preRollMs, 1500);
      expect(plain.jpegQuality, 95);
    });

    test('[MOT-002] a capture result with motion maps the clip facts', () {
      final r = captureResultFromMessage(resultMessage(withMotion: true));
      expect(r.memoryId, 'm1');
      expect(r.orientationDegrees, 90);
      expect(r.source, CameraSource.synthetic);
      expect(r.liveIncluded, isTrue);
      expect(r.renderedPath, '/r.jpg');
      expect(r.motion!.path, '/m.mp4');
      expect(r.motion!.keyFrameTimeMs, 1500);
      expect(r.motion!.hasAudio, isTrue);
      expect(r.motion!.width, 1280);
      expect(r.applied.iso, 400);
    });

    test('a failed rendition is surfaced and the original is still reported', () {
      final r = captureResultFromMessage(resultMessage(withRenditions: false));
      expect(r.renderFailed, isTrue);
      expect(r.originalPath, '/o.jpg');
      expect(r.renderedPath, isNull);
      expect(r.thumbnailPath, isNull);
      expect(r.displayPath, isNull);
      expect(r.motion, isNull);
    });

    test('[VID-001] video request and result map', () {
      final m = videoRequestToMessage(const VideoRequest(outputPath: '/v.mp4', size: CameraSize(1920, 1080), fps: 30, audio: false, stabilization: StabilizationMode.standard));
      expect(m.outputPath, '/v.mp4');
      expect(m.size!.width, 1920);
      expect(m.fps, 30);
      expect(m.audio, isFalse);
      expect(m.stabilization, StabilizationModeMessage.standard);
      final bare = videoRequestToMessage(const VideoRequest(outputPath: '/v.mp4'));
      expect(bare.size, isNull);
      expect(bare.fps, isNull);
      expect(bare.audio, isTrue);
      expect(bare.stabilization, isNull);
      final r = videoResultFromMessage(VideoResultMessage(path: '/v.mp4', durationMs: 5000, width: 1920, height: 1080, hasAudio: true, bytes: 123, orientationDegrees: 90, mime: 'video/mp4'));
      expect(r.durationMs, 5000);
      expect(r.bytes, 123);
      expect(r.orientationDegrees, 90);
    });

    test('[CAM-052] permissions map with the permanently-denied flags and helper getters', () {
      final p = permissionsFromMessage(
        PermissionsMessage(camera: PermissionStatusMessage.denied, microphone: PermissionStatusMessage.notDetermined, cameraPermanentlyDenied: true, microphonePermanentlyDenied: false),
      );
      expect(p.camera, PermissionStatus.denied);
      expect(p.microphone, PermissionStatus.notDetermined);
      expect(p.cameraGranted, isFalse);
      expect(p.microphoneGranted, isFalse);
      expect(p.cameraNeedsSettings, isTrue);
      expect(p.cameraRestricted, isFalse);
      final granted = permissionsFromMessage(PermissionsMessage(camera: PermissionStatusMessage.granted, microphone: PermissionStatusMessage.granted, cameraPermanentlyDenied: false, microphonePermanentlyDenied: false));
      expect(granted.cameraGranted && granted.microphoneGranted, isTrue);
      expect(granted.cameraNeedsSettings, isFalse);
      const restricted = CameraPermissions(camera: PermissionStatus.restricted, microphone: PermissionStatus.granted);
      expect(restricted.cameraRestricted, isTrue);
      expect(restricted.cameraNeedsSettings, isFalse);
      expect(granted, permissionsFromMessage(PermissionsMessage(camera: PermissionStatusMessage.granted, microphone: PermissionStatusMessage.granted, cameraPermanentlyDenied: false, microphonePermanentlyDenied: false)));
      expect(granted.hashCode, isA<int>());
    });

    test('[CAM-053] events map state, applied settings, errors, thermal and orientation', () {
      final state = eventFromMessage(SessionEventMessage(sessionId: 3, kind: SessionEventKindMessage.state, state: SessionStateMessage.recording));
      expect(state.sessionId, 3);
      expect(state.kind, SessionEventKind.state);
      expect(state.state, SessionState.recording);
      expect(state.applied, isNull);
      final applied = eventFromMessage(SessionEventMessage(sessionId: 3, kind: SessionEventKindMessage.applied, applied: appliedMessage()));
      expect(applied.applied!.iso, 400);
      final error = eventFromMessage(SessionEventMessage(sessionId: 3, kind: SessionEventKindMessage.error, errorCode: 'camera_in_use', errorMessage: 'busy'));
      expect(error.errorCode, 'camera_in_use');
      expect(error.errorMessage, 'busy');
      final thermal = eventFromMessage(SessionEventMessage(sessionId: 3, kind: SessionEventKindMessage.thermal, thermal: ThermalStateMessage.serious));
      expect(thermal.thermal, ThermalState.serious);
      final orientation = eventFromMessage(SessionEventMessage(sessionId: 3, kind: SessionEventKindMessage.orientation, orientationDegrees: 270));
      expect(orientation.orientationDegrees, 270);
    });
  });
}
