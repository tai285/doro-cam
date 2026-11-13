import 'package:doro_camera/src/messages.g.dart';
import 'package:doro_camera/src/types.dart';

/// Pigeon message <-> domain type mapping. The domain enums deliberately share the names of the message enums,
/// so the mapping goes by name; a contract test (test/mapping_test.dart) fails if the two ever diverge.
T _toDomain<T extends Enum>(List<T> values, Enum message) => values.byName(message.name);

T _toMessage<T extends Enum>(List<T> values, Enum domain) => values.byName(domain.name);

CameraSize _size(SizeMessage m) => CameraSize(m.width, m.height);

SizeMessage _sizeMessage(CameraSize s) => SizeMessage(width: s.width, height: s.height);

IntRange _intRange(IntRangeMessage m) => IntRange(m.min, m.max);

DoubleRange _doubleRange(DoubleRangeMessage m) => DoubleRange(m.min, m.max);

CameraDescriptor descriptorFromMessage(CameraDescriptorMessage m) => CameraDescriptor(
      id: m.id,
      facing: _toDomain(CameraFacing.values, m.facing),
      lensKind: _toDomain(LensKind.values, m.lensKind),
      isLogical: m.isLogical,
      physicalIds: List<String>.unmodifiable(m.physicalIds),
      sensorOrientation: m.sensorOrientation,
      source: _toDomain(CameraSource.values, m.source),
      label: m.label,
      focalLengthMm: m.focalLengthMm,
      focalLength35mmEq: m.focalLength35mmEq,
    );

CameraCapabilities capabilitiesFromMessage(CameraCapabilitiesMessage m) {
  final manual = m.focus.manual;
  final kelvin = m.whiteBalance.kelvin;
  final bias = m.exposureBias;
  return CameraCapabilities(
    cameraId: m.cameraId,
    iso: m.iso == null ? null : _intRange(m.iso!),
    exposureTimeNs: m.exposureTimeNs == null ? null : _intRange(m.exposureTimeNs!),
    exposureBias: bias == null ? null : ExposureBiasCapability(range: _doubleRange(bias.range), step: bias.step),
    apertures: List<double>.unmodifiable(m.apertures),
    focus: FocusCapabilities(
      auto: m.focus.auto,
      continuous: m.focus.continuous,
      tapToFocus: m.focus.tapToFocus,
      manual: manual == null
          ? null
          : ManualFocusCapability(
              minFocusDistanceDiopters: manual.minFocusDistanceDiopters,
              calibration: _toDomain(FocusCalibration.values, manual.calibration),
            ),
    ),
    whiteBalance: WhiteBalanceCapabilities(
      presets: List<WbPreset>.unmodifiable(m.whiteBalance.presets.map((p) => _toDomain(WbPreset.values, p))),
      kelvin: kelvin == null ? null : _intRange(kelvin),
    ),
    zoom: ZoomCapabilities(
      min: m.zoom.min,
      max: m.zoom.max,
      opticalSteps: List<double>.unmodifiable(m.zoom.opticalSteps),
    ),
    flash: List<FlashMode>.unmodifiable(m.flash.map((f) => _toDomain(FlashMode.values, f))),
    torch: m.torch,
    photoFormats: List<PhotoFormat>.unmodifiable(m.photoFormats.map((f) => _toDomain(PhotoFormat.values, f))),
    photoSizes: List<CameraSize>.unmodifiable(m.photoSizes.map(_size)),
    stabilization: StabilizationCapabilities(
      photo: List<StabilizationMode>.unmodifiable(m.stabilization.photo.map((s) => _toDomain(StabilizationMode.values, s))),
      video: List<StabilizationMode>.unmodifiable(m.stabilization.video.map((s) => _toDomain(StabilizationMode.values, s))),
    ),
    video: VideoCapabilities(
      options: List<VideoSizeOption>.unmodifiable(
        m.video.options.map((o) => VideoSizeOption(size: _size(o.size), fps: List<int>.unmodifiable(o.fps))),
      ),
      audio: m.video.audio,
    ),
    hdr: m.hdr,
    live: LiveCapabilities(supported: m.live.supported, maxPreBufferMs: m.live.maxPreBufferMs, audio: m.live.audio),
    hardwareLevel: m.hardwareLevel,
  );
}

SessionConfigMessage configToMessage(SessionConfig c) => SessionConfigMessage(
      cameraId: c.cameraId,
      photoFormat: _toMessage(PhotoFormatMessage.values, c.photoFormat),
      live: c.live,
      audio: c.audio,
      previewSize: c.previewSize == null ? null : _sizeMessage(c.previewSize!),
      photoSize: c.photoSize == null ? null : _sizeMessage(c.photoSize!),
    );

CameraSessionInfo sessionInfoFromMessage(SessionInfoMessage m) => CameraSessionInfo(
      sessionId: m.sessionId,
      textureId: m.textureId,
      cameraId: m.cameraId,
      previewSize: _size(m.previewSize),
      photoSize: _size(m.photoSize),
      photoFormat: _toDomain(PhotoFormat.values, m.photoFormat),
      sensorOrientation: m.sensorOrientation,
      source: _toDomain(CameraSource.values, m.source),
      liveActive: m.liveActive,
      audioActive: m.audioActive,
    );

