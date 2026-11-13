import type { AppConfig } from '../config/env.ts';
import type { Database } from '../db/client.ts';
import type { Mailer } from '../lib/mailer.ts';
import type { JobQueue } from '../lib/queue.ts';
import type { Storage } from '../lib/storage.ts';
import type { Auth } from './auth/auth.ts';
import type { Guard } from './auth/plugin.ts';

/** Everything a feature module needs. Modules receive this explicitly rather than through globals. */
export interface Services {
  config: AppConfig;
  database: Database;
  storage: Storage;
  jobs: JobQueue;
  mailer: Mailer;
  auth: Auth;
  guard: Guard;
}

/** The subset the worker has: it never handles requests, so it needs no auth or mailer. */
export type JobServices = Pick<Services, 'config' | 'database' | 'storage' | 'jobs'>;
