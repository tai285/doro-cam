import os from 'node:os';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createDatabase } from '../src/db/client.ts';
import { MIGRATIONS_FOLDER, runMigrations } from '../src/db/migrate.ts';
import { createTestDatabase, type TestDatabase } from './helpers/database.ts';

describe('database', () => {
  let testDb: TestDatabase;

  beforeAll(async () => {
    testDb = await createTestDatabase();
  });
  afterAll(async () => {
    await testDb.drop();
  });

  describe('createDatabase', () => {
    it('[NFR-013] check() succeeds against a reachable database', async () => {
      const database = createDatabase(testDb.url);
      try {
        await expect(database.check()).resolves.toBeUndefined();
        const { rows } = await database.pool.query<{ ok: number }>('select 1 as ok');
        expect(rows[0]?.ok).toBe(1);
      } finally {
        await database.close();
      }
    });

    it('[NFR-013] check() rejects quickly when the database is unreachable', async () => {
      const database = createDatabase('postgres://doro:x@127.0.0.1:1/doro');
      const started = Date.now();
      try {
        await expect(database.check()).rejects.toThrow();
        expect(Date.now() - started).toBeLessThan(5000);
      } finally {
        await database.close();
      }
    });

    it('does not crash the process when an idle client errors', async () => {
      const database = createDatabase(testDb.url);
      try {
        await database.check();
        // Terminate the server-side backend of the pooled idle client.
        await database.pool.query(
          "select pg_terminate_backend(pid) from pg_stat_activity where datname = current_database() and pid <> pg_backend_pid()",
        );
        await new Promise((resolve) => setTimeout(resolve, 100));
        await expect(database.check()).resolves.toBeUndefined();
      } finally {
        await database.close();
      }
    });

    it('registers an error listener so a pool error cannot crash the process', async () => {
      const database = createDatabase(testDb.url);
      try {
        expect(database.pool.listenerCount('error')).toBeGreaterThanOrEqual(1);
        expect(() => database.pool.emit('error', new Error('idle client failure'))).not.toThrow();
      } finally {
        await database.close();
      }
    });

    it('exposes a drizzle handle on the same pool', async () => {
      const database = createDatabase(testDb.url);
      try {
        const result = await database.db.execute('select 2 as two');
        expect(result.rows[0]).toEqual({ two: 2 });
      } finally {
        await database.close();
      }
    });
  });

  describe('runMigrations', () => {
    it('[ADR-0007] applies the committed migrations and records them', async () => {
      const database = createDatabase(testDb.url);
      try {
        await runMigrations(database.pool);
        const { rows } = await database.pool.query<{ count: string }>(
          'select count(*) from drizzle.__drizzle_migrations',
        );
        expect(Number(rows[0]?.count)).toBeGreaterThanOrEqual(1);
      } finally {
        await database.close();
      }
    });

    it('[ADR-0007] is idempotent: running twice applies nothing the second time', async () => {
      const database = createDatabase(testDb.url);
      try {
        await runMigrations(database.pool);
        const first = await database.pool.query<{ count: string }>('select count(*) from drizzle.__drizzle_migrations');
        await runMigrations(database.pool);
        const second = await database.pool.query<{ count: string }>('select count(*) from drizzle.__drizzle_migrations');
        expect(second.rows[0]?.count).toBe(first.rows[0]?.count);
      } finally {
        await database.close();
      }
    });

    it('rejects when the migrations folder does not exist', async () => {
      const database = createDatabase(testDb.url);
      try {
        await expect(runMigrations(database.pool, path.join(os.tmpdir(), 'no-such-migrations-folder'))).rejects.toThrow();
      } finally {
        await database.close();
      }
    });

    it('resolves the default folder to services/api/migrations', () => {
      expect(path.basename(MIGRATIONS_FOLDER)).toBe('migrations');
      expect(path.basename(path.dirname(MIGRATIONS_FOLDER))).toBe('api');
    });
  });
});
