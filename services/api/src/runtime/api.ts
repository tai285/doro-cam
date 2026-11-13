import type { FastifyInstance } from 'fastify';
import { PgBoss } from 'pg-boss';
import { buildApp } from '../app.ts';
import type { AppConfig } from '../config/env.ts';
import { createDatabase } from '../db/client.ts';
import { LogMailer, type MailLogger } from '../lib/mailer.ts';
import { JOBS, PgBossQueue } from '../lib/queue.ts';
import { createStorage } from '../lib/storage.ts';
import { createModules, createServices } from '../modules/index.ts';

export interface RunningApi {
  app: FastifyInstance;
  address: string;
  close(): Promise<void>;
}

/** Creates the dependencies, builds the app and starts listening. Cleans up if startup fails. */
export async function startApi(config: AppConfig): Promise<RunningApi> {
  const database = createDatabase(config.database.url);
  const storage = createStorage(config.s3);
  // The API only enqueues jobs; the worker supervises and runs them (ADR-0010).
  const boss = new PgBoss({ connectionString: config.database.url, supervise: false, schedule: false });
  boss.on('error', () => undefined);
  const closeDependencies = async () => {
    await boss.stop({ graceful: false }).catch(() => undefined);
    await database.close();
    storage.close();
  };

  try {
    await boss.start();
    for (const name of Object.values(JOBS)) {
      await boss.createQueue(name);
    }
    const loggerRef: { current: MailLogger } = { current: { info: () => undefined } };
    const services = createServices({
      config,
      database,
      storage,
      jobs: new PgBossQueue(boss),
      mailer: new LogMailer({ info: (object, message) => loggerRef.current.info(object, message) }),
    });
    const app = await buildApp({ config, database, storage }, { modules: createModules(services) });
    loggerRef.current = { info: (object, message) => app.log.info(object, message) };
    const address = await app.listen({ host: config.server.host, port: config.server.port });
    return {
      app,
      address,
      async close() {
        await app.close();
        await closeDependencies();
      },
    };
  } catch (error) {
    await closeDependencies();
    throw error;
  }
}
