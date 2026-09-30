import { defineConfig } from 'drizzle-kit';

// Modules own their tables and re-export them from src/db/schema.ts (docs/architecture/backend.md).
export default defineConfig({
  dialect: 'postgresql',
  schema: './src/db/schema.ts',
  out: './migrations',
  dbCredentials: { url: process.env.DATABASE_URL ?? '' },
});
