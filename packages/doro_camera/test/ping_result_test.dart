import 'package:doro_camera/doro_camera.dart';
import 'package:flutter_test/flutter_test.dart';

PingResult sample({
  String echo = 'hello',
  String platform = 'android',
  String osVersion = '15',
  bool synthetic = false,
}) => PingResult(
  echo: echo,
  platform: platform,
  osVersion: osVersion,
  syntheticCameraCompiledIn: synthetic,
);

void main() {
  group('PingResult', () {
    test('is equal when every field is equal, and hashes consistently', () {
      expect(sample(), equals(sample()));
      expect(sample().hashCode, sample().hashCode);
    });

    test('differs when any single field differs', () {
      expect(sample(), isNot(equals(sample(echo: 'other'))));
      expect(sample(), isNot(equals(sample(platform: 'ios'))));
      expect(sample(), isNot(equals(sample(osVersion: '14'))));
      expect(sample(), isNot(equals(sample(synthetic: true))));
    });

    test('is not equal to other types', () {
      expect(sample() == Object(), isFalse);
    });

    test('toString lists every field', () {
      expect(
        sample(synthetic: true).toString(),
        'PingResult(echo: hello, platform: android, osVersion: 15, syntheticCameraCompiledIn: true)',
      );
    });
  });

  group('CameraException', () {
    test('carries a stable code and an optional message', () {
      const error = CameraException('permission_denied', 'Camera permission was denied');
      expect(error.code, 'permission_denied');
      expect(error.message, 'Camera permission was denied');
      expect(error, isA<Exception>());
    });

    test('toString includes the message only when present', () {
      expect(const CameraException('camera_in_use').toString(), 'CameraException(camera_in_use)');
      expect(
        const CameraException('capture_failed', 'sensor timeout').toString(),
        'CameraException(capture_failed, sensor timeout)',
      );
    });
  });
}
