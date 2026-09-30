import http from 'node:http';
import type { AddressInfo } from 'node:net';
import type { AppConfig } from '../config/env.ts';
import { createJobs } from '../lib/jobs.ts';

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
    throw error;
  }

  return {
    healthPort: (server.address() as AddressInfo).port,
    async close() {
      await new Promise<void>((resolve) => server.close(() => resolve()));
      await boss.stop({ graceful: true, timeout: GRACEFUL_STOP_MS });
    },
  };
}
