import { sql } from 'drizzle-orm';
import {
  bigint,
  boolean,
  check,
  customType,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgEnum,
  pgSequence,
  pgTable,
  primaryKey,
  real,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import { user } from '../auth/schema.ts';

const bytea = customType<{ data: Buffer; driverData: Buffer }>({
  dataType: () => 'bytea',
});

export const memoryKind = pgEnum('memory_kind', ['photo', 'motion', 'video']);
export const lensKind = pgEnum('lens_kind', ['ultraWide', 'wide', 'tele', 'front', 'other']);
export const assetRole = pgEnum('asset_role', [
  'photo_original',
  'photo_rendered',
  'photo_display',
  'thumbnail',
  'motion_clip',
  'motion_web',
  'video_original',
  'sanitized_original',
]);
export const assetStatus = pgEnum('asset_status', ['pending', 'uploading', 'uploaded', 'verified', 'ready', 'failed']);
export const changeEntity = pgEnum('change_entity', ['memory', 'asset', 'preset', 'album']);
export const changeOp = pgEnum('change_op', ['upsert', 'delete']);

/** One global, monotonically increasing sequence stamps every change for the sync feed (docs/specs/database.md). */
export const changeSeq = pgSequence('change_seq');

export const storageObjects = pgTable(
  'storage_objects',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    key: text('key').notNull().unique(),
    bytes: bigint('bytes', { mode: 'number' }).notNull(),
    sha256: bytea('sha256').notNull(),
    refCount: integer('ref_count').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [unique('storage_objects_owner_hash_uq').on(table.ownerId, table.sha256, table.bytes)],
);

export const memories = pgTable(
  'memories',
  {
    id: uuid('id').primaryKey(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    kind: memoryKind('kind').notNull(),
    capturedAt: timestamp('captured_at', { withTimezone: true }).notNull(),
    capturedTz: text('captured_tz').notNull(),
    experienceId: text('experience_id').notNull(),
    profileId: text('profile_id'),
    profileVersion: integer('profile_version'),
    presetId: uuid('preset_id'),
    scenario: text('scenario'),
    focalLength35mm: real('focal_length_35mm'),
    iso: integer('iso'),
    exposureTimeNs: bigint('exposure_time_ns', { mode: 'number' }),
    aperture: real('aperture'),
    lensKind: lensKind('lens_kind'),
    capture: jsonb('capture').$type<Record<string, unknown>>().notNull(),
    lat: doublePrecision('lat'),
    lon: doublePrecision('lon'),
    locationAccuracyM: real('location_accuracy_m'),
    locationShared: boolean('location_shared').notNull().default(false),
    caption: text('caption'),
    favorite: boolean('favorite').notNull().default(false),
    aspectRatio: text('aspect_ratio'),
    publicHandle: text('public_handle').notNull().unique(),
    version: integer('version').notNull().default(1),
    changeSeq: bigint('change_seq', { mode: 'number' }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (table) => [
    index('memories_library_idx').on(table.ownerId, table.capturedAt.desc(), table.id),
    index('memories_sync_idx').on(table.ownerId, table.changeSeq),
    index('memories_trash_idx').on(table.deletedAt).where(sql`${table.deletedAt} is not null`),
    check('memories_location_both_or_neither', sql`(${table.lat} is null) = (${table.lon} is null)`),
    check('memories_caption_len', sql`${table.caption} is null or char_length(${table.caption}) <= 2000`),
  ],
);

export const assets = pgTable(
  'assets',
  {
    id: uuid('id').primaryKey(),
    memoryId: uuid('memory_id')
      .notNull()
      .references(() => memories.id, { onDelete: 'cascade' }),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    role: assetRole('role').notNull(),
    status: assetStatus('status').notNull().default('pending'),
    failureReason: text('failure_reason'),
    mime: text('mime').notNull(),
    bytes: bigint('bytes', { mode: 'number' }).notNull(),
    sha256: bytea('sha256').notNull(),
    width: integer('width'),
    height: integer('height'),
    durationMs: integer('duration_ms'),
    storageObjectId: uuid('storage_object_id').references(() => storageObjects.id),
    uploadId: text('upload_id'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index('assets_memory_idx').on(table.memoryId),
    index('assets_owner_idx').on(table.ownerId),
    index('assets_storage_object_idx').on(table.storageObjectId),
    uniqueIndex('assets_memory_role_uq').on(table.memoryId, table.role),
  ],
);

/** Sync tombstones and upserts (docs/specs/database.md). */
export const changeLog = pgTable(
  'change_log',
  {
    seq: bigint('seq', { mode: 'number' }).primaryKey(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    entity: changeEntity('entity').notNull(),
    entityId: uuid('entity_id').notNull(),
    op: changeOp('op').notNull(),
    at: timestamp('at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index('change_log_owner_seq_idx').on(table.ownerId, table.seq)],
);

export const idempotencyKeys = pgTable(
  'idempotency_keys',
  {
    key: text('key').notNull(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    route: text('route').notNull(),
    requestHash: text('request_hash').notNull(),
    statusCode: integer('status_code').notNull(),
    response: jsonb('response').$type<unknown>().notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.ownerId, table.key] })],
);
