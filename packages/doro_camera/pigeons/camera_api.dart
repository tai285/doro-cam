// Pigeon definition of the Dart <-> native camera contract (docs/specs/camera.md).
//
// Regenerate after editing:  dart run pigeon --input pigeons/camera_api.dart
// Generated files are committed (the native code compiles against them). Never edit them by hand.
//
// Naming rule: every message class ends in `Message`. The Dart domain types in lib/src/ are
// separate immutable classes (mapped from messages) so the public API does not depend on Pigeon.
//
// Design rules (docs/architecture/camera.md):
//  * Capabilities are ranges and sets, probed at runtime. Absent = null/empty. Nothing is simulated.
//  * Native does hardware work only. Intent resolution, presets, Experiences live in Dart.
//  * Applied settings are what the device REPORTED in its capture result, not what was requested.
//  * Errors cross the bridge as FlutterError(code, message) with the codes in docs/specs/camera.md.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'doro_camera',
    kotlinOut: 'android/src/main/kotlin/com/dorocam/doro_camera/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.dorocam.doro_camera'),
    swiftOut: 'ios/doro_camera/Sources/doro_camera/Messages.g.swift',
  ),
)
// ---------------------------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------------------------

enum CameraFacingMessage { back, front, external }

enum LensKindMessage { ultraWide, wide, tele, front, other }

/// `synthetic` exists only in debug and test builds (ADR-0013).
enum CameraSourceMessage { hardware, synthetic }

enum PhotoFormatMessage { heif, jpeg, dng }

enum WbPresetMessage { auto, daylight, cloudy, shade, tungsten, fluorescent }

enum FlashModeMessage { off, auto, on }

enum FocusModeMessage { continuous, auto, manual }

enum FocusCalibrationMessage { uncalibrated, approximate, calibrated }

enum StabilizationModeMessage { off, standard, optical }

enum PermissionStatusMessage { granted, denied, restricted, notDetermined }

enum SessionStateMessage { configuring, previewing, capturing, recording, suspended, closed }

enum ThermalStateMessage { nominal, fair, serious, critical }

enum SessionEventKindMessage { state, applied, error, thermal, orientation, interrupted, resumed }

// ---------------------------------------------------------------------------------------------
// Capabilities
// ---------------------------------------------------------------------------------------------

class SizeMessage {
  SizeMessage({required this.width, required this.height});
  int width;
  int height;
}

/// An inclusive integer range (ISO values, exposure durations in nanoseconds, Kelvin).
class IntRangeMessage {
  IntRangeMessage({required this.min, required this.max});
  int min;
  int max;
}

class DoubleRangeMessage {
  DoubleRangeMessage({required this.min, required this.max});
  double min;
  double max;
}

class ExposureBiasCapabilityMessage {
  ExposureBiasCapabilityMessage({required this.range, required this.step});

  /// Range in EV stops (already multiplied by [step]).
  DoubleRangeMessage range;

  /// Size of one compensation step in EV.
  double step;
}

class ManualFocusCapabilityMessage {
  ManualFocusCapabilityMessage({
    required this.minFocusDistanceDiopters,
    required this.calibration,
  });

  /// Diopters of the closest focus distance (1 / metres). Manual focus accepts 0 (infinity) .. this.
  double minFocusDistanceDiopters;
  FocusCalibrationMessage calibration;
}

class FocusCapabilitiesMessage {
  FocusCapabilitiesMessage({
    required this.auto,
    required this.continuous,
    required this.tapToFocus,
    this.manual,
  });
  bool auto;
  bool continuous;
  bool tapToFocus;
  ManualFocusCapabilityMessage? manual;
}

class WhiteBalanceCapabilitiesMessage {
  WhiteBalanceCapabilitiesMessage({required this.presets, this.kelvin});
  List<WbPresetMessage> presets;

  /// Non-null only when the device really supports manual colour gains (docs/specs/camera.md).
  IntRangeMessage? kelvin;
}

class ZoomCapabilitiesMessage {
  ZoomCapabilitiesMessage({
    required this.min,
    required this.max,
    required this.opticalSteps,
  });
  double min;
  double max;

  /// Zoom ratios that correspond to real optical lenses (for example 1.0, 2.0). May be just [1.0].
  List<double> opticalSteps;
}

