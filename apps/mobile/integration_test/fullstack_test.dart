import 'dart:convert';

import 'package:doro_cam/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// The device half of the full-stack scenario (scripts/e2e-fullstack.sh, requirement tags below). It drives the
/// real app on the Android Emulator against the real API + worker + storage:
/// offline capture, create account, confirm the mailed link, sign in, capture a Motion Memory, back everything
/// up. The web half (apps/web/e2e-fullstack) then finds the same Memories in the dashboard.
///
/// Run only through the script, which starts the stack and passes
/// `--dart-define=API_URL=http://10.0.2.2:<port> --dart-define=E2E_EMAIL=... --dart-define=E2E_PASSWORD=...`.
/// Without E2E_EMAIL the test does nothing, so `flutter test integration_test` stays runnable on its own.
const _email = String.fromEnvironment('E2E_EMAIL');
const _password = String.fromEnvironment('E2E_PASSWORD');
const _apiUrl = String.fromEnvironment('API_URL');

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester, milliseconds: 500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[MEM-001][MOT-001][MOT-002][AUTH-001][AUTH-005][SYNC-002][SYNC-008][MOT-005] photo and motion memory are captured, the account is '
    'confirmed by the mailed link, and both are backed up to the real API',
    (tester) async {
      if (_email.isEmpty) {
        return;
      }
      await app.main();
      await passOnboarding(tester);
      expect(
        await waitFor(tester, find.byKey(const Key('shutter-button'))),
        isTrue,
        reason:
            'camera permission must be granted before the run (adb shell pm grant)',
      );

      // 1. A photo with no account: the camera and the library work offline first.
      await tester.tap(find.byKey(const Key('shutter-button')));
      await settle(tester, milliseconds: 6000);
      expect(find.byKey(const Key('last-capture')), findsOneWidget);

      // 2. Create the account in the app; the confirmation link is in the API's mail outbox.
      await _tap(tester, find.byKey(const Key('open-settings')));
      await _tap(tester, find.byKey(const Key('settings-sign-up')));
      await _type(tester, 'name', 'Full Stack Tester');
      await _type(tester, 'email', _email);
      await _type(tester, 'password', _password);
      await _tap(tester, find.byKey(const Key('sign-up-submit')));
      expect(
        await waitFor(tester, find.byKey(const Key('check-email'))),
        isTrue,
        reason: 'sign-up must lead to the check-your-email screen',
      );

      final link = await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          final response = await http.get(Uri.parse('$_apiUrl/__test/outbox'));
          final items =
              (jsonDecode(response.body) as Map<String, dynamic>)['items']
                  as List<dynamic>;
          for (final item in items.reversed) {
            final mail = item as Map<String, dynamic>;
            if (mail['kind'] == 'verify_email' && mail['to'] == _email) {
              return mail['link'] as String;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        return null;
      });
      expect(link, isNotNull, reason: 'a verification mail must be sent');
      final verified = await tester.runAsync(() async {
        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(link!))
            ..followRedirects = false;
          return (await client.send(request)).statusCode;
        } finally {
          client.close();
        }
      });
      expect(verified, lessThan(400));

      // 3. Sign in (the account is confirmed now).
      await _tap(tester, find.byKey(const Key('go-sign-in')));
      await _type(tester, 'email', _email);
      await _type(tester, 'password', _password);
      await _tap(tester, find.byKey(const Key('sign-in-submit')));
      expect(
        await waitFor(tester, find.byKey(const Key('account-info'))),
        isTrue,
        reason: 'sign-in must land on settings showing the account',
      );
      expect(await waitFor(tester, find.text(_email)), isTrue);

      // 4. A Motion Memory: LIVE on, then the shutter.
      await _tap(tester, find.byIcon(Icons.arrow_back));
      expect(
        await waitFor(tester, find.byKey(const Key('shutter-button'))),
        isTrue,
      );
      await _tap(tester, find.byKey(const Key('live-button')));
      expect(find.byTooltip('LIVE on'), findsOneWidget);
      // Give the pre-roll buffer time to fill, as a person framing the shot would.
      await settle(tester, milliseconds: 2500);
      await tester.tap(find.byKey(const Key('shutter-button')));
      await settle(tester, milliseconds: 8000);
      expect(
        await waitFor(tester, find.byKey(const Key('last-live-badge'))),
        isTrue,
        reason: 'the newest capture must be marked as a Motion Memory',
      );

      // 5. Back up: both Memories must reach "Backed up" (the worker verifies each upload asynchronously).
      await _tap(tester, find.byKey(const Key('open-settings')));
      await _tap(tester, find.byKey(const Key('open-sync')));
      for (var i = 0; i < 8; i++) {
        await _tap(tester, find.byKey(const Key('sync-now')));
        if (await waitFor(
          tester,
          find.text('Backed up: 2'),
          seconds: 20,
        )) {
          break;
        }
      }
      expect(find.text('Backed up: 2'), findsOneWidget);
      expect(find.text('Failed: 0'), findsOneWidget);
    },
  );
}
