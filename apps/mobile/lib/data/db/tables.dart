// ignore_for_file: prefer_initializing_formals
import 'package:drift/drift.dart';

/// Local Memory records. The local database is the source of truth on the device
/// (docs/architecture/sync.md). Times are UTC epoch milliseconds.
@DataClassName('MemoryRow')
class Memories extends Table {
  /// Client-generated UUIDv7, immutable.
  TextColumn get id => text()();

  /// `photo` | `motion` | `video`.
  TextColumn get kind => text()();
  IntColumn get capturedAt => integer()();
  TextColumn get capturedTz => text()();
  TextColumn get experienceId => text()();
  TextColumn get profileId => text().nullable()();
  IntColumn get profileVersion => integer().nullable()();
  TextColumn get presetId => text().nullable()();
  TextColumn get scenario => text().nullable()();

  /// The settings actually applied by the device (CAM-050), as JSON.
  TextColumn get captureJson => text()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  RealColumn get locationAccuracyM => real().nullable()();
  BoolColumn get locationShared => boolean().withDefault(const Constant(false))();
  TextColumn get caption => text().nullable()();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  TextColumn get aspectRatio => text().nullable()();

  /// Server-assigned, null until the Memory has been registered.
  TextColumn get publicHandle => text().nullable()();
  IntColumn get serverVersion => integer().nullable()();

  /// The account that owns this Memory. Null while the device is anonymous (AUTH-005).
  TextColumn get accountId => text().nullable()();

  /// Whether the server knows this Memory (the register call succeeded).
  BoolColumn get registered => boolean().withDefault(const Constant(false))();

  /// False for Memories that arrived from the server and have no local originals.
  BoolColumn get capturedHere => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  /// Trash (MEM-007). Purged 30 days later.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => const [];
}

/// Files belonging to Memories. Immutable once written.
@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get memoryId => text().references(Memories, #id, onDelete: KeyAction.cascade)();

  /// photo_original, photo_rendered, photo_display, thumbnail, motion_clip, video_original, ...
  TextColumn get role => text()();

  /// Null for assets that only exist on the server.
  TextColumn get localPath => text().nullable()();
  IntColumn get bytes => integer()();

  /// Lowercase hex SHA-256.
  TextColumn get sha256 => text()();
  TextColumn get mime => text()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();

  /// pending | uploading | synced | failed (summary of the upload job, for LIB-004).
  TextColumn get uploadState => text().withDefault(const Constant('pending'))();

  /// The server's view of this asset's status, when known.
  TextColumn get serverStatus => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Durable upload queue: one row per asset (docs/architecture/sync.md "Upload state machine").
@DataClassName('UploadJobRow')
class UploadJobs extends Table {
  TextColumn get assetId => text().references(Assets, #id, onDelete: KeyAction.cascade)();

  /// Uploads never cross accounts (upload-sync.md "Account switch").
  TextColumn get accountId => text()();

  /// pending | registering | uploading | completing | verifying | synced | backoff | failed_permanent
  TextColumn get state => text()();

  /// The state to return to when a backoff timer fires.
  TextColumn get resumeState => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();
  TextColumn get serverUploadId => text().nullable()();
  IntColumn get partSize => integer().nullable()();
  IntColumn get partCount => integer().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get lastErrorCode => text().nullable()();

  /// How many times the server reported a checksum mismatch (permanent failure at 3).
  IntColumn get checksumFailures => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

/// Multipart progress. A part with an ETag is complete.
@DataClassName('UploadPartRow')
class UploadParts extends Table {
  TextColumn get assetId => text().references(Assets, #id, onDelete: KeyAction.cascade)();
  IntColumn get partNumber => integer()();
  TextColumn get etag => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();

  @override
  Set<Column<Object>> get primaryKey => {assetId, partNumber};
}

/// Pending metadata mutations, pushed in order (docs/architecture/sync.md "Metadata sync").
@DataClassName('OutboxRow')
class Outbox extends Table {
  /// UUID, used as the Idempotency-Key.
  TextColumn get id => text()();
  TextColumn get accountId => text()();

  /// memory | preset
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// patch | trash | restore | purge | upsert | delete
  TextColumn get op => text()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Pull cursor per account.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get accountId => text()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {accountId};
}

/// Capture presets (EXP-006, EXP-007).
@DataClassName('PresetRow')
class Presets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get experienceId => text()();
  TextColumn get intentJson => text()();
  TextColumn get profileId => text().nullable()();
  IntColumn get profileVersion => integer().nullable()();
  BoolColumn get live => boolean().withDefault(const Constant(false))();

  /// user | suggested
  TextColumn get source => text().withDefault(const Constant('user'))();
  IntColumn get serverVersion => integer().nullable()();

  /// True while the local copy differs from the server's.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Key/value device settings (Wi-Fi-only, location capture, ...).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
