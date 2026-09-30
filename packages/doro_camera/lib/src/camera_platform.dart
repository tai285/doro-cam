import 'package:doro_camera/src/pigeon_camera_platform.dart';
import 'package:doro_camera/src/ping_result.dart';

/// The seam between the app and the native camera (docs/architecture/camera.md).
///
/// The real implementation talks to Kotlin/Swift through Pigeon. App tests replace it with
/// `FakeCameraPlatform` from `package:doro_camera/testing.dart`.
abstract class CameraPlatform {
  /// The platform in use. Defaults to the Pigeon-backed implementation; tests assign a fake.
  static CameraPlatform instance = PigeonCameraPlatform();

  /// Sends [message] to the native side and returns what comes back.
  Future<PingResult> ping(String message);
}
