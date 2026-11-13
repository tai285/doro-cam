/// The Memory aggregate (docs/specs/memory-domain.md): Memory, Asset and CaptureMetadata with their invariants.
///
/// Pure Dart, shared by the local store and the sync layer. Invariants 1–3 and 7 are enforced by the
/// constructors and update methods here, mirroring the server's validation.
library;

import 'dart:math' as math;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/experience/preset.dart';

enum MemoryKind { photo, motion, video }

enum AssetRole {
  photoOriginal('photo_original'),
  photoRendered('photo_rendered'),
  photoDisplay('photo_display'),
  thumbnail('thumbnail'),
  motionClip('motion_clip'),
  motionWeb('motion_web'),
  videoOriginal('video_original'),
  sanitizedOriginal('sanitized_original');

  const AssetRole(this.wire);

  /// The name used by the API and the database.
  final String wire;

  static AssetRole? fromWire(Object? value) {
    for (final role in values) {
      if (role.wire == value) {
        return role;
      }
    }
    return null;
  }
}

/// Lifecycle: `pending → uploading → uploaded → verified → ready`, or `failed`.
enum AssetStatus { pending, uploading, uploaded, verified, ready, failed }

extension AssetStatusX on AssetStatus {
  /// Assets are immutable once uploaded (invariant 3).
  bool get isImmutable => this == AssetStatus.uploaded || this == AssetStatus.verified || this == AssetStatus.ready;
}

/// A device location. All fields are present or the Memory has no location (invariant 7).
class MemoryLocation {
  MemoryLocation({required this.lat, required this.lon, this.accuracyM, this.altitudeM}) {
    if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw InvariantViolation('Location must be a valid latitude (-90..90) and longitude (-180..180).');
    }
  }

  /// Builds a location only if both coordinates are given; one without the other violates invariant 7.
  static MemoryLocation? fromNullable({double? lat, double? lon, double? accuracyM, double? altitudeM}) {
    if (lat == null && lon == null) {
      return null;
    }
    if (lat == null || lon == null) {
      throw InvariantViolation('Latitude and longitude must both be present or both absent.');
    }
    return MemoryLocation(lat: lat, lon: lon, accuracyM: accuracyM, altitudeM: altitudeM);
  }

  final double lat;
  final double lon;
  final double? accuracyM;
  final double? altitudeM;

  Map<String, Object?> toJson() => <String, Object?>{
        'lat': lat,
        'lon': lon,
        if (accuracyM != null) 'accuracyM': accuracyM,
        if (altitudeM != null) 'altitudeM': altitudeM,
      };

  @override
  bool operator ==(Object other) =>
      other is MemoryLocation && other.lat == lat && other.lon == lon && other.accuracyM == accuracyM && other.altitudeM == altitudeM;

  @override
  int get hashCode => Object.hash(lat, lon, accuracyM, altitudeM);
}

/// The settings the device actually applied (CAM-050), plus what was requested where it differed.
class CaptureMetadata {
  const CaptureMetadata({
    this.deviceMake,
    this.deviceModel,
    this.platform,
    this.osVersion,
    this.appVersion,
    this.cameraId,
    this.lensKind,
    this.focalLengthMm,
    this.focalLength35mmEq,
    this.aperture,
    this.isoApplied,
    this.exposureTimeNsApplied,
    this.exposureBiasEv,
    this.whiteBalance,
    this.focusMode,
    this.focusDistanceDiopters,
    this.flash,
    this.zoomFactor,
    this.digitalZoom = false,
    this.hdr = false,
    this.format,
    this.widthPx,
    this.heightPx,
    this.requested,
    this.adjustments = const <Adjustment>[],
    this.synthetic = false,
  });

  final String? deviceMake;
  final String? deviceModel;
  final String? platform;
  final String? osVersion;
  final String? appVersion;
  final String? cameraId;
  final LensKind? lensKind;
  final double? focalLengthMm;
  final double? focalLength35mmEq;
  final double? aperture;
  final int? isoApplied;
  final int? exposureTimeNsApplied;
  final double? exposureBiasEv;
  final ResolvedWhiteBalance? whiteBalance;
  final FocusMode? focusMode;
  final double? focusDistanceDiopters;
  final FlashMode? flash;
  final double? zoomFactor;
  final bool digitalZoom;
  final bool hdr;
  final PhotoFormat? format;
  final int? widthPx;
  final int? heightPx;

