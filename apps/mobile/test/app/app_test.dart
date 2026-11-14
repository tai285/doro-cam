import 'package:doro_cam/app/app.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/theme/doro_tokens.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

void main() {
  uiTest('shows the camera on launch', (tester) async {
    await launch(tester, waitFor: find.byKey(const Key('shutter-button')));
    expect(find.byKey(const Key('shutter-button')), findsOneWidget);
  });

  uiTest('uses the dark theme by default (camera UI is dark)', (tester) async {
    await launch(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(context.tokens, DoroTokens.dark);
  });

  uiTest('is titled Doro Cam', (tester) async {
    await launch(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Doro Cam',
    );
  });

  uiTest(
    '[CAM-052] the first launch shows the introduction instead of the camera',
    (tester) async {
      await launch(tester, onboarded: false);
      expect(find.byKey(const Key('onboarding-pages')), findsOneWidget);
      expect(find.byKey(const Key('shutter-button')), findsNothing);
    },
  );

  uiTest(
    'the default router provider reads the onboarding flag from the data layer and disposes cleanly',
    (tester) async {
      final env = await io(tester, UiEnv.create);
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: env.overrides(),
          child: const DoroCamApp(),
        ),
      );
      await settle(tester, frames: 8);
      expect(
        find.byKey(const Key('onboarding-pages')),
        findsOneWidget,
      ); // not onboarded yet
      await tester.pumpWidget(const SizedBox());
      await settle(tester, frames: 2);
    },
  );

  test('routerProvider yields one router per container', () async {
    final env = await UiEnv.create();
    final container = ProviderContainer(overrides: env.overrides());
    addTearDown(() async {
      container.dispose();
      await env.dispose();
    });
    expect(
      identical(container.read(routerProvider), container.read(routerProvider)),
      isTrue,
    );
    expect(container.read(dataLayerProvider), same(env.data));
  });
}
