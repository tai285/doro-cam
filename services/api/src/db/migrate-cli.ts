import { loadConfig } from '../config/env.ts';
import { createDatabase } from './client.ts';
import { runMigrations } from './migrate.ts';

const config = loadConfig();
const database = createDatabase(config.database.url);
try {
  await runMigrations(database.pool);
  console.log('Migrations applied.');
} finally {
  await database.close();
}
