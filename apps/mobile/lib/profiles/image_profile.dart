/// Image profile definitions (docs/specs/image-profile.md, ADR-0004, PRF-001..PRF-004, PRF-010).
///
/// A profile is *data*: color parameters that compile to a 3D LUT, plus spatial effect parameters.
/// Profiles never change capture settings.
library;

/// Thrown when a profile definition is invalid.
class ProfileException implements Exception {
  ProfileException(this.message);

  final String message;

  @override
  String toString() => 'ProfileException: $message';
}

/// The hue bands of the per-hue HSL response, with their center angle in degrees.
enum HueBand {
  red(0),
  orange(30),
  yellow(60),
  green(120),
  aqua(180),
  blue(240),
  purple(280),
  magenta(320);

  const HueBand(this.centerDegrees);

  final double centerDegrees;
}

/// Adjustment of one hue band. Each value is in [-1, 1].
class HslShift {
  const HslShift({this.hue = 0, this.sat = 0, this.lum = 0});

  final double hue;
  final double sat;
  final double lum;

  bool get isIdentity => hue == 0 && sat == 0 && lum == 0;

  Map<String, Object?> toJson() => <String, Object?>{'hue': hue, 'sat': sat, 'lum': lum};

  factory HslShift.fromJson(Map<String, Object?> json) => HslShift(
        hue: (json['hue'] as num?)?.toDouble() ?? 0,
        sat: (json['sat'] as num?)?.toDouble() ?? 0,
        lum: (json['lum'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) => other is HslShift && other.hue == hue && other.sat == sat && other.lum == lum;

  @override
  int get hashCode => Object.hash(hue, sat, lum);
}

/// A tint pushed into shadows or highlights: [hue] in degrees (0–360), [amount] in [0, 1].
class SplitTone {
  const SplitTone({this.hue = 0, this.amount = 0});

  final double hue;
  final double amount;

  Map<String, Object?> toJson() => <String, Object?>{'hue': hue, 'amount': amount};

  factory SplitTone.fromJson(Map<String, Object?> json) =>
      SplitTone(hue: (json['hue'] as num?)?.toDouble() ?? 0, amount: (json['amount'] as num?)?.toDouble() ?? 0);

  @override
  bool operator ==(Object other) => other is SplitTone && other.hue == hue && other.amount == amount;

  @override
  int get hashCode => Object.hash(hue, amount);
}

/// Black-and-white conversion: a weighted channel mix (weights sum to about 1).
class MonochromeMix {
  const MonochromeMix({this.red = 0.30, this.green = 0.59, this.blue = 0.11});

  final double red;
  final double green;
  final double blue;

  Map<String, Object?> toJson() => <String, Object?>{'red': red, 'green': green, 'blue': blue};

  factory MonochromeMix.fromJson(Map<String, Object?> json) => MonochromeMix(
        red: (json['red'] as num?)?.toDouble() ?? 0.30,
        green: (json['green'] as num?)?.toDouble() ?? 0.59,
        blue: (json['blue'] as num?)?.toDouble() ?? 0.11,
      );

  @override
  bool operator ==(Object other) => other is MonochromeMix && other.red == red && other.green == green && other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);
}

/// A tone-curve control point; both axes in [0, 1].
class CurvePoint {
  const CurvePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is CurvePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Color parameters. Order of operations inside compilation is normative (image-profile.md):
/// exposure → white/black point → temperature/tint → tone curve and contrast → highlights/shadows →
/// HSL → saturation/vibrance → split tone → monochrome mix.
class ColorParams {
  const ColorParams({
    this.exposureEv = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.blackPoint = 0,
    this.whitePoint = 1,
    this.toneCurve = const <CurvePoint>[],
    this.saturation = 0,
    this.vibrance = 0,
    this.temperatureShift = 0,
    this.tintShift = 0,
    this.hsl = const <HueBand, HslShift>{},
    this.splitShadows = const SplitTone(),
    this.splitHighlights = const SplitTone(),
    this.monochrome,
  });