  /// What the user asked for, when it differs from what was applied.
  final CaptureIntent? requested;
  final List<Adjustment> adjustments;

  /// True for the debug-only synthetic camera source, which must never claim to be hardware (ADR-0013).
  final bool synthetic;

  /// The map stored in `capture` (server jsonb and the local DB). Keys the server extracts for analytics
  /// (lensKind, focalLength35mmEq, aperture, isoApplied, exposureTimeNsApplied) use exactly these names.
  Map<String, Object?> toJson() => <String, Object?>{
        if (deviceMake != null) 'deviceMake': deviceMake,
        if (deviceModel != null) 'deviceModel': deviceModel,
        if (platform != null) 'platform': platform,
        if (osVersion != null) 'osVersion': osVersion,
        if (appVersion != null) 'appVersion': appVersion,
        if (cameraId != null) 'cameraId': cameraId,
        if (lensKind != null) 'lensKind': lensKind!.name,
        if (focalLengthMm != null) 'focalLengthMm': focalLengthMm,
        if (focalLength35mmEq != null) 'focalLength35mmEq': focalLength35mmEq,
        if (aperture != null) 'aperture': aperture,
        if (isoApplied != null) 'isoApplied': isoApplied,
        if (exposureTimeNsApplied != null) 'exposureTimeNsApplied': exposureTimeNsApplied,
        if (exposureBiasEv != null) 'exposureBiasEv': exposureBiasEv,
        if (whiteBalance != null)
          'whiteBalance': <String, Object?>{
            'mode': whiteBalance!.preset.name,
            if (whiteBalance!.kelvin != null) 'kelvin': whiteBalance!.kelvin,
          },
        if (focusMode != null)
          'focus': <String, Object?>{
            'mode': focusMode!.name,
            if (focusDistanceDiopters != null) 'distanceDiopters': focusDistanceDiopters,
          },
        if (flash != null) 'flash': flash!.name,
        if (zoomFactor != null) 'zoomFactor': zoomFactor,
        'digitalZoom': digitalZoom,
        'hdr': hdr,
        if (format != null) 'format': format!.name,
        if (widthPx != null) 'widthPx': widthPx,
        if (heightPx != null) 'heightPx': heightPx,
        if (requested != null) 'requested': requested!.toJson(),
        if (adjustments.isNotEmpty)
          'adjustments': <Map<String, Object?>>[
            for (final a in adjustments)
              <String, Object?>{
                'field': a.field.name,
                'requested': '${a.requested}',
                'applied': '${a.applied}',
                'reason': a.reason.name,
              },
          ],
        if (synthetic) 'synthetic': true,
      };

  factory CaptureMetadata.fromJson(Map<String, Object?> json) {
    T? named<T extends Enum>(List<T> values, Object? raw) {
      for (final value in values) {
        if (value.name == raw) {
          return value;
        }
      }
      return null;
    }

    double? number(Object? raw) => raw is num ? raw.toDouble() : null;
    int? integer(Object? raw) => raw is num && raw == raw.truncate() ? raw.toInt() : null;
    final wb = json['whiteBalance'];
    final focus = json['focus'];
    final requested = json['requested'];
    return CaptureMetadata(
      deviceMake: json['deviceMake'] as String?,
      deviceModel: json['deviceModel'] as String?,
      platform: json['platform'] as String?,
      osVersion: json['osVersion'] as String?,
      appVersion: json['appVersion'] as String?,
      cameraId: json['cameraId'] as String?,
      lensKind: named(LensKind.values, json['lensKind']),
      focalLengthMm: number(json['focalLengthMm']),
      focalLength35mmEq: number(json['focalLength35mmEq']),
      aperture: number(json['aperture']),
      isoApplied: integer(json['isoApplied']),
      exposureTimeNsApplied: integer(json['exposureTimeNsApplied']),
      exposureBiasEv: number(json['exposureBiasEv']),
      whiteBalance: wb is Map<String, Object?>
          ? ResolvedWhiteBalance(
              preset: named(WbPreset.values, wb['mode']) ?? WbPreset.auto,
              kelvin: integer(wb['kelvin']),
            )
          : null,
      focusMode: focus is Map<String, Object?> ? named(FocusMode.values, focus['mode']) : null,
      focusDistanceDiopters: focus is Map<String, Object?> ? number(focus['distanceDiopters']) : null,
      flash: named(FlashMode.values, json['flash']),
      zoomFactor: number(json['zoomFactor']),
      digitalZoom: json['digitalZoom'] == true,
      hdr: json['hdr'] == true,
      format: named(PhotoFormat.values, json['format']),
      widthPx: integer(json['widthPx']),
      heightPx: integer(json['heightPx']),
      requested: requested is Map<String, Object?> ? CaptureIntent.fromJson(requested) : null,
      synthetic: json['synthetic'] == true,
    );
  }
}

