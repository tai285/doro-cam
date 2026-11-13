import 'dart:math' as math;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/intent_resolver.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ResolveResult r(CaptureIntent intent, [CameraCapabilities caps = fullCamera]) => resolve(intent, caps);

void main() {
  group('resolve: exposure', () {
    test('[CAM-010] passes ISO inside the range through untouched', () {
      final out = r(const CaptureIntent(iso: 400));
      expect(out.settings.iso, 400);
      expect(out.adjustments, isEmpty);
    });

    test('[CAM-010][EXP-008] clamps ISO to the device range and says why', () {
      final high = r(const CaptureIntent(iso: 6400));
      expect(high.settings.iso, 3200);
      expect(high.adjustments.single.reason, AdjustmentReason.outOfRange);
      expect(high.adjustments.single.requested, 6400);
      expect(high.adjustments.single.applied, 3200);
      expect(high.adjustments.single.message, contains('ISO 6400 → 3200'));
      expect(r(const CaptureIntent(iso: 10)).settings.iso, 50);
      expect(r(const CaptureIntent(iso: 50)).adjustments, isEmpty);
      expect(r(const CaptureIntent(iso: 3200)).adjustments, isEmpty);
    });

    test('[CAM-005] ISO without the capability becomes automatic with an "unsupported" adjustment', () {
      final out = r(const CaptureIntent(iso: 400), basicCamera);
      expect(out.settings.iso, isNull);
      expect(out.settings.manualIso, isFalse);
      expect(out.adjustmentFor(IntentField.iso)!.reason, AdjustmentReason.unsupported);
    });

    test('[CAM-005] a degenerate ISO range (min == max) is treated as no manual ISO', () {
      final out = r(const CaptureIntent(iso: 200), fullCamera.copyWith(iso: const IntRange(100, 100)));
      expect(out.settings.iso, isNull);
      expect(out.adjustmentFor(IntentField.iso)!.reason, AdjustmentReason.unsupported);
    });

    test('[CAM-011] clamps shutter speed and formats it readably', () {
      final slow = r(const CaptureIntent(exposureTimeNs: 4000000000));
      expect(slow.settings.exposureTimeNs, 1000000000);
      expect(slow.adjustments.single.message, contains('1 s'));
      final fast = r(const CaptureIntent(exposureTimeNs: 1000));
      expect(fast.settings.exposureTimeNs, 100000);
      expect(fast.adjustments.single.message, contains('1/10000 s'));
      expect(r(const CaptureIntent(exposureTimeNs: 8000000)).adjustments, isEmpty);
      final half = r(const CaptureIntent(exposureTimeNs: 1500000000), fullCamera.copyWith(exposureTimeNs: const IntRange(100000, 2000000000)));
      expect(half.adjustments, isEmpty);
      final clampedHalf = r(const CaptureIntent(exposureTimeNs: 3000000000), fullCamera.copyWith(exposureTimeNs: const IntRange(100000, 1500000000)));
      expect(clampedHalf.adjustments.single.message, contains('1.5 s'));
    });

    test('[CAM-011] shutter without the capability stays automatic', () {
      final out = r(const CaptureIntent(exposureTimeNs: 8000000), basicCamera);
      expect(out.settings.exposureTimeNs, isNull);
      expect(out.adjustmentFor(IntentField.exposureTime)!.reason, AdjustmentReason.unsupported);
    });

    test('spec rule 3: ISO and shutter are independent', () {
      final onlyIso = r(const CaptureIntent(iso: 200));
      expect(onlyIso.settings.iso, 200);
      expect(onlyIso.settings.exposureTimeNs, isNull);
      expect(onlyIso.settings.fullyManualExposure, isFalse);
      final onlyShutter = r(const CaptureIntent(exposureTimeNs: 8000000));
      expect(onlyShutter.settings.iso, isNull);
      expect(onlyShutter.settings.manualShutter, isTrue);
    });

    test('[CAM-012] exposure compensation is clamped and snapped to the step', () {
      expect(r(const CaptureIntent(exposureBiasEv: 1.2)).settings.exposureBiasEv, 1.0);
      expect(r(const CaptureIntent(exposureBiasEv: 1.3)).settings.exposureBiasEv, 1.5);
      final clamped = r(const CaptureIntent(exposureBiasEv: 5));
      expect(clamped.settings.exposureBiasEv, 2);
      expect(clamped.adjustments.single.reason, AdjustmentReason.outOfRange);
      expect(r(const CaptureIntent(exposureBiasEv: -5)).settings.exposureBiasEv, -2);
      final noStep = r(const CaptureIntent(exposureBiasEv: 0.7), fullCamera.copyWith(exposureBias: const ExposureBiasCaps(range: DoubleRange(-2, 2), step: 0)));
      expect(noStep.settings.exposureBiasEv, 0.7);
    });

    test('[CAM-012] exposure compensation without the capability is dropped with an explanation', () {
      final out = r(const CaptureIntent(exposureBiasEv: 1), basicCamera);
      expect(out.settings.exposureBiasEv, isNull);
      expect(out.adjustments.single.reason, AdjustmentReason.unsupported);
    });

    test('spec rule 4: exposure compensation is ignored when ISO and shutter are both manual', () {
      final out = r(const CaptureIntent(iso: 100, exposureTimeNs: 8000000, exposureBiasEv: 1));
      expect(out.settings.exposureBiasEv, isNull);
      expect(out.adjustmentFor(IntentField.exposureBias)!.reason, AdjustmentReason.notApplicableInManual);
      // with only one manual value it still applies
      expect(r(const CaptureIntent(iso: 100, exposureBiasEv: 1)).settings.exposureBiasEv, 1);
    });

    test('[CAM-014] exposure lock works in auto and is refused in full manual', () {
      expect(r(const CaptureIntent(exposureLock: true)).settings.exposureLocked, isTrue);
      final manual = r(const CaptureIntent(iso: 100, exposureTimeNs: 8000000, exposureLock: true));
      expect(manual.settings.exposureLocked, isFalse);
      expect(manual.adjustmentFor(IntentField.exposureLock)!.reason, AdjustmentReason.notApplicableInManual);
      expect(r(const CaptureIntent(exposureLock: false)).settings.exposureLocked, isFalse);
    });

    test('NaN and infinite numbers never crash and are reported', () {
      final out = r(const CaptureIntent(exposureBiasEv: double.nan));
      expect(out.settings.exposureBiasEv, isNull);
      expect(out.adjustments.single.reason, AdjustmentReason.outOfRange);
      expect(r(const CaptureIntent(exposureBiasEv: double.infinity)).settings.exposureBiasEv, isNull);
    });
  });

  group('resolve: focus', () {
    test('[CAM-020] defaults to the best available focus mode', () {
      expect(r(CaptureIntent.empty).settings.focusMode, FocusMode.continuous);
      expect(r(CaptureIntent.empty, basicCamera).settings.focusMode, FocusMode.auto);
      expect(r(CaptureIntent.empty, CameraCapabilities.none).settings.focusMode, FocusMode.fixed);
    });

    test('[CAM-020] an explicit auto request is honoured, or becomes fixed on a fixed-focus camera', () {
      expect(r(const CaptureIntent(focus: FocusRequest.auto)).settings.focusMode, FocusMode.auto);
      final fixed = r(const CaptureIntent(focus: FocusRequest.auto), CameraCapabilities.none);
      expect(fixed.settings.focusMode, FocusMode.fixed);
      expect(fixed.adjustmentFor(IntentField.focusMode)!.reason, AdjustmentReason.unsupported);
    });

    test('[CAM-020] continuous falls back to auto, then to fixed, with explanations', () {
      expect(r(const CaptureIntent(focus: FocusRequest.continuous)).settings.focusMode, FocusMode.continuous);
      final toAuto = r(const CaptureIntent(focus: FocusRequest.continuous), basicCamera);
      expect(toAuto.settings.focusMode, FocusMode.auto);
      expect(toAuto.adjustments.single.message, contains('single autofocus'));
      final toFixed = r(const CaptureIntent(focus: FocusRequest.continuous), CameraCapabilities.none);
      expect(toFixed.settings.focusMode, FocusMode.fixed);
      expect(toFixed.adjustments.single.message, contains('fixed focus'));
    });

    test('[CAM-021] manual focus is clamped to the closest focus distance', () {
      final ok = r(const CaptureIntent(focus: FocusRequest.manual, manualFocusDiopters: 5));
      expect(ok.settings.focusMode, FocusMode.manual);
      expect(ok.settings.manualFocusDiopters, 5);
      final near = r(const CaptureIntent(focus: FocusRequest.manual, manualFocusDiopters: 50));
      expect(near.settings.manualFocusDiopters, 10);
      expect(near.adjustments.single.message, contains('10 cm'));
      final neg = r(const CaptureIntent(focus: FocusRequest.manual, manualFocusDiopters: -3));
      expect(neg.settings.manualFocusDiopters, 0);
      expect(r(const CaptureIntent(focus: FocusRequest.manual)).settings.manualFocusDiopters, 0);
      final nan = r(const CaptureIntent(focus: FocusRequest.manual, manualFocusDiopters: double.nan));
      expect(nan.settings.manualFocusDiopters, 0);
      expect(nan.adjustmentFor(IntentField.manualFocus)!.reason, AdjustmentReason.outOfRange);
    });

    test('[CAM-021] a camera that cannot focus closer than infinity pins manual focus at infinity', () {
      final caps = fullCamera.copyWith(focus: const FocusCaps(auto: true, manual: ManualFocusCaps(minFocusDistanceDiopters: 0, calibration: FocusCalibration.uncalibrated)));
      final out = r(const CaptureIntent(focus: FocusRequest.manual, manualFocusDiopters: 3), caps);
      expect(out.settings.manualFocusDiopters, 0);
      expect(out.adjustments.single.message, contains('infinity'));
    });

    test('[CAM-021][CAM-005] manual focus without the capability uses autofocus (or fixed) and explains', () {
      final out = r(const CaptureIntent(focus: FocusRequest.manual), basicCamera);
      expect(out.settings.focusMode, FocusMode.auto);
      expect(out.settings.manualFocusDiopters, isNull);
      expect(out.adjustments.single.reason, AdjustmentReason.unsupported);
      expect(r(const CaptureIntent(focus: FocusRequest.manual), CameraCapabilities.none).settings.focusMode, FocusMode.fixed);
    });

    test('[CAM-022] focus lock works with autofocus only', () {
      expect(r(const CaptureIntent(focusLock: true)).settings.focusLocked, isTrue);
      final manual = r(const CaptureIntent(focus: FocusRequest.manual, focusLock: true));
      expect(manual.settings.focusLocked, isFalse);
      expect(manual.adjustmentFor(IntentField.focusLock)!.reason, AdjustmentReason.notApplicableInManual);
      final fixed = r(const CaptureIntent(focusLock: true), CameraCapabilities.none);
      expect(fixed.settings.focusLocked, isFalse);
      expect(fixed.adjustmentFor(IntentField.focusLock)!.reason, AdjustmentReason.unsupported);
    });
  });

  group('resolve: white balance', () {
    test('[CAM-030] supported presets pass through, auto always does', () {
      expect(r(const CaptureIntent(whiteBalance: WbRequest.preset(WbPreset.tungsten))).settings.whiteBalance.preset, WbPreset.tungsten);
      expect(r(const CaptureIntent(whiteBalance: WbRequest.preset(WbPreset.auto)), CameraCapabilities.none).settings.whiteBalance.preset, WbPreset.auto);
      expect(r(CaptureIntent.empty).settings.whiteBalance, const ResolvedWhiteBalance(preset: WbPreset.auto));
    });

    test('[CAM-030][CAM-005] an unsupported preset becomes automatic and explains', () {
      final out = r(const CaptureIntent(whiteBalance: WbRequest.preset(WbPreset.shade)), basicCamera);
      expect(out.settings.whiteBalance.preset, WbPreset.auto);
      expect(out.adjustments.single.message, contains('shade'));
    });

    test('[CAM-031] Kelvin is clamped to the supported range', () {
      final ok = r(const CaptureIntent(whiteBalance: WbRequest.kelvin(5500)));
      expect(ok.settings.whiteBalance.kelvin, 5500);
      final low = r(const CaptureIntent(whiteBalance: WbRequest.kelvin(1000)));
      expect(low.settings.whiteBalance.kelvin, 2500);
      expect(low.adjustments.single.message, contains('2500–8000 K'));
      expect(r(const CaptureIntent(whiteBalance: WbRequest.kelvin(20000))).settings.whiteBalance.kelvin, 8000);
    });

    test('[CAM-031][CAM-005] Kelvin without the capability stays automatic', () {
      final out = r(const CaptureIntent(whiteBalance: WbRequest.kelvin(5500)), basicCamera);
      expect(out.settings.whiteBalance.kelvin, isNull);
      expect(out.adjustments.single.reason, AdjustmentReason.unsupported);
      final invalid = r(const CaptureIntent(whiteBalance: WbRequest.kelvin(5500)), fullCamera.copyWith(whiteBalance: const WhiteBalanceCaps(kelvin: IntRange(5000, 4000))));
      expect(invalid.settings.whiteBalance.kelvin, isNull);
    });
  });

  group('resolve: zoom, lens and flash', () {
    test('[CAM-008] zoom within range is passed through; optical steps are not digital', () {
      final optical = r(const CaptureIntent(zoom: 2.5));
      expect(optical.settings.zoom, 2.5);
      expect(optical.settings.digitalZoom, isFalse);
      final digital = r(const CaptureIntent(zoom: 5));
      expect(digital.settings.zoom, 5);
      expect(digital.settings.digitalZoom, isTrue);
    });

    test('[CAM-008] zoom is clamped and the adjustment explains the range', () {
      final high = r(const CaptureIntent(zoom: 30));
      expect(high.settings.zoom, 10);
      expect(high.adjustments.single.message, contains('0.5–10.0×'));
      expect(r(const CaptureIntent(zoom: 0.1)).settings.zoom, 0.5);
    });

    test('[CAM-008] invalid zoom values fall back to the default zoom', () {
      for (final bad in <double>[double.nan, double.infinity, -2, 0]) {
        final out = r(CaptureIntent(zoom: bad));
        expect(out.settings.zoom, 1, reason: '$bad');
        expect(out.adjustments.single.reason, AdjustmentReason.outOfRange);
      }
    });

    test('[CAM-008] the default zoom respects the camera’s minimum, and cameras that cannot zoom stay at 1×', () {
      expect(r(CaptureIntent.empty).settings.zoom, 1);
      expect(r(CaptureIntent.empty, fullCamera.copyWith(zoom: const ZoomCaps(min: 2, max: 8))).settings.zoom, 2);
      expect(r(const CaptureIntent(zoom: 3), CameraCapabilities.none).settings.zoom, 1);
      // a malformed zoom range is normalized
      expect(r(const CaptureIntent(zoom: 3), fullCamera.copyWith(zoom: const ZoomCaps(min: 1, max: 0.5))).settings.zoom, 1);
      expect(r(const CaptureIntent(zoom: 3), fullCamera.copyWith(zoom: const ZoomCaps(min: double.nan, max: double.infinity))).settings.zoom, 1);
    });

    test('[CAM-008] with no reported optical steps anything above the minimum is digital', () {
      final caps = fullCamera.copyWith(zoom: const ZoomCaps(min: 1, max: 4));
      expect(r(const CaptureIntent(zoom: 1), caps).settings.digitalZoom, isFalse);
      expect(r(const CaptureIntent(zoom: 1.5), caps).settings.digitalZoom, isTrue);
    });

    test('[CAM-006] the requested lens is passed through for the session layer to select', () {
      expect(r(const CaptureIntent(lens: LensKind.tele)).settings.lens, LensKind.tele);
      expect(r(CaptureIntent.empty).settings.lens, isNull);
    });

    test('[CAM-040] flash modes follow the capability', () {
      expect(r(const CaptureIntent(flash: FlashMode.auto)).settings.flash, FlashMode.auto);
      expect(r(const CaptureIntent(flash: FlashMode.off), CameraCapabilities.none).settings.flash, FlashMode.off);
      final out = r(const CaptureIntent(flash: FlashMode.auto), basicCamera);
      expect(out.settings.flash, FlashMode.off);
      expect(out.adjustments.single.reason, AdjustmentReason.unsupported);
      expect(r(CaptureIntent.empty).settings.flash, FlashMode.off);
    });

    test('[CAM-040] torch needs a torch', () {
      expect(r(const CaptureIntent(torch: true)).settings.torch, isTrue);
      final out = r(const CaptureIntent(torch: true), basicCamera);
      expect(out.settings.torch, isFalse);
      expect(out.adjustments.single.message, contains('no torch'));
      expect(r(const CaptureIntent(torch: false)).settings.torch, isFalse);
    });
  });

  group('resolve: timer, grid, aspect, format, live', () {
    test('[CAM-041] allowed timers pass through; others snap to the nearest allowed value', () {
      for (final t in allowedTimers) {
        expect(r(CaptureIntent(timerSeconds: t)).settings.timerSeconds, t);
        expect(r(CaptureIntent(timerSeconds: t)).adjustments, isEmpty);
      }
      expect(r(const CaptureIntent(timerSeconds: 5)).settings.timerSeconds, 3);
      expect(r(const CaptureIntent(timerSeconds: 7)).settings.timerSeconds, 10);
      expect(r(const CaptureIntent(timerSeconds: -4)).settings.timerSeconds, 0);
      expect(r(const CaptureIntent(timerSeconds: 99)).adjustments.single.reason, AdjustmentReason.outOfRange);
    });

    test('[CAM-042] grid is a plain toggle', () {
      expect(r(const CaptureIntent(grid: true)).settings.grid, isTrue);
      expect(r(CaptureIntent.empty).settings.grid, isFalse);
    });

    test('[CAM-044] native aspect ratios need no crop; non-native ones are recorded as crop metadata', () {
      final native = r(const CaptureIntent(aspect: '4:3'));
      expect(native.settings.aspect, '4:3');
      expect(native.settings.cropNeeded, isFalse);
      final cropped = r(const CaptureIntent(aspect: '3:2'));
      expect(cropped.settings.aspect, '3:2');
      expect(cropped.settings.cropNeeded, isTrue);
      expect(r(const CaptureIntent(aspect: '16:9')).settings.cropNeeded, isFalse); // 4000x2250
      expect(r(const CaptureIntent(aspect: '1:1')).settings.cropNeeded, isFalse); // 3000x3000
      expect(r(const CaptureIntent(aspect: '3:2'), CameraCapabilities.none).settings.cropNeeded, isFalse); // unknown sizes
    });

    test('[CAM-044] an unknown aspect falls back to the sensor’s native one', () {
      final out = r(const CaptureIntent(aspect: '5:4'));
      expect(out.settings.aspect, '4:3');
      expect(out.adjustments.single.reason, AdjustmentReason.unsupported);
      final noNative4x3 = r(const CaptureIntent(aspect: 'zzz'), fullCamera.copyWith(photoSizes: const <PixelSize>[PixelSize(4000, 2250)]));
      expect(noNative4x3.settings.aspect, '16:9');
      expect(r(CaptureIntent.empty, CameraCapabilities.none).settings.aspect, '4:3');
    });

    test('[CAM-046] photo format: requested if offered, otherwise the best available with a fallback note', () {
      expect(r(const CaptureIntent(photoFormat: PhotoFormat.dng)).settings.photoFormat, PhotoFormat.dng);
      expect(r(CaptureIntent.empty).settings.photoFormat, PhotoFormat.heif);
      expect(r(CaptureIntent.empty, basicCamera).settings.photoFormat, PhotoFormat.jpeg);
      final fallback = r(const CaptureIntent(photoFormat: PhotoFormat.heif), basicCamera);
      expect(fallback.settings.photoFormat, PhotoFormat.jpeg);
      expect(fallback.adjustments.single.reason, AdjustmentReason.formatFallback);
      final dngOnly = fullCamera.copyWith(photoFormats: const <PhotoFormat>[PhotoFormat.dng]);
      expect(r(CaptureIntent.empty, dngOnly).settings.photoFormat, PhotoFormat.dng);
      final none = r(const CaptureIntent(photoFormat: PhotoFormat.heif), CameraCapabilities.none);
      expect(none.settings.photoFormat, isNull);
      expect(none.adjustments.single.reason, AdjustmentReason.unsupported);
      expect(r(CaptureIntent.empty, CameraCapabilities.none).settings.photoFormat, isNull);
    });

    test('[MOT-001][MOT-003] LIVE needs support; without a microphone the motion is silent and says so', () {
      expect(r(const CaptureIntent(live: true)).settings.live, isTrue);
      expect(r(const CaptureIntent(live: true)).settings.muteAudio, isFalse);
      final unsupported = r(const CaptureIntent(live: true), basicCamera);
      expect(unsupported.settings.live, isFalse);
      expect(unsupported.adjustments.single.reason, AdjustmentReason.unsupported);
      final noMic = r(const CaptureIntent(live: true), fullCamera.copyWith(live: const LiveCaps(supported: true, maxPreBufferMs: 1000)));
      expect(noMic.settings.muteAudio, isTrue);
      expect(noMic.adjustmentFor(IntentField.muteAudio)!.message, contains('silent'));
      expect(r(const CaptureIntent(live: true, muteAudio: true)).settings.muteAudio, isTrue);
      expect(r(const CaptureIntent(live: true, muteAudio: true), fullCamera.copyWith(live: const LiveCaps(supported: true))).adjustments, isEmpty);
    });

    test('the profile id is passed through', () {
      expect(r(const CaptureIntent(profileId: 'warm-film')).settings.profileId, 'warm-film');
    });
  });

  group('resolve: Experience constraints (spec rule 5)', () {
    test('[EXP-003] constraints are optional: without "authentic" the user overrides everything', () {
      final out = resolve(const CaptureIntent(aspect: '16:9'), fullCamera, experience: Experiences.instant);
      expect(out.settings.aspect, '16:9');
      expect(out.adjustmentFor(IntentField.aspect), isNull);
    });

    test('[EXP-003] "authentic" forces locked fields back to the Experience default and reports it', () {
      final out = resolve(const CaptureIntent(aspect: '16:9'), fullCamera, experience: Experiences.instant, authentic: true);
      expect(out.settings.aspect, '1:1');
      final adjustment = out.adjustmentFor(IntentField.aspect)!;
      expect(adjustment.reason, AdjustmentReason.experienceConstraint);
      expect(adjustment.requested, '16:9');
      expect(adjustment.applied, '1:1');
    });

    test('[EXP-003] "authentic" with the locked field unchanged is silent; unlocked fields stay free', () {
      final out = resolve(const CaptureIntent(aspect: '1:1', iso: 400), fullCamera, experience: Experiences.instant, authentic: true);
      expect(out.adjustments, isEmpty);
      expect(out.settings.iso, 400);
      // a locked field the user never set is still forced to the default
      expect(resolve(CaptureIntent.empty, fullCamera, experience: Experiences.instant, authentic: true).settings.aspect, '1:1');
    });

    test('[EXP-009] an authentic Film roll rejects the capture after its last frame, without throwing', () {
      final inside = resolve(CaptureIntent.empty, fullCamera, experience: Experiences.film, authentic: true, framesShot: 35);
      expect(inside.isRejected, isFalse);
      final done = resolve(CaptureIntent.empty, fullCamera, experience: Experiences.film, authentic: true, framesShot: 36);
      expect(done.isRejected, isTrue);
      expect(done.rejection!.code, 'roll_finished');
      expect(done.rejection!.message, contains('36'));
      expect(done.settings, isNotNull); // settings are still resolved
      expect(resolve(CaptureIntent.empty, fullCamera, experience: Experiences.film, framesShot: 99).isRejected, isFalse);
      expect(resolve(CaptureIntent.empty, fullCamera, experience: Experiences.mirrorless, authentic: true, framesShot: 999).isRejected, isFalse);
    });
  });

  group('resolve: whole-function guarantees', () {
    test('[CAM-005] an empty intent on a camera with no capabilities yields safe automatic settings', () {
      final out = r(CaptureIntent.empty, CameraCapabilities.none);
      expect(out.adjustments, isEmpty);
      expect(out.settings.iso, isNull);
      expect(out.settings.exposureTimeNs, isNull);
      expect(out.settings.focusMode, FocusMode.fixed);
      expect(out.settings.flash, FlashMode.off);
      expect(out.settings.zoom, 1);
      expect(out.settings.live, isFalse);
    });

    test('is deterministic: the same inputs give equal results', () {
      const intent = CaptureIntent(iso: 9999, zoom: 40, aspect: 'x', flash: FlashMode.on, timerSeconds: 5);
      final a = r(intent);
      final b = r(intent);
      expect(a.settings, b.settings);
      expect(a.adjustments, b.adjustments);
      expect(a.settings.hashCode, b.settings.hashCode);
    });

    test('adjustments are unmodifiable and findable by field', () {
      final out = r(const CaptureIntent(iso: 99999));
      expect(() => out.adjustments.add(out.adjustments.first), throwsUnsupportedError);
      expect(out.adjustmentFor(IntentField.iso), isNotNull);
      expect(out.adjustmentFor(IntentField.zoom), isNull);
    });

    test('[CAM-005][EXP-008] property: 20,000 random intents × random cameras never throw and always stay within capabilities', () {
      final rng = math.Random(20261113);
      for (var i = 0; i < 20000; i++) {
        final caps = randomCapabilities(rng);
        final intent = randomIntent(rng);
        final out = resolve(intent, caps);
        final s = out.settings;
        final label = 'case $i: $intent on ${caps.hashCode}';

        // exposure
        if (s.iso != null) {
          expect(caps.hasManualIso && caps.iso!.contains(s.iso!), isTrue, reason: label);
        }
        if (s.exposureTimeNs != null) {
          expect(caps.hasManualShutter && caps.exposureTimeNs!.contains(s.exposureTimeNs!), isTrue, reason: label);
        }
        if (s.exposureBiasEv != null) {
          expect(caps.exposureBias != null && caps.exposureBias!.range.contains(s.exposureBiasEv!), isTrue, reason: label);
          expect(s.fullyManualExposure, isFalse, reason: label);
          expect(s.exposureBiasEv!.isFinite, isTrue, reason: label);
        }
        if (s.fullyManualExposure) {
          expect(s.exposureLocked, isFalse, reason: label);
        }

        // focus
        switch (s.focusMode) {
          case FocusMode.continuous:
            expect(caps.focus.continuous, isTrue, reason: label);
          case FocusMode.auto:
            expect(caps.focus.auto, isTrue, reason: label);
          case FocusMode.manual:
            expect(caps.focus.manual, isNotNull, reason: label);
            expect(s.manualFocusDiopters, isNotNull, reason: label);
            expect(s.manualFocusDiopters!.isFinite && s.manualFocusDiopters! >= 0, isTrue, reason: label);
            expect(s.manualFocusDiopters! <= math.max(0, caps.focus.manual!.minFocusDistanceDiopters), isTrue, reason: label);
          case FocusMode.fixed:
            expect(s.focusLocked, isFalse, reason: label);
        }
        if (s.focusLocked) {
          expect(s.focusMode == FocusMode.auto || s.focusMode == FocusMode.continuous, isTrue, reason: label);
        }
        if (s.focusMode != FocusMode.manual) {
          expect(s.manualFocusDiopters, isNull, reason: label);
        }

        // white balance
        final kelvin = s.whiteBalance.kelvin;
        if (kelvin != null) {
          expect(caps.whiteBalance.kelvin != null && caps.whiteBalance.kelvin!.contains(kelvin), isTrue, reason: label);
        } else if (s.whiteBalance.preset != WbPreset.auto) {
          expect(caps.whiteBalance.presets.contains(s.whiteBalance.preset), isTrue, reason: label);
        }

        // zoom
        expect(s.zoom.isFinite && s.zoom > 0, isTrue, reason: label);
        if (caps.zoom.canZoom && caps.zoom.min.isFinite && caps.zoom.max.isFinite) {
          expect(s.zoom >= caps.zoom.min - 1e-9 && s.zoom <= caps.zoom.max + 1e-9, isTrue, reason: label);
        }
        expect(s.digitalZoom, s.zoom > caps.zoom.opticalMax + 1e-6, reason: label);

        // flash / torch / live
        expect(s.flash == FlashMode.off || caps.flash.contains(s.flash), isTrue, reason: label);
        if (s.torch) {
          expect(caps.torch, isTrue, reason: label);
        }
        if (s.live) {
          expect(caps.live.supported, isTrue, reason: label);
          if (!caps.live.audio) {
            expect(s.muteAudio, isTrue, reason: label);
          }
        }

        // timer, aspect, format
        expect(allowedTimers.contains(s.timerSeconds), isTrue, reason: label);
        expect(knownAspects.containsKey(s.aspect), isTrue, reason: label);
        if (s.photoFormat != null) {
          expect(caps.photoFormats.contains(s.photoFormat), isTrue, reason: label);
        } else {
          expect(caps.photoFormats, isEmpty, reason: label);
        }

        // determinism
        expect(resolve(intent, caps).settings, s, reason: label);

        // every deviation is explained
        if (intent.iso != null && s.iso != intent.iso) {
          expect(out.adjustmentFor(IntentField.iso), isNotNull, reason: label);
        }
        if (intent.exposureTimeNs != null && s.exposureTimeNs != intent.exposureTimeNs) {
          expect(out.adjustmentFor(IntentField.exposureTime), isNotNull, reason: label);
        }
        if (intent.flash != null && s.flash != intent.flash) {
          expect(out.adjustmentFor(IntentField.flash), isNotNull, reason: label);
        }
        if (intent.live == true && !s.live) {
          expect(out.adjustmentFor(IntentField.live), isNotNull, reason: label);
        }
        if (intent.torch == true && !s.torch) {
          expect(out.adjustmentFor(IntentField.torch), isNotNull, reason: label);
        }
        if (intent.timerSeconds != null && s.timerSeconds != intent.timerSeconds) {
          expect(out.adjustmentFor(IntentField.timer), isNotNull, reason: label);
        }
        for (final adjustment in out.adjustments) {
          expect(adjustment.message, isNotEmpty, reason: label);
        }
      }
    });
  });

  group('value types', () {
    test('ResolvedCaptureSettings equality and toString', () {
      expect(const ResolvedCaptureSettings(), const ResolvedCaptureSettings());
      expect(const ResolvedCaptureSettings(iso: 1), isNot(const ResolvedCaptureSettings(iso: 2)));
      expect(const ResolvedCaptureSettings().toString(), contains('ResolvedCaptureSettings'));
      expect(const ResolvedWhiteBalance(preset: WbPreset.auto, kelvin: 5000).toString(), 'WB(5000K)');
      expect(const ResolvedWhiteBalance(preset: WbPreset.daylight).toString(), 'WB(daylight)');
    });

    test('Adjustment equality, hash and toString', () {
      const a = Adjustment(field: IntentField.iso, requested: 1, applied: 2, reason: AdjustmentReason.outOfRange, message: 'm');
      const b = Adjustment(field: IntentField.iso, requested: 1, applied: 2, reason: AdjustmentReason.outOfRange, message: 'm');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('iso'));
      expect(a, isNot(const Adjustment(field: IntentField.iso, requested: 1, applied: 3, reason: AdjustmentReason.outOfRange, message: 'm')));
    });

    test('capability ranges clamp, compare and describe themselves', () {
      expect(const IntRange(1, 5).clamp(9), 5);
      expect(const IntRange(1, 5).clamp(-9), 1);
      expect(const IntRange(1, 5).contains(3), isTrue);
      expect(const IntRange(1, 5), const IntRange(1, 5));
      expect(const IntRange(1, 5).toString(), 'IntRange(1..5)');
      expect(const DoubleRange(1, 5).clamp(9), 5);
      expect(const DoubleRange(1, 5).clamp(-9), 1);
      expect(const DoubleRange(1, 5), const DoubleRange(1, 5));
      expect(const DoubleRange(1, 5).isValid, isTrue);
      expect(const DoubleRange(1, 5).hashCode, const DoubleRange(1, 5).hashCode);
      expect(const DoubleRange(1, 5).toString(), contains('1.0'));
    });

    test('PixelSize reports common aspect labels within 1%', () {
      expect(const PixelSize(4000, 3000).aspectLabel, '4:3');
      expect(const PixelSize(3000, 4000).aspectLabel, '4:3');
      expect(const PixelSize(4032, 2688).aspectLabel, '3:2');
      expect(const PixelSize(1920, 1080).aspectLabel, '16:9');
      expect(const PixelSize(2000, 2000).aspectLabel, '1:1');
      expect(const PixelSize(1234, 777).aspectLabel, isNull);
      expect(const PixelSize(0, 10).aspectLabel, isNull);
      expect(const PixelSize(4000, 3000), const PixelSize(4000, 3000));
      expect(const PixelSize(4000, 3000).pixels, 12000000);
      expect(const PixelSize(4000, 3000).toString(), '4000x3000');
    });

    test('capability value types compare structurally', () {
      expect(fullCamera.focus, fullCamera.focus);
      expect(const FocusCaps(auto: true), const FocusCaps(auto: true));
      expect(const FocusCaps(auto: true), isNot(const FocusCaps()));
      expect(const ManualFocusCaps(minFocusDistanceDiopters: 1, calibration: FocusCalibration.calibrated).canLabelDistance, isTrue);
      expect(const ManualFocusCaps(minFocusDistanceDiopters: 1, calibration: FocusCalibration.uncalibrated).canLabelDistance, isFalse);
      expect(const WhiteBalanceCaps(presets: <WbPreset>{WbPreset.auto}), const WhiteBalanceCaps(presets: <WbPreset>{WbPreset.auto}));
      expect(const ZoomCaps(opticalSteps: <double>[1]), const ZoomCaps(opticalSteps: <double>[1]));
      expect(const ZoomCaps(opticalSteps: <double>[1]), isNot(const ZoomCaps(opticalSteps: <double>[1, 2])));
      expect(const LiveCaps(supported: true), const LiveCaps(supported: true));
      expect(const ExposureBiasCaps(range: DoubleRange(-1, 1), step: 0.5), const ExposureBiasCaps(range: DoubleRange(-1, 1), step: 0.5));
      expect(fullCamera.apertureControllable, isFalse);
      expect(fullCamera.copyWith(apertures: const <double>[1.4, 2.8]).apertureControllable, isTrue);
      expect(fullCamera.nativeAspects, <String>{'4:3', '16:9', '1:1'});
      expect(fullCamera.copyWith(clearIso: true, clearExposureTime: true, clearExposureBias: true).iso, isNull);
    });
  });
}
