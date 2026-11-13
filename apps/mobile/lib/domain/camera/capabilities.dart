/// Camera capability model (docs/specs/camera.md, ADR-0002).
///
/// Capabilities are probed from the platform at runtime and describe one physical camera. They are
/// plain immutable values: pure Dart, no platform imports.
library;

/// An inclusive integer range.
class IntRange {
  const IntRange(this.min, this.max);

  final int min;
  final int max;

  /// A usable range has `min < max` (spec: manual ISO/shutter need valid ranges).
  bool get isValid => min < max;

  bool contains(int value) => value >= min && value <= max;

  int clamp(int value) => value < min ? min : (value > max ? max : value);

  @override
  bool operator ==(Object other) => other is IntRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'IntRange($min..$max)';
}

/// An inclusive floating-point range.
class DoubleRange {
  const DoubleRange(this.min, this.max);

  final double min;
  final double max;

  bool get isValid => min <= max;

  bool contains(double value) => value >= min && value <= max;

  double clamp(double value) => value < min ? min : (value > max ? max : value);

  @override
  bool operator ==(Object other) => other is DoubleRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'DoubleRange($min..$max)';
}

enum LensKind { ultraWide, wide, tele, front, other }

enum FlashMode { off, auto, on }

enum WbPreset { auto, daylight, cloudy, shade, tungsten, fluorescent }

enum PhotoFormat { heif, jpeg, dng }

enum FocusCalibration { uncalibrated, approximate, calibrated }

/// A width × height in pixels.
class PixelSize {
  const PixelSize(this.width, this.height);

  final int width;
  final int height;

  int get pixels => width * height;

