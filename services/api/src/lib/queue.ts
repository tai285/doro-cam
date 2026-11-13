import type { PgBoss } from 'pg-boss';

/** Job names. Handlers live in the worker (src/modules/jobs) and are registered by name. */
export const JOBS = {
  assetVerify: 'asset.verify',
  derivativeFallback: 'derivative.fallback',
  memoryPurge: 'memory.purge',
  userDelete: 'user.delete',
  sweep: 'maintenance.sweep',
} as const;

export type JobName = (typeof JOBS)[keyof typeof JOBS];

/**
 * What the API needs from the job system: enqueue work. The API never runs jobs itself (ADR-0010);
 * production uses pg-boss, tests may use an in-process queue to run handlers deterministically.
 */
export interface JobQueue {
  enqueue(name: JobName, payload: Record<string, unknown>): Promise<void>;
}

export type JobHandler = (payload: Record<string, unknown>) => Promise<void>;

/** Sends jobs to pg-boss. The queue must exist before sending (the worker creates all queues on start). */
export class PgBossQueue implements JobQueue {
  readonly #boss: PgBoss;

  constructor(boss: PgBoss) {
    this.#boss = boss;
  }

  async enqueue(name: JobName, payload: Record<string, unknown>): Promise<void> {
    await this.#boss.send(name, payload, { retryLimit: 5, retryDelay: 5, retryBackoff: true });
  }
}

/** Runs each job immediately in this process. For tests and single-process local tools. */
export class InlineQueue implements JobQueue {
  readonly #handlers = new Map<JobName, JobHandler>();
  readonly enqueued: Array<{ name: JobName; payload: Record<string, unknown> }> = [];
  autoRun = true;

  register(name: JobName, handler: JobHandler): void {
    this.#handlers.set(name, handler);
  }

  async enqueue(name: JobName, payload: Record<string, unknown>): Promise<void> {
    this.enqueued.push({ name, payload });
    if (this.autoRun) {
      await this.run(name, payload);
    }
  }

  async run(name: JobName, payload: Record<string, unknown>): Promise<void> {
    const handler = this.#handlers.get(name);
    if (handler === undefined) {
      throw new Error(`no handler registered for job ${name}`);
    }
    await handler(payload);
  }
}
