import 'package:doro_camera/doro_camera.dart';
import 'package:doro_camera/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeCameraPlatform', () {
    test('records every call in order', () async {
      final fake = FakeCameraPlatform();
      await fake.ping('a');
      await fake.ping('b');
      expect(fake.pingCalls, ['a', 'b']);
    });

    test('echoes the message while keeping the scripted platform details', () async {
      final fake = FakeCameraPlatform(
        pingResult: const PingResult(
          echo: 'ignored',
          platform: 'ios',
          osVersion: '18.6',
          syntheticCameraCompiledIn: true,
        ),
      );
      expect(
        await fake.ping('hello'),
        const PingResult(
          echo: 'hello',
          platform: 'ios',
          osVersion: '18.6',
          syntheticCameraCompiledIn: true,
        ),
      );
    });

    test('has sensible defaults: a fake platform without a synthetic camera', () async {
      final result = await FakeCameraPlatform().ping('x');
      expect(result.platform, 'fake');
      expect(result.syntheticCameraCompiledIn, isFalse);
    });

    test('throws the scripted error, and still records the call', () async {
      final fake = FakeCameraPlatform(pingError: const CameraException('permission_denied'));
      await expectLater(fake.ping('x'), throwsA(isA<CameraException>()));
      expect(fake.pingCalls, ['x']);
    });

    test('scripted behavior can change between calls', () async {
      final fake = FakeCameraPlatform(pingError: StateError('boom'));
      await expectLater(fake.ping('1'), throwsStateError);
      fake.pingError = null;
      expect((await fake.ping('2')).echo, '2');
    });
  });
}
