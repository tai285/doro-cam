import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../data/support/fake_backend.dart';
import '../data/support/support.dart';

const mib = 1024 * 1024;

/// Thrown from the engine's checkpoint hook to simulate the app being killed.
class SimulatedKill implements Exception {}

void main() {
  late Env env;
  setUp(() async => env = await Env.create(signedInAs: 'user-1'));
  tearDown(() => env.close());

  Future<List<UploadJobRow>> jobs() => (env.db.select(env.db.uploadJobs)).get();
  Future<MemoryView> capture({int size = 4096, bool thumbnail = true, DateTime? at}) =>
      env.memories.commitCapture(photoDraft(env.scratch, originalSize: size, withThumbnail: thumbnail, capturedAt: at));

  List<UploadEvent> collectEvents() {
    final events = <UploadEvent>[];
    env.engine.events.listen(events.add);
    return events;
  }

  group('single upload', () {
    test('[SYNC-002][SYNC-008] registers, uploads, verifies and marks every asset synced; the server holds the exact bytes', () async {
      final view = await capture();
      final events = collectEvents();
      expect(await env.engine.drain(), 2);

      expect((await jobs()).map((j) => j.state), everyElement(UploadStates.synced));
      expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);
      expect((await env.memories.view(view.memory.id))!.memory.registered, isTrue);
      expect((await env.memories.view(view.memory.id))!.memory.serverVersion, isNotNull);
      for (final asset in view.assets) {
        expect(crypto.sha256.convert(env.backend.objects[asset.id]!).toString(), asset.sha256);
        expect(env.backend.assets[asset.id]!['status'], 'verified');
      }
      expect(events.whereType<AssetSynced>(), hasLength(2));
    });

    test('the Memory is registered before any bytes move, and thumbnails go up before originals', () async {
      final view = await capture();
      await env.engine.drain();
      final requests = env.backend.requests;
      final thumb = view.asset(AssetRoles.thumbnail)!.id;
      final original = view.asset(AssetRoles.photoOriginal)!.id;
      expect(requests.first, startsWith('PUT /v1/memories/'));
      final thumbPut = requests.indexOf('PUT /o/$thumb');
      final originalPut = requests.indexOf('PUT /o/$original');
      expect(thumbPut, greaterThan(0));
      expect(thumbPut, lessThan(originalPut));
    });

    test('a Memory is registered once however many assets it has', () async {
      await capture();
      await env.engine.drain();
      expect(env.backend.requests.where((r) => r.startsWith('PUT /v1/memories/')), hasLength(1));
    });

    test('the register body carries the Memory’s metadata, caption and favorite', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch, caption: 'Hello', lat: 3.1, lon: 101.6));
      await env.memories.setFavorite(view.memory.id, favorite: true);
      await env.engine.drain();
      final body = env.backend.bodies['PUT /v1/memories/${view.memory.id}']!.single! as Map<String, Object?>;
      expect([body['caption'], body['favorite'], body['kind'], body['experienceId']], ['Hello', true, 'photo', 'mirrorless']);
      expect(body['location'], {'lat': 3.1, 'lon': 101.6});
    });

    test('[SYNC-008] the client does not mark an asset synced until the server says verified (polls until then)', () async {
      env.backend.verifyAfterPolls = 3;
      await capture(thumbnail: false);
      expect(await env.engine.drain(), 1);
      expect(env.backend.requests.where((r) => r.startsWith('GET /v1/memories/')).length, greaterThanOrEqualTo(3));
      expect((await jobs()).single.state, UploadStates.synced);
    });

    test('[SYNC-008] verification that takes too long backs off and finishes on the next run', () async {
      env.backend.verifyAfterPolls = 100;
      await capture(thumbnail: false);
      expect(await env.engine.drain(), 0);
      var job = (await jobs()).single;
      expect([job.state, job.lastErrorCode, job.resumeState], [UploadStates.backoff, 'verify_timeout', UploadStates.verifying]);
      env.backend.verifyAfterPolls = 0;
      env.clock.advance(const Duration(minutes: 1));
      expect(await env.engine.drain(), 1);
      job = (await jobs()).single;
      expect(job.state, UploadStates.synced);
    });

    test('[SYNC-004] identical bytes already stored for the account are deduplicated: no bytes are sent', () async {
      final first = await capture(thumbnail: false);
      await env.engine.drain();
      final putsBefore = env.backend.requests.where((r) => r.startsWith('PUT /o/')).length;

      // a second Memory whose original has the very same bytes
      final draft = photoDraft(env.scratch, withThumbnail: false);
      File(draft.assets.single.path).writeAsBytesSync(File(first.asset(AssetRoles.photoOriginal)!.localPath!).readAsBytesSync());
      final second = await env.memories.commitCapture(draft);
      expect(second.asset(AssetRoles.photoOriginal)!.sha256, first.asset(AssetRoles.photoOriginal)!.sha256);

      expect(await env.engine.drain(), 1);
      expect(env.backend.requests.where((r) => r.startsWith('PUT /o/')).length, putsBefore);
      expect((await env.memories.view(second.memory.id))!.status, SyncStatus.synced);
    });

    test('an asset the server already verified (a retry after a lost response) is marked synced without re-uploading', () async {
      await capture(thumbnail: false);
      await env.engine.drain();
      // pretend the app lost the "synced" write: put the job back to pending
      await env.db.update(env.db.uploadJobs).write(const UploadJobsCompanion(state: Value(UploadStates.pending)));
      final puts = env.backend.requests.where((r) => r.startsWith('PUT /o/')).length;
      expect(await env.engine.drain(), 1);
      expect(env.backend.requests.where((r) => r.startsWith('PUT /o/')).length, puts);
      expect((await jobs()).single.state, UploadStates.synced);
    });

    test('concurrent drain calls share one run', () async {
      await capture();
      final results = await Future.wait([env.engine.drain(), env.engine.drain()]);
      expect(results, [2, 2]);
      expect(env.backend.requests.where((r) => r.startsWith('PUT /v1/memories/')), hasLength(1));
    });

    test('maxJobs limits how many assets one drain handles', () async {
      await capture();
      expect(await env.engine.drain(maxJobs: 1), 1);
      expect((await jobs()).where((j) => j.state == UploadStates.synced), hasLength(1));
      expect(await env.engine.drain(), 1);
    });
  });

  group('multipart upload', () {
    test('[SYNC-003][NFR-005] uploads a 20 MiB file in 8 MiB parts and the server reassembles identical bytes', () async {
      final draft = photoDraft(env.scratch, withThumbnail: false);
      final big = env.scratch.bigFile('big.jpg', 20 * mib);
      final replaced = [for (final a in draft.assets) a.role == AssetRoles.photoOriginal ? DraftAsset(role: a.role, path: big.path, mime: a.mime) : a];
      final view = await env.memories.commitCapture(CaptureDraft(id: draft.id, kind: draft.kind, capturedAt: draft.capturedAt, capturedTz: draft.capturedTz, experienceId: draft.experienceId, capture: draft.capture, assets: replaced));
      final asset = view.asset(AssetRoles.photoOriginal)!;
      final events = collectEvents();
      expect(await env.engine.drain(), 1);

      expect(env.backend.requests.where((r) => r.startsWith('PUT /o/')), hasLength(3));
      expect(crypto.sha256.convert(env.backend.objects[asset.id]!).toString(), asset.sha256);
      final parts = await env.db.select(env.db.uploadParts).get();
      expect(parts.map((p) => [p.partNumber, p.etag != null]), [[1, true], [2, true], [3, true]]);
      final job = (await jobs()).single;
      expect([job.state, job.partSize, job.partCount], [UploadStates.synced, 8 * mib, 3]);
      expect(events.whereType<AssetSynced>(), hasLength(1));
    });

    Future<MemoryView> bigCapture() async {
      final draft = photoDraft(env.scratch, withThumbnail: false);
      final big = env.scratch.bigFile('big.jpg', 20 * mib);
      return env.memories.commitCapture(CaptureDraft(id: draft.id, kind: draft.kind, capturedAt: draft.capturedAt, capturedTz: draft.capturedTz, experienceId: draft.experienceId, capture: draft.capture, assets: [DraftAsset(role: AssetRoles.photoOriginal, path: big.path, mime: 'image/jpeg')]));
    }

    test('[SYNC-003] after the app is killed mid-upload, a new engine resumes from the last stored part', () async {
      final view = await bigCapture();
      final asset = view.asset(AssetRoles.photoOriginal)!;
      final first = env.restartEngine(checkpoint: (point) {
        if (point == 'part:1') throw SimulatedKill();
      });
      await expectLater(first.drain(), throwsA(isA<SimulatedKill>()));
      expect(env.backend.requests.where((r) => r.startsWith('PUT /o/')), hasLength(1));
      expect((await env.db.select(env.db.uploadParts).get()).where((p) => p.etag != null), hasLength(1));

      final second = env.restartEngine();
      expect(await second.drain(), 1);
      // only the two missing parts were sent
      expect(env.backend.requests.where((r) => r.startsWith('PUT /o/')), hasLength(3));
      expect(crypto.sha256.convert(env.backend.objects[asset.id]!).toString(), asset.sha256);
      expect(env.backend.assets.length, 1); // exactly one asset, no duplicates (SYNC-004)
    });

    test('[SYNC-003] a part whose ETag was never stored is simply sent again', () async {
      final view = await bigCapture();
      final first = env.restartEngine(checkpoint: (point) {
        if (point == 'part:2') throw SimulatedKill();
      });
      await expectLater(first.drain(), throwsA(isA<SimulatedKill>()));
      // drop the stored ETag of part 2 as if the app died between the response and the write
      await (env.db.update(env.db.uploadParts)..where((p) => p.partNumber.equals(2))).write(const UploadPartsCompanion(etag: Value(null), state: Value('pending')));
      expect(await env.restartEngine().drain(), 1);
      expect(crypto.sha256.convert(env.backend.objects[view.asset(AssetRoles.photoOriginal)!.id]!).toString(), view.asset(AssetRoles.photoOriginal)!.sha256);
    });

    test('[SYNC-002] network drops between parts only delay the upload; it never restarts from zero', () async {
      final view = await bigCapture();
      var failuresLeft = 2;
      env.backend.interceptor = (request, key) {
        if (request.url.host == env.backend.storageHost && failuresLeft > 0 && request.url.queryParameters['part'] == '2') {
          failuresLeft--;
          throw FakeBackend.networkDown;
        }
        return null;
      };
      var rounds = 0;
      while ((await jobs()).single.state != UploadStates.synced && rounds < 6) {
        await env.engine.drain();
        env.clock.advance(const Duration(hours: 1)); // let the backoff elapse
        rounds++;
      }
      expect((await jobs()).single.state, UploadStates.synced);
      expect(rounds, 3);
      expect(crypto.sha256.convert(env.backend.objects[view.asset(AssetRoles.photoOriginal)!.id]!).toString(), view.asset(AssetRoles.photoOriginal)!.sha256);
      // part 1 was sent exactly once across all rounds
      expect(env.backend.requests.where((r) => r == 'PUT /o/${view.asset(AssetRoles.photoOriginal)!.id}').length, greaterThanOrEqualTo(3));
      expect((await env.db.select(env.db.uploadParts).get()).every((p) => p.etag != null), isTrue);
    });

    test('[SYNC-003] an expired presigned URL is replaced by a fresh one without counting as a failure (400 and 403)', () async {
      for (final status in [400, 403]) {
        final local = await Env.create(signedInAs: 'user-1');
        addTearDown(local.close);
        local.backend
          ..urlsValidForRequests = 0
          ..expiredStatus = status;
        var rejected = false;
        local.backend.urlsValidForRequests = null;
        local.backend.interceptor = (request, key) {
          // storage rejects only the first attempt; the refreshed URL is accepted
          if (request.url.host == local.backend.storageHost && !rejected) {
            rejected = true;
            return http.Response('<Error>Request has expired</Error>', status);
          }
          return null;
        };
        final draft = photoDraft(local.scratch, withThumbnail: false);
        final big = local.scratch.bigFile('big.jpg', 17 * mib);
        final view = await local.memories.commitCapture(CaptureDraft(id: draft.id, kind: draft.kind, capturedAt: draft.capturedAt, capturedTz: draft.capturedTz, experienceId: draft.experienceId, capture: draft.capture, assets: [DraftAsset(role: AssetRoles.photoOriginal, path: big.path, mime: 'image/jpeg')]));
        expect(await local.engine.drain(), 1, reason: 'status $status');
        final job = (await local.db.select(local.db.uploadJobs).get()).single;
        expect([job.state, job.attempts], [UploadStates.synced, 0], reason: 'status $status');
        expect(local.backend.requests.where((r) => r.endsWith('/upload')).length, greaterThanOrEqualTo(2));
        expect(view.memory.id, isNotEmpty);
      }
    });

    test('[SYNC-003] URLs that are about to expire are refreshed proactively before a part is sent', () async {
      await bigCapture();
      env.backend.interceptor = (request, key) => null;
      // make the engine see every plan as already expired
      final engine = env.restartEngine(config: const UploadEngineConfig(urlRefreshMargin: Duration(days: 365)));
      expect(await engine.drain(), 1);
      expect(env.backend.requests.where((r) => r.endsWith('/upload')).length, greaterThan(1));
    });

    test('a session that expired on the server (upload.not_found at completion) restarts the upload from step 2', () async {
      final view = await bigCapture();
      var dropped = false;
      env.backend.interceptor = (request, key) {
        if (key.endsWith('/upload/complete') && !dropped) {
          dropped = true;
          env.backend.forgetUploadSessions();
        }
        return null;
      };
      expect(await env.engine.drain(), 1);
      expect((await jobs()).single.state, UploadStates.synced);
      expect(env.backend.requests.where((r) => r.startsWith('PUT /o/')).length, 6); // all parts sent a second time
      expect(crypto.sha256.convert(env.backend.objects[view.asset(AssetRoles.photoOriginal)!.id]!).toString(), view.asset(AssetRoles.photoOriginal)!.sha256);
    });
  });

  group('failures and retries', () {
    test('[SYNC-002] a server error backs off (not due again until the delay passes) and later succeeds', () async {
      await capture(thumbnail: false);
      var fail = true;
      env.backend.interceptor = (request, key) => fail && key.endsWith('/upload') ? http.Response('{"error":{"code":"service.unavailable","message":"x"}}', 503) : null;
      expect(await env.engine.drain(), 0);
      var job = (await jobs()).single;
      expect([job.state, job.attempts, job.lastErrorCode], [UploadStates.backoff, 1, 'service.unavailable']);
      expect(job.nextAttemptAt, greaterThan(env.clock().millisecondsSinceEpoch));

      fail = false;
      expect(await env.engine.drain(), 0); // still waiting
      expect(env.backend.assets.values.where((a) => a['status'] == 'verified'), isEmpty);
      env.clock.advance(const Duration(minutes: 31)); // beyond the cap
      expect(await env.engine.drain(), 1);
      job = (await jobs()).single;
      expect([job.state, job.attempts], [UploadStates.synced, 1]);
    });

    test('[SYNC-002] backoff grows with attempts but never beyond 30 minutes', () async {
      await capture(thumbnail: false);
      env.backend.interceptor = (request, key) => key.endsWith('/upload') ? http.Response('{"error":{"code":"x","message":"x"}}', 500) : null;
      var maxDelay = Duration.zero;
      for (var i = 0; i < 15; i++) {
        await env.engine.drain();
        final job = (await jobs()).single;
        final delay = Duration(milliseconds: job.nextAttemptAt - env.clock().millisecondsSinceEpoch);
        if (delay > maxDelay) maxDelay = delay;
        env.clock.advance(const Duration(minutes: 31));
      }
      expect(maxDelay, lessThanOrEqualTo(const Duration(minutes: 30)));
      expect((await jobs()).single.attempts, 15);
    });

    test('[SYNC-002] a 429 waits for Retry-After', () async {
      await capture(thumbnail: false);
      env.backend.interceptor = (request, key) => key.endsWith('/upload') ? http.Response('{"error":{"code":"rate_limited","message":"x"}}', 429, headers: {'retry-after': '90'}) : null;
      await env.engine.drain();
      final job = (await jobs()).single;
      expect(Duration(milliseconds: job.nextAttemptAt - env.clock().millisecondsSinceEpoch), const Duration(seconds: 90));
    });

    test('network errors back off with the reason recorded and resume the state they were in', () async {
      await capture(thumbnail: false);
      env.backend.interceptor = (request, key) => request.url.host == env.backend.storageHost ? throw FakeBackend.networkDown : null;
      await env.engine.drain();
      final job = (await jobs()).single;
      expect([job.state, job.resumeState, job.lastErrorCode], [UploadStates.backoff, UploadStates.uploading, 'network']);
      env.backend.interceptor = null;
      env.clock.advance(const Duration(hours: 1));
      expect(await env.engine.drain(), 1);
    });

    test('storage answering 5xx is treated as a retryable failure', () async {
      await capture(thumbnail: false);
      env.backend.interceptor = (request, key) => request.url.host == env.backend.storageHost ? http.Response('busy', 503) : null;
      await env.engine.drain();
      expect((await jobs()).single.state, UploadStates.backoff);
    });

    test('[AUTH-004] a 401 pauses the queue, emits NeedsSignIn, and leaves the job to resume after sign-in', () async {
      await capture(thumbnail: false);
      final events = collectEvents();
      env.backend.signInToken = 'rotated';
      expect(await env.engine.drain(), 0);
      await pumpEventQueue();
      expect(events.whereType<NeedsSignIn>(), hasLength(1));
      expect((await jobs()).single.state, isNot(UploadStates.failedPermanent));
      // the session ended, so the device is signed out locally; signing in again resumes the same job
      expect(env.account.isSignedIn, isFalse);
      env.backend.signInToken = 'token-2';
      await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      expect(await env.engine.drain(), 1);
    });

    test('a full quota pauses the queue for an hour and tells the user (upload.quota_exceeded)', () async {
      await capture(thumbnail: false);
      env.backend.quotaBytes = 10;
      final events = collectEvents();
      expect(await env.engine.drain(), 0);
      await pumpEventQueue();
      expect(events.whereType<QuotaExceeded>(), hasLength(1));
      final job = (await jobs()).single;
      expect(job.state, UploadStates.backoff);
      expect(Duration(milliseconds: job.nextAttemptAt - env.clock().millisecondsSinceEpoch), const Duration(hours: 1));
      env.backend.quotaBytes = 1 << 40;
      env.clock.advance(const Duration(hours: 1, minutes: 1));
      expect(await env.engine.drain(), 1);
    });

    test('[SYNC-004] permanent client errors (too large, unsupported type, conflicts) fail the asset with the server code and can be retried by the user', () async {
      for (final entry in {'upload.too_large': 413, 'upload.unsupported_type': 415, 'asset.role_taken': 409, 'memory.conflict': 409}.entries) {
        final local = await Env.create(signedInAs: 'user-1');
        addTearDown(local.close);
        await local.memories.commitCapture(photoDraft(local.scratch, withThumbnail: false));
        var broken = true;
        local.backend.interceptor = (request, key) => broken && (key.endsWith('/upload') || key.startsWith('PUT /v1/memories/')) ? http.Response('{"error":{"code":"${entry.key}","message":"nope"}}', entry.value) : null;
        final events = <UploadEvent>[];
        local.engine.events.listen(events.add);
        expect(await local.engine.drain(), 1, reason: entry.key);
        final job = (await local.db.select(local.db.uploadJobs).get()).single;
        expect([job.state, job.lastErrorCode], [UploadStates.failedPermanent, entry.key]);
        expect((await local.db.select(local.db.assets).get()).single.uploadState, 'failed');
        await pumpEventQueue();
        expect(events.whereType<AssetFailed>().single.code, entry.key);
        // permanent failures are not retried by themselves
        expect(await local.engine.drain(), 0);
        // ... but the user can retry
        broken = false;
        await local.engine.retry(job.assetId);
        expect(await local.engine.drain(), 1);
        expect((await local.db.select(local.db.uploadJobs).get()).single.state, UploadStates.synced);
      }
    });

    test('[SYNC-008] a checksum mismatch found by the server restarts the upload; success follows', () async {
      await capture(thumbnail: false);
      env.backend.corruptNextVerification = true;
      expect(await env.engine.drain(), 0); // restarted, now waiting out a short backoff
      var job = (await jobs()).single;
      expect([job.checksumFailures, job.state], [1, UploadStates.backoff]);
      env.clock.advance(const Duration(hours: 1));
      expect(await env.engine.drain(), 1);
      job = (await jobs()).single;
      expect([job.state, job.checksumFailures], [UploadStates.synced, 1]);
    });

    test('[SYNC-008] the third checksum mismatch is a permanent failure and the asset is never marked synced', () async {
      await capture(thumbnail: false);
      for (var i = 0; i < 3; i++) {
        env.backend.corruptNextVerification = true;
        await env.engine.drain();
        env.clock.advance(const Duration(hours: 1));
      }
      final job = (await jobs()).single;
      expect([job.state, job.lastErrorCode, job.checksumFailures], [UploadStates.failedPermanent, 'checksum_mismatch', 3]);
      expect((await env.memories.library()).single.status, SyncStatus.failed);
    });

    test('[SYNC-008] a size mismatch at completion (422) restarts and counts toward the permanent limit', () async {
      await capture(thumbnail: false);
      env.backend.interceptor = (request, key) => key.endsWith('/upload/complete') ? http.Response('{"error":{"code":"upload.size_mismatch","message":"x"}}', 422) : null;
      for (var i = 0; i < 3; i++) {
        await env.engine.drain();
        env.clock.advance(const Duration(hours: 1));
      }
      expect((await jobs()).single.state, UploadStates.failedPermanent);
    });

    test('storage rejecting freshly signed URLs repeatedly is a permanent failure (storage_rejected)', () async {
      await capture(thumbnail: false);
      env.backend.expireAllUrls = true;
      expect(await env.engine.drain(), 1);
      final job = (await jobs()).single;
      expect([job.state, job.lastErrorCode], [UploadStates.failedPermanent, 'storage_rejected']);
    });

    test('a file deleted before upload is a permanent failure with a clear code', () async {
      final view = await capture(thumbnail: false);
      File(view.asset(AssetRoles.photoOriginal)!.localPath!).deleteSync();
      expect(await env.engine.drain(), 1);
      expect((await jobs()).single.lastErrorCode, 'local_file_missing');
    });

    test('a file whose size changed since capture is refused rather than uploaded corrupt', () async {
      final view = await capture(thumbnail: false);
      File(view.asset(AssetRoles.photoOriginal)!.localPath!).writeAsBytesSync([1, 2, 3]);
      await env.engine.drain();
      expect((await jobs()).single.lastErrorCode, 'local_file_changed');
    });

    test('an asset without a local file is a permanent failure', () async {
      final view = await capture(thumbnail: false);
      await (env.db.update(env.db.assets)..where((a) => a.id.equals(view.assets.single.id))).write(const AssetsCompanion(localPath: Value(null)));
      await env.engine.drain();
      expect((await jobs()).single.lastErrorCode, 'local_file_missing');
    });

    test('a vanished server asset restarts the upload, and too many restarts is permanent', () async {
      await capture(thumbnail: false);
      env.backend.interceptor = (request, key) => key.endsWith('/upload/complete') ? http.Response('{"error":{"code":"upload.not_found","message":"x"}}', 404) : null;
      var rounds = 0;
      while ((await jobs()).single.state != UploadStates.failedPermanent && rounds < 30) {
        await env.engine.drain();
        rounds++;
      }
      final job = (await jobs()).single;
      expect([job.state, job.lastErrorCode], [UploadStates.failedPermanent, 'too_many_restarts']);
    });
  });

  group('policy and partitioning', () {
    test('[SYNC-005] with Wi-Fi only (the default) nothing uploads on mobile data; switching it off allows it', () async {
      await capture(thumbnail: false);
      env.connectivity.kind = NetworkKind.cellular;
      expect(await env.engine.drain(), 0);
      expect(env.backend.requests, isEmpty);
      await env.settings.setWifiOnly(value: false);
      expect(await env.engine.drain(), 1);
    });

    test('nothing uploads while offline, and the queue resumes when connectivity returns', () async {
      await capture(thumbnail: false);
      env.connectivity.kind = NetworkKind.none;
      expect(await env.engine.drain(), 0);
      env.connectivity.kind = NetworkKind.wifi;
      expect(await env.engine.drain(), 1);
    });

    test('a low battery pauses uploads unless the phone is charging', () async {
      await capture(thumbnail: false);
      env.power
        ..percent = 5
        ..charging = false;
      expect(await env.engine.drain(), 0);
      env.power.charging = true;
      expect(await env.engine.drain(), 1);
    });

    test('[AUTH-005] while signed out nothing uploads', () async {
      await capture(thumbnail: false);
      await env.account.setAccount(null);
      expect(await env.engine.drain(), 0);
      expect(await env.engine.nextDueAt(), isNull);
    });

    test('[SYNC-001] uploads never cross accounts: another account’s jobs wait until that account signs in', () async {
      await capture(thumbnail: false); // user-1's
      await env.account.setAccount('user-2');
      expect(await env.engine.drain(), 0);
      expect(env.backend.requests, isEmpty);
      await env.account.setAccount('user-1');
      expect(await env.engine.drain(), 1);
    });

    test('Memories in the trash are not uploaded', () async {
      final view = await capture(thumbnail: false);
      await env.memories.trash(view.memory.id);
      expect(await env.engine.drain(), 0);
      await env.memories.restore(view.memory.id);
      expect(await env.engine.drain(), 1);
    });

    test('nextDueAt reports now for pending work, the retry time for backoff, and null when idle', () async {
      expect(await env.engine.nextDueAt(), isNull);
      await capture(thumbnail: false);
      expect((await env.engine.nextDueAt())!.millisecondsSinceEpoch, 0);
      env.backend.interceptor = (request, key) => key.endsWith('/upload') ? http.Response('{"error":{"code":"x","message":"x"}}', 500) : null;
      await env.engine.drain();
      expect((await env.engine.nextDueAt())!.millisecondsSinceEpoch, (await jobs()).single.nextAttemptAt);
      env.backend.interceptor = null;
      env.clock.advance(const Duration(hours: 1));
      await env.engine.drain();
      expect(await env.engine.nextDueAt(), isNull);
    });
  });

  group('kill at every step (SYNC-001, SYNC-004)', () {
    test('[SYNC-001][SYNC-004] killing the app at each persisted transition and restarting always converges to one verified asset', () async {
      // discover how many checkpoints a clean run has
      final probe = await Env.create(signedInAs: 'user-1');
      final points = <String>[];
      final probeEngine = probe.restartEngine(checkpoint: points.add);
      await probe.memories.commitCapture(photoDraft(probe.scratch, withThumbnail: false));
      await probeEngine.drain();
      await probe.close();
      expect(points.length, greaterThan(4));

      for (var killAt = 0; killAt < points.length; killAt++) {
        final local = await Env.create(signedInAs: 'user-1');
        addTearDown(local.close);
        final view = await local.memories.commitCapture(photoDraft(local.scratch, withThumbnail: false, seed: killAt + 3));
        var seen = 0;
        final killed = local.restartEngine(checkpoint: (point) {
          if (seen++ == killAt) throw SimulatedKill();
        });
        await expectLater(killed.drain(), throwsA(isA<SimulatedKill>()), reason: 'kill #$killAt (${points[killAt]})');
        // restart: a brand-new engine on the same database
        local.clock.advance(const Duration(hours: 1));
        await local.restartEngine().drain();
        local.clock.advance(const Duration(hours: 1));
        await local.restartEngine().drain();

        final asset = view.asset(AssetRoles.photoOriginal)!;
        expect(local.backend.assets.length, 1, reason: 'one asset after kill #$killAt (${points[killAt]})');
        expect(local.backend.assets[asset.id]!['status'], 'verified', reason: 'kill #$killAt (${points[killAt]})');
        expect(crypto.sha256.convert(local.backend.objects[asset.id]!).toString(), asset.sha256);
        expect((await local.db.select(local.db.uploadJobs).get()).single.state, UploadStates.synced);
        expect(local.backend.memories.length, 1);
      }
    });
  });

  test('retry resets counters, parts and errors so the asset starts clean', () async {
    final view = await capture(thumbnail: false);
    final assetId = view.assets.single.id;
    await env.db.into(env.db.uploadParts).insert(UploadPartsCompanion.insert(assetId: assetId, partNumber: 1, etag: const Value('"x"')));
    await (env.db.update(env.db.uploadJobs)..where((j) => j.assetId.equals(assetId))).write(const UploadJobsCompanion(state: Value(UploadStates.failedPermanent), attempts: Value(9), checksumFailures: Value(3), lastError: Value('bad'), serverUploadId: Value('up')));
    await env.engine.retry(assetId);
    final job = (await jobs()).single;
    expect([job.state, job.attempts, job.checksumFailures, job.lastError, job.serverUploadId, job.nextAttemptAt], [UploadStates.pending, 0, 0, null, null, 0]);
    expect(await env.db.select(env.db.uploadParts).get(), isEmpty);
  });

  test('upload priority orders thumbnail, display, rendered, original, clip, video', () {
    expect(AssetRoles.uploadPriority.map(AssetRoles.priority), [0, 1, 2, 3, 4, 5]);
    expect(AssetRoles.priority('something_else'), 6);
  });
}
