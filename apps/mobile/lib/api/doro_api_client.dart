// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/api_models.dart';
import 'package:http/http.dart' as http;

/// Supplies the bearer token of the signed-in device session, or null when signed out.
typedef TokenReader = Future<String?> Function();

/// HTTP client for services/api (packages/api-contract/openapi.json). It only talks to the API;
/// media bytes go straight to storage through presigned URLs and never pass through here (ADR-0008).
class DoroApiClient {
  DoroApiClient({
    required this.baseUrl,
    required http.Client httpClient,
    required TokenReader token,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient,
       _token = token;

  final Uri baseUrl;
  final http.Client _http;
  final TokenReader _token;
  final Duration timeout;
  final StreamController<void> _unauthorized = StreamController<void>.broadcast();

  /// Fires when an authenticated request is answered with 401: the session ended or was revoked.
  Stream<void> get unauthorized => _unauthorized.stream;

  void close() {
    _http.close();
    unawaited(_unauthorized.close());
  }

  // ---- auth (Better Auth under /v1/auth) -----------------------------------------------------

  Future<void> signUp({required String name, required String email, required String password}) =>
      _send('POST', '/v1/auth/sign-up/email', body: {'name': name, 'email': email, 'password': password}, authenticated: false);

  /// Signs in and returns the bearer token of this device's session (AUTH-004: one session per device).
  Future<String> signIn({required String email, required String password}) async {
    final response = await _raw('POST', '/v1/auth/sign-in/email', body: {'email': email, 'password': password}, authenticated: false);
    final token = response.headers['set-auth-token'];
    if (token == null || token.isEmpty) {
      throw const ApiException(status: 500, code: 'auth.no_token', message: 'The server did not return a session token.');
    }
    return token;
  }

  Future<void> signOut() => _send('POST', '/v1/auth/sign-out', body: const {});

  Future<void> requestPasswordReset({required String email, required String redirectTo}) =>
      _send('POST', '/v1/auth/request-password-reset', body: {'email': email, 'redirectTo': redirectTo}, authenticated: false);

  Future<void> resetPassword({required String token, required String newPassword}) =>
      _send('POST', '/v1/auth/reset-password', body: {'token': token, 'newPassword': newPassword}, authenticated: false);

  // ---- account -------------------------------------------------------------------------------

  Future<Account> me() async => Account.fromJson(await _json('GET', '/v1/me'));

  Future<List<DeviceSession>> sessions() async {
    final json = await _json('GET', '/v1/me/sessions');
    return [for (final item in (json['items']! as List<Object?>).cast<Map<Object?, Object?>>()) DeviceSession.fromJson(Map<String, Object?>.from(item))];
  }

  Future<void> revokeSession(String id) => _send('DELETE', '/v1/me/sessions/$id');

  /// Schedules account deletion after the 7-day grace period (needs the password, PRIV-004).
  Future<DateTime> requestDeletion(String password) async {
    final json = await _json('POST', '/v1/me/deletion', body: {'password': password});
    return DateTime.parse(json['scheduledFor']! as String).toUtc();
  }

  Future<void> cancelDeletion() => _send('DELETE', '/v1/me/deletion');

  // ---- memories ------------------------------------------------------------------------------

  /// Idempotent upsert (upload-sync.md step 1). Throws [ApiException] 409 `memory.conflict` when the
  /// immutable fields differ, a client bug that is surfaced as a permanent failure.
  Future<RegisterResult> registerMemory(String id, RegisterMemory memory) async {
    final response = await _raw('PUT', '/v1/memories/$id', body: memory.toJson(), headers: {'Idempotency-Key': '$id:register'});
    return RegisterResult(memory: ApiMemory.fromJson(_decodeObject(response)), created: response.statusCode == 201);
  }

  Future<ApiMemory> memory(String id) async => ApiMemory.fromJson(await _json('GET', '/v1/memories/$id'));

  /// Fetches one page of the library (newest first). Returns the items and the next cursor, or null at the end.
  Future<({List<ApiMemory> items, String? nextCursor})> listMemories({String? cursor, int limit = 50, bool trashed = false}) async {
    final json = await _json('GET', '/v1/memories', query: {'limit': '$limit', 'cursor': ?cursor, if (trashed) 'trashed': 'true'});
    return (
      items: [for (final item in (json['items']! as List<Object?>).cast<Map<Object?, Object?>>()) ApiMemory.fromJson(Map<String, Object?>.from(item))],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Field-level update. [ifMatch] is the `serverVersion` the edit was based on.
  Future<ApiMemory> patchMemory(String id, Map<String, Object?> fields, {int? ifMatch}) async =>
      ApiMemory.fromJson(await _json('PATCH', '/v1/memories/$id', body: fields, headers: {'If-Match': ?ifMatch?.toString()}));

  Future<ApiMemory> trashMemory(String id) async => ApiMemory.fromJson(await _json('POST', '/v1/memories/$id/trash'));

  Future<ApiMemory> restoreMemory(String id) async => ApiMemory.fromJson(await _json('POST', '/v1/memories/$id/restore'));

  /// Permanently deletes a Memory that is already in the trash.
  Future<void> purgeMemory(String id) => _send('DELETE', '/v1/memories/$id');

  // ---- uploads -------------------------------------------------------------------------------

  Future<UploadPlan> createUpload(String memoryId, String assetId, CreateUpload upload) async =>
      UploadPlan.fromJson(await _json('POST', '/v1/memories/$memoryId/assets/$assetId/upload', body: upload.toJson()));

  /// Completes an upload; returns the asset status the server reports (`uploaded`, `verified`, ...).
  Future<String> completeUpload(String memoryId, String assetId, {String? uploadId, List<({int partNumber, String etag})>? parts}) async {
    final json = await _json(
      'POST',
      '/v1/memories/$memoryId/assets/$assetId/upload/complete',
      body: {
        'uploadId': ?uploadId,
        'parts': ?parts == null ? null : [for (final p in parts) {'partNumber': p.partNumber, 'etag': p.etag}],
      },
    );
    return json['status']! as String;
  }

  Future<void> abortUpload(String memoryId, String assetId) => _send('POST', '/v1/memories/$memoryId/assets/$assetId/upload/abort');

  // ---- sync ----------------------------------------------------------------------------------

  Future<SyncPage> syncChanges({required int cursor, int limit = 100}) async {
    final json = await _json('GET', '/v1/sync/changes', query: {'cursor': '$cursor', 'limit': '$limit'});
    return SyncPage(
      changes: [for (final c in (json['items']! as List<Object?>).cast<Map<Object?, Object?>>()) SyncChange.fromJson(Map<String, Object?>.from(c))],
      nextCursor: (json['nextCursor']! as num).toInt(),
      hasMore: json['hasMore']! as bool,
    );
  }

  Future<List<ApiPreset>> presets() async {
    final json = await _json('GET', '/v1/presets');
    return [for (final p in (json['items']! as List<Object?>).cast<Map<Object?, Object?>>()) ApiPreset.fromJson(Map<String, Object?>.from(p))];
  }

  Future<ApiPreset> putPreset(
    String id, {
    required String name,
    required String experienceId,
    required Map<String, Object?> intent,
    String? profileId,
    int? profileVersion,
    required bool live,
    required String source,
  }) async => ApiPreset.fromJson(
    await _json(
      'PUT',
      '/v1/presets/$id',
      body: {
        'name': name,
        'experienceId': experienceId,
        'intent': intent,
        'profile': profileId == null ? null : {'id': profileId, 'version': profileVersion ?? 1},
        'live': live,
        'source': source,
      },
    ),
  );

  Future<void> deletePreset(String id) => _send('DELETE', '/v1/presets/$id');

  // ---- transport -----------------------------------------------------------------------------

  Future<Map<String, Object?>> _json(String method, String path, {Object? body, Map<String, String>? query, Map<String, String>? headers}) async =>
      _decodeObject(await _raw(method, path, body: body, query: query, headers: headers));

  Future<void> _send(String method, String path, {Object? body, bool authenticated = true}) async {
    await _raw(method, path, body: body, authenticated: authenticated);
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    return Map<String, Object?>.from(decoded as Map<Object?, Object?>);
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    final uri = baseUrl.replace(path: path, queryParameters: query);
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    request.headers.addAll(headers ?? const {});
    if (authenticated) {
      final token = await _token();
      if (token != null) {
        request.headers['authorization'] = 'Bearer $token';
      }
    }
    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      if (error is SocketException || error is http.ClientException || error is TimeoutException || error is HandshakeException || error is TlsException) {
        throw NetworkException(error);
      }
      rethrow;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    final exception = _toException(response);
    if (authenticated && exception.status == 401) {
      _unauthorized.add(null);
    }
    throw exception;
  }

  ApiException _toException(http.Response response) {
    var code = 'request.failed';
    var message = 'The request failed.';
    String? requestId;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<Object?, Object?>) {
        final envelope = decoded['error'];
        if (envelope is Map<Object?, Object?>) {
          code = envelope['code'] as String? ?? code;
          message = envelope['message'] as String? ?? message;
          requestId = envelope['requestId'] as String?;
        } else {
          code = decoded['code'] as String? ?? code;
          message = decoded['message'] as String? ?? message;
        }
      }
    } on FormatException {
      // Not JSON (a proxy error page): keep the generic code.
    }
    final retryAfterSeconds = int.tryParse(response.headers['retry-after'] ?? '');
    return ApiException(
      status: response.statusCode,
      code: code,
      message: message,
      requestId: requestId,
      retryAfter: retryAfterSeconds == null ? null : Duration(seconds: retryAfterSeconds),
    );
  }
}
