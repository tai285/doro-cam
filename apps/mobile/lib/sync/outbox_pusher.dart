// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// Result of one [OutboxPusher.push] run.
class PushResult {
  const PushResult({this.sent = 0, this.dropped = 0, this.waiting = 0, this.needsSignIn = false});

  /// Operations the server accepted.
  final int sent;

  /// Operations discarded because the server answered with a permanent client error or the target
  /// no longer exists (they can never succeed, so keeping them would block the queue).
  final int dropped;

  /// Operations left for a later run (offline, server busy, Memory not registered yet).
  final int waiting;
  final bool needsSignIn;
}

/// Sends queued metadata edits (caption, favorite, trash, restore, delete, presets) in order
/// (docs/architecture/sync.md "Push (outbox)"). Conflict rules: field-level last-writer-wins by
/// server receipt order, and delete wins over edit.
class OutboxPusher {
  OutboxPusher({required AppDatabase db, required DoroApiClient api, required AccountContext account})
    : _db = db,
      _api = api,
      _account = account;

  final AppDatabase _db;
  final DoroApiClient _api;
  final AccountContext _account;

  Future<PushResult> push() async {
    final account = _account.accountId;
    if (account == null) {
      return const PushResult();
    }
    final ops = await (_db.select(_db.outbox)
          ..where((o) => o.accountId.equals(account))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt), (o) => OrderingTerm.asc(o.id)]))
        .get();
    var sent = 0;
    var dropped = 0;
    var waiting = 0;
    // Once an operation for an entity is left waiting, later ones for the same entity must wait too,
    // otherwise they would be applied out of order.
    final blocked = <String>{};
    for (final op in ops) {
      final key = '${op.entity}:${op.entityId}';
      if (blocked.contains(key)) {
        waiting++;
        continue;
      }
      try {
        final outcome = await _apply(op);
        switch (outcome) {
          case _Outcome.sent:
            sent++;
            await _remove(op);
          case _Outcome.dropped:
            dropped++;
            await _remove(op);
          case _Outcome.waiting:
            waiting++;
            blocked.add(key);
        }
      } on NetworkException {
        await _bumpAttempts(op);
        return PushResult(sent: sent, dropped: dropped, waiting: ops.length - sent - dropped);
      } on ApiException catch (error) {
        if (error.isUnauthenticated) {
          return PushResult(sent: sent, dropped: dropped, waiting: ops.length - sent - dropped, needsSignIn: true);
        }
        if (error.isRateLimited || error.isServerError) {
          await _bumpAttempts(op);
          waiting++;
          blocked.add(key);
          continue;
        }
        dropped++; // a permanent client error: this operation can never succeed
        await _remove(op);
      }
    }
    return PushResult(sent: sent, dropped: dropped, waiting: waiting);
  }

  Future<void> _remove(OutboxRow op) => (_db.delete(_db.outbox)..where((o) => o.id.equals(op.id))).go();

  Future<void> _bumpAttempts(OutboxRow op) =>
      (_db.update(_db.outbox)..where((o) => o.id.equals(op.id))).write(OutboxCompanion(attempts: Value(op.attempts + 1)));

  Future<_Outcome> _apply(OutboxRow op) async {
    if (op.entity == 'preset') {
      return _applyPreset(op);
    }
    return _applyMemory(op);
  }

  Future<_Outcome> _applyMemory(OutboxRow op) async {
    final memory = await (_db.select(_db.memories)..where((m) => m.id.equals(op.entityId))).getSingleOrNull();
    switch (op.op) {
      case 'purge':
        // The server only deletes Memories that are already in the trash.
        try {
          await _api.purgeMemory(op.entityId);
        } on ApiException catch (error) {
          if (error.code == 'memory.not_trashed') {
            await _api.trashMemory(op.entityId);
            await _api.purgeMemory(op.entityId);
          } else if (error.status != 404) {
            rethrow;
          }
        }
        return _Outcome.sent;
      case 'patch':
      case 'trash':
      case 'restore':
        if (memory == null) {
          return _Outcome.dropped; // purged locally in the meantime: delete wins
        }
        if (!memory.registered) {
          return _Outcome.waiting; // the upload engine registers it first
        }
        try {
          final updated = await _send(op, memory);
          await _recordVersion(memory.id, updated);
          return _Outcome.sent;
        } on ApiException catch (error) {
          if (error.status == 404) {
            return _Outcome.dropped;
          }
          rethrow;
        }
    }
    return _Outcome.dropped;
  }

  Future<int> _send(OutboxRow op, MemoryRow memory) async {
    switch (op.op) {
      case 'trash':
        return (await _api.trashMemory(memory.id)).version;
      case 'restore':
        return (await _api.restoreMemory(memory.id)).version;
      default:
        final payload = Map<String, Object?>.from(jsonDecode(op.payloadJson) as Map<Object?, Object?>);
        try {
          return (await _api.patchMemory(memory.id, payload, ifMatch: memory.serverVersion)).version;
        } on ApiException catch (error) {
          if (error.code != 'conflict.version') {
            rethrow;
          }
          // Someone else changed it first. Ours is applied on top of their version (last writer wins
          // by server receipt order); the server assigns versions, never the client's clock.
          final current = await _api.memory(memory.id);
          return (await _api.patchMemory(memory.id, payload, ifMatch: current.version)).version;
        }
    }
  }

  Future<void> _recordVersion(String memoryId, int version) =>
      (_db.update(_db.memories)..where((m) => m.id.equals(memoryId))).write(MemoriesCompanion(serverVersion: Value(version)));

  Future<_Outcome> _applyPreset(OutboxRow op) async {
    if (op.op == 'delete') {
      try {
        await _api.deletePreset(op.entityId);
      } on ApiException catch (error) {
        if (error.status != 404) {
          rethrow;
        }
      }
      return _Outcome.sent;
    }
    final preset = await (_db.select(_db.presets)..where((p) => p.id.equals(op.entityId))).getSingleOrNull();
    if (preset == null || preset.deletedAt != null) {
      return _Outcome.dropped;
    }
    final saved = await _api.putPreset(
      preset.id,
      name: preset.name,
      experienceId: preset.experienceId,
      intent: Map<String, Object?>.from(jsonDecode(preset.intentJson) as Map<Object?, Object?>),
      profileId: preset.profileId,
      profileVersion: preset.profileVersion,
      live: preset.live,
      source: preset.source,
    );
    await (_db.update(_db.presets)..where((p) => p.id.equals(preset.id))).write(
      PresetsCompanion(serverVersion: Value(saved.version), dirty: const Value(false)),
    );
    return _Outcome.sent;
  }
}

enum _Outcome { sent, dropped, waiting }
