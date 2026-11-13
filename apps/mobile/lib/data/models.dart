// ignore_for_file: prefer_initializing_formals
import 'package:doro_cam/data/db/app_database.dart';
import 'package:meta/meta.dart';

/// Memory kinds (docs/specs/memory-domain.md).
abstract final class MemoryKinds {
  static const photo = 'photo';
  static const motion = 'motion';
  static const video = 'video';
}

/// Asset roles the device produces and uploads (docs/architecture/media-pipeline.md).
abstract final class AssetRoles {
  static const photoOriginal = 'photo_original';
  static const photoRendered = 'photo_rendered';
  static const photoDisplay = 'photo_display';
  static const thumbnail = 'thumbnail';
  static const motionClip = 'motion_clip';
  static const videoOriginal = 'video_original';

  /// Upload order: renderings and thumbnails first so the Memory appears on the web quickly,
  /// then the heavy originals (docs/architecture/sync.md "Order").
  static const uploadPriority = [thumbnail, photoDisplay, photoRendered, photoOriginal, motionClip, videoOriginal];

  static int priority(String role) {
    final index = uploadPriority.indexOf(role);
    return index < 0 ? uploadPriority.length : index;
  }
}

/// The persisted upload state machine (docs/architecture/sync.md).
abstract final class UploadStates {
  static const pending = 'pending';
  static const registering = 'registering';
  static const uploading = 'uploading';
  static const completing = 'completing';
  static const verifying = 'verifying';
  static const synced = 'synced';
  static const backoff = 'backoff';
  static const failedPermanent = 'failed_permanent';

  static const active = {pending, registering, uploading, completing, verifying, backoff};
}

/// What the library shows per Memory (LIB-004).
enum SyncStatus {
  /// Not signed in, or nothing queued: the Memory exists only on this device.
  localOnly,
  uploading,
  synced,
  failed,
}

/// A Memory with its assets and derived sync status, as the library consumes it.
@immutable
class MemoryView {
  const MemoryView({required this.memory, required this.assets, required this.status});

  final MemoryRow memory;
  final List<AssetRow> assets;
  final SyncStatus status;

  AssetRow? asset(String role) {
    for (final asset in assets) {
      if (asset.role == role) {
        return asset;
      }
    }
    return null;
  }

  /// The best local image for a grid cell: thumbnail, then display, then rendered, then original.
  AssetRow? get thumbnail =>
      asset(AssetRoles.thumbnail) ?? asset(AssetRoles.photoDisplay) ?? asset(AssetRoles.photoRendered) ?? asset(AssetRoles.photoOriginal);

  bool get isTrashed => memory.deletedAt != null;
}

/// A file the capture pipeline produced, still at its temporary location.
@immutable
class DraftAsset {
  const DraftAsset({
    required this.role,
    required this.path,
    required this.mime,
    this.width,
    this.height,
    this.durationMs,
  });

  final String role;
  final String path;
  final String mime;
  final int? width;
  final int? height;
  final int? durationMs;
}

/// Everything needed to turn a finished capture into a durable Memory (MEM-001, MEM-002).
@immutable
class CaptureDraft {
  const CaptureDraft({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.capturedTz,
    required this.experienceId,
    required this.capture,
    required this.assets,
    this.profileId,
    this.profileVersion,
    this.presetId,
    this.scenario,
    this.lat,
    this.lon,
    this.locationAccuracyM,
    this.aspectRatio,
    this.caption,
  });

  final String id;
  final String kind;
  final DateTime capturedAt;
  final String capturedTz;
  final String experienceId;
  final Map<String, Object?> capture;
  final List<DraftAsset> assets;
  final String? profileId;
  final int? profileVersion;
  final String? presetId;
  final String? scenario;
  final double? lat;
  final double? lon;
  final double? locationAccuracyM;
  final String? aspectRatio;
  final String? caption;
}

/// Invalid input to the capture use case (an invariant of docs/specs/memory-domain.md).
class CaptureException implements Exception {
  const CaptureException(this.message);
  final String message;

  @override
  String toString() => 'CaptureException: $message';
}
