import 'package:doro_camera/src/pigeon_camera_platform.dart';
import 'package:doro_camera/src/ping_result.dart';
import 'package:doro_camera/src/types.dart';

/// The seam between the app and the native camera (docs/architecture/camera.md).
///
/// The real implementation talks to Kotlin/Swift through Pigeon. App tests replace it with
/// `FakeCameraPlatform` from `package:doro_camera/testing.dart`.
abstract class CameraPlatform {
  /// The platform in use. Defaults to the Pigeon-backed implementation; tests assign a fake.
  static CameraPlatform instance = PigeonCameraPlatform();

  /// Sends [message] to the native side and returns what comes back.
  Future<PingResult> ping(String message);

  Future<CameraPermissions> checkPermissions();

  /// Shows the system permission dialogs for whatever is not granted and resolves with the new status.
  Future<CameraPermissions> requestPermissions({bool camera = true, bool microphone = true});

  /// Opens this app's page in the system settings (CAM-052 recovery).
  Future<void> openAppSettings();

  Future<List<CameraDescriptor>> listCameras();

  Future<CameraCapabilities> capabilities(String cameraId);

  Future<CameraSessionInfo> openSession(SessionConfig config);

  /// Idempotent.
  Future<void> closeSession(int sessionId);

  Future<AppliedSettings> applySettings(int sessionId, ResolvedCaptureSettings settings);

  /// Tap-to-focus and tap-to-meter at a normalised preview point (0..1, 0..1).
  Future<void> focusAt(int sessionId, double x, double y);

  Future<void> setLive(int sessionId, {required bool enabled});

  Future<CaptureResult> capture(int sessionId, CaptureRequest request);

  Future<void> startVideo(int sessionId, VideoRequest request);

  Future<VideoResult> stopVideo(int sessionId);

  /// App backgrounded or another interruption: stops preview and LIVE buffering (NFR-012).
  Future<void> suspendSession(int sessionId);

  Future<void> resumeSession(int sessionId);

  /// Events of every open session: state, applied settings, errors, thermal state, orientation.
  Stream<SessionEvent> get sessionEvents;
}
