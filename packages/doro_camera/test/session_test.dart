import 'package:doro_camera/doro_camera.dart';
import 'package:doro_camera/src/messages.g.dart';
import 'package:doro_camera/src/pigeon_camera_platform.dart';
import 'package:doro_camera/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mapping_test.dart' show appliedMessage, fullCapsMessage;

/// Records every call that reaches the "native" side and answers with canned messages.
class RecordingHost extends CameraHostApi {
  final List<String> calls = <String>[];
  Object? failure;
  CameraCapabilitiesMessage capabilities = fullCapsMessage();

  void _enter(String call) {
    calls.add(call);
    final f = failure;
    if (f != null) {
      throw f;
    }
  }

  @override
  Future<PermissionsMessage> checkPermissions() async {
    _enter('checkPermissions');
    return PermissionsMessage(camera: PermissionStatusMessage.granted, microphone: PermissionStatusMessage.denied, cameraPermanentlyDenied: false, microphonePermanentlyDenied: true);
  }

  @override
  Future<PermissionsMessage> requestPermissions(bool camera, bool microphone) async {
    _enter('requestPermissions:$camera,$microphone');
    return PermissionsMessage(camera: PermissionStatusMessage.granted, microphone: PermissionStatusMessage.granted, cameraPermanentlyDenied: false, microphonePermanentlyDenied: false);
  }

  @override
  Future<void> openAppSettings() async => _enter('openAppSettings');

  @override
  Future<List<CameraDescriptorMessage>> listCameras() async {
    _enter('listCameras');
    return <CameraDescriptorMessage>[
      CameraDescriptorMessage(id: '0', facing: CameraFacingMessage.back, lensKind: LensKindMessage.wide, isLogical: false, physicalIds: <String>[], sensorOrientation: 90, source: CameraSourceMessage.hardware, label: 'Back camera'),
    ];
  }

  @override
  Future<CameraCapabilitiesMessage> getCapabilities(String cameraId) async {
    _enter('getCapabilities:$cameraId');
    return capabilities;
  }

  @override
  Future<SessionInfoMessage> openSession(SessionConfigMessage config) async {
    _enter('openSession:${config.cameraId}');
    return SessionInfoMessage(
      sessionId: 5,
      textureId: 77,
      cameraId: config.cameraId,
      previewSize: SizeMessage(width: 1280, height: 720),
      photoSize: SizeMessage(width: 4000, height: 3000),
      photoFormat: config.photoFormat,
      sensorOrientation: 90,
      source: CameraSourceMessage.hardware,
      liveActive: config.live,
      audioActive: false,
    );
  }

  @override
  Future<void> closeSession(int sessionId) async => _enter('closeSession:$sessionId');

  @override
  Future<AppliedSettingsMessage> applySettings(int sessionId, ResolvedCaptureSettingsMessage settings) async {
    _enter('applySettings:$sessionId:${settings.iso}');
    return appliedMessage();
  }

  @override
  Future<void> focusAt(int sessionId, double x, double y) async => _enter('focusAt:$x,$y');

  @override
  Future<void> setLive(int sessionId, bool enabled) async => _enter('setLive:$enabled');

  @override
  Future<CaptureResultMessage> capture(int sessionId, CaptureRequestMessage request) async {
    _enter('capture:${request.memoryId}');
    return CaptureResultMessage(
      memoryId: request.memoryId,
      originalPath: '${request.outputDir}/${request.originalName}',
      originalMime: 'image/jpeg',
      width: 4000,
      height: 3000,
      orientationDegrees: 0,
      applied: appliedMessage(),
      capturedAtEpochMs: 1,
      source: CameraSourceMessage.hardware,
      liveIncluded: false,
      mirrored: false,
      renderFailed: false,
    );
  }

  @override
  Future<void> startVideo(int sessionId, VideoRequestMessage request) async => _enter('startVideo:${request.outputPath}');

  @override
  Future<VideoResultMessage> stopVideo(int sessionId) async {
    _enter('stopVideo');
    return VideoResultMessage(path: '/v.mp4', durationMs: 1000, width: 1280, height: 720, hasAudio: true, bytes: 1, orientationDegrees: 0, mime: 'video/mp4');
  }

  @override
  Future<void> suspendSession(int sessionId) async => _enter('suspendSession');

  @override
  Future<void> resumeSession(int sessionId) async => _enter('resumeSession');
}

AppliedSettings applied({List<String> mismatches = const <String>[]}) => AppliedSettings(mismatches: mismatches);

CaptureResult resultWith(List<String> mismatches) => CaptureResult(
      memoryId: 'm',
      originalPath: '/o',
      originalMime: 'image/jpeg',
      width: 1,
      height: 1,
      orientationDegrees: 0,
      applied: applied(mismatches: mismatches),
      capturedAtEpochMs: 0,
      source: CameraSource.hardware,
      liveIncluded: false,
      mirrored: false,
      renderFailed: false,
    );

