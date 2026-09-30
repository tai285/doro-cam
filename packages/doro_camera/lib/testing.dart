/// Test doubles for code that depends on the camera plugin. Import only from tests.
library;

import 'package:doro_camera/doro_camera.dart';

/// A scriptable [CameraPlatform] for widget and unit tests: no hardware, no channels.
///
/// It records every call and answers with whatever the test configured, including failures.
class FakeCameraPlatform implements CameraPlatform {
  FakeCameraPlatform({
    this.pingResult = const PingResult(
      echo: '',
      platform: 'fake',
      osVersion: '0',
      syntheticCameraCompiledIn: false,
    ),
    this.pingError,
  });

  /// Returned by [ping] with its `echo` replaced by the message that was sent.
  PingResult pingResult;

  /// When set, [ping] throws it instead of answering.
  Object? pingError;

  /// Messages received by [ping], in order.
  final List<String> pingCalls = <String>[];

  @override
  Future<PingResult> ping(String message) async {
    pingCalls.add(message);
    final error = pingError;
    if (error != null) {
      throw error;
    }
    return PingResult(
      echo: message,
      platform: pingResult.platform,
      osVersion: pingResult.osVersion,
      syntheticCameraCompiledIn: pingResult.syntheticCameraCompiledIn,
    );
  }
}