ResolvedCaptureSettingsMessage settingsToMessage(ResolvedCaptureSettings s) => ResolvedCaptureSettingsMessage(
      iso: s.iso,
      exposureTimeNs: s.exposureTimeNs,
      exposureBiasEv: s.exposureBiasEv,
      aeLock: s.aeLock,
      focusMode: _toMessage(FocusModeMessage.values, s.focusMode),
      focusDistanceDiopters: s.focusDistanceDiopters,
      afLock: s.afLock,
      whiteBalancePreset: s.whiteBalancePreset == null ? null : _toMessage(WbPresetMessage.values, s.whiteBalancePreset!),
      kelvin: s.kelvin,
      zoomRatio: s.zoomRatio,
      flash: _toMessage(FlashModeMessage.values, s.flash),
      torch: s.torch,
      stabilization: s.stabilization == null ? null : _toMessage(StabilizationModeMessage.values, s.stabilization!),
    );

AppliedSettings appliedFromMessage(AppliedSettingsMessage m) => AppliedSettings(
      iso: m.iso,
      exposureTimeNs: m.exposureTimeNs,
      exposureBiasEv: m.exposureBiasEv,
      aperture: m.aperture,
      focalLengthMm: m.focalLengthMm,
      focusDistanceDiopters: m.focusDistanceDiopters,
      focusMode: m.focusMode == null ? null : _toDomain(FocusMode.values, m.focusMode!),
      whiteBalanceMode: m.whiteBalanceMode,
      whiteBalanceGains: m.whiteBalanceGains == null ? null : List<double>.unmodifiable(m.whiteBalanceGains!),
      estimatedKelvin: m.estimatedKelvin,
      aeLocked: m.aeLocked,
      afLocked: m.afLocked,
      zoomRatio: m.zoomRatio,
      flashFired: m.flashFired,
      flash: m.flash == null ? null : _toDomain(FlashMode.values, m.flash!),
      stabilization: m.stabilization == null ? null : _toDomain(StabilizationMode.values, m.stabilization!),
      mismatches: List<String>.unmodifiable(m.mismatches),
    );

CaptureRequestMessage captureRequestToMessage(CaptureRequest r) => CaptureRequestMessage(
      memoryId: r.memoryId,
      outputDir: r.outputDir,
      originalName: r.originalName,
      renderedName: r.renderedName,
      thumbnailName: r.thumbnailName,
      displayName: r.displayName,
      motionName: r.motionName,
      live: r.live,
      preRollMs: r.preRollMs,
      postRollMs: r.postRollMs,
      jpegQuality: r.jpegQuality,
      render: r.render == null
          ? null
          : RenderSpecMessage(
              lut: r.render!.lut,
              lutSize: r.render!.lutSize,
              grain: r.render!.grain,
              vignette: r.render!.vignette,
              aspectRatio: r.render!.aspectRatio,
              profileId: r.render!.profileId,
            ),
      location: r.location == null
          ? null
          : LocationMessage(
              latitude: r.location!.latitude,
              longitude: r.location!.longitude,
              accuracyM: r.location!.accuracyM,
              altitudeM: r.location!.altitudeM,
            ),
      timestampEpochMs: r.timestampEpochMs,
    );

MotionResult motionFromMessage(MotionResultMessage m) => MotionResult(
      path: m.path,
      durationMs: m.durationMs,
      preRollMs: m.preRollMs,
      postRollMs: m.postRollMs,
      keyFrameTimeMs: m.keyFrameTimeMs,
      hasAudio: m.hasAudio,
      width: m.width,
      height: m.height,
      orientationDegrees: m.orientationDegrees,
      mime: m.mime,
    );

CaptureResult captureResultFromMessage(CaptureResultMessage m) => CaptureResult(
      memoryId: m.memoryId,
      originalPath: m.originalPath,
      originalMime: m.originalMime,
      width: m.width,
      height: m.height,
      orientationDegrees: m.orientationDegrees,
      applied: appliedFromMessage(m.applied),
      capturedAtEpochMs: m.capturedAtEpochMs,
      source: _toDomain(CameraSource.values, m.source),
      liveIncluded: m.liveIncluded,
      mirrored: m.mirrored,
      renderFailed: m.renderFailed,
      renderedPath: m.renderedPath,
      thumbnailPath: m.thumbnailPath,
      displayPath: m.displayPath,
      motion: m.motion == null ? null : motionFromMessage(m.motion!),
    );

VideoRequestMessage videoRequestToMessage(VideoRequest r) => VideoRequestMessage(
      outputPath: r.outputPath,
      size: r.size == null ? null : _sizeMessage(r.size!),
      fps: r.fps,
      audio: r.audio,
      stabilization: r.stabilization == null ? null : _toMessage(StabilizationModeMessage.values, r.stabilization!),
    );

VideoResult videoResultFromMessage(VideoResultMessage m) => VideoResult(
      path: m.path,
      durationMs: m.durationMs,
      width: m.width,
      height: m.height,
      hasAudio: m.hasAudio,
      bytes: m.bytes,
      orientationDegrees: m.orientationDegrees,
      mime: m.mime,
    );

CameraPermissions permissionsFromMessage(PermissionsMessage m) => CameraPermissions(
      camera: _toDomain(PermissionStatus.values, m.camera),
      microphone: _toDomain(PermissionStatus.values, m.microphone),
      cameraPermanentlyDenied: m.cameraPermanentlyDenied,
      microphonePermanentlyDenied: m.microphonePermanentlyDenied,
    );

SessionEvent eventFromMessage(SessionEventMessage m) => SessionEvent(
      sessionId: m.sessionId,
      kind: _toDomain(SessionEventKind.values, m.kind),
      state: m.state == null ? null : _toDomain(SessionState.values, m.state!),
      applied: m.applied == null ? null : appliedFromMessage(m.applied!),
      errorCode: m.errorCode,
      errorMessage: m.errorMessage,
      thermal: m.thermal == null ? null : _toDomain(ThermalState.values, m.thermal!),
      orientationDegrees: m.orientationDegrees,
    );
