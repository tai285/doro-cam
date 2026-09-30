import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import type pg from 'pg';

const here = path.dirname(fileURLToPath(import.meta.url));

/** Default migrations folder: services/api/migrations (works from src/ and from dist/). */
export const MIGRATIONS_FOLDER = path.resolve(here, '..', '..', 'migrations');

/** Applies pending migrations in order. Already-applied migrations are skipped (idempotent). */
export async function runMigrations(pool: pg.Pool, migrationsFolder: string = MIGRATIONS_FOLDER): Promise<void> {
  await migrate(drizzle(pool), { migrationsFolder });
}
