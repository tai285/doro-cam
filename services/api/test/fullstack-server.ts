/**
 * Test-only entrypoint for the full-stack scenario (scripts/e2e-fullstack.sh). It runs the production
 * wiring as closely as a laptop allows: one real pg-boss worker (src/runtime/worker.ts, so uploads are
 * verified and motion clips transcoded asynchronously, exactly as in production) and the real API
 * (src/app.ts, pg-boss queue) on a private Postgres database and the real Garage S3.
 *
 * The same database and bucket are served by TWO API listeners because phone and browser reach the
 * machine under different addresses and presigned URLs are signed for one host:
 *   - `device` (the Android emulator): http://10.0.2.2:<devicePort>, storage at http://10.0.2.2:9000
 *   - `web`    (Playwright/browser):   http://127.0.0.1:<webPort>,  storage at http://127.0.0.1:9000
 * Only mail is replaced: an in-memory outbox readable at GET /__test/outbox (no inbox exists in tests).
 *
 *   node test/fullstack-server.ts   (env: FULLSTACK_DEVICE_PORT, FULLSTACK_WEB_PORT, FULLSTACK_WEB_ORIGIN)
 *
 * Prints `READY` once both listeners and the worker are up. Never used outside tests.
 */
import type { FastifyPluginAsync } from 'fastify';
import { PgBoss } from 'pg-boss';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config/env.ts';
import { createDatabase } from '../src/db/client.ts';
import { runMigrations } from '../src/db/migrate.ts';
import { OutboxMailer } from '../src/lib/mailer.ts';
import { JOBS, PgBossQueue } from '../src/lib/queue.ts';
import { createStorage } from '../src/lib/storage.ts';
import { createModules, createServices } from '../src/modules/index.ts';
import { startWorker } from '../src/runtime/worker.ts';
import { createTestDatabase } from './helpers/database.ts';
import { baseEnv } from './helpers/env.ts';

const devicePort = Number(process.env.FULLSTACK_DEVICE_PORT ?? 4310);
const webPort = Number(process.env.FULLSTACK_WEB_PORT ?? 4311);
const webOrigin = process.env.FULLSTACK_WEB_ORIGIN ?? 'http://127.0.0.1:4173';
const s3Host = new URL(baseEnv().S3_ENDPOINT as string);

const testDb = await createTestDatabase();
const common = {
  DATABASE_URL: testDb.url,
  AUTH_RATE_LIMIT_PER_MINUTE: '100000',
  LOG_LEVEL: 'warn',
  WEB_ORIGINS: webOrigin,
  HOST: '127.0.0.1',
  WORKER_HEALTH_PORT: '0',
};

const workerConfig = loadConfig(baseEnv(common));
{
  const database = createDatabase(workerConfig.database.url);
  await runMigrations(database.pool);
  await database.close();
}
const worker = await startWorker(workerConfig);

const mailer = new OutboxMailer();
const mailModule: FastifyPluginAsync = async (app) => {
  app.get('/__test/outbox', async () => ({ items: mailer.sent }));
};

async function listen(name: string, port: number, publicBase: string, s3Public: string) {
  const config = loadConfig(
    baseEnv({ ...common, PORT: String(port), PUBLIC_BASE_URL: publicBase, S3_PUBLIC_ENDPOINT: s3Public }),
  );
  const database = createDatabase(config.database.url);
  const storage = createStorage(config.s3);
  const boss = new PgBoss({ connectionString: config.database.url, supervise: false, schedule: false });
  boss.on('error', () => undefined);
  await boss.start();
  for (const job of Object.values(JOBS)) {
    await boss.createQueue(job);
  }
  const services = createServices({ config, database, storage, jobs: new PgBossQueue(boss), mailer });
  const app = await buildApp({ config, database, storage }, { modules: [...createModules(services), mailModule] });
  await app.listen({ host: '0.0.0.0', port });
  console.log(`${name} api listening on ${publicBase}`);
  return {
    async close() {
      await app.close();
      await boss.stop({ graceful: false }).catch(() => undefined);
      await database.close();
      storage.close();
    },
  };
}

const s3At = (host: string) => `${s3Host.protocol}//${host}:${s3Host.port}`;
const device = await listen('device', devicePort, `http://10.0.2.2:${String(devicePort)}`, s3At('10.0.2.2'));
const web = await listen('web', webPort, `http://127.0.0.1:${String(webPort)}`, s3At('127.0.0.1'));
console.log('READY');

let closing = false;
const shutdown = async () => {
  if (closing) return;
  closing = true;
  await device.close();
  await web.close();
  await worker.close();
  await testDb.drop();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown());
process.on('SIGINT', () => void shutdown());
