// Pigeon definition of the Dart <-> native camera contract (docs/specs/camera.md).
//
// Regenerate after editing:  dart run pigeon --input pigeons/camera_api.dart
// Generated files are committed (the native code compiles against them). Never edit them by hand.
//
// Naming rule: every message class ends in `Message`. The Dart domain types in lib/src/ are
// separate immutable classes (mapped from messages) so the public API does not depend on Pigeon.
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

@HostApi()
abstract class CameraHostApi {
  PingResultMessage ping(String message);
}
