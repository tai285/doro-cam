import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createJobs } from '../src/lib/jobs.ts';
import { createTestDatabase, type TestDatabase } from './helpers/database.ts';

describe('jobs (pg-boss on Postgres)', () => {
  let testDb: TestDatabase;

  beforeAll(async () => {
    testDb = await createTestDatabase();
  });
  afterAll(async () => {
    await testDb.drop();
  });

  it('[ADR-0010] installs its schema in our Postgres and processes a job end to end', async () => {
    const boss = createJobs(testDb.url);
    try {
      await boss.start();
      expect(await boss.isInstalled()).toBe(true);

      await boss.createQueue('test.echo');
      const received = new Promise<{ message: string }>((resolve) => {
        void boss.work<{ message: string }>('test.echo', async ([job]) => {
          if (job) {
            resolve(job.data);
          }
        });
      });
      await boss.send('test.echo', { message: 'hello worker' });

      await expect(received).resolves.toEqual({ message: 'hello worker' });
    } finally {
      await boss.stop({ graceful: true, timeout: 5000 });
    }
  });

  it('[ADR-0010] a job survives a restart of the worker (durable in Postgres)', async () => {
    const first = createJobs(testDb.url);
    await first.start();
    await first.createQueue('test.durable');
    const id = await first.send('test.durable', { n: 1 });
    expect(id).toBeTruthy();
    await first.stop({ graceful: true, timeout: 5000 });

    const second = createJobs(testDb.url);
    try {
      await second.start();
      const received = new Promise<{ n: number }>((resolve) => {
        void second.work<{ n: number }>('test.durable', async ([job]) => {
          if (job) {
            resolve(job.data);
          }
        });
      });
      await expect(received).resolves.toEqual({ n: 1 });
    } finally {
      await second.stop({ graceful: true, timeout: 5000 });
    }
  });

  it('does not crash the process on a background error', () => {
    const boss = createJobs(testDb.url);
    expect(boss.listenerCount('error')).toBeGreaterThanOrEqual(1);
    expect(() => boss.emit('error', new Error('background failure'))).not.toThrow();
  });
});
