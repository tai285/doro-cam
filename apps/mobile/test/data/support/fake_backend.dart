import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// An in-memory stand-in for services/api plus object storage, implementing the protocol of
/// docs/specs/upload-sync.md closely enough to exercise every client state transition and failure
/// path deterministically. (The same client code is also run against the REAL API in
/// test/data/integration.)
class FakeBackend extends http.BaseClient {
  FakeBackend({this.userId = 'user-1'});

  final String userId;
  final String storageHost = 'storage.test';

  // ---- state --------------------------------------------------------------------------------
  final Map<String, Map<String, Object?>> memories = {};
  final Map<String, Map<String, Object?>> assets = {};
  final Map<String, List<int>> objects = {};
  final Map<String, Map<int, ({List<int> bytes, String etag})>> multipart = {};
  final Map<String, Map<String, Object?>> presets = {};
  final List<Map<String, Object?>> changes = [];
  int _seq = 0;
  int _uploadCounter = 0;

  /// All requests received, as `METHOD /path`.
  final List<String> requests = [];

  /// Bodies of the JSON requests by `METHOD /path`.
  final Map<String, List<Object?>> bodies = {};

  // ---- fault injection ----------------------------------------------------------------------
  /// Called before every request. Return a response to short-circuit, throw to simulate a network
  /// failure, or return null to continue normally.
  FutureOr<http.Response?> Function(http.BaseRequest request, String key)? interceptor;

  /// Status the server reports for an asset right after `complete`. Set to `failed` to simulate a
  /// checksum mismatch found by the verify job.
  bool corruptNextVerification = false;

  /// How many `GET /v1/memories/{id}` calls report `uploaded` before the asset becomes `verified`.
  int verifyAfterPolls = 0;
  final Map<String, int> _polls = {};

  /// Presigned URLs older than this (counting storage requests) are rejected with [expiredStatus].
  int? urlsValidForRequests;
  int expiredStatus = 400;
  int _storageRequests = 0;
  int _urlGeneration = 0;
  final Map<String, int> _urlIssuedAt = {};
  bool expireAllUrls = false;

  int quotaBytes = 1 << 40;
  String? signInToken = 'token-1';
  String? currentPassword = 'correct-password';

  int get storageRequestCount => _storageRequests;