class Asset {
  Asset({
    required this.id,
    required this.memoryId,
    required this.role,
    required this.mime,
    required this.bytes,
    this.sha256,
    this.width,
    this.height,
    this.durationMs,
    this.status = AssetStatus.pending,
    this.localPath,
  }) {
    if (id.isEmpty || memoryId.isEmpty) {
      throw InvariantViolation('An asset needs an id and a Memory id.');
    }
    if (bytes < 0) {
      throw InvariantViolation('An asset cannot have a negative size.');
    }
    if (sha256 != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256!)) {
      throw InvariantViolation('sha256 must be 64 lowercase hexadecimal characters.');
    }
  }

  final String id;
  final String memoryId;
  final AssetRole role;
  final String mime;
  final int bytes;
  final String? sha256;
  final int? width;
  final int? height;
  final int? durationMs;
  final AssetStatus status;

  /// Device file path (not serialized to the server).
  final String? localPath;

  /// Moves through the lifecycle. Only forward steps (or → failed, or failed → pending for a retry) are legal.
  Asset withStatus(AssetStatus next) {
    final allowed = switch (status) {
      AssetStatus.pending => <AssetStatus>{AssetStatus.uploading, AssetStatus.failed, AssetStatus.verified, AssetStatus.ready},
      AssetStatus.uploading => <AssetStatus>{AssetStatus.uploaded, AssetStatus.failed, AssetStatus.pending},
      AssetStatus.uploaded => <AssetStatus>{AssetStatus.verified, AssetStatus.failed},
      AssetStatus.verified => <AssetStatus>{AssetStatus.ready},
      AssetStatus.ready => <AssetStatus>{},
      AssetStatus.failed => <AssetStatus>{AssetStatus.pending},
    };
    if (!allowed.contains(next)) {
      throw InvariantViolation('An asset cannot go from ${status.name} to ${next.name}.');
    }
    return _copy(status: next);
  }

  /// Replaces the file contents. Not allowed once uploaded: a changed rendering is a *new* asset (invariant 3).
  Asset withNewContent({required int bytes, required String sha256, String? localPath, int? width, int? height}) {
    if (status.isImmutable) {
      throw InvariantViolation('Asset $id is ${status.name} and cannot be modified; create a new asset instead.');
    }
    return Asset(
      id: id,
      memoryId: memoryId,
      role: role,
      mime: mime,
      bytes: bytes,
      sha256: sha256,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs,
      status: status,
      localPath: localPath ?? this.localPath,
    );
  }

  Asset _copy({AssetStatus? status}) => Asset(
        id: id,
        memoryId: memoryId,
        role: role,
        mime: mime,
        bytes: bytes,
        sha256: sha256,
        width: width,
        height: height,
        durationMs: durationMs,
        status: status ?? this.status,
        localPath: localPath,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'memoryId': memoryId,
        'role': role.wire,
        'mime': mime,
        'bytes': bytes,
        if (sha256 != null) 'sha256': sha256,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'durationMs': durationMs,
        'status': status.name,
      };

  @override
  bool operator ==(Object other) =>
      other is Asset &&
      other.id == id &&
      other.memoryId == memoryId &&
      other.role == role &&
      other.mime == mime &&
      other.bytes == bytes &&
      other.sha256 == sha256 &&
      other.width == width &&
      other.height == height &&
      other.durationMs == durationMs &&
      other.status == status &&
      other.localPath == localPath;

  @override
  int get hashCode => Object.hash(id, memoryId, role, mime, bytes, sha256, width, height, durationMs, status, localPath);
}

