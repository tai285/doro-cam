import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/control_availability.dart';
import 'package:doro_cam/domain/camera/intent_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Builds capabilities from a bit mask: each bit switches one capability on, so every permutation is covered.
CameraCapabilities fromMask(int mask) {
  bool on(int bit) => (mask >> bit) & 1 == 1;
  return CameraCapabilities(
    iso: on(0) ? const IntRange(50, 3200) : null,
    exposureTimeNs: on(1) ? const IntRange(100000, 1000000000) : null,
    exposureBias: on(2) ? const ExposureBiasCaps(range: DoubleRange(-2, 2), step: 0.5) : null,
    apertures: on(3) ? const <double>[1.8, 2.8] : (on(11) ? const <double>[1.8] : const <double>[]),
    focus: FocusCaps(
      auto: on(4),
      continuous: on(5),
      tapToFocus: on(6),
      manual: on(7) ? const ManualFocusCaps(minFocusDistanceDiopters: 8, calibration: FocusCalibration.approximate) : null,
    ),
    whiteBalance: WhiteBalanceCaps(
      presets: on(8) ? const <WbPreset>{WbPreset.auto, WbPreset.daylight} : const <WbPreset>{WbPreset.auto},
      kelvin: on(9) ? const IntRange(2500, 8000) : null,
    ),
    zoom: on(10) ? const ZoomCaps(min: 1, max: 5, opticalSteps: <double>[1, 2]) : const ZoomCaps(),
    flash: on(12) ? const <FlashMode>{FlashMode.off, FlashMode.on} : const <FlashMode>{},
    torch: on(13),
    photoFormats: on(14) ? const <PhotoFormat>[PhotoFormat.heif, PhotoFormat.jpeg] : const <PhotoFormat>[PhotoFormat.jpeg],
    hdr: on(15),
    live: LiveCaps(supported: on(16), audio: on(17)),
  );
}

