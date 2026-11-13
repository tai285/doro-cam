// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/api_models.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:doro_cam/data/settings_repository.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:doro_cam/sync/storage_uploader.dart';
import 'package:drift/drift.dart';

/// Tunables of the upload engine. Defaults follow docs/architecture/sync.md and docs/specs/upload-sync.md.
class UploadEngineConfig {
  const UploadEngineConfig({
    this.backoffBase = const Duration(seconds: 5),
    this.backoffCap = const Duration(minutes: 30),
    this.maxChecksumFailures = 3,
    this.maxStorageRejections = 3,
    this.maxRestarts = 12,
    this.verifyPollInterval = const Duration(seconds: 1),
    this.maxVerifyPolls = 30,
    this.quotaPause = const Duration(hours: 1),
    this.urlRefreshMargin = const Duration(seconds: 30),
  });

  final Duration backoffBase;
  final Duration backoffCap;

  /// SYNC-008: a checksum mismatch restarts the upload; the third one is permanent.
  final int maxChecksumFailures;

  /// How many freshly presigned URLs may be rejected in a row before the failure is permanent.
  final int maxStorageRejections;

  /// Restarts (lost server session, vanished asset) before the failure is treated as permanent.
  final int maxRestarts;
  final Duration verifyPollInterval;
  final int maxVerifyPolls;
  final Duration quotaPause;
  final Duration urlRefreshMargin;
}

/// Things the UI may want to react to.
sealed class UploadEvent {
  const UploadEvent();
}

class AssetSynced extends UploadEvent {
  const AssetSynced(this.memoryId, this.assetId);
  final String memoryId;
  final String assetId;
}

class AssetFailed extends UploadEvent {
  const AssetFailed(this.memoryId, this.assetId, this.code);
  final String memoryId;
  final String assetId;
  final String code;
}

/// The session ended; the queue pauses until the user signs in again (`auth.unauthenticated`).
class NeedsSignIn extends UploadEvent {
  const NeedsSignIn();
}

/// The account's storage is full; the queue pauses (`upload.quota_exceeded`).
class QuotaExceeded extends UploadEvent {
  const QuotaExceeded();
}

class _Pause implements Exception {
  const _Pause();
}

class _PermanentFailure implements Exception {
  const _PermanentFailure(this.code, this.message);
  final String code;
  final String message;
}

/// Restarts the upload from step 2 (session expired server-side, size mismatch).
class _Restart implements Exception {
  const _Restart(this.reason, {this.countsAsChecksumFailure = false});
  final String reason;
  final bool countsAsChecksumFailure;
}

/// The resumable, durable upload queue runner (docs/specs/upload-sync.md, docs/architecture/sync.md).
///
/// Every state transition is written to the database before the side effect it authorizes counts
/// as done, so killing the process at any point and starting a new engine on the same database
/// resumes where it left off (SYNC-001, SYNC-003). Retries never create duplicates because the
/// server is idempotent (SYNC-004), and an asset is only marked synced once the server reports it
/// verified (SYNC-008).
class UploadEngine {
  UploadEngine({
    required AppDatabase db,
    required DoroApiClient api,
    required StorageUploader storage,
    required ConnectivityMonitor connectivity,
    required AccountContext account,
    required SettingsRepository settings,
    PowerMonitor power = const UnlimitedPower(),
    UploadPolicy policy = const UploadPolicy(),
    UploadEngineConfig config = const UploadEngineConfig(),
    Clock clock = systemClock,
    Random? random,
    Sleeper sleeper = realSleep,
    this.checkpoint,
  }) : _db = db,
       _api = api,
       _storage = storage,
       _connectivity = connectivity,
       _account = account,
       _settings = settings,
       _power = power,
       _policy = policy,
       _config = config,
       _clock = clock,
       _random = random ?? Random(),
       _sleeper = sleeper;

  final AppDatabase _db;
  final DoroApiClient _api;
  final StorageUploader _storage;
  final ConnectivityMonitor _connectivity;
  final AccountContext _account;
  final SettingsRepository _settings;
  final PowerMonitor _power;
  final UploadPolicy _policy;
  final UploadEngineConfig _config;
  final Clock _clock;
  final Random _random;
  final Sleeper _sleeper;

  /// Test seam: called right after each persisted transition with a label such as
  /// `uploading` or `part:3`. Tests throw from it to simulate the app being killed.
  final FutureOr<void> Function(String point)? checkpoint;

