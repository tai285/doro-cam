import { Writable } from 'node:stream';
import type { FastifyPluginAsync } from 'fastify';
import { type ZodTypeProvider } from 'fastify-type-provider-zod';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';
import {
  ConflictError,
  ForbiddenError,
  NotFoundError,
  RateLimitedError,
  ServiceUnavailableError,
  UnauthenticatedError,
} from '../src/lib/errors.ts';
import { buildTestApp, type TestApp } from './helpers/app.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** Throwaway routes that exercise the error handling paths a real module will hit. */
const probeRoutes: FastifyPluginAsync = async (app) => {
  const typed = app.withTypeProvider<ZodTypeProvider>();
  typed.get('/probe/conflict', async () => {
    throw new ConflictError('Already exists.', 'memory.conflict', { id: 'm1' });
  });
  typed.get('/probe/not-found', async () => {
    throw new NotFoundError('No such memory.', 'memory.not_found');
  });
  typed.get('/probe/unauthenticated', async () => {
    throw new UnauthenticatedError();
  });
  typed.get('/probe/forbidden', async () => {
    throw new ForbiddenError();
  });
  typed.get('/probe/rate-limited', async () => {
    throw new RateLimitedError('Slow down.', 30);
  });
  typed.get('/probe/unavailable', async () => {
    throw new ServiceUnavailableError();
  });
  typed.get(
    '/probe/query',
    { schema: { querystring: z.object({ limit: z.coerce.number().int().min(1).max(10) }) } },
    async (request) => ({ limit: request.query.limit }),
  );
  typed.post(
    '/probe/body',
    { schema: { body: z.object({ name: z.string().min(1) }) } },
    async (request) => ({ name: request.body.name }),
  );
  typed.get('/probe/boom', async () => {
    throw new Error('database password is hunter2');
  });
  typed.get('/probe/throw-string', async () => {
    // eslint-disable-next-line @typescript-eslint/only-throw-error -- deliberately not an Error
    throw 'plain string failure';
  });
  typed.get('/probe/throw-undefined', async () => {
    // eslint-disable-next-line @typescript-eslint/only-throw-error -- deliberately not an Error
    throw undefined;
  });
  typed.get('/probe/throw-null', async () => {
    // eslint-disable-next-line @typescript-eslint/only-throw-error -- deliberately not an Error
    throw null;
  });
  typed.get('/probe/throw-number', async () => {
    // eslint-disable-next-line @typescript-eslint/only-throw-error -- deliberately not an Error
    throw 42;
  });
  typed.get('/probe/throw-object', async () => {
    // eslint-disable-next-line @typescript-eslint/only-throw-error -- deliberately not an Error
    throw { statusCode: 409, message: 'plain object' };
  });
  typed.get('/probe/sync-throw', () => {
    throw new Error('synchronous failure');
  });
  typed.get('/probe/ok', async () => ({ fine: true }));
  typed.get('/probe/client-status', async () => {
    throw Object.assign(new Error('upstream said so'), { statusCode: 408 });
  });
  typed.get('/probe/server-status', async () => {
    throw Object.assign(new Error('upstream exploded'), { statusCode: 502 });
  });
  typed.get(
    '/probe/bad-response',
    { schema: { response: { 200: z.object({ id: z.string() }) } } },
    async () => ({ id: 123 }) as unknown as { id: string },
  );
};

