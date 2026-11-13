// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/memory_repository.dart' show enqueueOutbox;
import 'package:doro_cam/data/platform.dart';
import 'package:drift/drift.dart';

/// Capture presets: create, edit, rename and delete (EXP-006, EXP-007). Signed-in changes are
/// queued for the server through the outbox; anonymous ones are queued when the user signs in.
class PresetRepository {
  PresetRepository({required AppDatabase db, required AccountContext account, Clock clock = systemClock, IdGenerator? ids})
    : _db = db,
      _account = account,
      _clock = clock,
      _ids = ids ?? IdGenerator();

  final AppDatabase _db;
  final AccountContext _account;
  final Clock _clock;
  final IdGenerator _ids;

  int get _now => _clock().millisecondsSinceEpoch;

  /// Live presets, oldest first.
  Future<List<PresetRow>> list() =>
      (_db.select(_db.presets)
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.asc(p.createdAt), (p) => OrderingTerm.asc(p.id)]))
          .get();

  Stream<List<PresetRow>> watch() =>
      (_db.select(_db.presets)
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.asc(p.createdAt), (p) => OrderingTerm.asc(p.id)]))
          .watch();

  Future<PresetRow?> get(String id) => (_db.select(_db.presets)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Creates a preset (when [id] is null) or updates one. Returns the saved row.
  Future<PresetRow> save({
    String? id,
    required String name,
    required String experienceId,
    required Map<String, Object?> intent,
    String? profileId,
    int? profileVersion,
    bool live = false,
    String source = 'user',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError.value(name, 'name', 'A preset name must be 1 to 80 characters.');
    }
    final presetId = id ?? _ids.newId();
    final now = _now;
    await _db.transaction(() async {
      final existing = await get(presetId);
      if (existing == null) {
        await _db
            .into(_db.presets)
            .insert(
              PresetsCompanion.insert(
                id: presetId,
                name: trimmed,
                experienceId: experienceId,
                intentJson: jsonEncode(intent),
                profileId: Value(profileId),
                profileVersion: Value(profileVersion),
                live: Value(live),
                source: Value(source),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (_db.update(_db.presets)..where((p) => p.id.equals(presetId))).write(
          PresetsCompanion(
            name: Value(trimmed),
            experienceId: Value(experienceId),
            intentJson: Value(jsonEncode(intent)),
            profileId: Value(profileId),
            profileVersion: Value(profileVersion),
            live: Value(live),
            source: Value(source),
            deletedAt: const Value(null),
            dirty: const Value(true),
            updatedAt: Value(now),
          ),
        );
      }
      final account = _account.accountId;
      if (account != null) {
        await (_db.delete(_db.outbox)..where((o) => o.entity.equals('preset') & o.entityId.equals(presetId))).go();
        await enqueueOutbox(_db, account: account, entity: 'preset', entityId: presetId, op: 'upsert', payload: const {}, now: now);
      }
    });
    return (await get(presetId))!;
  }

  /// Deletes a preset. Returns false if it does not exist.
  Future<bool> delete(String id) async {
    final existing = await get(id);
    if (existing == null || existing.deletedAt != null) {
      return false;
    }
    final now = _now;
    await _db.transaction(() async {
      await (_db.update(_db.presets)..where((p) => p.id.equals(id))).write(
        PresetsCompanion(deletedAt: Value(now), dirty: const Value(true), updatedAt: Value(now)),
      );
      final account = _account.accountId;
      if (account != null) {
        await (_db.delete(_db.outbox)..where((o) => o.entity.equals('preset') & o.entityId.equals(id))).go();
        await enqueueOutbox(_db, account: account, entity: 'preset', entityId: id, op: 'delete', payload: const {}, now: now);
      }
    });
    return true;
  }
}
