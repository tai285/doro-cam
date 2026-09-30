import 'package:doro_camera/doro_camera.dart';
import 'package:doro_camera/src/pigeon_camera_platform.dart';
import 'package:doro_camera/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CameraPlatform original;

  setUp(() {
    original = CameraPlatform.instance;
  });
  tearDown(() {
    CameraPlatform.instance = original;
  });

  group('CameraPlatform.instance', () {
    test('defaults to the Pigeon-backed implementation', () {
      expect(CameraPlatform.instance, isA<PigeonCameraPlatform>());
    });

    test('can be replaced by a legitimate implementation such as the fake', () {
      final fake = FakeCameraPlatform();
      CameraPlatform.instance = fake;
      expect(CameraPlatform.instance, same(fake));
    });
  });

  group('DoroCamera', () {
    test('uses the injected platform', () async {
      final fake = FakeCameraPlatform();
      final result = await DoroCamera(platform: fake).ping('hello');
      expect(fake.pingCalls, ['hello']);
      expect(result.echo, 'hello');
    });

    test('defaults the ping message', () async {
      final fake = FakeCameraPlatform();
      await DoroCamera(platform: fake).ping();
      expect(fake.pingCalls, ['ping']);
    });

    test('falls back to the global platform instance when none is injected', () async {
      final fake = FakeCameraPlatform();
      CameraPlatform.instance = fake;
      await DoroCamera().ping('via instance');
      expect(fake.pingCalls, ['via instance']);
    });

    test('propagates platform failures unchanged', () async {
      final fake = FakeCameraPlatform(pingError: const CameraException('camera_in_use'));
      await expectLater(
        DoroCamera(platform: fake).ping(),
        throwsA(isA<CameraException>().having((e) => e.code, 'code', 'camera_in_use')),
      );
    });
  });
}
