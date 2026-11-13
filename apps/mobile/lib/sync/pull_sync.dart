// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/api_models.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:drift/drift.dart';

class PullResult {
  const PullResult({this.memoriesUpdated = 0, this.memoriesRemoved = 0, this.presetsChanged = 0, this.needsSignIn = false});
  final int memoriesUpdated;
  final int memoriesRemoved;
  final int presetsChanged;
  final bool needsSignIn;
}

/// Applies the server's change feed to the local database (docs/architecture/sync.md "Pull").
/// The feed names what changed; the full entities are fetched and merged, and the cursor advances
/// only together with the data it covers, in one transaction.
class PullSync {
  PullSync({required AppDatabase db, required DoroApiClient api, required AccountContext account, Clock clock = systemClock})
    : _db = db,
      _api = api,
      _account = account,
      _clock = clock;

  final AppDatabase _db;
  final DoroApiClient _api;
  final AccountContext _account;
  final Clock _clock;

  Future<int> cursor(String account) async =>
      (await (_db.select(_db.syncState)..where((s) => s.accountId.equals(account))).getSingleOrNull())?.cursor ?? 0;

  /// Pulls every page since the saved cursor. Safe to repeat: merging the same change twice is a no-op.
  Future<PullResult> pull() async {
    final account = _account.accountId;
    if (account == null) {
      return const PullResult();
    }
    var updated = 0;
    var removed = 0;
    var presets = 0;
    try {
      var position = await cursor(account);
      while (true) {
        final page = await _api.syncChanges(cursor: position);
        final memoryIds = <String>{};
        var presetChanged = false;
        for (final change in page.changes) {
          if (change.entity == 'memory') {
            memoryIds.add(change.entityId);
          } else if (change.entity == 'preset') {
            presetChanged = true;
          }
        }
        final fetched = <String, ApiMemory?>{};
        for (final id in memoryIds) {
          fetched[id] = await _fetchMemory(id);
        }
        final serverPresets = presetChanged ? await _api.presets() : null;
        await _db.transaction(() async {
          for (final entry in fetched.entries) {
            if (entry.value == null) {
              removed += await _removeLocal(entry.key);
            } else if (await _merge(entry.value!, account)) {
              updated++;
            }
          }
          if (serverPresets != null) {
            presets += await _mergePresets(serverPresets);
          }
          await _db
              .into(_db.syncState)
              .insertOnConflictUpdate(SyncStateCompanion.insert(accountId: account, cursor: Value(page.nextCursor)));
        });
        position = page.nextCursor;
        if (!page.hasMore) {
          break;
        }
      }
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        return PullResult(memoriesUpdated: updated, memoriesRemoved: removed, presetsChanged: presets, needsSignIn: true);
      }
      rethrow;
    }
    return PullResult(memoriesUpdated: updated, memoriesRemoved: removed, presetsChanged: presets);
  }

  /// null means the Memory no longer exists for this user (purged or never theirs).
  Future<ApiMemory?> _fetchMemory(String id) async {
    try {
      return await _api.memory(id);
    } on ApiException catch (error) {
      if (error.status == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<int> _removeLocal(String id) async {
    final row = await (_db.select(_db.memories)..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return 0;
    }
    // Delete wins over edit: drop pending edits and queued uploads along with the Memory.
    await (_db.delete(_db.outbox)..where((o) => o.entity.equals('memory') & o.entityId.equals(id))).go();
    await (_db.delete(_db.memories)..where((m) => m.id.equals(id))).go();
    return 1;
  }

  /// Merges one server Memory. Fields with a pending local edit are left alone (they will be sent on
  /// top of the new version); everything else takes the server's value. Returns true if anything changed.
  Future<bool> _merge(ApiMemory server, String account) async {
    final local = await (_db.select(_db.memories)..where((m) => m.id.equals(server.id))).getSingleOrNull();
    final now = _clock().millisecondsSinceEpoch;
    if (local == null) {
      await _db
          .into(_db.memories)
          .insert(
            MemoriesCompanion.insert(
              id: server.id,
              kind: server.kind,
              capturedAt: server.capturedAt.millisecondsSinceEpoch,
              capturedTz: server.capturedTz,
              experienceId: server.experienceId,
              profileId: Value(server.profileId),
              profileVersion: Value(server.profileVersion),
              presetId: Value(server.presetId),
              scenario: Value(server.scenario),
              captureJson: jsonEncode(server.capture),
              lat: Value(server.lat),
              lon: Value(server.lon),
              locationAccuracyM: Value(server.locationAccuracyM),
              locationShared: Value(server.locationShared),
              caption: Value(server.caption),
              favorite: Value(server.favorite),
              aspectRatio: Value(server.aspectRatio),
              publicHandle: Value(server.publicHandle),
              serverVersion: Value(server.version),
              accountId: Value(account),
              registered: const Value(true),
              capturedHere: const Value(false),
              createdAt: now,
              updatedAt: now,
              deletedAt: Value(server.deletedAt?.millisecondsSinceEpoch),
            ),
          );
      for (final asset in server.assets.where((a) => a.isServable)) {
        await _db
            .into(_db.assets)
            .insert(
              AssetsCompanion.insert(
                id: asset.id,
                memoryId: server.id,
                role: asset.role,
                bytes: asset.bytes,
                sha256: '',
                mime: asset.mime,
                width: Value(asset.width),
                height: Value(asset.height),
                durationMs: Value(asset.durationMs),
                uploadState: const Value('synced'),
                serverStatus: Value(asset.status),
              ),
            );
      }
      return true;
    }
    if (local.accountId != account) {
      return false; // never touch another account's data
    }
    final pending = await (_db.select(_db.outbox)..where((o) => o.entity.equals('memory') & o.entityId.equals(server.id))).get();
    final hasEdits = pending.isNotEmpty;
    final changes = hasEdits
        ? MemoriesCompanion(serverVersion: Value(server.version), registered: const Value(true), publicHandle: Value(server.publicHandle))
        : MemoriesCompanion(
            caption: Value(server.caption),
            favorite: Value(server.favorite),
            deletedAt: Value(server.deletedAt?.millisecondsSinceEpoch),
            lat: Value(server.lat),
            lon: Value(server.lon),
            locationAccuracyM: Value(server.locationAccuracyM),
            locationShared: Value(server.locationShared),
            serverVersion: Value(server.version),
            registered: const Value(true),
            publicHandle: Value(server.publicHandle),
            updatedAt: Value(now),
          );
    await (_db.update(_db.memories)..where((m) => m.id.equals(server.id))).write(changes);
    for (final asset in server.assets) {
      await (_db.update(_db.assets)..where((a) => a.id.equals(asset.id))).write(AssetsCompanion(serverStatus: Value(asset.status)));
    }
    return true;
  }

  /// Presets: the server's list wins unless the local copy has unsent changes; a clean local preset
  /// that the server no longer has was deleted elsewhere.
  Future<int> _mergePresets(List<ApiPreset> server) async {
    var changed = 0;
    final local = await _db.select(_db.presets).get();
    final localById = {for (final p in local) p.id: p};
    final serverIds = {for (final p in server) p.id};
    final now = _clock().millisecondsSinceEpoch;
    for (final preset in server) {
      final existing = localById[preset.id];
      if (existing != null && existing.dirty) {
        continue;
      }
      await _db
          .into(_db.presets)
          .insertOnConflictUpdate(
            PresetsCompanion.insert(
              id: preset.id,
              name: preset.name,
              experienceId: preset.experienceId,
              intentJson: jsonEncode(preset.intent),
              profileId: Value(preset.profileId),
              profileVersion: Value(preset.profileVersion),
              live: Value(preset.live),
              source: Value(preset.source),
              serverVersion: Value(preset.version),
              dirty: const Value(false),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      changed++;
    }
    for (final preset in local) {
      if (!serverIds.contains(preset.id) && !preset.dirty && preset.serverVersion != null) {
        await (_db.delete(_db.presets)..where((p) => p.id.equals(preset.id))).go();
        changed++;
      }
    }
    return changed;
  }
}
