// ignore_for_file: prefer_initializing_formals, use_null_aware_elements
import 'dart:async';
import 'dart:convert';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Remote-only features (albums, trips, insights). Everything else goes through the local-first data layer;
/// these screens need the server by nature (other people, aggregates) and say so when offline.
@immutable
class AlbumDto {
  const AlbumDto({
    required this.id,
    required this.title,
    required this.kind,
    required this.role,
    required this.memberCount,
    required this.itemCount,
    required this.allowOriginalDownload,
    required this.shareLocation,
    required this.autoAddDuringTrip,
    this.description,
    this.startsOn,
    this.endsOn,
  });

  factory AlbumDto.fromJson(Map<String, Object?> j) => AlbumDto(
    id: j['id']! as String,
    title: j['title']! as String,
    kind: j['kind']! as String,
    role: j['role']! as String,
    memberCount: (j['memberCount']! as num).toInt(),
    itemCount: (j['itemCount']! as num).toInt(),
    allowOriginalDownload: j['allowOriginalDownload']! as bool,
    shareLocation: j['shareLocation']! as bool,
    autoAddDuringTrip: j['autoAddDuringTrip']! as bool,
    description: j['description'] as String?,
    startsOn: j['startsOn'] as String?,
    endsOn: j['endsOn'] as String?,
  );

  final String id;
  final String title;
  final String kind;
  final String role;
  final int memberCount;
  final int itemCount;
  final bool allowOriginalDownload;
  final bool shareLocation;
  final bool autoAddDuringTrip;
  final String? description;
  final String? startsOn;
  final String? endsOn;

  bool get isTrip => kind == 'trip';
  bool get canEdit => role == 'owner' || role == 'editor';
  bool get canAdd => role != 'viewer';
  bool get isOwner => role == 'owner';
}

@immutable
class AlbumMemberDto {
  const AlbumMemberDto({
    required this.userId,
    required this.name,
    required this.role,
  });

  factory AlbumMemberDto.fromJson(Map<String, Object?> j) => AlbumMemberDto(
    userId: j['userId']! as String,
    name: j['name']! as String,
    role: j['role']! as String,
  );

  final String userId;
  final String name;
  final String role;
}

@immutable
class AlbumDetail {
  const AlbumDetail({required this.album, required this.members});
  final AlbumDto album;
  final List<AlbumMemberDto> members;
}

@immutable
class AlbumMemoryDto {
  const AlbumMemoryDto({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.isOwner,
    this.caption,
    this.thumbnailUrl,
  });

  factory AlbumMemoryDto.fromJson(Map<String, Object?> j) {
    final thumb = j['thumbnail'];
    return AlbumMemoryDto(
      id: j['id']! as String,
      kind: j['kind']! as String,
      capturedAt: DateTime.parse(j['capturedAt']! as String),
      isOwner: j['isOwner']! as bool,
      caption: j['caption'] as String?,
      thumbnailUrl: thumb is Map<Object?, Object?>
          ? thumb['url'] as String?
          : null,
    );
  }

  final String id;
  final String kind;
  final DateTime capturedAt;
  final bool isOwner;
  final String? caption;

  /// Presigned, or a path on the API origin for sanitized media.
  final String? thumbnailUrl;
}

@immutable
class BucketDto {
  const BucketDto(this.label, this.count, this.share);
  factory BucketDto.fromJson(Map<String, Object?> j) => BucketDto(
    j['label']! as String,
    (j['count']! as num).toInt(),
    (j['share']! as num).toDouble(),
  );
  final String label;
  final int count;
  final double share;
}

@immutable
class InsightsDto {
  const InsightsDto({
    required this.total,
    required this.distributions,
    required this.trend,
    required this.findings,
  });

  factory InsightsDto.fromJson(Map<String, Object?> j) {
    List<BucketDto> buckets(String key) {
      final dist = j[key];
      if (dist is! Map<Object?, Object?>) {
        return const <BucketDto>[];
      }
      return <BucketDto>[
        for (final b in dist['buckets']! as List<Object?>)
          BucketDto.fromJson(
            Map<String, Object?>.from(b! as Map<Object?, Object?>),
          ),
      ];
    }

    const keys = <String, String>{
      'focalLength': 'Focal length',
      'lens': 'Lens',
      'profile': 'Look',
      'experience': 'Experience',
      'iso': 'ISO',
      'shutter': 'Shutter speed',
      'aperture': 'Aperture',
      'timeOfDay': 'Time of day',
    };
    return InsightsDto(
      total: (j['total']! as num).toInt(),
      distributions: <String, List<BucketDto>>{
        for (final e in keys.entries) e.value: buckets(e.key),
      },
      trend: <(String, int)>[
        for (final t in j['trend']! as List<Object?>)
          (
            (t! as Map<Object?, Object?>)['month']! as String,
            ((t as Map<Object?, Object?>)['count']! as num).toInt(),
          ),
      ],
      findings: <(String, String)>[
        for (final f in j['insights']! as List<Object?>)
          (
            (f! as Map<Object?, Object?>)['id']! as String,
            (f as Map<Object?, Object?>)['text']! as String,
          ),
      ],
    );
  }

  final int total;
  final Map<String, List<BucketDto>> distributions;
  final List<(String, int)> trend;
  final List<(String id, String text)> findings;
}

@immutable
class SuggestionDto {
  const SuggestionDto({
    required this.patternKey,
    required this.title,
    required this.explanation,
    required this.supportingCount,
    required this.of,
  });

  factory SuggestionDto.fromJson(Map<String, Object?> j) => SuggestionDto(
    patternKey: j['patternKey']! as String,
    title: j['title']! as String,
    explanation: j['explanation']! as String,
    supportingCount: (j['supportingCount']! as num).toInt(),
    of: (j['of']! as num).toInt(),
  );

