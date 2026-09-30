import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import pg from 'pg';

export interface Database {
  pool: pg.Pool;
  db: NodePgDatabase;
  /** Resolves when a trivial query succeeds. */
  check(): Promise<void>;
  close(): Promise<void>;
}

export function createDatabase(connectionString: string): Database {
  const pool = new pg.Pool({
    connectionString,
    max: 10,
    connectionTimeoutMillis: 2000,
    // A stalled query must not hang a readiness probe or a request forever.
    query_timeout: 10_000,
  });
  // Idle clients can error (server restart). Without a listener Node would crash the process.
  pool.on('error', () => undefined);
  return {
    pool,
    db: drizzle(pool),
    async check() {
      await pool.query('select 1');
    },
    async close() {
      await pool.end();
    },
  };
}
