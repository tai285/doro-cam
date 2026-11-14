import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/domain/camera/capabilities.dart' as dom;
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/intent_resolver.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:doro_cam/domain/experience/layers.dart';
import 'package:doro_cam/domain/experience/preset.dart';
import 'package:doro_cam/domain/experience/scenario.dart';
import 'package:doro_camera/doro_camera.dart' as cam;
import 'package:meta/meta.dart';

enum CameraPhase { initializing, needsPermission, noCamera, ready, failed }

enum CaptureMode { photo, video }

/// Everything the camera screen shows. Immutable; the controller replaces it on every change.
@immutable
class CameraState {
  const CameraState({
    this.phase = CameraPhase.initializing,
    this.permissions,
    this.cameras = const <cam.CameraDescriptor>[],
    this.camera,
    this.pluginCaps,
    this.caps = dom.CameraCapabilities.none,
    this.session,
    this.experience = Experiences.mirrorless,
    this.authentic = false,
    this.scenario,
    this.preset,
    this.user = CaptureIntent.empty,
    this.layered,
    this.result,
    this.mode = CaptureMode.photo,
    this.recording = false,
    this.recordingSeconds = 0,
    this.capturing = false,
    this.countdown,
    this.lastCapture,
    this.developing,
    this.notice,
    this.errorMessage,
    this.disabled = const <IntentField>{},
    this.framesShot = 0,
    this.focusPoint,
    this.flashPulse = 0,
    this.thermal,
  });

  final CameraPhase phase;
  final cam.CameraPermissions? permissions;
  final List<cam.CameraDescriptor> cameras;
  final cam.CameraDescriptor? camera;
  final cam.CameraCapabilities? pluginCaps;
  final dom.CameraCapabilities caps;
  final cam.CameraSession? session;
  final Experience experience;

  /// "Authentic" mode: the Experience's constraints cannot be overridden (EXP-003).
  final bool authentic;
  final Scenario? scenario;
  final Preset? preset;

  /// The user's own overrides, the top layer (ADR-0003).
  final CaptureIntent user;
  final LayeredIntent? layered;
  final ResolveResult? result;
  final CaptureMode mode;
  final bool recording;
  final int recordingSeconds;
  final bool capturing;

  /// Seconds left on the self-timer, or null.
  final int? countdown;
  final MemoryView? lastCapture;

  /// Instant: the capture being shown as a developing print (EXP-010).
  final MemoryView? developing;
  final String? notice;
  final String? errorMessage;

  /// Controls the device ignored three times in a row: hidden for the rest of the session.
  final Set<IntentField> disabled;
  final int framesShot;

  /// Normalised tap-to-focus position, for the focus ring.
  final (double, double)? focusPoint;

  /// Incremented on every capture so the screen can flash (CAM-051).
  final int flashPulse;
  final cam.ThermalState? thermal;

  ResolvedCaptureSettings? get settings => result?.settings;
  bool get isReady => phase == CameraPhase.ready;
  bool get liveOn =>
      (settings?.live ?? false) && caps.live.supported && session != null;

  CameraState copyWith({
    CameraPhase? phase,
    cam.CameraPermissions? permissions,
    List<cam.CameraDescriptor>? cameras,
    cam.CameraDescriptor? camera,
    cam.CameraCapabilities? pluginCaps,
    dom.CameraCapabilities? caps,
    cam.CameraSession? session,
    bool clearSession = false,
    Experience? experience,
    bool? authentic,
    Scenario? scenario,
    bool clearScenario = false,
    Preset? preset,
    bool clearPreset = false,
    CaptureIntent? user,
    LayeredIntent? layered,
    ResolveResult? result,
    CaptureMode? mode,
    bool? recording,
    int? recordingSeconds,
    bool? capturing,
    int? countdown,
    bool clearCountdown = false,
    MemoryView? lastCapture,
    MemoryView? developing,
    bool clearDeveloping = false,
    String? notice,
    bool clearNotice = false,
    String? errorMessage,
    bool clearError = false,
    Set<IntentField>? disabled,
    int? framesShot,
    (double, double)? focusPoint,
    bool clearFocusPoint = false,
    int? flashPulse,
    cam.ThermalState? thermal,
  }) {
    return CameraState(
      phase: phase ?? this.phase,
      permissions: permissions ?? this.permissions,
      cameras: cameras ?? this.cameras,
      camera: camera ?? this.camera,
      pluginCaps: pluginCaps ?? this.pluginCaps,
      caps: caps ?? this.caps,
      session: clearSession ? null : (session ?? this.session),
      experience: experience ?? this.experience,
      authentic: authentic ?? this.authentic,
      scenario: clearScenario ? null : (scenario ?? this.scenario),
      preset: clearPreset ? null : (preset ?? this.preset),
      user: user ?? this.user,
      layered: layered ?? this.layered,
      result: result ?? this.result,
      mode: mode ?? this.mode,
      recording: recording ?? this.recording,
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
      capturing: capturing ?? this.capturing,
      countdown: clearCountdown ? null : (countdown ?? this.countdown),
      lastCapture: lastCapture ?? this.lastCapture,
      developing: clearDeveloping ? null : (developing ?? this.developing),
      notice: clearNotice ? null : (notice ?? this.notice),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      disabled: disabled ?? this.disabled,
      framesShot: framesShot ?? this.framesShot,
      focusPoint: clearFocusPoint ? null : (focusPoint ?? this.focusPoint),
      flashPulse: flashPulse ?? this.flashPulse,
      thermal: thermal ?? this.thermal,
    );
  }
}