class StabilizationCapabilitiesMessage {
  StabilizationCapabilitiesMessage({required this.photo, required this.video});
  List<StabilizationModeMessage> photo;
  List<StabilizationModeMessage> video;
}

class VideoSizeOptionMessage {
  VideoSizeOptionMessage({required this.size, required this.fps});
  SizeMessage size;
  List<int> fps;
}

class VideoCapabilitiesMessage {
  VideoCapabilitiesMessage({required this.options, required this.audio});
  List<VideoSizeOptionMessage> options;
  bool audio;
}

class LiveCapabilitiesMessage {
  LiveCapabilitiesMessage({
    required this.supported,
    required this.maxPreBufferMs,
    required this.audio,
  });
  bool supported;
  int maxPreBufferMs;
  bool audio;
}

class CameraDescriptorMessage {
  CameraDescriptorMessage({
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
  String id;
  CameraFacingMessage facing;
  LensKindMessage lensKind;
  bool isLogical;
  List<String> physicalIds;
  int sensorOrientation;
  CameraSourceMessage source;

  /// Short human label such as "Back camera" or "Back camera (wide)".
  String label;
  double? focalLengthMm;
  double? focalLength35mmEq;
}

class CameraCapabilitiesMessage {
  CameraCapabilitiesMessage({
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
  String cameraId;

  /// Null = no manual ISO.
  IntRangeMessage? iso;

  /// Nanoseconds. Null = no manual shutter.
  IntRangeMessage? exposureTimeNs;
  ExposureBiasCapabilityMessage? exposureBias;

  /// Usually length 1, which means display only (CAM-013).
  List<double> apertures;
  FocusCapabilitiesMessage focus;
  WhiteBalanceCapabilitiesMessage whiteBalance;
  ZoomCapabilitiesMessage zoom;
  List<FlashModeMessage> flash;
  bool torch;
  List<PhotoFormatMessage> photoFormats;
  List<SizeMessage> photoSizes;
  StabilizationCapabilitiesMessage stabilization;
  VideoCapabilitiesMessage video;
  bool hdr;
  LiveCapabilitiesMessage live;

  /// Android: LEGACY | LIMITED | FULL | LEVEL_3 | EXTERNAL. iOS: `n/a`.
  String hardwareLevel;
}

// ---------------------------------------------------------------------------------------------
// Session, settings, capture
// ---------------------------------------------------------------------------------------------

class SessionConfigMessage {
  SessionConfigMessage({
    required this.cameraId,
    required this.photoFormat,
    required this.live,
    required this.audio,
    this.previewSize,
    this.photoSize,
  });
  String cameraId;
  PhotoFormatMessage photoFormat;

  /// Keep a rolling pre-shutter buffer so a capture can include motion (MOT-009).
  bool live;

  /// Record audio for motion and video. Requires microphone permission, else motion is silent (MOT-003).
  bool audio;
  SizeMessage? previewSize;

  /// Null = the largest size the format supports (CAM-003).
  SizeMessage? photoSize;
}

class SessionInfoMessage {
  SessionInfoMessage({
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
  int sessionId;

  /// Flutter `Texture` id of the live preview.
  int textureId;
  String cameraId;

  /// Size of the preview frames as delivered (before rotating for display).
  SizeMessage previewSize;
  SizeMessage photoSize;

  /// The format actually used, which can differ from the request (typed fallback, docs/specs/camera.md).
  PhotoFormatMessage photoFormat;
  int sensorOrientation;
  CameraSourceMessage source;
  bool liveActive;
  bool audioActive;
}

/// Already clamped to the capabilities by the Dart resolver. Native applies it as given.
class ResolvedCaptureSettingsMessage {
  ResolvedCaptureSettingsMessage({
    required this.aeLock,
    required this.focusMode,
    required this.afLock,
    required this.zoomRatio,
    required this.flash,
    required this.torch,
    this.iso,
    this.exposureTimeNs,
    this.exposureBiasEv,
    this.focusDistanceDiopters,
    this.whiteBalancePreset,
    this.kelvin,
    this.stabilization,
  });

  /// Manual ISO; both [iso] and [exposureTimeNs] null = auto exposure.
  int? iso;

  /// Manual shutter in nanoseconds.
  int? exposureTimeNs;

  /// Exposure compensation in EV. Ignored by native when exposure is fully manual.
  double? exposureBiasEv;
  bool aeLock;
  FocusModeMessage focusMode;

  /// Only for [FocusModeMessage.manual].
  double? focusDistanceDiopters;
  bool afLock;

  /// Null = auto white balance.
  WbPresetMessage? whiteBalancePreset;

  /// Takes precedence over [whiteBalancePreset].
  int? kelvin;
  double zoomRatio;
  FlashModeMessage flash;
  bool torch;
  StabilizationModeMessage? stabilization;
}

/// What the device reported it actually used (CAM-050). Every value comes from the capture result.
class AppliedSettingsMessage {
  AppliedSettingsMessage({
    required this.aeLocked,
    required this.afLocked,
    required this.zoomRatio,
    required this.mismatches,
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
    this.flashFired,
    this.flash,
    this.stabilization,
  });
  int? iso;
  int? exposureTimeNs;
  double? exposureBiasEv;
  double? aperture;
  double? focalLengthMm;
  double? focusDistanceDiopters;
  FocusModeMessage? focusMode;

  /// `auto`, or `manual`, or a preset name.
  String? whiteBalanceMode;

  /// Red, green-even, green-odd, blue gains when the device reported them.
  List<double>? whiteBalanceGains;

  /// Estimated colour temperature derived from the gains. Never a hardware-reported value.
  int? estimatedKelvin;
  bool aeLocked;
  bool afLocked;
  double zoomRatio;
  bool? flashFired;
  FlashModeMessage? flash;
  StabilizationModeMessage? stabilization;

  /// Names of requested fields the device did not honour (for example `iso`), so Dart can downgrade
  /// the capability after a persistent mismatch (docs/specs/camera.md acceptance criteria).
  List<String> mismatches;
}

class LocationMessage {
  LocationMessage({required this.latitude, required this.longitude, this.accuracyM, this.altitudeM});
  double latitude;
  double longitude;
  double? accuracyM;
  double? altitudeM;
}

/// Look applied when rendering the `rendered` JPEG (ADR-0004). Native does the pixel work.
class RenderSpecMessage {
  RenderSpecMessage({
    required this.grain,
    required this.vignette,
    this.lut,
    this.lutSize,
    this.aspectRatio,
    this.profileId,
  });

  /// Packed RGB bytes of a cube LUT (`lutSize`^3 entries, R fastest, 3 bytes per entry). Null = identity.
  Uint8List? lut;
  int? lutSize;

  /// 0..1 film grain strength.
  double grain;

  /// 0..1 vignette strength.
  double vignette;

  /// `W:H` such as `3:2`. The ORIGINAL is never cropped (CAM-044); only the rendition is.
  String? aspectRatio;
  String? profileId;
}

class CaptureRequestMessage {
  CaptureRequestMessage({
    required this.memoryId,
    required this.outputDir,
    required this.originalName,
    required this.renderedName,
    required this.thumbnailName,
    required this.displayName,
    required this.live,
    required this.preRollMs,
    required this.postRollMs,
    required this.jpegQuality,
    this.motionName,
    this.render,
    this.location,
    this.timestampEpochMs,
  });
  String memoryId;

  /// Directory that exists and is writable. Native writes temp files then renames (NFR-002).
  String outputDir;

  /// File names (without directory). Dart owns naming.
  String originalName;
  String renderedName;
  String thumbnailName;
  String displayName;
  String? motionName;

  /// Include the pre/post-roll clip. Ignored (with `liveIncluded=false` in the result) when LIVE is off.
  bool live;

  /// Motion window before and after the shutter. Native may deliver more pre-roll (it must start on a
  /// key frame) but never less than the buffer holds.
  int preRollMs;
  int postRollMs;
  int jpegQuality;
  RenderSpecMessage? render;

  /// Written into EXIF only when the app passes it (PRIV-001).
  LocationMessage? location;

  /// Overrides the shutter timestamp; null = now.
  int? timestampEpochMs;
}

class MotionResultMessage {
  MotionResultMessage({
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
  String path;
  int durationMs;
  int preRollMs;
  int postRollMs;

  /// Time of the shutter inside the clip.
  int keyFrameTimeMs;
  bool hasAudio;
  int width;
  int height;
  int orientationDegrees;
  String mime;
}

class CaptureResultMessage {
  CaptureResultMessage({
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
  String memoryId;
  String originalPath;
  String originalMime;
  int width;
  int height;

  /// Clockwise degrees to rotate the stored pixels for upright display (EXIF orientation).
  int orientationDegrees;
  AppliedSettingsMessage applied;
  int capturedAtEpochMs;
  CameraSourceMessage source;
  bool liveIncluded;

  /// Front camera photos are NOT mirrored in the file; this is true only when the preview was.
  bool mirrored;

  /// True when the original was saved but rendition steps failed (retry later; original is safe).
  bool renderFailed;
  String? renderedPath;
  String? thumbnailPath;
  String? displayPath;
  MotionResultMessage? motion;
}

class VideoRequestMessage {
  VideoRequestMessage({
    required this.outputPath,
    required this.audio,
    this.size,
    this.fps,
    this.stabilization,
  });
  String outputPath;
  SizeMessage? size;
  int? fps;
  bool audio;
  StabilizationModeMessage? stabilization;
}

class VideoResultMessage {
  VideoResultMessage({
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
    required this.bytes,
    required this.orientationDegrees,
    required this.mime,
  });
  String path;
  int durationMs;
  int width;
  int height;
  bool hasAudio;
  int bytes;
  int orientationDegrees;
  String mime;
}

// ---------------------------------------------------------------------------------------------
// Permissions and events
// ---------------------------------------------------------------------------------------------

class PermissionsMessage {
  PermissionsMessage({
    required this.camera,
    required this.microphone,
    required this.cameraPermanentlyDenied,
    required this.microphonePermanentlyDenied,
  });
  PermissionStatusMessage camera;
  PermissionStatusMessage microphone;

  /// True when Android will no longer show the system dialog: send the user to settings (CAM-052).
  bool cameraPermanentlyDenied;
  bool microphonePermanentlyDenied;
}

class SessionEventMessage {
  SessionEventMessage({
    required this.sessionId,
    required this.kind,
    this.state,
    this.applied,
    this.errorCode,
    this.errorMessage,
    this.thermal,
    this.orientationDegrees,
  });
  int sessionId;
  SessionEventKindMessage kind;
  SessionStateMessage? state;
  AppliedSettingsMessage? applied;
  String? errorCode;
  String? errorMessage;
  ThermalStateMessage? thermal;

  /// Device orientation from the sensor, 0/90/180/270 (CAM edge case: capture follows the sensor).
  int? orientationDegrees;
}

// ---------------------------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------------------------

@HostApi()
abstract class CameraHostApi {
  PingResultMessage ping(String message);

  PermissionsMessage checkPermissions();

  @async
  PermissionsMessage requestPermissions(bool camera, bool microphone);

  void openAppSettings();

  List<CameraDescriptorMessage> listCameras();

  CameraCapabilitiesMessage getCapabilities(String cameraId);

  @async
  SessionInfoMessage openSession(SessionConfigMessage config);

  /// Idempotent.
  @async
  void closeSession(int sessionId);

  /// Applies settings to the running preview and returns what the device reported.
  @async
  AppliedSettingsMessage applySettings(
    int sessionId,
    ResolvedCaptureSettingsMessage settings,
  );

  /// Tap-to-focus and tap-to-meter at a normalised preview point (0..1, 0..1).
  @async
  void focusAt(int sessionId, double x, double y);

  void setLive(int sessionId, bool enabled);

  @async
  CaptureResultMessage capture(int sessionId, CaptureRequestMessage request);

  @async
  void startVideo(int sessionId, VideoRequestMessage request);

  @async
  VideoResultMessage stopVideo(int sessionId);

  /// App backgrounded or another interruption: stop preview and LIVE buffering (NFR-012).
  @async
  void suspendSession(int sessionId);

  @async
  void resumeSession(int sessionId);
}

@FlutterApi()
abstract class CameraEventsApi {
  void onSessionEvent(SessionEventMessage event);
}

/// Answer to a `ping`: proves the bridge works in both directions and reports what the native side is.
class PingResultMessage {
  PingResultMessage({
    required this.echo,
    required this.platform,
    required this.osVersion,
    required this.syntheticCameraCompiledIn,
  });

  /// The message that was sent, returned unchanged.
  String echo;

  /// `android` or `ios`.
  String platform;

  /// Operating system version, for example `15` or `18.6`.
  String osVersion;

  /// True only in debug and test builds that contain the synthetic test camera (ADR-0013).
  /// Release builds must always report false.
  bool syntheticCameraCompiledIn;
}