final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final RegExp _handle = RegExp(r'^[0-9A-Za-z]{22}$');

bool isUuid(String value) => _uuid.hasMatch(value);

/// A UUIDv7 (time-ordered) for client-generated ids (docs/specs/database.md).
String generateUuidV7({DateTime? now, math.Random? random}) {
  final rng = random ?? math.Random.secure();
  final ms = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  for (var i = 0; i < 6; i++) {
    bytes[i] = (ms >> (8 * (5 - i))) & 0xff;
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

const String _base62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// A 22-character random base62 public handle (MEM-008).
String generatePublicHandle({math.Random? random}) {
  final rng = random ?? math.Random.secure();
  return String.fromCharCodes(List<int>.generate(22, (_) => _base62.codeUnitAt(rng.nextInt(_base62.length))));
}

class Memory {
  Memory({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.capturedTz,
    required this.experienceId,
    required this.capture,
    required this.assets,
    required this.publicHandle,
    this.ownerId,
    this.profile,
    this.presetId,
    this.scenario,
    this.location,
    this.caption,
    this.favorite = false,
    this.aspectRatio,
    this.version = 1,
    this.deletedAt,
    this.tags = const <String>[],
  }) {
    final problems = validate();
    if (problems.isNotEmpty) {
      throw InvariantViolation(problems.join(' '));
    }
  }

  static const int maxCaptionLength = 2000;

  final String id;
  final String? ownerId;
  final MemoryKind kind;
  final DateTime capturedAt;
  final String capturedTz;
  final String experienceId;
  final ProfileRef? profile;
  final String? presetId;
  final String? scenario;
  final CaptureMetadata capture;
  final MemoryLocation? location;
  final String? caption;
  final bool favorite;
  final String? aspectRatio;
  final String publicHandle;
  final int version;
  final DateTime? deletedAt;
  final List<String> tags;
  final List<Asset> assets;

  bool get isTrashed => deletedAt != null;

  Asset? assetFor(AssetRole role) {
    for (final asset in assets) {
      if (asset.role == role) {
        return asset;
      }
    }
    return null;
  }

  /// Every broken invariant, as readable sentences (empty when valid). Invariants 1–3 and 7 of memory-domain.md.
  List<String> validate() {
    final problems = <String>[];
    if (!isUuid(id)) {
      problems.add('A Memory id must be a UUID.');
    }
    if (!_handle.hasMatch(publicHandle)) {
      problems.add('A public handle must be 22 base62 characters.');
    }
    if (capturedTz.trim().isEmpty) {
      problems.add('A Memory needs the time zone it was captured in.');
    }
    if (caption != null && caption!.length > maxCaptionLength) {
      problems.add('A caption may be at most $maxCaptionLength characters.');
    }
    if (assets.any((asset) => asset.memoryId != id)) {
      problems.add('Every asset must belong to this Memory.');
    }
    final roles = <AssetRole, int>{};
    for (final asset in assets) {
      roles[asset.role] = (roles[asset.role] ?? 0) + 1;
    }
    if (roles.values.any((count) => count > 1)) {
      problems.add('A Memory may have only one asset per role.');
    }
    // Invariant 1: exactly one original of the right kind.
    final originals = kind == MemoryKind.video ? roles[AssetRole.videoOriginal] ?? 0 : roles[AssetRole.photoOriginal] ?? 0;
    if (originals != 1) {
      problems.add(kind == MemoryKind.video
          ? 'A video Memory needs exactly one video_original asset.'
          : 'A photo or motion Memory needs exactly one photo_original asset.');
    }
    if (kind == MemoryKind.video && (roles[AssetRole.photoOriginal] ?? 0) > 0) {
      problems.add('A video Memory has no photo_original asset.');
    }
    if (kind != MemoryKind.video && (roles[AssetRole.videoOriginal] ?? 0) > 0) {
      problems.add('Only a video Memory has a video_original asset.');
    }
    // Invariant 2: motion ⇔ exactly one motion_clip.
    final clips = roles[AssetRole.motionClip] ?? 0;
    if (kind == MemoryKind.motion && clips != 1) {
      problems.add('A motion Memory needs exactly one motion_clip asset.');
    }
    if (kind != MemoryKind.motion && clips != 0) {
      problems.add('Only a motion Memory has a motion_clip asset.');
    }
    return problems;
  }

  Memory _copy({
    String? ownerId,
    List<Asset>? assets,
    String? caption,
    bool clearCaption = false,
    bool? favorite,
    MemoryLocation? location,
    bool clearLocation = false,
    DateTime? deletedAt,
    bool clearDeleted = false,
    int? version,
    List<String>? tags,
  }) =>
      Memory(
        id: id,
        ownerId: ownerId ?? this.ownerId,
        kind: kind,
        capturedAt: capturedAt,
        capturedTz: capturedTz,
        experienceId: experienceId,
        profile: profile,
        presetId: presetId,
        scenario: scenario,
        capture: capture,
        location: clearLocation ? null : (location ?? this.location),
        caption: clearCaption ? null : (caption ?? this.caption),
        favorite: favorite ?? this.favorite,
        aspectRatio: aspectRatio,
        publicHandle: publicHandle,
        version: version ?? this.version,
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
        tags: tags ?? this.tags,
        assets: assets ?? this.assets,
      );

  Memory withCaption(String? text) => text == null || text.trim().isEmpty
      ? _copy(clearCaption: true, version: version + 1)
      : _copy(caption: text.trim(), version: version + 1);

  Memory withFavorite(bool value) => _copy(favorite: value, version: version + 1);

  /// Removes the location (PRIV-001). All three location fields go together (invariant 7).
  Memory withoutLocation() => _copy(clearLocation: true, version: version + 1);

  Memory trashed(DateTime when) => _copy(deletedAt: when, version: version + 1);

  Memory restored() => _copy(clearDeleted: true, version: version + 1);

  Memory withOwner(String owner) => _copy(ownerId: owner);

  /// Replaces one asset by id. Fails if the existing asset is already uploaded (invariant 3).
  Memory withUpdatedAsset(Asset updated) {
    final existing = assets.where((asset) => asset.id == updated.id).toList();
    if (existing.isEmpty) {
      throw InvariantViolation('Asset ${updated.id} is not part of this Memory.');
    }
    final current = existing.single;
    if (current.status.isImmutable && (current.sha256 != updated.sha256 || current.bytes != updated.bytes)) {
      throw InvariantViolation('Asset ${current.id} is ${current.status.name} and cannot be modified.');
    }
    return _copy(assets: <Asset>[for (final asset in assets) asset.id == updated.id ? updated : asset]);
  }

  /// The overall sync state for the library badge (LIB-004).
  SyncState get syncState {
    if (assets.any((asset) => asset.status == AssetStatus.failed)) {
      return SyncState.failed;
    }
    if (assets.every((asset) => asset.status == AssetStatus.verified || asset.status == AssetStatus.ready)) {
      return SyncState.synced;
    }
    if (assets.any((asset) => asset.status == AssetStatus.uploading || asset.status == AssetStatus.uploaded)) {
      return SyncState.uploading;
    }
    return SyncState.localOnly;
  }

  /// The body of `PUT /v1/memories/{id}` (docs/specs/api.md): the immutable fields plus initial metadata.
  Map<String, Object?> toRegisterJson() => <String, Object?>{
        'kind': kind.name,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'capturedTz': capturedTz,
        'experienceId': experienceId,
        if (profile != null) 'profile': profile!.toJson(),
        if (presetId != null) 'presetId': presetId,
        if (scenario != null) 'scenario': scenario,
        'capture': capture.toJson(),
        if (location != null)
          'location': <String, Object?>{
            'lat': location!.lat,
            'lon': location!.lon,
            if (location!.accuracyM != null) 'accuracyM': location!.accuracyM,
          },
        if (caption != null) 'caption': caption,
        'favorite': favorite,
        if (aspectRatio != null) 'aspectRatio': aspectRatio,
      };

  @override
  bool operator ==(Object other) => other is Memory && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

enum SyncState { localOnly, uploading, synced, failed }
