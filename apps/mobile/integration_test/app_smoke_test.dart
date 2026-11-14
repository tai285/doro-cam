import 'package:doro_cam/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// Runs the real app on an Android Emulator / iOS Simulator (ADR-0013). On first launch the introduction
/// shows; after skipping it the camera screen is the home of the app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first launch shows the introduction, then the camera, and navigation works',
    (tester) async {
      await app.main();
      await passOnboarding(tester);
      // The camera screen is up: either the viewfinder controls or the permission explanation.
      final shown =
          await waitFor(tester, find.byKey(const Key('shutter-button'))) ||
          find.byKey(const Key('camera-status-title')).evaluate().isNotEmpty;
      expect(shown, isTrue);
    },
  );
}
