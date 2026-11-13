import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/api_models.dart';
import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../data/support/fake_backend.dart';
import '../data/support/support.dart';

DoroApiClient clientFor(http.Client client, {String? token = 'tok'}) =>
    DoroApiClient(baseUrl: Uri.parse('https://api.test'), httpClient: client, token: () async => token);

http.Response json(Object? body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

Map<String, Object?> memoryJson({String id = 'm1', int version = 1}) => {
  'id': id,
  'ownerId': 'u1',
  'isOwner': true,
  'kind': 'photo',
  'capturedAt': '2026-11-01T09:30:00.000Z',
  'capturedTz': 'Asia/Kuala_Lumpur',
  'experienceId': 'mirrorless',
  'profile': {'id': 'natural', 'version': 2},
  'presetId': null,
  'scenario': 'street',
  'capture': {'isoApplied': 200},
  'location': {'lat': 3.1, 'lon': 101.6, 'accuracyM': 5},
  'locationShared': true,
  'caption': 'Hi',
  'favorite': true,
  'aspectRatio': '3:2',
  'publicHandle': 'H' * 22,
  'version': version,
  'createdAt': '2026-11-01T09:31:00.000Z',
  'updatedAt': '2026-11-01T09:31:00.000Z',
  'deletedAt': null,
  'assets': [
    {'id': 'a1', 'role': 'photo_original', 'status': 'verified', 'mime': 'image/jpeg', 'bytes': 10, 'width': 4, 'height': 3, 'durationMs': null, 'failureReason': null},
  ],
};

void main() {
  group('requests', () {
    test('[AUTH-004] sends the bearer token on authenticated calls and none on sign-in', () async {
      final seen = <http.BaseRequest>[];
      final client = clientFor(MockClient((request) async {
        seen.add(request);
        return request.url.path == '/v1/auth/sign-in/email' ? json({'ok': true}, 200, {'set-auth-token': 'new-token'}) : json({'items': <Object?>[]});
      }));
      expect(await client.signIn(email: 'a@b.test', password: 'secret-password'), 'new-token');
      await client.sessions();
      expect(seen[0].headers['authorization'], isNull);
      expect(seen[1].headers['authorization'], 'Bearer tok');
    });

    test('sign-in without a token header is an error, not a silent success', () async {
      final client = clientFor(MockClient((_) async => json({'ok': true})));
      await expectLater(client.signIn(email: 'a@b.test', password: 'x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'auth.no_token')));
    });

    test('a request with no stored token is sent without credentials', () async {
      String? header = 'unset';
      final client = clientFor(MockClient((request) async {
        header = request.headers['authorization'];
        return json({'items': <Object?>[]});
      }), token: null);
      await client.presets();
      expect(header, isNull);
    });

    test('[SYNC-004] registerMemory PUTs to the Memory id with an Idempotency-Key and reports created vs existing', () async {
      final seen = <http.Request>[];
      var status = 201;
      final client = clientFor(MockClient((request) async {
        seen.add(request);
        return json(memoryJson(), status);
      }));
      final register = RegisterMemory(kind: 'photo', capturedAt: DateTime.utc(2026, 11, 1, 9, 30), capturedTz: 'Asia/Kuala_Lumpur', experienceId: 'mirrorless', capture: const {'isoApplied': 200}, profileId: 'natural', lat: 3.1, lon: 101.6, caption: 'Hi');
      expect((await client.registerMemory('m1', register)).created, isTrue);
      status = 200;
      expect((await client.registerMemory('m1', register)).created, isFalse);
      expect(seen.first.method, 'PUT');
      expect(seen.first.url.path, '/v1/memories/m1');
      expect(seen.first.headers['Idempotency-Key'], 'm1:register');
      final body = jsonDecode(seen.first.body) as Map<String, Object?>;
      expect(body, {
        'kind': 'photo',
        'capturedAt': '2026-11-01T09:30:00.000Z',
        'capturedTz': 'Asia/Kuala_Lumpur',
        'experienceId': 'mirrorless',
        'profile': {'id': 'natural', 'version': 1},
        'capture': {'isoApplied': 200},
        'location': {'lat': 3.1, 'lon': 101.6},
        'caption': 'Hi',
        'favorite': false,
      });
    });

    test('RegisterMemory omits location unless both coordinates exist, and includes optional fields when set', () {
      final minimal = RegisterMemory(kind: 'photo', capturedAt: DateTime.utc(2026), capturedTz: 'UTC', experienceId: 'x', capture: const {}, lat: 1).toJson();
      expect(minimal.containsKey('location'), isFalse);
      final full = RegisterMemory(kind: 'motion', capturedAt: DateTime.utc(2026), capturedTz: 'UTC', experienceId: 'x', capture: const {}, presetId: 'p', scenario: 's', lat: 1, lon: 2, locationAccuracyM: 3, aspectRatio: '3:2', favorite: true, profileId: 'n', profileVersion: 4).toJson();
      expect(full['presetId'], 'p');
      expect(full['location'], {'lat': 1.0, 'lon': 2.0, 'accuracyM': 3.0});
      expect(full['profile'], {'id': 'n', 'version': 4});
      expect(full['aspectRatio'], '3:2');
    });

    test('patch sends If-Match, trash/restore/purge hit the documented endpoints', () async {
      final seen = <String>[];
      final client = clientFor(MockClient((request) async {
        seen.add('${request.method} ${request.url.path} ${request.headers['If-Match'] ?? ''}'.trim());
        return request.method == 'DELETE' ? json({'status': 'purging'}, 202) : json(memoryJson(version: 3));
      }));
      expect((await client.patchMemory('m1', {'favorite': true}, ifMatch: 2)).version, 3);
      await client.patchMemory('m1', {'caption': null});
      await client.trashMemory('m1');
      await client.restoreMemory('m1');
      await client.purgeMemory('m1');
      expect(seen, ['PATCH /v1/memories/m1 2', 'PATCH /v1/memories/m1', 'POST /v1/memories/m1/trash', 'POST /v1/memories/m1/restore', 'DELETE /v1/memories/m1']);
    });

    test('lists memories with cursor and trash filter', () async {
      Uri? last;
      final client = clientFor(MockClient((request) async {
        last = request.url;
        return json({'items': [memoryJson()], 'nextCursor': 'abc'});
      }));
      final page = await client.listMemories(cursor: 'c1', limit: 10, trashed: true);
      expect(page.items.single.id, 'm1');
      expect(page.nextCursor, 'abc');
      expect(last!.queryParameters, {'limit': '10', 'cursor': 'c1', 'trashed': 'true'});
      await client.listMemories();
      expect(last!.queryParameters, {'limit': '50'});
    });

    test('account endpoints', () async {
      final seen = <String>[];
      final client = clientFor(MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        return switch (request.url.path) {
          '/v1/me' => json({'id': 'u1', 'email': 'a@b.test', 'name': 'A', 'emailVerified': true, 'storage': {'usedBytes': 5, 'quotaBytes': 10}, 'deletionScheduledFor': '2026-12-01T00:00:00.000Z'}),
          '/v1/me/sessions' => json({'items': [{'id': 's1', 'current': true, 'userAgent': 'UA', 'createdAt': '2026-11-01T00:00:00.000Z'}]}),
          '/v1/me/deletion' => request.method == 'POST' ? json({'scheduledFor': '2026-12-01T00:00:00.000Z'}) : http.Response('', 204),
          _ => http.Response('', 204),
        };
      }));
      final account = await client.me();
      expect([account.id, account.usedBytes, account.quotaBytes, account.deletionScheduledFor], ['u1', 5, 10, DateTime.utc(2026, 12, 1)]);
      final sessions = await client.sessions();
      expect([sessions.single.id, sessions.single.current, sessions.single.userAgent], ['s1', true, 'UA']);
      await client.revokeSession('s1');
      expect(await client.requestDeletion('pw'), DateTime.utc(2026, 12, 1));
      await client.cancelDeletion();
      await client.signUp(name: 'A', email: 'a@b.test', password: 'long-enough-pw');
      await client.signOut();
      await client.requestPasswordReset(email: 'a@b.test', redirectTo: 'doro://reset');
      await client.resetPassword(token: 't', newPassword: 'new-long-password');
      expect(seen, ['GET /v1/me', 'GET /v1/me/sessions', 'DELETE /v1/me/sessions/s1', 'POST /v1/me/deletion', 'DELETE /v1/me/deletion', 'POST /v1/auth/sign-up/email', 'POST /v1/auth/sign-out', 'POST /v1/auth/request-password-reset', 'POST /v1/auth/reset-password']);
    });

    test('presets list, put and delete', () async {
      final seen = <String>[];
      final client = clientFor(MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        final preset = {'id': 'p1', 'name': 'N', 'experienceId': 'e', 'intent': {'a': 1}, 'profile': {'id': 'x', 'version': 3}, 'live': true, 'source': 'user', 'version': 4};
        return request.method == 'GET' ? json({'items': [preset]}) : request.method == 'PUT' ? json(preset) : http.Response('', 204);
      }));
      final list = await client.presets();
      expect([list.single.name, list.single.profileId, list.single.profileVersion, list.single.live, list.single.version], ['N', 'x', 3, true, 4]);
      final saved = await client.putPreset('p1', name: 'N', experienceId: 'e', intent: const {'a': 1}, live: true, source: 'user', profileId: 'x');
      expect(saved.intent, {'a': 1});
      await client.deletePreset('p1');
      expect(seen, ['GET /v1/presets', 'PUT /v1/presets/p1', 'DELETE /v1/presets/p1']);
    });

    test('putPreset sends a null profile when there is none', () async {
      Object? body;
      final client = clientFor(MockClient((request) async {
        body = jsonDecode(request.body);
        return json({'id': 'p1', 'name': 'N', 'experienceId': 'e', 'intent': <String, Object?>{}, 'profile': null, 'live': false, 'source': 'user', 'version': 1});
      }));
      await client.putPreset('p1', name: 'N', experienceId: 'e', intent: const {}, live: false, source: 'user');
      expect((body! as Map<String, Object?>)['profile'], isNull);
    });
  });

  group('uploads', () {
    test('parses a complete, a single and a multipart plan', () async {
      final plans = <Map<String, Object?>>[
        {'mode': 'complete', 'status': 'complete', 'deduplicated': true},
        {'mode': 'single', 'url': 'https://s.test/x?sig=1', 'expiresAt': '2026-11-13T13:00:00.000Z', 'headers': {'content-type': 'image/jpeg'}},
        {
          'mode': 'multipart',
          'uploadId': 'up1',
          'partSize': 8388608,
          'partCount': 3,
          'expiresAt': '2026-11-13T13:00:00.000Z',
          'parts': [{'partNumber': 2, 'url': 'https://s.test/p2'}, {'partNumber': 3, 'url': 'https://s.test/p3'}],
          'completed': [{'partNumber': 1, 'etag': '"e1"'}],
        },
      ];
      var i = 0;
      final client = clientFor(MockClient((_) async => json(plans[i++])));
      const body = CreateUpload(role: 'photo_original', mime: 'image/jpeg', bytes: 10, sha256: 'ab');
      final complete = await client.createUpload('m1', 'a1', body) as CompleteUploadPlan;
      expect(complete.deduplicated, isTrue);
      final single = await client.createUpload('m1', 'a1', body) as SingleUploadPlan;
      expect([single.url.host, single.headers['content-type'], single.expiresAt], ['s.test', 'image/jpeg', DateTime.utc(2026, 11, 13, 13)]);
      final multi = await client.createUpload('m1', 'a1', body) as MultipartUploadPlan;
      expect([multi.uploadId, multi.partSize, multi.partCount], ['up1', 8388608, 3]);
      expect(multi.parts.keys, [2, 3]);
      expect(multi.completed, {1: '"e1"'});
    });

    test('an unknown upload mode is a format error', () {
      expect(() => UploadPlan.fromJson({'mode': 'teleport'}), throwsFormatException);
    });

    test('CreateUpload includes dimensions only when known', () {
      expect(const CreateUpload(role: 'r', mime: 'm', bytes: 1, sha256: 's').toJson(), {'role': 'r', 'mime': 'm', 'bytes': 1, 'sha256': 's'});
      expect(const CreateUpload(role: 'r', mime: 'm', bytes: 1, sha256: 's', width: 2, height: 3, durationMs: 4).toJson(), containsPair('durationMs', 4));
    });

    test('completeUpload sends the part list and returns the asset status', () async {
      Object? sent;
      final client = clientFor(MockClient((request) async {
        final text = request.body;
        sent = text.isEmpty ? null : jsonDecode(text);
        return json({'status': 'uploaded'});
      }));
      expect(await client.completeUpload('m1', 'a1', uploadId: 'up1', parts: [(partNumber: 1, etag: '"e1"'), (partNumber: 2, etag: '"e2"')]), 'uploaded');
      expect(sent, {'uploadId': 'up1', 'parts': [{'partNumber': 1, 'etag': '"e1"'}, {'partNumber': 2, 'etag': '"e2"'}]});
      await client.completeUpload('m1', 'a1');
      expect(sent, <String, Object?>{});
      await client.abortUpload('m1', 'a1');
    });
  });

  group('sync', () {
    test('[SYNC-006] parses the change feed', () async {
      final client = clientFor(MockClient((request) async {
        expect(request.url.queryParameters, {'cursor': '5', 'limit': '2'});
        return json({
          'items': [
            {'seq': 6, 'entity': 'memory', 'entityId': 'm1', 'op': 'upsert', 'at': 'x'},
            {'seq': 7, 'entity': 'preset', 'entityId': 'p1', 'op': 'delete', 'at': 'x'},
          ],
          'nextCursor': 7,
          'hasMore': true,
        });
      }));
      final page = await client.syncChanges(cursor: 5, limit: 2);
      expect(page.changes.map((c) => [c.seq, c.entity, c.entityId, c.op]), [[6, 'memory', 'm1', 'upsert'], [7, 'preset', 'p1', 'delete']]);
      expect([page.nextCursor, page.hasMore], [7, true]);
    });
  });

  group('errors', () {
    test('maps the documented error envelope, including the request id', () async {
      final client = clientFor(MockClient((_) async => json({'error': {'code': 'memory.conflict', 'message': 'Different fields.', 'requestId': 'r-9'}}, 409)));
      final error = await client.memory('m1').then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<ApiException>());
      final api = error! as ApiException;
      expect([api.status, api.code, api.message, api.requestId], [409, 'memory.conflict', 'Different fields.', 'r-9']);
      expect(api.toString(), contains('409 memory.conflict'));
    });

    test('maps Better Auth bodies and non-JSON failures', () async {
      var body = jsonEncode({'code': 'INVALID_EMAIL_OR_PASSWORD', 'message': 'Invalid email or password'});
      final client = clientFor(MockClient((_) async => http.Response(body, 401)));
      expect(await client.signIn(email: 'a', password: 'b').then<Object?>((_) => null, onError: (Object e) => e), isA<ApiException>().having((e) => e.code, 'code', 'INVALID_EMAIL_OR_PASSWORD'));
      body = '<html>bad gateway</html>';
      expect(await client.signIn(email: 'a', password: 'b').then<Object?>((_) => null, onError: (Object e) => e), isA<ApiException>().having((e) => [e.status, e.code], 'status/code', [401, 'request.failed']));
    });

    test('[SYNC-002] reads Retry-After seconds on 429 and classifies status families', () async {
      final client = clientFor(MockClient((_) async => json({'error': {'code': 'rate_limited', 'message': 'slow down'}}, 429, {'retry-after': '12'})));
      final error = await client.me().then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
      expect(error!.retryAfter, const Duration(seconds: 12));
      expect([error.isRateLimited, error.isServerError, error.isUnauthenticated], [true, false, false]);
      expect(const ApiException(status: 503, code: 'x', message: 'x').isServerError, isTrue);
    });

    test('network failures become NetworkException, never raw socket errors', () async {
      for (final failure in <Object>[const SocketException('down'), http.ClientException('reset'), TimeoutException('slow'), const HandshakeException('tls')]) {
        final client = clientFor(MockClient((_) async => throw failure));
        await expectLater(client.me(), throwsA(isA<NetworkException>()), reason: '$failure');
      }
      expect(const NetworkException('x').toString(), contains('NetworkException'));
    });

    test('other exceptions are not swallowed', () async {
      final client = clientFor(MockClient((_) async => throw StateError('bug')));
      await expectLater(client.me(), throwsStateError);
    });

    test('a request that takes longer than the timeout is a NetworkException', () async {
      final client = DoroApiClient(
        baseUrl: Uri.parse('https://api.test'),
        httpClient: MockClient((_) => Completer<http.Response>().future),
        token: () async => 't',
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(client.me(), throwsA(isA<NetworkException>()));
    });

    test('[AUTH-004] a 401 on an authenticated call fires the unauthorized stream; sign-in 401 does not', () async {
      final client = clientFor(MockClient((_) async => json({'error': {'code': 'auth.unauthenticated', 'message': 'x'}}, 401)));
      var fired = 0;
      final sub = client.unauthorized.listen((_) => fired++);
      await client.me().then<void>((_) {}, onError: (Object _) {});
      await client.signIn(email: 'a', password: 'b').then<void>((_) {}, onError: (Object _) {});
      await pumpEventQueue();
      expect(fired, 1);
      await sub.cancel();
      client.close();
    });
  });

  group('models', () {
    test('ApiMemory parses every field, the owner flag and asset lookup', () {
      final memory = ApiMemory.fromJson(memoryJson(version: 4));
      expect([memory.id, memory.version, memory.profileId, memory.profileVersion, memory.caption, memory.favorite, memory.aspectRatio, memory.locationShared], ['m1', 4, 'natural', 2, 'Hi', true, '3:2', true]);
      expect([memory.lat, memory.lon, memory.locationAccuracyM], [3.1, 101.6, 5.0]);
      expect(memory.capturedAt, DateTime.utc(2026, 11, 1, 9, 30));
      expect(memory.asset('a1')!.isServable, isTrue);
      expect(memory.asset('nope'), isNull);
      expect(memory.deletedAt, isNull);
    });

    test('ApiMemory tolerates a missing location, profile and deletedAt value', () {
      final json = memoryJson()
        ..['location'] = null
        ..['profile'] = null
        ..['deletedAt'] = '2026-11-02T00:00:00.000Z'
        ..['isOwner'] = false;
      final memory = ApiMemory.fromJson(json);
      expect([memory.lat, memory.profileId, memory.isOwner], [null, null, false]);
      expect(memory.deletedAt, DateTime.utc(2026, 11, 2));
    });

    test('an asset is servable only when verified or ready', () {
      ApiAsset asset(String s) => ApiAsset(id: 'a', role: 'r', status: s, mime: 'm', bytes: 1);
      expect(['pending', 'uploading', 'uploaded', 'verified', 'ready', 'failed'].map((s) => asset(s).isServable), [false, false, false, true, true, false]);
    });
  });

  group('AuthService', () {
    late Env env;
    setUp(() async => env = await Env.create());
    tearDown(() => env.close());

    test('[AUTH-001] sign-up forwards the details; the user must verify before signing in', () async {
      await env.auth.signUp(name: 'D', email: 'd@example.test', password: 'long-enough-pw');
      expect(env.backend.bodies['POST /v1/auth/sign-up/email']!.single, {'name': 'D', 'email': 'd@example.test', 'password': 'long-enough-pw'});
    });

    test('[AUTH-005] sign-in stores the token, activates the account and claims anonymous captures', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      expect(view.memory.accountId, isNull);
      final account = await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      expect(account.id, 'user-1');
      expect(await env.tokens.read(), 'token-1');
      expect(env.account.accountId, 'user-1');
      expect(env.auth.current!.email, 'dorothy@example.test');
      expect((await env.memories.view(view.memory.id))!.memory.accountId, 'user-1');
      expect(await env.db.select(env.db.uploadJobs).get(), hasLength(2));
    });

    test('[AUTH-001] a wrong password leaves the device signed out with no token stored', () async {
      await expectLater(env.auth.signIn(email: 'd@example.test', password: 'wrong'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(await env.tokens.read(), isNull);
      expect(env.account.isSignedIn, isFalse);
    });

    test('a failure fetching the account after sign-in does not leave a half signed-in state', () async {
      env.backend.interceptor = (request, key) => key == 'GET /v1/me' ? http.Response('{}', 500) : null;
      await expectLater(env.auth.signIn(email: 'd@example.test', password: 'correct-password'), throwsA(isA<ApiException>()));
      expect(await env.tokens.read(), isNull);
      expect(env.account.isSignedIn, isFalse);
    });

    test('[AUTH-004] sign-out clears the token and account even when offline; local data stays', () async {
      final view = await env.memories.commitCapture(photoDraft(env.scratch));
      await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      env.backend.interceptor = (r, k) => throw FakeBackend.networkDown;
      await env.auth.signOut();
      expect(await env.tokens.read(), isNull);
      expect(env.account.accountId, isNull);
      expect(env.auth.current, isNull);
      expect(await env.memories.view(view.memory.id), isNotNull); // NFR-001
    });

    test('sign-out also tolerates the session already being gone', () async {
      await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      env.backend.interceptor = (r, k) => http.Response('{"error":{"code":"auth.unauthenticated","message":"x"}}', 401);
      await env.auth.signOut();
      expect(env.account.isSignedIn, isFalse);
    });

    test('[AUTH-004] restore re-activates a valid session, signs out a revoked one, and survives being offline', () async {
      expect(await env.auth.restore(), isNull); // nothing stored

      await env.tokens.write('token-1');
      expect((await env.auth.restore())!.id, 'user-1');
      expect(env.account.accountId, 'user-1');

      env.backend.interceptor = (r, k) => throw FakeBackend.networkDown;
      expect((await env.auth.restore())!.id, 'user-1'); // offline: stay signed in (NFR-001)
      expect(env.account.accountId, 'user-1');

      env.backend.interceptor = null;
      env.backend.signInToken = 'rotated'; // the server no longer accepts the stored token
      expect(await env.auth.restore(), isNull);
      expect(await env.tokens.read(), isNull);
      expect(env.account.accountId, isNull);
    });

    test('restore rethrows server errors that are not about authentication', () async {
      await env.tokens.write('token-1');
      env.backend.interceptor = (r, k) => http.Response('{"error":{"code":"internal","message":"x"}}', 500);
      await expectLater(env.auth.restore(), throwsA(isA<ApiException>()));
    });

    test('[AUTH-004] a 401 from any call ends the local session', () async {
      await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      env.backend.signInToken = 'revoked';
      await env.api.presets().then<void>((_) {}, onError: (Object _) {});
      await pumpEventQueue();
      expect(env.account.accountId, isNull);
      expect(await env.tokens.read(), isNull);
    });

    test('[AUTH-006] password reset, sessions, revocation, deletion and refresh delegate to the API', () async {
      await env.auth.signIn(email: 'd@example.test', password: 'correct-password');
      await env.auth.requestPasswordReset('d@example.test', redirectTo: 'doro://reset');
      await env.auth.resetPassword(token: 't', newPassword: 'a-new-long-password');
      expect((await env.auth.sessions()).single.current, isTrue);
      await env.auth.revokeSession('s1');
      expect(await env.auth.requestAccountDeletion('correct-password'), DateTime.utc(2026, 12, 1));
      await env.auth.cancelAccountDeletion();
      expect((await env.auth.refresh()).quotaBytes, greaterThan(0));
      expect(env.backend.bodies['POST /v1/auth/request-password-reset']!.single, {'email': 'd@example.test', 'redirectTo': 'doro://reset'});
    });
  });

  test('InMemoryTokenStore stores, reads and deletes a token', () async {
    final store = InMemoryTokenStore();
    expect(await store.read(), isNull);
    await store.write('t');
    expect(await store.read(), 't');
    await store.delete();
    expect(await store.read(), isNull);
  });
}
