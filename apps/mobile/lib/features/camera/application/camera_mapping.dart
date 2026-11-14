// ignore_for_file: use_null_aware_elements
import 'dart:typed_data';

import 'package:doro_cam/domain/camera/capabilities.dart' as dom;
import 'package:doro_cam/domain/camera/capture_intent.dart' as dom;
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:doro_cam/profiles/lut.dart';
import 'package:doro_camera/doro_camera.dart' as cam;

/// The plugin reports hardware facts in its own types; the app's domain layer reasons in its own
/// (ADR-0001: intent resolution lives in the app). These functions are the only place the two meet.

dom.CameraCapabilities toDomainCapabilities(cam.CameraCapabilities c) {
  final manual = c.focus.manual;
  return dom.CameraCapabilities(
    iso: c.iso == null ? null : dom.IntRange(c.iso!.min, c.iso!.max),
    exposureTimeNs: c.exposureTimeNs == null
        ? null
        : dom.IntRange(c.exposureTimeNs!.min, c.exposureTimeNs!.max),
    exposureBias: c.exposureBias == null
        ? null
        : dom.ExposureBiasCaps(
            range: dom.DoubleRange(
              c.exposureBias!.range.min,
              c.exposureBias!.range.max,
            ),
            step: c.exposureBias!.step,
          ),
    apertures: c.apertures,
    focus: dom.FocusCaps(
      auto: c.focus.auto,
      continuous: c.focus.continuous,
      tapToFocus: c.focus.tapToFocus,
      manual: manual == null
          ? null
          : dom.ManualFocusCaps(
              minFocusDistanceDiopters: manual.minFocusDistanceDiopters,
              calibration: dom.FocusCalibration.values.byName(
                manual.calibration.name,
              ),
            ),
    ),
    whiteBalance: dom.WhiteBalanceCaps(
      presets: <dom.WbPreset>{
        for (final p in c.whiteBalance.presets)
          dom.WbPreset.values.byName(p.name),
      },
      kelvin: c.whiteBalance.kelvin == null
          ? null
          : dom.IntRange(
              c.whiteBalance.kelvin!.min,
              c.whiteBalance.kelvin!.max,
            ),
    ),
    zoom: dom.ZoomCaps(
      min: c.zoom.min,
      max: c.zoom.max,
      opticalSteps: c.zoom.opticalSteps,
    ),
    flash: <dom.FlashMode>{
      for (final f in c.flash) dom.FlashMode.values.byName(f.name),
    },
    torch: c.torch,
    photoFormats: <dom.PhotoFormat>[
      for (final f in c.photoFormats) dom.PhotoFormat.values.byName(f.name),
    ],
    photoSizes: <dom.PixelSize>[
      for (final s in c.photoSizes) dom.PixelSize(s.width, s.height),
    ],
    hdr: c.hdr,
    live: dom.LiveCaps(
      supported: c.live.supported,
      maxPreBufferMs: c.live.maxPreBufferMs,
      audio: c.live.audio,
    ),
    hardwareLevel: c.hardwareLevel,
  );
}

cam.ResolvedCaptureSettings toPluginSettings(dom.ResolvedCaptureSettings s) {
  final wb = s.whiteBalance;
  return cam.ResolvedCaptureSettings(
    iso: s.iso,
    exposureTimeNs: s.exposureTimeNs,
    exposureBiasEv: s.exposureBiasEv,
    aeLock: s.exposureLocked,
    focusMode: switch (s.focusMode) {
      dom.FocusMode.continuous => cam.FocusMode.continuous,
      dom.FocusMode.manual => cam.FocusMode.manual,
      dom.FocusMode.auto || dom.FocusMode.fixed => cam.FocusMode.auto,
    },
    focusDistanceDiopters: s.manualFocusDiopters,
    afLock: s.focusLocked,
    whiteBalancePreset: wb.kelvin != null || wb.preset == dom.WbPreset.auto
        ? null
        : cam.WbPreset.values.byName(wb.preset.name),
    kelvin: wb.kelvin,
    zoomRatio: s.zoom,
    flash: cam.FlashMode.values.byName(s.flash.name),
    torch: s.torch,
  );
}

