/// What the user (or an Experience, scenario or preset) asks for, and what the camera is told to do (ADR-0003).
library;

import 'package:doro_cam/domain/camera/capabilities.dart';

/// Every field an intent can carry. Used for provenance, adjustments, and Experience locks.
enum IntentField {
  iso,
  exposureTime,
  exposureBias,
  exposureLock,
  focusMode,
  manualFocus,
  focusLock,
  whiteBalance,
  zoom,
  flash,
  torch,
  timer,
  grid,
  aspect,
  photoFormat,
  lens,
  live,
  muteAudio,
  profile,
}

enum FocusRequest { auto, continuous, manual }

/// What the camera will actually do about focus. `fixed` means the camera offers no focus control at all.
enum FocusMode { fixed, auto, continuous, manual }

/// A white-balance request: a preset, or a temperature in Kelvin. Exactly one of the two is set.
class WbRequest {
  const WbRequest.preset(WbPreset this.preset) : kelvin = null;
  const WbRequest.kelvin(int this.kelvin) : preset = null;

  final WbPreset? preset;
  final int? kelvin;

  Map<String, Object?> toJson() => <String, Object?>{
        if (preset != null) 'preset': preset!.name,
        if (kelvin != null) 'kelvin': kelvin,
      };

  static WbRequest? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final kelvin = json['kelvin'];
    if (kelvin is int) {
      return WbRequest.kelvin(kelvin);
    }
    final name = json['preset'];
    for (final value in WbPreset.values) {
      if (value.name == name) {
        return WbRequest.preset(value);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is WbRequest && other.preset == preset && other.kelvin == kelvin;

  @override
  int get hashCode => Object.hash(preset, kelvin);

  @override
  String toString() => preset != null ? 'WbRequest(${preset!.name})' : 'WbRequest(${kelvin}K)';
}

/// A *partial* request: every field is optional, and null means "not specified, fall through to the
/// next layer". Intents are immutable; [merge] combines layers field by field.
class CaptureIntent {
  const CaptureIntent({
    this.iso,
    this.exposureTimeNs,
    this.exposureBiasEv,
    this.exposureLock,
    this.focus,
    this.manualFocusDiopters,
    this.focusLock,
    this.whiteBalance,
    this.zoom,
    this.flash,
    this.torch,
    this.timerSeconds,
    this.grid,
    this.aspect,
    this.photoFormat,
    this.lens,
    this.live,
    this.muteAudio,
    this.profileId,
  });

  static const CaptureIntent empty = CaptureIntent();

  final int? iso;
  final int? exposureTimeNs;
  final double? exposureBiasEv;
  final bool? exposureLock;
  final FocusRequest? focus;
  final double? manualFocusDiopters;
  final bool? focusLock;
  final WbRequest? whiteBalance;
  final double? zoom;
  final FlashMode? flash;
  final bool? torch;
  final int? timerSeconds;
  final bool? grid;
  final String? aspect;
  final PhotoFormat? photoFormat;
  final LensKind? lens;
  final bool? live;
  final bool? muteAudio;
  final String? profileId;

  /// The fields this intent specifies.
  Set<IntentField> get specifiedFields => <IntentField>{
        if (iso != null) IntentField.iso,
        if (exposureTimeNs != null) IntentField.exposureTime,
        if (exposureBiasEv != null) IntentField.exposureBias,
        if (exposureLock != null) IntentField.exposureLock,
        if (focus != null) IntentField.focusMode,
        if (manualFocusDiopters != null) IntentField.manualFocus,
        if (focusLock != null) IntentField.focusLock,
        if (whiteBalance != null) IntentField.whiteBalance,
        if (zoom != null) IntentField.zoom,
        if (flash != null) IntentField.flash,
        if (torch != null) IntentField.torch,
        if (timerSeconds != null) IntentField.timer,
        if (grid != null) IntentField.grid,
        if (aspect != null) IntentField.aspect,
        if (photoFormat != null) IntentField.photoFormat,
        if (lens != null) IntentField.lens,
        if (live != null) IntentField.live,
        if (muteAudio != null) IntentField.muteAudio,
        if (profileId != null) IntentField.profile,
      };

  bool get isEmpty => specifiedFields.isEmpty;

  /// Fields of [other] that are specified win; everything else comes from this intent.
  CaptureIntent merge(CaptureIntent other) => CaptureIntent(
        iso: other.iso ?? iso,
        exposureTimeNs: other.exposureTimeNs ?? exposureTimeNs,
        exposureBiasEv: other.exposureBiasEv ?? exposureBiasEv,
        exposureLock: other.exposureLock ?? exposureLock,
        focus: other.focus ?? focus,
        manualFocusDiopters: other.manualFocusDiopters ?? manualFocusDiopters,
        focusLock: other.focusLock ?? focusLock,
        whiteBalance: other.whiteBalance ?? whiteBalance,
        zoom: other.zoom ?? zoom,
        flash: other.flash ?? flash,
        torch: other.torch ?? torch,
        timerSeconds: other.timerSeconds ?? timerSeconds,
        grid: other.grid ?? grid,
        aspect: other.aspect ?? aspect,
        photoFormat: other.photoFormat ?? photoFormat,
        lens: other.lens ?? lens,
        live: other.live ?? live,
        muteAudio: other.muteAudio ?? muteAudio,
        profileId: other.profileId ?? profileId,
      );

  /// A copy with the given fields cleared (e.g. "go back to auto ISO").
  CaptureIntent without(Set<IntentField> fields) => CaptureIntent(
        iso: fields.contains(IntentField.iso) ? null : iso,
        exposureTimeNs: fields.contains(IntentField.exposureTime) ? null : exposureTimeNs,
        exposureBiasEv: fields.contains(IntentField.exposureBias) ? null : exposureBiasEv,
        exposureLock: fields.contains(IntentField.exposureLock) ? null : exposureLock,
        focus: fields.contains(IntentField.focusMode) ? null : focus,
        manualFocusDiopters: fields.contains(IntentField.manualFocus) ? null : manualFocusDiopters,
        focusLock: fields.contains(IntentField.focusLock) ? null : focusLock,
        whiteBalance: fields.contains(IntentField.whiteBalance) ? null : whiteBalance,
        zoom: fields.contains(IntentField.zoom) ? null : zoom,
        flash: fields.contains(IntentField.flash) ? null : flash,
        torch: fields.contains(IntentField.torch) ? null : torch,
        timerSeconds: fields.contains(IntentField.timer) ? null : timerSeconds,
        grid: fields.contains(IntentField.grid) ? null : grid,
        aspect: fields.contains(IntentField.aspect) ? null : aspect,
        photoFormat: fields.contains(IntentField.photoFormat) ? null : photoFormat,
        lens: fields.contains(IntentField.lens) ? null : lens,
        live: fields.contains(IntentField.live) ? null : live,
        muteAudio: fields.contains(IntentField.muteAudio) ? null : muteAudio,
        profileId: fields.contains(IntentField.profile) ? null : profileId,
      );

  /// Value of one field (for provenance and tests).
  Object? valueOf(IntentField field) => switch (field) {
        IntentField.iso => iso,
        IntentField.exposureTime => exposureTimeNs,
        IntentField.exposureBias => exposureBiasEv,
        IntentField.exposureLock => exposureLock,
        IntentField.focusMode => focus,
        IntentField.manualFocus => manualFocusDiopters,
        IntentField.focusLock => focusLock,
        IntentField.whiteBalance => whiteBalance,
        IntentField.zoom => zoom,
        IntentField.flash => flash,
        IntentField.torch => torch,
        IntentField.timer => timerSeconds,
        IntentField.grid => grid,
        IntentField.aspect => aspect,
        IntentField.photoFormat => photoFormat,
        IntentField.lens => lens,
        IntentField.live => live,
        IntentField.muteAudio => muteAudio,
        IntentField.profile => profileId,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        if (iso != null) 'iso': iso,
        if (exposureTimeNs != null) 'exposureTimeNs': exposureTimeNs,
        if (exposureBiasEv != null) 'exposureBiasEv': exposureBiasEv,
        if (exposureLock != null) 'exposureLock': exposureLock,
        if (focus != null) 'focus': focus!.name,
        if (manualFocusDiopters != null) 'manualFocusDiopters': manualFocusDiopters,
        if (focusLock != null) 'focusLock': focusLock,
        if (whiteBalance != null) 'whiteBalance': whiteBalance!.toJson(),
        if (zoom != null) 'zoom': zoom,
        if (flash != null) 'flash': flash!.name,
        if (torch != null) 'torch': torch,
        if (timerSeconds != null) 'timerSeconds': timerSeconds,
        if (grid != null) 'grid': grid,
        if (aspect != null) 'aspect': aspect,
        if (photoFormat != null) 'photoFormat': photoFormat!.name,
        if (lens != null) 'lens': lens!.name,
        if (live != null) 'live': live,
        if (muteAudio != null) 'muteAudio': muteAudio,
        if (profileId != null) 'profileId': profileId,
      };

  /// Lenient: unknown or mistyped entries are ignored (an old/new app version must never crash on a preset).
  factory CaptureIntent.fromJson(Map<String, Object?> json) {
    T? named<T extends Enum>(List<T> values, Object? raw) {
      for (final value in values) {
        if (value.name == raw) {
          return value;
        }
      }
      return null;
    }

    double? number(Object? raw) => raw is num ? raw.toDouble() : null;
    int? integer(Object? raw) => raw is int ? raw : (raw is num && raw == raw.truncate() ? raw.toInt() : null);
    bool? boolean(Object? raw) => raw is bool ? raw : null;
    return CaptureIntent(
      iso: integer(json['iso']),
      exposureTimeNs: integer(json['exposureTimeNs']),
      exposureBiasEv: number(json['exposureBiasEv']),
      exposureLock: boolean(json['exposureLock']),
      focus: named(FocusRequest.values, json['focus']),
      manualFocusDiopters: number(json['manualFocusDiopters']),
      focusLock: boolean(json['focusLock']),
      whiteBalance: WbRequest.fromJson(json['whiteBalance']),
      zoom: number(json['zoom']),
      flash: named(FlashMode.values, json['flash']),
      torch: boolean(json['torch']),
      timerSeconds: integer(json['timerSeconds']),
      grid: boolean(json['grid']),
      aspect: json['aspect'] is String ? json['aspect']! as String : null,
      photoFormat: named(PhotoFormat.values, json['photoFormat']),
      lens: named(LensKind.values, json['lens']),
      live: boolean(json['live']),
      muteAudio: boolean(json['muteAudio']),
      profileId: json['profileId'] is String ? json['profileId']! as String : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! CaptureIntent) {
      return false;
    }
    for (final field in IntentField.values) {
      if (valueOf(field) != other.valueOf(field)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[for (final field in IntentField.values) valueOf(field)]);

  @override
  String toString() => 'CaptureIntent(${toJson()})';
}

/// The white balance the camera will use.
class ResolvedWhiteBalance {
  const ResolvedWhiteBalance({required this.preset, this.kelvin});

  /// `auto` when [kelvin] is set is never produced: Kelvin implies a manual, preset-less balance.
  final WbPreset preset;
  final int? kelvin;

  @override
  bool operator ==(Object other) => other is ResolvedWhiteBalance && other.preset == preset && other.kelvin == kelvin;

  @override
  int get hashCode => Object.hash(preset, kelvin);

  @override
  String toString() => kelvin != null ? 'WB(${kelvin}K)' : 'WB(${preset.name})';
}

/// Why a requested value was changed (EXP-008).
enum AdjustmentReason {
  /// Clamped into the device's range (or invalid like NaN).
  outOfRange,

  /// The camera has no such capability; the request became automatic / default.
  unsupported,

  /// The value does not apply in the current mode (e.g. exposure bias in full manual exposure).
  notApplicableInManual,

  /// The requested format/size is not available; another was chosen.
  formatFallback,

  /// An "authentic" Experience constraint overrode the request.
  experienceConstraint,
}

/// One change made by the resolver, shown to the user ("ISO 6400 → 3200: the camera's maximum").
class Adjustment {
  const Adjustment({
    required this.field,
    required this.requested,
    required this.applied,
    required this.reason,
    required this.message,
  });

  final IntentField field;
  final Object? requested;
  final Object? applied;
  final AdjustmentReason reason;

  /// A short, human sentence for the UI.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is Adjustment &&
      other.field == field &&
      other.requested == requested &&
      other.applied == applied &&
      other.reason == reason &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, requested, applied, reason, message);

  @override
  String toString() => 'Adjustment($field: $requested → $applied, ${reason.name})';
}

/// Concrete settings the native camera applies. `null` for iso/exposureTime/exposureBias means automatic.
class ResolvedCaptureSettings {
  const ResolvedCaptureSettings({
    this.iso,
    this.exposureTimeNs,
    this.exposureBiasEv,
    this.exposureLocked = false,
    this.focusMode = FocusMode.fixed,
    this.manualFocusDiopters,
    this.focusLocked = false,
    this.whiteBalance = const ResolvedWhiteBalance(preset: WbPreset.auto),
    this.zoom = 1,
    this.digitalZoom = false,
    this.flash = FlashMode.off,
    this.torch = false,
    this.timerSeconds = 0,
    this.grid = false,
    this.aspect = '4:3',
    this.cropNeeded = false,
    this.photoFormat,
    this.lens,
    this.live = false,
    this.muteAudio = false,
    this.profileId,
  });

  final int? iso;
  final int? exposureTimeNs;
  final double? exposureBiasEv;
  final bool exposureLocked;
  final FocusMode focusMode;
  final double? manualFocusDiopters;
  final bool focusLocked;
  final ResolvedWhiteBalance whiteBalance;
  final double zoom;

  /// True when [zoom] is beyond the largest optical step. Digital zoom must be labelled (CAM-008).
  final bool digitalZoom;
  final FlashMode flash;
  final bool torch;
  final int timerSeconds;
  final bool grid;
  final String aspect;

  /// True when [aspect] is not native: the original stays uncropped and the crop is recorded as metadata (CAM-044).
  final bool cropNeeded;
  final PhotoFormat? photoFormat;
  final LensKind? lens;
  final bool live;
  final bool muteAudio;
  final String? profileId;

  bool get manualIso => iso != null;
  bool get manualShutter => exposureTimeNs != null;

  /// "Fully manual" means both ISO and shutter are set; only then is exposure bias meaningless.
  bool get fullyManualExposure => manualIso && manualShutter;

  @override
  bool operator ==(Object other) =>
      other is ResolvedCaptureSettings &&
      other.iso == iso &&
      other.exposureTimeNs == exposureTimeNs &&
      other.exposureBiasEv == exposureBiasEv &&
      other.exposureLocked == exposureLocked &&
      other.focusMode == focusMode &&
      other.manualFocusDiopters == manualFocusDiopters &&
      other.focusLocked == focusLocked &&
      other.whiteBalance == whiteBalance &&
      other.zoom == zoom &&
      other.digitalZoom == digitalZoom &&
      other.flash == flash &&
      other.torch == torch &&
      other.timerSeconds == timerSeconds &&
      other.grid == grid &&
      other.aspect == aspect &&
      other.cropNeeded == cropNeeded &&
      other.photoFormat == photoFormat &&
      other.lens == lens &&
      other.live == live &&
      other.muteAudio == muteAudio &&
      other.profileId == profileId;

  @override
  int get hashCode => Object.hash(
        iso,
        exposureTimeNs,
        exposureBiasEv,
        exposureLocked,
        focusMode,
        manualFocusDiopters,
        focusLocked,
        whiteBalance,
        zoom,
        digitalZoom,
        flash,
        torch,
        timerSeconds,
        grid,
        aspect,
        cropNeeded,
        Object.hash(photoFormat, lens, live, muteAudio, profileId),
      );

  @override
  String toString() =>
      'ResolvedCaptureSettings(iso: $iso, shutter: $exposureTimeNs, bias: $exposureBiasEv, focus: $focusMode, '
      'wb: $whiteBalance, zoom: $zoom, flash: $flash, aspect: $aspect, format: $photoFormat, live: $live)';
}
