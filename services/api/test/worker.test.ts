import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config/env.ts';
import { startWorker } from '../src/runtime/worker.ts';
import { occupyPort } from './helpers/app.ts';
import { connectionCount, createTestDatabase, type TestDatabase } from './helpers/database.ts';
import { baseEnv } from './helpers/env.ts';

describe('worker runtime', () => {
  let testDb: TestDatabase;

  beforeAll(async () => {
    testDb = await createTestDatabase();
  });
  afterAll(async () => {
    await testDb.drop();
  });

  const configFor = (healthPort: number) =>
    loadConfig(baseEnv({ DATABASE_URL: testDb.url, HOST: '127.0.0.1', WORKER_HEALTH_PORT: String(healthPort) }));

  it('[NFR-013] starts pg-boss and serves a health endpoint, then stops cleanly', async () => {
    const worker = await startWorker(configFor(0));
    const base = `http://127.0.0.1:${worker.healthPort}`;
    try {
      const health = await fetch(`${base}/healthz`);
      expect(health.status).toBe(200);
      expect(await health.json()).toEqual({ status: 'ok', role: 'worker' });

      const other = await fetch(`${base}/anything`);
      expect(other.status).toBe(404);
      expect(await other.json()).toEqual({ error: { code: 'route.not_found' } });

      const wrongMethod = await fetch(`${base}/healthz`, { method: 'POST' });
      expect(wrongMethod.status).toBe(404);
    } finally {
      await worker.close();
    }
    await expect(fetch(`${base}/healthz`)).rejects.toThrow();
  });

  it('[NFR-013] leaves no database connections behind after closing', async () => {
    const worker = await startWorker(configFor(0));
    expect(await connectionCount(testDb.name)).toBeGreaterThan(0);
    await worker.close();
    await expect.poll(() => connectionCount(testDb.name), { timeout: 5000 }).toBe(0);
  });

  it('[NFR-013] fails to start when the health port is taken, and releases pg-boss', async () => {
    const occupied = await occupyPort();
    try {
      await expect(startWorker(configFor(occupied.port))).rejects.toThrow(/EADDRINUSE|address already in use/i);
      await expect.poll(() => connectionCount(testDb.name), { timeout: 5000 }).toBe(0);
    } finally {
      await occupied.close();
    }
  });
});
