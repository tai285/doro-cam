import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config/env.ts';
import { startApi } from '../src/runtime/api.ts';
import { occupyPort } from './helpers/app.ts';
import { connectionCount, createTestDatabase, type TestDatabase } from './helpers/database.ts';
import { baseEnv } from './helpers/env.ts';

describe('api runtime', () => {
  let testDb: TestDatabase;

  beforeAll(async () => {
    testDb = await createTestDatabase();
  });
  afterAll(async () => {
    await testDb.drop();
  });

  const configFor = (port: number) => loadConfig(baseEnv({ DATABASE_URL: testDb.url, HOST: '127.0.0.1', PORT: String(port) }));

  it('[NFR-013] listens, serves real HTTP, and shuts down releasing the port and connections', async () => {
    const api = await startApi(configFor(0));
    try {
      expect(api.address).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);
      const health = await fetch(`${api.address}/healthz`);
      expect(health.status).toBe(200);
      expect(health.headers.get('x-request-id')).toBeTruthy();

      const ready = await fetch(`${api.address}/readyz`);
      expect(ready.status).toBe(200);
      expect(await ready.json()).toEqual({ status: 'ready', checks: { database: 'ok', storage: 'ok' } });
    } finally {
      await api.close();
    }
    await expect(fetch(`${api.address}/healthz`)).rejects.toThrow();
    await expect.poll(() => connectionCount(testDb.name), { timeout: 5000 }).toBe(0);
  });

  it('[NFR-013] fails to start when the port is taken and cleans up its dependencies', async () => {
    const occupied = await occupyPort();
    try {
      await expect(startApi(configFor(occupied.port))).rejects.toThrow(/EADDRINUSE|address already in use/i);
      await expect.poll(() => connectionCount(testDb.name), { timeout: 5000 }).toBe(0);
    } finally {
      await occupied.close();
    }
  });
});
