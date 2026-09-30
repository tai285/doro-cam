import net, { type AddressInfo } from 'node:net';
import type { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { buildApp } from '../../src/app.ts';
import { type AppConfig, loadConfig } from '../../src/config/env.ts';
import { createDatabase, type Database } from '../../src/db/client.ts';
import { createStorage, type Storage } from '../../src/lib/storage.ts';
import { baseEnv } from './env.ts';

export interface TestApp {
  app: FastifyInstance;
  config: AppConfig;
  database: Database;
  storage: Storage;
  close(): Promise<void>;
}

export interface TestAppOptions {
  env?: Record<string, string | undefined>;
  modules?: readonly FastifyPluginAsync[];
  logStream?: NodeJS.WritableStream;
}

/** Builds the real app with real dependencies (no mocks) from the test environment. */
export async function buildTestApp(options: TestAppOptions = {}): Promise<TestApp> {
  const config = loadConfig(baseEnv(options.env));
  const database = createDatabase(config.database.url);
  const storage = createStorage(config.s3);
  const app = await buildApp(
    { config, database, storage },
    {
      ...(options.modules === undefined ? {} : { modules: options.modules }),
      ...(options.logStream === undefined ? {} : { logStream: options.logStream }),
    },
  );
  await app.ready();
  return {
    app,
    config,
    database,
    storage,
    async close() {
      await app.close();
      await database.close();
      storage.close();
    },
  };
}

/** A currently free TCP port on localhost. */
export async function freePort(): Promise<number> {
  const server = net.createServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  await new Promise<void>((resolve) => server.close(() => resolve()));
  return port;
}

/** Occupies a port until closed, to provoke EADDRINUSE. */
export async function occupyPort(): Promise<{ port: number; close(): Promise<void> }> {
  const server = net.createServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return { port, close: () => new Promise<void>((resolve) => server.close(() => resolve())) };
}
