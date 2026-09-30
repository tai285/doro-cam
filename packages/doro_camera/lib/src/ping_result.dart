import 'package:flutter/foundation.dart';

/// Answer of a native `ping`: the echoed message plus what the native side is.
@immutable
class PingResult {
  const PingResult({
    required this.echo,
    required this.platform,
    required this.osVersion,
    required this.syntheticCameraCompiledIn,
  });

  /// The message that was sent, returned unchanged.
  final String echo;

  /// `android` or `ios`.
  final String platform;

  /// Operating system version, for example `15` or `18.6`.
  final String osVersion;

  /// True only in debug and test builds that contain the synthetic test camera (ADR-0013).
  /// Release builds always report false.
  final bool syntheticCameraCompiledIn;

  @override
  bool operator ==(Object other) =>
      other is PingResult &&
      other.echo == echo &&
      other.platform == platform &&
      other.osVersion == osVersion &&
      other.syntheticCameraCompiledIn == syntheticCameraCompiledIn;

  @override
  int get hashCode => Object.hash(echo, platform, osVersion, syntheticCameraCompiledIn);

  @override
  String toString() =>
      'PingResult(echo: $echo, platform: $platform, osVersion: $osVersion, '
      'syntheticCameraCompiledIn: $syntheticCameraCompiledIn)';
}