  /// Stops of exposure, in [-2, 2].
  final double exposureEv;
  final double contrast;
  final double highlights;
  final double shadows;

  /// Output level of black, in [0, 0.25]; output level of white, in [0.75, 1].
  final double blackPoint;
  final double whitePoint;

  /// Optional curve control points (x ascending, strictly increasing). Empty means the identity curve.
  final List<CurvePoint> toneCurve;
  final double saturation;
  final double vibrance;

  /// Positive is warmer (more red, less blue); [-1, 1].
  final double temperatureShift;

  /// Positive is more magenta; [-1, 1].
  final double tintShift;
  final Map<HueBand, HslShift> hsl;
  final SplitTone splitShadows;
  final SplitTone splitHighlights;
  final MonochromeMix? monochrome;

  bool get isMonochrome => monochrome != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'exposureEv': exposureEv,
        'contrast': contrast,
        'highlights': highlights,
        'shadows': shadows,
        'blackPoint': blackPoint,
        'whitePoint': whitePoint,
        'toneCurve': <List<double>>[
          for (final p in toneCurve) <double>[p.x, p.y],
        ],
        'saturation': saturation,
        'vibrance': vibrance,
        'temperatureShift': temperatureShift,
        'tintShift': tintShift,
        'hsl': <String, Object?>{
          for (final band in HueBand.values)
            if (hsl[band] != null && !hsl[band]!.isIdentity) band.name: hsl[band]!.toJson(),
        },
        'splitTone': <String, Object?>{
          'shadows': splitShadows.toJson(),
          'highlights': splitHighlights.toJson(),
        },
        'monochrome': monochrome?.toJson(),
      };

