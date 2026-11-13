import { createHash, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { buildApp } from '../../src/app.ts';
import { type AppConfig, loadConfig } from '../../src/config/env.ts';
import { createDatabase, type Database } from '../../src/db/client.ts';
import { runMigrations } from '../../src/db/migrate.ts';
import { OutboxMailer } from '../../src/lib/mailer.ts';
import { InlineQueue, type JobName, JOBS } from '../../src/lib/queue.ts';
import { createStorage, type Storage } from '../../src/lib/storage.ts';
import type { Services } from '../../src/modules/context.ts';
import { createModules, createServices } from '../../src/modules/index.ts';
import { createJobHandlers } from '../../src/modules/jobs/handlers.ts';
import { createTestDatabase, type TestDatabase } from './database.ts';
import { baseEnv } from './env.ts';

export interface Stack {
  app: FastifyInstance;
  config: AppConfig;
  database: Database;
  storage: Storage;
  services: Services;
  mailer: OutboxMailer;
  queue: InlineQueue;
  close(): Promise<void>;
}

/** The real API on a private database, real Garage S3, an in-process job queue and an inspectable mail outbox. */
export async function startStack(
  env: Record<string, string | undefined> = {},
  options: { logStream?: NodeJS.WritableStream; extraModules?: (stack: { mailer: OutboxMailer; services: Services }) => FastifyPluginAsync[] } = {},
): Promise<Stack> {
  const testDb: TestDatabase = await createTestDatabase();
  const config = loadConfig(baseEnv({ DATABASE_URL: testDb.url, AUTH_RATE_LIMIT_PER_MINUTE: '100000', ...env }));
  const database = createDatabase(config.database.url);
  await runMigrations(database.pool);
  const storage = createStorage({ ...config.s3 });
  const mailer = new OutboxMailer();
  const queue = new InlineQueue();
  const services = createServices({ config, database, storage, jobs: queue, mailer });
  const handlers = createJobHandlers(services);
  for (const name of Object.values(JOBS) as JobName[]) {
    queue.register(name, handlers[name]);
  }
  const app = await buildApp({ config, database, storage }, {
    modules: [...createModules(services), ...(options.extraModules?.({ mailer, services }) ?? [])],
    ...(options.logStream === undefined ? {} : { logStream: options.logStream }),
  });
  await app.ready();
  return {
    app,
    config,
    database,
    storage,
    services,
    mailer,
    queue,
    async close() {
      await app.close();
      await database.close();
      storage.close();
      await testDb.drop();
    },
  };
}

export interface TestUser {
  id: string;
  email: string;
  password: string;
  /** Authorization header value for bearer requests (mobile style). */
  bearer: string;
  headers: { authorization: string };
}

export const PASSWORD = 'correct-horse-battery';

/** Signs up, verifies the email through the mailed link, and signs in. Returns a bearer-authenticated user. */
export async function createUser(stack: Stack, name = 'Test User'): Promise<TestUser> {
  const email = `user-${randomUUID().slice(0, 8)}@example.test`;
  const signUp = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-up/email', payload: { name, email, password: PASSWORD } });
  if (signUp.statusCode !== 200) {
    throw new Error(`sign-up failed: ${signUp.statusCode} ${signUp.body}`);
  }
  const mail = stack.mailer.last('verify_email');
  if (mail === undefined || mail.to !== email) {
    throw new Error('verification email was not sent');
  }
  const link = new URL(mail.link);
  const verify = await stack.app.inject({ method: 'GET', url: `${link.pathname}${link.search}` });
  if (verify.statusCode >= 400) {
    throw new Error(`verification failed: ${verify.statusCode} ${verify.body}`);
  }
  const signIn = await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email, password: PASSWORD } });
  const token = signIn.headers['set-auth-token'];
  if (signIn.statusCode !== 200 || typeof token !== 'string') {
    throw new Error(`sign-in failed: ${signIn.statusCode} ${signIn.body}`);
  }
  const me = await stack.app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${token}` } });
  const id = (me.json() as { id: string }).id;
  return { id, email, password: PASSWORD, bearer: `Bearer ${token}`, headers: { authorization: `Bearer ${token}` } };
}

export function sha256(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex');
}

export function memoryBody(overrides: Record<string, unknown> = {}) {
  return {
    kind: 'photo',
    capturedAt: '2026-11-01T09:30:00.000Z',
    capturedTz: 'Asia/Kuala_Lumpur',
    experienceId: 'mirrorless',
    profile: { id: 'natural', version: 1 },
    scenario: 'street',
    capture: {
      lensKind: 'wide',
      focalLength35mmEq: 26,
      aperture: 1.8,
      isoApplied: 200,
      exposureTimeNsApplied: 8_000_000,
      widthPx: 4000,
      heightPx: 3000,
    },
    ...overrides,
  };
}

/** A tiny valid JPEG with GPS EXIF can be built by sharp in tests; this returns a plain solid-colour one. */
export async function jpegBuffer(width = 64, height = 48, color = { r: 200, g: 120, b: 80 }): Promise<Buffer> {
  const { default: sharp } = await import('sharp');
  return sharp({ create: { width, height, channels: 3, background: color } }).jpeg().toBuffer();
}

/** Uploads one asset end to end through the real protocol (register → presigned PUT → complete). */
export async function uploadAsset(
  stack: Stack,
  user: TestUser,
  memoryId: string,
  options: { role: string; mime: string; data: Buffer; assetId?: string },
): Promise<{ assetId: string; status: string }> {
  const assetId = options.assetId ?? randomUUID();
  const created = await stack.app.inject({
    method: 'POST',
    url: `/v1/memories/${memoryId}/assets/${assetId}/upload`,
    headers: user.headers,
    payload: { role: options.role, mime: options.mime, bytes: options.data.length, sha256: sha256(options.data) },
  });
  if (created.statusCode !== 200) {
    throw new Error(`upload create failed: ${created.statusCode} ${created.body}`);
  }
  const plan = created.json() as { mode: string; url?: string; headers?: Record<string, string> };
  if (plan.mode === 'single') {
    const put = await fetch(plan.url as string, { method: 'PUT', headers: plan.headers ?? {}, body: new Uint8Array(options.data) });
    if (!put.ok) {
      throw new Error(`storage PUT failed: ${put.status} ${await put.text()}`);
    }
  } else if (plan.mode !== 'complete') {
    throw new Error(`unexpected mode ${plan.mode}`);
  }
  const completed = await stack.app.inject({
    method: 'POST',
    url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`,
    headers: user.headers,
    payload: {},
  });
  return { assetId, status: (completed.json() as { status: string }).status };
}
