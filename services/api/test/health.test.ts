import Fastify from 'fastify';
import { serializerCompiler, validatorCompiler } from 'fastify-type-provider-zod';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { healthRoutes } from '../src/modules/health/routes.ts';
import { buildTestApp } from './helpers/app.ts';
import { createTestDatabase, type TestDatabase } from './helpers/database.ts';

describe('health endpoints', () => {
  let database: TestDatabase;

  beforeAll(async () => {
    database = await createTestDatabase();
  });
  afterAll(async () => {
    await database.drop();
  });

  async function readyz(env: Record<string, string | undefined> = {}) {
    const ctx = await buildTestApp({ env: { DATABASE_URL: database.url, ...env } });
    try {
      const response = await ctx.app.inject('/readyz');
      return { status: response.statusCode, body: response.json<Record<string, unknown>>(), raw: response.body };
    } finally {
      await ctx.close();
    }
  }

  describe('GET /healthz', () => {
    it('[NFR-013] reports liveness without touching any dependency', async () => {
      // Even with both dependencies unreachable the process is alive.
      const ctx = await buildTestApp({
        env: { DATABASE_URL: 'postgres://u:p@127.0.0.1:1/x', S3_ENDPOINT: 'http://127.0.0.1:1' },
      });
      try {
        const response = await ctx.app.inject('/healthz');
        expect(response.statusCode).toBe(200);
        expect(response.json()).toEqual({ status: 'ok' });
      } finally {
        await ctx.close();
      }
    });
  });

  describe('GET /readyz', () => {
    it('[NFR-013] is ready when Postgres and storage are reachable', async () => {
      const result = await readyz();
      expect(result.status).toBe(200);
      expect(result.body).toEqual({ status: 'ready', checks: { database: 'ok', storage: 'ok' } });
    });

    it('[NFR-013] is unavailable when the database is down, and says which check failed', async () => {
      const result = await readyz({ DATABASE_URL: 'postgres://doro:x@127.0.0.1:1/doro' });
      expect(result.status).toBe(503);
      expect(result.body).toEqual({ status: 'unavailable', checks: { database: 'fail', storage: 'ok' } });
    });

    it('[NFR-013] is unavailable when the storage endpoint is unreachable', async () => {
      const result = await readyz({ S3_ENDPOINT: 'http://127.0.0.1:1' });
      expect(result.status).toBe(503);
      expect(result.body).toEqual({ status: 'unavailable', checks: { database: 'ok', storage: 'fail' } });
    });

    it('[NFR-013] is unavailable when the bucket does not exist', async () => {
      const result = await readyz({ S3_BUCKET: 'no-such-bucket-for-tests' });
      expect(result.status).toBe(503);
      expect(result.body).toEqual({ status: 'unavailable', checks: { database: 'ok', storage: 'fail' } });
    });

    it('[NFR-013] is unavailable when the storage credentials are wrong', async () => {
      const result = await readyz({
        S3_ACCESS_KEY_ID: 'GKffffffffffffffffffffffff',
        S3_SECRET_ACCESS_KEY: 'f'.repeat(64),
      });
      expect(result.status).toBe(503);
      expect(result.body).toEqual({ status: 'unavailable', checks: { database: 'ok', storage: 'fail' } });
    });

    it('reports every failing dependency at once', async () => {
      const result = await readyz({
        DATABASE_URL: 'postgres://doro:x@127.0.0.1:1/doro',
        S3_ENDPOINT: 'http://127.0.0.1:1',
      });
      expect(result.status).toBe(503);
      expect(result.body).toEqual({ status: 'unavailable', checks: { database: 'fail', storage: 'fail' } });
    });

    it('[NFR-011] reveals only pass/fail, never hosts, ports or error text', async () => {
      const result = await readyz({
        DATABASE_URL: 'postgres://doro:secret-db-pass@127.0.0.1:1/doro',
        S3_ENDPOINT: 'http://127.0.0.1:1',
      });
      expect(Object.keys(result.body).sort()).toEqual(['checks', 'status']);
      for (const leaked of ['127.0.0.1', 'ECONNREFUSED', 'secret-db-pass', 'doro']) {
        expect(result.raw).not.toContain(leaked);
      }
    });

    it('bounds a hanging dependency with a timeout instead of hanging the probe', async () => {
      const app = Fastify();
      app.setValidatorCompiler(validatorCompiler);
      app.setSerializerCompiler(serializerCompiler);
      await app.register(
        healthRoutes([
          { name: 'database', run: () => new Promise<void>(() => undefined) },
          { name: 'storage', run: async () => undefined },
        ]),
      );
      const started = Date.now();
      const response = await app.inject('/readyz');
      const elapsed = Date.now() - started;

      expect(response.statusCode).toBe(503);
      expect(response.json()).toEqual({ status: 'unavailable', checks: { database: 'fail', storage: 'ok' } });
      expect(elapsed).toBeGreaterThanOrEqual(2900);
      expect(elapsed).toBeLessThan(6000);
      await app.close();
    });

    it('is ready with no checks registered', async () => {
      const app = Fastify();
      app.setValidatorCompiler(validatorCompiler);
      app.setSerializerCompiler(serializerCompiler);
      await app.register(healthRoutes([]));
      const response = await app.inject('/readyz');
      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ status: 'ready', checks: {} });
      await app.close();
    });
  });
});
