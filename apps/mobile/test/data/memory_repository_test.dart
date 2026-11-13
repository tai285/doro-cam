import 'dart:convert';
import 'dart:io';

import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/memory_repository.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'support/support.dart';

void main() {
  late Env env;
  setUp(() async => env = await Env.create());
  tearDown(() => env.close());

  Future<List<UploadJobRow>> jobs() => env.db.select(env.db.uploadJobs).get();
  Future<List<OutboxRow>> outbox() => env.db.select(env.db.outbox).get();

  group('capture → Memory (MEM-001, MEM-002, NFR-002)', () {
    test('[MEM-001] persists the Memory, its assets and files before returning', () async {
      final draft = photoDraft(env.scratch, caption: 'Golden hour', lat: 3.139, lon: 101.686);
      final view = await env.memories.commitCapture(draft);

      expect(view.memory.id, draft.id);
      expect(view.memory.kind, 'photo');
      expect(view.memory.caption, 'Golden hour');
      expect(view.memory.accountId, isNull);
      expect(view.assets.map((a) => a.role), [AssetRoles.thumbnail, AssetRoles.photoOriginal]); // upload priority order
      for (final asset in view.assets) {
        final file = File(asset.localPath!);
        expect(file.existsSync(), isTrue, reason: asset.role);
        expect(await file.length(), asset.bytes);
        expect(await sha256OfFile(file), asset.sha256);
      }
      // the files were moved into the media store, not left behind
      for (final source in draft.assets) {
        expect(File(source.path).existsSync(), isFalse);
      }
    });

    test('[MEM-002] records the applied settings, profile, experience and time zone', () async {
      final draft = photoDraft(env.scratch, capture: {'isoApplied': 400, 'exposureTimeNsApplied': 16000000, 'adjustments': [{'field': 'iso', 'requested': 100000, 'applied': 400, 'reason': 'clamped'}]});
      final row = (await env.memories.commitCapture(draft)).memory;
      expect(jsonDecode(row.captureJson), {'isoApplied': 400, 'exposureTimeNsApplied': 16000000, 'adjustments': [{'field': 'iso', 'requested': 100000, 'applied': 400, 'reason': 'clamped'}]});
      expect([row.profileId, row.profileVersion, row.experienceId, row.capturedTz, row.scenario], ['natural', 1, 'mirrorless', 'Asia/Kuala_Lumpur', 'street']);
      expect(DateTime.fromMillisecondsSinceEpoch(row.capturedAt, isUtc: true), DateTime.utc(2026, 11, 1, 9, 30));
    });

    test('[PRIV-001] a capture without location stores none', () async {
      final row = (await env.memories.commitCapture(photoDraft(env.scratch))).memory;
      expect([row.lat, row.lon, row.locationAccuracyM], [null, null, null]);
    });

    test('[MEM-001] committing the same capture twice returns the existing Memory and adds nothing', () async {
      final draft = photoDraft(env.scratch);
      await env.memories.commitCapture(draft);
      final again = await env.memories.commitCapture(draft);
      expect(again.memory.id, draft.id);
      expect((await env.db.select(env.db.memories).get()), hasLength(1));
      expect((await env.db.select(env.db.assets).get()), hasLength(2));
    });

    test('[MEM-001] a motion Memory keeps its clip next to the photo', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch, kind: MemoryKinds.motion));
      expect(view.assets.map((a) => a.role).toSet(), {AssetRoles.photoOriginal, AssetRoles.thumbnail, AssetRoles.motionClip});
      expect(view.asset(AssetRoles.motionClip)!.durationMs, 3000);
    });

    test('[NFR-002] if a file is missing nothing is committed and the files already moved are removed', () async {
      final draft = photoDraft(env.scratch);
      File(draft.assets.last.path).deleteSync(); // the thumbnail vanished mid-capture
      await expectLater(env.memories.commitCapture(draft), throwsA(isA<CaptureException>()));
      expect(await env.db.select(env.db.memories).get(), isEmpty);
      expect(await env.db.select(env.db.assets).get(), isEmpty);
      expect(env.media.directoryFor(draft.id).existsSync(), isFalse);
    });

    test('[NFR-002] an empty file is refused', () async {
      final draft = photoDraft(env.scratch);
      File(draft.assets.first.path).writeAsBytesSync([]);
      await expectLater(env.memories.commitCapture(draft), throwsA(isA<CaptureException>().having((e) => e.message, 'message', contains('empty'))));
      expect(await env.db.select(env.db.memories).get(), isEmpty);
    });

    test('[NFR-002] a database failure after the files moved removes them: either a complete Memory or none', () async {
      final draft = photoDraft(env.scratch);
      // Make the insert fail: a Memory with this id exists in a half state the unique key rejects.
      await env.db.into(env.db.memories).insert(MemoriesCompanion.insert(id: draft.id, kind: 'photo', capturedAt: 1, capturedTz: 'UTC', experienceId: 'x', captureJson: '{}', createdAt: 1, updatedAt: 1));
      await env.db.customStatement('ALTER TABLE assets RENAME TO assets_old'); // the asset insert then fails inside the transaction
      await expectLater(env.memories.commitCapture(photoDraft(env.scratch, id: IdGenerator().newId())), throwsA(anything));
      // nothing for the failed id remains on disk
      expect(env.media.root.listSync().whereType<Directory>().where((d) => d.path.endsWith(draft.id)), isEmpty);
    });

    test('recoverOrphans removes media directories no Memory owns (a crash between moving files and committing)', () async {
      final kept = await env.memories.commitCapture(photoDraft(env.scratch));
      final orphan = IdGenerator().newId();
      await env.media.adopt(env.scratch.file('lost.jpg'), File(env.media.pathFor(orphan, AssetRoles.photoOriginal, 'image/jpeg')));
      expect(await env.memories.recoverOrphans(), 0); // too fresh: it may still be committing
      env.clock.advance(const Duration(hours: 2));
      // the clock is virtual; age the directory on disk as well
      Process.runSync('touch', ['-d', DateTime.now().toUtc().subtract(const Duration(hours: 5)).toIso8601String(), env.media.directoryFor(orphan).path]);
      env.clock.now = DateTime.now().toUtc();
      expect(await env.memories.recoverOrphans(), 1);
      expect(env.media.directoryFor(orphan).existsSync(), isFalse);
      expect(env.media.directoryFor(kept.memory.id).existsSync(), isTrue);
    });

    group('invariants of docs/specs/memory-domain.md', () {
      Future<void> expectRejected(CaptureDraft draft, String fragment) =>
          expectLater(env.memories.commitCapture(draft), throwsA(isA<CaptureException>().having((e) => e.message, 'message', contains(fragment))));

      test('a capture needs at least one file', () async {
        final base = photoDraft(env.scratch);
        await expectRejected(CaptureDraft(id: base.id, kind: 'photo', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: const []), 'at least one file');
      });

      test('a photo needs exactly one photo_original', () async {
        final base = photoDraft(env.scratch, withThumbnail: false);
        final noOriginal = CaptureDraft(id: base.id, kind: 'photo', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: [DraftAsset(role: AssetRoles.thumbnail, path: env.scratch.file('t.jpg').path, mime: 'image/jpeg')]);
        await expectRejected(noOriginal, 'photo_original');
      });

      test('a motion Memory needs a motion_clip, and a plain photo cannot have one', () async {
        final base = photoDraft(env.scratch, withThumbnail: false);
        await expectRejected(CaptureDraft(id: base.id, kind: 'motion', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: base.assets), 'motion_clip');
        final withClip = photoDraft(env.scratch, withClip: true);
        await expectRejected(CaptureDraft(id: withClip.id, kind: 'photo', capturedAt: withClip.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: withClip.assets), 'Only a motion Memory');
      });

      test('a video needs a video_original', () async {
        final base = photoDraft(env.scratch);
        await expectRejected(CaptureDraft(id: base.id, kind: 'video', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: base.assets), 'video_original');
        final ok = CaptureDraft(id: IdGenerator().newId(), kind: 'video', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: [DraftAsset(role: AssetRoles.videoOriginal, path: env.scratch.file('v.mp4').path, mime: 'video/mp4', durationMs: 1000)]);
        expect((await env.memories.commitCapture(ok)).memory.kind, 'video');
      });

      test('an unknown kind is refused', () async {
        final base = photoDraft(env.scratch);
        await expectRejected(CaptureDraft(id: base.id, kind: 'hologram', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: base.assets), 'Unknown Memory kind');
      });

      test('each role appears once', () async {
        final base = photoDraft(env.scratch, withThumbnail: false);
        await expectRejected(CaptureDraft(id: base.id, kind: 'photo', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: [...base.assets, DraftAsset(role: AssetRoles.photoOriginal, path: env.scratch.file('dup.jpg').path, mime: 'image/jpeg')]), 'only once');
      });

      test('location is both coordinates or neither (invariant 7)', () async {
        await expectRejected(photoDraft(env.scratch, lat: 1), 'both latitude and longitude');
        await expectRejected(photoDraft(env.scratch, lon: 1), 'both latitude and longitude');
      });

      test('a caption is at most 2000 characters', () async {
        await expectRejected(photoDraft(env.scratch, caption: 'x' * 2001), '2000');
      });

      test('a missing file is a clear error naming the role', () async {
        final base = photoDraft(env.scratch);
        await expectRejected(
          CaptureDraft(id: base.id, kind: 'photo', capturedAt: base.capturedAt, capturedTz: 'UTC', experienceId: 'x', capture: const {}, assets: [DraftAsset(role: AssetRoles.photoOriginal, path: '/nope/missing.jpg', mime: 'image/jpeg')]),
          'photo_original',
        );
      });
    });

    test('[SYNC-001] while anonymous nothing is queued; when signed in every asset joins the upload queue', () async {
      await env.memories.commitCapture(photoDraft(env.scratch));
      expect(await jobs(), isEmpty);

      await env.account.setAccount('user-1');
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      expect(view.memory.accountId, 'user-1');
      final queued = await jobs();
      expect(queued, hasLength(2));
      expect(queued.every((j) => j.state == UploadStates.pending && j.accountId == 'user-1'), isTrue);
    });
  });

  group('library (LIB-001)', () {
    test('[LIB-001] lists Memories newest first, ties broken by id, offline', () async {
      final a = await env.memories.commitCapture(photoDraft(env.scratch, capturedAt: DateTime.utc(2026, 1, 1)));
      final b = await env.memories.commitCapture(photoDraft(env.scratch, capturedAt: DateTime.utc(2026, 3, 1)));
      final c = await env.memories.commitCapture(photoDraft(env.scratch, capturedAt: DateTime.utc(2026, 2, 1)));
      expect((await env.memories.library()).map((v) => v.memory.id), [b.memory.id, c.memory.id, a.memory.id]);

      final t1 = await env.memories.commitCapture(photoDraft(env.scratch, id: '00000000-0000-7000-8000-000000000001', capturedAt: DateTime.utc(2026, 6, 1)));
      final t2 = await env.memories.commitCapture(photoDraft(env.scratch, id: '00000000-0000-7000-8000-000000000002', capturedAt: DateTime.utc(2026, 6, 1)));
      expect((await env.memories.library()).take(2).map((v) => v.memory.id), [t2.memory.id, t1.memory.id]);
    });

    test('[LIB-003] filters by kind and favorites, and limits', () async {
      final photo = await env.memories.commitCapture(photoDraft(env.scratch));
      final motion = await env.memories.commitCapture(photoDraft(env.scratch, kind: MemoryKinds.motion, capturedAt: DateTime.utc(2026, 11, 2)));
      await env.memories.setFavorite(photo.memory.id, favorite: true);
      expect((await env.memories.library(kind: MemoryKinds.motion)).map((v) => v.memory.id), [motion.memory.id]);
      expect((await env.memories.library(favoritesOnly: true)).map((v) => v.memory.id), [photo.memory.id]);
      expect(await env.memories.library(limit: 1), hasLength(1));
    });

    test('the grid thumbnail prefers the thumbnail, then display, rendered and original', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      expect(view.thumbnail!.role, AssetRoles.thumbnail);
      final onlyOriginal = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      expect(onlyOriginal.thumbnail!.role, AssetRoles.photoOriginal);
    });

    test('[LIB-001] the library stream emits again when a Memory is added or edited', () async {
      final emissions = <List<String>>[];
      final subscription = env.memories.watchLibrary().listen((views) => emissions.add([for (final v in views) v.memory.caption ?? '-']));
      await pumpEventQueue();
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      await pumpEventQueue();
      await env.memories.setCaption(view.memory.id, 'Hello');
      await pumpEventQueue();
      await subscription.cancel();
      expect(emissions, [<String>[], ['-'], ['Hello']]);
    });

    test('watchMemory follows one Memory and reports null after it is deleted', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      final captions = <String?>[];
      final subscription = env.memories.watchMemory(view.memory.id).listen((v) => captions.add(v == null ? 'gone' : v.memory.caption));
      await pumpEventQueue();
      await env.memories.setCaption(view.memory.id, 'One');
      await pumpEventQueue();
      await env.memories.purge(view.memory.id);
      await pumpEventQueue();
      await subscription.cancel();
      expect(captions, [null, 'One', 'gone']);
    });

    test('view returns null for an unknown id', () async {
      expect(await env.memories.view('nope'), isNull);
    });
  });

  group('sync status (LIB-004)', () {
    test('local only while anonymous, uploading once queued, synced when every asset is synced, failed on a permanent failure', () async {
      final anonymous = await env.memories.commitCapture(photoDraft(env.scratch));
      expect(anonymous.status, SyncStatus.localOnly);

      await env.account.setAccount('user-1');
      final queued = await env.memories.commitCapture(photoDraft(env.scratch));
      expect(queued.status, SyncStatus.uploading);

      await env.db.update(env.db.memories).write(const MemoriesCompanion(registered: Value(true)));
      await env.db.update(env.db.uploadJobs).write(const UploadJobsCompanion(state: Value(UploadStates.synced)));
      expect((await env.memories.view(queued.memory.id))!.status, SyncStatus.synced);

      final oneBad = (await env.db.select(env.db.uploadJobs).get()).first;
      await (env.db.update(env.db.uploadJobs)..where((j) => j.assetId.equals(oneBad.assetId))).write(const UploadJobsCompanion(state: Value(UploadStates.failedPermanent)));
      expect((await env.memories.view(queued.memory.id))!.status, SyncStatus.failed);
    });

    test('a Memory that came from the server counts as synced', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      await env.db.update(env.db.memories).write(const MemoriesCompanion(capturedHere: Value(false)));
      expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);
    });
  });

  group('edits', () {
    test('[MEM-004] sets, trims and clears a caption', () async {
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.setCaption(id, '  Nice light  ');
      expect((await env.memories.view(id))!.memory.caption, 'Nice light');
      await env.memories.setCaption(id, '   ');
      expect((await env.memories.view(id))!.memory.caption, isNull);
      await expectLater(env.memories.setCaption(id, 'x' * 2001), throwsA(isA<CaptureException>()));
    });

    test('[MEM-006] toggles favorite', () async {
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.setFavorite(id, favorite: true);
      expect((await env.memories.view(id))!.memory.favorite, isTrue);
      await env.memories.setFavorite(id, favorite: false);
      expect((await env.memories.view(id))!.memory.favorite, isFalse);
    });

    test('[PRIV-001] removing the location clears all three fields and sharing', () async {
      final id = (await env.memories.commitCapture(photoDraft(env.scratch, lat: 3, lon: 101))).memory.id;
      await env.memories.setLocationShared(id, shared: true);
      await env.memories.removeLocation(id);
      final row = (await env.memories.view(id))!.memory;
      expect([row.lat, row.lon, row.locationAccuracyM, row.locationShared], [null, null, null, false]);
    });

    test('editing an unknown Memory is an error', () async {
      await expectLater(env.memories.setFavorite('nope', favorite: true), throwsStateError);
    });

    test('[SYNC-002] anonymous edits are not queued; signed-in edits are, in order, with their payload', () async {
      final anonymous = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.setCaption(anonymous, 'local');
      expect(await outbox(), isEmpty);

      await env.account.setAccount('user-1');
      final mine = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.setCaption(mine, 'one');
      await env.memories.setFavorite(mine, favorite: true);
      await env.memories.trash(mine);
      await env.memories.restore(mine);
      final ops = (await outbox()).where((o) => o.entityId == mine).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      expect(ops.map((o) => o.op), ['patch', 'patch', 'trash', 'restore']);
      expect(jsonDecode(ops[0].payloadJson), {'caption': 'one'});
      expect(jsonDecode(ops[1].payloadJson), {'favorite': true});
      expect(ops.every((o) => o.accountId == 'user-1'), isTrue);
    });

    test('a Memory owned by another account is edited locally but never queued for the signed-in one', () async {
      await env.account.setAccount('alice');
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.account.setAccount('bob');
      await env.memories.setCaption(id, 'bob edits alices photo');
      expect(await outbox(), isEmpty);
    });
  });

  group('trash (MEM-007)', () {
    test('[MEM-007] trash hides from the library and restore brings it back; both are idempotent', () async {
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.trash(id);
      await env.memories.trash(id);
      expect(await env.memories.library(), isEmpty);
      expect((await env.memories.library(trashed: true)).single.isTrashed, isTrue);
      await env.memories.restore(id);
      await env.memories.restore(id);
      expect((await env.memories.library()).single.isTrashed, isFalse);
    });

    test('[MEM-007] purge deletes rows, jobs and files, and removes the Memory’s pending edits', () async {
      await env.account.setAccount('user-1');
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.setCaption(id, 'pending edit');
      await env.memories.purge(id);
      expect(await env.db.select(env.db.memories).get(), isEmpty);
      expect(await env.db.select(env.db.assets).get(), isEmpty);
      expect(await jobs(), isEmpty);
      expect(env.media.directoryFor(id).existsSync(), isFalse);
      expect(await outbox(), isEmpty); // never registered, so the server has nothing to delete
    });

    test('[MEM-007] purging a registered Memory queues the delete for the server (delete wins over edit)', () async {
      await env.account.setAccount('user-1');
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await (env.db.update(env.db.memories)..where((m) => m.id.equals(id))).write(const MemoriesCompanion(registered: Value(true)));
      await env.memories.setCaption(id, 'pending edit');
      await env.memories.purge(id);
      final ops = await outbox();
      expect(ops.map((o) => [o.op, o.entityId]), [['purge', id]]);
    });

    test('[MEM-007] purgeExpired removes only Memories trashed more than 30 days ago', () async {
      final old = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      final recent = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.trash(old);
      env.clock.advance(const Duration(days: 20));
      await env.memories.trash(recent);
      env.clock.advance(const Duration(days: 11)); // old: 31 days, recent: 11 days
      expect(await env.memories.purgeExpired(), 1);
      expect((await env.memories.library(trashed: true)).map((v) => v.memory.id), [recent]);
      expect(env.media.directoryFor(old).existsSync(), isFalse);
      expect(env.media.directoryFor(recent).existsSync(), isTrue);
    });

    test('[MEM-007] exactly 30 days is not yet expired', () async {
      final id = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.trash(id);
      env.clock.advance(trashRetention);
      expect(await env.memories.purgeExpired(), 0);
      env.clock.advance(const Duration(milliseconds: 1));
      expect(await env.memories.purgeExpired(), 1);
    });

    test('[MEM-007] emptyTrash purges every trashed Memory and keeps the rest', () async {
      final a = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      final b = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      final keep = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.trash(a);
      await env.memories.trash(b);
      expect(await env.memories.emptyTrash(), 2);
      expect((await env.memories.library()).map((v) => v.memory.id), [keep]);
    });
  });

  group('claimAnonymous (AUTH-005)', () {
    test('[AUTH-005] captures made while anonymous become the account’s and join the upload queue; others are untouched', () async {
      final first = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      final trashed = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id;
      await env.memories.trash(trashed);
      await env.account.setAccount('alice');
      final alices = (await env.memories.commitCapture(photoDraft(env.scratch))).memory.id; // already alice's, jobs exist
      await env.account.setAccount('bob');

      final claimed = await env.memories.claimAnonymous('bob');
      expect(claimed, 2);
      expect((await env.memories.view(first))!.memory.accountId, 'bob');
      expect((await env.memories.view(alices))!.memory.accountId, 'alice'); // never crosses accounts
      final bobJobs = (await jobs()).where((j) => j.accountId == 'bob').toList();
      expect(bobJobs, hasLength(4)); // two assets each for the two claimed Memories
      expect((await outbox()).where((o) => o.op == 'trash' && o.entityId == trashed), hasLength(1));
    });

    test('claiming twice is harmless', () async {
      await env.memories.commitCapture(photoDraft(env.scratch));
      await env.memories.claimAnonymous('bob');
      expect(await env.memories.claimAnonymous('bob'), 0);
      expect(await jobs(), hasLength(2));
    });

    test('a server-origin Memory is never claimed', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      await env.db.update(env.db.memories).write(const MemoriesCompanion(capturedHere: Value(false)));
      expect(await env.memories.claimAnonymous('bob'), 0);
      expect((await env.memories.view(view.memory.id))!.memory.accountId, isNull);
    });
  });

  test('CaptureException describes itself', () {
    expect(const CaptureException('bad').toString(), 'CaptureException: bad');
  });

  test('deriveSyncStatus: an unregistered Memory with all jobs synced is still uploading', () async {
    await env.account.setAccount('user-1');
    final view = await env.memories.commitCapture(photoDraft(env.scratch));
    final jobsByAsset = {for (final j in await jobs()) j.assetId: j.copyWith(state: UploadStates.synced)};
    expect(deriveSyncStatus(view.memory, view.assets, jobsByAsset), SyncStatus.uploading);
  });
}
