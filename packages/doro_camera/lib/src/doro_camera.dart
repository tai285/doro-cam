import 'package:doro_camera/src/camera_platform.dart';
import 'package:doro_camera/src/ping_result.dart';

/// Entry point of the camera plugin. Grows with the capability, preview and capture APIs
/// (docs/specs/camera.md); for now it only proves the native bridge works.
class DoroCamera {
  DoroCamera({this._platform});

  final CameraPlatform? _platform;

  CameraPlatform get _resolved => _platform ?? CameraPlatform.instance;

  /// Round-trips [message] through the native layer.
  Future<PingResult> ping([String message = 'ping']) => _resolved.ping(message);
}
