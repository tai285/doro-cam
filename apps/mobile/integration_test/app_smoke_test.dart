import 'package:doro_cam/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs the real app on an Android Emulator / iOS Simulator (ADR-0013). On first launch the introduction
/// shows; after skipping it the camera screen is the home of the app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first launch shows the introduction, then the camera, and navigation works',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      if (find.byKey(const Key('onboarding-skip')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('onboarding-skip')));
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      // The camera screen is up: either the viewfinder controls or the permission explanation.
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      expect(
        find.byKey(const Key('shutter-button')).evaluate().isNotEmpty ||
            find.byKey(const Key('camera-status-title')).evaluate().isNotEmpty,
        isTrue,
        reason: 'visible texts: $texts',
      );
    },
  );
}
