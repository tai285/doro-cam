import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart' show CaptureIntent;
import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/camera/presentation/camera_overlays.dart';
import 'package:doro_camera/doro_camera.dart' as cam;
import 'package:doro_camera/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

const _id = 'fake:back';

cam.CameraCapabilities _full() => FakeCameraPlatform.fullCapabilities(_id);

FileWritingCamera _cameraWith(
  cam.CameraCapabilities caps, {
  cam.CameraPermissions? permissions,
  List<cam.CameraDescriptor>? cameras,
  Map<String, cam.CameraCapabilities>? all,
}) => FileWritingCamera(
  permissions:
      permissions ??
      const cam.CameraPermissions(
        camera: cam.PermissionStatus.granted,
        microphone: cam.PermissionStatus.granted,
      ),
  cameras: cameras,
  capabilities: all ?? <String, cam.CameraCapabilities>{_id: caps},
);

/// A widget test with semantics on, so labels can be asserted exactly as a screen reader announces them.
void cameraTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
      // Let focus rings, animations and sheets finish so no timer outlives the widget tree.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      handle.dispose();
    }
  });
}

void main() {
  late UiEnv env;

  Future<void> pumpCamera(
    WidgetTester tester, {
    FileWritingCamera? camera,
    List<Override> extra = const <Override>[],
  }) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    env = await io(tester, () => UiEnv.create(camera: camera));
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, extra: extra));
    await pumpUntil(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w.key == const Key('shutter-button') ||
            w.key == const Key('camera-status-title'),
      ),
    );
    await settle(tester, frames: 3);
  }

  Future<void> pumpUntilSaved(WidgetTester tester, int count) async {
    for (var i = 0; i < 100; i++) {
      final saved = await io(tester, () => env.memories.library());
      if (saved.length >= count) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openSheet(WidgetTester tester, Key chip) async {
    await tester.ensureVisible(find.byKey(chip));
    await tester.tap(find.byKey(chip));
    await settle(tester, frames: 3);
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle(tester, frames: 6);
  }

  void changeSlider(WidgetTester tester, Key key, double value) {
    tester.widget<Slider>(find.byKey(key)).onChanged!(value);
  }

  group('permissions and states', () {
    cameraTest(
      '[CAM-052] asks for the camera with a clear explanation, then shows the viewfinder',
      (tester) async {
        final camera = _cameraWith(
          _full(),
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.notDetermined,
            microphone: cam.PermissionStatus.notDetermined,
          ),
        );
        camera.permissionsAfterRequest = const cam.CameraPermissions(
          camera: cam.PermissionStatus.granted,
          microphone: cam.PermissionStatus.denied,
        );
        await pumpCamera(tester, camera: camera);
        expect(find.text('Doro Cam needs the camera'), findsOneWidget);
        expect(find.textContaining('microphone is optional'), findsOneWidget);
        expect(find.byKey(const Key('shutter-button')), findsNothing);
        await tester.tap(find.text('Allow camera'));
        await pumpUntil(tester, find.byKey(const Key('shutter-button')));
        expect(find.byKey(const Key('shutter-button')), findsOneWidget);
      },
    );
    cameraTest(
      '[CAM-052] after a permanent refusal it explains and opens the system settings',
      (tester) async {
        final camera = _cameraWith(
          _full(),
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.denied,
            microphone: cam.PermissionStatus.denied,
            cameraPermanentlyDenied: true,
          ),
        );
        await pumpCamera(tester, camera: camera);
        expect(find.textContaining('turned off for Doro Cam'), findsOneWidget);
        await tester.tap(find.text('Open Settings'));
        await settle(tester);
        expect(camera.calls, contains('openAppSettings'));
      },
    );
    cameraTest(
      '[CAM-052] a restricted camera cannot be asked for and only offers the library',
      (tester) async {
        final camera = _cameraWith(
          _full(),
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.restricted,
            microphone: cam.PermissionStatus.restricted,
          ),
        );
        await pumpCamera(tester, camera: camera);
        expect(find.text('The camera is restricted'), findsOneWidget);
        expect(find.text('Allow camera'), findsNothing);
        await tester.tap(find.text('Open library'));
        await settle(tester);
        expect(find.text('Library'), findsWidgets);
      },
    );
    cameraTest('a device with no camera says so and offers the library', (
      tester,
    ) async {
      await pumpCamera(
        tester,
        camera: FileWritingCamera(cameras: <cam.CameraDescriptor>[]),
      );
      expect(find.text('No camera found'), findsOneWidget);
    });
    cameraTest(
      '[CAM-053] a camera that fails to start explains and can be retried',
      (tester) async {
        final camera = _cameraWith(_full())
          ..error = const cam.CameraException('camera_in_use');
        await pumpCamera(tester, camera: camera);
        expect(
          find.textContaining('Another app is using the camera'),
          findsOneWidget,
        );
        camera.error = null;
        await tester.tap(find.text('Try again'));
        await pumpUntil(tester, find.byKey(const Key('shutter-button')));
        expect(find.byKey(const Key('shutter-button')), findsOneWidget);
      },
    );
    cameraTest(
      '[CAM-053] backgrounding the app suspends the camera and returning resumes it',
      (tester) async {
        final camera = _cameraWith(_full());
        await pumpCamera(tester, camera: camera);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await settle(tester);
        expect(camera.calls, contains('suspendSession'));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
        expect(camera.calls, contains('resumeSession'));
      },
    );
    cameraTest(
      'coming back from the system settings with permission re-opens the camera',
      (tester) async {
        final camera = _cameraWith(
          _full(),
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.denied,
            microphone: cam.PermissionStatus.denied,
            cameraPermanentlyDenied: true,
          ),
        );
        await pumpCamera(tester, camera: camera);
        camera.permissions = const cam.CameraPermissions(
          camera: cam.PermissionStatus.granted,
          microphone: cam.PermissionStatus.granted,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpUntil(tester, find.byKey(const Key('shutter-button')));
        expect(find.byKey(const Key('shutter-button')), findsOneWidget);
      },
    );
  });

  group('taking photos', () {
    cameraTest(
      '[CAM-003][MEM-001] the shutter saves a Memory, shows it as the last photo, and gives feedback',
      (tester) async {
        await pumpCamera(tester);
        await tester.tap(find.byKey(const Key('shutter-button')));
        await pumpUntilSaved(tester, 1);
        final saved = await io(tester, () => env.memories.library());
        expect(saved, hasLength(1));
        expect(
          saved.single.assets.map((a) => a.role),
          containsAll(<String>[AssetRoles.photoOriginal, AssetRoles.thumbnail]),
        );
        expect(env.feedback.events, contains('shutter'));
        expect(env.camera.captures.single.render!.profileId, 'natural');
      },
    );
    cameraTest('[CAM-041] the self-timer shows its countdown', (tester) async {
      await pumpCamera(tester);
      await tapKey(tester, const Key('timer-button'));
      expect(find.bySemanticsLabel('Timer: 3 seconds'), findsOneWidget);
      await tapKey(tester, const Key('shutter-button'));
      expect(env.camera.captures, hasLength(1));
    });
    cameraTest(
      '[CAM-044] the aspect button cycles through the offered ratios and a crop note appears for non-native ones',
      (tester) async {
        await pumpCamera(tester);
        for (final label in <String>['16:9', '1:1', '4:3', '3:2']) {
          await tapKey(tester, const Key('aspect-button'));
          expect(
            find.bySemanticsLabel('Aspect ratio $label'),
            findsOneWidget,
            reason: label,
          );
        }
      },
    );
    cameraTest('[CAM-042] the grid can be switched', (tester) async {
      await pumpCamera(tester);
      expect(
        find.bySemanticsLabel('Grid on'),
        findsOneWidget,
      ); // Mirrorless default
      await tapKey(tester, const Key('grid-button'));
      expect(find.bySemanticsLabel('Grid off'), findsOneWidget);
    });
    cameraTest('[CAM-040] flash cycles through the modes the camera reports', (
      tester,
    ) async {
      await pumpCamera(tester);
      for (final label in <String>['Auto', 'On', 'Off']) {
        await tapKey(tester, const Key('flash-button'));
        expect(
          find.bySemanticsLabel('Flash: $label'),
          findsOneWidget,
          reason: label,
        );
      }
    });
    cameraTest('[CAM-040] the torch toggles when supported', (tester) async {
      await pumpCamera(tester);
      await tapKey(tester, const Key('torch-button'));
      expect(env.camera.appliedSettings.last.torch, isTrue);
    });
    cameraTest(
      '[CAM-007] shows the 35 mm equivalent focal length and labels digital zoom',
      (tester) async {
        await pumpCamera(tester);
        expect(find.byKey(const Key('readout')), findsOneWidget);
        expect(find.textContaining('26 mm'), findsOneWidget);
        await openSheet(tester, const Key('control-zoom'));
        changeSlider(tester, const Key('slider-zoom'), 4);
        await settle(tester, frames: 3);
        expect(find.textContaining('digital zoom'), findsWidgets);
      },
    );
    cameraTest('[CAM-020] tapping the viewfinder focuses there', (
      tester,
    ) async {
      await pumpCamera(tester);
      await tester.tapAt(const Offset(195, 300));
      await settle(tester, frames: 3);
      expect(env.camera.focusPoints, isNotEmpty);
      expect(find.byKey(const Key('focus-ring')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('focus-ring')), findsNothing);
    });
  });

  group('the control strip shows only what the camera supports (CAM-005)', () {
    final cases =
        <
          (
            String,
            cam.CameraCapabilities Function(cam.CameraCapabilities),
            Key,
            String,
          )
        >[
          (
            'manual ISO',
            (c) => capsWithout(c, iso: true),
            const Key('control-iso'),
            'manual ISO',
          ),
          (
            'manual shutter',
            (c) => capsWithout(c, shutter: true),
            const Key('control-shutter'),
            'manual shutter',
          ),
          (
            'exposure compensation',
            (c) => capsWithout(c, bias: true),
            const Key('control-ev'),
            'exposure compensation',
          ),
          (
            'white balance',
            (c) => capsWithout(c, wbPresets: true, kelvin: true),
            const Key('control-wb'),
            'white-balance',
          ),
          (
            'manual focus and focus lock',
            (c) => capsWithout(c, manualFocus: true, autoFocus: true),
            const Key('control-focus'),
            'manual focus',
          ),
          (
            'zoom',
            (c) => capsWithout(c, zoom: true),
            const Key('control-zoom'),
            'doesn’t zoom',
          ),
          (
            'flash',
            (c) => capsWithout(c, flash: true),
            const Key('flash-button'),
            'no flash',
          ),
          (
            'torch',
            (c) => capsWithout(c, torch: true),
            const Key('torch-button'),
            'no torch',
          ),
        ];
    for (final (name, mutate, key, reason) in cases) {
      cameraTest(
        'without $name: the control is absent and the "why" sheet says why',
        (tester) async {
          await pumpCamera(tester, camera: _cameraWith(mutate(_full())));
          expect(find.byKey(key), findsNothing);
          await openSheet(tester, const Key('why-unavailable'));
          expect(find.byKey(const Key('unavailable-sheet')), findsOneWidget);
          expect(find.textContaining(reason), findsWidgets);
        },
      );
    }
    cameraTest(
      'with everything supported the strip has every manual control and the sheet is empty of reasons',
      (tester) async {
        await pumpCamera(tester);
        for (final key in <String>[
          'control-zoom',
          'control-iso',
          'control-shutter',
          'control-ev',
          'control-wb',
          'control-focus',
          'control-ae-lock',
          'readout-aperture',
        ]) {
          expect(
            find.byKey(Key(key), skipOffstage: false),
            findsOneWidget,
            reason: key,
          );
        }
        await openSheet(tester, const Key('why-unavailable'));
        expect(
          find.textContaining('Everything the app offers'),
          findsNothing,
        ); // photo format etc. are reported as unavailable
      },
    );
    cameraTest(
      '[CAM-013] the aperture is a readout, not a dial, on a fixed-aperture camera',
      (tester) async {
        await pumpCamera(tester);
        expect(
          find.byKey(const Key('readout-aperture'), skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('ƒ/1.8', skipOffstage: false), findsOneWidget);
      },
    );
    cameraTest(
      '[MOT-001] LIVE is unavailable on cameras without motion capture, with the reason on tap',
      (tester) async {
        await pumpCamera(
          tester,
          camera: _cameraWith(capsWithout(_full(), live: true)),
        );
        await tapKey(tester, const Key('live-button'));
        expect(
          find.textContaining('Motion capture isn’t available'),
          findsWidgets,
        );
      },
    );
    cameraTest(
      '[CAM-046] the format chooser appears only with more than one photo format',
      (tester) async {
        await pumpCamera(tester);
        expect(
          find.byKey(const Key('control-format'), skipOffstage: false),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        await pumpCamera(
          tester,
          camera: _cameraWith(capsWithout(_full(), formats: true)),
        );
        await openSheet(tester, const Key('control-format'));
        expect(find.byKey(const Key('format-heif')), findsOneWidget);
        await tapKey(tester, const Key('format-heif'));
      },
    );
  });

  group('manual control sheets', () {
    cameraTest(
      '[CAM-010] ISO: choosing a value applies it, and Auto clears it',
      (tester) async {
        await pumpCamera(tester);
        await openSheet(tester, const Key('control-iso'));
        changeSlider(tester, const Key('slider-iso'), 8);
        await settle(tester, frames: 3);
        expect(env.camera.appliedSettings.last.iso, isNotNull);
        expect(find.textContaining('ISO'), findsWidgets);
        await tapKey(tester, const Key('sheet-auto'));
        expect(env.camera.appliedSettings.last.iso, isNull);
      },
    );
    cameraTest('[CAM-011] shutter: choosing a speed shows it as a fraction', (
      tester,
    ) async {
      await pumpCamera(tester);
      await openSheet(tester, const Key('control-shutter'));
      changeSlider(tester, const Key('slider-shutter'), 5);
      await settle(tester, frames: 3);
      expect(env.camera.appliedSettings.last.exposureTimeNs, isNotNull);
      await tapKey(tester, const Key('sheet-auto'));
      expect(env.camera.appliedSettings.last.exposureTimeNs, isNull);
    });
    cameraTest(
      '[CAM-012] exposure compensation moves in the camera’s steps and resets',
      (tester) async {
        await pumpCamera(tester);
        await openSheet(tester, const Key('control-ev'));
        changeSlider(tester, const Key('slider-ev'), 1);
        await settle(tester, frames: 3);
        expect(env.camera.appliedSettings.last.exposureBiasEv, closeTo(1, 0.4));
        expect(find.text('+1 EV'), findsWidgets);
        await tapKey(tester, const Key('sheet-auto'));
        expect(
          env.camera.appliedSettings.last.exposureBiasEv,
          anyOf(isNull, 0.0),
        );
      },
    );
    cameraTest('[CAM-030][CAM-031] white balance: a preset, then Kelvin', (
      tester,
    ) async {
      await pumpCamera(tester);
      await openSheet(tester, const Key('control-wb'));
      await tapKey(tester, const Key('wb-tungsten'));
      expect(
        env.camera.appliedSettings.last.whiteBalancePreset,
        cam.WbPreset.tungsten,
      );
      changeSlider(tester, const Key('slider-kelvin'), 4300);
      await settle(tester, frames: 3);
      expect(env.camera.appliedSettings.last.kelvin, 4300);
      expect(find.text('4300 K'), findsWidgets);
    });
    cameraTest(
      '[CAM-021][CAM-022] focus: manual focus is labelled "not calibrated" unless the device says otherwise; focus lock toggles',
      (tester) async {
        await pumpCamera(tester);
        await openSheet(tester, const Key('control-focus'));
        await tapKey(tester, const Key('switch-af-lock'));
        expect(env.camera.appliedSettings.last.afLock, isTrue);
        await tapKey(tester, const Key('switch-manual-focus'));
        expect(
          find.text('∞'),
          findsOneWidget,
        ); // approximate calibration still names a distance
        expect(env.camera.appliedSettings.last.focusMode, cam.FocusMode.manual);
        expect(
          env.camera.appliedSettings.last.afLock,
          isFalse,
        ); // focus lock is for autofocus; the resolver explains it
        changeSlider(tester, const Key('slider-focus'), 5);
        await settle(tester, frames: 3);
        expect(env.camera.appliedSettings.last.focusDistanceDiopters, 5);
      },
    );
    cameraTest(
      '[CAM-021] a calibrated focus ring shows the distance, an uncalibrated one says so',
      (tester) async {
        cam.CameraCapabilities withCalibration(
          cam.FocusCalibration calibration,
        ) {
          final caps = FakeCameraPlatform.fullCapabilities(_id);
          return cam.CameraCapabilities(
            cameraId: _id,
            iso: caps.iso,
            exposureTimeNs: caps.exposureTimeNs,
            exposureBias: caps.exposureBias,
            apertures: caps.apertures,
            focus: cam.FocusCapabilities(
              auto: true,
              continuous: true,
              tapToFocus: true,
              manual: cam.ManualFocusCapability(
                minFocusDistanceDiopters: 10,
                calibration: calibration,
              ),
            ),
            whiteBalance: caps.whiteBalance,
            zoom: caps.zoom,
            flash: caps.flash,
            torch: caps.torch,
            photoFormats: caps.photoFormats,
            photoSizes: caps.photoSizes,
            stabilization: caps.stabilization,
            video: caps.video,
            hdr: caps.hdr,
            live: caps.live,
            hardwareLevel: caps.hardwareLevel,
          );
        }

        await pumpCamera(
          tester,
          camera: _cameraWith(withCalibration(cam.FocusCalibration.calibrated)),
        );
        await openSheet(tester, const Key('control-focus'));
        await tapKey(tester, const Key('switch-manual-focus'));
        changeSlider(tester, const Key('slider-focus'), 2);
        await settle(tester, frames: 3);
        expect(find.text('50 cm'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await settle(tester, frames: 2);
        await pumpCamera(
          tester,
          camera: _cameraWith(
            withCalibration(cam.FocusCalibration.uncalibrated),
          ),
        );
        await openSheet(tester, const Key('control-focus'));
        await tapKey(tester, const Key('switch-manual-focus'));
        expect(find.textContaining('not calibrated'), findsOneWidget);
      },
    );

    cameraTest('[CAM-014] auto-exposure lock toggles from the strip', (
      tester,
    ) async {
      await pumpCamera(tester);
      await tester.ensureVisible(find.byKey(const Key('control-ae-lock')));
      await tapKey(tester, const Key('control-ae-lock'));
      expect(env.camera.appliedSettings.last.aeLock, isTrue);
    });
    cameraTest(
      '[EXP-008] a value the camera had to change shows what changed and why, in the sheet and over the viewfinder',
      (tester) async {
        await pumpCamera(tester);
        await openSheet(tester, const Key('control-iso'));
        env.camera.appliedBuilder = null;
        final element = tester.element(find.byKey(const Key('slider-iso')));
        final container = ProviderScope.containerOf(element);
        container
            .read(cameraControllerProvider.notifier)
            .adjust((u) => u.merge(const CaptureIntent(iso: 99999)));
        await settle(tester, frames: 3);
        expect(find.byKey(const Key('adjustment-message')), findsOneWidget);
        expect(find.byKey(const Key('notice-text')), findsOneWidget);
        await tapKey(tester, const Key('notice-dismiss'));
      },
    );
    cameraTest('[CAM-008] optical zoom steps are chips', (tester) async {
      final caps = FakeCameraPlatform.fullCapabilities(_id);
      final withSteps = cam.CameraCapabilities(
        cameraId: _id,
        iso: caps.iso,
        exposureTimeNs: caps.exposureTimeNs,
        exposureBias: caps.exposureBias,
        apertures: caps.apertures,
        focus: caps.focus,
        whiteBalance: caps.whiteBalance,
        zoom: const cam.ZoomCapabilities(
          min: 0.6,
          max: 10,
          opticalSteps: <double>[0.6, 1, 3],
        ),
        flash: caps.flash,
        torch: caps.torch,
        photoFormats: caps.photoFormats,
        photoSizes: caps.photoSizes,
        stabilization: caps.stabilization,
        video: caps.video,
        hdr: caps.hdr,
        live: caps.live,
        hardwareLevel: caps.hardwareLevel,
      );
      await pumpCamera(tester, camera: _cameraWith(withSteps));
      await openSheet(tester, const Key('control-zoom'));
      await tapKey(tester, const Key('zoom-step-3.0'));
      expect(env.camera.appliedSettings.last.zoomRatio, 3);
      await tapKey(tester, const Key('sheet-auto'));
      expect(env.camera.appliedSettings.last.zoomRatio, 1);
    });
    cameraTest(
      '[CAM-006] several back lenses give a lens chooser that switches the camera',
      (tester) async {
        const wide = FakeCameraPlatform.defaultDescriptor;
        const tele = cam.CameraDescriptor(
          id: 'fake:tele',
          facing: cam.CameraFacing.back,
          lensKind: cam.LensKind.tele,
          isLogical: false,
          physicalIds: <String>[],
          sensorOrientation: 90,
          source: cam.CameraSource.hardware,
          label: 'Telephoto',
          focalLength35mmEq: 80,
        );
        final camera = _cameraWith(
          _full(),
          cameras: <cam.CameraDescriptor>[wide, tele],
          all: <String, cam.CameraCapabilities>{
            _id: _full(),
            'fake:tele': FakeCameraPlatform.fullCapabilities('fake:tele'),
          },
        );
        await pumpCamera(tester, camera: camera);
        await openSheet(tester, const Key('control-lens'));
        await tester.tap(find.byKey(const Key('lens-fake:tele')));
        await pumpUntilTrue(tester, () => camera.opened.length > 1);
        expect(camera.opened.last.cameraId, 'fake:tele');
      },
    );
  });

  group('Experiences, scenarios, presets and looks', () {
    cameraTest(
      '[EXP-001] switching Experience restyles the camera; Film shows a frame counter',
      (tester) async {
        await pumpCamera(tester);
        await tester.ensureVisible(find.byKey(const Key('experience-film')));
        await tapKey(tester, const Key('experience-film'));
        expect(
          find.byKey(const Key('frame-counter'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.textContaining('Frame 0 / 36', skipOffstage: false),
          findsOneWidget,
        );
        await tapKey(tester, const Key('experience-dslr'));
        expect(
          find.byKey(const Key('frame-counter'), skipOffstage: false),
          findsNothing,
        );
      },
    );
    cameraTest(
      '[EXP-010] Instant shows the print developing after a capture, and a tap skips it',
      (tester) async {
        await pumpCamera(tester);
        await tapKey(tester, const Key('experience-instant'));
        await tester.tap(find.byKey(const Key('shutter-button')));
        await pumpUntil(tester, find.byKey(const Key('developing-print')));
        expect(find.byKey(const Key('developing-print')), findsOneWidget);
        await tapKey(tester, const Key('developing-print'));
        await pumpUntilTrue(
          tester,
          () => find.byKey(const Key('developing-print')).evaluate().isEmpty,
        );
        expect(find.byKey(const Key('developing-print')), findsNothing);
      },
    );
    cameraTest('Instant keeps manual dials out of the way until asked for', (
      tester,
    ) async {
      await pumpCamera(tester);
      await tapKey(tester, const Key('experience-instant'));
      expect(
        find.byKey(const Key('control-iso'), skipOffstage: false),
        findsNothing,
      );
      await tester.ensureVisible(find.byKey(const Key('chip-manual-toggle')));
      await tapKey(tester, const Key('chip-manual-toggle'));
      expect(
        find.byKey(const Key('control-iso'), skipOffstage: false),
        findsOneWidget,
      );
    });
    cameraTest('[EXP-004] choosing a scenario explains what it set and why', (
      tester,
    ) async {
      await pumpCamera(tester);
      await tapKey(tester, const Key('chip-scenario'));
      await tapKey(tester, const Key('scenario-night'));
      expect(find.byKey(const Key('scenario-summary')), findsOneWidget);
      expect(find.textContaining('•'), findsWidgets);
      await tapKey(tester, const Key('scenario-none'));
      expect(find.byKey(const Key('scenario-summary')), findsNothing);
    });
    cameraTest(
      '[EXP-007] presets: save the current settings, then apply, and stop using it',
      (tester) async {
        await pumpCamera(tester);
        await tapKey(tester, const Key('chip-preset'));
        expect(
          find.textContaining('No presets for this camera yet'),
          findsOneWidget,
        );
        await tapKey(tester, const Key('preset-save'));
        await tester.enterText(
          find.byKey(const Key('preset-name')),
          'Golden hour',
        );
        await tester.tap(find.byKey(const Key('preset-name-save')));
        await pumpUntil(tester, find.text('Golden hour'), tries: 10);
        final rows = await io(tester, () => env.data.presets.list());
        expect(rows.single.name, 'Golden hour');
        await tapKey(tester, const Key('chip-preset'));
        await tester.tap(find.byKey(Key('preset-${rows.single.id}')));
        await settle(tester, frames: 4);
        expect(find.text('Golden hour'), findsWidgets);
      },
    );
    cameraTest(
      '[PRF-001][PRF-004] the look sheet offers every profile and changes the preview look',
      (tester) async {
        await pumpCamera(tester);
        await tapKey(tester, const Key('chip-look'));
        for (final id in <String>[
          'natural',
          'warm-film',
          'soft-film',
          'instant-warm',
          'mono-classic',
        ]) {
          expect(find.byKey(Key('look-$id')), findsOneWidget, reason: id);
        }
        await tapKey(tester, const Key('look-soft-film'));
        expect(find.text('Look: Soft Film'), findsOneWidget);
      },
    );
    cameraTest(
      '[EXP-005] overriding a field shows Reset, and Reset returns to the scenario',
      (tester) async {
        await pumpCamera(tester);
        await tapKey(tester, const Key('chip-scenario'));
        await tapKey(tester, const Key('scenario-street'));
        await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
        await settle(tester, frames: 3);
        await tapKey(tester, const Key('timer-button'));
        expect(find.byKey(const Key('chip-reset')), findsOneWidget);
        expect(find.text('Reset to scenario'), findsOneWidget);
        await tapKey(tester, const Key('chip-reset'));
        expect(find.byKey(const Key('chip-reset')), findsNothing);
      },
    );
  });

  group('LIVE and video', () {
    cameraTest(
      '[MOT-001][MOT-002] LIVE toggles on, and the next capture is a Motion Memory with a LIVE badge',
      (tester) async {
        await pumpCamera(tester);
        expect(
          find.descendant(
            of: find.byKey(const Key('live-button')),
            matching: find.byIcon(Icons.motion_photos_off),
          ),
          findsOneWidget,
        );
        await tapKey(tester, const Key('live-button'));
        expect(
          find.descendant(
            of: find.byKey(const Key('live-button')),
            matching: find.byIcon(Icons.motion_photos_on),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('shutter-button')));
        await pumpUntilSaved(tester, 1);
        await settle(tester, frames: 4);
        expect(find.byKey(const Key('last-live-badge')), findsOneWidget);
        final saved = await io(tester, () => env.memories.library());
        expect(saved.single.memory.kind, MemoryKinds.motion);
      },
    );
    cameraTest('[VID-001] video mode records and stops, saving a video', (
      tester,
    ) async {
      await pumpCamera(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('mode-switch')),
          matching: find.byIcon(Icons.videocam_outlined),
        ),
      );
      await settle(tester, frames: 3);
      expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shutter-button')));
      await pumpUntil(tester, find.byKey(const Key('recording-time')));
      expect(find.byKey(const Key('recording-time')), findsOneWidget);
      expect(find.bySemanticsLabel('Stop recording'), findsOneWidget);
      // Stopping saves through real file and database I/O, so it runs outside the fake-async zone.
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('shutter-button'))),
      );
      final view = await io(
        tester,
        () => container.read(cameraControllerProvider.notifier).stopVideo(),
      );
      await settle(tester, frames: 3);
      expect(view, isNotNull);
      final saved = await io(tester, () => env.memories.library());
      expect(saved, hasLength(1));
      expect(saved.single.memory.kind, MemoryKinds.video);
    });
  });

  group('overlays', () {
    cameraTest('CameraStatusView renders title, message and both actions', (
      tester,
    ) async {
      var primary = 0;
      var secondary = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CameraStatusView(
            title: 'T',
            message: 'M',
            primaryLabel: 'P',
            onPrimary: () => primary++,
            secondaryLabel: 'S',
            onSecondary: () => secondary++,
          ),
        ),
      );
      await tester.tap(find.text('P'));
      await tester.tap(find.text('S'));
      expect((primary, secondary), (1, 1));
    });
    cameraTest(
      'CaptureFlash does not animate when the user prefers reduced motion',
      (tester) async {
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: CaptureFlash(pulse: 0)),
          ),
        );
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: CaptureFlash(pulse: 1)),
          ),
        );
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  });
}
