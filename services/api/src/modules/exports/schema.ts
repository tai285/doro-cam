import { bigint, index, pgEnum, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';
import { user } from '../auth/schema.ts';

export const exportStatus = pgEnum('export_status', ['pending', 'building', 'ready', 'failed']);

/** A requested archive of the user's originals and metadata (WEB-010, PRIV-006). */
export const dataExports = pgTable(
  'data_exports',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    status: exportStatus('status').notNull().default('pending'),
    objectKey: text('object_key'),
    bytes: bigint('bytes', { mode: 'number' }),
    failureReason: text('failure_reason'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    completedAt: timestamp('completed_at', { withTimezone: true }),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  },
  (table) => [index('data_exports_owner_idx').on(table.ownerId)],
);
