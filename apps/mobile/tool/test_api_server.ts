/**
 * Test-only API server for the mobile app's integration tests. It runs the REAL services/api app
 * (real Postgres and Garage S3 from `pnpm infra:up`) on a private database, with two differences
 * that make it drivable from tests: jobs run in-process (so uploads are verified immediately) and
 * emails are kept in memory and readable at /__test/mail.
 *
 *   cd services/api && PORT=3999 node ../../apps/mobile/tool/test_api_server.ts
 *
 * Prints `READY <port>` once listening. Never used outside tests.
 */
import { randomBytes } from 'node:crypto';
import { buildApp } from '../../../services/api/src/app.ts';
import { loadConfig } from '../../../services/api/src/config/env.ts';
import { createDatabase } from '../../../services/api/src/db/client.ts';
import { runMigrations } from '../../../services/api/src/db/migrate.ts';
import { OutboxMailer } from '../../../services/api/src/lib/mailer.ts';
import { InlineQueue, type JobName, JOBS } from '../../../services/api/src/lib/queue.ts';
import { createStorage } from '../../../services/api/src/lib/storage.ts';
import { createModules, createServices } from '../../../services/api/src/modules/index.ts';
import { createJobHandlers } from '../../../services/api/src/modules/jobs/handlers.ts';

const port = Number(process.env.PORT ?? 0);
const adminUrl =
  process.env.DATABASE_URL ?? 'postgres://doro:doro_dev_password@127.0.0.1:5432/doro';
const name = `doro_mobile_${randomBytes(6).toString('hex')}`;
const databaseUrl = new URL(adminUrl);
databaseUrl.pathname = `/${name}`;

const admin = createDatabase(adminUrl);
await admin.pool.query(`create database ${name}`);

const config = loadConfig({
  NODE_ENV: 'test',
  LOG_LEVEL: 'silent',
  DATABASE_URL: databaseUrl.toString(),
  S3_ENDPOINT: process.env.S3_ENDPOINT ?? 'http://127.0.0.1:9000',
  S3_REGION: 'garage',
  S3_BUCKET: process.env.S3_BUCKET ?? 'doro-media',
  S3_ACCESS_KEY_ID: process.env.S3_ACCESS_KEY_ID ?? 'GK0123456789abcdef01234567',
  S3_SECRET_ACCESS_KEY:
    process.env.S3_SECRET_ACCESS_KEY ??
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  PUBLIC_BASE_URL: `http://127.0.0.1:${port}`,
  AUTH_RATE_LIMIT_PER_MINUTE: '100000',
  ...(process.env.STORAGE_QUOTA_BYTES === undefined
    ? {}
    : { STORAGE_QUOTA_BYTES: process.env.STORAGE_QUOTA_BYTES }),
});
const database = createDatabase(config.database.url);
await runMigrations(database.pool);
const storage = createStorage(config.s3);
const mailer = new OutboxMailer();
const queue = new InlineQueue();
const services = createServices({ config, database, storage, jobs: queue, mailer });
const handlers = createJobHandlers(services);
for (const job of Object.values(JOBS) as JobName[]) {
  queue.register(job, handlers[job]);
}

const app = await buildApp(
  { config, database, storage },
  {
    modules: [
      ...createModules(services),
      async (instance) => {
        /** Creates an account whose email is already verified, through the real sign-up and verify flow. */
        instance.post('/__test/users', async (request, reply) => {
          const body = request.body as { email: string; name: string; password: string };
          const signUp = await app.inject({ method: 'POST', url: '/v1/auth/sign-up/email', payload: body });
          if (signUp.statusCode !== 200) {
            return reply.status(signUp.statusCode).send(signUp.body);
          }
          const mail = mailer.last('verify_email');
          if (mail === undefined) {
            return reply.status(500).send({ error: 'no verification mail' });
          }
          const link = new URL(mail.link);
          const verify = await app.inject({ method: 'GET', url: `${link.pathname}${link.search}` });
          return reply.status(verify.statusCode < 400 ? 200 : verify.statusCode).send({ ok: true });
        });
        instance.get('/__test/mail', async (request) => {
          const { kind } = request.query as { kind?: string };
          const mail = mailer.last(kind as 'verify_email' | 'reset_password' | undefined);
          return mail ?? {};
        });
      },
    ],
  },
);

await app.listen({ host: '127.0.0.1', port });
const address = app.server.address();
console.log(`READY ${typeof address === 'object' && address !== null ? address.port : port}`);

async function shutdown(): Promise<void> {
  await app.close();
  await database.close();
  storage.close();
  await admin.pool.query(`drop database if exists ${name} with (force)`);
  await admin.close();
  process.exit(0);
}
process.on('SIGTERM', () => void shutdown());
process.on('SIGINT', () => void shutdown());