const CaptureRequest request = CaptureRequest(memoryId: 'm1', outputDir: '/d', originalName: 'o.jpg', renderedName: 'r.jpg', thumbnailName: 't.jpg', displayName: 'p.jpg');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PigeonCameraPlatform', () {
    late RecordingHost host;
    late PigeonCameraPlatform platform;

    setUp(() {
      host = RecordingHost();
      platform = PigeonCameraPlatform(api: host, listenForEvents: false);
    });

    test('[CAM-004] lists cameras and maps capabilities', () async {
      final cameras = await platform.listCameras();
      expect(cameras.single.label, 'Back camera');
      final caps = await platform.capabilities('0');
      expect(caps.iso, const IntRange(50, 3200));
      expect(host.calls, <String>['listCameras', 'getCapabilities:0']);
    });

    test('[CAM-052] permission calls map the status and pass what to ask for', () async {
      final check = await platform.checkPermissions();
      expect(check.camera, PermissionStatus.granted);
      expect(check.microphone, PermissionStatus.denied);
      expect(check.microphonePermanentlyDenied, isTrue);
      final asked = await platform.requestPermissions(microphone: false);
      expect(asked.microphoneGranted, isTrue);
      await platform.openAppSettings();
      expect(host.calls, <String>['checkPermissions', 'requestPermissions:true,false', 'openAppSettings']);
    });

    test('a full session round trip goes through the host with mapped types', () async {
      final info = await platform.openSession(const SessionConfig(cameraId: '0', live: true));
      expect(info.sessionId, 5);
      expect(info.textureId, 77);
      expect(info.liveActive, isTrue);
      final settings = await platform.applySettings(5, const ResolvedCaptureSettings(iso: 400));
      expect(settings.iso, 400);
      await platform.focusAt(5, 0.5, 0.25);
      await platform.setLive(5, enabled: false);
      final result = await platform.capture(5, request);
      expect(result.originalPath, '/d/o.jpg');
      await platform.startVideo(5, const VideoRequest(outputPath: '/v.mp4'));
      expect((await platform.stopVideo(5)).path, '/v.mp4');
      await platform.suspendSession(5);
      await platform.resumeSession(5);
      await platform.closeSession(5);
      expect(host.calls, <String>[
        'openSession:0',
        'applySettings:5:400',
        'focusAt:0.5,0.25',
        'setLive:false',
        'capture:m1',
        'startVideo:/v.mp4',
        'stopVideo',
        'suspendSession',
        'resumeSession',
        'closeSession:5',
      ]);
    });

    test('every native PlatformException becomes a typed CameraException on every call', () async {
      host.failure = PlatformException(code: 'camera_in_use', message: 'busy');
      final calls = <Future<Object?>>[
        platform.checkPermissions(),
        platform.requestPermissions(),
        platform.openAppSettings(),
        platform.listCameras(),
        platform.capabilities('0'),
        platform.openSession(const SessionConfig(cameraId: '0')),
        platform.closeSession(1),
        platform.applySettings(1, const ResolvedCaptureSettings()),
        platform.focusAt(1, 0, 0),
        platform.setLive(1, enabled: true),
        platform.capture(1, request),
        platform.startVideo(1, const VideoRequest(outputPath: '/v')),
        platform.stopVideo(1),
        platform.suspendSession(1),
        platform.resumeSession(1),
      ];
      for (final call in calls) {
        await expectLater(call, throwsA(isA<CameraException>().having((e) => e.code, 'code', 'camera_in_use')));
      }
    });

    test('[CAM-053] events pushed by native reach the stream mapped', () async {
      final events = <SessionEvent>[];
      final sub = platform.sessionEvents.listen(events.add);
      platform.handleEvent(SessionEventMessage(sessionId: 5, kind: SessionEventKindMessage.interrupted, errorCode: 'camera_in_use'));
      platform.handleEvent(SessionEventMessage(sessionId: 5, kind: SessionEventKindMessage.resumed));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events.map((e) => e.kind), <SessionEventKind>[SessionEventKind.interrupted, SessionEventKind.resumed]);
      expect(events.first.errorCode, 'camera_in_use');
    });
  });

  group('DoroCamera and CameraSession', () {
    late FakeCameraPlatform fake;
    late DoroCamera camera;

    setUp(() {
      fake = FakeCameraPlatform();
      camera = DoroCamera(platform: fake);
    });

    test('[CAM-004] capabilities are cached per instance until refreshed', () async {
      final first = await camera.capabilities('fake:back');
      final second = await camera.capabilities('fake:back');
      expect(identical(first, second), isTrue);
      expect(fake.calls.where((c) => c.startsWith('capabilities')), hasLength(1));
      fake.capabilitiesById['fake:back'] = FakeCameraPlatform.fullCapabilities('fake:back').copyWith(iso: () => null);
      expect((await camera.capabilities('fake:back')).iso, isNotNull);
      expect((await camera.capabilities('fake:back', refresh: true)).iso, isNull);
    });

    test('permissions, settings and camera listing delegate to the platform', () async {
      expect((await camera.checkPermissions()).cameraGranted, isTrue);
      fake.permissionsAfterRequest = const CameraPermissions(camera: PermissionStatus.denied, microphone: PermissionStatus.denied, cameraPermanentlyDenied: true);
      expect((await camera.requestPermissions()).cameraNeedsSettings, isTrue);
      await camera.openAppSettings();
      expect((await camera.listCameras()).single.id, 'fake:back');
      expect((await camera.ping('hi')).echo, 'hi');
      expect(fake.calls, containsAll(<String>['checkPermissions', 'requestPermissions', 'openAppSettings', 'listCameras']));
    });

    test('[CAM-052] opening without permission fails with a typed error', () async {
      fake.permissions = const CameraPermissions(camera: PermissionStatus.denied, microphone: PermissionStatus.granted);
      await expectLater(camera.open(const SessionConfig(cameraId: 'fake:back')), throwsA(isA<CameraException>().having((e) => e.code, 'code', 'permission_denied')));
      fake.permissions = const CameraPermissions(camera: PermissionStatus.restricted, microphone: PermissionStatus.granted);
      await expectLater(camera.open(const SessionConfig(cameraId: 'fake:back')), throwsA(isA<CameraException>().having((e) => e.code, 'code', 'permission_restricted')));
    });

    test('an open session exposes its texture and forwards every call', () async {
      final session = await camera.open(const SessionConfig(cameraId: 'fake:back', live: true));
      expect(session.textureId, 1001);
      expect(session.sessionId, 1);
      expect(session.info.liveActive, isTrue);
      expect(session.state, SessionState.previewing);
      final applied = await session.apply(const ResolvedCaptureSettings(iso: 800));
      expect(applied.iso, 800);
      expect(session.lastApplied!.iso, 800);
      await session.focusAt(0.3, 0.6);
      await session.setLive(enabled: false);
      final result = await session.capture(request);
      expect(result.originalPath, '/d/o.jpg');
      await session.startVideo(const VideoRequest(outputPath: '/v.mp4', size: CameraSize(1920, 1080)));
      final video = await session.stopVideo();
      expect(video.width, 1920);
      await session.suspend();
      await session.resume();
      expect(fake.focusPoints.single, (0.3, 0.6));
      expect(fake.calls, containsAllInOrder(<String>['openSession', 'applySettings', 'focusAt', 'setLive:false', 'capture', 'startVideo', 'stopVideo', 'suspendSession', 'resumeSession']));
      await session.close();
    });

    test('[CAM-053] session events are filtered by id and update the state and last applied settings', () async {
      final a = await camera.open(const SessionConfig(cameraId: 'fake:back'));
      final b = await camera.open(const SessionConfig(cameraId: 'fake:back'));
      final seen = <SessionEvent>[];
      final sub = a.events.listen(seen.add);
      fake
        ..emit(SessionEvent(sessionId: a.sessionId, kind: SessionEventKind.state, state: SessionState.suspended))
        ..emit(SessionEvent(sessionId: b.sessionId, kind: SessionEventKind.state, state: SessionState.recording))
        ..emit(SessionEvent(sessionId: a.sessionId, kind: SessionEventKind.applied, applied: const AppliedSettings(iso: 123)))
        ..emit(SessionEvent(sessionId: a.sessionId, kind: SessionEventKind.error, errorCode: 'camera_in_use'));
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((e) => e.kind), <SessionEventKind>[SessionEventKind.state, SessionEventKind.applied, SessionEventKind.error]);
      expect(a.state, SessionState.suspended);
      expect(b.state, SessionState.recording);
      expect(a.lastApplied!.iso, 123);
      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('close is idempotent, closes the native session and makes later calls fail loudly', () async {
      final session = await camera.open(const SessionConfig(cameraId: 'fake:back'));
      await session.close();
      await session.close();
      expect(fake.calls.where((c) => c == 'closeSession'), hasLength(1));
      expect(fake.openSessions, isEmpty);
      expect(session.isClosed, isTrue);
      expect(() => session.apply(const ResolvedCaptureSettings()), throwsStateError);
      expect(() => session.focusAt(0, 0), throwsStateError);
      expect(() => session.setLive(enabled: true), throwsStateError);
      expect(() => session.capture(request), throwsStateError);
      expect(() => session.startVideo(const VideoRequest(outputPath: '/v')), throwsStateError);
      expect(() => session.stopVideo(), throwsStateError);
      expect(() => session.suspend(), throwsStateError);
      expect(() => session.resume(), throwsStateError);
    });

    test('errors from the platform propagate unchanged', () async {
      final session = await camera.open(const SessionConfig(cameraId: 'fake:back'));
      fake.error = const CameraException('storage_full', 'disk full');
      await expectLater(session.capture(request), throwsA(isA<CameraException>().having((e) => e.code, 'code', 'storage_full')));
      await session.close();
    });
  });

  group('MismatchTracker', () {
    // docs/specs/camera.md: a control whose mismatch persists across 3 captures is disabled for the session
    test('[CAM-050] a control ignored on 3 consecutive captures is disabled, with a notification', () async {
      final fake = FakeCameraPlatform();
      final session = await DoroCamera(platform: fake).open(const SessionConfig(cameraId: 'fake:back'));
      final changes = <Set<String>>[];
      final sub = session.disabledControlsChanges.listen(changes.add);
      for (var i = 0; i < 2; i++) {
        fake.nextCaptureResult = resultWith(<String>['iso']);
        await session.capture(request);
      }
      expect(session.disabledControls, isEmpty);
      fake.nextCaptureResult = resultWith(<String>['iso', 'exposureTime']);
      await session.capture(request);
      await Future<void>.delayed(Duration.zero);
      expect(session.disabledControls, <String>{'iso'});
      expect(changes, <Set<String>>[
        <String>{'iso'},
      ]);
      await sub.cancel();
      await session.close();
    });

    test('an honoured request resets the streak, and a disabled control stays disabled', () {
      final tracker = MismatchTracker();
      expect(tracker.record(applied(mismatches: <String>['iso'])), isEmpty);
      expect(tracker.record(applied(mismatches: <String>['iso'])), isEmpty);
      tracker.record(applied()); // the device honoured it: streak resets
      expect(tracker.record(applied(mismatches: <String>['iso'])), isEmpty);
      expect(tracker.record(applied(mismatches: <String>['iso'])), isEmpty);
      expect(tracker.record(applied(mismatches: <String>['iso'])), <String>{'iso'});
      expect(tracker.disabled, <String>{'iso'});
      expect(tracker.record(applied(mismatches: <String>['iso'])), isEmpty); // not reported twice
      tracker.record(applied());
      expect(tracker.disabled, <String>{'iso'});
      tracker.reset();
      expect(tracker.disabled, isEmpty);
    });

    test('streaks are tracked per control and a custom limit is honoured', () {
      final tracker = MismatchTracker(limit: 1);
      expect(tracker.record(applied(mismatches: <String>['focusDistance', 'kelvin'])), <String>{'focusDistance', 'kelvin'});
      expect(() => tracker.disabled.add('x'), throwsUnsupportedError);
      expect(mismatchLimit, 3);
    });
  });

  group('FakeCameraPlatform', () {
    test('records calls, scripts failures and builds results from requests', () async {
      final fake = FakeCameraPlatform();
      expect((await fake.capabilities('fake:back')).hasManualExposure, isTrue);
      await expectLater(fake.capabilities('nope'), throwsA(isA<CameraException>()));
      final info = await fake.openSession(const SessionConfig(cameraId: 'synthetic:wide', live: true));
      expect(info.source, CameraSource.synthetic);
      expect(info.audioActive, isTrue);
      await fake.applySettings(info.sessionId, const ResolvedCaptureSettings(iso: 200));
      final live = await fake.capture(info.sessionId, const CaptureRequest(memoryId: 'm', outputDir: '/d', originalName: 'o', renderedName: 'r', thumbnailName: 't', displayName: 'p', live: true, motionName: 'x.mp4'));
      expect(live.motion!.path, '/d/x.mp4');
      expect(live.applied.iso, 200);
      fake.appliedBuilder = (s) => AppliedSettings(iso: 1, mismatches: <String>['iso']);
      expect((await fake.applySettings(info.sessionId, const ResolvedCaptureSettings(iso: 9))).mismatches, <String>['iso']);
      expect((await fake.stopVideo(info.sessionId)).path, '');
      await fake.startVideo(info.sessionId, const VideoRequest(outputPath: '/v.mp4', size: CameraSize(640, 480), audio: false));
      final video = await fake.stopVideo(info.sessionId);
      expect(video.width, 640);
      expect(video.hasAudio, isFalse);
      await fake.closeSession(info.sessionId);
      expect(fake.openSessions, isEmpty);
      fake.permissions = const CameraPermissions(camera: PermissionStatus.denied, microphone: PermissionStatus.denied);
      await expectLater(fake.openSession(const SessionConfig(cameraId: 'fake:back')), throwsA(isA<CameraException>()));
    });
  });
}
