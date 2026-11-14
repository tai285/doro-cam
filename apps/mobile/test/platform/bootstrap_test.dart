import 'dart:io';

import 'package:doro_cam/platform/background_sync.dart';
import 'package:doro_cam/platform/bootstrap.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_planner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    docs = Directory.systemTemp.createTempSync('doro_bootstrap_test_');
    // The platform plugins have no host implementation: answer the calls the start-up makes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    docs.deleteSync(recursive: true);
  });

  test('openDataLayer creates the media folder and database under app storage, signed out', () async {
    final data = await openDataLayer(documents: () async => docs);
    addTearDown(data.close);
    expect(Directory('${docs.path}/media').existsSync(), isTrue);
    expect(data.account.isSignedIn, isFalse);
    expect(await data.settings.wifiOnly(), isTrue);
    expect(File('${docs.path}/doro.sqlite').existsSync(), isTrue);
  });

  test('[SYNC-002][SYNC-005] bootstrap registers the headless entry point and the periodic pass with the Wi-Fi-only setting, and follows changes', () async {
    final planner = FakePlanner();
    final runtime = await bootstrap(
      apiBase: Uri.parse('https://api.test'),
      planner: planner,
      documents: () async => docs,
    );
    addTearDown(runtime.data.close);
    await pumpEventQueue();

    expect(planner.dispatcher, same(backgroundCallbackDispatcher));
    expect(planner.work.map((w) => (w.kind, w.name, w.unmeteredOnly)), [('periodic', periodicWorkName, true)]);

    await runtime.data.settings.setWifiOnly(value: false);
    await pumpEventQueue(times: 50);
    expect(planner.work.last.unmeteredOnly, isFalse);
    expect(runtime.data.account.isSignedIn, isFalse);
  });

  test('bootstrap without a background scheduler (desktop and tests) still opens the app', () async {
    final runtime = await bootstrap(apiBase: Uri.parse('https://api.test'), documents: () async => docs);
    addTearDown(runtime.data.close);
    expect(runtime.data.account.isSignedIn, isFalse);
    expect(await runtime.tokens.read(), isNull);
  });
}
