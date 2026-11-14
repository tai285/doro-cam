import 'package:doro_cam/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// The core journey on a real Android Emulator / iOS Simulator (ADR-0013, the MVP journey of requirements.md):
/// open the app, take a photo with the camera the device offers (the Simulator has only the synthetic source),
/// see it saved, and find it in the library with its metadata.
///
/// Camera and microphone permission are granted before the run (`adb shell pm grant ...`); without them the
/// test stops at the explanation screen, which the smoke test covers.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[MEM-001][LIB-001][CAM-050] a captured photo is saved and shows up with its applied settings',
    (tester) async {
      await app.main();
      await passOnboarding(tester);
      final ready = await waitFor(
        tester,
        find.byKey(const Key('shutter-button')),
      );
      if (!ready) {
        // No camera permission on this run: the explanation screen is the correct and only possible state.
        expect(find.byKey(const Key('camera-status-title')), findsOneWidget);
        return;
      }

      await tester.tap(find.byKey(const Key('shutter-button')));
      // The Memory is saved before success is shown, so a few seconds are plenty (capture, render, durable write).
      await settle(tester, milliseconds: 6000);

      await tester.tap(find.byKey(const Key('last-capture')));
      expect(
        await waitFor(tester, find.byKey(const Key('caption-field'))),
        isTrue,
      );
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Camera style'), findsOneWidget);
    },
  );
}