describe('error handling', () => {
  let ctx: TestApp;
  const logLines: string[] = [];

  beforeAll(async () => {
    const logStream = new Writable({
      write(chunk: Buffer, _encoding, callback) {
        logLines.push(chunk.toString('utf8'));
        callback();
      },
    });
    ctx = await buildTestApp({ modules: [probeRoutes], env: { LOG_LEVEL: 'info' }, logStream });
  });
  afterAll(async () => {
    await ctx.close();
  });

  const call = (url: string, init: { method?: 'GET' | 'POST'; headers?: Record<string, string>; payload?: string } = {}) =>
    ctx.app.inject({ url, method: init.method ?? 'GET', ...(init.headers ? { headers: init.headers } : {}), ...(init.payload === undefined ? {} : { payload: init.payload }) });

  describe('application errors', () => {
    it('renders code, message, details and the request ID', async () => {
      const response = await call('/probe/conflict');
      expect(response.statusCode).toBe(409);
      const body = response.json<{ error: Record<string, unknown> }>();
      expect(body.error).toEqual({
        code: 'memory.conflict',
        message: 'Already exists.',
        details: { id: 'm1' },
        requestId: response.headers['x-request-id'],
      });
    });

    const cases: ReadonlyArray<[string, number, string]> = [
      ['/probe/not-found', 404, 'memory.not_found'],
      ['/probe/unauthenticated', 401, 'auth.unauthenticated'],
      ['/probe/forbidden', 403, 'auth.forbidden'],
      ['/probe/rate-limited', 429, 'rate_limited'],
      ['/probe/unavailable', 503, 'service.unavailable'],
    ];
    for (const [url, status, code] of cases) {
      it(`${url} → ${status} ${code}`, async () => {
        const response = await call(url);
        expect(response.statusCode).toBe(status);
        expect(response.json<{ error: { code: string } }>().error.code).toBe(code);
      });
    }

    it('includes the retry hint of a rate-limit error', async () => {
      const response = await call('/probe/rate-limited');
      expect(response.json<{ error: { details: unknown } }>().error.details).toEqual({ retryAfterSeconds: 30 });
    });
  });

  describe('request validation', () => {
    it('[NFR-008] rejects a bad query parameter with 400 and a per-field path', async () => {
      const response = await call('/probe/query?limit=abc');
      expect(response.statusCode).toBe(400);
      const { error } = response.json<{ error: { code: string; details: Array<{ path: string; message: string }> } }>();
      expect(error.code).toBe('request.invalid');
      expect(error.details.some((detail) => detail.path.includes('limit'))).toBe(true);
    });

    it('rejects a missing required parameter and an out-of-range value', async () => {
      expect((await call('/probe/query')).statusCode).toBe(400);
      expect((await call('/probe/query?limit=11')).statusCode).toBe(400);
      expect((await call('/probe/query?limit=0')).statusCode).toBe(400);
    });

    it('accepts and coerces a valid query parameter', async () => {
      const response = await call('/probe/query?limit=7');
      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ limit: 7 });
    });

    it('rejects a body that breaks the schema', async () => {
      const response = await call('/probe/body', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        payload: JSON.stringify({ name: '' }),
      });
      expect(response.statusCode).toBe(400);
      expect(response.json<{ error: { code: string } }>().error.code).toBe('request.invalid');
    });

    it('accepts a valid body', async () => {
      const response = await call('/probe/body', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        payload: JSON.stringify({ name: 'Doro' }),
      });
      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ name: 'Doro' });
    });

    it('maps malformed JSON to 400 request.invalid', async () => {
      const response = await call('/probe/body', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        payload: '{"name":',
      });
      expect(response.statusCode).toBe(400);
      expect(response.json<{ error: { code: string } }>().error.code).toBe('request.invalid');
    });

    it('[ADR-0008] maps an oversized body to 413 request.too_large (uploads never go through the API)', async () => {
      const response = await call('/probe/body', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        payload: JSON.stringify({ name: 'x'.repeat(1024 * 1024 + 10) }),
      });
      expect(response.statusCode).toBe(413);
      expect(response.json<{ error: { code: string } }>().error.code).toBe('request.too_large');
    });

    it('maps an unsupported content type to 415', async () => {
      const response = await call('/probe/body', {
        method: 'POST',
        headers: { 'content-type': 'application/x-unknown' },
        payload: 'name=Doro',
      });
      expect(response.statusCode).toBe(415);
      expect(response.json<{ error: { code: string } }>().error.code).toBe('request.unsupported_media_type');
    });
  });

  describe('unexpected failures', () => {
    it('[NFR-008] hides the details of an unexpected error from the client but logs them', async () => {
      const response = await call('/probe/boom');
      expect(response.statusCode).toBe(500);
      expect(response.body).not.toContain('hunter2');
      const { error } = response.json<{ error: { code: string; message: string; requestId: string } }>();
      expect(error.code).toBe('internal');
      expect(error.message).toBe('Something went wrong on our side.');
      expect(logLines.join('')).toContain('hunter2');
      expect(logLines.join('')).toContain(error.requestId);
    });

    it('[NFR-008] treats a thrown non-Error value as a server error without describing it', async () => {
      const response = await call('/probe/throw-string');
      expect(response.statusCode).toBe(500);
      expect(response.body).not.toContain('plain string failure');
      const { error } = response.json<{ error: { code: string; message: string } }>();
      expect(error).toMatchObject({ code: 'internal', message: 'Something went wrong on our side.' });
      expect(logLines.join('')).toContain('plain string failure');
    });

    it('handles every kind of thrown primitive the same way', async () => {
      for (const path of ['/probe/throw-undefined', '/probe/throw-null', '/probe/throw-number']) {
        const response = await call(path);
        expect(response.statusCode, path).toBe(500);
        expect(response.json<{ error: { code: string } }>().error.code, path).toBe('internal');
      }
    });

    it('keeps the status of a thrown plain object that carries a 4xx statusCode', async () => {
      const response = await call('/probe/throw-object');
      expect(response.statusCode).toBe(409);
    });

    it('supports synchronous (non-async) handlers that throw', async () => {
      const response = await call('/probe/sync-throw');
      expect(response.statusCode).toBe(500);
      expect(response.json<{ error: { code: string } }>().error.code).toBe('internal');
    });

    it('returns the handler result unchanged when nothing throws', async () => {
      const response = await call('/probe/ok');
      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ fine: true });
    });

    it('keeps an unmapped 4xx status but uses the generic request.invalid code and message', async () => {
      const response = await call('/probe/client-status');
      expect(response.statusCode).toBe(408);
      const { error } = response.json<{ error: { code: string; message: string } }>();
      expect(error).toMatchObject({ code: 'request.invalid', message: 'The request is invalid.' });
      expect(response.body).not.toContain('upstream said so');
    });

    it('never passes an upstream 5xx status or message through', async () => {
      const response = await call('/probe/server-status');
      expect(response.statusCode).toBe(500);
      expect(response.body).not.toContain('upstream exploded');
    });

    it('treats a response that breaks its own schema as a server error, not a client error', async () => {
      const response = await call('/probe/bad-response');
      expect(response.statusCode).toBe(500);
      expect(response.json<{ error: { code: string } }>().error.code).toBe('internal');
    });
  });

  describe('routing', () => {
    it('answers unknown routes with a route.not_found envelope that does not echo the query string', async () => {
      const response = await call('/nope?token=secret-token');
      expect(response.statusCode).toBe(404);
      const { error } = response.json<{ error: { code: string; message: string } }>();
      expect(error.code).toBe('route.not_found');
      expect(error.message).toBe('No route for GET /nope.');
      expect(response.body).not.toContain('secret-token');
    });

    it('answers a wrong method on a known path with 404', async () => {
      const response = await call('/healthz', { method: 'POST' });
      expect(response.statusCode).toBe(404);
    });
  });

  describe('request IDs', () => {
    it('echoes a valid caller-supplied ID in the header and in error bodies', async () => {
      const response = await call('/probe/not-found', { headers: { 'x-request-id': 'client-request-0001' } });
      expect(response.headers['x-request-id']).toBe('client-request-0001');
      expect(response.json<{ error: { requestId: string } }>().error.requestId).toBe('client-request-0001');
    });

    it('replaces an unsafe ID with a generated UUID', async () => {
      const response = await call('/healthz', { headers: { 'x-request-id': 'bad id with spaces' } });
      expect(response.headers['x-request-id']).toMatch(UUID);
    });

    it('generates an ID when none is supplied', async () => {
      const response = await call('/healthz');
      expect(response.headers['x-request-id']).toMatch(UUID);
    });
  });

  describe('logging', () => {
    it('[NFR-011] never writes the Authorization header or cookies to the log', async () => {
      await call('/healthz', {
        headers: { authorization: 'Bearer top-secret-token', cookie: 'session=cookie-secret-value' },
      });
      const logged = logLines.join('');
      expect(logged).not.toContain('top-secret-token');
      expect(logged).not.toContain('cookie-secret-value');
    });
  });
});
