/// The intent resolver (docs/specs/camera.md "Intent resolution", ADR-0003).
///
/// `resolve(intent, capabilities)` is pure, total and deterministic: it never throws for any input, and
/// every value it returns lies within the capabilities. Each change it makes is reported as an [Adjustment]
/// (EXP-008) so the UI can say what changed and why.
library;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/experience/experience.dart';

/// Allowed self-timer values (CAM-041).
const List<int> allowedTimers = <int>[0, 3, 10];

class ResolveResult {
  const ResolveResult({required this.settings, required this.adjustments, this.rejection});

  final ResolvedCaptureSettings settings;
  final List<Adjustment> adjustments;

  /// Set when the Experience validator refuses the capture (e.g. an authentic roll is finished).
  final ConstraintRejection? rejection;

  bool get isRejected => rejection != null;

  Adjustment? adjustmentFor(IntentField field) {
    for (final adjustment in adjustments) {
      if (adjustment.field == field) {
        return adjustment;
      }
    }
    return null;
  }
}

String _ns(int ns) {
  if (ns >= 1000000000) {
    return '${(ns / 1e9).toStringAsFixed(ns % 1000000000 == 0 ? 0 : 1)} s';
  }
  return '1/${(1e9 / ns).round()} s';
}

/// Resolves [intent] against [caps].
///
/// With an [experience] and [authentic] set, the Experience's locked fields are forced to its defaults and
/// the roll validator runs last (spec rule 5), reporting a [ConstraintRejection] instead of throwing.
ResolveResult resolve(
  CaptureIntent intent,
  CameraCapabilities caps, {
  Experience? experience,
  bool authentic = false,
  int framesShot = 0,
}) {
  final adjustments = <Adjustment>[];
  var request = intent;

  // Experience "authentic" constraint: locked fields snap back to the Experience default.
  if (experience != null && authentic) {
    final defaults = experience.defaultsWithProfile;
    for (final field in experience.authenticLocks) {
      final wanted = request.valueOf(field);
      final locked = defaults.valueOf(field);
      if (wanted != null && locked != null && wanted != locked) {
        adjustments.add(
          Adjustment(
            field: field,
            requested: wanted,
            applied: locked,
            reason: AdjustmentReason.experienceConstraint,
            message: '${experience.name} keeps this fixed while "authentic" is on.',
          ),
        );
      }
    }
    request = request.without(experience.authenticLocks).merge(
          CaptureIntent.empty.merge(_only(defaults, experience.authenticLocks)),
        );
  }

  // ---- exposure -----------------------------------------------------------------------------
  int? iso;
  if (request.iso != null) {
    final range = caps.iso;
    if (range == null || !range.isValid) {
      adjustments.add(Adjustment(
        field: IntentField.iso,
        requested: request.iso,
        applied: null,
        reason: AdjustmentReason.unsupported,
        message: 'Manual ISO is not available on this camera, so ISO stays automatic.',
      ));
    } else {
      iso = range.clamp(request.iso!);
      if (iso != request.iso) {
        adjustments.add(Adjustment(
          field: IntentField.iso,
          requested: request.iso,
          applied: iso,
          reason: AdjustmentReason.outOfRange,
          message: 'ISO ${request.iso} → $iso: this camera supports ISO ${range.min}–${range.max}.',
        ));
      }
    }
  }

  int? exposureTime;
  if (request.exposureTimeNs != null) {
    final range = caps.exposureTimeNs;
    if (range == null || !range.isValid) {
      adjustments.add(Adjustment(
        field: IntentField.exposureTime,
        requested: request.exposureTimeNs,
        applied: null,
        reason: AdjustmentReason.unsupported,
        message: 'Manual shutter speed is not available on this camera, so it stays automatic.',
      ));
    } else {
      exposureTime = range.clamp(request.exposureTimeNs!);
      if (exposureTime != request.exposureTimeNs) {
        adjustments.add(Adjustment(
          field: IntentField.exposureTime,
          requested: request.exposureTimeNs,
          applied: exposureTime,
          reason: AdjustmentReason.outOfRange,
          message: 'Shutter ${_ns(request.exposureTimeNs!)} → ${_ns(exposureTime)}: '
              'this camera supports ${_ns(range.min)} to ${_ns(range.max)}.',
        ));
      }
    }
  }

  final fullyManual = iso != null && exposureTime != null;

  double? bias;
  if (request.exposureBiasEv != null) {
    final wanted = request.exposureBiasEv!;
    final caps0 = caps.exposureBias;
    if (!wanted.isFinite) {
      adjustments.add(Adjustment(
        field: IntentField.exposureBias,
        requested: wanted,
        applied: null,
        reason: AdjustmentReason.outOfRange,
        message: 'That exposure compensation is not a valid number, so it was ignored.',
      ));
    } else if (caps0 == null || !caps0.range.isValid) {
      adjustments.add(Adjustment(
        field: IntentField.exposureBias,
        requested: wanted,
        applied: null,
        reason: AdjustmentReason.unsupported,
        message: 'Exposure compensation is not available on this camera.',
      ));
    } else if (fullyManual) {
      adjustments.add(Adjustment(
        field: IntentField.exposureBias,
        requested: wanted,
        applied: null,
        reason: AdjustmentReason.notApplicableInManual,
        message: 'Exposure compensation is ignored when ISO and shutter are both manual.',
      ));
    } else {
      var applied = caps0.range.clamp(wanted);
      if (caps0.step > 0) {
        applied = caps0.range.clamp((applied / caps0.step).round() * caps0.step);
      }
      bias = applied;
      if ((wanted - applied).abs() > caps0.step / 2 + 1e-9) {
        adjustments.add(Adjustment(
          field: IntentField.exposureBias,
          requested: wanted,
          applied: applied,
          reason: AdjustmentReason.outOfRange,
          message: 'Exposure compensation ${wanted.toStringAsFixed(1)} → ${applied.toStringAsFixed(1)} EV: '
              'this camera supports ${caps0.range.min}–${caps0.range.max} EV.',
        ));
      }
    }
  }

  var exposureLocked = request.exposureLock ?? false;
  if (exposureLocked && fullyManual) {
    exposureLocked = false;
    adjustments.add(Adjustment(
      field: IntentField.exposureLock,
      requested: true,
      applied: false,
      reason: AdjustmentReason.notApplicableInManual,
      message: 'Exposure lock does nothing when ISO and shutter are both manual.',
    ));
  }

  // ---- focus --------------------------------------------------------------------------------
  final focusCaps = caps.focus;
  FocusMode autoFallback() => focusCaps.auto ? FocusMode.auto : FocusMode.fixed;
  var focusMode = focusCaps.continuous
      ? FocusMode.continuous
      : (focusCaps.auto ? FocusMode.auto : FocusMode.fixed);
  double? manualDiopters;
  switch (request.focus) {
    case null:
      break;
    case FocusRequest.auto:
      focusMode = autoFallback();
      if (!focusCaps.auto) {
        adjustments.add(_unsupported(IntentField.focusMode, request.focus, focusMode, 'Autofocus is not available on this camera.'));
      }
    case FocusRequest.continuous:
      if (focusCaps.continuous) {
        focusMode = FocusMode.continuous;
      } else {
        focusMode = autoFallback();
        adjustments.add(_unsupported(
          IntentField.focusMode,
          request.focus,
          focusMode,
          focusCaps.auto
              ? 'Continuous focus is not available, so single autofocus is used.'
              : 'This camera has fixed focus.',
        ));
      }
    case FocusRequest.manual:
      final manual = focusCaps.manual;
      if (manual == null) {
        focusMode = autoFallback();
        adjustments.add(_unsupported(
          IntentField.focusMode,
          request.focus,
          focusMode,
          'Manual focus is not available on this camera, so autofocus is used.',
        ));
      } else {
        focusMode = FocusMode.manual;
        final wanted = request.manualFocusDiopters;
        final limit = manual.minFocusDistanceDiopters.isFinite && manual.minFocusDistanceDiopters > 0 ? manual.minFocusDistanceDiopters : 0.0;
        if (wanted == null) {
          manualDiopters = 0;
        } else if (!wanted.isFinite) {
          manualDiopters = 0;
          adjustments.add(Adjustment(
            field: IntentField.manualFocus,
            requested: wanted,
            applied: 0.0,
            reason: AdjustmentReason.outOfRange,
            message: 'That focus distance is not valid, so focus was set to infinity.',
          ));
        } else {
          manualDiopters = wanted.clamp(0.0, limit);
          if (manualDiopters != wanted) {
            adjustments.add(Adjustment(
              field: IntentField.manualFocus,
              requested: wanted,
              applied: manualDiopters,
              reason: AdjustmentReason.outOfRange,
              message: 'Focus distance adjusted: this camera focuses from infinity to ${limit > 0 ? '${(1 / limit * 100).round()} cm' : 'infinity'}.',
            ));
          }
        }
      }
  }
  var focusLocked = request.focusLock ?? false;
  if (focusLocked && (focusMode == FocusMode.fixed || focusMode == FocusMode.manual)) {
    focusLocked = false;
    adjustments.add(Adjustment(
      field: IntentField.focusLock,
      requested: true,
      applied: false,
      reason: focusMode == FocusMode.fixed ? AdjustmentReason.unsupported : AdjustmentReason.notApplicableInManual,
      message: focusMode == FocusMode.fixed
          ? 'Focus lock is not available on a fixed-focus camera.'
          : 'Focus lock is for autofocus; manual focus already stays where you set it.',
    ));
  }

  // ---- white balance ------------------------------------------------------------------------
  var whiteBalance = const ResolvedWhiteBalance(preset: WbPreset.auto);
  final wbRequest = request.whiteBalance;
  if (wbRequest != null) {
    final kelvinCaps = caps.whiteBalance.kelvin;
    if (wbRequest.kelvin != null) {
      if (kelvinCaps == null || !kelvinCaps.isValid) {
        adjustments.add(_unsupported(
          IntentField.whiteBalance,
          wbRequest,
          whiteBalance,
          'White balance in Kelvin is not available on this camera, so it stays automatic.',
        ));
      } else {
        final kelvin = kelvinCaps.clamp(wbRequest.kelvin!);
        whiteBalance = ResolvedWhiteBalance(preset: WbPreset.auto, kelvin: kelvin);
        if (kelvin != wbRequest.kelvin) {
          adjustments.add(Adjustment(
            field: IntentField.whiteBalance,
            requested: wbRequest,
            applied: kelvin,
            reason: AdjustmentReason.outOfRange,
            message: 'White balance ${wbRequest.kelvin} K → $kelvin K: this camera supports ${kelvinCaps.min}–${kelvinCaps.max} K.',
          ));
        }
      }
    } else {
      final preset = wbRequest.preset!;
      if (preset == WbPreset.auto || caps.whiteBalance.presets.contains(preset)) {
        whiteBalance = ResolvedWhiteBalance(preset: preset);
      } else {
        adjustments.add(_unsupported(
          IntentField.whiteBalance,
          wbRequest,
          whiteBalance,
          'The ${preset.name} white balance is not available on this camera, so it stays automatic.',
        ));
      }
    }
  }

  // ---- zoom ---------------------------------------------------------------------------------
  final zoomCaps = caps.zoom;
  final zoomMin = zoomCaps.min.isFinite ? zoomCaps.min : 1.0;
  final zoomMax = zoomCaps.max.isFinite && zoomCaps.max >= zoomMin ? zoomCaps.max : zoomMin;
  var zoom = 1.0.clamp(zoomMin, zoomMax);
  final zoomRequest = request.zoom;
  if (zoomRequest != null) {
    if (!zoomRequest.isFinite || zoomRequest <= 0) {
      adjustments.add(Adjustment(
        field: IntentField.zoom,
        requested: zoomRequest,
        applied: zoom,
        reason: AdjustmentReason.outOfRange,
        message: 'That zoom is not valid, so the default zoom is used.',
      ));
    } else {
      zoom = zoomRequest.clamp(zoomMin, zoomMax);
      if (zoom != zoomRequest) {
        adjustments.add(Adjustment(
          field: IntentField.zoom,
          requested: zoomRequest,
          applied: zoom,
          reason: AdjustmentReason.outOfRange,
          message: 'Zoom ${zoomRequest.toStringAsFixed(1)}× → ${zoom.toStringAsFixed(1)}×: '
              'this camera zooms ${zoomMin.toStringAsFixed(1)}–${zoomMax.toStringAsFixed(1)}×.',
        ));
      }
    }
  }
  final digitalZoom = zoom > zoomCaps.opticalMax + 1e-6;

  // ---- flash and torch ----------------------------------------------------------------------
  var flash = FlashMode.off;
  if (request.flash != null) {
    if (request.flash == FlashMode.off || caps.flash.contains(request.flash)) {
      flash = request.flash!;
    } else {
      adjustments.add(_unsupported(
        IntentField.flash,
        request.flash,
        FlashMode.off,
        'Flash mode ${request.flash!.name} is not available on this camera, so flash stays off.',
      ));
    }
  }
  var torch = false;
  if (request.torch ?? false) {
    if (caps.torch) {
      torch = true;
    } else {
      adjustments.add(_unsupported(IntentField.torch, true, false, 'This camera has no torch.'));
    }
  }

  // ---- timer, grid, aspect, format ----------------------------------------------------------
  var timer = 0;
  if (request.timerSeconds != null) {
    final wanted = request.timerSeconds!;
    if (allowedTimers.contains(wanted)) {
      timer = wanted;
    } else {
      timer = allowedTimers.reduce((a, b) => (a - wanted).abs() <= (b - wanted).abs() ? a : b);
      adjustments.add(Adjustment(
        field: IntentField.timer,
        requested: wanted,
        applied: timer,
        reason: AdjustmentReason.outOfRange,
        message: 'The timer offers 0, 3 or 10 seconds, so $timer s is used.',
      ));
    }
  }

  final nativeAspects = caps.nativeAspects;
  var aspect = nativeAspects.isNotEmpty
      ? (nativeAspects.contains('4:3') ? '4:3' : (nativeAspects.toList()..sort()).first)
      : '4:3';
  if (request.aspect != null) {
    if (knownAspects.containsKey(request.aspect)) {
      aspect = request.aspect!;
    } else {
      adjustments.add(_unsupported(IntentField.aspect, request.aspect, aspect, '${request.aspect} is not an available aspect ratio.'));
    }
  }
  final cropNeeded = caps.photoSizes.isNotEmpty && !nativeAspects.contains(aspect);

  PhotoFormat? format;
  if (caps.photoFormats.isNotEmpty) {
    PhotoFormat preferred() {
      if (caps.photoFormats.contains(PhotoFormat.heif)) {
        return PhotoFormat.heif;
      }
      if (caps.photoFormats.contains(PhotoFormat.jpeg)) {
        return PhotoFormat.jpeg;
      }
      return caps.photoFormats.first;
    }

    if (request.photoFormat != null && caps.photoFormats.contains(request.photoFormat)) {
      format = request.photoFormat;
    } else {
      format = preferred();
      if (request.photoFormat != null) {
        adjustments.add(Adjustment(
          field: IntentField.photoFormat,
          requested: request.photoFormat,
          applied: format,
          reason: AdjustmentReason.formatFallback,
          message: '${request.photoFormat!.name.toUpperCase()} is not available, so ${format.name.toUpperCase()} is used.',
        ));
      }
    }
  } else if (request.photoFormat != null) {
    adjustments.add(_unsupported(IntentField.photoFormat, request.photoFormat, null, 'This camera reports no photo formats.'));
  }

  // ---- LIVE ---------------------------------------------------------------------------------
  var live = false;
  if (request.live ?? false) {
    if (caps.live.supported) {
      live = true;
    } else {
      adjustments.add(_unsupported(IntentField.live, true, false, 'Motion capture (LIVE) is not available on this camera.'));
    }
  }
  var mute = request.muteAudio ?? false;
  if (live && !caps.live.audio && !mute) {
    mute = true;
    adjustments.add(_unsupported(IntentField.muteAudio, false, true, 'No microphone is available, so this motion will be silent.'));
  }

  final settings = ResolvedCaptureSettings(
    iso: iso,
    exposureTimeNs: exposureTime,
    exposureBiasEv: bias,
    exposureLocked: exposureLocked,
    focusMode: focusMode,
    manualFocusDiopters: manualDiopters,
    focusLocked: focusLocked,
    whiteBalance: whiteBalance,
    zoom: zoom,
    digitalZoom: digitalZoom,
    flash: flash,
    torch: torch,
    timerSeconds: timer,
    grid: request.grid ?? false,
    aspect: aspect,
    cropNeeded: cropNeeded,
    photoFormat: format,
    lens: request.lens,
    live: live,
    muteAudio: mute,
    profileId: request.profileId,
  );

  final rejection = experience?.validate(authentic: authentic, framesShot: framesShot);
  return ResolveResult(settings: settings, adjustments: List<Adjustment>.unmodifiable(adjustments), rejection: rejection);
}

Adjustment _unsupported(IntentField field, Object? requested, Object? applied, String message) => Adjustment(
      field: field,
      requested: requested,
      applied: applied,
      reason: AdjustmentReason.unsupported,
      message: message,
    );

/// The fields of [source] restricted to [fields].
CaptureIntent _only(CaptureIntent source, Set<IntentField> fields) =>
    source.without(IntentField.values.toSet().difference(fields));

