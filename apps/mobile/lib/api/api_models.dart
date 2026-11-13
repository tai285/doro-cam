// ignore_for_file: prefer_initializing_formals
import 'package:meta/meta.dart';

/// Wire types of services/api (packages/api-contract/openapi.json). Only the fields the app uses.

@immutable
class ApiAsset {
  const ApiAsset({
    required this.id,
    required this.role,
    required this.status,
    required this.mime,
    required this.bytes,
    this.width,
    this.height,
    this.durationMs,
    this.failureReason,
  });

  factory ApiAsset.fromJson(Map<String, Object?> json) => ApiAsset(
    id: json['id']! as String,
    role: json['role']! as String,
    status: json['status']! as String,
    mime: json['mime']! as String,
    bytes: (json['bytes']! as num).toInt(),
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    durationMs: (json['durationMs'] as num?)?.toInt(),
    failureReason: json['failureReason'] as String?,
  );

  final String id;
  final String role;

  /// pending | uploading | uploaded | verified | ready | failed
  final String status;
  final String mime;
  final int bytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? failureReason;

  bool get isServable => status == 'verified' || status == 'ready';
}

@immutable
class ApiMemory {
  const ApiMemory({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.capturedAt,
    required this.capturedTz,
    required this.experienceId,
    required this.capture,
    required this.favorite,
    required this.version,
    required this.assets,
    this.profileId,
    this.profileVersion,
    this.presetId,
    this.scenario,
    this.lat,
    this.lon,
    this.locationAccuracyM,
    this.locationShared = false,
    this.caption,
    this.aspectRatio,
    this.publicHandle,
    this.deletedAt,
    this.isOwner = true,
  });

  factory ApiMemory.fromJson(Map<String, Object?> json) {
    final profile = json['profile'] as Map<String, Object?>?;
    final location = json['location'] as Map<String, Object?>?;
    return ApiMemory(
      id: json['id']! as String,
      ownerId: json['ownerId']! as String,
      kind: json['kind']! as String,
      capturedAt: DateTime.parse(json['capturedAt']! as String).toUtc(),
      capturedTz: json['capturedTz']! as String,
      experienceId: json['experienceId']! as String,
      profileId: profile?['id'] as String?,
      profileVersion: (profile?['version'] as num?)?.toInt(),
      presetId: json['presetId'] as String?,
      scenario: json['scenario'] as String?,
      capture: Map<String, Object?>.from(json['capture']! as Map<Object?, Object?>),
      lat: (location?['lat'] as num?)?.toDouble(),
      lon: (location?['lon'] as num?)?.toDouble(),
      locationAccuracyM: (location?['accuracyM'] as num?)?.toDouble(),
      locationShared: json['locationShared'] as bool? ?? false,
      caption: json['caption'] as String?,
      favorite: json['favorite']! as bool,
      aspectRatio: json['aspectRatio'] as String?,
      publicHandle: json['publicHandle'] as String?,
      version: (json['version']! as num).toInt(),
      deletedAt: json['deletedAt'] == null ? null : DateTime.parse(json['deletedAt']! as String).toUtc(),
      isOwner: json['isOwner'] as bool? ?? true,
      assets: [for (final a in (json['assets']! as List<Object?>)) ApiAsset.fromJson(Map<String, Object?>.from(a! as Map<Object?, Object?>))],
    );
  }

  final String id;
  final String ownerId;
  final String kind;
  final DateTime capturedAt;
  final String capturedTz;
  final String experienceId;
  final String? profileId;
  final int? profileVersion;
  final String? presetId;
  final String? scenario;
  final Map<String, Object?> capture;
  final double? lat;
  final double? lon;
  final double? locationAccuracyM;
  final bool locationShared;
  final String? caption;
  final bool favorite;
  final String? aspectRatio;
  final String? publicHandle;
  final int version;
  final DateTime? deletedAt;
  final bool isOwner;
  final List<ApiAsset> assets;

