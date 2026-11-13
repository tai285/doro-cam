/// The original image profiles shipped with the app (PRF-004). Names describe a character, never a brand
/// or film stock (PRF-010). A profile's version increments on any output change; old versions stay in the
/// registry so existing Memories re-render identically.
library;

import 'package:doro_cam/profiles/image_profile.dart';

abstract final class BuiltInProfiles {
  static final ImageProfile natural = ImageProfile(
    id: 'natural',
    version: 1,
    name: 'Natural',
    description: 'True-to-life color with a touch of snap.',
    color: const ColorParams(contrast: 0.05, saturation: 0.02, vibrance: 0.05),
  );

  static final ImageProfile warmFilm = ImageProfile(
    id: 'warm-film',
    version: 1,
    name: 'Warm Film',
    description: 'Soft warm highlights, lifted blacks, gentle saturation and fine grain.',
    color: const ColorParams(
      contrast: 0.1,
      highlights: -0.2,
      shadows: 0.15,
      blackPoint: 0.04,
      whitePoint: 0.97,
      saturation: -0.05,
      vibrance: 0.1,
      temperatureShift: 0.08,
      tintShift: 0.02,
      hsl: <HueBand, HslShift>{HueBand.orange: HslShift(hue: 0.02, sat: 0.05, lum: 0.03)},
      splitShadows: SplitTone(hue: 200, amount: 0.05),
      splitHighlights: SplitTone(hue: 40, amount: 0.08),
    ),
    effects: const ProfileEffects(
      grain: GrainParams(amount: 0.25, size: 1.2, chroma: 0.1),
      vignette: VignetteParams(amount: 0.2, midpoint: 0.6, roundness: 0.2),
    ),
  );

  static final ImageProfile softFilm = ImageProfile(
    id: 'soft-film',
    version: 1,
    name: 'Soft Film',
    description: 'Low contrast, hazy highlights and muted color with a light grain.',
    color: const ColorParams(
      contrast: -0.12,
      highlights: -0.3,
      shadows: 0.25,
      blackPoint: 0.05,
      whitePoint: 0.95,
      toneCurve: <CurvePoint>[CurvePoint(0, 0), CurvePoint(0.25, 0.27), CurvePoint(0.5, 0.5), CurvePoint(0.75, 0.73), CurvePoint(1, 1)],
      saturation: -0.1,
      vibrance: 0.05,
      temperatureShift: 0.02,
      splitShadows: SplitTone(hue: 210, amount: 0.04),
      splitHighlights: SplitTone(hue: 50, amount: 0.04),
    ),
    effects: const ProfileEffects(
      grain: GrainParams(amount: 0.12, size: 1, chroma: 0.05),
      vignette: VignetteParams(amount: 0.1, midpoint: 0.65, roundness: 0.1),
    ),
  );

  static final ImageProfile instantWarm = ImageProfile(
    id: 'instant-warm',
    version: 1,
    name: 'Instant Warm',
    description: 'A sun-faded print: warm whites, cool shadows and a vignette.',
    color: const ColorParams(
      exposureEv: 0.1,
      contrast: 0.15,
      blackPoint: 0.06,
      whitePoint: 0.96,
      saturation: 0.1,
      vibrance: 0.1,
      temperatureShift: 0.15,
      tintShift: 0.03,
      hsl: <HueBand, HslShift>{HueBand.yellow: HslShift(sat: 0.1), HueBand.red: HslShift(hue: -0.03, sat: 0.05)},
      splitShadows: SplitTone(hue: 180, amount: 0.06),
      splitHighlights: SplitTone(hue: 50, amount: 0.1),
    ),
    effects: const ProfileEffects(
      grain: GrainParams(amount: 0.2, size: 1.1, chroma: 0.15),
      vignette: VignetteParams(amount: 0.35, midpoint: 0.5, roundness: 0),
    ),
  );

  static final ImageProfile monoClassic = ImageProfile(
    id: 'mono-classic',
    version: 1,
    name: 'Black & White',
    description: 'Rich, contrasty black and white with visible grain.',
    color: const ColorParams(
      contrast: 0.2,
      blackPoint: 0.03,
      whitePoint: 0.98,
      monochrome: MonochromeMix(red: 0.4, green: 0.5, blue: 0.1),
    ),
    effects: const ProfileEffects(
      grain: GrainParams(amount: 0.3, size: 1.4, chroma: 0),
      vignette: VignetteParams(amount: 0.25, midpoint: 0.55, roundness: 0.1),
    ),
  );

  /// Every shipped definition (all versions).
  static final List<ImageProfile> all = <ImageProfile>[natural, warmFilm, softFilm, instantWarm, monoClassic];
}

/// Looks profiles up by id and version.
class ProfileRegistry {
  ProfileRegistry(Iterable<ImageProfile> profiles) : _profiles = List<ImageProfile>.unmodifiable(profiles) {
    final seen = <ProfileRefKey>{};
    for (final profile in _profiles) {
      profile.validated();
      if (!seen.add(profile.key)) {
        throw ProfileException('Duplicate profile ${profile.key}.');
      }
    }
  }

  /// The shipped profiles.
  factory ProfileRegistry.builtIn() => ProfileRegistry(BuiltInProfiles.all);

  /// The profile used when a Memory references one that is missing or corrupt (the UI falls back, capture never blocks).
  static const String fallbackId = 'natural';

  final List<ImageProfile> _profiles;

  List<ImageProfile> get all => _profiles;

  /// The newest version of each profile id, in definition order: what the picker offers.
  List<ImageProfile> get latest {
    final byId = <String, ImageProfile>{};
    for (final profile in _profiles) {
      final current = byId[profile.id];
      if (current == null || profile.version > current.version) {
        byId[profile.id] = profile;
      }
    }
    return byId.values.toList(growable: false);
  }

  ImageProfile? find(String id, [int? version]) {
    ImageProfile? best;
    for (final profile in _profiles) {
      if (profile.id != id) {
        continue;
      }
      if (version != null) {
        if (profile.version == version) {
          return profile;
        }
      } else if (best == null || profile.version > best.version) {
        best = profile;
      }
    }
    return version == null ? best : null;
  }

  /// [find], or the fallback profile when [id] is unknown.
  ImageProfile resolve(String? id, [int? version]) =>
      (id == null ? null : find(id, version)) ?? find(fallbackId)!;
}
