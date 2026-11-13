/// Layered intent (ADR-0003): Experience defaults → source layer (Scenario or Preset) → user overrides.
library;

import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:doro_cam/domain/experience/preset.dart';
import 'package:doro_cam/domain/experience/scenario.dart';

enum IntentLayer { experience, scenario, preset, user }

class LayeredIntent {
  const LayeredIntent({required this.intent, required this.provenance});

  /// The merged request, ready for `resolve`.
  final CaptureIntent intent;

  /// Which layer supplied each specified field, so the UI can say "this came from the Night scenario".
  final Map<IntentField, IntentLayer> provenance;

  IntentLayer? sourceOf(IntentField field) => provenance[field];
}

/// Merges the layers. Later layers win field by field. If both a [scenario] and a [preset] are given the
/// preset is used (a preset is the more specific choice); "custom mode" is saving the merged intent as a preset.
LayeredIntent layerIntents({
  required Experience experience,
  Scenario? scenario,
  Preset? preset,
  CaptureIntent user = CaptureIntent.empty,
}) {
  final layers = <(IntentLayer, CaptureIntent)>[
    (IntentLayer.experience, experience.defaultsWithProfile),
    if (preset != null) (IntentLayer.preset, preset.toIntent()) else if (scenario != null) (IntentLayer.scenario, scenario.intent),
    (IntentLayer.user, user),
  ];
  var merged = CaptureIntent.empty;
  final provenance = <IntentField, IntentLayer>{};
  for (final (layer, intent) in layers) {
    for (final field in intent.specifiedFields) {
      provenance[field] = layer;
    }
    merged = merged.merge(intent);
  }
  return LayeredIntent(intent: merged, provenance: Map<IntentField, IntentLayer>.unmodifiable(provenance));
}

/// "Custom mode": the merged intent saved as a new preset (without Experience-only defaults the user never touched).
Preset saveAsPreset({
  required String id,
  required String name,
  required Experience experience,
  required LayeredIntent layered,
  required DateTime now,
  int profileVersion = 1,
}) {
  final keep = layered.provenance.entries.where((e) => e.value != IntentLayer.experience).map((e) => e.key).toSet();
  final partial = layered.intent.without(layered.intent.specifiedFields.difference(keep));
  final profileId = partial.profileId ?? layered.intent.profileId;
  return Preset(
    id: id,
    name: name,
    experienceId: experience.id.name,
    intent: partial.without(<IntentField>{IntentField.profile, IntentField.live}),
    profile: profileId == null ? null : ProfileRef(profileId, profileVersion),
    live: layered.intent.live ?? false,
    createdAt: now,
  );
}
