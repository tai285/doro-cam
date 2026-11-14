import 'package:doro_cam/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

void main() {
  group('AppRoutes', () {
    test(
      'memory(), album() and invite() build paths and percent-encode ids',
      () {
        expect(AppRoutes.memory('abc-123'), '/memory/abc-123');
        expect(AppRoutes.memory('a/b c'), '/memory/a%2Fb%20c');
        expect(AppRoutes.album('x y'), '/albums/x%20y');
        expect(AppRoutes.invite('tok'), '/invites/tok');
        expect(AppRoutes.invite(''), '/invites');
      },
    );

    test('route constants match the documented locations', () {
      expect(AppRoutes.camera, '/camera');
      expect(AppRoutes.library, '/library');
      expect(AppRoutes.settings, '/settings');
      expect(AppRoutes.memoryPattern, '/memory/:id');
      expect(AppRoutes.onboarding, '/onboarding');
    });
  });

  group('router', () {
    uiTest('the root path redirects to the camera', (tester) async {
      await launch(
        tester,
        location: '/',
        waitFor: find.byKey(const Key('shutter-button')),
      );
      expect(find.byKey(const Key('shutter-button')), findsOneWidget);
    });

    uiTest('deep links reach every screen', (tester) async {
      final cases = <String, Finder>{
        AppRoutes.library: find.text('Library'),
        AppRoutes.settings: find.text('Settings'),
        AppRoutes.sync: find.text('Backup status'),
        AppRoutes.presets: find.text('Presets'),
        AppRoutes.signIn: find.byKey(const Key('sign-in-submit')),
        AppRoutes.signUp: find.byKey(const Key('sign-up-submit')),
        AppRoutes.forgotPassword: find.byKey(const Key('send-reset')),
        AppRoutes.inviteBase: find.byKey(const Key('invite-accept')),
        AppRoutes.memory('0190a000-0000-7000-8000-000000000001'): find.byKey(
          const Key('memory-missing'),
        ),
      };
      for (final entry in cases.entries) {
        await launch(tester, location: entry.key);
        expect(entry.value, findsWidgets, reason: entry.key);
        await tester.pumpWidget(const SizedBox());
      }
    });

    uiTest('an unknown address shows the not-found screen', (tester) async {
      await launch(tester, location: '/no/such/place');
      expect(find.textContaining('/no/such/place'), findsWidgets);
    });

    uiTest('the back button on the library returns to the camera', (
      tester,
    ) async {
      await launch(tester, location: AppRoutes.library);
      await tester.tap(find.byTooltip('Back to camera'));
      await settle(tester, frames: 8);
      expect(find.byKey(const Key('shutter-button')), findsOneWidget);
    });
  });
}
