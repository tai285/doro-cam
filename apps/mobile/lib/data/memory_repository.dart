// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:drift/drift.dart';

/// How long a trashed Memory stays recoverable (MEM-007).
const trashRetention = Duration(days: 30);

/// Local Memories: the capture use case, the library queries and the edits (docs/architecture/sync.md
/// "The local drift DB is the source of truth"). Every edit is written to the Memory row and, when
/// signed in, appended to the outbox in the same transaction.
class MemoryRepository {
  MemoryRepository({
    required AppDatabase db,
    required AccountContext account,
    required MediaStore media,
    Clock clock = systemClock,
  }) : _db = db,
       _account = account,
       _media = media,
       _clock = clock;

  final AppDatabase _db;
  final AccountContext _account;
  final MediaStore _media;
  final Clock _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  // ---- capture ------------------------------------------------------------------------------

  /// Turns a finished capture into a durable Memory (MEM-001, MEM-002, NFR-002). The Memory is only
  /// visible once all its files are in place and fsynced and the row is committed, so a crash at any
  /// point leaves either a complete Memory or none; leftovers are found by [recoverOrphans].
  ///
  /// Calling it again with the same id returns the existing Memory, so a retried capture never
  /// duplicates.
  Future<MemoryView> commitCapture(CaptureDraft draft) async {
    final existing = await view(draft.id);
    if (existing != null) {
      return existing;
    }
    _validate(draft);

    final moved = <File>[];
    try {
      final rows = <AssetsCompanion>[];
      final assetIds = IdGenerator();
      for (final asset in draft.assets) {
        final source = File(asset.path);
        if (!source.existsSync()) {
          throw CaptureException('The ${asset.role} file does not exist: ${asset.path}');
        }
        final bytes = await source.length();
        if (bytes == 0) {
          throw CaptureException('The ${asset.role} file is empty.');
        }
        final digest = await sha256OfFile(source);
        final destination = File(_media.pathFor(draft.id, asset.role, asset.mime));
        await _media.adopt(source, destination);
        moved.add(destination);
        rows.add(
          AssetsCompanion.insert(
            id: assetIds.newId(),
            memoryId: draft.id,
            role: asset.role,
            localPath: Value(destination.path),
            bytes: bytes,
            sha256: digest,
            mime: asset.mime,
            width: Value(asset.width),
            height: Value(asset.height),
            durationMs: Value(asset.durationMs),
          ),
        );
      }

      final account = _account.accountId;
      final now = _now;
      await _db.transaction(() async {
        await _db
            .into(_db.memories)
            .insert(
              MemoriesCompanion.insert(
                id: draft.id,
                kind: draft.kind,
                capturedAt: draft.capturedAt.toUtc().millisecondsSinceEpoch,
                capturedTz: draft.capturedTz,
                experienceId: draft.experienceId,
                profileId: Value(draft.profileId),
                profileVersion: Value(draft.profileVersion),
                presetId: Value(draft.presetId),
                scenario: Value(draft.scenario),
                captureJson: jsonEncode(draft.capture),
                lat: Value(draft.lat),
                lon: Value(draft.lon),
                locationAccuracyM: Value(draft.locationAccuracyM),
                caption: Value(draft.caption),
                aspectRatio: Value(draft.aspectRatio),
                accountId: Value(account),
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (final row in rows) {
          await _db.into(_db.assets).insert(row);
          if (account != null) {
            await _db
                .into(_db.uploadJobs)
                .insert(
                  UploadJobsCompanion.insert(
                    assetId: row.id.value,
                    accountId: account,
                    state: UploadStates.pending,
                    updatedAt: now,
                  ),
                );
          }
        }
      });
    } on Object {
      // Nothing was committed: remove what was moved so no orphan is left behind.
      for (final file in moved) {
        if (file.existsSync()) {
          await file.delete();
        }
      }
      await _media.deleteMemoryFiles(draft.id);
      rethrow;
    }
    return (await view(draft.id))!;
  }

  void _validate(CaptureDraft draft) {
    if (draft.assets.isEmpty) {
      throw const CaptureException('A capture needs at least one file.');
    }
    final roles = draft.assets.map((a) => a.role).toList();
    if (roles.toSet().length != roles.length) {
      throw const CaptureException('Each asset role may appear only once per Memory.');
    }
    final originals = roles.where((r) => r == AssetRoles.photoOriginal || r == AssetRoles.videoOriginal).length;
    switch (draft.kind) {
      case MemoryKinds.photo:
      case MemoryKinds.motion:
        if (!roles.contains(AssetRoles.photoOriginal) || originals != 1) {
          throw const CaptureException('A photo or motion Memory needs exactly one photo_original.');
        }
        if (draft.kind == MemoryKinds.motion && !roles.contains(AssetRoles.motionClip)) {
          throw const CaptureException('A motion Memory needs a motion_clip.');
        }
        if (draft.kind == MemoryKinds.photo && roles.contains(AssetRoles.motionClip)) {
          throw const CaptureException('Only a motion Memory has a motion_clip.');
        }
      case MemoryKinds.video:
        if (!roles.contains(AssetRoles.videoOriginal)) {
          throw const CaptureException('A video Memory needs a video_original.');
        }
      default:
        throw CaptureException('Unknown Memory kind: ${draft.kind}.');
    }
    if ((draft.lat == null) != (draft.lon == null)) {
      throw const CaptureException('Location must have both latitude and longitude, or neither.');
    }
    if (draft.caption != null && draft.caption!.length > 2000) {
      throw const CaptureException('A caption can be at most 2000 characters.');
    }
  }

  /// Directories in the media store that no Memory owns (a capture that crashed before committing).
  /// Deletes them and returns how many were removed.
  Future<int> recoverOrphans({Duration grace = const Duration(hours: 1)}) async {
    final known = (await _db.select(_db.memories).get()).map((m) => m.id).toSet();
    final orphans = await _media.orphans(known, now: _clock(), grace: grace);
    for (final id in orphans) {
      await _media.deleteMemoryFiles(id);
    }
    return orphans.length;
  }

  // ---- library queries ----------------------------------------------------------------------

  /// Memories newest first, available offline (LIB-001). Re-emits when memories, assets or upload
  /// jobs change, so sync status (LIB-004) stays live.
  Stream<List<MemoryView>> watchLibrary({String? kind, bool favoritesOnly = false, bool trashed = false, int? limit}) =>
      _reactive(() => library(kind: kind, favoritesOnly: favoritesOnly, trashed: trashed, limit: limit));

  /// Runs [load] now and again whenever memories, assets or upload jobs change. Bursts of changes
  /// are coalesced so a slow consumer sees the latest state rather than every intermediate one.
  Stream<T> _reactive<T>(Future<T> Function() load) {
    // ignore: close_sinks
    late final StreamController<T> controller;
    StreamSubscription<Set<TableUpdate>>? updates;
    var running = false;
    var dirty = false;

    Future<void> emit() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      do {
        dirty = false;
        try {
          final value = await load();
          if (!controller.isClosed) {
            controller.add(value);
          }
        } on Object catch (error, stack) {
          if (!controller.isClosed) {
            controller.addError(error, stack);
          }
        }
      } while (dirty && !controller.isClosed);
      running = false;
    }

    controller = StreamController<T>(
      onListen: () {
        updates = _db.tableUpdates(TableUpdateQuery.onAllTables([_db.memories, _db.assets, _db.uploadJobs])).listen((_) => unawaited(emit()));
        unawaited(emit());
      },
      onCancel: () async {
        await updates?.cancel();
      },
    );
    return controller.stream;
  }

  Future<List<MemoryView>> library({String? kind, bool favoritesOnly = false, bool trashed = false, int? limit}) async {
    final query = _db.select(_db.memories)
      ..where((m) => trashed ? m.deletedAt.isNotNull() : m.deletedAt.isNull())
      ..orderBy([(m) => OrderingTerm.desc(m.capturedAt), (m) => OrderingTerm.desc(m.id)]);
    if (kind != null) {
      query.where((m) => m.kind.equals(kind));
    }
    if (favoritesOnly) {
      query.where((m) => m.favorite.equals(true));
    }
    if (limit != null) {
      query.limit(limit);
    }
    return _views(await query.get());
  }

  Stream<MemoryView?> watchMemory(String id) => _reactive(() => view(id));

  Future<MemoryView?> view(String id) async {
    final row = await (_db.select(_db.memories)..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return (await _views([row])).single;
  }

  Future<List<MemoryView>> _views(List<MemoryRow> rows) async {
    if (rows.isEmpty) {
      return const [];
    }
    final ids = rows.map((r) => r.id).toList();
    final assets = await (_db.select(_db.assets)..where((a) => a.memoryId.isIn(ids))).get();
    final jobs = await (_db.select(_db.uploadJobs)..where((j) => j.assetId.isIn(assets.map((a) => a.id).toList()))).get();
    final jobsByAsset = {for (final job in jobs) job.assetId: job};
    return [
      for (final row in rows)
        () {
          final own = assets.where((a) => a.memoryId == row.id).toList()
            ..sort((a, b) => AssetRoles.priority(a.role).compareTo(AssetRoles.priority(b.role)));
          return MemoryView(memory: row, assets: own, status: deriveSyncStatus(row, own, jobsByAsset));
        }(),
    ];
  }

  // ---- edits (MEM-004, MEM-006, MEM-007) ----------------------------------------------------

  Future<void> setCaption(String id, String? caption) async {
    final trimmed = caption?.trim();
    final value = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (value != null && value.length > 2000) {
      throw const CaptureException('A caption can be at most 2000 characters.');
    }
    await _edit(id, MemoriesCompanion(caption: Value(value)), 'patch', {'caption': value});
  }

  Future<void> setFavorite(String id, {required bool favorite}) =>
      _edit(id, MemoriesCompanion(favorite: Value(favorite)), 'patch', {'favorite': favorite});

  /// PRIV-001: clear the Memory's location. The original file keeps its EXIF (docs/architecture/security.md).
  Future<void> removeLocation(String id) => _edit(
    id,
    const MemoriesCompanion(lat: Value(null), lon: Value(null), locationAccuracyM: Value(null), locationShared: Value(false)),
    'patch',
    {'removeLocation': true},
  );

  /// SHR-006: whether this Memory's location may be shown to album members.
  Future<void> setLocationShared(String id, {required bool shared}) =>
      _edit(id, MemoriesCompanion(locationShared: Value(shared)), 'patch', {'locationShared': shared});

  /// Moves to the trash. Idempotent.
  Future<void> trash(String id) async {
    final current = await _memory(id);
    if (current.deletedAt != null) {
      return;
    }
    await _edit(id, MemoriesCompanion(deletedAt: Value(_now)), 'trash', const {});
  }

  /// Restores from the trash. Idempotent.
  Future<void> restore(String id) async {
    final current = await _memory(id);
    if (current.deletedAt == null) {
      return;
    }
    await _edit(id, const MemoriesCompanion(deletedAt: Value(null)), 'restore', const {});
  }

  Future<MemoryRow> _memory(String id) async {
    final row = await (_db.select(_db.memories)..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('No Memory with id $id.');
    }
    return row;
  }

  Future<void> _edit(String id, MemoriesCompanion changes, String op, Map<String, Object?> payload) async {
    final current = await _memory(id);
    await _db.transaction(() async {
      await (_db.update(_db.memories)..where((m) => m.id.equals(id))).write(changes.copyWith(updatedAt: Value(_now)));
      final account = _account.accountId ?? current.accountId;
      if (account != null && _account.accountId == current.accountId) {
        await enqueueOutbox(_db, account: account, entity: 'memory', entityId: id, op: op, payload: payload, now: _now);
      }
    });
  }

  /// Deletes a Memory from this device for good: its files, rows and queued uploads. A signed-in
  /// delete is also queued for the server ("delete wins over edit", docs/architecture/sync.md).
  Future<void> purge(String id) async {
    final current = await _memory(id);
    final account = current.accountId;
    await _db.transaction(() async {
      await (_db.delete(_db.memories)..where((m) => m.id.equals(id))).go(); // assets, jobs, parts cascade
      await (_db.delete(_db.outbox)..where((o) => o.entity.equals('memory') & o.entityId.equals(id))).go();
      if (account != null && current.registered) {
        await enqueueOutbox(_db, account: account, entity: 'memory', entityId: id, op: 'purge', payload: const {}, now: _now);
      }
    });
    await _media.deleteMemoryFiles(id);
  }

  /// Permanently removes Memories that have been in the trash for more than 30 days (MEM-007).
  Future<int> purgeExpired() async {
    final cutoff = _clock().subtract(trashRetention).millisecondsSinceEpoch;
    final expired = await (_db.select(_db.memories)..where((m) => m.deletedAt.isNotNull() & m.deletedAt.isSmallerThanValue(cutoff))).get();
    for (final row in expired) {
      await purge(row.id);
    }
    return expired.length;
  }

  /// Empties the trash.
  Future<int> emptyTrash() async {
    final trashed = await (_db.select(_db.memories)..where((m) => m.deletedAt.isNotNull())).get();
    for (final row in trashed) {
      await purge(row.id);
    }
    return trashed.length;
  }

  // ---- account hand-over ---------------------------------------------------------------------

  /// Called after sign-in: Memories captured while anonymous now belong to [accountId] and join the
  /// upload queue (AUTH-005). Presets and queued edits are claimed too. Memories already owned by
  /// another account are left alone, so uploads never cross accounts.
  Future<int> claimAnonymous(String accountId) async {
    final now = _now;
    var claimed = 0;
    await _db.transaction(() async {
      final orphans = await (_db.select(_db.memories)..where((m) => m.accountId.isNull() & m.capturedHere.equals(true))).get();
      for (final memory in orphans) {
        await (_db.update(_db.memories)..where((m) => m.id.equals(memory.id))).write(MemoriesCompanion(accountId: Value(accountId)));
        final assets = await (_db.select(_db.assets)..where((a) => a.memoryId.equals(memory.id))).get();
        for (final asset in assets) {
          await _db
              .into(_db.uploadJobs)
              .insert(
                UploadJobsCompanion.insert(assetId: asset.id, accountId: accountId, state: UploadStates.pending, updatedAt: now),
                mode: InsertMode.insertOrIgnore,
              );
        }
        if (memory.deletedAt != null) {
          await enqueueOutbox(_db, account: accountId, entity: 'memory', entityId: memory.id, op: 'trash', payload: const {}, now: now);
        }
        claimed++;
      }
      final presets = await (_db.select(_db.presets)).get();
      for (final preset in presets.where((p) => p.deletedAt == null)) {
        await enqueueOutbox(_db, account: accountId, entity: 'preset', entityId: preset.id, op: 'upsert', payload: const {}, now: now);
        await (_db.update(_db.presets)..where((p) => p.id.equals(preset.id))).write(const PresetsCompanion(dirty: Value(true)));
      }
    });
    return claimed;
  }
}

/// Appends a pending metadata mutation (docs/architecture/sync.md "outbox"). Visible to other
/// repositories so presets use the same queue.
Future<void> enqueueOutbox(
  AppDatabase db, {
  required String account,
  required String entity,
  required String entityId,
  required String op,
  required Map<String, Object?> payload,
  required int now,
}) async {
  await db
      .into(db.outbox)
      .insert(
        OutboxCompanion.insert(
          id: IdGenerator().newId(),
          accountId: account,
          entity: entity,
          entityId: entityId,
          op: op,
          payloadJson: Value(jsonEncode(payload)),
          createdAt: now,
        ),
      );
}

/// What the library shows for one Memory (LIB-004).
SyncStatus deriveSyncStatus(MemoryRow memory, List<AssetRow> assets, Map<String, UploadJobRow> jobsByAsset) {
  if (!memory.capturedHere) {
    return SyncStatus.synced;
  }
  if (memory.accountId == null) {
    return SyncStatus.localOnly;
  }
  final jobs = [for (final asset in assets) if (jobsByAsset[asset.id] != null) jobsByAsset[asset.id]!];
  if (jobs.any((job) => job.state == UploadStates.failedPermanent)) {
    return SyncStatus.failed;
  }
  if (memory.registered && jobs.isNotEmpty && jobs.every((job) => job.state == UploadStates.synced)) {
    return SyncStatus.synced;
  }
  return SyncStatus.uploading;
}
