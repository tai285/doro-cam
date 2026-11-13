import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../data/support/api_harness.dart';
import '../data/support/support.dart';

const mib = 1024 * 1024;

class SimulatedKill implements Exception {}

/// Integration tests: the mobile data layer against the REAL services/api, Postgres and Garage S3
/// (docs/specs/upload-sync.md acceptance criteria). Needs `pnpm infra:up` (Docker in WSL).
void main() {
  late ApiHarness api;
  late http.Client plain;

  setUpAll(() async {
    api = await ApiHarness.start();
    plain = http.Client();
  });
  tearDownAll(() async {
    plain.close();
    await api.stop();
  });

  Future<Env> signedInDevice({http.Client? client, FutureOr<void> Function(String)? checkpoint, ({String email, String password})? credentials, UploadEngineConfig config = const UploadEngineConfig()}) async {
    final user = credentials ?? await api.createUser();
    final env = await Env.create(httpClient: client ?? plain, baseUrl: api.baseUrl, checkpoint: checkpoint, config: config);
    await env.auth.signIn(email: user.email, password: user.password);
    return env;
  }

  Future<String> sha256Of(http.Client client, Uri url) async {
    final response = await client.send(http.Request('GET', url));
    final digest = await crypto.sha256.bind(response.stream).first;
    return digest.toString();
  }

  test('[AUTH-001] sign-in through the real API returns a working device session', () async {
    final user = await api.createUser();
    final env = await Env.create(httpClient: plain, baseUrl: api.baseUrl);
    addTearDown(env.close);
    final account = await env.auth.signIn(email: user.email, password: user.password);
    expect(account.email, user.email);
    expect(account.emailVerified, isTrue);
    expect(env.account.accountId, account.id);
    expect((await env.auth.sessions()).any((s) => s.current), isTrue);
    await expectLater(env.auth.signIn(email: user.email, password: 'not-the-password'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
  });

  test('[AUTH-004] revoking this device’s session on the server stops uploads and asks the user to sign in', () async {
    final env = await signedInDevice();
    addTearDown(env.close);
    final events = <UploadEvent>[];
    env.engine.events.listen(events.add);
    await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
    final current = (await env.auth.sessions()).firstWhere((s) => s.current);
    await env.auth.revokeSession(current.id);
    expect(await env.engine.drain(), 0);
    await pumpEventQueue();
    expect(events.whereType<NeedsSignIn>(), hasLength(1));
    expect(env.account.isSignedIn, isFalse);
  });

  test('[MEM-001][SYNC-002][SYNC-008][NFR-005] capture → upload → the server serves back bit-exact files, and the library shows synced', () async {
    final env = await signedInDevice();
    addTearDown(env.close);
    final view = await env.memories.commitCapture(photoDraft(env.scratch, kind: MemoryKinds.motion, originalSize: 3 * mib, caption: 'Real server'));
    expect(view.status, SyncStatus.uploading);
    expect(await env.engine.drain(), 3);
    expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);

    final remote = await env.api.memory(view.memory.id);
    expect([remote.caption, remote.kind, remote.version], ['Real server', 'motion', greaterThanOrEqualTo(1)]);
    expect(remote.assets.map((a) => a.status).toSet(), {'verified'});
    expect(remote.assets.map((a) => a.role).toSet(), {AssetRoles.photoOriginal, AssetRoles.thumbnail, AssetRoles.motionClip});
    for (final asset in view.assets) {
      final link = await _downloadLink(env, view.memory.id, asset.id);
      expect(await sha256Of(plain, link), asset.sha256, reason: asset.role);
    }
    final account = await env.api.me();
    expect(account.usedBytes, view.assets.fold<int>(0, (sum, a) => sum + a.bytes));
  });

  test('[SYNC-004] retrying after everything succeeded changes nothing: no duplicates on the server', () async {
    final env = await signedInDevice();
    addTearDown(env.close);
    final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
    await env.engine.drain();
    await env.db.update(env.db.uploadJobs).write(const UploadJobsCompanion(state: Value(UploadStates.pending)));
    await env.db.update(env.db.memories).write(const MemoriesCompanion(registered: Value(false)));
    expect(await env.engine.drain(), 1);
    final page = await env.api.listMemories();
    expect(page.items.where((m) => m.id == view.memory.id), hasLength(1));
    expect((await env.api.memory(view.memory.id)).assets, hasLength(1));
  });

  test('[SYNC-004] the same bytes uploaded for two Memories are stored once and counted once', () async {
    final env = await signedInDevice();
    addTearDown(env.close);
    final first = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false, originalSize: 200000));
    await env.engine.drain();
    final draft = photoDraft(env.scratch, withThumbnail: false);
    File(draft.assets.single.path).writeAsBytesSync(File(first.asset(AssetRoles.photoOriginal)!.localPath!).readAsBytesSync());
    final second = await env.memories.commitCapture(draft);
    await env.engine.drain();
    expect((await env.memories.view(second.memory.id))!.status, SyncStatus.synced);
    expect((await env.api.me()).usedBytes, 200000);
  });

  test('[SYNC-008] a checksum the server cannot verify ends as a permanent failure, with nothing left stored', () async {
    final env = await signedInDevice();
    addTearDown(env.close);
    final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
    final asset = view.asset(AssetRoles.photoOriginal)!;
    await (env.db.update(env.db.assets)..where((a) => a.id.equals(asset.id))).write(AssetsCompanion(sha256: Value('0' * 64)));
    for (var i = 0; i < 3; i++) {
      await env.engine.drain();
      env.clock.advance(const Duration(hours: 1));
    }
    final job = (await env.db.select(env.db.uploadJobs).get()).single;
    expect([job.state, job.lastErrorCode], [UploadStates.failedPermanent, 'checksum_mismatch']);
    expect((await env.memories.view(view.memory.id))!.status, SyncStatus.failed);
    expect((await env.api.me()).usedBytes, 0);
  });

  test('[SYNC-005] a quota-limited account pauses the queue and tells the user', () async {
    final small = await ApiHarness.start(quotaBytes: 5000);
    addTearDown(small.stop);
    final user = await small.createUser();
    final env = await Env.create(httpClient: plain, baseUrl: small.baseUrl);
    addTearDown(env.close);
    await env.auth.signIn(email: user.email, password: user.password);
    final events = <UploadEvent>[];
    env.engine.events.listen(events.add);
    await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false, originalSize: 20000));
    expect(await env.engine.drain(), 0);
    await pumpEventQueue();
    expect(events.whereType<QuotaExceeded>(), hasLength(1));
    expect((await env.db.select(env.db.uploadJobs).get()).single.state, UploadStates.backoff);
  });

  test('[SYNC-003][SYNC-004][SYNC-008] 200 MB through 6 network drops and 2 app kills ends with one verified asset, a matching SHA-256 and no orphans', () async {
    final faulty = FaultyClient(plain)
      ..dropBefore.addAll({3, 9, 14, 20})
      ..dropAfter.addAll({6, 17});
    final kills = <String>{'part:9', 'part:23'};
    final user = await api.createUser();
    final env = await signedInDevice(
      client: faulty,
      credentials: user,
      checkpoint: (point) {
        if (kills.remove(point)) throw SimulatedKill();
      },
    );
    addTearDown(env.close);

    final draft = photoDraft(env.scratch, withThumbnail: false);
    final big = env.scratch.bigFile('video.jpg', 200 * mib, seed: 42);
    final view = await env.memories.commitCapture(CaptureDraft(
      id: draft.id,
      kind: MemoryKinds.photo,
      capturedAt: draft.capturedAt,
      capturedTz: draft.capturedTz,
      experienceId: draft.experienceId,
      capture: draft.capture,
      assets: [DraftAsset(role: AssetRoles.photoOriginal, path: big.path, mime: 'image/jpeg')],
    ));
    // the API caps a photo_original at 200 MiB, which is exactly this file
    final asset = view.asset(AssetRoles.photoOriginal)!;
    expect(asset.bytes, 200 * mib);

    var engine = env.engine;
    var kills2 = 0;
    for (var round = 0; round < 40; round++) {
      try {
        await engine.drain();
      } on SimulatedKill {
        kills2++;
        // the app was killed: a brand-new engine continues from the database
        engine = env.restartEngine(
          httpClient: faulty,
          checkpoint: (point) {
            if (kills.remove(point)) throw SimulatedKill();
          },
        );
      }
      final job = (await env.db.select(env.db.uploadJobs).get()).single;
      if (job.state == UploadStates.synced) {
        break;
      }
      env.clock.advance(const Duration(hours: 1)); // let any backoff elapse
    }

    final job = (await env.db.select(env.db.uploadJobs).get()).single;
    expect(job.state, UploadStates.synced, reason: job.lastError);
    expect(kills2, 2);
    expect(faulty.dropped, 6);

    // one memory, one asset, verified by the server
    final page = await env.api.listMemories();
    expect(page.items.where((m) => m.id == view.memory.id), hasLength(1));
    final remote = await env.api.memory(view.memory.id);
    expect(remote.assets, hasLength(1));
    expect(remote.assets.single.status, 'verified');
    expect(remote.assets.single.bytes, 200 * mib);

    // the stored object has exactly the SHA-256 the device computed at capture
    final link = await _downloadLink(env, view.memory.id, asset.id);
    expect(await sha256Of(plain, link), asset.sha256);

    // no orphan bytes: the account is charged for exactly one 200 MiB object
    expect((await env.api.me()).usedBytes, 200 * mib);
  }, timeout: const Timeout(Duration(minutes: 10)));

  group('metadata sync across two devices (same account)', () {
    test('[SYNC-006][MEM-004][MEM-006][MEM-007] edits, trash and delete on device A reach device B through the change feed', () async {
      final user = await api.createUser();
      final a = await signedInDevice(credentials: user);
      final b = await signedInDevice(credentials: user);
      addTearDown(a.close);
      addTearDown(b.close);

      final view = await a.memories.commitCapture(photoDraft(a.scratch, withThumbnail: false));
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      var onB = (await b.memories.view(view.memory.id))!;
      expect([onB.memory.capturedHere, onB.status, onB.assets.single.role], [false, SyncStatus.synced, AssetRoles.photoOriginal]);

      await a.memories.setCaption(view.memory.id, 'Edited on A');
      await a.memories.setFavorite(view.memory.id, favorite: true);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      onB = (await b.memories.view(view.memory.id))!;
      expect([onB.memory.caption, onB.memory.favorite], ['Edited on A', true]);

      await a.memories.trash(view.memory.id);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      expect((await b.memories.view(view.memory.id))!.isTrashed, isTrue);

      await a.memories.restore(view.memory.id);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      expect((await b.memories.view(view.memory.id))!.isTrashed, isFalse);

      await a.memories.trash(view.memory.id);
      await a.memories.purge(view.memory.id);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      expect(await b.memories.view(view.memory.id), isNull);
      await expectLater(a.api.memory(view.memory.id), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
    });

    test('[SYNC-007] two devices editing different fields while offline both survive; the same field takes the last write', () async {
      final user = await api.createUser();
      final a = await signedInDevice(credentials: user);
      final b = await signedInDevice(credentials: user);
      addTearDown(a.close);
      addTearDown(b.close);
      final view = await a.memories.commitCapture(photoDraft(a.scratch, withThumbnail: false));
      await a.sync.syncOnce();
      await b.sync.syncOnce();

      await a.memories.setCaption(view.memory.id, 'caption from A');
      await b.memories.setFavorite(view.memory.id, favorite: true);
      await b.memories.setCaption(view.memory.id, 'caption from B');
      await a.sync.syncOnce(); // A reaches the server first
      await b.sync.syncOnce(); // B's edits arrive later, on top
      await a.sync.syncOnce();

      final remote = await a.api.memory(view.memory.id);
      expect([remote.favorite, remote.caption], [true, 'caption from B']);
      expect((await a.memories.view(view.memory.id))!.memory.favorite, isTrue);
    });

    test('[EXP-007][SYNC-006] presets created on A appear on B, and deleting them removes them there', () async {
      final user = await api.createUser();
      final a = await signedInDevice(credentials: user);
      final b = await signedInDevice(credentials: user);
      addTearDown(a.close);
      addTearDown(b.close);
      final preset = await a.presets.save(name: 'Street 35', experienceId: 'mirrorless', intent: {'scenario': 'street'}, profileId: 'warm-film', live: true);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      final onB = (await b.presets.list()).single;
      expect([onB.id, onB.name, onB.live, jsonDecode(onB.intentJson)], [preset.id, 'Street 35', true, {'scenario': 'street'}]);

      await a.presets.delete(preset.id);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      expect(await b.presets.list(), isEmpty);
    });

    test('[AUTH-005] captures made before signing in upload after sign-in, and another account never receives them', () async {
      final alice = await api.createUser();
      final bob = await api.createUser();
      final env = await Env.create(httpClient: plain, baseUrl: api.baseUrl);
      addTearDown(env.close);
      final view = await env.memories.commitCapture(photoDraft(env.scratch, withThumbnail: false));
      expect(view.status, SyncStatus.localOnly);
      await env.auth.signIn(email: alice.email, password: alice.password);
      await env.sync.syncOnce();
      expect((await env.memories.view(view.memory.id))!.status, SyncStatus.synced);

      await env.auth.signOut();
      await env.auth.signIn(email: bob.email, password: bob.password);
      await env.sync.syncOnce();
      expect((await env.api.listMemories()).items, isEmpty); // Bob sees nothing of Alice's
      expect((await env.memories.view(view.memory.id))!.memory.accountId, isNot(env.account.accountId));
    });
  });
}

Future<Uri> _downloadLink(Env env, String memoryId, String assetId) async {
  final token = await env.tokens.read();
  final response = await http.get(
    env.api.baseUrl.replace(path: '/v1/memories/$memoryId/assets/$assetId/download'),
    headers: {'authorization': 'Bearer $token'},
  );
  expect(response.statusCode, 200, reason: response.body);
  return Uri.parse((jsonDecode(response.body) as Map<String, Object?>)['url']! as String);
}
