import 'dart:convert';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:doro_cam/sync/sync_coordinator.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../data/support/fake_backend.dart';
import '../data/support/support.dart';

http.Response err(int status, String code) => http.Response(jsonEncode({'error': {'code': code, 'message': 'x'}}), status, headers: {'content-type': 'application/json'});

void main() {
  late Env env;
  setUp(() async => env = await Env.create(signedInAs: 'user-1'));
  tearDown(() => env.close());

  /// A registered, fully synced Memory.
  Future<MemoryView> syncedMemory() async {
    final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
    await env.engine.drain();
    return (await env.memories.view(view.memory.id))!;
  }

  group('OutboxPusher (metadata push)', () {
    test('[MEM-004][MEM-006] sends caption and favorite as patches with the server version, then clears the queue', () async {
      final m = await syncedMemory();
      await env.memories.setCaption(m.memory.id, 'Hello');
      await env.memories.setFavorite(m.memory.id, favorite: true);
      final result = await env.outbox.push();
      expect([result.sent, result.dropped, result.waiting], [2, 0, 0]);
      expect(env.backend.memories[m.memory.id]!['caption'], 'Hello');
      expect(env.backend.memories[m.memory.id]!['favorite'], true);
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
      expect((await env.memories.view(m.memory.id))!.memory.serverVersion, env.backend.memories[m.memory.id]!['version']);
    });

    test('[MEM-007] trash and restore reach the server in order', () async {
      final m = await syncedMemory();
      await env.memories.trash(m.memory.id);
      await env.memories.restore(m.memory.id);
      await env.outbox.push();
      expect(env.backend.memories[m.memory.id]!['deletedAt'], isNull);
      final trashCalls = env.backend.requests.where((r) => r.endsWith('/trash') || r.endsWith('/restore')).toList();
      expect(trashCalls.map((r) => r.split('/').last), ['trash', 'restore']);
    });

    test('[MEM-007] a permanent delete reaches the server (trash first when the server has not seen the trash)', () async {
      final m = await syncedMemory();
      await env.memories.purge(m.memory.id);
      await env.outbox.push();
      expect(env.backend.memories, isEmpty);
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });

    test('[SYNC-007] a version conflict is resolved by re-applying the edit on top of the newer server version', () async {
      final m = await syncedMemory();
      env.backend.memories[m.memory.id]!['version'] = 9; // another device edited meanwhile
      env.backend.memories[m.memory.id]!['caption'] = 'from another device';
      await env.memories.setFavorite(m.memory.id, favorite: true);
      final result = await env.outbox.push();
      expect(result.sent, 1);
      expect(env.backend.memories[m.memory.id]!['favorite'], true);
      expect(env.backend.memories[m.memory.id]!['caption'], 'from another device'); // their field is untouched (field-level LWW)
      expect((await env.memories.view(m.memory.id))!.memory.serverVersion, 10);
    });

    test('edits for a Memory the server does not know yet wait until the upload engine registers it', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      await env.memories.setCaption(view.memory.id, 'early');
      var result = await env.outbox.push();
      expect([result.sent, result.waiting], [0, 1]);
      await env.engine.drain();
      result = await env.outbox.push();
      expect(result.sent, 1);
      expect(env.backend.memories[view.memory.id]!['caption'], 'early');
    });

    test('later edits for an entity wait behind an earlier one that is waiting (order is kept)', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      await env.memories.setCaption(view.memory.id, 'one');
      await env.memories.setFavorite(view.memory.id, favorite: true);
      final result = await env.outbox.push();
      expect(result.waiting, 2);
    });

    test('[NFR-001] offline pushes leave everything queued and bump the attempt count', () async {
      final m = await syncedMemory();
      await env.memories.setFavorite(m.memory.id, favorite: true);
      env.backend.interceptor = (r, k) => throw FakeBackend.networkDown;
      final result = await env.outbox.push();
      expect([result.sent, result.waiting], [0, 1]);
      final queued = await env.db.select(env.db.outbox).get();
      expect(queued.single.attempts, 1);
    });

    test('a server error keeps the operation for later; 429 too', () async {
      final m = await syncedMemory();
      await env.memories.setFavorite(m.memory.id, favorite: true);
      for (final status in [500, 503, 429]) {
        env.backend.interceptor = (r, k) => k.startsWith('PATCH') ? err(status, 'x') : null;
        final result = await env.outbox.push();
        expect([result.sent, result.waiting], [0, 1], reason: '$status');
      }
      env.backend.interceptor = null;
      expect((await env.outbox.push()).sent, 1);
    });

    test('a permanent client error drops the operation so it cannot block the queue', () async {
      final m = await syncedMemory();
      await env.memories.setCaption(m.memory.id, 'a');
      await env.memories.setFavorite(m.memory.id, favorite: true);
      var first = true;
      env.backend.interceptor = (r, k) {
        if (k.startsWith('PATCH') && first) {
          first = false;
          return err(400, 'request.invalid');
        }
        return null;
      };
      final result = await env.outbox.push();
      expect([result.dropped, result.sent], [1, 1]);
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });

    test('[AUTH-004] a 401 stops the push and reports that sign-in is needed, keeping the queue', () async {
      final m = await syncedMemory();
      await env.memories.setFavorite(m.memory.id, favorite: true);
      env.backend.interceptor = (r, k) => err(401, 'auth.unauthenticated');
      final result = await env.outbox.push();
      expect(result.needsSignIn, isTrue);
      expect(await env.db.select(env.db.outbox).get(), hasLength(1));
    });

    test('edits for a Memory deleted on the server (404) are dropped', () async {
      final m = await syncedMemory();
      await env.memories.trash(m.memory.id);
      env.backend.memories.remove(m.memory.id);
      final result = await env.outbox.push();
      expect(result.dropped, 1);
    });

    test('an edit whose Memory was purged locally in the meantime is dropped (delete wins)', () async {
      final m = await syncedMemory();
      await env.memories.setFavorite(m.memory.id, favorite: true);
      await env.db.delete(env.db.memories).go();
      expect((await env.outbox.push()).dropped, 1);
    });

    test('nothing is sent while signed out', () async {
      await env.account.setAccount(null);
      expect((await env.outbox.push()).sent, 0);
    });

    test('[EXP-007] presets are upserted and deleted on the server, and marked clean', () async {
      final preset = await env.presets.save(name: 'Street', experienceId: 'mirrorless', intent: {'scenario': 'street'}, profileId: 'warm-film', live: true);
      expect((await env.outbox.push()).sent, 1);
      expect(env.backend.presets[preset.id]!['name'], 'Street');
      final row = (await env.presets.get(preset.id))!;
      expect([row.dirty, row.serverVersion], [false, 1]);

      await env.presets.delete(preset.id);
      expect((await env.outbox.push()).sent, 1);
      expect(env.backend.presets, isEmpty);
    });

    test('deleting a preset the server already lost is fine; an upsert for a deleted preset is dropped', () async {
      final preset = await env.presets.save(name: 'Gone', experienceId: 'x', intent: const {});
      await env.presets.delete(preset.id);
      final p2 = await env.presets.save(name: 'Other', experienceId: 'x', intent: const {});
      await env.db.into(env.db.outbox).insert(OutboxCompanion.insert(id: 'manual', accountId: 'user-1', entity: 'preset', entityId: p2.id, op: 'upsert', createdAt: 0));
      await env.presets.delete(p2.id);
      final result = await env.outbox.push();
      expect(result.sent + result.dropped, greaterThanOrEqualTo(2));
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });
  });

  group('PullSync (metadata pull)', () {
    test('[SYNC-006] a Memory captured on another device appears locally as a server-origin Memory', () async {
      env.backend.memories['remote-1'] = {
        'id': 'remote-1', 'kind': 'photo', 'capturedAt': '2026-10-01T10:00:00.000Z', 'capturedTz': 'UTC', 'experienceId': 'instant', 'capture': {'isoApplied': 100}, 'caption': 'From my other phone', 'version': 3, 'deletedAt': null, 'publicHandle': 'H' * 22,
      };
      env.backend.assets['ra'] = {'id': 'ra', 'memoryId': 'remote-1', 'role': 'photo_original', 'status': 'verified', 'mime': 'image/jpeg', 'bytes': 123, 'sha256': 'x'};
      env.backend.assets['pending'] = {'id': 'pending', 'memoryId': 'remote-1', 'role': 'thumbnail', 'status': 'uploading', 'mime': 'image/jpeg', 'bytes': 5, 'sha256': 'x'};
      env.backend.recordExternalChange('memory', 'remote-1', 'upsert');
      final result = await env.pull.pull();
      expect(result.memoriesUpdated, 1);
      final view = (await env.memories.view('remote-1'))!;
      expect([view.memory.caption, view.memory.capturedHere, view.memory.accountId, view.memory.serverVersion, view.status], ['From my other phone', false, 'user-1', 3, SyncStatus.synced]);
      expect(view.assets.map((a) => a.id), ['ra']); // only servable assets are mirrored
      expect(view.assets.single.localPath, isNull);
    });

    test('[SYNC-006] the cursor advances with the data and a second pull finds nothing new', () async {
      env.backend.memories['r1'] = {'id': 'r1', 'kind': 'photo', 'capturedAt': '2026-10-01T10:00:00.000Z', 'capturedTz': 'UTC', 'experienceId': 'x', 'capture': <String, Object?>{}, 'version': 1, 'deletedAt': null};
      env.backend.recordExternalChange('memory', 'r1', 'upsert');
      await env.pull.pull();
      expect(await env.pull.cursor('user-1'), 1);
      final again = await env.pull.pull();
      expect([again.memoriesUpdated, again.memoriesRemoved], [0, 0]);
    });

    test('[SYNC-006] pages through a long feed', () async {
      for (var i = 0; i < 250; i++) {
        env.backend.memories['r$i'] = {'id': 'r$i', 'kind': 'photo', 'capturedAt': '2026-10-01T10:00:00.000Z', 'capturedTz': 'UTC', 'experienceId': 'x', 'capture': <String, Object?>{}, 'version': 1, 'deletedAt': null};
        env.backend.recordExternalChange('memory', 'r$i', 'upsert');
      }
      expect((await env.pull.pull()).memoriesUpdated, 250);
      expect(env.backend.requests.where((r) => r == 'GET /v1/sync/changes').length, 3);
    });

    test('[MEM-007] a Memory trashed or restored elsewhere follows', () async {
      final m = await syncedMemory();
      env.backend.memories[m.memory.id]!['deletedAt'] = '2026-11-10T00:00:00.000Z';
      env.backend.memories[m.memory.id]!['version'] = 5;
      env.backend.recordExternalChange('memory', m.memory.id, 'delete');
      await env.pull.pull();
      var view = (await env.memories.view(m.memory.id))!;
      expect([view.isTrashed, view.memory.serverVersion], [true, 5]);
      env.backend.memories[m.memory.id]!['deletedAt'] = null;
      env.backend.recordExternalChange('memory', m.memory.id, 'upsert');
      await env.pull.pull();
      view = (await env.memories.view(m.memory.id))!;
      expect(view.isTrashed, isFalse);
    });

    test('a Memory purged elsewhere is removed here, with its pending edits (delete wins over edit)', () async {
      final m = await syncedMemory();
      await env.memories.setCaption(m.memory.id, 'pending');
      env.backend.memories.remove(m.memory.id);
      env.backend.recordExternalChange('memory', m.memory.id, 'delete');
      final result = await env.pull.pull();
      expect(result.memoriesRemoved, 1);
      expect(await env.memories.view(m.memory.id), isNull);
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });

    test('a change for a Memory this device never had and the server no longer has is ignored', () async {
      env.backend.recordExternalChange('memory', 'ghost', 'delete');
      final result = await env.pull.pull();
      expect(result.memoriesRemoved, 0);
    });

    test('[SYNC-007] fields with an unsent local edit are not overwritten by the pull; the version still advances', () async {
      final m = await syncedMemory();
      await env.memories.setCaption(m.memory.id, 'my offline edit');
      env.backend.memories[m.memory.id]!['caption'] = 'their edit';
      env.backend.memories[m.memory.id]!['favorite'] = true;
      env.backend.memories[m.memory.id]!['version'] = 7;
      env.backend.recordExternalChange('memory', m.memory.id, 'upsert');
      await env.pull.pull();
      final row = (await env.memories.view(m.memory.id))!.memory;
      expect([row.caption, row.serverVersion], ['my offline edit', 7]);
      // once pushed, ours is applied on top
      await env.outbox.push();
      expect(env.backend.memories[m.memory.id]!['caption'], 'my offline edit');
    });

    test('[SYNC-006] the server’s asset status is recorded on the local asset', () async {
      final m = await syncedMemory();
      env.backend.recordExternalChange('memory', m.memory.id, 'upsert');
      await env.pull.pull();
      expect((await env.memories.view(m.memory.id))!.assets.single.serverStatus, 'verified');
    });

    test('never touches another account’s Memory with the same id', () async {
      final m = await syncedMemory();
      await env.db.update(env.db.memories).write(const MemoriesCompanion(accountId: Value('someone-else')));
      env.backend.memories[m.memory.id]!['caption'] = 'server caption';
      env.backend.recordExternalChange('memory', m.memory.id, 'upsert');
      final result = await env.pull.pull();
      expect(result.memoriesUpdated, 0);
      expect((await env.memories.view(m.memory.id))!.memory.caption, isNull);
    });

    test('[EXP-007][SYNC-006] presets made elsewhere arrive, deleted ones leave, and unsent local presets survive', () async {
      env.backend.presets['remote-p'] = {'id': 'remote-p', 'name': 'Remote', 'experienceId': 'instant', 'intent': {'a': 1}, 'profile': {'id': 'x', 'version': 2}, 'live': true, 'source': 'user', 'version': 4};
      env.backend.recordExternalChange('preset', 'remote-p', 'upsert');
      final local = await env.presets.save(name: 'Local unsent', experienceId: 'x', intent: const {});
      await env.db.delete(env.db.outbox).go(); // keep it dirty but unsent
      await env.pull.pull();
      final presets = await env.presets.list();
      expect(presets.map((p) => p.name).toSet(), {'Remote', 'Local unsent'});
      final remote = presets.firstWhere((p) => p.id == 'remote-p');
      expect([remote.live, remote.profileId, remote.profileVersion, remote.serverVersion, remote.dirty], [true, 'x', 2, 4, false]);
      expect((await env.presets.get(local.id))!.dirty, isTrue);

      env.backend.presets.remove('remote-p');
      env.backend.recordExternalChange('preset', 'remote-p', 'delete');
      final result = await env.pull.pull();
      expect(result.presetsChanged, greaterThanOrEqualTo(1));
      expect((await env.presets.list()).map((p) => p.name), ['Local unsent']);
    });

    test('a 401 while pulling reports that sign-in is needed', () async {
      env.backend.interceptor = (r, k) => err(401, 'auth.unauthenticated');
      expect((await env.pull.pull()).needsSignIn, isTrue);
    });

    test('other server errors propagate so the caller can retry', () async {
      env.backend.interceptor = (r, k) => err(500, 'internal');
      await expectLater(env.pull.pull(), throwsA(isA<ApiException>()));
    });

    test('nothing is pulled while signed out', () async {
      await env.account.setAccount(null);
      final result = await env.pull.pull();
      expect(result.memoriesUpdated, 0);
      expect(env.backend.requests, isEmpty);
    });

    test('merging a Memory a second time is idempotent', () async {
      env.backend.memories['r1'] = {'id': 'r1', 'kind': 'photo', 'capturedAt': '2026-10-01T10:00:00.000Z', 'capturedTz': 'UTC', 'experienceId': 'x', 'capture': <String, Object?>{}, 'version': 1, 'deletedAt': null};
      env.backend.recordExternalChange('memory', 'r1', 'upsert');
      await env.pull.pull();
      await env.db.delete(env.db.syncState).go(); // pretend the cursor was lost
      await env.pull.pull();
      expect((await env.db.select(env.db.memories).get()).where((m) => m.id == 'r1'), hasLength(1));
    });
  });

  group('SyncCoordinator', () {
    test('[SYNC-002] one round pushes edits, uploads media and pulls changes, in that order', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      await env.memories.setCaption(view.memory.id, 'while offline');
      final report = await env.sync.syncOnce();
      expect(report.uploaded, 1);
      expect(report.push.sent, 1); // the edit was waiting for registration, then sent in the second push
      expect(env.backend.memories[view.memory.id]!['caption'], 'while offline');
      expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);
    });

    test('does nothing while signed out', () async {
      await env.account.setAccount(null);
      final report = await env.sync.syncOnce();
      expect([report.uploaded, report.push.sent], [0, 0]);
      expect(env.backend.requests, isEmpty);
    });

    test('concurrent rounds share one run', () async {
      await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      final reports = await Future.wait([env.sync.syncOnce(), env.sync.syncOnce()]);
      expect(reports.map((r) => r.uploaded), [1, 1]);
    });

    test('[SYNC-002] when connectivity returns, a started coordinator runs the queue by itself', () async {
      env.connectivity.kind = NetworkKind.none;
      final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      env.sync.start();
      env.sync.start(); // idempotent
      await pumpEventQueue(times: 50);
      expect(env.backend.requests.where((r) => r.startsWith('PUT /v1/memories')), isEmpty);
      env.connectivity.set(NetworkKind.wifi);
      for (var i = 0; i < 100 && (await env.memories.view(view.memory.id))!.status != SyncStatus.synced; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);
      await env.sync.stop();
    });

    test('[AUTH-005] signing in starts a round that uploads what was captured anonymously', () async {
      await env.account.setAccount(null);
      final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      env.sync.start();
      await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      for (var i = 0; i < 150 && (await env.memories.view(view.memory.id))!.status != SyncStatus.synced; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);
      await env.sync.stop();
    });

    test('schedules a background wake-up for the next backed-off job and cancels it when idle', () async {
      final scheduler = _RecordingScheduler();
      final coordinator = SyncCoordinator(uploads: env.engine, outbox: env.outbox, pull: env.pull, connectivity: env.connectivity, account: env.account, background: scheduler);
      await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      env.backend.interceptor = (r, k) => k.endsWith('/upload') ? err(503, 'x') : null;
      await coordinator.syncOnce();
      expect(scheduler.wakeUps, hasLength(1));
      expect(scheduler.cancels, 0);
      env.backend.interceptor = null;
      env.clock.advance(const Duration(hours: 1));
      await coordinator.syncOnce();
      expect(scheduler.cancels, 1);
      await coordinator.stop();
    });

    test('NoBackgroundScheduler does nothing', () async {
      const scheduler = NoBackgroundScheduler();
      await scheduler.scheduleWakeUp(DateTime.now());
      await scheduler.cancel();
    });
  });
}

class _RecordingScheduler implements BackgroundScheduler {
  final List<DateTime> wakeUps = [];
  int cancels = 0;

  @override
  Future<void> scheduleWakeUp(DateTime at) async => wakeUps.add(at);

  @override
  Future<void> cancel() async => cancels++;
}
