import 'dart:convert';

import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/experience/preset.dart';

/// A stored preset row as the domain [Preset] (an unreadable intent becomes an empty one: a damaged preset
/// never blocks the camera).
Preset rowToPreset(PresetRow row) {
  CaptureIntent intent;
  try {
    intent = CaptureIntent.fromJson(
      Map<String, Object?>.from(
        jsonDecode(row.intentJson) as Map<Object?, Object?>,
      ),
    );
  } on Object {
    intent = CaptureIntent.empty;
  }
  return Preset(
    id: row.id,
    name: row.name,
    experienceId: row.experienceId,
    intent: intent,
    profile: row.profileId == null
        ? null
        : ProfileRef(row.profileId!, row.profileVersion ?? 1),
    live: row.live,
    source: row.source == 'suggested'
        ? PresetSource.suggested
        : PresetSource.user,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true),
  );
}
