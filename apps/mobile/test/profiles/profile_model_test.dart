import 'dart:convert';

import 'package:doro_cam/profiles/builtin_profiles.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:flutter_test/flutter_test.dart';

ImageProfile profile({
  String id = 'test-look',
  int version = 1,
  String name = 'Test Look',
  String description = 'A test.',
  ColorParams color = const ColorParams(),
  ProfileEffects effects = const ProfileEffects(),
}) =>
    ImageProfile(id: id, version: version, name: name, description: description, color: color, effects: effects);

void main() {
  group('built-in profiles', () {
    test('[PRF-004] at least five originals ship: natural, warm-film, soft-film, instant-warm, mono-classic', () {
      expect(BuiltInProfiles.all.length, greaterThanOrEqualTo(5));
      expect(BuiltInProfiles.all.map((p) => p.id), containsAll(<String>['natural', 'warm-film', 'soft-film', 'instant-warm', 'mono-classic']));
    });

    test('[PRF-004] every shipped definition is valid and has a name and description', () {
      for (final p in BuiltInProfiles.all) {
        expect(p.validate(), isEmpty, reason: p.id);
        expect(p.name, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.version, greaterThanOrEqualTo(1));
      }
    });

    test('[PRF-010] no name, description or id references a proprietary film stock or brand', () {
      for (final p in BuiltInProfiles.all) {
        final text = '${p.id} ${p.name} ${p.description}'.toLowerCase();
        for (final word in forbiddenProfileWords) {
          expect(text.contains(word), isFalse, reason: '${p.id} mentions $word');
        }
      }
    });

    test('[PRF-004] the profiles are visibly distinct looks (their color parameters all differ)', () {
      final encoded = BuiltInProfiles.all.map((p) => jsonEncode(p.color.toJson())).toSet();
      expect(encoded.length, BuiltInProfiles.all.length);
      expect(BuiltInProfiles.monoClassic.color.isMonochrome, isTrue);
      expect(BuiltInProfiles.natural.color.isMonochrome, isFalse);
    });

    test('[PRF-006] the film looks carry grain and vignette; natural carries none', () {
      expect(BuiltInProfiles.natural.effects.grain.isActive, isFalse);
      expect(BuiltInProfiles.natural.effects.vignette.isActive, isFalse);
      for (final p in <ImageProfile>[BuiltInProfiles.warmFilm, BuiltInProfiles.softFilm, BuiltInProfiles.instantWarm, BuiltInProfiles.monoClassic]) {
        expect(p.effects.grain.isActive, isTrue, reason: p.id);
        expect(p.effects.vignette.isActive, isTrue, reason: p.id);
      }
    });
  });

  group('validation', () {
    test('rejects bad ids and versions', () {
      expect(profile(id: 'Bad Id').validate(), isNotEmpty);
      expect(profile(id: '1abc').validate(), isNotEmpty);
      expect(profile(version: 0).validate(), contains('version must be at least 1.'));
      expect(profile(id: 'ok-1').validate(), isEmpty);
    });

    test('[PRF-010] rejects proprietary names in the name, description or id', () {
      expect(profile(name: 'Kodak Look').validate(), isNotEmpty);
      expect(profile(description: 'Inspired by Polaroid prints.').validate(), isNotEmpty);
      expect(profile(id: 'portra-like').validate(), isNotEmpty);
      expect(profile(name: 'Matrix Warmth', description: 'Not the film.').validate(), isEmpty); // "trix" inside a longer word is fine
      expect(profile(name: 'Tri-X style').validate(), isNotEmpty);
    });

    test('rejects out-of-range color parameters, naming the field', () {
      final cases = <String, ColorParams>{
        'exposureEv': const ColorParams(exposureEv: 3),
        'contrast': const ColorParams(contrast: -1.5),
        'highlights': const ColorParams(highlights: 2),
        'shadows': const ColorParams(shadows: -2),
        'blackPoint': const ColorParams(blackPoint: 0.5),
        'whitePoint': const ColorParams(whitePoint: 0.5),
        'saturation': const ColorParams(saturation: 2),
        'vibrance': const ColorParams(vibrance: -2),
        'temperatureShift': const ColorParams(temperatureShift: 1.5),
        'tintShift': const ColorParams(tintShift: -1.5),
        'hsl.red.hue': const ColorParams(hsl: <HueBand, HslShift>{HueBand.red: HslShift(hue: 2)}),
        'hsl.blue.sat': const ColorParams(hsl: <HueBand, HslShift>{HueBand.blue: HslShift(sat: -2)}),
        'hsl.green.lum': const ColorParams(hsl: <HueBand, HslShift>{HueBand.green: HslShift(lum: 5)}),
        'splitTone.shadows.hue': const ColorParams(splitShadows: SplitTone(hue: 400)),
        'splitTone.highlights.amount': const ColorParams(splitHighlights: SplitTone(amount: 2)),
        'monochrome.red': const ColorParams(monochrome: MonochromeMix(red: 5)),
        'monochrome.green': const ColorParams(monochrome: MonochromeMix(green: -5)),
        'monochrome.blue': const ColorParams(monochrome: MonochromeMix(blue: 9)),
      };
      cases.forEach((field, color) {
        final problems = profile(color: color).validate();
        expect(problems.any((p) => p.contains(field)), isTrue, reason: '$field in $problems');
      });
      expect(profile(color: const ColorParams(exposureEv: double.nan)).validate(), isNotEmpty);
    });

    test('rejects out-of-range effects', () {
      final cases = <String, ProfileEffects>{
        'grain.amount': const ProfileEffects(grain: GrainParams(amount: 2)),
        'grain.size': const ProfileEffects(grain: GrainParams(size: 9)),
        'grain.chroma': const ProfileEffects(grain: GrainParams(chroma: -1)),
        'vignette.amount': const ProfileEffects(vignette: VignetteParams(amount: 2)),
        'vignette.midpoint': const ProfileEffects(vignette: VignetteParams(midpoint: 2)),
        'vignette.roundness': const ProfileEffects(vignette: VignetteParams(roundness: 3)),
      };
      cases.forEach((field, effects) {
        expect(profile(effects: effects).validate().any((p) => p.contains(field)), isTrue, reason: field);
      });
    });

    test('tone curves must be at least 2 points, in range, increasing in x and non-decreasing in y', () {
      expect(profile(color: const ColorParams(toneCurve: <CurvePoint>[CurvePoint(0, 0)])).validate(), contains('toneCurve needs at least 2 points.'));
      expect(profile(color: const ColorParams(toneCurve: <CurvePoint>[CurvePoint(0, 0), CurvePoint(1, 2)])).validate(), isNotEmpty);
      expect(profile(color: const ColorParams(toneCurve: <CurvePoint>[CurvePoint(0, 0), CurvePoint(0.5, 0.5), CurvePoint(0.5, 0.6)])).validate(), contains('toneCurve x values must be strictly increasing.'));
      expect(profile(color: const ColorParams(toneCurve: <CurvePoint>[CurvePoint(0, 0.5), CurvePoint(1, 0.2)])).validate(), contains('toneCurve must not decrease.'));
      expect(profile(color: const ColorParams(toneCurve: <CurvePoint>[CurvePoint(0, 0), CurvePoint(1, 1)])).validate(), isEmpty);
    });

    test('validated() throws ProfileException with the profile id, and returns itself when valid', () {
      expect(() => profile(id: 'bad id').validated(), throwsA(isA<ProfileException>().having((e) => e.message, 'message', contains('bad id'))));
      final ok = profile();
      expect(ok.validated(), same(ok));
      expect(ProfileException('x').toString(), contains('x'));
    });
  });

  group('JSON', () {
    test('every built-in profile round-trips through JSON unchanged', () {
      for (final p in BuiltInProfiles.all) {
        final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>;
        final copy = ImageProfile.fromJson(json);
        expect(jsonEncode(copy.toJson()), jsonEncode(p.toJson()), reason: p.id);
        expect(copy.color, p.color, reason: p.id);
        expect(copy.effects, p.effects, reason: p.id);
        expect(copy.key, p.key);
      }
    });

    test('fromJson validates, and tolerates absent optional sections', () {
      expect(() => ImageProfile.fromJson(const <String, Object?>{'id': 'x'}), throwsA(isA<ProfileException>()));
      expect(() => ImageProfile.fromJson(const <String, Object?>{'id': 'x', 'version': 1, 'name': 'X', 'color': <String, Object?>{'contrast': 5}}), throwsA(isA<ProfileException>()));
      final minimal = ImageProfile.fromJson(const <String, Object?>{'id': 'plain', 'version': 2, 'name': 'Plain'});
      expect(minimal.color, const ColorParams());
      expect(minimal.effects, const ProfileEffects());
      expect(minimal.description, '');
    });

    test('the documented example from image-profile.md parses', () {
      final json = jsonDecode('''
{
  "id": "warm-film", "version": 1, "name": "Warm Film",
  "description": "Soft warm highlights, lifted blacks, gentle saturation.",
  "color": {
    "exposureEv": 0.0, "contrast": 0.1, "highlights": -0.2, "shadows": 0.15, "blackPoint": 0.04, "whitePoint": 0.97,
    "toneCurve": [[0,0.04],[0.25,0.24],[0.5,0.52],[0.75,0.78],[1,0.97]],
    "saturation": -0.05, "vibrance": 0.1, "temperatureShift": 0.08, "tintShift": 0.02,
    "hsl": { "orange": {"hue": 0.02, "sat": 0.05, "lum": 0.03} },
    "splitTone": { "shadows": {"hue": 200, "amount": 0.05}, "highlights": {"hue": 40, "amount": 0.08} },
    "monochrome": null
  },
  "effects": { "grain": { "amount": 0.25, "size": 1.2, "chroma": 0.1 }, "vignette": { "amount": 0.2, "midpoint": 0.6, "roundness": 0.2 } }
}''') as Map<String, Object?>;
      final p = ImageProfile.fromJson(json);
      expect(p.color.toneCurve.length, 5);
      expect(p.color.hsl[HueBand.orange]!.sat, 0.05);
      expect(p.color.splitHighlights.hue, 40);
      expect(p.color.monochrome, isNull);
      expect(p.effects.grain.size, 1.2);
    });

    test('value objects compare and hash structurally', () {
      expect(const HslShift(hue: 0.1), const HslShift(hue: 0.1));
      expect(const HslShift(hue: 0.1).hashCode, const HslShift(hue: 0.1).hashCode);
      expect(const HslShift().isIdentity, isTrue);
      expect(const SplitTone(hue: 1, amount: 1), const SplitTone(hue: 1, amount: 1));
      expect(const SplitTone(hue: 1).hashCode, const SplitTone(hue: 1).hashCode);
      expect(const MonochromeMix(), const MonochromeMix());
      expect(const MonochromeMix().hashCode, const MonochromeMix().hashCode);
      expect(const CurvePoint(0, 1), const CurvePoint(0, 1));
      expect(const CurvePoint(0, 1).hashCode, const CurvePoint(0, 1).hashCode);
      expect(const GrainParams(amount: 1), const GrainParams(amount: 1));
      expect(const GrainParams(amount: 1).hashCode, const GrainParams(amount: 1).hashCode);
      expect(const VignetteParams(amount: 1), const VignetteParams(amount: 1));
      expect(const VignetteParams(amount: 1).hashCode, const VignetteParams(amount: 1).hashCode);
      expect(const ProfileEffects(), const ProfileEffects());
      expect(const ProfileEffects().hashCode, const ProfileEffects().hashCode);
      expect(const ColorParams(contrast: 0.1).hashCode, const ColorParams(contrast: 0.1).hashCode);
      expect(const ColorParams(contrast: 0.1), isNot(const ColorParams(contrast: 0.2)));
      expect(const ProfileRefKey('a', 1), const ProfileRefKey('a', 1));
      expect(const ProfileRefKey('a', 1).hashCode, const ProfileRefKey('a', 1).hashCode);
      expect(const ProfileRefKey('a', 1).toString(), 'a@v1');
    });
  });

  group('ProfileRegistry (versioning)', () {
    final v1 = profile(id: 'look', version: 1);
    final v2 = profile(id: 'look', version: 2, color: const ColorParams(contrast: 0.1));

    test('[PRF-002] old versions stay available so existing Memories re-render identically', () {
      final registry = ProfileRegistry(<ImageProfile>[v1, v2]);
      expect(registry.find('look', 1), same(v1));
      expect(registry.find('look', 2), same(v2));
      expect(registry.find('look'), same(v2));
      expect(registry.find('look', 3), isNull);
      expect(registry.find('missing'), isNull);
      expect(registry.all.length, 2);
    });

    test('the picker lists only the newest version of each profile, in definition order', () {
      final registry = ProfileRegistry(<ImageProfile>[v1, profile(id: 'other'), v2]);
      expect(registry.latest.map((p) => p.key.toString()), <String>['look@v2', 'other@v1']);
    });

    test('a missing or unknown profile falls back to natural instead of blocking capture', () {
      final registry = ProfileRegistry.builtIn();
      expect(registry.resolve('does-not-exist').id, 'natural');
      expect(registry.resolve(null).id, 'natural');
      expect(registry.resolve('warm-film').id, 'warm-film');
      expect(registry.resolve('warm-film', 99).id, 'natural'); // unknown version of a known id
      expect(registry.resolve('warm-film', 1).version, 1);
    });

    test('rejects duplicate keys and invalid definitions', () {
      expect(() => ProfileRegistry(<ImageProfile>[v1, v1]), throwsA(isA<ProfileException>()));
      expect(() => ProfileRegistry(<ImageProfile>[profile(id: 'Bad Id')]), throwsA(isA<ProfileException>()));
    });
  });
}
