import { randomUUID } from 'node:crypto';
import { Writable } from 'node:stream';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createUser, jpegBuffer, memoryBody, PASSWORD, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';

/** Collects every log line so tests can assert on what gets written (NFR-011). */
class LogCapture extends Writable {
  readonly lines: string[] = [];
  override _write(chunk: Buffer, _encoding: BufferEncoding, done: () => void): void {
    this.lines.push(...chunk.toString().split('\n').filter((line) => line !== ''));
    done();
  }
  get text(): string {
    return this.lines.join('\n');
  }
}

describe('logging (NFR-011)', () => {
  const capture = new LogCapture();
  let stack: Stack;
  let user: TestUser;

  beforeAll(async () => {
    stack = await startStack({ LOG_LEVEL: 'debug' }, { logStream: capture });
    user = await createUser(stack, 'Logger');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[NFR-011] writes structured JSON with a request id for every request', async () => {
    capture.lines.length = 0;
    const response = await stack.app.inject({ method: 'GET', url: '/v1/me', headers: user.headers });
    const parsed = capture.lines.map((line) => JSON.parse(line) as Record<string, unknown>);
    expect(parsed.length).toBeGreaterThan(0);
    const completed = parsed.find((entry) => entry.msg === 'request completed');
    expect(completed).toMatchObject({ reqId: response.headers['x-request-id'], res: { statusCode: 200 } });
  });

  it('[NFR-011] never logs passwords, session tokens, cookies or authorization headers', async () => {
    capture.lines.length = 0;
    const email = `log-${randomUUID().slice(0, 6)}@example.test`;
    await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-up/email', payload: { name: 'L', email, password: PASSWORD } });
    await stack.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email, password: 'not-the-right-one' } });
    await stack.app.inject({ method: 'GET', url: '/v1/me', headers: { ...user.headers, cookie: 'better-auth.session_token=SECRET-COOKIE-VALUE' } });
    const token = user.bearer.replace('Bearer ', '');
    expect(capture.text).not.toContain(PASSWORD);
    expect(capture.text).not.toContain('not-the-right-one');
    expect(capture.text).not.toContain(token);
    expect(capture.text).not.toContain('SECRET-COOKIE-VALUE');
  });

  it('[NFR-011] never logs precise location, captions or media links', async () => {
    capture.lines.length = 0;
    const id = randomUUID();
    await stack.app.inject({
      method: 'PUT',
      url: `/v1/memories/${id}`,
      headers: user.headers,
      payload: memoryBody({ caption: 'PRIVATE-CAPTION-TEXT', location: { lat: 3.1390123, lon: 101.6869456 } }),
    });
    await uploadAsset(stack, user, id, { role: 'thumbnail', mime: 'image/jpeg', data: await jpegBuffer(16, 16) });
    await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: user.headers, payload: { caption: 'ANOTHER-PRIVATE-NOTE' } });
    for (const secret of ['PRIVATE-CAPTION-TEXT', 'ANOTHER-PRIVATE-NOTE', '3.1390123', '101.6869456', 'X-Amz-Signature']) {
      expect(capture.text, secret).not.toContain(secret);
    }
  });

  it('[NFR-011] failed requests are logged without echoing their bodies', async () => {
    capture.lines.length = 0;
    await stack.app.inject({ method: 'PUT', url: `/v1/memories/${randomUUID()}`, headers: user.headers, payload: { kind: 'hologram', caption: 'LEAKY-CAPTION' } });
    expect(capture.text).not.toContain('LEAKY-CAPTION');
  });

  it('[NFR-011] echoes a caller-supplied request id and replaces a malformed one', async () => {
    const ok = await stack.app.inject({ method: 'GET', url: '/healthz', headers: { 'x-request-id': 'trace-me-123' } });
    expect(ok.headers['x-request-id']).toBe('trace-me-123');
    const bad = await stack.app.inject({ method: 'GET', url: '/healthz', headers: { 'x-request-id': 'bad id with spaces & junk' } });
    expect(bad.headers['x-request-id']).not.toContain(' ');
  });
});

describe('latency baseline (NFR-006)', () => {
  let stack: Stack;
  let user: TestUser;
  /** Budgets recorded from the first baseline (docs/specs/api.md "Latency budgets"). Generous on purpose: they catch regressions, not noise. */
  const BUDGET_P95_MS = { me: 60, list: 120, register: 120, detail: 80 };

  const measure = async (count: number, work: (i: number) => Promise<unknown>) => {
    const samples: number[] = [];
    for (let i = 0; i < count; i += 1) {
      const started = performance.now();
      await work(i);
      samples.push(performance.now() - started);
    }
    samples.sort((a, b) => a - b);
    return { p50: samples[Math.floor(count * 0.5)] as number, p95: samples[Math.floor(count * 0.95)] as number };
  };

  beforeAll(async () => {
    stack = await startStack();
    user = await createUser(stack, 'Perf');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[NFR-006] stays inside the recorded p95 budgets for the hot endpoints (in-process, real database)', async () => {
    const ids: string[] = [];
    const register = await measure(60, async (i) => {
      const id = randomUUID();
      ids.push(id);
      const response = await stack.app.inject({
        method: 'PUT',
        url: `/v1/memories/${id}`,
        headers: user.headers,
        payload: memoryBody({ capturedAt: new Date(Date.UTC(2026, 0, 1, 0, i)).toISOString() }),
      });
      expect(response.statusCode).toBe(201);
    });
    const me = await measure(60, () => stack.app.inject({ method: 'GET', url: '/v1/me', headers: user.headers }));
    const list = await measure(40, () => stack.app.inject({ method: 'GET', url: '/v1/memories?limit=50', headers: user.headers }));
    const detail = await measure(60, (i) => stack.app.inject({ method: 'GET', url: `/v1/memories/${ids[i % ids.length] as string}`, headers: user.headers }));
    console.info('latency baseline (ms)', JSON.stringify({ register, me, list, detail }));
    expect(me.p95).toBeLessThan(BUDGET_P95_MS.me);
    expect(list.p95).toBeLessThan(BUDGET_P95_MS.list);
    expect(register.p95).toBeLessThan(BUDGET_P95_MS.register);
    expect(detail.p95).toBeLessThan(BUDGET_P95_MS.detail);
  });
});