  final StreamController<UploadEvent> _events = StreamController<UploadEvent>.broadcast();
  Future<int>? _running;

  Stream<UploadEvent> get events => _events.stream;

  int get _now => _clock().millisecondsSinceEpoch;

  /// Runs every upload that is due until nothing is left to do now, then returns how many assets
  /// reached a final state. Concurrent calls share one run.
  Future<int> drain({int maxJobs = 1 << 30}) => _running ??= _drain(maxJobs).whenComplete(() => _running = null);

  Future<int> _drain(int maxJobs) async {
    var finished = 0;
    while (finished < maxJobs) {
      if (!await _mayRun()) {
        break;
      }
      final job = await _nextDue();
      if (job == null) {
        break;
      }
      try {
        if (await _process(job)) {
          finished++;
        }
      } on _Pause {
        break;
      }
    }
    return finished;
  }

  /// When the next queued job becomes due, or null if nothing is waiting.
  Future<DateTime?> nextDueAt() async {
    final account = _account.accountId;
    if (account == null) {
      return null;
    }
    final jobs = await (_db.select(_db.uploadJobs)
          ..where((j) => j.accountId.equals(account) & j.state.isIn(UploadStates.active)))
        .get();
    if (jobs.isEmpty) {
      return null;
    }
    final earliest = jobs.map((j) => j.state == UploadStates.backoff ? j.nextAttemptAt : 0).reduce(min);
    return DateTime.fromMillisecondsSinceEpoch(max(earliest, 0), isUtc: true);
  }