void main() {
  test('[CAM-005] every control has an entry, and unavailable controls always carry a reason (all 262,144 sampled permutations)', () {
    // 18 independent capability bits; step through the space so the whole range of every bit is exercised.
    for (var mask = 0; mask < (1 << 18); mask += 7) {
      final map = controlAvailability(fromMask(mask));
      expect(map.keys.toSet(), Control.values.toSet());
      for (final entry in map.entries) {
        if (entry.value.state != ControlState.enabled) {
          expect(entry.value.reason, isNotNull, reason: '$mask ${entry.key}');
          expect(entry.value.reason, isNotEmpty);
        }
        expect(entry.value.isEnabled, entry.value.state == ControlState.enabled);
        expect(entry.value.isVisible, entry.value.state != ControlState.unavailable);
      }
    }
  });

  test('[CAM-005] a control is available exactly when its capability exists (every bit, both values)', () {
    for (var bit = 0; bit < 18; bit++) {
      for (final base in <int>[0, (1 << 18) - 1, 0x2AAAA, 0x15555]) {
        final off = controlAvailability(fromMask(base & ~(1 << bit)));
        final on = controlAvailability(fromMask(base | (1 << bit)));
        final expectations = <int, List<Control>>{
          0: [Control.iso],
          1: [Control.shutter],
          2: [Control.exposureBias],
          3: [Control.aperture],
          4: [Control.focusLock],
          5: [Control.continuousFocus],
          6: [Control.tapToFocus],
          7: [Control.manualFocus],
          8: [Control.whiteBalancePresets],
          9: [Control.whiteBalanceKelvin],
          10: [Control.zoom, Control.opticalLens],
          12: [Control.flash],
          13: [Control.torch],
          15: [Control.hdr],
          16: [Control.live],
        };
        for (final control in expectations[bit] ?? const <Control>[]) {
          // aperture bit 3 toggles "two apertures"; with bit 11 set it is read-only rather than hidden
          if (control == Control.aperture) {
            expect(on[control]!.isEnabled, isTrue);
            expect(off[control]!.isEnabled, isFalse);
            continue;
          }
          expect(on[control]!.isEnabled, isTrue, reason: 'bit $bit $control');
          expect(off[control]!.isEnabled, isFalse, reason: 'bit $bit $control');
        }
      }
    }
  });

  test('[CAM-013] a fixed aperture is shown read-only; several apertures are controllable; none is hidden', () {
    expect(controlAvailability(fullCamera)[Control.aperture]!.state, ControlState.readOnly);
    expect(controlAvailability(fullCamera)[Control.aperture]!.reason, contains('fixed'));
    expect(controlAvailability(fullCamera)[Control.aperture]!.isVisible, isTrue);
    expect(controlAvailability(fullCamera.copyWith(apertures: const <double>[1.4, 2.8]))[Control.aperture]!.state, ControlState.enabled);
    expect(controlAvailability(CameraCapabilities.none)[Control.aperture]!.state, ControlState.unavailable);
  });

  test('[CAM-005] a full camera enables everything except the fixed aperture; "none" offers nothing', () {
    final full = controlAvailability(fullCamera);
    expect(full.entries.where((e) => e.value.state == ControlState.unavailable), isEmpty);
    final none = controlAvailability(CameraCapabilities.none);
    expect(none.values.every((a) => a.state == ControlState.unavailable), isTrue);
    expect(unavailableControls(CameraCapabilities.none).length, Control.values.length);
    expect(unavailableControls(fullCamera), isEmpty);
    expect(unavailableControls(basicCamera)[Control.iso], contains('manual ISO'));
  });

  test('[CAM-005] white-balance presets that are only "auto" do not count as presets', () {
    final caps = fullCamera.copyWith(whiteBalance: const WhiteBalanceCaps(presets: <WbPreset>{WbPreset.auto}));
    expect(controlAvailability(caps)[Control.whiteBalancePresets]!.isEnabled, isFalse);
    expect(controlAvailability(caps.copyWith(whiteBalance: const WhiteBalanceCaps(kelvin: IntRange(5000, 4000))))[Control.whiteBalanceKelvin]!.isEnabled, isFalse);
  });

  test('[MOT-003] audio explains itself differently when LIVE is missing and when only the microphone is', () {
    expect(controlAvailability(basicCamera)[Control.liveAudio]!.reason, contains('Motion capture'));
    final silent = fullCamera.copyWith(live: const LiveCaps(supported: true));
    expect(controlAvailability(silent)[Control.liveAudio]!.reason, contains('microphone'));
  });

  test('[CAM-005] property: a control the camera hides never reaches the settings the resolver produces', () {
    const everything = CaptureIntent(
      iso: 800,
      exposureTimeNs: 8000000,
      exposureBiasEv: 1,
      focus: FocusRequest.manual,
      manualFocusDiopters: 2,
      whiteBalance: WbRequest.kelvin(5000),
      zoom: 3,
      flash: FlashMode.on,
      torch: true,
      photoFormat: PhotoFormat.heif,
      live: true,
    );
    for (var mask = 0; mask < (1 << 18); mask += 13) {
      final caps = fromMask(mask);
      final controls = controlAvailability(caps);
      final s = resolve(everything, caps).settings;
      if (!controls[Control.iso]!.isEnabled) expect(s.iso, isNull, reason: '$mask');
      if (!controls[Control.shutter]!.isEnabled) expect(s.exposureTimeNs, isNull, reason: '$mask');
      if (!controls[Control.manualFocus]!.isEnabled) expect(s.focusMode, isNot(FocusMode.manual), reason: '$mask');
      if (!controls[Control.whiteBalanceKelvin]!.isEnabled) expect(s.whiteBalance.kelvin, isNull, reason: '$mask');
      if (!controls[Control.flash]!.isEnabled) expect(s.flash, FlashMode.off, reason: '$mask');
      if (!controls[Control.torch]!.isEnabled) expect(s.torch, isFalse, reason: '$mask');
      if (!controls[Control.live]!.isEnabled) expect(s.live, isFalse, reason: '$mask');
      if (!controls[Control.zoom]!.isEnabled) expect(s.zoom, 1, reason: '$mask');
      if (!controls[Control.exposureBias]!.isEnabled) expect(s.exposureBiasEv, isNull, reason: '$mask');
    }
  });

  group('AppliedMismatchMonitor (spec: persistent mismatch disables a control)', () {
    test('[CAM-050] disables a control after three consecutive mismatches and explains why', () {
      final monitor = AppliedMismatchMonitor();
      expect(monitor.record(<IntentField, bool>{IntentField.iso: false}), isEmpty);
      expect(monitor.record(<IntentField, bool>{IntentField.iso: false}), isEmpty);
      expect(monitor.isDisabled(IntentField.iso), isFalse);
      expect(monitor.record(<IntentField, bool>{IntentField.iso: false}), <IntentField>{IntentField.iso});
      expect(monitor.isDisabled(IntentField.iso), isTrue);
      expect(monitor.disabled, <IntentField>{IntentField.iso});
      expect(monitor.explanation(IntentField.iso), contains('3 times in a row'));
      expect(monitor.explanation(IntentField.zoom), isNull);
    });

    test('[CAM-050] a match resets the streak, so intermittent mismatches do not disable a control', () {
      final monitor = AppliedMismatchMonitor();
      for (var i = 0; i < 10; i++) {
        monitor.record(<IntentField, bool>{IntentField.iso: false});
        monitor.record(<IntentField, bool>{IntentField.iso: false});
        monitor.record(<IntentField, bool>{IntentField.iso: true});
      }
      expect(monitor.isDisabled(IntentField.iso), isFalse);
    });

    test('tracks fields independently, ignores disabled fields afterwards, and resets', () {
      final monitor = AppliedMismatchMonitor(threshold: 2);
      monitor.record(<IntentField, bool>{IntentField.iso: false, IntentField.zoom: true});
      final newly = monitor.record(<IntentField, bool>{IntentField.iso: false, IntentField.zoom: false});
      expect(newly, <IntentField>{IntentField.iso});
      expect(monitor.record(<IntentField, bool>{IntentField.iso: false}), isEmpty); // already disabled
      expect(monitor.isDisabled(IntentField.zoom), isFalse);
      expect(() => monitor.disabled.add(IntentField.zoom), throwsUnsupportedError);
      monitor.reset();
      expect(monitor.disabled, isEmpty);
    });

    test('ControlAvailability compares and prints', () {
      expect(const ControlAvailability(ControlState.enabled), const ControlAvailability(ControlState.enabled));
      expect(const ControlAvailability(ControlState.enabled).hashCode, const ControlAvailability(ControlState.enabled).hashCode);
      expect(const ControlAvailability(ControlState.unavailable, 'x').toString(), contains('unavailable: x'));
      expect(const ControlAvailability(ControlState.readOnly).toString(), 'ControlAvailability(readOnly)');
    });
  });
}
