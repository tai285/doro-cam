import 'package:doro_camera/doro_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Proves the Dart <-> native bridge works on a real Android Emulator / iOS Simulator (ADR-0013):
/// the message goes through Pigeon to Kotlin or Swift and comes back.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final expectedPlatform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  testWidgets('[CAM-004] ping round-trips through the native plugin', (tester) async {
    final result = await DoroCamera().ping('integration');

    expect(result.echo, 'integration');
    expect(result.platform, expectedPlatform);
    expect(result.osVersion, isNotEmpty);
  });

  testWidgets('[CAM-004] native answers keep unusual text intact', (tester) async {
    const text = 'Doro 相机 📷 — café';
    expect((await DoroCamera().ping(text)).echo, text);
  });

  testWidgets('[NFR-016] debug test builds report the synthetic test camera as compiled in', (tester) async {
    // Integration tests run debug builds, where the synthetic camera exists (ADR-0013).
    // Release builds must report false: CI checks that on the release artifacts.
    expect(kDebugMode, isTrue);
    expect((await DoroCamera().ping()).syntheticCameraCompiledIn, isTrue);
  });
}
