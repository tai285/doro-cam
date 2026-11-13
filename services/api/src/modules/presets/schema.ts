import { boolean, index, integer, jsonb, pgEnum, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { user } from '../auth/schema.ts';

export const presetSource = pgEnum('preset_source', ['user', 'suggested']);

export const presets = pgTable(
  'presets',
  {
    id: uuid('id').primaryKey(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    experienceId: text('experience_id').notNull(),
    intent: jsonb('intent').$type<Record<string, unknown>>().notNull(),
    profileId: text('profile_id'),
    profileVersion: integer('profile_version'),
    live: boolean('live').notNull().default(false),
    source: presetSource('source').notNull().default('user'),
    version: integer('version').notNull().default(1),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (table) => [index('presets_owner_idx').on(table.ownerId)],
);

/** Remembered dismissals so a suggestion the user declined is not offered again (PRE-003). */
export const presetSuggestionDismissals = pgTable(
  'preset_suggestion_dismissals',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    patternKey: text('pattern_key').notNull(),
    dismissedAt: timestamp('dismissed_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [uniqueIndex('preset_dismissals_owner_pattern_uq').on(table.ownerId, table.patternKey)],
);
