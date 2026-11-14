import 'dart:convert';
import 'dart:io';

import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/domain/camera/capabilities.dart' as dom;
import 'package:doro_cam/domain/camera/capture_intent.dart' as dom;
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:doro_cam/domain/experience/scenario.dart';
import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/camera/application/camera_state.dart';
import 'package:doro_cam/platform/adapters.dart';
import 'package:doro_camera/doro_camera.dart' as cam;
import 'package:doro_camera/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

void main() {
  late UiEnv env;
  late ProviderContainer container;

  CameraController controller() =>
      container.read(cameraControllerProvider.notifier);
  CameraState state() => container.read(cameraControllerProvider);

  Future<void> start({FileWritingCamera? camera}) async {
    env = await UiEnv.create(camera: camera);
    container = ProviderContainer(overrides: env.overrides());
    // Keep the controller alive for the whole test.
    container.listen(cameraControllerProvider, (_, _) {});
  }

  Future<void> stop() async {
    container.dispose();
    await env.dispose();
  }

  group('opening the camera', () {
    test('[CAM-001] opens the back camera with its capabilities and resolves the Experience defaults', () async {
      await start();
      await controller().open();
      expect(state().phase, CameraPhase.ready);
      expect(state().camera!.facing, cam.CameraFacing.back);
      expect(
        env.camera.opened.single.cameraId,
        FakeCameraPlatform.defaultDescriptor.id,
      );
      expect(state().settings!.aspect, '3:2'); // Mirrorless default
      expect(state().settings!.grid, isTrue);
      expect(state().caps.hasManualIso, isTrue);
      expect(env.camera.appliedSettings, isNotEmpty);
      await stop();
    });

    test('[CAM-052] without camera permission it asks, and explains when it is refused', () async {
      await start(
        camera: FileWritingCamera(
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.denied,
            microphone: cam.PermissionStatus.denied,
          ),
        ),
      );
      await controller().open();
      expect(state().phase, CameraPhase.needsPermission);
      expect(env.camera.opened, isEmpty);

      env.camera.permissionsAfterRequest = const cam.CameraPermissions(
        camera: cam.PermissionStatus.granted,
        microphone: cam.PermissionStatus.denied,
      );
      await controller().requestPermissions();
      expect(state().phase, CameraPhase.ready);
      await stop();
    });

    test('[CAM-052] a permanent refusal sends the user to the system settings instead of asking again', () async {
      await start(
        camera: FileWritingCamera(
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.denied,
            microphone: cam.PermissionStatus.denied,
            cameraPermanentlyDenied: true,
          ),
        ),
      );
      await controller().open();
      await controller().requestPermissions();
      expect(env.camera.calls, contains('openAppSettings'));
      expect(env.camera.calls.where((c) => c == 'requestPermissions'), isEmpty);
      expect(state().phase, CameraPhase.needsPermission);
      await stop();
    });

    test('[CAM-052] the microphone is optional: the camera opens without it and LIVE audio is off', () async {
      await start(
        camera: FileWritingCamera(
          permissions: const cam.CameraPermissions(
            camera: cam.PermissionStatus.granted,
            microphone: cam.PermissionStatus.denied,
          ),
        ),
      );
      await controller().open();
      expect(state().phase, CameraPhase.ready);
      expect(env.camera.opened.single.audio, isFalse);
      await stop();
    });

    test('reports a device without cameras', () async {
      await start(camera: FileWritingCamera(cameras: <cam.CameraDescriptor>[]));
      await controller().open();
      expect(state().phase, CameraPhase.noCamera);
      await stop();
    });

    test('[CAM-053] another app holding the camera is a plain-language failure that can be retried', () async {
      await start();
      env.camera.error = const cam.CameraException('camera_in_use');
      await controller().open();
      expect(state().phase, CameraPhase.failed);
      expect(state().errorMessage, contains('Another app is using the camera'));
      env.camera.error = null;
      await controller().open();
      expect(state().phase, CameraPhase.ready);
      await stop();
    });

    test('an unexpected error is reported rather than thrown', () async {
      await start();
      env.camera.error = StateError('boom');
      await controller().open();
      expect(state().phase, CameraPhase.failed);
      expect(state().errorMessage, contains('boom'));
      await stop();
    });

    test('[CAM-053] suspend and resume go to the native session; closing the controller closes the camera', () async {
      await start();
      await controller().open();
      await controller().suspend();
      await controller().resume();
      expect(
        env.camera.calls,
        containsAll(<String>['suspendSession', 'resumeSession']),
      );
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(env.camera.openSessions, isEmpty);
      await env.dispose();
    });
  });

  group('settings and Experiences', () {
    test('[CAM-010][EXP-008] a manual ISO outside the device range is clamped, applied, and explained', () async {
      await start();
      await controller().open();
      controller().adjust((u) => u.merge(const dom.CaptureIntent(iso: 99999)));
      expect(state().settings!.iso, 3200);
      expect(
        state().result!.adjustmentFor(dom.IntentField.iso)!.message,
        isNotEmpty,
      );
      await Future<void>.delayed(Duration.zero);
      expect(env.camera.appliedSettings.last.iso, 3200);
      await stop();
    });

    test('[EXP-001] choosing an Experience restores its defaults and is remembered for the next launch', () async {
      await start();
      await controller().open();
      await controller().setExperience(Experiences.instant);
      expect(state().settings!.aspect, '1:1');
      expect(state().settings!.profileId, 'instant-warm');
      expect(
        await env.data.settings.read(CameraSettingKeys.experience),
        'instant',
      );

      container.dispose();
      container = ProviderContainer(overrides: env.overrides());
      container.listen(cameraControllerProvider, (_, _) {});
      await controller().open();
      expect(state().experience.id, ExperienceId.instant);
      await stop();
    });

    test('[MOT-001] LIVE is remembered per Experience', () async {
      await start();
      await controller().open();
      await controller().setLive(enabled: true);
      expect(state().liveOn, isTrue);
      expect(env.camera.calls, contains('setLive:true'));
      await controller().setExperience(Experiences.film);
      expect(state().settings!.live, isFalse); // film has its own setting
      await controller().setExperience(Experiences.mirrorless);
      expect(state().settings!.live, isTrue);
      await stop();
    });

    test('[EXP-004] a scenario applies recommended settings; resetting clears the user’s overrides', () async {
      await start();
      await controller().open();
      controller().setScenario(Scenarios.night);
      final fromScenario = state().settings!;
      expect(state().scenario!.id, ScenarioId.night);
      controller().adjust((u) => u.merge(const dom.CaptureIntent(iso: 100)));
      expect(state().settings!.iso, 100);
      controller().resetOverrides();
      expect(state().settings!.iso, fromScenario.iso);
      controller().setScenario(null);
      expect(state().scenario, isNull);
      await stop();
    });

    test('[EXP-007] saving the current settings stores a preset that can be applied again', () async {
      await start();
      await controller().open();
      controller().adjust(
        (u) => u.merge(const dom.CaptureIntent(iso: 400, timerSeconds: 3)),
      );
      await controller().saveAsPreset('Dim room');
      final rows = await env.data.presets.list();
      expect(rows.single.name, 'Dim room');
      expect(rows.single.experienceId, 'mirrorless');
      expect(jsonDecode(rows.single.intentJson), containsPair('iso', 400));
      await stop();
    });

    test('[EXP-003] an authentic Experience refuses to be overridden and rejects shooting past the end of the roll', () async {
      await start();
      await env.data.settings.write(CameraSettingKeys.frames, '36');
      await controller().open();
      await controller().setExperience(Experiences.film);
      await controller().setAuthentic(value: true);
      expect(state().result!.rejection, isNotNull);
      final saved = await controller().capture();
      expect(saved, isNull);
      expect(state().notice, contains('roll of 36 frames is finished'));
      expect(env.camera.captures, isEmpty);
      await stop();
    });

    test('[CAM-005] capabilities the camera lacks give an empty availability, and the resolver still produces valid settings', () async {
      final bare = FileWritingCamera(
        capabilities: <String, cam.CameraCapabilities>{
          FakeCameraPlatform.defaultDescriptor.id: capsWithout(
            FakeCameraPlatform.fullCapabilities(
              FakeCameraPlatform.defaultDescriptor.id,
            ),
            iso: true,
            shutter: true,
            bias: true,
            manualFocus: true,
            autoFocus: true,
            tapFocus: true,
            wbPresets: true,
            kelvin: true,
            zoom: true,
            flash: true,
            torch: true,
            live: true,
          ),
        },
      );
      await start(camera: bare);
      await controller().open();
      controller().adjust(
        (u) => u.merge(
          const dom.CaptureIntent(
            iso: 800,
            exposureTimeNs: 1000000,
            zoom: 4,
            flash: dom.FlashMode.on,
            live: true,
          ),
        ),
      );
      expect(state().settings!.iso, isNull);
      expect(state().settings!.zoom, 1);
      expect(state().settings!.flash, dom.FlashMode.off);
      expect(state().settings!.live, isFalse);
      await stop();
    });

    test('[CAM-050] a control the camera ignores three times is disabled with an explanation', () async {
      await start();
      await controller().open();
      env.camera.appliedBuilder = null;
      for (var i = 0; i < 3; i++) {
        env.camera.nextCaptureResult = _result(
          env,
          mismatches: <String>['iso'],
        );
        await controller().capture();
      }
      expect(state().disabled, contains(dom.IntentField.iso));
      expect(state().notice, contains('ignored a manual setting'));
      await stop();
    });

    test(
      '[NFR-012] a serious thermal state turns LIVE off with a reason',
      () async {
        await start();
        await controller().open();
        await controller().setLive(enabled: true);
        env.camera.emit(
          cam.SessionEvent(
            sessionId: state().session!.sessionId,
            kind: cam.SessionEventKind.thermal,
            thermal: cam.ThermalState.serious,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(state().settings!.live, isFalse);
        expect(state().notice, contains('LIVE was turned off'));
        await stop();
      },
    );

    test('a native error event is shown as a notice', () async {
      await start();
      await controller().open();
      env.camera.emit(
        cam.SessionEvent(
          sessionId: state().session!.sessionId,
          kind: cam.SessionEventKind.error,
          errorMessage: 'The camera was interrupted.',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(state().notice, 'The camera was interrupted.');
      controller().dismissNotice();
      expect(state().notice, isNull);
      await stop();
    });
  });

  group('lenses and focus', () {
    test('[CAM-002] flipping to the front camera and back', () async {
      const front = cam.CameraDescriptor(
        id: 'fake:front',
        facing: cam.CameraFacing.front,
        lensKind: cam.LensKind.front,
        isLogical: false,
        physicalIds: <String>[],
        sensorOrientation: 270,
        source: cam.CameraSource.hardware,
        label: 'Front camera',
      );
      await start(
        camera: FileWritingCamera(
          cameras: <cam.CameraDescriptor>[
            FakeCameraPlatform.defaultDescriptor,
            front,
          ],
          capabilities: <String, cam.CameraCapabilities>{
            FakeCameraPlatform.defaultDescriptor.id:
                FakeCameraPlatform.fullCapabilities(
                  FakeCameraPlatform.defaultDescriptor.id,
                ),
            front.id: FakeCameraPlatform.fullCapabilities(front.id),
          },
        ),
      );
      await controller().open();
      await controller().flip();
      expect(state().camera!.id, 'fake:front');
      expect(env.camera.openSessions.length, 1); // the first session was closed
      await controller().flip();
      expect(state().camera!.id, FakeCameraPlatform.defaultDescriptor.id);
      await stop();
    });

    test('flipping on a one-camera device says so', () async {
      await start();
      await controller().open();
      await controller().flip();
      expect(state().notice, 'This device has only one camera.');
      await stop();
    });

    test(
      '[CAM-006] selecting another lens reopens the session on it',
      () async {
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
        await start(
          camera: FileWritingCamera(
            cameras: <cam.CameraDescriptor>[
              FakeCameraPlatform.defaultDescriptor,
              tele,
            ],
            capabilities: <String, cam.CameraCapabilities>{
              FakeCameraPlatform.defaultDescriptor.id:
                  FakeCameraPlatform.fullCapabilities(
                    FakeCameraPlatform.defaultDescriptor.id,
                  ),
              tele.id: FakeCameraPlatform.fullCapabilities(tele.id),
            },
          ),
        );
        await controller().open();
        await controller().selectCamera(tele);
        expect(state().camera!.id, 'fake:tele');
        await controller().selectCamera(tele); // already selected: no-op
        expect(env.camera.opened.length, 2);
        await stop();
      },
    );

    test('[CAM-020] tap-to-focus reaches the camera and shows a focus point; unsupported cameras ignore it', () async {
      await start();
      await controller().open();
      await controller().tapToFocus(0.4, 0.6);
      expect(env.camera.focusPoints, <(double, double)>[(0.4, 0.6)]);
      expect(state().focusPoint, (0.4, 0.6));
      controller().clearFocusPoint();
      expect(state().focusPoint, isNull);
      await stop();

      await start(
        camera: FileWritingCamera(
          capabilities: <String, cam.CameraCapabilities>{
            FakeCameraPlatform.defaultDescriptor.id: capsWithout(
              FakeCameraPlatform.fullCapabilities(
                FakeCameraPlatform.defaultDescriptor.id,
              ),
              tapFocus: true,
            ),
          },
        ),
      );
      await controller().open();
      await controller().tapToFocus(0.5, 0.5);
      expect(env.camera.focusPoints, isEmpty);
      await stop();
    });

    test('setting the mode is ignored while recording', () async {
      await start();
      await controller().open();
      controller().setMode(CaptureMode.video);
      expect(state().mode, CaptureMode.video);
      await controller().startVideo();
      controller().setMode(CaptureMode.photo);
      expect(state().mode, CaptureMode.video);
      await controller().stopVideo();
      await stop();
    });
  });

  group('capture', () {
    test('[MEM-001][CAM-050] a capture is saved durably with the applied settings, all assets and the chosen look', () async {
      await start();
      await controller().open();
      controller().setScenario(Scenarios.street);
      final view = await controller().capture();
      expect(view, isNotNull);
      expect(view!.memory.kind, MemoryKinds.photo);
      expect(view.memory.experienceId, 'mirrorless');
      expect(view.memory.profileId, 'natural');
      expect(view.memory.scenario, 'street');
      expect(view.assets.map((a) => a.role).toSet(), <String>{
        AssetRoles.photoOriginal,
        AssetRoles.photoRendered,
        AssetRoles.photoDisplay,
        AssetRoles.thumbnail,
      });
      for (final asset in view.assets) {
        expect(File(asset.localPath!).existsSync(), isTrue, reason: asset.role);
      }
      final capture =
          jsonDecode(view.memory.captureJson) as Map<String, Object?>;
      expect(capture, containsPair('lensKind', 'wide'));
      expect(capture, containsPair('cameraId', 'fake:back'));
      expect(capture['requested'], isA<Map<String, Object?>>());
      expect(state().lastCapture!.memory.id, view.memory.id);
      expect(env.feedback.events, contains('shutter'));
      expect(await env.data.settings.read(CameraSettingKeys.frames), '1');
      expect((await env.memories.library()).length, 1);
      await stop();
    });

    test('[CAM-003] the capture request carries the look as a LUT, the aspect crop and a timestamp', () async {
      await start();
      await controller().open();
      controller().adjust(
        (u) => u.merge(const dom.CaptureIntent(aspect: '1:1')),
      );
      await controller().capture();
      final request = env.camera.captures.single;
      expect(request.render!.profileId, 'natural');
      expect(request.render!.lutSize, 33);
      expect(request.render!.lut!.length, 33 * 33 * 33 * 3);
      expect(
        request.render!.aspectRatio,
        '1:1',
      ); // not native, so the rendition is cropped
      expect(request.timestampEpochMs, isNotNull);
      expect(request.live, isFalse);
      await stop();
    });

    test('[PRF-001] choosing another look changes what the capture is rendered with', () async {
      await start();
      await controller().open();
      controller().setProfile('mono-classic');
      await controller().capture();
      expect(env.camera.captures.single.render!.profileId, 'mono-classic');
      expect(state().lastCapture!.memory.profileId, 'mono-classic');
      await stop();
    });

    test(
      '[MOT-002] a LIVE capture saves a Motion Memory with the clip',
      () async {
        await start();
        await controller().open();
        await controller().setLive(enabled: true);
        final view = await controller().capture();
        expect(view!.memory.kind, MemoryKinds.motion);
        expect(view.asset(AssetRoles.motionClip), isNotNull);
        expect(env.camera.captures.single.live, isTrue);
        await stop();
      },
    );

    test('[PRIV-001] location is left out by default and added only when the setting is on', () async {
      await start();
      await controller().open();
      env.location.fix = const DeviceLocation(
        latitude: 3.139,
        longitude: 101.6869,
        accuracyM: 5,
      );
      var view = await controller().capture();
      expect(view!.memory.lat, isNull);
      expect(env.camera.captures.last.location, isNull);

      await env.data.settings.setCaptureLocation(value: true);
      view = await controller().capture();
      expect(view!.memory.lat, closeTo(3.139, 1e-6));
      expect(
        env.camera.captures.last.location!.longitude,
        closeTo(101.6869, 1e-6),
      );

      env.location.permission = false;
      view = await controller().capture();
      expect(
        view!.memory.lat,
        isNull,
      ); // no permission: no location, and the photo is still taken
      await stop();
    });

    test(
      '[CAM-041] the self-timer counts down before the shutter fires',
      () async {
        await start();
        await controller().open();
        controller().adjust(
          (u) => u.merge(const dom.CaptureIntent(timerSeconds: 3)),
        );
        final seen = <int?>[];
        container.listen(
          cameraControllerProvider,
          (_, next) => seen.add(next.countdown),
        );
        await controller().capture();
        expect(seen.whereType<int>(), <int>[3, 2, 1]);
        expect(state().countdown, isNull);
        expect(env.camera.captures, hasLength(1));
        await stop();
      },
    );

    test('[CAM-051] shutter feedback follows the Experience (Instant makes a sound) and warns on failure', () async {
      await start();
      await controller().open();
      await controller().setExperience(Experiences.instant);
      await controller().capture();
      expect(env.feedback.events, contains('shutter+sound'));
      expect(state().developing, isNotNull); // EXP-010
      controller().finishDeveloping();
      expect(state().developing, isNull);

      env.camera.error = const cam.CameraException('camera_in_use');
      await controller().capture();
      expect(env.feedback.events, contains('warn'));
      await stop();
    });

    test('[CAM-053][NFR-002] a failed capture shows why, loses nothing and can be retried', () async {
      await start();
      await controller().open();
      env.camera.error = const cam.CameraException('storage_full');
      expect(await controller().capture(), isNull);
      expect(state().notice, contains('not enough storage'));
      expect(state().capturing, isFalse);
      env.camera.error = null;
      expect(await controller().capture(), isNotNull);
      expect((await env.memories.library()).length, 1);
      await stop();
    });

    test(
      'a capture that produced no readable file is reported, not saved',
      () async {
        await start();
        await controller().open();
        env.camera.nextCaptureResult = _result(
          env,
          originalPath: '/nonexistent/original.jpg',
        );
        expect(await controller().capture(), isNull);
        expect(state().notice, contains('could not be saved'));
        expect(await env.memories.library(), isEmpty);
        await stop();
      },
    );

    test('capturing twice at once takes one photo', () async {
      await start();
      await controller().open();
      final results = await Future.wait(<Future<MemoryView?>>[
        controller().capture(),
        controller().capture(),
      ]);
      expect(results.whereType<MemoryView>().length, 1);
      await stop();
    });

    test('a capture never starts without an open session', () async {
      await start();
      expect(await controller().capture(), isNull);
      await stop();
    });
  });

  group('video', () {
    test('[VID-001] records and saves a video Memory with the same camera settings', () async {
      await start();
      await controller().open();
      controller().setMode(CaptureMode.video);
      await controller().startVideo();
      expect(state().recording, isTrue);
      expect(env.camera.videos.single.audio, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(state().recordingSeconds, greaterThanOrEqualTo(1));
      final view = await controller().stopVideo();
      expect(view!.memory.kind, MemoryKinds.video);
      expect(view.asset(AssetRoles.videoOriginal), isNotNull);
      expect(state().recording, isFalse);
      await stop();
    });

    test('recording errors are shown and leave the camera usable', () async {
      await start();
      await controller().open();
      env.camera.error = const cam.CameraException(
        'encoder_failed',
        'The video encoder failed.',
      );
      await controller().startVideo();
      expect(state().recording, isFalse);
      expect(state().notice, 'The video encoder failed.');
      expect(await controller().stopVideo(), isNull);
      await stop();
    });
  });

  group('helpers', () {
    test('timezoneFromOffset maps whole-hour offsets to Etc/GMT zones and falls back to UTC', () {
      expect(timezoneFromOffset(Duration.zero), 'UTC');
      expect(timezoneFromOffset(const Duration(hours: 8)), 'Etc/GMT-8');
      expect(timezoneFromOffset(const Duration(hours: -5)), 'Etc/GMT+5');
      expect(timezoneFromOffset(const Duration(hours: 5, minutes: 30)), 'UTC');
    });
  });
}

cam.CaptureResult _result(
  UiEnv env, {
  List<String> mismatches = const <String>[],
  String? originalPath,
}) {
  final dir = env.scratch.sub(
    'result-${DateTime.now().microsecondsSinceEpoch}',
  );
  final jpeg = <int>[
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0,
    1,
    1,
    0,
    0,
    1,
    0,
    1,
    0,
    0,
    0xFF,
    0xD9,
  ];
  File write(String name) => File('${dir.path}/$name')..writeAsBytesSync(jpeg);
  return cam.CaptureResult(
    memoryId: 'x',
    originalPath: originalPath ?? write('original.jpg').path,
    originalMime: 'image/jpeg',
    width: 4000,
    height: 3000,
    orientationDegrees: 0,
    applied: cam.AppliedSettings(iso: 100, mismatches: mismatches),
    capturedAtEpochMs: 1700000000000,
    source: cam.CameraSource.hardware,
    liveIncluded: false,
    mirrored: false,
    renderFailed: false,
    renderedPath: write('rendered.jpg').path,
    thumbnailPath: write('thumb.jpg').path,
    displayPath: write('display.jpg').path,
  );
}
