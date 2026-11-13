/// Saved presets (EXP-006, EXP-007): capture settings + profile + experience options (memory-domain.md).
library;

import 'package:doro_cam/domain/camera/capture_intent.dart';

enum PresetSource { user, suggested }

/// Thrown when a preset or other domain object breaks an invariant.
class InvariantViolation implements Exception {
  InvariantViolation(this.message);

  final String message;

  @override
  String toString() => 'InvariantViolation: $message';
}

class ProfileRef {
  const ProfileRef(this.id, this.version);

  final String id;
  final int version;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'version': version};

  static ProfileRef? fromJson(Object? json) {
    if (json is Map<String, Object?> && json['id'] is String && json['version'] is int) {
      return ProfileRef(json['id']! as String, json['version']! as int);
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is ProfileRef && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() => '$id@v$version';
}

class Preset {
  Preset({
    required this.id,
    required String name,
    required this.experienceId,
    required this.intent,
    required this.createdAt,
    DateTime? updatedAt,
    this.profile,
    this.live = false,
    this.source = PresetSource.user,
  })  : name = name.trim(),
        updatedAt = updatedAt ?? createdAt {
    if (this.name.isEmpty || this.name.length > maxNameLength) {
      throw InvariantViolation('A preset name must be 1–$maxNameLength characters.');
    }
    if (id.isEmpty) {
      throw InvariantViolation('A preset needs an id.');
    }
  }

  static const int maxNameLength = 80;

  final String id;
  final String name;

  /// An [ExperienceId] name (kept as a string so unknown future Experiences still load).
  final String experienceId;

  /// A *partial* intent: unspecified fields fall through to the Experience defaults.
  final CaptureIntent intent;
  final ProfileRef? profile;
  final bool live;
  final PresetSource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The intent this preset applies: its stored intent plus its profile and LIVE choice.
  CaptureIntent toIntent() => intent.merge(CaptureIntent(profileId: profile?.id, live: live ? true : null));

  Preset rename(String newName, DateTime now) => Preset(
        id: id,
        name: newName,
        experienceId: experienceId,
        intent: intent,
        profile: profile,
        live: live,
        source: source,
        createdAt: createdAt,
        updatedAt: now,
      );

  Preset withIntent(CaptureIntent newIntent, {ProfileRef? newProfile, bool? newLive, required DateTime now}) => Preset(
        id: id,
        name: name,
        experienceId: experienceId,
        intent: newIntent,
        profile: newProfile ?? profile,
        live: newLive ?? live,
        source: source,
        createdAt: createdAt,
        updatedAt: now,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'experienceId': experienceId,
        'intent': intent.toJson(),
        if (profile != null) 'profile': profile!.toJson(),
        'live': live,
        'source': source.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  /// Throws [InvariantViolation] when required fields are missing or invalid.
  factory Preset.fromJson(Map<String, Object?> json) {
    final intent = json['intent'];
    final created = DateTime.tryParse('${json['createdAt']}');
    final updated = DateTime.tryParse('${json['updatedAt']}');
    if (json['id'] is! String || json['name'] is! String || json['experienceId'] is! String || created == null) {
      throw InvariantViolation('Preset JSON is missing required fields.');
    }
    return Preset(
      id: json['id']! as String,
      name: json['name']! as String,
      experienceId: json['experienceId']! as String,
      intent: CaptureIntent.fromJson(intent is Map<String, Object?> ? intent : const <String, Object?>{}),
      profile: ProfileRef.fromJson(json['profile']),
      live: json['live'] == true,
      source: json['source'] == 'suggested' ? PresetSource.suggested : PresetSource.user,
      createdAt: created,
      updatedAt: updated,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Preset &&
      other.id == id &&
      other.name == name &&
      other.experienceId == experienceId &&
      other.intent == intent &&
      other.profile == profile &&
      other.live == live &&
      other.source == source &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, experienceId, intent, profile, live, source, createdAt, updatedAt);
}
