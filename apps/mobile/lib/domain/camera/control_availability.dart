/// Which camera controls the UI may show for a given camera, and why not (CAM-005).
///
/// The UI never invents a control: anything not listed as available is hidden or shown disabled with the
/// reason below. The camera spec's "mismatch" rule lives here too: a control whose requested and applied
/// values keep disagreeing is switched off for the session.
library;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';

enum Control {
  iso,
  shutter,
  exposureBias,
  exposureLock,
  aperture,
  manualFocus,
  tapToFocus,
  focusLock,
  continuousFocus,
  whiteBalancePresets,
  whiteBalanceKelvin,
  zoom,
  opticalLens,
  flash,
  torch,
  photoFormat,
  live,
  liveAudio,
  hdr,
}

enum ControlState {
  /// The control works.
  enabled,

  /// Shown but not changeable (the aperture of a fixed-aperture phone camera is display-only, CAM-013).
  readOnly,

  /// Not offered. The UI hides it or shows it disabled, with [ControlAvailability.reason].
  unavailable,
}

class ControlAvailability {
  const ControlAvailability(this.state, [this.reason]);

  final ControlState state;

  /// A short explanation, always present for [ControlState.unavailable] and [ControlState.readOnly].
  final String? reason;

  bool get isEnabled => state == ControlState.enabled;
  bool get isVisible => state != ControlState.unavailable;

  @override
  bool operator ==(Object other) => other is ControlAvailability && other.state == state && other.reason == reason;

  @override
  int get hashCode => Object.hash(state, reason);

  @override
  String toString() => 'ControlAvailability(${state.name}${reason == null ? '' : ': $reason'})';
}

const ControlAvailability _enabled = ControlAvailability(ControlState.enabled);

ControlAvailability _no(String reason) => ControlAvailability(ControlState.unavailable, reason);

/// The availability of every [Control] for [caps]. Total: covers every capability combination.
Map<Control, ControlAvailability> controlAvailability(CameraCapabilities caps) {
  return <Control, ControlAvailability>{
    Control.iso: caps.hasManualIso ? _enabled : _no('This camera doesn’t allow manual ISO.'),
    Control.shutter: caps.hasManualShutter ? _enabled : _no('This camera doesn’t allow manual shutter speed.'),
    Control.exposureBias: caps.exposureBias != null && caps.exposureBias!.range.isValid
        ? _enabled
        : _no('This camera doesn’t report exposure compensation.'),
    Control.exposureLock: caps.hasManualIso && caps.hasManualShutter || caps.exposureBias != null || caps.focus.auto
        ? _enabled
        : _no('This camera has fixed exposure.'),
    Control.aperture: switch (caps.apertures.length) {
      0 => _no('This camera doesn’t report its aperture.'),
      1 => const ControlAvailability(ControlState.readOnly, 'The aperture is fixed on this camera, so it is shown but can’t be changed.'),
      _ => _enabled,
    },
    Control.manualFocus: caps.focus.manual != null ? _enabled : _no('This camera doesn’t allow manual focus.'),
    Control.tapToFocus: caps.focus.tapToFocus ? _enabled : _no('This camera doesn’t support tap to focus.'),
    Control.focusLock: caps.focus.auto ? _enabled : _no('Focus lock needs autofocus, which this camera doesn’t have.'),
    Control.continuousFocus: caps.focus.continuous ? _enabled : _no('This camera doesn’t support continuous autofocus.'),
    Control.whiteBalancePresets: caps.whiteBalance.presets.any((preset) => preset != WbPreset.auto)
        ? _enabled
        : _no('This camera doesn’t offer white-balance presets.'),
    Control.whiteBalanceKelvin: caps.whiteBalance.kelvin != null && caps.whiteBalance.kelvin!.isValid
        ? _enabled
        : _no('This camera doesn’t allow white balance in Kelvin.'),
    Control.zoom: caps.zoom.canZoom ? _enabled : _no('This camera doesn’t zoom.'),
    Control.opticalLens: caps.zoom.opticalSteps.length > 1 ? _enabled : _no('Only one lens is available to apps on this camera.'),
    Control.flash: caps.flash.any((mode) => mode != FlashMode.off) ? _enabled : _no('This camera has no flash.'),
    Control.torch: caps.torch ? _enabled : _no('This camera has no torch.'),
    Control.photoFormat: caps.photoFormats.length > 1 ? _enabled : _no('Only one photo format is available.'),
    Control.live: caps.live.supported ? _enabled : _no('Motion capture isn’t available on this camera.'),
    Control.liveAudio: caps.live.supported && caps.live.audio
        ? _enabled
        : _no(caps.live.supported ? 'No microphone is available, so motion is silent.' : 'Motion capture isn’t available on this camera.'),
    Control.hdr: caps.hdr ? _enabled : _no('This camera doesn’t expose an HDR option.'),
  };
}

/// Controls that are not available, with the explanation to show (e.g. in a "Why can’t I…" sheet).
Map<Control, String> unavailableControls(CameraCapabilities caps) => <Control, String>{
      for (final entry in controlAvailability(caps).entries)
        if (entry.value.state == ControlState.unavailable) entry.key: entry.value.reason!,
    };

/// Tracks whether the camera really applies what we ask for (CAM-050). After [threshold] consecutive
/// captures where a control's applied value differs from the request, the control is disabled for the session.
class AppliedMismatchMonitor {
  AppliedMismatchMonitor({this.threshold = 3});

  final int threshold;
  final Map<IntentField, int> _streak = <IntentField, int>{};
  final Set<IntentField> _disabled = <IntentField>{};

  Set<IntentField> get disabled => Set<IntentField>.unmodifiable(_disabled);

  bool isDisabled(IntentField field) => _disabled.contains(field);

  /// Records one capture: [matched] says, per requested field, whether the applied value matched.
  /// Returns the fields that became disabled by this call.
  Set<IntentField> record(Map<IntentField, bool> matched) {
    final newlyDisabled = <IntentField>{};
    matched.forEach((field, ok) {
      if (_disabled.contains(field)) {
        return;
      }
      if (ok) {
        _streak[field] = 0;
        return;
      }
      final streak = (_streak[field] ?? 0) + 1;
      _streak[field] = streak;
      if (streak >= threshold) {
        _disabled.add(field);
        newlyDisabled.add(field);
      }
    });
    return newlyDisabled;
  }

  String? explanation(IntentField field) => _disabled.contains(field)
      ? 'This control is switched off for this session: the camera did not apply it $threshold times in a row.'
      : null;

  void reset() {
    _streak.clear();
    _disabled.clear();
  }
}