  /// The ratio as "w:h" reduced to the common photographic forms (4:3, 3:2, 16:9, 1:1) when it matches
  /// within 1%; otherwise null.
  String? get aspectLabel {
    if (width <= 0 || height <= 0) {
      return null;
    }
    final long = width >= height ? width : height;
    final short = width >= height ? height : width;
    final ratio = long / short;
    for (final entry in knownAspects.entries) {
      if ((ratio - entry.value).abs() / entry.value < 0.01) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is PixelSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// The aspect ratios the app offers (CAM-044), as long-edge / short-edge.
const Map<String, double> knownAspects = <String, double>{
  '4:3': 4 / 3,
  '3:2': 3 / 2,
  '16:9': 16 / 9,
  '1:1': 1,
};

class ExposureBiasCaps {
  const ExposureBiasCaps({required this.range, required this.step});

  final DoubleRange range;
  final double step;

  @override
  bool operator ==(Object other) => other is ExposureBiasCaps && other.range == range && other.step == step;

  @override
  int get hashCode => Object.hash(range, step);
}

class ManualFocusCaps {
  const ManualFocusCaps({required this.minFocusDistanceDiopters, required this.calibration});

  /// Diopters of the closest focus distance (1 / metres). Larger means it can focus closer.
  final double minFocusDistanceDiopters;
  final FocusCalibration calibration;

  /// Distances may only be shown when the device reports calibrated or approximate focus (CAM-021).
  bool get canLabelDistance => calibration != FocusCalibration.uncalibrated;

  @override
  bool operator ==(Object other) =>
      other is ManualFocusCaps &&
      other.minFocusDistanceDiopters == minFocusDistanceDiopters &&
      other.calibration == calibration;

  @override
  int get hashCode => Object.hash(minFocusDistanceDiopters, calibration);
}

class FocusCaps {
  const FocusCaps({this.auto = false, this.continuous = false, this.tapToFocus = false, this.manual});

  final bool auto;
  final bool continuous;
  final bool tapToFocus;
  final ManualFocusCaps? manual;

  @override
  bool operator ==(Object other) =>
      other is FocusCaps &&
      other.auto == auto &&
      other.continuous == continuous &&
      other.tapToFocus == tapToFocus &&
      other.manual == manual;

  @override
  int get hashCode => Object.hash(auto, continuous, tapToFocus, manual);
}

class WhiteBalanceCaps {
  const WhiteBalanceCaps({this.presets = const <WbPreset>{}, this.kelvin});

  final Set<WbPreset> presets;

  /// Null means no Kelvin control.
  final IntRange? kelvin;

  @override
  bool operator ==(Object other) =>
      other is WhiteBalanceCaps && _setEquals(other.presets, presets) && other.kelvin == kelvin;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(presets), kelvin);
}

class ZoomCaps {
  const ZoomCaps({this.min = 1, this.max = 1, this.opticalSteps = const <double>[]});

  final double min;
  final double max;

  /// Zoom factors that are real optical lenses/steps (e.g. 0.5, 1, 2.5). Anything above the largest is digital.
  final List<double> opticalSteps;

  /// The largest zoom that is still optical. With no reported optical steps, only the minimum is optical.
  double get opticalMax => opticalSteps.isEmpty ? min : opticalSteps.reduce((a, b) => a > b ? a : b);

  bool get canZoom => max > min;

  @override
  bool operator ==(Object other) =>
      other is ZoomCaps && other.min == min && other.max == max && _listEquals(other.opticalSteps, opticalSteps);

  @override
  int get hashCode => Object.hash(min, max, Object.hashAll(opticalSteps));
}

class LiveCaps {
  const LiveCaps({this.supported = false, this.maxPreBufferMs = 0, this.audio = false});

  final bool supported;
  final int maxPreBufferMs;
  final bool audio;

  @override
  bool operator ==(Object other) =>
      other is LiveCaps && other.supported == supported && other.maxPreBufferMs == maxPreBufferMs && other.audio == audio;

  @override
  int get hashCode => Object.hash(supported, maxPreBufferMs, audio);
}

/// What one physical camera can do. Absent (null / empty) means "not supported": the UI hides or disables
/// the control and explains why. Nothing here is ever simulated (CAM-005).
class CameraCapabilities {
  const CameraCapabilities({
    this.iso,
    this.exposureTimeNs,
    this.exposureBias,
    this.apertures = const <double>[],
    this.focus = const FocusCaps(),
    this.whiteBalance = const WhiteBalanceCaps(),
    this.zoom = const ZoomCaps(),
    this.flash = const <FlashMode>{},
    this.torch = false,
    this.photoFormats = const <PhotoFormat>[],
    this.photoSizes = const <PixelSize>[],
    this.hdr = false,
    this.live = const LiveCaps(),
    this.hardwareLevel = '',
  });

  /// No capabilities at all: the resolver must still produce valid settings from this.
  static const CameraCapabilities none = CameraCapabilities();

  /// Null ⇒ no manual ISO.
  final IntRange? iso;

  /// Exposure time in nanoseconds. Null ⇒ no manual shutter.
  final IntRange? exposureTimeNs;
  final ExposureBiasCaps? exposureBias;

  /// Usually one value, so aperture is display-only (CAM-013).
  final List<double> apertures;
  final FocusCaps focus;
  final WhiteBalanceCaps whiteBalance;
  final ZoomCaps zoom;
  final Set<FlashMode> flash;
  final bool torch;
  final List<PhotoFormat> photoFormats;
  final List<PixelSize> photoSizes;
  final bool hdr;
  final LiveCaps live;
  final String hardwareLevel;

  bool get hasManualIso => iso != null && iso!.isValid;
  bool get hasManualShutter => exposureTimeNs != null && exposureTimeNs!.isValid;
  bool get apertureControllable => apertures.length > 1;

  /// Aspect ratios the sensor/format can deliver natively, from [photoSizes].
  Set<String> get nativeAspects => <String>{
        for (final size in photoSizes)
          if (size.aspectLabel != null) size.aspectLabel!,
      };

  CameraCapabilities copyWith({
    IntRange? iso,
    IntRange? exposureTimeNs,
    ExposureBiasCaps? exposureBias,
    List<double>? apertures,
    FocusCaps? focus,
    WhiteBalanceCaps? whiteBalance,
    ZoomCaps? zoom,
    Set<FlashMode>? flash,
    bool? torch,
    List<PhotoFormat>? photoFormats,
    List<PixelSize>? photoSizes,
    bool? hdr,
    LiveCaps? live,
    String? hardwareLevel,
    bool clearIso = false,
    bool clearExposureTime = false,
    bool clearExposureBias = false,
  }) {
    return CameraCapabilities(
      iso: clearIso ? null : (iso ?? this.iso),
      exposureTimeNs: clearExposureTime ? null : (exposureTimeNs ?? this.exposureTimeNs),
      exposureBias: clearExposureBias ? null : (exposureBias ?? this.exposureBias),
      apertures: apertures ?? this.apertures,
      focus: focus ?? this.focus,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      zoom: zoom ?? this.zoom,
      flash: flash ?? this.flash,
      torch: torch ?? this.torch,
      photoFormats: photoFormats ?? this.photoFormats,
      photoSizes: photoSizes ?? this.photoSizes,
      hdr: hdr ?? this.hdr,
      live: live ?? this.live,
      hardwareLevel: hardwareLevel ?? this.hardwareLevel,
    );
  }
}

bool _setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
