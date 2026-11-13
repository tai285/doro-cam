import 'package:flutter/foundation.dart';

/// Domain types of the camera plugin (docs/specs/camera.md). They are immutable Dart classes that the
/// platform implementation maps from the Pigeon messages, so the public API never exposes Pigeon types.

enum CameraFacing { back, front, external }

enum LensKind { ultraWide, wide, tele, front, other }

/// `synthetic` exists only in debug and test builds (ADR-0013). The UI shows a "TEST CAMERA" badge for it.
enum CameraSource { hardware, synthetic }

enum PhotoFormat { heif, jpeg, dng }

enum WbPreset { auto, daylight, cloudy, shade, tungsten, fluorescent }

enum FlashMode { off, auto, on }

enum FocusMode { continuous, auto, manual }

enum FocusCalibration { uncalibrated, approximate, calibrated }

enum StabilizationMode { off, standard, optical }

enum PermissionStatus { granted, denied, restricted, notDetermined }

enum SessionState { configuring, previewing, capturing, recording, suspended, closed }

enum ThermalState { nominal, fair, serious, critical }

enum SessionEventKind { state, applied, error, thermal, orientation, interrupted, resumed }

@immutable
class CameraSize {
  const CameraSize(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => width / height;

  int get pixels => width * height;

  @override
  bool operator ==(Object other) => other is CameraSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

@immutable
class IntRange {
  const IntRange(this.min, this.max);

  final int min;
  final int max;

  bool contains(int value) => value >= min && value <= max;

  int clamp(int value) => value < min ? min : (value > max ? max : value);

  @override
  bool operator ==(Object other) => other is IntRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => '$min..$max';
}

@immutable
class DoubleRange {
  const DoubleRange(this.min, this.max);

  final double min;
  final double max;

  bool contains(double value) => value >= min && value <= max;

  double clamp(double value) => value < min ? min : (value > max ? max : value);

  @override
  bool operator ==(Object other) => other is DoubleRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => '$min..$max';
}

@immutable
class ExposureBiasCapability {
  const ExposureBiasCapability({required this.range, required this.step});

  /// Range in EV stops.
  final DoubleRange range;

  /// Size of one compensation step in EV.
  final double step;

  @override
  bool operator ==(Object other) => other is ExposureBiasCapability && other.range == range && other.step == step;

  @override
  int get hashCode => Object.hash(range, step);
}

@immutable
class ManualFocusCapability {
  const ManualFocusCapability({required this.minFocusDistanceDiopters, required this.calibration});

  /// Manual focus accepts 0 (infinity) up to this many diopters (the closest focus distance).
  final double minFocusDistanceDiopters;

  /// Distances may be labelled in metres only when this is [FocusCalibration.calibrated] or
  /// [FocusCalibration.approximate] (CAM-021).
  final FocusCalibration calibration;

  @override
  bool operator ==(Object other) =>
      other is ManualFocusCapability &&
      other.minFocusDistanceDiopters == minFocusDistanceDiopters &&
      other.calibration == calibration;

  @override
  int get hashCode => Object.hash(minFocusDistanceDiopters, calibration);
}

@immutable
class FocusCapabilities {
  const FocusCapabilities({
    required this.auto,
    required this.continuous,
    required this.tapToFocus,
    this.manual,
  });

  final bool auto;
  final bool continuous;
  final bool tapToFocus;
  final ManualFocusCapability? manual;

  @override
  bool operator ==(Object other) =>
      other is FocusCapabilities &&
      other.auto == auto &&
      other.continuous == continuous &&
      other.tapToFocus == tapToFocus &&
      other.manual == manual;

  @override
  int get hashCode => Object.hash(auto, continuous, tapToFocus, manual);
}

@immutable
class WhiteBalanceCapabilities {
  const WhiteBalanceCapabilities({required this.presets, this.kelvin});

  final List<WbPreset> presets;

  /// Non-null only when the device really supports manual colour gains.
  final IntRange? kelvin;

  @override
  bool operator ==(Object other) => other is WhiteBalanceCapabilities && listEquals(other.presets, presets) && other.kelvin == kelvin;

  @override
  int get hashCode => Object.hash(Object.hashAll(presets), kelvin);
}

@immutable
class ZoomCapabilities {
  const ZoomCapabilities({required this.min, required this.max, required this.opticalSteps});

  final double min;
  final double max;

  /// Zoom ratios that correspond to real optical lenses. Anything beyond is digital zoom and must be labelled.
  final List<double> opticalSteps;

  @override
  bool operator ==(Object other) =>
      other is ZoomCapabilities && other.min == min && other.max == max && listEquals(other.opticalSteps, opticalSteps);

  @override
  int get hashCode => Object.hash(min, max, Object.hashAll(opticalSteps));
}

@immutable
class StabilizationCapabilities {
  const StabilizationCapabilities({required this.photo, required this.video});

  final List<StabilizationMode> photo;
  final List<StabilizationMode> video;

  @override
  bool operator ==(Object other) =>
      other is StabilizationCapabilities && listEquals(other.photo, photo) && listEquals(other.video, video);

  @override
  int get hashCode => Object.hash(Object.hashAll(photo), Object.hashAll(video));
}

@immutable
class VideoSizeOption {
  const VideoSizeOption({required this.size, required this.fps});

  final CameraSize size;
  final List<int> fps;

  @override
  bool operator ==(Object other) => other is VideoSizeOption && other.size == size && listEquals(other.fps, fps);

  @override
  int get hashCode => Object.hash(size, Object.hashAll(fps));
}

@immutable
class VideoCapabilities {
  const VideoCapabilities({required this.options, required this.audio});

  final List<VideoSizeOption> options;
  final bool audio;

  bool get supported => options.isNotEmpty;

  @override
  bool operator ==(Object other) => other is VideoCapabilities && listEquals(other.options, options) && other.audio == audio;

  @override
  int get hashCode => Object.hash(Object.hashAll(options), audio);
}

@immutable
class LiveCapabilities {
  const LiveCapabilities({required this.supported, required this.maxPreBufferMs, required this.audio});

  final bool supported;
  final int maxPreBufferMs;
  final bool audio;

  @override
  bool operator ==(Object other) =>
      other is LiveCapabilities && other.supported == supported && other.maxPreBufferMs == maxPreBufferMs && other.audio == audio;

  @override
  int get hashCode => Object.hash(supported, maxPreBufferMs, audio);
}

/// One camera usable by the app. `id` is opaque: pass it back to [CameraCapabilities] and [SessionConfig].
@immutable
class CameraDescriptor {
  const CameraDescriptor({
    required this.id,
    required this.facing,
    required this.lensKind,
    required this.isLogical,
    required this.physicalIds,
    required this.sensorOrientation,
    required this.source,
    required this.label,
    this.focalLengthMm,
    this.focalLength35mmEq,
  });

  final String id;
  final CameraFacing facing;
  final LensKind lensKind;
  final bool isLogical;
  final List<String> physicalIds;
  final int sensorOrientation;
  final CameraSource source;
  final String label;
  final double? focalLengthMm;
  final double? focalLength35mmEq;

  bool get isSynthetic => source == CameraSource.synthetic;

  @override
  bool operator ==(Object other) =>
      other is CameraDescriptor &&
      other.id == id &&
      other.facing == facing &&
      other.lensKind == lensKind &&
      other.isLogical == isLogical &&
      listEquals(other.physicalIds, physicalIds) &&
      other.sensorOrientation == sensorOrientation &&
      other.source == source &&
      other.label == label &&
      other.focalLengthMm == focalLengthMm &&
      other.focalLength35mmEq == focalLength35mmEq;

  @override
  int get hashCode => Object.hash(id, facing, lensKind, isLogical, Object.hashAll(physicalIds), sensorOrientation, source, label);
}

/// What a camera can really do, probed from the platform. Capabilities are ranges and sets; absent means
/// the control must not be offered (CAM-005). Booleans are derived getters.
@immutable
class CameraCapabilities {
  const CameraCapabilities({
    required this.cameraId,
    required this.apertures,
    required this.focus,
    required this.whiteBalance,
    required this.zoom,
    required this.flash,
    required this.torch,
    required this.photoFormats,
    required this.photoSizes,
    required this.stabilization,
    required this.video,
    required this.hdr,
    required this.live,
    required this.hardwareLevel,
    this.iso,
    this.exposureTimeNs,
    this.exposureBias,
  });

  final String cameraId;
  final IntRange? iso;

  /// Shutter duration range in nanoseconds.
  final IntRange? exposureTimeNs;
  final ExposureBiasCapability? exposureBias;

  /// Usually a single value: display only (CAM-013).
  final List<double> apertures;
  final FocusCapabilities focus;
  final WhiteBalanceCapabilities whiteBalance;
  final ZoomCapabilities zoom;
  final List<FlashMode> flash;
  final bool torch;
  final List<PhotoFormat> photoFormats;
  final List<CameraSize> photoSizes;
  final StabilizationCapabilities stabilization;
  final VideoCapabilities video;
  final bool hdr;
  final LiveCapabilities live;
  final String hardwareLevel;

  bool get hasManualIso => iso != null;

  bool get hasManualShutter => exposureTimeNs != null;

  bool get hasManualExposure => hasManualIso && hasManualShutter;

  bool get hasExposureBias => exposureBias != null;

  bool get hasManualFocus => focus.manual != null;

  bool get hasKelvin => whiteBalance.kelvin != null;

  bool get hasFlash => flash.isNotEmpty;

  /// True only when the hardware reports more than one aperture (CAM-013).
  bool get apertureControllable => apertures.length > 1;

  bool get hasDigitalZoom => zoom.max > (zoom.opticalSteps.isEmpty ? 1.0 : zoom.opticalSteps.last);

  CameraCapabilities copyWith({
    IntRange? Function()? iso,
    IntRange? Function()? exposureTimeNs,
    ExposureBiasCapability? Function()? exposureBias,
    FocusCapabilities? focus,
    WhiteBalanceCapabilities? whiteBalance,
    List<FlashMode>? flash,
    bool? torch,
    LiveCapabilities? live,
  }) {
    return CameraCapabilities(
      cameraId: cameraId,
      iso: iso == null ? this.iso : iso(),
      exposureTimeNs: exposureTimeNs == null ? this.exposureTimeNs : exposureTimeNs(),
      exposureBias: exposureBias == null ? this.exposureBias : exposureBias(),
      apertures: apertures,
      focus: focus ?? this.focus,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      zoom: zoom,
      flash: flash ?? this.flash,
      torch: torch ?? this.torch,
      photoFormats: photoFormats,
      photoSizes: photoSizes,
      stabilization: stabilization,
      video: video,
      hdr: hdr,
      live: live ?? this.live,
      hardwareLevel: hardwareLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CameraCapabilities &&
      other.cameraId == cameraId &&
      other.iso == iso &&
      other.exposureTimeNs == exposureTimeNs &&
      other.exposureBias == exposureBias &&
      listEquals(other.apertures, apertures) &&
      other.focus == focus &&
      other.whiteBalance == whiteBalance &&
      other.zoom == zoom &&
      listEquals(other.flash, flash) &&
      other.torch == torch &&
      listEquals(other.photoFormats, photoFormats) &&
      listEquals(other.photoSizes, photoSizes) &&
      other.stabilization == stabilization &&
      other.video == video &&
      other.hdr == hdr &&
      other.live == live &&
      other.hardwareLevel == hardwareLevel;

  @override
  int get hashCode => Object.hash(cameraId, iso, exposureTimeNs, exposureBias, focus, whiteBalance, zoom, torch, hdr, live, hardwareLevel);
}

// ---------------------------------------------------------------------------------------------
// Session, settings, capture
// ---------------------------------------------------------------------------------------------

@immutable
class SessionConfig {
  const SessionConfig({
    required this.cameraId,
    this.photoFormat = PhotoFormat.jpeg,
    this.live = false,
    this.audio = true,
    this.previewSize,
    this.photoSize,
  });

  final String cameraId;
  final PhotoFormat photoFormat;

  /// Keep a rolling pre-shutter buffer so a capture can include motion (MOT-009).
  final bool live;

  /// Record audio for motion and video. Without microphone permission motion is silent (MOT-003).
  final bool audio;
  final CameraSize? previewSize;

  /// Null = the largest the format supports (CAM-003).
  final CameraSize? photoSize;
}

@immutable
class CameraSessionInfo {
  const CameraSessionInfo({
    required this.sessionId,
    required this.textureId,
    required this.cameraId,
    required this.previewSize,
    required this.photoSize,
    required this.photoFormat,
    required this.sensorOrientation,
    required this.source,
    required this.liveActive,
    required this.audioActive,
  });

  final int sessionId;

  /// Flutter `Texture` id of the live preview.
  final int textureId;
  final String cameraId;

  /// Size of the preview frames as delivered, before rotating for display.
  final CameraSize previewSize;
  final CameraSize photoSize;

  /// The format actually used, which can differ from the request.
  final PhotoFormat photoFormat;
  final int sensorOrientation;
  final CameraSource source;

  /// False when LIVE was requested but could not start (unsupported stream combination, thermal state).
  final bool liveActive;
  final bool audioActive;

  CameraSessionInfo copyWith({bool? liveActive, bool? audioActive}) => CameraSessionInfo(
        sessionId: sessionId,
        textureId: textureId,
        cameraId: cameraId,
        previewSize: previewSize,
        photoSize: photoSize,
        photoFormat: photoFormat,
        sensorOrientation: sensorOrientation,
        source: source,
        liveActive: liveActive ?? this.liveActive,
        audioActive: audioActive ?? this.audioActive,
      );
}

/// Already clamped to the capabilities by the resolver. Native applies it as given.
@immutable
class ResolvedCaptureSettings {
  const ResolvedCaptureSettings({
    this.iso,
    this.exposureTimeNs,
    this.exposureBiasEv,
    this.aeLock = false,
    this.focusMode = FocusMode.continuous,
    this.focusDistanceDiopters,
    this.afLock = false,
    this.whiteBalancePreset,
    this.kelvin,
    this.zoomRatio = 1.0,
    this.flash = FlashMode.off,
    this.torch = false,
    this.stabilization,
  });

  /// Manual ISO. Both [iso] and [exposureTimeNs] null = automatic exposure.
  final int? iso;

  /// Manual shutter in nanoseconds.
  final int? exposureTimeNs;

  /// Exposure compensation in EV; ignored by native in fully manual exposure.
  final double? exposureBiasEv;
  final bool aeLock;
  final FocusMode focusMode;
  final double? focusDistanceDiopters;
  final bool afLock;

  /// Null = automatic white balance.
  final WbPreset? whiteBalancePreset;

  /// Takes precedence over [whiteBalancePreset].
  final int? kelvin;
  final double zoomRatio;
  final FlashMode flash;
  final bool torch;
  final StabilizationMode? stabilization;

  @override
  bool operator ==(Object other) =>
      other is ResolvedCaptureSettings &&
      other.iso == iso &&
      other.exposureTimeNs == exposureTimeNs &&
      other.exposureBiasEv == exposureBiasEv &&
      other.aeLock == aeLock &&
      other.focusMode == focusMode &&
      other.focusDistanceDiopters == focusDistanceDiopters &&
      other.afLock == afLock &&
      other.whiteBalancePreset == whiteBalancePreset &&
      other.kelvin == kelvin &&
      other.zoomRatio == zoomRatio &&
      other.flash == flash &&
      other.torch == torch &&
      other.stabilization == stabilization;

  @override
  int get hashCode => Object.hash(iso, exposureTimeNs, exposureBiasEv, aeLock, focusMode, focusDistanceDiopters, afLock,
      whiteBalancePreset, kelvin, zoomRatio, flash, torch, stabilization);
}

/// What the device REPORTED it used (CAM-050): values come from the capture result, not from the request.
@immutable
class AppliedSettings {
  const AppliedSettings({
    this.iso,
    this.exposureTimeNs,
    this.exposureBiasEv,
    this.aperture,
    this.focalLengthMm,
    this.focusDistanceDiopters,
    this.focusMode,
    this.whiteBalanceMode,
    this.whiteBalanceGains,
    this.estimatedKelvin,
    this.aeLocked = false,
    this.afLocked = false,
    this.zoomRatio = 1.0,
    this.flashFired,
    this.flash,
    this.stabilization,
    this.mismatches = const <String>[],
  });

  final int? iso;
  final int? exposureTimeNs;
  final double? exposureBiasEv;
  final double? aperture;
  final double? focalLengthMm;
  final double? focusDistanceDiopters;
  final FocusMode? focusMode;

  /// `auto`, `manual` or a preset name.
  final String? whiteBalanceMode;
  final List<double>? whiteBalanceGains;

  /// An estimate derived from the colour gains. Never a hardware-reported value.
  final int? estimatedKelvin;
  final bool aeLocked;
  final bool afLocked;
  final double zoomRatio;
  final bool? flashFired;
  final FlashMode? flash;
  final StabilizationMode? stabilization;

  /// Requested fields the device did not honour (for example `iso`, `exposureTime`, `focusDistance`).
  final List<String> mismatches;

  bool get honouredRequest => mismatches.isEmpty;
}

@immutable
class LocationFix {
  const LocationFix({required this.latitude, required this.longitude, this.accuracyM, this.altitudeM});

  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? altitudeM;
}

/// Look applied when rendering the `rendered` JPEG (ADR-0004).
@immutable
class RenderSpec {
  const RenderSpec({
    this.lut,
    this.lutSize,
    this.grain = 0,
    this.vignette = 0,
    this.aspectRatio,
    this.profileId,
  });

  /// Packed RGB bytes of a cube LUT (`lutSize`^3 entries, R fastest, 3 bytes each). Null = identity.
  final Uint8List? lut;
  final int? lutSize;
  final double grain;
  final double vignette;

  /// `W:H`; only the rendition is cropped, the original never is (CAM-044).
  final String? aspectRatio;
  final String? profileId;
}

@immutable
class CaptureRequest {
  const CaptureRequest({
    required this.memoryId,
    required this.outputDir,
    required this.originalName,
    required this.renderedName,
    required this.thumbnailName,
    required this.displayName,
    this.motionName,
    this.live = false,
    this.preRollMs = 1500,
    this.postRollMs = 1500,
    this.jpegQuality = 95,
    this.render,
    this.location,
    this.timestampEpochMs,
  });

  final String memoryId;

  /// Existing, writable directory. Native writes temp files and renames them (NFR-002).
  final String outputDir;
  final String originalName;
  final String renderedName;
  final String thumbnailName;
  final String displayName;
  final String? motionName;
  final bool live;
  final int preRollMs;
  final int postRollMs;
  final int jpegQuality;
  final RenderSpec? render;

  /// Written into the original's EXIF only when the app passes it (PRIV-001).
  final LocationFix? location;
  final int? timestampEpochMs;
}

@immutable
class MotionResult {
  const MotionResult({
    required this.path,
    required this.durationMs,
    required this.preRollMs,
    required this.postRollMs,
    required this.keyFrameTimeMs,
    required this.hasAudio,
    required this.width,
    required this.height,
    required this.orientationDegrees,
    required this.mime,
  });

  final String path;
  final int durationMs;
  final int preRollMs;
  final int postRollMs;

  /// Time of the shutter inside the clip.
  final int keyFrameTimeMs;
  final bool hasAudio;
  final int width;
  final int height;
  final int orientationDegrees;
  final String mime;
}

@immutable
class CaptureResult {
  const CaptureResult({
    required this.memoryId,
    required this.originalPath,
    required this.originalMime,
    required this.width,
    required this.height,
    required this.orientationDegrees,
    required this.applied,
    required this.capturedAtEpochMs,
    required this.source,
    required this.liveIncluded,
    required this.mirrored,
    required this.renderFailed,
    this.renderedPath,
    this.thumbnailPath,
    this.displayPath,
    this.motion,
  });

  final String memoryId;
  final String originalPath;
  final String originalMime;
  final int width;
  final int height;

  /// Clockwise degrees to rotate the stored pixels for upright display.
  final int orientationDegrees;
  final AppliedSettings applied;
  final int capturedAtEpochMs;
  final CameraSource source;
  final bool liveIncluded;
  final bool mirrored;

  /// The original is saved but renditions failed: retry rendering later (the original is never lost).
  final bool renderFailed;
  final String? renderedPath;
  final String? thumbnailPath;
  final String? displayPath;
  final MotionResult? motion;
}

@immutable
class VideoRequest {
  const VideoRequest({required this.outputPath, this.size, this.fps, this.audio = true, this.stabilization});

  final String outputPath;
  final CameraSize? size;
  final int? fps;
  final bool audio;
  final StabilizationMode? stabilization;
}

@immutable
class VideoResult {
  const VideoResult({
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
    required this.bytes,
    required this.orientationDegrees,
    required this.mime,
  });

  final String path;
  final int durationMs;
  final int width;
  final int height;
  final bool hasAudio;
  final int bytes;
  final int orientationDegrees;
  final String mime;
}

@immutable
class CameraPermissions {
  const CameraPermissions({
    required this.camera,
    required this.microphone,
    this.cameraPermanentlyDenied = false,
    this.microphonePermanentlyDenied = false,
  });

  final PermissionStatus camera;
  final PermissionStatus microphone;

  /// True when the system dialog will not show again: send the user to settings (CAM-052).
  final bool cameraPermanentlyDenied;
  final bool microphonePermanentlyDenied;

  bool get cameraGranted => camera == PermissionStatus.granted;

  bool get microphoneGranted => microphone == PermissionStatus.granted;

  /// Whether the UI should offer "Open settings" instead of asking again.
  bool get cameraNeedsSettings => cameraPermanentlyDenied && !cameraGranted;

  /// Restricted by a device policy: explain, and do not offer settings.
  bool get cameraRestricted => camera == PermissionStatus.restricted;

  @override
  bool operator ==(Object other) =>
      other is CameraPermissions &&
      other.camera == camera &&
      other.microphone == microphone &&
      other.cameraPermanentlyDenied == cameraPermanentlyDenied &&
      other.microphonePermanentlyDenied == microphonePermanentlyDenied;

  @override
  int get hashCode => Object.hash(camera, microphone, cameraPermanentlyDenied, microphonePermanentlyDenied);
}

@immutable
class SessionEvent {
  const SessionEvent({
    required this.sessionId,
    required this.kind,
    this.state,
    this.applied,
    this.errorCode,
    this.errorMessage,
    this.thermal,
    this.orientationDegrees,
  });

  final int sessionId;
  final SessionEventKind kind;
  final SessionState? state;
  final AppliedSettings? applied;
  final String? errorCode;
  final String? errorMessage;
  final ThermalState? thermal;

  /// Device orientation from the sensor: 0/90/180/270.
  final int? orientationDegrees;
}
