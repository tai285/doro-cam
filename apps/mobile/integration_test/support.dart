import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets real time pass (database, platform channels and the camera run outside the test clock) and pumps
/// frames, until [finder] matches or [seconds] run out.
Future<bool> waitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 30,
}) async {
  for (var i = 0; i < seconds * 4; i++) {
    if (finder.evaluate().isNotEmpty) {
      return true;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return finder.evaluate().isNotEmpty;
}

/// Lets real time pass without waiting for any widget.
Future<void> settle(WidgetTester tester, {int milliseconds = 1000}) async {
  await tester.runAsync(
    () => Future<void>.delayed(Duration(milliseconds: milliseconds)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens the first screen the app shows: skips the introduction when it appears.
Future<void> passOnboarding(WidgetTester tester) async {
  final skip = find.byKey(const Key('onboarding-skip'));
  final camera = find.byKey(const Key('shutter-button'));
  final status = find.byKey(const Key('camera-status-title'));
  for (var i = 0; i < 120; i++) {
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await settle(tester);
      return;
    }
    if (camera.evaluate().isNotEmpty || status.evaluate().isNotEmpty) {
      return;
    }
    await settle(tester, milliseconds: 250);
  }
}
