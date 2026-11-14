import 'package:doro_cam/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// The return trip of the full-stack scenario (scripts/e2e-fullstack.sh): on a FRESH install, signing in to the
/// account whose Memories the first run uploaded and whose caption was edited in the web dashboard brings
/// everything back: both Memories, with the web edit. Does nothing without E2E_EMAIL.
const _email = String.fromEnvironment('E2E_EMAIL');
const _password = String.fromEnvironment('E2E_PASSWORD');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester, milliseconds: 500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[SYNC-006][MEM-004][MEM-006][LIB-001] a fresh install signs in and gets back its Memories with the web edits',
    (tester) async {
      if (_email.isEmpty) {
        return;
      }
      await app.main();
      await passOnboarding(tester);
      expect(
        await waitFor(tester, find.byKey(const Key('shutter-button'))),
        isTrue,
      );

      await _tap(tester, find.byKey(const Key('open-settings')));
      await _tap(tester, find.byKey(const Key('settings-sign-in')));
      await tester.enterText(find.byKey(const Key('email')), _email);
      await tester.enterText(find.byKey(const Key('password')), _password);
      await _tap(tester, find.byKey(const Key('sign-in-submit')));
      expect(
        await waitFor(tester, find.byKey(const Key('account-info'))),
        isTrue,
      );

      await _tap(tester, find.byKey(const Key('open-sync')));
      await _tap(tester, find.byKey(const Key('sync-now')));
      // Pulling is part of "Sync now": two Memories arrive, and they are already backed up.
      expect(
        await waitFor(tester, find.text('Backed up: 2'), seconds: 40),
        isTrue,
        reason: 'both Memories must be restored from the account',
      );

      // The library lists both, the favorite set on the web is marked, and its caption came with it.
      await _tap(tester, find.byIcon(Icons.arrow_back));
      await _tap(tester, find.byIcon(Icons.arrow_back));
      await _tap(tester, find.byKey(const Key('last-capture')));
      expect(
        await waitFor(tester, find.byKey(const Key('library-grid'))),
        isTrue,
      );
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('★'), findsOneWidget, reason: 'the web favorite');
      await _tap(tester, find.text('★'));
      expect(
        await waitFor(
          tester,
          find.widgetWithText(TextField, 'Caption written on the web'),
        ),
        isTrue,
        reason: 'the caption edited on the web',
      );
    },
  );
}
