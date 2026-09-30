import 'package:doro_camera/doro_camera.dart';
import 'package:doro_camera/src/messages.g.dart';
import 'package:doro_camera/src/pigeon_camera_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the generated host API when only the mapping logic is under test.
class FakeHostApi extends CameraHostApi {
  final List<String> received = <String>[];
  Object? failure;
  bool synthetic = false;

  @override
  Future<PingResultMessage> ping(String message) async {
    received.add(message);
    final error = failure;
    if (error != null) {
      throw error;
    }
    return PingResultMessage(
      echo: message,
      platform: 'android',
      osVersion: '15',
      syntheticCameraCompiledIn: synthetic,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PigeonCameraPlatform.ping (mapping)', () {
    late FakeHostApi host;
    late PigeonCameraPlatform platform;

    setUp(() {
      host = FakeHostApi();
      platform = PigeonCameraPlatform(api: host);
    });

    test('[CAM-004] forwards the message and maps the native answer to the domain type', () async {
      final result = await platform.ping('hello');

      expect(host.received, ['hello']);
      expect(
        result,
        const PingResult(
          echo: 'hello',
          platform: 'android',
          osVersion: '15',
          syntheticCameraCompiledIn: false,
        ),
      );
    });

    test('maps the synthetic-camera flag from the native side', () async {
      host.synthetic = true;
      expect((await platform.ping('p')).syntheticCameraCompiledIn, isTrue);
    });

    test('turns a native PlatformException into a typed CameraException', () async {
      host.failure = PlatformException(code: 'permission_denied', message: 'Camera permission was denied');

      await expectLater(
        platform.ping('p'),
        throwsA(
          isA<CameraException>()
              .having((e) => e.code, 'code', 'permission_denied')
              .having((e) => e.message, 'message', 'Camera permission was denied'),
        ),
      );
    });

    test('keeps a PlatformException without a message as a code-only CameraException', () async {
      host.failure = PlatformException(code: 'camera_in_use');
      await expectLater(
        platform.ping('p'),
        throwsA(isA<CameraException>().having((e) => e.message, 'message', isNull)),
      );
    });

    test('does not swallow unexpected errors', () async {
      host.failure = StateError('bug');
      await expectLater(platform.ping('p'), throwsStateError);
    });

    test('creates its own host API when none is injected', () {
      expect(PigeonCameraPlatform(), isA<CameraPlatform>());
    });
  });

  group('PigeonCameraPlatform.ping (wire format)', () {
    const channelName = 'dev.flutter.pigeon.doro_camera.CameraHostApi.ping';
    final channel = BasicMessageChannel<Object?>(channelName, CameraHostApi.pigeonChannelCodec);

    void nativeAnswers(Future<Object?> Function(List<Object?> arguments) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        channel,
        (message) => handler(message! as List<Object?>),
      );
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        channel,
        null,
      );
    });

    test('[CAM-004] uses the documented channel and the Pigeon codec in both directions', () async {
      List<Object?>? sent;
      nativeAnswers((arguments) async {
        sent = arguments;
        return <Object?>[
          PingResultMessage(
            echo: arguments.first! as String,
            platform: 'ios',
            osVersion: '18.6',
            syntheticCameraCompiledIn: true,
          ),
        ];
      });

      final result = await PigeonCameraPlatform().ping('over the wire');

      expect(sent, ['over the wire']);
      expect(
        result,
        const PingResult(
          echo: 'over the wire',
          platform: 'ios',
          osVersion: '18.6',
          syntheticCameraCompiledIn: true,
        ),
      );
    });

    test('carries non-ASCII text and long messages intact', () async {
      nativeAnswers((arguments) async => <Object?>[
        PingResultMessage(
          echo: arguments.first! as String,
          platform: 'android',
          osVersion: '15',
          syntheticCameraCompiledIn: false,
        ),
      ]);
      final platform = PigeonCameraPlatform();

      const text = 'Doro 相机 📷 — café';
      expect((await platform.ping(text)).echo, text);
      final long = 'x' * 100000;
      expect((await platform.ping(long)).echo, long);
    });

    test('maps an error reply (code, message, details) to a CameraException', () async {
      nativeAnswers((_) async => <Object?>['camera_in_use', 'Another app is using the camera', null]);

      await expectLater(
        PigeonCameraPlatform().ping('p'),
        throwsA(
          isA<CameraException>()
              .having((e) => e.code, 'code', 'camera_in_use')
              .having((e) => e.message, 'message', 'Another app is using the camera'),
        ),
      );
    });

    test('reports a missing native handler as a channel error, not a hang', () async {
      await expectLater(PigeonCameraPlatform().ping('p'), throwsA(isA<CameraException>()));
    });
  });
}