  ApiAsset? asset(String id) {
    for (final asset in assets) {
      if (asset.id == id) {
        return asset;
      }
    }
    return null;
  }
}

/// The body of `PUT /v1/memories/{id}` (upload-sync.md step 1).
@immutable
class RegisterMemory {
  const RegisterMemory({
    required this.kind,
    required this.capturedAt,
    required this.capturedTz,
    required this.experienceId,
    required this.capture,
    this.profileId,
    this.profileVersion,
    this.presetId,
    this.scenario,
    this.lat,
    this.lon,
    this.locationAccuracyM,
    this.caption,
    this.favorite = false,
    this.aspectRatio,
  });

  final String kind;
  final DateTime capturedAt;
  final String capturedTz;
  final String experienceId;
  final Map<String, Object?> capture;
  final String? profileId;
  final int? profileVersion;
  final String? presetId;
  final String? scenario;
  final double? lat;
  final double? lon;
  final double? locationAccuracyM;
  final String? caption;
  final bool favorite;
  final String? aspectRatio;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'capturedTz': capturedTz,
    'experienceId': experienceId,
    if (profileId != null) 'profile': {'id': profileId, 'version': profileVersion ?? 1},
    if (presetId != null) 'presetId': presetId,
    if (scenario != null) 'scenario': scenario,
    'capture': capture,
    if (lat != null && lon != null) 'location': {'lat': lat, 'lon': lon, if (locationAccuracyM != null) 'accuracyM': locationAccuracyM},
    if (caption != null) 'caption': caption,
    'favorite': favorite,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
  };
}

/// Result of registering a Memory.
@immutable
class RegisterResult {
  const RegisterResult({required this.memory, required this.created});
  final ApiMemory memory;
  final bool created;
}

@immutable
class CreateUpload {
  const CreateUpload({
    required this.role,
    required this.mime,
    required this.bytes,
    required this.sha256,
    this.width,
    this.height,
    this.durationMs,
  });

  final String role;
  final String mime;
  final int bytes;
  final String sha256;
  final int? width;
  final int? height;
  final int? durationMs;

  Map<String, Object?> toJson() => {
    'role': role,
    'mime': mime,
    'bytes': bytes,
    'sha256': sha256,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'durationMs': durationMs,
  };
}

/// The server's answer to "create or resume an upload" (upload-sync.md step 2).
sealed class UploadPlan {
  const UploadPlan();

  factory UploadPlan.fromJson(Map<String, Object?> json) {
    switch (json['mode']) {
      case 'complete':
        return CompleteUploadPlan(deduplicated: json['deduplicated'] as bool? ?? false);
      case 'single':
        return SingleUploadPlan(
          url: Uri.parse(json['url']! as String),
          headers: Map<String, String>.from(json['headers']! as Map<Object?, Object?>),
          expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
        );
      case 'multipart':
        return MultipartUploadPlan(
          uploadId: json['uploadId']! as String,
          partSize: (json['partSize']! as num).toInt(),
          partCount: (json['partCount']! as num).toInt(),
          expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
          parts: {
            for (final part in (json['parts']! as List<Object?>).cast<Map<Object?, Object?>>())
              (part['partNumber']! as num).toInt(): Uri.parse(part['url']! as String),
          },
          completed: {
            for (final part in (json['completed']! as List<Object?>).cast<Map<Object?, Object?>>())
              (part['partNumber']! as num).toInt(): part['etag']! as String,
          },
        );
      default:
        throw FormatException('Unknown upload mode: ${json['mode']}');
    }
  }
}

/// The asset is already stored (verified earlier, or deduplicated against identical bytes).
class CompleteUploadPlan extends UploadPlan {
  const CompleteUploadPlan({required this.deduplicated});
  final bool deduplicated;
}

