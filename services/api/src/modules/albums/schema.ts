import { boolean, date, index, integer, pgEnum, pgTable, primaryKey, text, timestamp, uuid } from 'drizzle-orm/pg-core';
import { user } from '../auth/schema.ts';
import { memories } from '../memories/schema.ts';

export const albumKind = pgEnum('album_kind', ['album', 'trip']);
export const albumRole = pgEnum('album_role', ['owner', 'editor', 'contributor', 'viewer']);

export const albums = pgTable(
  'albums',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    kind: albumKind('kind').notNull().default('album'),
    title: text('title').notNull(),
    description: text('description'),
    startsOn: date('starts_on'),
    endsOn: date('ends_on'),
    coverMemoryId: uuid('cover_memory_id').references(() => memories.id, { onDelete: 'set null' }),
    allowOriginalDownload: boolean('allow_original_download').notNull().default(true),
    shareLocation: boolean('share_location').notNull().default(false),
    autoAddDuringTrip: boolean('auto_add_during_trip').notNull().default(false),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (table) => [index('albums_owner_idx').on(table.ownerId)],
);

export const albumMembers = pgTable(
  'album_members',
  {
    albumId: uuid('album_id')
      .notNull()
      .references(() => albums.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    role: albumRole('role').notNull(),
    invitedBy: uuid('invited_by').references(() => user.id, { onDelete: 'set null' }),
    joinedAt: timestamp('joined_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.albumId, table.userId] }), index('album_members_user_idx').on(table.userId)],
);

export const albumInvites = pgTable(
  'album_invites',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    albumId: uuid('album_id')
      .notNull()
      .references(() => albums.id, { onDelete: 'cascade' }),
    role: albumRole('role').notNull(),
    tokenHash: text('token_hash').notNull().unique(),
    createdBy: uuid('created_by')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    maxUses: integer('max_uses').notNull().default(1),
    uses: integer('uses').notNull().default(0),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index('album_invites_album_idx').on(table.albumId)],
);

export const albumItems = pgTable(
  'album_items',
  {
    albumId: uuid('album_id')
      .notNull()
      .references(() => albums.id, { onDelete: 'cascade' }),
    memoryId: uuid('memory_id')
      .notNull()
      .references(() => memories.id, { onDelete: 'cascade' }),
    addedBy: uuid('added_by')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    addedAt: timestamp('added_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.albumId, table.memoryId] }), index('album_items_memory_idx').on(table.memoryId)],
);
