import 'dart:async';

import 'package:doro_camera/src/camera_platform.dart';
import 'package:doro_camera/src/ping_result.dart';
import 'package:doro_camera/src/types.dart';

/// Entry point of the camera plugin (docs/specs/camera.md): permissions, camera discovery, capabilities and
/// opening a [CameraSession]. Intent resolution, presets and Experiences are NOT here: they live in the app
/// (ADR-0001), and this API applies already-resolved settings and reports what the hardware did.
class DoroCamera {
  DoroCamera({this._platform});

  final CameraPlatform? _platform;
  final Map<String, CameraCapabilities> _capabilityCache = <String, CameraCapabilities>{};

  CameraPlatform get _resolved => _platform ?? CameraPlatform.instance;

  /// Round-trips [message] through the native layer.
  Future<PingResult> ping([String message = 'ping']) => _resolved.ping(message);

  Future<CameraPermissions> checkPermissions() => _resolved.checkPermissions();

  Future<CameraPermissions> requestPermissions({bool camera = true, bool microphone = true}) =>
      _resolved.requestPermissions(camera: camera, microphone: microphone);

  Future<void> openAppSettings() => _resolved.openAppSettings();

  /// One entry per camera the app may use, including the synthetic test camera in debug builds.
  Future<List<CameraDescriptor>> listCameras() => _resolved.listCameras();

  /// Capabilities are cached per [DoroCamera] instance; pass [refresh] after a reconfiguration.
  Future<CameraCapabilities> capabilities(String cameraId, {bool refresh = false}) async {
    if (!refresh) {
      final cached = _capabilityCache[cameraId];
      if (cached != null) {
        return cached;
      }
    }
    final fresh = await _resolved.capabilities(cameraId);
    _capabilityCache[cameraId] = fresh;
    return fresh;
  }

  /// Opens a camera. Fails with a typed [CameraException] (`permission_denied`, `camera_in_use`, ...).
  Future<CameraSession> open(SessionConfig config) async {
    final platform = _resolved;
    final info = await platform.openSession(config);
    return CameraSession(platform, info);
  }
}

/// How many consecutive results must ignore a request before the control is disabled for the session.
const int mismatchLimit = 3;

/// Counts consecutive request/applied mismatches per control (docs/specs/camera.md: "a control whose mismatch
/// persists across 3 captures is disabled for the session with an explanation").
class MismatchTracker {
  MismatchTracker({this.limit = mismatchLimit});

  final int limit;
  final Map<String, int> _consecutive = <String, int>{};
  final Set<String> _disabled = <String>{};

  /// Controls the device ignores persistently. The UI hides them and explains why.
  Set<String> get disabled => Set<String>.unmodifiable(_disabled);

  /// Feeds one result. Returns the controls that became disabled by it.
  Set<String> record(AppliedSettings applied) {
    final newlyDisabled = <String>{};
    final seen = applied.mismatches.toSet();
    for (final field in seen) {
      final count = (_consecutive[field] ?? 0) + 1;
      _consecutive[field] = count;
      if (count >= limit && _disabled.add(field)) {
        newlyDisabled.add(field);
      }
    }
    _consecutive.removeWhere((field, _) => !seen.contains(field));
    return newlyDisabled;
  }

  void reset() {
    _consecutive.clear();
    _disabled.clear();
  }
}

/// An open camera session with a live preview texture.
class CameraSession {
  CameraSession(this._platform, CameraSessionInfo info) : _info = info {
    _subscription = _platform.sessionEvents.where((event) => event.sessionId == info.sessionId).listen(_onEvent);
  }

  final CameraPlatform _platform;
  final CameraSessionInfo _info;
  late final StreamSubscription<SessionEvent> _subscription;
  final StreamController<SessionEvent> _events = StreamController<SessionEvent>.broadcast();
  final StreamController<Set<String>> _disabledChanges = StreamController<Set<String>>.broadcast();
  final MismatchTracker _mismatches = MismatchTracker();
  SessionState _state = SessionState.previewing;
  AppliedSettings? _lastApplied;
  bool _closed = false;

  CameraSessionInfo get info => _info;

  int get sessionId => _info.sessionId;

  /// Flutter `Texture` id of the live preview: `Texture(textureId: session.textureId)`.
  int get textureId => _info.textureId;

  SessionState get state => _state;

  /// The last settings the device reported, from `apply` or from the preview.
  AppliedSettings? get lastApplied => _lastApplied;

  bool get isClosed => _closed;

  /// Controls the device ignored on 3 consecutive results (docs/specs/camera.md).
  Set<String> get disabledControls => _mismatches.disabled;

  /// Emits whenever [disabledControls] grows.
  Stream<Set<String>> get disabledControlsChanges => _disabledChanges.stream;

  /// State, applied-settings, error, thermal and orientation events of this session.
  Stream<SessionEvent> get events => _events.stream;

  void _onEvent(SessionEvent event) {
    final state = event.state;
    if (event.kind == SessionEventKind.state && state != null) {
      _state = state;
    }
    final applied = event.applied;
    if (event.kind == SessionEventKind.applied && applied != null) {
      _lastApplied = applied;
    }
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('The camera session is closed');
    }
  }

  /// Applies already-resolved settings and returns what the device reported it used (CAM-050).
  Future<AppliedSettings> apply(ResolvedCaptureSettings settings) async {
    _ensureOpen();
    final applied = await _platform.applySettings(sessionId, settings);
    _lastApplied = applied;
    return applied;
  }

  Future<void> focusAt(double x, double y) {
    _ensureOpen();
    return _platform.focusAt(sessionId, x, y);
  }

  /// Turns the LIVE pre-roll buffer on or off (MOT-009). [info] then reflects whether it really started.
  Future<void> setLive({required bool enabled}) async {
    _ensureOpen();
    await _platform.setLive(sessionId, enabled: enabled);
  }

  /// Takes a photo. The result records the settings the device reported; repeated mismatches disable the
  /// affected control for this session ([disabledControls]).
  Future<CaptureResult> capture(CaptureRequest request) async {
    _ensureOpen();
    final result = await _platform.capture(sessionId, request);
    _lastApplied = result.applied;
    final newlyDisabled = _mismatches.record(result.applied);
    if (newlyDisabled.isNotEmpty && !_disabledChanges.isClosed) {
      _disabledChanges.add(_mismatches.disabled);
    }
    return result;
  }

  Future<void> startVideo(VideoRequest request) {
    _ensureOpen();
    return _platform.startVideo(sessionId, request);
  }

  Future<VideoResult> stopVideo() {
    _ensureOpen();
    return _platform.stopVideo(sessionId);
  }

  /// Stops preview and LIVE buffering while the app is in the background (NFR-012).
  Future<void> suspend() {
    _ensureOpen();
    return _platform.suspendSession(sessionId);
  }

  Future<void> resume() {
    _ensureOpen();
    return _platform.resumeSession(sessionId);
  }

  /// Closes the camera. Idempotent.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    try {
      await _platform.closeSession(sessionId);
    } finally {
      await _events.close();
      await _disabledChanges.close();
    }
  }
}
