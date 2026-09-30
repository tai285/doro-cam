import { type ChildProcess, spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { freePort } from './helpers/app.ts';
import { createTestDatabase, type TestDatabase } from './helpers/database.ts';
import { baseEnv } from './helpers/env.ts';

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Starts an entrypoint as a real child process. Only the given environment is passed on. */
function start(entry: string, env: NodeJS.ProcessEnv) {
  const child = spawn(process.execPath, [entry], {
    cwd: packageDir,
    env: { ...(process.env.SystemRoot ? { SystemRoot: process.env.SystemRoot } : {}), ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', (chunk: Buffer) => (output += chunk.toString()));
  child.stderr.on('data', (chunk: Buffer) => (output += chunk.toString()));
  const exited = new Promise<number | null>((resolve) => child.once('exit', (code) => resolve(code)));
  return { child, exited, output: () => output };
}

async function stop(child: ChildProcess, exited: Promise<number | null>): Promise<void> {
  if (child.exitCode === null) {
    child.kill();
  }
  await exited;
}

async function waitForHealth(url: string, isAlive: () => boolean): Promise<Response> {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (!isAlive()) {
      throw new Error('process exited before becoming healthy');
    }
    try {
      const response = await fetch(url);
      if (response.ok) {
        return response;
      }
    } catch {
      // not listening yet
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`no healthy response from ${url}`);
}

describe('process entrypoints', () => {
  let testDb: TestDatabase;

  beforeAll(async () => {
    testDb = await createTestDatabase();
  });
  afterAll(async () => {
    await testDb.drop();
  });

  it('[NFR-013] src/server.ts starts the API as a real process and answers requests', async () => {
    const port = await freePort();
    const run = start('src/server.ts', baseEnv({ DATABASE_URL: testDb.url, HOST: '127.0.0.1', PORT: String(port) }));
    try {
      const health = await waitForHealth(`http://127.0.0.1:${port}/healthz`, () => run.child.exitCode === null);
      expect(await health.json()).toEqual({ status: 'ok' });
      const ready = await fetch(`http://127.0.0.1:${port}/readyz`);
      expect(ready.status).toBe(200);
    } finally {
      await stop(run.child, run.exited);
    }
  });

  it('[NFR-013] src/worker.ts starts the worker as a real process with a health endpoint', async () => {
    const port = await freePort();
    const run = start(
      'src/worker.ts',
      baseEnv({ DATABASE_URL: testDb.url, HOST: '127.0.0.1', WORKER_HEALTH_PORT: String(port) }),
    );
    try {
      const health = await waitForHealth(`http://127.0.0.1:${port}/healthz`, () => run.child.exitCode === null);
      expect(await health.json()).toEqual({ status: 'ok', role: 'worker' });
    } finally {
      await stop(run.child, run.exited);
    }
  });

  it('[NFR-011] exits 1 on invalid configuration and lists the variables without echoing values', async () => {
    const run = start('src/server.ts', {
      DATABASE_URL: 'mysql://user:leaked-password@db/app',
      S3_BUCKET: 'BAD',
    });
    const code = await run.exited;
    expect(code).toBe(1);
    const output = run.output();
    expect(output).toContain('Startup failed');
    expect(output).toContain('DATABASE_URL');
    expect(output).toContain('S3_ENDPOINT: is required');
    expect(output).not.toContain('leaked-password');
  });
});
