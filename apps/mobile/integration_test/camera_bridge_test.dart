import 'dart:io';

import 'package:doro_camera/doro_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Proves the Dart <-> native bridge on a real Android Emulator / iOS Simulator (ADR-0013). The iOS
/// Simulator has no camera, so everything here runs against the synthetic test source, which exists
/// only in debug and test builds.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final expectedPlatform = defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  Future<CameraDescriptor> syntheticCamera(DoroCamera camera) async {
    final cameras = await camera.listCameras();
    return cameras.firstWhere((c) => c.source == CameraSource.synthetic);
  }

  testWidgets('[CAM-004] native answers keep unusual text intact', (
    tester,
  ) async {
    const text = 'Doro 相机 📷 — café';
    final result = await DoroCamera().ping(text);
    expect(result.echo, text);
    expect(result.platform, expectedPlatform);
    expect(result.osVersion, isNotEmpty);
  });

  testWidgets(
    '[NFR-016] debug test builds report the synthetic test camera as compiled in',
    (tester) async {
      expect(kDebugMode, isTrue);
      expect((await DoroCamera().ping()).syntheticCameraCompiledIn, isTrue);
    },
  );

  testWidgets(
    '[CAM-004] the synthetic source is listed and reports capabilities',
    (tester) async {
      final camera = DoroCamera();
      final synthetic = await syntheticCamera(camera);
      final caps = await camera.capabilities(synthetic.id);
      expect(caps.cameraId, synthetic.id);
      expect(caps.photoSizes, isNotEmpty);
      expect(caps.zoom.min, lessThanOrEqualTo(caps.zoom.max));
    },
  );

  testWidgets(
    '[CAM-050] a still capture on the synthetic source writes files and reports applied settings',
    (tester) async {
      final camera = DoroCamera();
      final synthetic = await syntheticCamera(camera);
      final session = await camera.open(SessionConfig(cameraId: synthetic.id));
      final dir = await Directory.systemTemp.createTemp('doro_it_');
      try {
        expect(session.info.source, CameraSource.synthetic);
        await session.apply(const ResolvedCaptureSettings());
        final result = await session.capture(
          CaptureRequest(
            memoryId: '0190a000-0000-7000-8000-000000000001',
            outputDir: dir.path,
            originalName: 'original.jpg',
            renderedName: 'rendered.jpg',
            thumbnailName: 'thumb.jpg',
            displayName: 'display.jpg',
          ),
        );
        expect(result.source, CameraSource.synthetic);
        expect(result.width, greaterThan(0));
        expect(File(result.originalPath).existsSync(), isTrue);
        expect(File(result.originalPath).lengthSync(), greaterThan(0));
        expect(result.applied.zoomRatio, greaterThan(0));
      } finally {
        await session.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
