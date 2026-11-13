import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/intent_resolver.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:doro_cam/domain/experience/layers.dart';
import 'package:doro_cam/domain/experience/preset.dart';
import 'package:doro_cam/domain/experience/scenario.dart';
import 'package:doro_cam/profiles/builtin_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('Experiences', () {
    test('[EXP-001] there are exactly four, in a stable order', () {
      expect(Experiences.all.map((e) => e.id), <ExperienceId>[ExperienceId.mirrorless, ExperienceId.dslr, ExperienceId.film, ExperienceId.instant]);
      expect(Experiences.all.map((e) => e.name).toSet().length, 4);
    });

    test('[EXP-002] each defines defaults, a default profile, a theme and workflow flags', () {
      for (final e in Experiences.all) {
        expect(e.defaults.aspect, isNotNull, reason: e.name);
        expect(e.defaults.isEmpty, isFalse);
        expect(e.defaultProfileId, isNotEmpty);
        expect(e.tagline, isNotEmpty);
        expect(e.theme.cornerRadius, greaterThanOrEqualTo(0));
        expect(e.defaultsWithProfile.profileId, e.defaultProfileId);
      }
    });

    test('[EXP-002] every default profile exists in the profile registry', () {
      final registry = ProfileRegistry.builtIn();
      for (final e in Experiences.all) {
        expect(registry.find(e.defaultProfileId), isNotNull, reason: e.name);
      }
    });

    test('[EXP-011] Mirrorless and Instant are fully built; DSLR and Film are styled variants', () {
      expect(Experiences.all.where((e) => e.fullyBuilt).map((e) => e.id), <ExperienceId>[ExperienceId.mirrorless, ExperienceId.instant]);
    });

    test('[EXP-010] only Instant develops the capture after the shutter', () {
      expect(Experiences.all.where((e) => e.workflow.developsAfterCapture).map((e) => e.id), <ExperienceId>[ExperienceId.instant]);
    });

    test('each Experience has a distinct look (theme surface and font differ)', () {
      expect(Experiences.all.map((e) => e.theme.surface).toSet().length, 4);
      expect(Experiences.all.map((e) => e.theme.fontFamily).toSet().length, 4);
    });

    test('lookup by id and by stored name, with an unknown name falling back to Mirrorless', () {
      expect(Experiences.byId(ExperienceId.film), Experiences.film);
      expect(Experiences.fromName('instant'), Experiences.instant);
      expect(Experiences.fromName('hologram'), Experiences.mirrorless);
      expect(Experiences.fromName(null), Experiences.mirrorless);
    });

    test('[EXP-009] roll validator: unlimited rolls and non-authentic use never reject', () {
      expect(Experiences.mirrorless.validate(authentic: true, framesShot: 1000), isNull);
      expect(Experiences.film.validate(authentic: false, framesShot: 1000), isNull);
      expect(Experiences.film.validate(authentic: true, framesShot: 35), isNull);
      expect(Experiences.film.validate(authentic: true, framesShot: 36)!.code, 'roll_finished');
      expect(Experiences.film.validate(authentic: true, framesShot: 36).toString(), contains('roll_finished'));
    });
  });

  group('InstantDevelop (EXP-010)', () {
    const develop = InstantDevelop();

    test('starts undeveloped and ends fully developed', () {
      expect(develop.progress(Duration.zero), 0);
      expect(develop.progress(const Duration(seconds: 6)), 1);
      expect(develop.progress(const Duration(minutes: 5)), 1);
      expect(develop.progress(const Duration(seconds: -1)), 0);
      expect(develop.isDeveloped(const Duration(seconds: 5)), isFalse);
      expect(develop.isDeveloped(const Duration(seconds: 6)), isTrue);
    });

    test('progress is monotonic and eased', () {
      var last = -1.0;
      for (var ms = 0; ms <= 6000; ms += 100) {
        final p = develop.progress(Duration(milliseconds: ms));
        expect(p, greaterThanOrEqualTo(last));
        last = p;
      }
      expect(develop.progress(const Duration(seconds: 3)), closeTo(0.5, 1e-9));
      expect(develop.progress(const Duration(milliseconds: 600)), lessThan(0.1)); // slow start
    });

    test('opacity and haze mirror progress; a zero duration is instant', () {
      expect(develop.opacity(Duration.zero), 0);
      expect(develop.opacity(const Duration(seconds: 6)), 1);
      expect(const InstantDevelop(startOpacity: 0.2).opacity(Duration.zero), 0.2);
      expect(develop.chemicalHaze(Duration.zero), 1);
      expect(develop.chemicalHaze(const Duration(seconds: 6)), 0);
      expect(const InstantDevelop(duration: Duration.zero).progress(Duration.zero), 1);
    });
  });

  group('Scenarios (EXP-004)', () {
    test('the ten scenarios exist, with unique ids and names', () {
      expect(Scenarios.all.length, 10);
      expect(Scenarios.all.map((s) => s.id).toSet().length, 10);
      expect(Scenarios.all.map((s) => s.name), <String>['Portrait', 'Street', 'Landscape', 'Night', 'Sunset', 'Indoor', 'Bright Day', 'Film', 'Instant', 'Cinema']);
    });

    test('every recommended setting has an explanation and vice versa', () {
      for (final s in Scenarios.all) {
        expect(s.isConsistent, isTrue, reason: s.name);
        expect(s.summary, isNotEmpty);
        for (final text in s.explanations.values) {
          expect(text.length, greaterThan(10), reason: s.name);
        }
      }
    });

    test('every scenario recommends a profile that exists', () {
      final registry = ProfileRegistry.builtIn();
      for (final s in Scenarios.all) {
        expect(registry.find(s.intent.profileId!), isNotNull, reason: s.name);
      }
    });

    test('[CAM-005] resolved against a camera with nothing, every scenario still yields valid settings and explains what it dropped', () {
      for (final s in Scenarios.all) {
        final out = resolve(s.intent, CameraCapabilities.none);
        expect(out.settings.aspect, isNotEmpty);
        for (final a in out.adjustments) {
          expect(s.explanations.containsKey(a.field) || a.field == IntentField.muteAudio, isTrue, reason: '${s.name} ${a.field}');
        }
      }
    });

    test('Night brightens and avoids flash; Sunset darkens; Landscape goes wide', () {
      expect(Scenarios.night.intent.exposureBiasEv, greaterThan(0));
      expect(Scenarios.night.intent.flash, FlashMode.off);
      expect(Scenarios.sunset.intent.exposureBiasEv, lessThan(0));
      expect(Scenarios.landscape.intent.aspect, '16:9');
      expect(Scenarios.instant.intent.aspect, '1:1');
    });

    test('lookup by id and stored name', () {
      expect(Scenarios.byId(ScenarioId.night), Scenarios.night);
      expect(Scenarios.fromName('cinema'), Scenarios.cinema);
      expect(Scenarios.fromName('nonsense'), isNull);
      expect(Scenarios.fromName(null), isNull);
    });
  });

  group('layered intent (ADR-0003)', () {
    test('later layers win field by field, and provenance names the layer', () {
      final layered = layerIntents(
        experience: Experiences.mirrorless,
        scenario: Scenarios.night,
        user: const CaptureIntent(iso: 800, exposureBiasEv: 0.5),
      );
      expect(layered.intent.aspect, '3:2'); // experience default
      expect(layered.sourceOf(IntentField.aspect), IntentLayer.experience);
      expect(layered.intent.flash, FlashMode.off); // scenario overrides the experience (also off)
      expect(layered.sourceOf(IntentField.timer), IntentLayer.scenario);
      expect(layered.intent.exposureBiasEv, 0.5); // user beats the scenario's +1
      expect(layered.sourceOf(IntentField.exposureBias), IntentLayer.user);
      expect(layered.intent.iso, 800);
      expect(layered.sourceOf(IntentField.iso), IntentLayer.user);
      expect(layered.sourceOf(IntentField.profile), IntentLayer.scenario); // natural from the scenario beats the experience default
      expect(layered.sourceOf(IntentField.torch), isNull);
    });

    test('the Experience default profile applies when nothing else chooses one', () {
      final layered = layerIntents(experience: Experiences.film);
      expect(layered.intent.profileId, 'warm-film');
      expect(layered.sourceOf(IntentField.profile), IntentLayer.experience);
    });

    test('[EXP-006] a preset is the source layer; it wins over a scenario given at the same time', () {
      final preset = Preset(id: 'p1', name: 'Mine', experienceId: 'mirrorless', intent: const CaptureIntent(iso: 200), profile: const ProfileRef('soft-film', 1), live: true, createdAt: DateTime.utc(2026));
      final layered = layerIntents(experience: Experiences.mirrorless, scenario: Scenarios.night, preset: preset);
      expect(layered.intent.iso, 200);
      expect(layered.sourceOf(IntentField.iso), IntentLayer.preset);
      expect(layered.intent.profileId, 'soft-film');
      expect(layered.intent.live, isTrue);
      expect(layered.intent.timerSeconds, 0); // night's 3 s timer was not applied; the Experience default stays
    });

    test('merged intents resolve end to end', () {
      final layered = layerIntents(experience: Experiences.instant, scenario: Scenarios.sunset, user: const CaptureIntent(iso: 5000));
      final out = resolve(layered.intent, fullCamera, experience: Experiences.instant);
      expect(out.settings.iso, 3200); // clamped
      expect(out.settings.aspect, '16:9'); // sunset overrides instant's square when not authentic
      expect(out.settings.profileId, 'warm-film');
    });

    test('"custom mode" is saving the merged intent as a preset, keeping only what the user or scenario chose', () {
      final layered = layerIntents(experience: Experiences.mirrorless, scenario: Scenarios.sunset, user: const CaptureIntent(iso: 400, live: true));
      final preset = saveAsPreset(id: 'p9', name: 'Golden', experience: Experiences.mirrorless, layered: layered, now: DateTime.utc(2026, 11, 13));
      expect(preset.name, 'Golden');
      expect(preset.experienceId, 'mirrorless');
      expect(preset.intent.iso, 400);
      expect(preset.intent.exposureBiasEv, -0.7);
      expect(preset.intent.grid, isNull); // experience-only default not captured
      expect(preset.profile, const ProfileRef('warm-film', 1));
      expect(preset.live, isTrue);
      expect(preset.intent.profileId, isNull);
      // round trip: applying the preset reproduces the same effective choices
      final again = layerIntents(experience: Experiences.mirrorless, preset: preset);
      expect(again.intent.iso, 400);
      expect(again.intent.exposureBiasEv, -0.7);
      expect(again.intent.profileId, 'warm-film');
    });

    test('saving with no profile chosen stores none', () {
      final layered = LayeredIntent(intent: const CaptureIntent(iso: 100), provenance: const <IntentField, IntentLayer>{IntentField.iso: IntentLayer.user});
      final preset = saveAsPreset(id: 'p', name: 'X', experience: Experiences.dslr, layered: layered, now: DateTime.utc(2026));
      expect(preset.profile, isNull);
      expect(preset.live, isFalse);
    });
  });

  group('Preset (EXP-007)', () {
    Preset make({String name = 'Street 35', CaptureIntent intent = const CaptureIntent(iso: 200, whiteBalance: WbRequest.kelvin(5200))}) => Preset(
          id: 'p1',
          name: name,
          experienceId: 'mirrorless',
          intent: intent,
          profile: const ProfileRef('warm-film', 2),
          live: true,
          createdAt: DateTime.utc(2026, 11, 13, 10),
        );

    test('trims names and enforces 1–80 characters', () {
      expect(make(name: '  Hello  ').name, 'Hello');
      expect(() => make(name: '   '), throwsA(isA<InvariantViolation>()));
      expect(() => make(name: 'x' * 81), throwsA(isA<InvariantViolation>()));
      expect(make(name: 'x' * 80).name.length, 80);
      expect(() => Preset(id: '', name: 'a', experienceId: 'x', intent: CaptureIntent.empty, createdAt: DateTime.utc(2026)), throwsA(isA<InvariantViolation>()));
      expect(InvariantViolation('boom').toString(), contains('boom'));
    });

    test('rename and edit bump updatedAt and keep identity', () {
      final p = make();
      final renamed = p.rename('Street 28', DateTime.utc(2026, 11, 14));
      expect(renamed.name, 'Street 28');
      expect(renamed.id, p.id);
      expect(renamed.createdAt, p.createdAt);
      expect(renamed.updatedAt, DateTime.utc(2026, 11, 14));
      final edited = p.withIntent(const CaptureIntent(iso: 800), newLive: false, now: DateTime.utc(2026, 11, 15));
      expect(edited.intent.iso, 800);
      expect(edited.live, isFalse);
      expect(edited.profile, p.profile);
      expect(p.withIntent(p.intent, newProfile: const ProfileRef('natural', 1), now: DateTime.utc(2026, 11, 15)).profile, const ProfileRef('natural', 1));
    });

    test('JSON round trip preserves everything, including white balance and profile versions', () {
      final p = make();
      final copy = Preset.fromJson(p.toJson());
      expect(copy, p);
      expect(copy.intent.whiteBalance, const WbRequest.kelvin(5200));
      expect(copy.profile, const ProfileRef('warm-film', 2));
      expect(copy.hashCode, p.hashCode);
      expect(Preset.fromJson(<String, Object?>{...p.toJson(), 'source': 'suggested'}).source, PresetSource.suggested);
    });

    test('fromJson rejects missing fields and tolerates unknown intent entries', () {
      expect(() => Preset.fromJson(<String, Object?>{'id': 'x'}), throwsA(isA<InvariantViolation>()));
      expect(() => Preset.fromJson(<String, Object?>{'id': 'x', 'name': 'n', 'experienceId': 'm', 'createdAt': 'not a date'}), throwsA(isA<InvariantViolation>()));
      final lenient = Preset.fromJson(<String, Object?>{
        'id': 'x',
        'name': 'n',
        'experienceId': 'future-experience',
        'createdAt': '2026-01-01T00:00:00Z',
        'intent': <String, Object?>{'iso': 'lots', 'flash': 'plasma', 'zoom': 2},
      });
      expect(lenient.intent.iso, isNull);
      expect(lenient.intent.flash, isNull);
      expect(lenient.intent.zoom, 2);
      expect(Preset.fromJson(<String, Object?>{'id': 'x', 'name': 'n', 'experienceId': 'm', 'createdAt': '2026-01-01T00:00:00Z', 'intent': 5}).intent.isEmpty, isTrue);
    });

    test('toIntent adds the profile and LIVE choice', () {
      expect(make().toIntent().profileId, 'warm-film');
      expect(make().toIntent().live, isTrue);
      final plain = Preset(id: 'p', name: 'n', experienceId: 'm', intent: const CaptureIntent(iso: 100), createdAt: DateTime.utc(2026));
      expect(plain.toIntent().live, isNull);
      expect(plain.toIntent().profileId, isNull);
    });
  });

  group('CaptureIntent', () {
    test('merge: specified fields of the other win, others fall through', () {
      const base = CaptureIntent(iso: 100, flash: FlashMode.on);
      final merged = base.merge(const CaptureIntent(iso: 200, grid: true));
      expect(merged.iso, 200);
      expect(merged.flash, FlashMode.on);
      expect(merged.grid, isTrue);
      expect(base.merge(CaptureIntent.empty), base);
    });

    test('without clears exactly the named fields', () {
      const full = CaptureIntent(iso: 1, exposureTimeNs: 2, exposureBiasEv: 3, exposureLock: true, focus: FocusRequest.auto, manualFocusDiopters: 1, focusLock: true, whiteBalance: WbRequest.kelvin(5000), zoom: 2, flash: FlashMode.on, torch: true, timerSeconds: 3, grid: true, aspect: '1:1', photoFormat: PhotoFormat.jpeg, lens: LensKind.tele, live: true, muteAudio: true, profileId: 'natural');
      expect(full.specifiedFields, IntentField.values.toSet());
      for (final field in IntentField.values) {
        final cleared = full.without(<IntentField>{field});
        expect(cleared.specifiedFields, IntentField.values.toSet()..remove(field), reason: field.name);
        expect(cleared.valueOf(field), isNull);
      }
      expect(full.without(IntentField.values.toSet()).isEmpty, isTrue);
    });

    test('JSON round trip of every field', () {
      const full = CaptureIntent(iso: 1, exposureTimeNs: 2, exposureBiasEv: 0.5, exposureLock: true, focus: FocusRequest.manual, manualFocusDiopters: 1.5, focusLock: false, whiteBalance: WbRequest.preset(WbPreset.shade), zoom: 2.5, flash: FlashMode.auto, torch: false, timerSeconds: 10, grid: true, aspect: '16:9', photoFormat: PhotoFormat.dng, lens: LensKind.ultraWide, live: true, muteAudio: false, profileId: 'natural');
      final copy = CaptureIntent.fromJson(full.toJson());
      expect(copy, full);
      expect(copy.hashCode, full.hashCode);
      expect(copy.toString(), contains('iso'));
      expect(CaptureIntent.fromJson(const <String, Object?>{}), CaptureIntent.empty);
    });

    test('fromJson tolerates wrong types and integral doubles', () {
      final intent = CaptureIntent.fromJson(const <String, Object?>{'iso': 200.0, 'exposureTimeNs': 1.5, 'zoom': 'x', 'grid': 1, 'whiteBalance': 'warm', 'aspect': 4, 'profileId': 7});
      expect(intent.iso, 200);
      expect(intent.exposureTimeNs, isNull);
      expect(intent.zoom, isNull);
      expect(intent.grid, isNull);
      expect(intent.whiteBalance, isNull);
      expect(intent.aspect, isNull);
      expect(intent.profileId, isNull);
    });

    test('WbRequest json round trip, equality and printing', () {
      expect(WbRequest.fromJson(const WbRequest.kelvin(4000).toJson()), const WbRequest.kelvin(4000));
      expect(WbRequest.fromJson(const WbRequest.preset(WbPreset.cloudy).toJson()), const WbRequest.preset(WbPreset.cloudy));
      expect(WbRequest.fromJson(const <String, Object?>{'preset': 'lava'}), isNull);
      expect(const WbRequest.kelvin(4000).toString(), 'WbRequest(4000K)');
      expect(const WbRequest.preset(WbPreset.shade).toString(), 'WbRequest(shade)');
      expect(const WbRequest.kelvin(4000).hashCode, const WbRequest.kelvin(4000).hashCode);
    });
  });
}
