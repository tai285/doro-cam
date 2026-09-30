import 'package:doro_cam/app/app.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/theme/doro_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows the camera title on launch', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('camera-title')), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('uses the dark theme by default (camera UI is dark)', (tester) async {
    await pumpApp(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(context.tokens, DoroTokens.dark);
  });

  testWidgets('is titled Doro Cam', (tester) async {
    await pumpApp(tester);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'Doro Cam');
  });

  testWidgets('the default router provider creates and disposes a router', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DoroCamApp()));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.byType(DoroCamApp), findsOneWidget);

    // Removing the app disposes the provider's router without errors.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('routerProvider yields one router per container', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(identical(container.read(routerProvider), container.read(routerProvider)), isTrue);
  });
}
