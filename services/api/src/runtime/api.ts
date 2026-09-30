import type { FastifyInstance } from 'fastify';
import { buildApp } from '../app.ts';
import type { AppConfig } from '../config/env.ts';
import { createDatabase } from '../db/client.ts';
import { createStorage } from '../lib/storage.ts';

export interface RunningApi {
  app: FastifyInstance;
  address: string;
  close(): Promise<void>;
}

/** Creates the dependencies, builds the app and starts listening. Cleans up if startup fails. */
export async function startApi(config: AppConfig): Promise<RunningApi> {
  const database = createDatabase(config.database.url);
  const storage = createStorage(config.s3);
  const closeDependencies = async () => {
    await database.close();
    storage.close();
  };

  try {
    const app = await buildApp({ config, database, storage });
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