  /// Puts a permanently failed asset back in the queue (the user tapped "retry").
  Future<void> retry(String assetId) async {
    await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(assetId))).write(
      UploadJobsCompanion(
        state: const Value(UploadStates.pending),
        resumeState: const Value(UploadStates.pending),
        attempts: const Value(0),
        nextAttemptAt: const Value(0),
        checksumFailures: const Value(0),
        serverUploadId: const Value(null),
        partSize: const Value(null),
        partCount: const Value(null),
        lastError: const Value(null),
        lastErrorCode: const Value(null),
        updatedAt: Value(_now),
      ),
    );
    await (_db.delete(_db.uploadParts)..where((p) => p.assetId.equals(assetId))).go();
    await (_db.update(_db.assets)..where((a) => a.id.equals(assetId))).write(const AssetsCompanion(uploadState: Value('pending')));
  }

  Future<bool> _mayRun() async {
    if (_account.accountId == null) {
      return false;
    }
    return _policy.allows(
      network: await _connectivity.current(),
      wifiOnly: await _settings.wifiOnly(),
      power: await _power.current(),
      lowBatteryPercent: await _settings.lowBatteryPercent(),
    );
  }

  Future<UploadJobRow?> _nextDue() async {
    final account = _account.accountId;
    if (account == null) {
      return null;
    }
    final now = _now;
    final query = _db.select(_db.uploadJobs).join([
      innerJoin(_db.assets, _db.assets.id.equalsExp(_db.uploadJobs.assetId)),
      innerJoin(_db.memories, _db.memories.id.equalsExp(_db.assets.memoryId)),
    ])
      ..where(
        _db.uploadJobs.accountId.equals(account) &
            _db.uploadJobs.state.isIn(UploadStates.active) &
            _db.uploadJobs.nextAttemptAt.isSmallerOrEqualValue(now) &
            _db.memories.deletedAt.isNull(),
      );
    final rows = await query.get();
    if (rows.isEmpty) {
      return null;
    }
    rows.sort((a, b) {
      final byRole = AssetRoles.priority(a.readTable(_db.assets).role).compareTo(AssetRoles.priority(b.readTable(_db.assets).role));
      if (byRole != 0) {
        return byRole;
      }
      final byMemory = a.readTable(_db.memories).createdAt.compareTo(b.readTable(_db.memories).createdAt);
      return byMemory != 0 ? byMemory : a.readTable(_db.assets).id.compareTo(b.readTable(_db.assets).id);
    });
    return rows.first.readTable(_db.uploadJobs);
  }

  // ---- one asset ----------------------------------------------------------------------------

  /// Drives one job until it is synced, failed, or waiting. Returns true when it reached a final state.
  Future<bool> _process(UploadJobRow initial) async {
    var job = initial;
    if (job.state == UploadStates.backoff) {
      job = await _setState(job, job.resumeState);
    }
    try {
      while (true) {
        job = await _reload(job.assetId);
        switch (job.state) {
          case UploadStates.pending:
          case UploadStates.registering:
            await _register(job);
          case UploadStates.uploading:
            await _upload(job);
          case UploadStates.completing:
            await _complete(job);
          case UploadStates.verifying:
            await _verify(job);
          case UploadStates.synced:
            return true;
          default:
            return job.state == UploadStates.failedPermanent;
        }
      }
    } on _Pause {
      rethrow;
    } on _PermanentFailure catch (failure) {
      await _fail(job, failure.code, failure.message);
      return true;
    } on _Restart catch (restart) {
      return _restart(job, restart);
    } on NetworkException catch (error) {
      await _backoff(job, 'network: ${error.cause}', 'network');
      return false;
    } on FileSystemException catch (error) {
      await _fail(job, 'local_file_missing', 'The local file is unavailable: ${error.message}');
      return true;
    } on ApiException catch (error) {
      return _handleApiError(job, error);
    }
  }

  Future<bool> _handleApiError(UploadJobRow job, ApiException error) async {
    if (error.isUnauthenticated) {
      _events.add(const NeedsSignIn());
      throw const _Pause();
    }
    if (error.isRateLimited || error.isServerError) {
      await _backoff(job, '${error.status} ${error.code}', error.code, retryAfter: error.retryAfter);
      return false;
    }
    if (error.code == 'upload.quota_exceeded') {
      await _backoff(job, error.message, error.code, fixedDelay: _config.quotaPause);
      _events.add(const QuotaExceeded());
      throw const _Pause();
    }
    if (error.code == 'upload.not_found' || error.code == 'upload.size_mismatch') {
      return _restart(job, _Restart(error.code, countsAsChecksumFailure: error.code == 'upload.size_mismatch'));
    }
    // Any other 4xx is the client's problem (too large, unsupported type, conflict): retrying cannot help.
    await _fail(job, error.code, error.message);
    return true;
  }

  Future<UploadJobRow> _reload(String assetId) => (_db.select(_db.uploadJobs)..where((j) => j.assetId.equals(assetId))).getSingle();

  Future<UploadJobRow> _setState(UploadJobRow job, String state, {Map<String, Object?> extra = const {}}) async {
    await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(job.assetId))).write(
      UploadJobsCompanion(
        state: Value(state),
        serverUploadId: extra.containsKey('uploadId') ? Value(extra['uploadId'] as String?) : const Value.absent(),
        partSize: extra.containsKey('partSize') ? Value(extra['partSize'] as int?) : const Value.absent(),
        partCount: extra.containsKey('partCount') ? Value(extra['partCount'] as int?) : const Value.absent(),
        updatedAt: Value(_now),
      ),
    );
    await _updateAssetState(job.assetId, state);
    await checkpoint?.call(state);
    return _reload(job.assetId);
  }

  Future<void> _updateAssetState(String assetId, String state) {
    final summary = switch (state) {
      UploadStates.synced => 'synced',
      UploadStates.failedPermanent => 'failed',
      UploadStates.uploading || UploadStates.completing || UploadStates.verifying || UploadStates.registering => 'uploading',
      _ => 'pending',
    };
    return (_db.update(_db.assets)..where((a) => a.id.equals(assetId))).write(AssetsCompanion(uploadState: Value(summary)));
  }

  Future<void> _backoff(UploadJobRow job, String reason, String code, {Duration? retryAfter, Duration? fixedDelay}) async {
    final fresh = await _reload(job.assetId);
    final delay = retryAfter ?? fixedDelay ?? backoffDelay(fresh.attempts, _random, base: _config.backoffBase, cap: _config.backoffCap);
    final resume = fresh.state == UploadStates.backoff ? fresh.resumeState : fresh.state;
    await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(job.assetId))).write(
      UploadJobsCompanion(
        state: const Value(UploadStates.backoff),
        resumeState: Value(resume == UploadStates.registering ? UploadStates.pending : resume),
        attempts: Value(fresh.attempts + 1),
        nextAttemptAt: Value(_now + delay.inMilliseconds),
        lastError: Value(reason),
        lastErrorCode: Value(code),
        updatedAt: Value(_now),
      ),
    );
    await checkpoint?.call('backoff');
  }

  Future<void> _fail(UploadJobRow job, String code, String message) async {
    await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(job.assetId))).write(
      UploadJobsCompanion(
        state: const Value(UploadStates.failedPermanent),
        lastError: Value(message),
        lastErrorCode: Value(code),
        updatedAt: Value(_now),
      ),
    );
    await _updateAssetState(job.assetId, UploadStates.failedPermanent);
    final asset = await (_db.select(_db.assets)..where((a) => a.id.equals(job.assetId))).getSingleOrNull();
    if (asset != null) {
      _events.add(AssetFailed(asset.memoryId, asset.id, code));
    }
    await checkpoint?.call('failed');
  }

  /// Starts again from step 2: forgets the server-side session and the recorded parts.
  Future<bool> _restart(UploadJobRow job, _Restart restart) async {
    final fresh = await _reload(job.assetId);
    final failures = fresh.checksumFailures + (restart.countsAsChecksumFailure ? 1 : 0);
    if (!restart.countsAsChecksumFailure && fresh.attempts >= _config.maxRestarts) {
      await _fail(job, 'too_many_restarts', 'The upload restarted ${fresh.attempts} times (${restart.reason}).');
      return true;
    }
    if (failures >= _config.maxChecksumFailures) {
      await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(job.assetId))).write(UploadJobsCompanion(checksumFailures: Value(failures)));
      await _fail(job, 'checksum_mismatch', 'The server could not verify the upload after $failures attempts (${restart.reason}).');
      return true;
    }
    await _db.transaction(() async {
      await (_db.delete(_db.uploadParts)..where((p) => p.assetId.equals(job.assetId))).go();
      await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(job.assetId))).write(
        UploadJobsCompanion(
          state: const Value(UploadStates.pending),
          resumeState: const Value(UploadStates.pending),
          checksumFailures: Value(failures),
          attempts: Value(fresh.attempts + 1),
          serverUploadId: const Value(null),
          partSize: const Value(null),
          partCount: const Value(null),
          lastError: Value('restarted: ${restart.reason}'),
          lastErrorCode: Value(restart.reason),
          updatedAt: Value(_now),
        ),
      );
    });
    await _updateAssetState(job.assetId, UploadStates.pending);
    await checkpoint?.call('restart');
    // Restarting is immediate for a lost session; a mismatch waits a little so a flapping server is not hammered.
    if (restart.countsAsChecksumFailure) {
      await _backoff(await _reload(job.assetId), restart.reason, restart.reason);
      return false;
    }
    return false;
  }

  // ---- steps --------------------------------------------------------------------------------

  Future<(AssetRow, MemoryRow, File)> _load(UploadJobRow job) async {
    final asset = await (_db.select(_db.assets)..where((a) => a.id.equals(job.assetId))).getSingle();
    final memory = await (_db.select(_db.memories)..where((m) => m.id.equals(asset.memoryId))).getSingle();
    final path = asset.localPath;
    if (path == null) {
      throw const _PermanentFailure('local_file_missing', 'The asset has no local file.');
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw const _PermanentFailure('local_file_missing', 'The local file was deleted before it could be uploaded.');
    }
    if (await file.length() != asset.bytes) {
      throw const _PermanentFailure('local_file_changed', 'The local file no longer has the size that was recorded at capture.');
    }
    return (asset, memory, file);
  }

  /// Step 1: make sure the server knows the Memory (idempotent upsert), then move to `uploading`.
  Future<void> _register(UploadJobRow job) async {
    var current = job;
    if (current.state != UploadStates.registering) {
      current = await _setState(current, UploadStates.registering);
    }
    final (_, memory, _) = await _load(current);
    if (!memory.registered) {
      final result = await _api.registerMemory(memory.id, _registerBody(memory));
      await (_db.update(_db.memories)..where((m) => m.id.equals(memory.id))).write(
        MemoriesCompanion(
          registered: const Value(true),
          serverVersion: Value(result.memory.version),
          publicHandle: Value(result.memory.publicHandle),
        ),
      );
    }
    await _setState(current, UploadStates.uploading);
  }

  RegisterMemory _registerBody(MemoryRow memory) => RegisterMemory(
    kind: memory.kind,
    capturedAt: DateTime.fromMillisecondsSinceEpoch(memory.capturedAt, isUtc: true),
    capturedTz: memory.capturedTz,
    experienceId: memory.experienceId,
    capture: Map<String, Object?>.from(jsonDecode(memory.captureJson) as Map<Object?, Object?>),
    profileId: memory.profileId,
    profileVersion: memory.profileVersion,
    presetId: memory.presetId,
    scenario: memory.scenario,
    lat: memory.lat,
    lon: memory.lon,
    locationAccuracyM: memory.locationAccuracyM,
    caption: memory.caption,
    favorite: memory.favorite,
    aspectRatio: memory.aspectRatio,
  );

  /// Step 2 and 3: ask for the upload (the server answers "already done", a single PUT, or the
  /// parts still missing) and transfer the bytes. Always starts by asking, so a restart after a kill
  /// gets fresh URLs and learns which parts storage already holds.
  Future<void> _upload(UploadJobRow job) async {
    final (asset, memory, file) = await _load(job);
    var plan = await _api.createUpload(memory.id, asset.id, _createBody(asset));
    switch (plan) {
      case CompleteUploadPlan():
        await _markSynced(job, asset);
      case SingleUploadPlan():
        var rejections = 0;
        while (true) {
          final single = plan;
          if (single is! SingleUploadPlan) {
            throw const _Restart('upload_plan_changed');
          }
          final result = await _storage.putRange(single.url, file, offset: 0, length: asset.bytes, headers: single.headers);
          if (result.ok) {
            break;
          }
          plan = await _handleRejection(result, job, asset, memory, ++rejections);
          if (plan is CompleteUploadPlan) {
            await _markSynced(job, asset);
            return;
          }
        }
        await _setState(job, UploadStates.completing);
      case MultipartUploadPlan():
        await _uploadParts(job, asset, memory, file, plan);
    }
  }

  CreateUpload _createBody(AssetRow asset) => CreateUpload(
    role: asset.role,
    mime: asset.mime,
    bytes: asset.bytes,
    sha256: asset.sha256,
    width: asset.width,
    height: asset.height,
    durationMs: asset.durationMs,
  );

  /// A presigned URL was rejected. Ask for fresh ones and carry on; only a fresh URL being
  /// rejected counts toward the permanent-failure limit (upload-sync.md "Transfer").
  Future<UploadPlan> _handleRejection(PutResult result, UploadJobRow job, AssetRow asset, MemoryRow memory, int rejections) async {
    if (result.looksLikeExpiredUrl) {
      if (rejections >= _config.maxStorageRejections) {
        throw _PermanentFailure('storage_rejected', 'Storage rejected freshly signed URLs ${result.statusCode}: ${result.body}');
      }
      return _api.createUpload(memory.id, asset.id, _createBody(asset));
    }
    // 5xx and anything unexpected from storage: retry later.
    throw NetworkException('storage answered ${result.statusCode}');
  }

  Future<void> _uploadParts(UploadJobRow job, AssetRow asset, MemoryRow memory, File file, MultipartUploadPlan first) async {
    var plan = first;
    await _db.transaction(() async {
      await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(asset.id))).write(
        UploadJobsCompanion(serverUploadId: Value(plan.uploadId), partSize: Value(plan.partSize), partCount: Value(plan.partCount), updatedAt: Value(_now)),
      );
      for (var n = 1; n <= plan.partCount; n++) {
        await _db.into(_db.uploadParts).insert(UploadPartsCompanion.insert(assetId: asset.id, partNumber: n), mode: InsertMode.insertOrIgnore);
      }
      // The server is the authority on what storage holds.
      for (final entry in plan.completed.entries) {
        await (_db.update(_db.uploadParts)..where((p) => p.assetId.equals(asset.id) & p.partNumber.equals(entry.key))).write(
          UploadPartsCompanion(etag: Value(entry.value), state: const Value('done')),
        );
      }
    });
    await checkpoint?.call('multipart');

    var rejections = 0;
    final pending = plan.parts.keys.toList()..sort();
    for (final number in pending) {
      while (true) {
        if (plan.expiresAt.difference(_clock()) < _config.urlRefreshMargin) {
          plan = await _refreshPlan(job, asset, memory, plan);
        }
        final url = plan.parts[number];
        if (url == null) {
          break; // the refreshed plan says storage already has this part
        }
        final offset = (number - 1) * plan.partSize;
        final length = min(plan.partSize, asset.bytes - offset);
        final result = await _storage.putRange(url, file, offset: offset, length: length);
        if (result.ok) {
          final etag = result.etag;
          if (etag == null) {
            throw NetworkException('storage returned no ETag for part $number');
          }
          // Persist the ETag before moving on: a kill after this line never re-uploads the part.
          await (_db.update(_db.uploadParts)..where((p) => p.assetId.equals(asset.id) & p.partNumber.equals(number))).write(
            UploadPartsCompanion(etag: Value(etag), state: const Value('done')),
          );
          await checkpoint?.call('part:$number');
          rejections = 0;
          break;
        }
        final next = await _handleRejection(result, job, asset, memory, ++rejections);
        if (next is MultipartUploadPlan) {
          plan = next;
        } else {
          await _markSynced(job, asset);
          return;
        }
      }
    }
    await _setState(job, UploadStates.completing);
  }

  Future<MultipartUploadPlan> _refreshPlan(UploadJobRow job, AssetRow asset, MemoryRow memory, MultipartUploadPlan old) async {
    final fresh = await _api.createUpload(memory.id, asset.id, _createBody(asset));
    if (fresh is MultipartUploadPlan) {
      return fresh;
    }
    throw const _Restart('upload_plan_changed');
  }

  Future<void> _complete(UploadJobRow job) async {
    final asset = await (_db.select(_db.assets)..where((a) => a.id.equals(job.assetId))).getSingle();
    final memory = await (_db.select(_db.memories)..where((m) => m.id.equals(asset.memoryId))).getSingle();
    List<({int partNumber, String etag})>? parts;
    if (job.serverUploadId != null) {
      final rows = await (_db.select(_db.uploadParts)
            ..where((p) => p.assetId.equals(asset.id))
            ..orderBy([(p) => OrderingTerm.asc(p.partNumber)]))
          .get();
      if (rows.any((p) => p.etag == null)) {
        // A part is missing (rows were reset): go back and upload it.
        await _setState(job, UploadStates.uploading);
        return;
      }
      parts = [for (final p in rows) (partNumber: p.partNumber, etag: p.etag!)];
    }
    final status = await _api.completeUpload(memory.id, asset.id, uploadId: job.serverUploadId, parts: parts);
    if (status == 'verified' || status == 'ready') {
      await _markSynced(job, asset);
    } else if (status == 'failed') {
      throw const _Restart('checksum_mismatch', countsAsChecksumFailure: true);
    } else {
      await _setState(job, UploadStates.verifying);
    }
  }

  /// Waits for the server's asynchronous checksum verification. The client never marks an asset
  /// synced before the server says `verified` or `ready` (upload-sync.md invariant 1, SYNC-008).
  Future<void> _verify(UploadJobRow job) async {
    final asset = await (_db.select(_db.assets)..where((a) => a.id.equals(job.assetId))).getSingle();
    for (var poll = 0; poll < _config.maxVerifyPolls; poll++) {
      final server = await _api.memory(asset.memoryId);
      final remote = server.asset(asset.id);
      if (remote == null) {
        throw const _Restart('asset_missing_on_server');
      }
      if (remote.isServable) {
        await _markSynced(job, asset, serverStatus: remote.status);
        return;
      }
      if (remote.status == 'failed') {
        throw const _Restart('checksum_mismatch', countsAsChecksumFailure: true);
      }
      await _sleeper(_config.verifyPollInterval);
    }
    await _backoff(job, 'verification is taking long', 'verify_timeout', fixedDelay: const Duration(seconds: 10));
  }

  Future<void> _markSynced(UploadJobRow job, AssetRow asset, {String serverStatus = 'verified'}) async {
    await _db.transaction(() async {
      await (_db.update(_db.uploadJobs)..where((j) => j.assetId.equals(job.assetId))).write(
        UploadJobsCompanion(
          state: const Value(UploadStates.synced),
          lastError: const Value(null),
          lastErrorCode: const Value(null),
          updatedAt: Value(_now),
        ),
      );
      await (_db.update(_db.assets)..where((a) => a.id.equals(job.assetId))).write(
        AssetsCompanion(uploadState: const Value('synced'), serverStatus: Value(serverStatus)),
      );
    });
    _events.add(AssetSynced(asset.memoryId, asset.id));
    await checkpoint?.call('synced');
  }

  Future<void> dispose() => _events.close();
}
