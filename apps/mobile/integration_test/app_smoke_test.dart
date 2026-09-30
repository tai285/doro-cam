import 'package:doro_cam/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a real Android Emulator / iOS Simulator (ADR-0013): the app launches and navigates.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches on the camera and navigates between screens', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera-title')), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('No memories yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to camera'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera-title')), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });
}
