import 'dart:math' as math;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';

/// A fully capable camera (like a modern flagship back camera).
const CameraCapabilities fullCamera = CameraCapabilities(
  iso: IntRange(50, 3200),
  exposureTimeNs: IntRange(100000, 1000000000),
  exposureBias: ExposureBiasCaps(range: DoubleRange(-2, 2), step: 0.5),
  apertures: <double>[1.8],
  focus: FocusCaps(
    auto: true,
    continuous: true,
    tapToFocus: true,
    manual: ManualFocusCaps(minFocusDistanceDiopters: 10, calibration: FocusCalibration.approximate),
  ),
  whiteBalance: WhiteBalanceCaps(
    presets: <WbPreset>{WbPreset.auto, WbPreset.daylight, WbPreset.cloudy, WbPreset.shade, WbPreset.tungsten, WbPreset.fluorescent},
    kelvin: IntRange(2500, 8000),
  ),
  zoom: ZoomCaps(min: 0.5, max: 10, opticalSteps: <double>[0.5, 1, 2.5]),
  flash: <FlashMode>{FlashMode.off, FlashMode.auto, FlashMode.on},
  torch: true,
  photoFormats: <PhotoFormat>[PhotoFormat.heif, PhotoFormat.jpeg, PhotoFormat.dng],
  photoSizes: <PixelSize>[PixelSize(4000, 3000), PixelSize(4000, 2250), PixelSize(3000, 3000)],
  hdr: true,
  live: LiveCaps(supported: true, maxPreBufferMs: 1500, audio: true),
  hardwareLevel: 'FULL',
);

/// A typical budget phone: auto only, a fixed lens, JPEG, flash.
const CameraCapabilities basicCamera = CameraCapabilities(
  apertures: <double>[2.0],
  focus: FocusCaps(auto: true, tapToFocus: true),
  whiteBalance: WhiteBalanceCaps(presets: <WbPreset>{WbPreset.auto, WbPreset.daylight}),
  zoom: ZoomCaps(min: 1, max: 4, opticalSteps: <double>[1]),
  flash: <FlashMode>{FlashMode.off, FlashMode.on},
  photoFormats: <PhotoFormat>[PhotoFormat.jpeg],
  photoSizes: <PixelSize>[PixelSize(4000, 3000)],
);

/// Random but plausible capabilities, including absent controls, for property tests.
CameraCapabilities randomCapabilities(math.Random r) {
  bool coin([double p = 0.5]) => r.nextDouble() < p;
  IntRange intRange(int lo, int hi) {
    final a = lo + r.nextInt(hi - lo);
    return IntRange(a, a + 1 + r.nextInt(hi - a));
  }

  final steps = coin() ? <double>[] : <double>[for (var i = 0; i < 1 + r.nextInt(3); i++) 0.5 + r.nextInt(6) * 0.5];
  final zoomMin = coin() ? 1.0 : 0.5;
  return CameraCapabilities(
    iso: coin() ? intRange(25, 12800) : (coin(0.2) ? const IntRange(100, 100) : null),
    exposureTimeNs: coin() ? intRange(50000, 2000000000) : null,
    exposureBias: coin() ? ExposureBiasCaps(range: DoubleRange(-1 - r.nextInt(3).toDouble(), 1 + r.nextInt(3).toDouble()), step: coin() ? 1 / 3 : 0.5) : null,
    apertures: <double>[for (var i = 0; i < r.nextInt(3); i++) 1.4 + i],
    focus: FocusCaps(
      auto: coin(0.8),
      continuous: coin(0.6),
      tapToFocus: coin(0.7),
      manual: coin(0.4) ? ManualFocusCaps(minFocusDistanceDiopters: coin(0.1) ? 0 : 2 + r.nextInt(10).toDouble(), calibration: FocusCalibration.values[r.nextInt(3)]) : null,
    ),
    whiteBalance: WhiteBalanceCaps(
      presets: <WbPreset>{for (final p in WbPreset.values) if (coin(0.5)) p},
      kelvin: coin(0.4) ? intRange(2000, 10000) : null,
    ),
    zoom: ZoomCaps(min: zoomMin, max: zoomMin + r.nextInt(10).toDouble(), opticalSteps: steps),
    flash: <FlashMode>{for (final f in FlashMode.values) if (coin(0.5)) f},
    torch: coin(),
    photoFormats: <PhotoFormat>[for (final f in PhotoFormat.values) if (coin(0.6)) f],
    photoSizes: <PixelSize>[for (final s in const <PixelSize>[PixelSize(4000, 3000), PixelSize(4000, 2250), PixelSize(3000, 3000), PixelSize(4032, 3024), PixelSize(1234, 777)]) if (coin(0.5)) s],
    hdr: coin(),
    live: LiveCaps(supported: coin(0.5), maxPreBufferMs: 1500, audio: coin(0.6)),
  );
}

const List<double> _nasty = <double>[double.nan, double.infinity, double.negativeInfinity, -1e18, 1e18, 0, -0.0, 5e-324];

/// Random intent, including NaN/∞/huge values, to prove the resolver is total.
CaptureIntent randomIntent(math.Random r) {
  bool coin([double p = 0.5]) => r.nextDouble() < p;
  double? dbl(double lo, double hi) => coin(0.35) ? null : (coin(0.12) ? _nasty[r.nextInt(_nasty.length)] : lo + r.nextDouble() * (hi - lo));
  int? integer(int lo, int hi) => coin(0.35) ? null : (coin(0.1) ? (coin() ? -5 : 1 << 40) : lo + r.nextInt(hi - lo));
  return CaptureIntent(
    iso: integer(1, 20000),
    exposureTimeNs: integer(1000, 3000000000),
    exposureBiasEv: dbl(-6, 6),
    exposureLock: coin(0.6) ? null : coin(),
    focus: coin(0.3) ? null : FocusRequest.values[r.nextInt(3)],
    manualFocusDiopters: dbl(-2, 20),
    focusLock: coin(0.6) ? null : coin(),
    whiteBalance: coin(0.4) ? null : (coin() ? WbRequest.preset(WbPreset.values[r.nextInt(WbPreset.values.length)]) : WbRequest.kelvin(r.nextInt(14000) - 1000)),
    zoom: dbl(-1, 20),
    flash: coin(0.4) ? null : FlashMode.values[r.nextInt(3)],
    torch: coin(0.6) ? null : coin(),
    timerSeconds: coin(0.4) ? null : <int>[0, 3, 10, 5, -1, 99][r.nextInt(6)],
    grid: coin(0.6) ? null : coin(),
    aspect: coin(0.4) ? null : <String>['4:3', '3:2', '16:9', '1:1', '5:4', 'nope', ''][r.nextInt(7)],
    photoFormat: coin(0.4) ? null : PhotoFormat.values[r.nextInt(3)],
    lens: coin(0.7) ? null : LensKind.values[r.nextInt(LensKind.values.length)],
    live: coin(0.5) ? null : coin(),
    muteAudio: coin(0.6) ? null : coin(),
    profileId: coin(0.5) ? null : 'natural',
  );
}
