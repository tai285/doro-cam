import { buildApp } from './app.ts';
import { loadConfig } from './config/env.ts';
import { createDatabase } from './db/client.ts';
import { OutboxMailer } from './lib/mailer.ts';
import { InlineQueue } from './lib/queue.ts';
import { createStorage } from './lib/storage.ts';
import { createModules, createServices } from './modules/index.ts';

/**
 * Builds the app against placeholder configuration (no connections are opened) and returns the OpenAPI
 * document derived from the route schemas. The committed copy is checked against this (ADR-0012).
 */
export async function generateOpenApi(): Promise<string> {
  const config = loadConfig({
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgres://openapi:openapi@127.0.0.1:1/openapi',
    S3_ENDPOINT: 'http://127.0.0.1:1',
    S3_BUCKET: 'openapi-bucket',
    S3_ACCESS_KEY_ID: 'openapi',
    S3_SECRET_ACCESS_KEY: 'openapi',
    PUBLIC_BASE_URL: 'http://localhost:3000',
  });
  const database = createDatabase(config.database.url);
  const storage = createStorage(config.s3);
  const services = createServices({ config, database, storage, jobs: new InlineQueue(), mailer: new OutboxMailer() });
  const app = await buildApp({ config, database, storage }, { modules: createModules(services) });
  try {
    await app.ready();
    return `${JSON.stringify(app.swagger(), null, 2)}\n`;
  } finally {
    await app.close();
    await database.close();
    storage.close();
  }
}