  factory ColorParams.fromJson(Map<String, Object?> json) {
    double n(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    final curve = json['toneCurve'];
    final hslJson = json['hsl'];
    final split = json['splitTone'];
    final mono = json['monochrome'];
    return ColorParams(
      exposureEv: n('exposureEv', 0),
      contrast: n('contrast', 0),
      highlights: n('highlights', 0),
      shadows: n('shadows', 0),
      blackPoint: n('blackPoint', 0),
      whitePoint: n('whitePoint', 1),
      toneCurve: curve is List<Object?>
          ? <CurvePoint>[
              for (final p in curve)
                if (p is List<Object?> && p.length == 2) CurvePoint((p[0]! as num).toDouble(), (p[1]! as num).toDouble()),
            ]
          : const <CurvePoint>[],
      saturation: n('saturation', 0),
      vibrance: n('vibrance', 0),
      temperatureShift: n('temperatureShift', 0),
      tintShift: n('tintShift', 0),
      hsl: hslJson is Map<String, Object?>
          ? <HueBand, HslShift>{
              for (final band in HueBand.values)
                if (hslJson[band.name] is Map<String, Object?>) band: HslShift.fromJson(hslJson[band.name]! as Map<String, Object?>),
            }
          : const <HueBand, HslShift>{},
      splitShadows: split is Map<String, Object?> && split['shadows'] is Map<String, Object?>
          ? SplitTone.fromJson(split['shadows']! as Map<String, Object?>)
          : const SplitTone(),
      splitHighlights: split is Map<String, Object?> && split['highlights'] is Map<String, Object?>
          ? SplitTone.fromJson(split['highlights']! as Map<String, Object?>)
          : const SplitTone(),
      monochrome: mono is Map<String, Object?> ? MonochromeMix.fromJson(mono) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ColorParams && _jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(<Object?>[exposureEv, contrast, highlights, shadows, blackPoint, whitePoint, saturation, vibrance, temperatureShift, tintShift]);
}

class GrainParams {
  const GrainParams({this.amount = 0, this.size = 1, this.chroma = 0});

  /// Strength in [0, 1].
  final double amount;

  /// Grain size relative to a 1080 px short edge, in [0.5, 4]: the same look at preview and full resolution.
  final double size;

  /// How much of the grain is colored rather than monochrome, in [0, 1].
  final double chroma;

  bool get isActive => amount > 0;

  Map<String, Object?> toJson() => <String, Object?>{'amount': amount, 'size': size, 'chroma': chroma};

  factory GrainParams.fromJson(Map<String, Object?> json) => GrainParams(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        size: (json['size'] as num?)?.toDouble() ?? 1,
        chroma: (json['chroma'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) => other is GrainParams && other.amount == amount && other.size == size && other.chroma == chroma;

  @override
  int get hashCode => Object.hash(amount, size, chroma);
}

class VignetteParams {
  const VignetteParams({this.amount = 0, this.midpoint = 0.6, this.roundness = 0});

  /// Darkening at the corners in [0, 1].
  final double amount;

  /// Normalized radius where darkening starts, in [0, 1].
  final double midpoint;

  /// 0 follows the frame (elliptical), 1 is a circle; [-1, 1] extends to extra-wide ovals.
  final double roundness;

  bool get isActive => amount > 0;

  Map<String, Object?> toJson() => <String, Object?>{'amount': amount, 'midpoint': midpoint, 'roundness': roundness};

  factory VignetteParams.fromJson(Map<String, Object?> json) => VignetteParams(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        midpoint: (json['midpoint'] as num?)?.toDouble() ?? 0.6,
        roundness: (json['roundness'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is VignetteParams && other.amount == amount && other.midpoint == midpoint && other.roundness == roundness;

  @override
  int get hashCode => Object.hash(amount, midpoint, roundness);
}

class ProfileEffects {
  const ProfileEffects({this.grain = const GrainParams(), this.vignette = const VignetteParams()});

  final GrainParams grain;
  final VignetteParams vignette;

  Map<String, Object?> toJson() => <String, Object?>{'grain': grain.toJson(), 'vignette': vignette.toJson()};

  factory ProfileEffects.fromJson(Map<String, Object?> json) => ProfileEffects(
        grain: json['grain'] is Map<String, Object?> ? GrainParams.fromJson(json['grain']! as Map<String, Object?>) : const GrainParams(),
        vignette:
            json['vignette'] is Map<String, Object?> ? VignetteParams.fromJson(json['vignette']! as Map<String, Object?>) : const VignetteParams(),
      );

  @override
  bool operator ==(Object other) => other is ProfileEffects && other.grain == grain && other.vignette == vignette;

  @override
  int get hashCode => Object.hash(grain, vignette);
}

/// Words that would reference proprietary film stocks, brands or trade dress (PRF-010). Profile names and
/// descriptions must not contain them.
const List<String> forbiddenProfileWords = <String>[
  'kodak', 'kodachrome', 'ektachrome', 'portra', 'ektar', 'tri-x', 'trix', 'fuji', 'fujifilm', 'velvia', 'provia', 'astia',
  'superia', 'ilford', 'agfa', 'polaroid', 'lomo', 'leica', 'hasselblad', 'cinestill', 'instax', 'vsco', 'canon', 'nikon',
];

class ImageProfile {
  ImageProfile({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    this.color = const ColorParams(),
    this.effects = const ProfileEffects(),
  });

  final String id;

  /// Increments on *any* change to the profile's output, so old Memories re-render identically.
  final int version;
  final String name;
  final String description;
  final ColorParams color;
  final ProfileEffects effects;

  /// Problems with this definition (empty when valid): parameter ranges, curve monotonicity, forbidden names.
  List<String> validate() {
    final problems = <String>[];
    if (!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(id)) {
      problems.add('id must be lowercase letters, digits and hyphens.');
    }
    if (version < 1) {
      problems.add('version must be at least 1.');
    }
    final text = '${name.toLowerCase()} ${description.toLowerCase()} ${id.toLowerCase()}';
    for (final word in forbiddenProfileWords) {
      if (RegExp('(^|[^a-z])${RegExp.escape(word)}([^a-z]|\$)').hasMatch(text)) {
        problems.add('must not reference the proprietary name "$word".');
      }
    }
    void range(String label, double value, double min, double max) {
      if (!value.isFinite || value < min || value > max) {
        problems.add('$label must be between $min and $max.');
      }
    }

    final c = color;
    range('exposureEv', c.exposureEv, -2, 2);
    range('contrast', c.contrast, -1, 1);
    range('highlights', c.highlights, -1, 1);
    range('shadows', c.shadows, -1, 1);
    range('blackPoint', c.blackPoint, 0, 0.25);
    range('whitePoint', c.whitePoint, 0.75, 1);
    range('saturation', c.saturation, -1, 1);
    range('vibrance', c.vibrance, -1, 1);
    range('temperatureShift', c.temperatureShift, -1, 1);
    range('tintShift', c.tintShift, -1, 1);
    for (final entry in c.hsl.entries) {
      range('hsl.${entry.key.name}.hue', entry.value.hue, -1, 1);
      range('hsl.${entry.key.name}.sat', entry.value.sat, -1, 1);
      range('hsl.${entry.key.name}.lum', entry.value.lum, -1, 1);
    }
    for (final (label, tone) in <(String, SplitTone)>[('shadows', c.splitShadows), ('highlights', c.splitHighlights)]) {
      range('splitTone.$label.hue', tone.hue, 0, 360);
      range('splitTone.$label.amount', tone.amount, 0, 1);
    }
    if (c.monochrome != null) {
      for (final (label, v) in <(String, double)>[('red', c.monochrome!.red), ('green', c.monochrome!.green), ('blue', c.monochrome!.blue)]) {
        range('monochrome.$label', v, -1, 2);
      }
    }
    if (c.toneCurve.isNotEmpty) {
      if (c.toneCurve.length < 2) {
        problems.add('toneCurve needs at least 2 points.');
      }
      for (var i = 0; i < c.toneCurve.length; i++) {
        final p = c.toneCurve[i];
        if (!p.x.isFinite || !p.y.isFinite || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) {
          problems.add('toneCurve points must lie in [0, 1].');
        }
        if (i > 0 && p.x <= c.toneCurve[i - 1].x) {
          problems.add('toneCurve x values must be strictly increasing.');
        }
        if (i > 0 && p.y < c.toneCurve[i - 1].y) {
          problems.add('toneCurve must not decrease.');
        }
      }
    }
    final g = effects.grain;
    range('grain.amount', g.amount, 0, 1);
    range('grain.size', g.size, 0.5, 4);
    range('grain.chroma', g.chroma, 0, 1);
    final v = effects.vignette;
    range('vignette.amount', v.amount, 0, 1);
    range('vignette.midpoint', v.midpoint, 0, 1);
    range('vignette.roundness', v.roundness, -1, 1);
    return problems;
  }

  /// Throws [ProfileException] if invalid; returns this otherwise.
  ImageProfile validated() {
    final problems = validate();
    if (problems.isNotEmpty) {
      throw ProfileException('Profile "$id": ${problems.join(' ')}');
    }
    return this;
  }

  ProfileRefKey get key => ProfileRefKey(id, version);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'version': version,
        'name': name,
        'description': description,
        'color': color.toJson(),
        'effects': effects.toJson(),
      };

  factory ImageProfile.fromJson(Map<String, Object?> json) {
    if (json['id'] is! String || json['version'] is! int || json['name'] is! String) {
      throw ProfileException('Profile JSON needs id, version and name.');
    }
    return ImageProfile(
      id: json['id']! as String,
      version: json['version']! as int,
      name: json['name']! as String,
      description: (json['description'] as String?) ?? '',
      color: json['color'] is Map<String, Object?> ? ColorParams.fromJson(json['color']! as Map<String, Object?>) : const ColorParams(),
      effects: json['effects'] is Map<String, Object?> ? ProfileEffects.fromJson(json['effects']! as Map<String, Object?>) : const ProfileEffects(),
    ).validated();
  }
}

/// `id@version`, the identity of a profile definition.
class ProfileRefKey {
  const ProfileRefKey(this.id, this.version);

  final String id;
  final int version;

  @override
  bool operator ==(Object other) => other is ProfileRefKey && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() => '$id@v$version';
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
