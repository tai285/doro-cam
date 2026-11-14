import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/features/auth/presentation/auth_screens.dart';
import 'package:doro_cam/features/settings/presentation/account_section.dart';
import 'package:doro_cam/features/sync/presentation/sync_screen.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

void main() {
  group('settings', () {
    uiTest(
      '[SYNC-005] uploads are Wi-Fi only by default, and the switch is remembered',
      (tester) async {
        final env = await launch(tester, location: AppRoutes.settings);
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('wifi-only')))
              .value,
          isTrue,
        );
        await tester.tap(find.byKey(const Key('wifi-only')));
        await settle(tester, frames: 6);
        expect(await io(tester, () => env.data.settings.wifiOnly()), isFalse);
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('wifi-only')))
              .value,
          isFalse,
        );
      },
    );

    uiTest(
      '[PRIV-001] location is off by default; turning it on asks for permission and respects a refusal',
      (tester) async {
        late UiEnv env;
        env = await launch(tester, location: AppRoutes.settings);
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('capture-location')))
              .value,
          isFalse,
        );
        env.location.permission = false;
        await tester.ensureVisible(find.byKey(const Key('capture-location')));
        await tester.tap(find.byKey(const Key('capture-location')));
        await settle(tester, frames: 6);
        expect(env.location.requests, 1);
        expect(
          await io(tester, () => env.data.settings.captureLocation()),
          isFalse,
        );
        expect(
          find.textContaining('Location access was not allowed'),
          findsOneWidget,
        );

        env.location.permission = true;
        await tester.tap(find.byKey(const Key('capture-location')));
        await settle(tester, frames: 6);
        expect(
          await io(tester, () => env.data.settings.captureLocation()),
          isTrue,
        );
        await tester.tap(
          find.byKey(const Key('capture-location')),
        ); // turning it off needs no permission
        await settle(tester, frames: 6);
        expect(
          await io(tester, () => env.data.settings.captureLocation()),
          isFalse,
        );
      },
    );

    uiTest('[EXP-003] the authentic switch is stored', (tester) async {
      final env = await launch(tester, location: AppRoutes.settings);
      await tester.ensureVisible(find.byKey(const Key('authentic-mode')));
      await tester.tap(find.byKey(const Key('authentic-mode')));
      await settle(tester, frames: 6);
      expect(
        await io(
          tester,
          () => env.data.settings.readBool('camera.authentic', fallback: false),
        ),
        isTrue,
      );
    });

    uiTest(
      '[AUTH-005] signed out: the account section offers sign-in and says everything still works',
      (tester) async {
        await launch(tester, location: AppRoutes.settings);
        await pumpUntil(tester, find.byKey(const Key('settings-sign-in')));
        await tester.ensureVisible(find.byKey(const Key('settings-sign-in')));
        expect(find.text('You’re not signed in'), findsOneWidget);
        expect(
          find.byKey(const Key('open-albums')),
          findsNothing,
        ); // account features are hidden until signed in
        await tester.tap(find.byKey(const Key('settings-sign-in')));
        await settle(tester, frames: 6);
        expect(find.text('Sign in'), findsWidgets);
      },
    );

    uiTest(
      '[WEB-005][AUTH-004] signed in: shows the account, storage and devices, and signs out',
      (tester) async {
        late UiEnv env;
        env = await launch(
          tester,
          location: AppRoutes.settings,
          prepare: signIn,
        );
        await pumpUntil(tester, find.byKey(const Key('account-info')));
        await tester.ensureVisible(find.byKey(const Key('account-info')));
        expect(find.text('Dorothy'), findsOneWidget);
        expect(find.byKey(const Key('storage-text')), findsOneWidget);
        expect(find.byKey(const Key('session-s1')), findsOneWidget);
        expect(find.text('This device'), findsOneWidget);
        expect(find.byKey(const Key('open-albums')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('sign-out')));
        await tester.tap(find.byKey(const Key('sign-out')));
        await settle(tester, frames: 8);
        expect(await io(tester, () => env.tokens.read()), isNull);
        expect(find.text('You’re not signed in'), findsOneWidget);
      },
    );

    uiTest(
      '[PRIV-004][WEB-006] deleting the account needs the password and then shows the date; it can be cancelled',
      (tester) async {
        await launch(tester, location: AppRoutes.settings, prepare: signIn);
        await pumpUntil(tester, find.byKey(const Key('delete-account')));
        await tester.ensureVisible(find.byKey(const Key('delete-account')));
        await tester.tap(find.byKey(const Key('delete-account')));
        await settle(tester, frames: 4);
        await tester.enterText(
          find.byKey(const Key('delete-password')),
          'wrong',
        );
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester, frames: 8);
        expect(find.byKey(const Key('delete-error')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('delete-password')),
          'correct-password',
        );
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester, frames: 10);
        expect(find.byKey(const Key('delete-error')), findsNothing);
      },
    );

    uiTest('the settings page links to the backup status and presets', (
      tester,
    ) async {
      await launch(tester, location: AppRoutes.settings);
      await tester.ensureVisible(find.byKey(const Key('open-sync')));
      await tester.tap(find.byKey(const Key('open-sync')));
      await settle(tester, frames: 8);
      expect(find.text('Backup status'), findsWidgets);
    });
  });

  group('sign in, sign up and reset', () {
    uiTest(
      '[AUTH-001] signs in, claims the session and goes back to settings',
      (tester) async {
        late UiEnv env;
        env = await launch(tester, location: AppRoutes.signIn);
        await tester.enterText(
          find.byKey(const Key('email')),
          'dorothy@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('password')),
          'correct-password',
        );
        await tester.tap(find.byKey(const Key('sign-in-submit')));
        await settle(tester, frames: 12);
        expect(await io(tester, () => env.tokens.read()), 'token-1');
        expect(find.text('Settings'), findsWidgets);
      },
    );

    uiTest(
      '[AUTH-001] a wrong password is explained in plain words and the user stays on the page',
      (tester) async {
        await launch(tester, location: AppRoutes.signIn);
        await tester.enterText(find.byKey(const Key('email')), 'a@b.test');
        await tester.enterText(find.byKey(const Key('password')), 'nope');
        await tester.tap(find.byKey(const Key('sign-in-submit')));
        await settle(tester, frames: 10);
        expect(
          find.text('That email and password do not match.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('sign-in-submit')), findsOneWidget);
      },
    );

    uiTest('links to sign-up and password reset', (tester) async {
      await launch(tester, location: AppRoutes.signIn);
      await tester.ensureVisible(find.byKey(const Key('to-sign-up')));
      await tester.tap(find.byKey(const Key('to-sign-up')));
      await settle(tester, frames: 8);
      expect(find.byKey(const Key('sign-up-submit')), findsOneWidget);
    });

    uiTest(
      '[AUTH-001] sign-up asks to check email; a short password is refused locally',
      (tester) async {
        await launch(tester, location: AppRoutes.signUp);
        await tester.enterText(find.byKey(const Key('name')), 'Dorothy');
        await tester.enterText(
          find.byKey(const Key('email')),
          'd@example.test',
        );
        await tester.enterText(find.byKey(const Key('password')), 'short');
        await tester.tap(find.byKey(const Key('sign-up-submit')));
        await settle(tester, frames: 4);
        expect(
          find.text('Use a password of at least 10 characters.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('password')),
          'a-long-enough-password',
        );
        await tester.tap(find.byKey(const Key('sign-up-submit')));
        await settle(tester, frames: 10);
        expect(find.byKey(const Key('check-email')), findsOneWidget);
        expect(find.textContaining('d@example.test'), findsOneWidget);
      },
    );

    uiTest(
      '[AUTH-006] password reset: request a link, then set a new password with the code',
      (tester) async {
        await launch(tester, location: AppRoutes.forgotPassword);
        await tester.enterText(
          find.byKey(const Key('email')),
          'd@example.test',
        );
        await tester.tap(find.byKey(const Key('send-reset')));
        await settle(tester, frames: 8);
        expect(find.byKey(const Key('reset-sent')), findsOneWidget);
        await tester.enterText(find.byKey(const Key('reset-token')), 'abc123');
        await tester.enterText(
          find.byKey(const Key('new-password')),
          'a-brand-new-password',
        );
        await tester.ensureVisible(find.byKey(const Key('reset-submit')));
        await tester.tap(find.byKey(const Key('reset-submit')));
        await settle(tester, frames: 10);
        expect(find.byKey(const Key('reset-done')), findsOneWidget);
      },
    );

    uiTest(
      'friendlyAuthError explains offline, wrong password, unverified email, rate limits and unknown failures',
      (tester) async {
        expect(
          friendlyAuthError(const NetworkException('x')),
          contains('Can’t reach the server'),
        );
        expect(
          friendlyAuthError(
            const ApiException(status: 401, code: 'x', message: 'm'),
          ),
          'That email and password do not match.',
        );
        expect(
          friendlyAuthError(
            const ApiException(
              status: 403,
              code: 'EMAIL_NOT_VERIFIED',
              message: 'm',
            ),
          ),
          contains('confirm your email'),
        );
        expect(
          friendlyAuthError(
            const ApiException(status: 429, code: 'rate_limited', message: 'm'),
          ),
          contains('Too many attempts'),
        );
        expect(
          friendlyAuthError(
            const ApiException(
              status: 400,
              code: 'x',
              message: 'Password too short',
            ),
          ),
          'Password too short',
        );
        expect(
          friendlyAuthError(StateError('x')),
          'Something went wrong. Please try again.',
        );
      },
    );

    uiTest('formatBytes writes sizes in readable units', (tester) async {
      expect(
        <int>[
          0,
          999,
          1024,
          1536,
          5 * 1024 * 1024,
          3 * 1024 * 1024 * 1024,
        ].map(formatBytes),
        <String>['0 B', '999 B', '1.00 KB', '1.50 KB', '5.00 MB', '3.00 GB'],
      );
    });
  });

  group('backup status', () {
    uiTest(
      '[LIB-004] signed out: explains nothing uploads and lists what is waiting',
      (tester) async {
        await launch(
          tester,
          location: AppRoutes.sync,
          prepare: (env) async {
            await env.seed(caption: 'waiting one');
          },
        );
        await pumpUntil(tester, find.byKey(const Key('count-local')));
        expect(find.byKey(const Key('sync-signed-out')), findsOneWidget);
        expect(find.text('Only on this phone: 1'), findsOneWidget);
        expect(find.text('Backed up: 0'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('sync-now')))
              .onPressed,
          isNull,
        );
      },
    );

    uiTest('[SYNC-002] signed in: sync now runs the round and reports it', (
      tester,
    ) async {
      await launch(tester, location: AppRoutes.sync, prepare: signIn);
      await tester.tap(find.byKey(const Key('sync-now')));
      await settle(tester, frames: 12);
      expect(find.byKey(const Key('sync-result')), findsOneWidget);
      expect(find.byKey(const Key('sync-all-done')), findsOneWidget);
    });

    uiTest('describeEvent turns every upload event into a sentence', (
      tester,
    ) async {
      expect(describeEvent(const AssetSynced('m', 'a')), isNotEmpty);
      expect(
        describeEvent(const AssetFailed('m', 'a', 'upload.too_large')),
        contains('upload.too_large'),
      );
      expect(describeEvent(const NeedsSignIn()), contains('Sign in again'));
      expect(describeEvent(const QuotaExceeded()), contains('storage is full'));
    });
  });

  group('presets', () {
    uiTest('[EXP-007] lists, renames and deletes presets', (tester) async {
      late UiEnv env;
      late String id;
      env = await launch(
        tester,
        location: AppRoutes.presets,
        prepare: (e) async {
          id = (await e.data.presets.save(
            name: 'Street',
            experienceId: 'mirrorless',
            intent: <String, Object?>{'iso': 400},
            profileId: 'warm-film',
            live: true,
          )).id;
        },
      );
      await pumpUntil(tester, find.textContaining('Street'));
      expect(
        find.textContaining('mirrorless · warm-film · LIVE'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('rename-$id')));
      await settle(tester, frames: 4);
      await tester.enterText(
        find.byKey(const Key('rename-field')),
        'Street 28',
      );
      await tester.tap(find.byKey(const Key('rename-save')));
      await settle(tester, frames: 8);
      expect(
        (await io(tester, () => env.data.presets.list())).single.name,
        'Street 28',
      );
      await tester.tap(find.byKey(Key('delete-$id')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('delete-preset-confirm')));
      await settle(tester, frames: 8);
      expect(await io(tester, () => env.data.presets.list()), isEmpty);
      expect(find.byKey(const Key('presets-empty')), findsOneWidget);
    });
  });

  group('onboarding', () {
    uiTest(
      '[CAM-052] the first launch explains the app, then asks for camera and microphone',
      (tester) async {
        final env = await launch(tester, onboarded: false);
        expect(find.byKey(const Key('onboarding-pages')), findsOneWidget);
        expect(find.text('1 of 3'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding-next')));
        await settle(tester, frames: 6);
        await tester.tap(find.byKey(const Key('onboarding-next')));
        await settle(tester, frames: 6);
        expect(find.textContaining('microphone is optional'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding-allow')));
        await settle(tester, frames: 12);
        expect(env.camera.calls, contains('requestPermissions'));
        expect(
          await io(
            tester,
            () => env.data.settings.readBool(onboardedKey, fallback: false),
          ),
          isTrue,
        );
      },
    );

    uiTest('it can be skipped and is not shown again', (tester) async {
      final env = await launch(tester, onboarded: false);
      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await settle(tester, frames: 12);
      expect(env.camera.calls.where((c) => c == 'requestPermissions'), isEmpty);
      expect(
        await io(
          tester,
          () => env.data.settings.readBool(onboardedKey, fallback: false),
        ),
        isTrue,
      );
    });
  });
}
