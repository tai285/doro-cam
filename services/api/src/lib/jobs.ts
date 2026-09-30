import { PgBoss } from 'pg-boss';

/**
 * Background jobs run on pg-boss inside the primary PostgreSQL database (ADR-0010).
 * pg-boss creates and migrates its own `pgboss` schema on start().
 */
export function createJobs(databaseUrl: string): PgBoss {
  const boss = new PgBoss(databaseUrl);
  // pg-boss emits 'error' for background failures; without a listener Node would crash the process.
  boss.on('error', () => undefined);
  return boss;
}
