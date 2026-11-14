import 'package:doro_cam/domain/camera/capabilities.dart';

/// Photographer-friendly value lists for the manual dials. They are only ever offered inside the range the
/// device reported (CAM-010, CAM-011): a stop outside it simply isn't in the list.

const List<int> _isoStops = <int>[
  25,
  50,
  64,
  80,
  100,
  125,
  160,
  200,
  250,
  320,
  400,
  500,
  640,
  800,
  1000,
  1250,
  1600,
  2000,
  2500,
  3200,
  4000,
  5000,
  6400,
  8000,
  10000,
  12800,
  25600,
  51200,
];

List<int> isoStops(IntRange range) {
  final stops = <int>{
    range.min,
    for (final stop in _isoStops)
      if (stop > range.min && stop < range.max) stop,
    range.max,
  }.toList()..sort();
  return stops;
}

/// Exposure times in nanoseconds: 1/8000 s … 30 s, within [range].
List<int> shutterStops(IntRange range) {
  const denominators = <int>[
    8000,
    4000,
    2000,
    1000,
    500,
    250,
    125,
    60,
    30,
    15,
    8,
    4,
    2,
  ];
  final stops = <int>{
    range.min,
    for (final d in denominators)
      if ((1e9 / d).round() > range.min && (1e9 / d).round() < range.max)
        (1e9 / d).round(),
    for (final s in <int>[1, 2, 4, 8, 15, 30])
      if (s * 1000000000 > range.min && s * 1000000000 < range.max)
        s * 1000000000,
    range.max,
  }.toList()..sort();
  return stops;
}

String formatShutterNs(int ns) {
  if (ns >= 1000000000) {
    final seconds = ns / 1e9;
    return '${seconds == seconds.roundToDouble() ? seconds.round() : seconds.toStringAsFixed(1)} s';
  }
  return '1/${(1e9 / ns).round()}';
}

String formatEv(double ev) {
  if (ev == 0) {
    return '0 EV';
  }
  final text = ev.abs() == ev.abs().roundToDouble()
      ? ev.abs().toStringAsFixed(0)
      : ev.abs().toStringAsFixed(1);
  return '${ev > 0 ? '+' : '−'}$text EV';
}

String formatZoom(double zoom) =>
    '${zoom == zoom.roundToDouble() ? zoom.round().toString() : zoom.toStringAsFixed(1)}×';

/// 100 cm = 1 m: a calibrated manual-focus distance in diopters → a readable distance (CAM-021).
String formatFocusDistance(double diopters) {
  if (diopters <= 0.05) {
    return '∞';
  }
  final metres = 1 / diopters;
  return metres < 1
      ? '${(metres * 100).round()} cm'
      : '${metres.toStringAsFixed(metres < 10 ? 1 : 0)} m';
}

String presetLabel(WbPreset preset) => switch (preset) {
  WbPreset.auto => 'Auto',
  WbPreset.daylight => 'Daylight',
  WbPreset.cloudy => 'Cloudy',
  WbPreset.shade => 'Shade',
  WbPreset.tungsten => 'Tungsten',
  WbPreset.fluorescent => 'Fluorescent',
};

String flashLabel(FlashMode mode) => switch (mode) {
  FlashMode.off => 'Off',
  FlashMode.auto => 'Auto',
  FlashMode.on => 'On',
};

String lensLabel(String kind) => switch (kind) {
  'ultraWide' => 'Ultra-wide',
  'wide' => 'Wide',
  'tele' => 'Telephoto',
  'front' => 'Front',
  _ => 'Camera',
};

/// Aspect ratios the app offers (CAM-044). Non-native ones become crop metadata on the rendition.
const List<String> aspectChoices = <String>['4:3', '3:2', '16:9', '1:1'];
