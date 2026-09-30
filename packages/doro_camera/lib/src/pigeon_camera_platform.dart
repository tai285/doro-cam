import 'package:doro_camera/src/camera_exception.dart';
import 'package:doro_camera/src/camera_platform.dart';
import 'package:doro_camera/src/messages.g.dart';
import 'package:doro_camera/src/ping_result.dart';
import 'package:flutter/services.dart';

/// [CameraPlatform] backed by the Pigeon-generated host API (Kotlin on Android, Swift on iOS).
class PigeonCameraPlatform extends CameraPlatform {
  PigeonCameraPlatform({CameraHostApi? api}) : _api = api ?? CameraHostApi();

  final CameraHostApi _api;

  @override
  Future<PingResult> ping(String message) async {
    try {
      final result = await _api.ping(message);
      return PingResult(
        echo: result.echo,
        platform: result.platform,
        osVersion: result.osVersion,
        syntheticCameraCompiledIn: result.syntheticCameraCompiledIn,
      );
    } on PlatformException catch (error) {
      throw CameraException(error.code, error.message);
    }
  }
}