/// Packed RGB bytes of the profile's cube LUT, R fastest, 3 bytes per entry (the plugin's `RenderSpec.lut`).
Uint8List packLut(Lut3d lut) {
  final out = Uint8List(lut.data.length);
  for (var i = 0; i < out.length; i++) {
    out[i] = (lut.data[i].clamp(0.0, 1.0) * 255).round();
  }
  return out;
}

cam.RenderSpec renderSpecFor(
  ImageProfile profile,
  Lut3d lut, {
  String? aspect,
  bool crop = false,
}) => cam.RenderSpec(
  lut: packLut(lut),
  lutSize: lut.size,
  grain: profile.effects.grain.amount,
  vignette: profile.effects.vignette.amount,
  aspectRatio: crop ? aspect : null,
  profileId: profile.id,
);

/// The settings the device REPORTED, as the `capture` JSON stored with a Memory (CAM-050, memory-domain.md).
/// Requested values are kept only where they differ, together with the adjustments the UI showed.
Map<String, Object?> buildCaptureMetadata({
  required cam.CameraDescriptor camera,
  required cam.CaptureResult result,
  required dom.ResolvedCaptureSettings requested,
  required List<dom.Adjustment> adjustments,
  required String platform,
  String? osVersion,
  required String appVersion,
}) {
  final applied = result.applied;
  final zoom = applied.zoomRatio;
  return <String, Object?>{
    'platform': platform,
    if (osVersion != null) 'osVersion': osVersion,
    'appVersion': appVersion,
    'cameraId': camera.id,
    'cameraSource': result.source.name,
    'lensKind': camera.lensKind.name,
    if (applied.focalLengthMm != null)
      'focalLengthMm': applied.focalLengthMm
    else if (camera.focalLengthMm != null)
      'focalLengthMm': camera.focalLengthMm,
    if (camera.focalLength35mmEq != null)
      'focalLength35mmEq': camera.focalLength35mmEq! * (zoom > 0 ? zoom : 1),
    if (applied.aperture != null) 'aperture': applied.aperture,
    if (applied.iso != null) 'isoApplied': applied.iso,
    if (applied.exposureTimeNs != null)
      'exposureTimeNsApplied': applied.exposureTimeNs,
    if (applied.exposureBiasEv != null)
      'exposureBiasEv': applied.exposureBiasEv,
    'whiteBalance': <String, Object?>{
      if (applied.whiteBalanceMode != null) 'mode': applied.whiteBalanceMode,
      if (applied.estimatedKelvin != null) 'kelvin': applied.estimatedKelvin,
    },
    'focus': <String, Object?>{
      if (applied.focusMode != null) 'mode': applied.focusMode!.name,
      if (applied.focusDistanceDiopters != null)
        'distanceDiopters': applied.focusDistanceDiopters,
    },
    if (applied.flash != null) 'flash': applied.flash!.name,
    if (applied.flashFired != null) 'flashFired': applied.flashFired,
    'zoomFactor': zoom,
    'digitalZoom': requested.digitalZoom,
    'format': result.originalMime,
    'widthPx': result.width,
    'heightPx': result.height,
    'orientationDegrees': result.orientationDegrees,
    'mirrored': result.mirrored,
    'live': result.liveIncluded,
    'requested': <String, Object?>{
      if (requested.iso != null) 'iso': requested.iso,
      if (requested.exposureTimeNs != null)
        'exposureTimeNs': requested.exposureTimeNs,
      if (requested.exposureBiasEv != null)
        'exposureBiasEv': requested.exposureBiasEv,
      'zoom': requested.zoom,
      'aspect': requested.aspect,
    },
    'adjustments': <Map<String, Object?>>[
      for (final a in adjustments)
        <String, Object?>{
          'field': a.field.name,
          'requested': a.requested?.toString(),
          'applied': a.applied?.toString(),
          'reason': a.reason.name,
        },
    ],
    if (applied.mismatches.isNotEmpty) 'mismatches': applied.mismatches,
  };
}
