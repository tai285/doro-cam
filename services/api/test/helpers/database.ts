import { randomBytes } from 'node:crypto';
import pg from 'pg';
import { baseEnv } from './env.ts';

export interface TestDatabase {
  url: string;
  name: string;
  drop(): Promise<void>;
}

/** Creates a private database on the local Postgres so test files never share state. */
export async function createTestDatabase(): Promise<TestDatabase> {
  const adminUrl = baseEnv().DATABASE_URL as string;
  const name = `doro_test_${randomBytes(6).toString('hex')}`;

  const admin = new pg.Client({ connectionString: adminUrl });
  await admin.connect();
  try {
    await admin.query(`create database ${name}`);
  } finally {
    await admin.end();
  }

  const url = new URL(adminUrl);
  url.pathname = `/${name}`;
  return {
    url: url.toString(),
    name,
    async drop() {
      const client = new pg.Client({ connectionString: adminUrl });
      await client.connect();
      try {
        await client.query(`drop database if exists ${name} with (force)`);
      } finally {
        await client.end();
      }
    },
  };
}

/** Number of open connections to a database (used to prove cleanup after failures). */
export async function connectionCount(databaseName: string): Promise<number> {
  const client = new pg.Client({ connectionString: baseEnv().DATABASE_URL as string });
  await client.connect();
  try {
    const { rows } = await client.query<{ count: string }>(
      'select count(*) from pg_stat_activity where datname = $1',
      [databaseName],
    );
    return Number(rows[0]?.count ?? 0);
  } finally {
    await client.end();
  }
}