  final String patternKey;
  final String title;
  final String explanation;
  final int supportingCount;
  final int of;
}

class RemoteApi {
  RemoteApi({
    required this.baseUrl,
    required http.Client client,
    required TokenStore tokens,
  }) : _http = client,
       _tokens = tokens;

  final Uri baseUrl;
  final http.Client _http;
  final TokenStore _tokens;

  Future<Object?> _call(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(
      method,
      baseUrl.replace(path: path, queryParameters: query),
    );
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final token = await _tokens.read();
    if (token != null) {
      request.headers['authorization'] = 'Bearer $token';
    }
    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 30)),
      );
    } on Object catch (error) {
      throw NetworkException(error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var code = 'request.failed';
      var message = 'The request failed.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<Object?, Object?> &&
            decoded['error'] is Map<Object?, Object?>) {
          final error = decoded['error']! as Map<Object?, Object?>;
          code = error['code'] as String? ?? code;
          message = error['message'] as String? ?? message;
        }
      } on FormatException {
        // keep the generic message
      }
      throw ApiException(
        status: response.statusCode,
        code: code,
        message: message,
      );
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Map<String, Object?> _obj(Object? value) =>
      Map<String, Object?>.from(value! as Map<Object?, Object?>);

  Future<List<AlbumDto>> albums() async => <AlbumDto>[
    for (final a
        in _obj(await _call('GET', '/v1/albums'))['items']! as List<Object?>)
      AlbumDto.fromJson(_obj(a)),
  ];

  Future<AlbumDto> createAlbum({
    required String title,
    bool trip = false,
    String? startsOn,
    String? endsOn,
  }) async => AlbumDto.fromJson(
    _obj(
      await _call(
        'POST',
        '/v1/albums',
        body: <String, Object?>{
          'title': title,
          'kind': trip ? 'trip' : 'album',
          if (trip) 'startsOn': startsOn,
          if (trip) 'endsOn': endsOn,
        },
      ),
    ),
  );

  Future<AlbumDetail> album(String id) async {
    final json = _obj(await _call('GET', '/v1/albums/$id'));
    return AlbumDetail(
      album: AlbumDto.fromJson(_obj(json['album'])),
      members: <AlbumMemberDto>[
        for (final m in json['members']! as List<Object?>)
          AlbumMemberDto.fromJson(_obj(m)),
      ],
    );
  }

  Future<AlbumDto> patchAlbum(String id, Map<String, Object?> fields) async =>
      AlbumDto.fromJson(
        _obj(await _call('PATCH', '/v1/albums/$id', body: fields)),
      );

  Future<void> deleteAlbum(String id) => _call('DELETE', '/v1/albums/$id');

  Future<List<AlbumMemoryDto>> albumMemories(String id) async =>
      <AlbumMemoryDto>[
        for (final m
            in _obj(await _call('GET', '/v1/albums/$id/memories'))['items']!
                as List<Object?>)
          AlbumMemoryDto.fromJson(_obj(m)),
      ];

  Future<int> addToAlbum(String id, List<String> memoryIds) async =>
      (_obj(
                await _call(
                  'POST',
                  '/v1/albums/$id/items',
                  body: <String, Object?>{'memoryIds': memoryIds},
                ),
              )['added']!
              as num)
          .toInt();

  Future<void> removeFromAlbum(String id, String memoryId) =>
      _call('DELETE', '/v1/albums/$id/items/$memoryId');

  Future<List<String>> tripProposals(String id) async => <String>[
    for (final m
        in _obj(
              await _call('GET', '/v1/albums/$id/trip-proposals'),
            )['memoryIds']!
            as List<Object?>)
      m! as String,
  ];

  /// Returns the one-time invite token.
  Future<String> createInvite(
    String id, {
    required String role,
    String? email,
  }) async =>
      _obj(
            await _call(
              'POST',
              '/v1/albums/$id/invites',
              body: <String, Object?>{
                'role': role,
                if (email != null) 'email': email,
              },
            ),
          )['token']!
          as String;

  Future<String> acceptInvite(String token) async =>
      _obj(
            await _call(
              'POST',
              '/v1/invites/accept',
              body: <String, Object?>{'token': token},
            ),
          )['albumId']!
          as String;

  Future<void> changeRole(String id, String userId, String role) => _call(
    'PATCH',
    '/v1/albums/$id/members/$userId',
    body: <String, Object?>{'role': role},
  );

  Future<void> removeMember(String id, String userId) =>
      _call('DELETE', '/v1/albums/$id/members/$userId');

  Future<InsightsDto> insights() async =>
      InsightsDto.fromJson(_obj(await _call('GET', '/v1/insights/summary')));

  Future<List<SuggestionDto>> suggestions() async => <SuggestionDto>[
    for (final s
        in _obj(await _call('GET', '/v1/insights/preset-suggestions'))['items']!
            as List<Object?>)
      SuggestionDto.fromJson(_obj(s)),
  ];

  Future<void> dismissSuggestion(String key) =>
      _call('POST', '/v1/insights/preset-suggestions/$key/dismiss');

  Future<String> acceptSuggestion(String key, {String? name}) async =>
      _obj(
            await _call(
              'POST',
              '/v1/insights/preset-suggestions/$key/accept',
              body: <String, Object?>{if (name != null) 'name': name},
            ),
          )['presetId']!
          as String;

  void close() => _http.close();
}

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final remoteApiProvider = Provider<RemoteApi>(
  (ref) => RemoteApi(
    baseUrl: ref.watch(apiBaseProvider),
    client: ref.watch(httpClientProvider),
    tokens: ref.watch(tokenStoreProvider),
  ),
);