/// Presigned PUT for the whole file (up to 16 MiB).
class SingleUploadPlan extends UploadPlan {
  const SingleUploadPlan({required this.url, required this.headers, required this.expiresAt});
  final Uri url;
  final Map<String, String> headers;
  final DateTime expiresAt;
}

/// Multipart: fresh URLs for the parts not yet completed, plus the ETags of those that are.
class MultipartUploadPlan extends UploadPlan {
  const MultipartUploadPlan({
    required this.uploadId,
    required this.partSize,
    required this.partCount,
    required this.expiresAt,
    required this.parts,
    required this.completed,
  });

  final String uploadId;
  final int partSize;
  final int partCount;
  final DateTime expiresAt;

  /// partNumber -> presigned URL, only for parts still to upload.
  final Map<int, Uri> parts;

  /// partNumber -> ETag, for parts storage already has.
  final Map<int, String> completed;
}

@immutable
class SyncChange {
  const SyncChange({required this.seq, required this.entity, required this.entityId, required this.op});

  factory SyncChange.fromJson(Map<String, Object?> json) => SyncChange(
    seq: (json['seq']! as num).toInt(),
    entity: json['entity']! as String,
    entityId: json['entityId']! as String,
    op: json['op']! as String,
  );

  final int seq;

  /// memory | asset | preset | album
  final String entity;
  final String entityId;

  /// upsert | delete
  final String op;
}

@immutable
class SyncPage {
  const SyncPage({required this.changes, required this.nextCursor, required this.hasMore});
  final List<SyncChange> changes;
  final int nextCursor;
  final bool hasMore;
}

@immutable
class ApiPreset {
  const ApiPreset({
    required this.id,
    required this.name,
    required this.experienceId,
    required this.intent,
    required this.live,
    required this.source,
    required this.version,
    this.profileId,
    this.profileVersion,
  });

  factory ApiPreset.fromJson(Map<String, Object?> json) {
    final profile = json['profile'] as Map<String, Object?>?;
    return ApiPreset(
      id: json['id']! as String,
      name: json['name']! as String,
      experienceId: json['experienceId']! as String,
      intent: Map<String, Object?>.from(json['intent']! as Map<Object?, Object?>),
      profileId: profile?['id'] as String?,
      profileVersion: (profile?['version'] as num?)?.toInt(),
      live: json['live']! as bool,
      source: json['source']! as String,
      version: (json['version']! as num).toInt(),
    );
  }

  final String id;
  final String name;
  final String experienceId;
  final Map<String, Object?> intent;
  final String? profileId;
  final int? profileVersion;
  final bool live;
  final String source;
  final int version;
}

@immutable
class Account {
  const Account({
    required this.id,
    required this.email,
    required this.name,
    required this.emailVerified,
    required this.usedBytes,
    required this.quotaBytes,
    this.deletionScheduledFor,
  });

  factory Account.fromJson(Map<String, Object?> json) {
    final storage = json['storage']! as Map<Object?, Object?>;
    return Account(
      id: json['id']! as String,
      email: json['email']! as String,
      name: json['name']! as String,
      emailVerified: json['emailVerified']! as bool,
      usedBytes: (storage['usedBytes']! as num).toInt(),
      quotaBytes: (storage['quotaBytes']! as num).toInt(),
      deletionScheduledFor: json['deletionScheduledFor'] == null ? null : DateTime.parse(json['deletionScheduledFor']! as String).toUtc(),
    );
  }

  final String id;
  final String email;
  final String name;
  final bool emailVerified;
  final int usedBytes;
  final int quotaBytes;
  final DateTime? deletionScheduledFor;
}

@immutable
class DeviceSession {
  const DeviceSession({required this.id, required this.current, required this.createdAt, this.userAgent});

  factory DeviceSession.fromJson(Map<String, Object?> json) => DeviceSession(
    id: json['id']! as String,
    current: json['current']! as bool,
    userAgent: json['userAgent'] as String?,
    createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
  );

  final String id;
  final bool current;
  final String? userAgent;
  final DateTime createdAt;
}