  // ---- http.Client --------------------------------------------------------------------------
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final key = '${request.method} ${request.url.path}';
    requests.add(key);
    final intercepted = await interceptor?.call(request, key);
    http.Response response;
    if (intercepted != null) {
      response = intercepted;
    } else if (request.url.host == storageHost) {
      response = _storage(request, bytes);
    } else {
      response = _api(request, bytes, key);
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      contentLength: response.bodyBytes.length,
    );
  }

  http.Response _json(int status, Object? body, {Map<String, String> headers = const {}}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

  http.Response _error(int status, String code, [String message = 'error']) =>
      _json(status, {'error': {'code': code, 'message': message, 'requestId': 'req-1'}});

  Map<String, Object?> _body(List<int> bytes) =>
      bytes.isEmpty ? {} : Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map<Object?, Object?>);

  // ---- API ----------------------------------------------------------------------------------
  http.Response _api(http.BaseRequest request, List<int> bytes, String key) {
    final path = request.url.path;
    final method = request.method;
    Map<String, Object?> body = {};
    if (method != 'GET' && bytes.isNotEmpty) {
      body = _body(bytes);
      (bodies[key] ??= []).add(body);
    }

    if (method == 'POST' && path == '/v1/auth/sign-in/email') {
      if (body['password'] != currentPassword) {
        return _json(401, {'code': 'INVALID_EMAIL_OR_PASSWORD', 'message': 'Invalid email or password'});
      }
      return _json(200, {'ok': true}, headers: {'set-auth-token': signInToken ?? ''});
    }
    if (method == 'POST' && path == '/v1/auth/sign-up/email') {
      return _json(200, {'ok': true});
    }
    if (method == 'POST' && (path == '/v1/auth/sign-out' || path == '/v1/auth/request-password-reset' || path == '/v1/auth/reset-password')) {
      return _json(200, {'ok': true});
    }
    final auth = request.headers['authorization'];
    if (auth == null || auth != 'Bearer $signInToken') {
      return _error(401, 'auth.unauthenticated', 'Authentication is required.');
    }
    if (method == 'GET' && path == '/v1/me') {
      return _json(200, {
        'id': userId,
        'email': 'dorothy@example.test',
        'name': 'Dorothy',
        'emailVerified': true,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'storage': {'usedBytes': 0, 'quotaBytes': quotaBytes},
        'deletionRequestedAt': null,
        'deletionScheduledFor': null,
      });
    }
    if (method == 'GET' && path == '/v1/me/sessions') {
      return _json(200, {
        'items': [
          {'id': 's1', 'current': true, 'userAgent': 'Test', 'ipAddress': null, 'createdAt': '2026-01-01T00:00:00.000Z', 'expiresAt': '2026-02-01T00:00:00.000Z'},
        ],
      });
    }
    if (method == 'DELETE' && path.startsWith('/v1/me/sessions/')) {
      return http.Response('', 204);
    }
    if (method == 'POST' && path == '/v1/me/deletion') {
      if (body['password'] != currentPassword) {
        return _error(403, 'auth.reauthentication_failed');
      }
      return _json(200, {'scheduledFor': '2026-12-01T00:00:00.000Z'});
    }
    if (method == 'DELETE' && path == '/v1/me/deletion') {
      return http.Response('', 204);
    }
    if (method == 'GET' && path == '/v1/sync/changes') {
      final cursor = int.parse(request.url.queryParameters['cursor'] ?? '0');
      final limit = int.parse(request.url.queryParameters['limit'] ?? '100');
      final due = changes.where((c) => (c['seq']! as int) > cursor).toList();
      final page = due.take(limit).toList();
      return _json(200, {
        'items': page,
        'nextCursor': page.isEmpty ? cursor : page.last['seq'],
        'hasMore': due.length > limit,
      });
    }
    if (path == '/v1/presets' && method == 'GET') {
      return _json(200, {'items': presets.values.toList()});
    }
    final preset = RegExp(r'^/v1/presets/([^/]+)$').firstMatch(path);
    if (preset != null) {
      final id = preset.group(1)!;
      if (method == 'PUT') {
        final existing = presets[id];
        final saved = {
          'id': id,
          'name': body['name'],
          'experienceId': body['experienceId'],
          'intent': body['intent'],
          'profile': body['profile'],
          'live': body['live'],
          'source': body['source'],
          'version': existing == null ? 1 : (existing['version']! as int) + 1,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        };
        presets[id] = saved;
        _record('preset', id, 'upsert');
        return _json(200, saved);
      }
      if (method == 'DELETE') {
        if (presets.remove(id) == null) {
          return _error(404, 'preset.not_found');
        }
        _record('preset', id, 'delete');
        return http.Response('', 204);
      }
    }

    final memoryMatch = RegExp(r'^/v1/memories/([^/]+)(?:/(.*))?$').firstMatch(path);
    if (memoryMatch == null) {
      return _error(404, 'route.not_found');
    }
    final memoryId = memoryMatch.group(1)!;
    final sub = memoryMatch.group(2);

    if (sub == null) {
      if (method == 'PUT') {
        final existing = memories[memoryId];
        if (existing != null) {
          if (existing['kind'] != body['kind'] || existing['capturedAt'] != body['capturedAt']) {
            return _error(409, 'memory.conflict');
          }
          return _json(200, _memoryJson(memoryId));
        }
        memories[memoryId] = {...body, 'id': memoryId, 'version': 1, 'deletedAt': null, 'publicHandle': 'H${memoryId.hashCode.abs()}'.padRight(22, 'x')};
        _record('memory', memoryId, 'upsert');
        return _json(201, _memoryJson(memoryId));
      }
      final memory = memories[memoryId];
      if (memory == null) {
        return _error(404, 'memory.not_found');
      }
      if (method == 'GET') {
        _advanceVerification(memoryId);
        return _json(200, _memoryJson(memoryId));
      }
      if (method == 'PATCH') {
        final ifMatch = request.headers['If-Match'] ?? request.headers['if-match'];
        if (ifMatch != null && int.parse(ifMatch) != memory['version']) {
          return _error(409, 'conflict.version');
        }
        for (final entry in body.entries) {
          if (entry.key == 'removeLocation') {
            memory.remove('location');
          } else {
            memory[entry.key] = entry.value;
          }
        }
        memory['version'] = (memory['version']! as int) + 1;
        _record('memory', memoryId, 'upsert');
        return _json(200, _memoryJson(memoryId));
      }
      if (method == 'DELETE') {
        if (memory['deletedAt'] == null) {
          return _error(409, 'memory.not_trashed');
        }
        memories.remove(memoryId);
        assets.removeWhere((_, a) => a['memoryId'] == memoryId);
        _record('memory', memoryId, 'delete');
        return _json(202, {'status': 'purging'});
      }
    }
    final memory = memories[memoryId];
    if (memory == null) {
      return _error(404, 'memory.not_found');
    }
    if (method == 'POST' && (sub == 'trash' || sub == 'restore')) {
      memory['deletedAt'] = sub == 'trash' ? '2026-11-13T00:00:00.000Z' : null;
      memory['version'] = (memory['version']! as int) + 1;
      _record('memory', memoryId, sub == 'trash' ? 'delete' : 'upsert');
      return _json(200, _memoryJson(memoryId));
    }
    final upload = RegExp(r'^assets/([^/]+)/upload(?:/(complete|abort))?$').firstMatch(sub ?? '');
    if (upload != null && method == 'POST') {
      final assetId = upload.group(1)!;
      return switch (upload.group(2)) {
        null => _createUpload(memoryId, assetId, body),
        'complete' => _completeUpload(memoryId, assetId, body),
        _ => http.Response('', 204),
      };
    }
    return _error(404, 'route.not_found');
  }

  void _record(String entity, String id, String op) {
    _seq++;
    changes.add({'seq': _seq, 'entity': entity, 'entityId': id, 'op': op, 'at': '2026-11-13T00:00:00.000Z'});
  }

  /// Adds a change as if another device had made it.
  void recordExternalChange(String entity, String id, String op) => _record(entity, id, op);

  Map<String, Object?> _memoryJson(String id) {
    final memory = memories[id]!;
    final own = assets.values.where((a) => a['memoryId'] == id).toList();
    return {
      'id': id,
      'ownerId': userId,
      'isOwner': true,
      'kind': memory['kind'],
      'capturedAt': memory['capturedAt'],
      'capturedTz': memory['capturedTz'],
      'experienceId': memory['experienceId'],
      'profile': memory['profile'],
      'presetId': memory['presetId'],
      'scenario': memory['scenario'],
      'capture': memory['capture'] ?? <String, Object?>{},
      'location': memory['location'],
      'locationShared': memory['locationShared'] ?? false,
      'caption': memory['caption'],
      'favorite': memory['favorite'] ?? false,
      'aspectRatio': memory['aspectRatio'],
      'publicHandle': memory['publicHandle'],
      'version': memory['version'],
      'createdAt': '2026-11-13T00:00:00.000Z',
      'updatedAt': '2026-11-13T00:00:00.000Z',
      'deletedAt': memory['deletedAt'],
      'assets': [
        for (final a in own)
          {
            'id': a['id'],
            'role': a['role'],
            'status': a['status'],
            'mime': a['mime'],
            'bytes': a['bytes'],
            'width': null,
            'height': null,
            'durationMs': null,
            'failureReason': a['failureReason'],
          },
      ],
      'thumbnail': null,
      'display': null,
    };
  }

  // ---- uploads ------------------------------------------------------------------------------
  Uri _url(String assetId, {int? part}) {
    _urlGeneration++;
    final url = Uri.https(storageHost, '/o/$assetId', {'gen': '$_urlGeneration', if (part != null) 'part': '$part'});
    _urlIssuedAt[url.toString()] = _storageRequests;
    return url;
  }

  http.Response _createUpload(String memoryId, String assetId, Map<String, Object?> body) {
    final bytes = (body['bytes']! as num).toInt();
    final existing = assets[assetId];
    if (existing != null && (existing['status'] == 'verified' || existing['status'] == 'ready')) {
      return _json(200, {'mode': 'complete', 'status': 'complete', 'deduplicated': false});
    }
    final used = assets.values.where((a) => a['status'] == 'verified').fold<int>(0, (sum, a) => sum + (a['bytes']! as int));
    if (existing == null && used + bytes > quotaBytes) {
      return _error(403, 'upload.quota_exceeded', 'Your storage quota is full.');
    }
    final duplicate = assets.values.where((a) => a['sha256'] == body['sha256'] && a['bytes'] == bytes && a['status'] == 'verified').toList();
    if (existing == null && duplicate.isNotEmpty) {
      assets[assetId] = {...body, 'id': assetId, 'memoryId': memoryId, 'status': 'verified', 'failureReason': null};
      _record('memory', memoryId, 'upsert');
      return _json(200, {'mode': 'complete', 'status': 'complete', 'deduplicated': true});
    }
    assets[assetId] = {...body, 'id': assetId, 'memoryId': memoryId, 'status': 'uploading', 'failureReason': null, if (existing != null) 'uploadId': existing['uploadId']};
    final expires = DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
    if (bytes <= 16 * 1024 * 1024) {
      return _json(200, {'mode': 'single', 'url': _url(assetId).toString(), 'expiresAt': expires, 'headers': {'content-type': body['mime']}});
    }
    final partSize = ((bytes / 10000).ceil() > 8 * 1024 * 1024 ? (bytes / 10000).ceil() : 8 * 1024 * 1024);
    final rounded = (partSize / (1024 * 1024)).ceil() * 1024 * 1024;
    final count = (bytes / rounded).ceil();
    final uploadId = (assets[assetId]!['uploadId'] as String?) ?? 'upload-${++_uploadCounter}';
    assets[assetId]!['uploadId'] = uploadId;
    final stored = multipart[uploadId] ??= {};
    return _json(200, {
      'mode': 'multipart',
      'uploadId': uploadId,
      'partSize': rounded,
      'partCount': count,
      'expiresAt': expires,
      'parts': [for (var n = 1; n <= count; n++) if (!stored.containsKey(n)) {'partNumber': n, 'url': _url(assetId, part: n).toString()}],
      'completed': [for (final e in stored.entries) {'partNumber': e.key, 'etag': e.value.etag}],
    });
  }

  http.Response _completeUpload(String memoryId, String assetId, Map<String, Object?> body) {
    final asset = assets[assetId];
    if (asset == null) {
      return _error(404, 'upload.not_found');
    }
    if (asset['status'] != 'uploading') {
      return _json(200, {'status': asset['status']});
    }
    List<int> data;
    final uploadId = asset['uploadId'] as String?;
    if (uploadId != null) {
      final parts = multipart[uploadId];
      if (parts == null) {
        return _error(404, 'upload.not_found');
      }
      final listed = (body['parts'] as List<Object?>?)?.cast<Map<Object?, Object?>>() ?? [];
      for (final part in listed) {
        final stored = parts[(part['partNumber']! as num).toInt()];
        if (stored == null || stored.etag != part['etag']) {
          return _error(400, 'InvalidPart');
        }
      }
      data = [for (final n in (parts.keys.toList()..sort())) ...parts[n]!.bytes];
    } else {
      final single = objects[assetId];
      if (single == null) {
        return _error(404, 'upload.not_found');
      }
      data = single;
    }
    if (data.length != asset['bytes']) {
      return _error(422, 'upload.size_mismatch');
    }
    objects[assetId] = data;
    asset['status'] = 'uploaded';
    asset['actualSha'] = crypto.sha256.convert(data).toString();
    return _json(200, {'status': 'uploaded'});
  }

  void _advanceVerification(String memoryId) {
    for (final asset in assets.values.where((a) => a['memoryId'] == memoryId && a['status'] == 'uploaded')) {
      final polls = _polls[asset['id']! as String] = (_polls[asset['id']! as String] ?? 0) + 1;
      if (polls > verifyAfterPolls) {
        final bad = corruptNextVerification || asset['actualSha'] != asset['sha256'];
        corruptNextVerification = false;
        asset['status'] = bad ? 'failed' : 'verified';
        asset['failureReason'] = bad ? 'checksum_mismatch' : null;
        if (bad) {
          objects.remove(asset['id']);
        }
        _record('memory', memoryId, 'upsert');
      }
    }
  }

  // ---- storage ------------------------------------------------------------------------------
  http.Response _storage(http.BaseRequest request, List<int> bytes) {
    _storageRequests++;
    final url = request.url.toString();
    final issued = _urlIssuedAt[url];
    if (expireAllUrls || (urlsValidForRequests != null && issued != null && _storageRequests - issued > urlsValidForRequests!)) {
      return http.Response('<Error>expired</Error>', expiredStatus);
    }
    if (request.method != 'PUT') {
      return http.Response('', 405);
    }
    final assetId = request.url.pathSegments.last;
    final part = request.url.queryParameters['part'];
    if (part == null) {
      objects[assetId] = bytes;
      return http.Response('', 200, headers: {'etag': '"${crypto.md5.convert(bytes)}"'});
    }
    final uploadId = assets[assetId]?['uploadId'] as String?;
    if (uploadId == null) {
      return http.Response('<Error>NoSuchUpload</Error>', 404);
    }
    final etag = '"${crypto.md5.convert(bytes)}"';
    (multipart[uploadId] ??= {})[int.parse(part)] = (bytes: bytes, etag: etag);
    return http.Response('', 200, headers: {'etag': etag});
  }

  /// Drops multipart state, as storage does when an upload session expires.
  void forgetUploadSessions() => multipart.clear();

  /// Tells which assets the server holds in a given status.
  List<String> assetsWithStatus(String status) => [for (final a in assets.values) if (a['status'] == status) a['id']! as String];

  /// A network failure for the interceptor to throw.
  static SocketException get networkDown => const SocketException('network is down');
}
