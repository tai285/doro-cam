import http from 'node:http';
import type { AddressInfo } from 'node:net';
import type { AppConfig } from '../config/env.ts';
import { createDatabase } from '../db/client.ts';
import { createJobs } from '../lib/jobs.ts';
import { type JobName, JOBS, PgBossQueue } from '../lib/queue.ts';
import { createStorage } from '../lib/storage.ts';
import { createJobHandlers } from '../modules/jobs/handlers.ts';

export interface RunningWorker {
  /** Port of the health endpoint (useful when configured with port 0). */
  healthPort: number;
  close(): Promise<void>;
}

/** How long stop() waits for in-flight jobs before giving up. */
const GRACEFUL_STOP_MS = 20_000;

/**
 * Starts pg-boss and a tiny health endpoint. The worker serves no other HTTP (docs/architecture/backend.md).
 * Job handlers are registered here by their modules as they are added.
 */
export async function startWorker(config: AppConfig): Promise<RunningWorker> {
  const boss = createJobs(config.database.url);
  await boss.start();
  const database = createDatabase(config.database.url);
  const storage = createStorage(config.s3);
  const handlers = createJobHandlers({ config, database, storage, jobs: new PgBossQueue(boss) });
  for (const name of Object.values(JOBS) as JobName[]) {
    await boss.createQueue(name);
    const handler = handlers[name];
    await boss.work(name, async (jobs) => {
      for (const job of jobs) {
        await handler((job.data ?? {}) as Record<string, unknown>);
      }
    });
  }
  await boss.schedule(JOBS.sweep, '*/15 * * * *');

  const server = http.createServer((request, response) => {
    if (request.method === 'GET' && request.url === '/healthz') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ status: 'ok', role: 'worker' }));
      return;
    }
    response.writeHead(404, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ error: { code: 'route.not_found' } }));
  });

  try {
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(config.worker.healthPort, config.server.host, () => {
        server.off('error', reject);
        resolve();
      });
    });
  } catch (error) {
    await boss.stop({ graceful: false });
    await database.close();
    storage.close();
    throw error;
  }

  return {
    healthPort: (server.address() as AddressInfo).port,
    async close() {
      await new Promise<void>((resolve) => server.close(() => resolve()));
      await boss.stop({ graceful: true, timeout: GRACEFUL_STOP_MS });
      await database.close();
      storage.close();
    },
  };
}
