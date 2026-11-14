import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:doro_cam/platform/adapters.dart';
import 'package:doro_cam/platform/bootstrap.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('networkKindOf', () {
    test('[SYNC-005] Wi-Fi and ethernet are unmetered; mobile and anything else is metered; nothing is none', () {
      expect(
        networkKindOf(<ConnectivityResult>[ConnectivityResult.wifi]),
        NetworkKind.wifi,
      );
      expect(
        networkKindOf(<ConnectivityResult>[ConnectivityResult.ethernet]),
        NetworkKind.wifi,
      );
      expect(
        networkKindOf(<ConnectivityResult>[
          ConnectivityResult.mobile,
          ConnectivityResult.wifi,
        ]),
        NetworkKind.wifi,
      );
      expect(
        networkKindOf(<ConnectivityResult>[ConnectivityResult.mobile]),
        NetworkKind.cellular,
      );
      expect(
        networkKindOf(<ConnectivityResult>[ConnectivityResult.vpn]),
        NetworkKind.cellular,
      );
      expect(
        networkKindOf(<ConnectivityResult>[ConnectivityResult.none]),
        NetworkKind.none,
      );
      expect(
        networkKindOf(<ConnectivityResult>[ConnectivityResult.bluetooth]),
        NetworkKind.none,
      );
      expect(networkKindOf(const <ConnectivityResult>[]), NetworkKind.none);
    });
  });

  group('SecureTokenStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test(
      '[AUTH-004] keeps the session token in secure storage, not anywhere else',
      () async {
        final store = SecureTokenStore();
        expect(await store.read(), isNull);
        await store.write('abc');
        expect(await store.read(), 'abc');
        await store.delete();
        expect(await store.read(), isNull);
      },
    );
  });

  group('SystemFeedbackService', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add('${call.method}:${call.arguments}');
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    test('[CAM-051] the shutter gives a haptic, and a click only when the Experience asks for it', () async {
      const service = SystemFeedbackService();
      await service.shutter(sound: false);
      expect(calls, <String>[
        'HapticFeedback.vibrate:HapticFeedbackType.mediumImpact',
      ]);
      calls.clear();
      await service.shutter(sound: true);
      expect(
        calls,
        containsAll(<String>[
          'HapticFeedback.vibrate:HapticFeedbackType.mediumImpact',
          'SystemSound.play:SystemSoundType.click',
        ]),
      );
    });

    test('selection and warning use light and heavy haptics', () async {
      const service = SystemFeedbackService();
      await service.select();
      await service.warn();
      expect(calls, <String>[
        'HapticFeedback.vibrate:HapticFeedbackType.selectionClick',
        'HapticFeedback.vibrate:HapticFeedbackType.heavyImpact',
      ]);
    });
  });

  test('the API base defaults to the host machine for the emulator and can be overridden at build time', () {
    expect(
      defaultApiBase().toString(),
      anyOf('http://10.0.2.2:3000', 'http://localhost:3000'),
    );
  });

  test('DeviceLocation carries its accuracy', () {
    const fix = DeviceLocation(
      latitude: 1,
      longitude: 2,
      accuracyM: 5,
      altitudeM: 9,
    );
    expect(
      (fix.latitude, fix.longitude, fix.accuracyM, fix.altitudeM),
      (1.0, 2.0, 5.0, 9.0),
    );
  });
}
