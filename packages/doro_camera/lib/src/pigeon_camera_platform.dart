import 'dart:async';

import 'package:doro_camera/src/camera_exception.dart';
import 'package:doro_camera/src/camera_platform.dart';
import 'package:doro_camera/src/mapping.dart';
import 'package:doro_camera/src/messages.g.dart';
import 'package:doro_camera/src/ping_result.dart';
import 'package:doro_camera/src/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// [CameraPlatform] backed by the Pigeon-generated host API (Kotlin on Android, Swift on iOS).
class PigeonCameraPlatform extends CameraPlatform {
  PigeonCameraPlatform({CameraHostApi? api, this._listenForEvents = true}) : _api = api ?? CameraHostApi();

  final CameraHostApi _api;
  final bool _listenForEvents;
  bool _registered = false;

  /// Registers the native-to-Dart event channel on first use, so constructing the platform needs no binding.
  void _register() {
    if (_listenForEvents && !_registered) {
      _registered = true;
      CameraEventsApi.setUp(_EventReceiver(_events));
    }
  }
  final StreamController<SessionEvent> _events = StreamController<SessionEvent>.broadcast();

  /// Feeds an event as if native had sent it. For tests.
  @visibleForTesting
  void handleEvent(SessionEventMessage message) => _events.add(eventFromMessage(message));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      throw CameraException(error.code, error.message);
    }
  }

  @override
  Future<PingResult> ping(String message) => _guard(() async {
        final result = await _api.ping(message);
        return PingResult(
          echo: result.echo,
          platform: result.platform,
          osVersion: result.osVersion,
          syntheticCameraCompiledIn: result.syntheticCameraCompiledIn,
        );
      });

  @override
  Future<CameraPermissions> checkPermissions() => _guard(() async => permissionsFromMessage(await _api.checkPermissions()));

  @override
  Future<CameraPermissions> requestPermissions({bool camera = true, bool microphone = true}) =>
      _guard(() async => permissionsFromMessage(await _api.requestPermissions(camera, microphone)));

  @override
  Future<void> openAppSettings() => _guard(_api.openAppSettings);

  @override
  Future<List<CameraDescriptor>> listCameras() => _guard(() async => (await _api.listCameras()).map(descriptorFromMessage).toList());

  @override
  Future<CameraCapabilities> capabilities(String cameraId) =>
      _guard(() async => capabilitiesFromMessage(await _api.getCapabilities(cameraId)));

  @override
  Future<CameraSessionInfo> openSession(SessionConfig config) {
    _register(); // events can arrive while the session is still opening
    return _guard(() async => sessionInfoFromMessage(await _api.openSession(configToMessage(config))));
  }

  @override
  Future<void> closeSession(int sessionId) => _guard(() => _api.closeSession(sessionId));

  @override
  Future<AppliedSettings> applySettings(int sessionId, ResolvedCaptureSettings settings) =>
      _guard(() async => appliedFromMessage(await _api.applySettings(sessionId, settingsToMessage(settings))));

  @override
  Future<void> focusAt(int sessionId, double x, double y) => _guard(() => _api.focusAt(sessionId, x, y));

  @override
  Future<void> setLive(int sessionId, {required bool enabled}) => _guard(() => _api.setLive(sessionId, enabled));

  @override
  Future<CaptureResult> capture(int sessionId, CaptureRequest request) =>
      _guard(() async => captureResultFromMessage(await _api.capture(sessionId, captureRequestToMessage(request))));

  @override
  Future<void> startVideo(int sessionId, VideoRequest request) =>
      _guard(() => _api.startVideo(sessionId, videoRequestToMessage(request)));

  @override
  Future<VideoResult> stopVideo(int sessionId) => _guard(() async => videoResultFromMessage(await _api.stopVideo(sessionId)));

  @override
  Future<void> suspendSession(int sessionId) => _guard(() => _api.suspendSession(sessionId));

  @override
  Future<void> resumeSession(int sessionId) => _guard(() => _api.resumeSession(sessionId));

  @override
  Stream<SessionEvent> get sessionEvents {
    _register();
    return _events.stream;
  }
}

class _EventReceiver implements CameraEventsApi {
  _EventReceiver(this._sink);

  final StreamController<SessionEvent> _sink;

  @override
  void onSessionEvent(SessionEventMessage event) => _sink.add(eventFromMessage(event));
}
