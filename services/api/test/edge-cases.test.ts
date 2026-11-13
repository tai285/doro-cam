import { randomBytes, randomUUID } from 'node:crypto';
import { HeadObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { PgBoss } from 'pg-boss';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { JOBS, PgBossQueue } from '../src/lib/queue.ts';
import { verifyAsset } from '../src/modules/assets/verify.ts';
import { startWorker } from '../src/runtime/worker.ts';
import { createUser, jpegBuffer, memoryBody, sha256, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';

describe('edge cases', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const api = (user: TestUser, method: 'GET' | 'POST' | 'PATCH' | 'DELETE' | 'PUT', url: string, payload?: unknown) =>
    stack.app.inject({ method, url, headers: user.headers, ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }) });
  const register = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    expect((await api(user, 'PUT', `/v1/memories/${id}`, memoryBody(overrides))).statusCode).toBe(201);
    return id;
  };
  const exists = (key: string) => stack.storage.client.send(new HeadObjectCommand({ Bucket: stack.storage.bucket, Key: key })).then(() => true, () => false);

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[SYNC-004] two uploads of identical bytes racing each other end with one stored object and one verified copy each', async () => {
    const data = await jpegBuffer(77, 55, { r: 12, g: 34, b: 56 });
    const first = await register(alice);
    const second = await register(alice);
    stack.queue.autoRun = false;
    const a = await uploadAsset(stack, alice, first, { role: 'photo_rendered', mime: 'image/jpeg', data });
    const b = await uploadAsset(stack, alice, second, { role: 'photo_rendered', mime: 'image/jpeg', data });
    stack.queue.autoRun = true;
    expect(await verifyAsset(stack.services, a.assetId)).toBe('verified');
    expect(await verifyAsset(stack.services, b.assetId)).toBe('verified');
    const { rows } = await stack.database.pool.query('select count(*)::int as n, max(ref_count)::int as refs from storage_objects where owner_id = $1', [alice.id]);
    expect(rows[0]).toEqual({ n: 1, refs: 2 });
    expect(await exists(`o/${alice.id}/${second}/${b.assetId}/photo_rendered`)).toBe(false); // the duplicate copy was removed
    const detail = (await api(alice, 'GET', `/v1/memories/${second}`)).json() as { assets: Array<{ status: string }>; thumbnail: { url: string } | null };
    expect(detail.assets[0]!.status).toBe('verified');
    expect(sha256(Buffer.from(await (await fetch((detail as unknown as { display: { url: string } }).display.url)).arrayBuffer()))).toBe(sha256(data));
  });

  it('a failed asset can be replaced under a new asset id for the same role', async () => {
    const memoryId = await register(alice);
    const wrong = await jpegBuffer(30, 30, { r: 1, g: 1, b: 1 });
    const claimed = sha256(await jpegBuffer(31, 31, { r: 2, g: 2, b: 2 }));
    const failedId = randomUUID();
    const plan = (await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${failedId}/upload`, { role: 'photo_original', mime: 'image/jpeg', bytes: wrong.length, sha256: claimed })).json() as { url: string };
    await fetch(plan.url, { method: 'PUT', headers: { 'content-type': 'image/jpeg' }, body: new Uint8Array(wrong) });
    expect(((await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${failedId}/upload/complete`, {})).json() as { status: string }).status).toBe('failed');
    const good = await jpegBuffer(32, 32, { r: 3, g: 3, b: 3 });
    const replaced = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: good });
    expect(replaced.status).toBe('verified');
    expect((await stack.database.pool.query('select count(*)::int as n from assets where memory_id = $1', [memoryId])).rows[0].n).toBe(1);
  });

  it('completing a multipart upload twice (lost response) still succeeds', async () => {
    const memoryId = await register(alice, { kind: 'motion' });
    const data = randomBytes(17 * 1024 * 1024);
    const assetId = randomUUID();
    const plan = (await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${assetId}/upload`, { role: 'motion_clip', mime: 'video/mp4', bytes: data.length, sha256: sha256(data) })).json() as { partSize: number; parts: Array<{ partNumber: number; url: string }> };
    stack.queue.autoRun = false;
    for (const part of plan.parts) {
      await fetch(part.url, { method: 'PUT', body: new Uint8Array(data.subarray((part.partNumber - 1) * plan.partSize, part.partNumber * plan.partSize)) });
    }
    // simulate: complete reached storage but the API row still says "uploading"
    expect(((await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, {})).json() as { status: string }).status).toBe('uploaded');
    await stack.database.pool.query("update assets set status = 'uploading', upload_id = coalesce(upload_id, 'gone') where id = $1", [assetId]);
    stack.queue.autoRun = true;
    expect(((await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, {})).json() as { status: string }).status).toBe('verified');
  });

  it('a multipart session that no longer exists answers upload.not_found', async () => {
    const memoryId = await register(alice, { kind: 'motion' });
    const assetId = randomUUID();
    const bytes = 17 * 1024 * 1024;
    await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${assetId}/upload`, { role: 'motion_clip', mime: 'video/mp4', bytes, sha256: 'c'.repeat(64) });
    const response = await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, { parts: [{ partNumber: 1, etag: '"nope"' }] });
    expect(response.statusCode).toBe(404);
    expect((response.json() as { error: { code: string } }).error.code).toBe('upload.not_found');
  });

  it('aborting an upload that is not in progress does nothing', async () => {
    const memoryId = await register(alice);
    expect((await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${randomUUID()}/upload/abort`)).statusCode).toBe(204);
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(9, 9, { r: 9, g: 8, b: 7 }) });
    expect((await api(alice, 'POST', `/v1/memories/${memoryId}/assets/${assetId}/upload/abort`)).statusCode).toBe(204);
    expect((await stack.database.pool.query('select status from assets where id = $1', [assetId])).rows[0].status).toBe('verified');
  });

  it('[PRIV-002] the owner streams their own media through the content endpoint, untouched', async () => {
    const memoryId = await register(alice);
    const data = await jpegBuffer(40, 40, { r: 70, g: 80, b: 90 });
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data });
    const content = await api(alice, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/content`);
    expect(content.statusCode).toBe(200);
    expect(content.headers['cache-control']).toBe('private, no-store');
    expect(sha256(content.rawPayload)).toBe(sha256(data));
  });

  it('[SYNC-004] registering an id that is in the trash returns it instead of failing', async () => {
    const id = await register(alice);
    await api(alice, 'POST', `/v1/memories/${id}/trash`);
    const again = await api(alice, 'PUT', `/v1/memories/${id}`, memoryBody());
    expect(again.statusCode).toBe(200);
    expect((again.json() as { deletedAt: string | null }).deletedAt).not.toBeNull();
  });

  it('[SHR-001] album settings can be changed one by one and each change is applied', async () => {
    const album = (await api(alice, 'POST', '/v1/albums', { title: 'Settings' })).json() as { id: string };
    const patched = (await api(alice, 'PATCH', `/v1/albums/${album.id}`, {
      description: 'Notes', kind: 'trip', startsOn: '2027-01-01', endsOn: '2027-01-09', allowOriginalDownload: false, shareLocation: true, autoAddDuringTrip: true,
    })).json() as Record<string, unknown>;
    expect(patched).toMatchObject({ description: 'Notes', kind: 'trip', startsOn: '2027-01-01', endsOn: '2027-01-09', allowOriginalDownload: false, shareLocation: true, autoAddDuringTrip: true });
    expect(((await api(alice, 'PATCH', `/v1/albums/${album.id}`, { description: null })).json() as { description: string | null }).description).toBeNull();
    const badDates = await api(alice, 'PATCH', `/v1/albums/${album.id}`, { endsOn: '2026-12-01' });
    expect((badDates.json() as { error: { code: string } }).error.code).toBe('album.invalid_dates');
    expect(((await api(alice, 'PATCH', `/v1/albums/${album.id}`, { kind: 'album', startsOn: null, endsOn: null })).json() as { kind: string }).kind).toBe('album');
  });

  it('[SHR-003] an invite can be emailed, and unknown members and albums answer 404', async () => {
    const album = (await api(alice, 'POST', '/v1/albums', { title: 'Mail' })).json() as { id: string };
    const response = await api(alice, 'POST', `/v1/albums/${album.id}/invites`, { role: 'viewer', email: 'friend@example.test' });
    expect(response.statusCode).toBe(201);
    const mail = stack.mailer.last('album_invite');
    expect(mail?.to).toBe('friend@example.test');
    expect(mail?.link).toContain(`/invites/${(response.json() as { token: string }).token}`);
    expect((await api(alice, 'PATCH', `/v1/albums/${album.id}/members/${randomUUID()}`, { role: 'viewer' })).statusCode).toBe(404);
    expect((await api(alice, 'DELETE', `/v1/albums/${album.id}/members/${randomUUID()}`)).statusCode).toBe(404);

    const { token } = response.json() as { token: string };
    await api(alice, 'DELETE', `/v1/albums/${album.id}`);
    expect((await api(bob, 'POST', '/v1/invites/accept', { token })).statusCode).toBe(404); // a deleted album cannot be joined
  });

  it('[SHR-001] adding missing or trashed Memories is refused, and trashed ones leave album listings', async () => {
    const album = (await api(alice, 'POST', '/v1/albums', { title: 'Gone' })).json() as { id: string };
    expect((await api(alice, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [randomUUID()] })).statusCode).toBe(404);
    const id = await register(alice);
    await api(alice, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [id] });
    await api(alice, 'POST', `/v1/memories/${id}/trash`);
    expect((await api(alice, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [id] })).statusCode).toBe(404);
    expect(((await api(alice, 'GET', `/v1/albums/${album.id}/memories`)).json() as { items: unknown[] }).items).toEqual([]);
    expect((await api(alice, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [] })).statusCode).toBe(400);
  });

  it('[ANL-002] summary accepts a one-sided time range', async () => {
    await register(alice, { capturedAt: '2026-08-01T00:00:00.000Z' });
    const from = (await api(alice, 'GET', '/v1/insights/summary?from=2026-07-01T00:00:00Z')).json() as { total: number };
    const to = (await api(alice, 'GET', '/v1/insights/summary?to=2000-01-01T00:00:00Z')).json() as { total: number };
    expect(from.total).toBeGreaterThan(0);
    expect(to.total).toBe(0);
  });

  it('serves an OpenAPI document that describes the memory and upload routes', async () => {
    const response = await stack.app.inject({ method: 'GET', url: '/v1/openapi.json' });
    expect(response.statusCode).toBe(200);
    const spec = response.json() as { openapi: string; paths: Record<string, unknown> };
    expect(spec.openapi).toMatch(/^3\./);
    for (const path of ['/v1/memories', '/v1/memories/{memoryId}', '/v1/memories/{memoryId}/assets/{assetId}/upload', '/v1/albums', '/v1/sync/changes', '/v1/me']) {
      expect(spec.paths[path], path).toBeDefined();
    }
  });

  it('sends CORS headers only for configured web origins', async () => {
    const allowed = await stack.app.inject({ method: 'OPTIONS', url: '/v1/me', headers: { origin: 'http://localhost:5173', 'access-control-request-method': 'GET' } });
    expect(allowed.headers['access-control-allow-origin']).toBe('http://localhost:5173');
    expect(allowed.headers['access-control-allow-credentials']).toBe('true');
    const denied = await stack.app.inject({ method: 'OPTIONS', url: '/v1/me', headers: { origin: 'https://evil.example', 'access-control-request-method': 'GET' } });
    expect(denied.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('rate limits sign-in attempts with the documented envelope', async () => {
    const limited = await startStack({ AUTH_RATE_LIMIT_PER_MINUTE: '3' });
    try {
      const codes: number[] = [];
      let body: { error?: { code?: string } } = {};
      for (let i = 0; i < 5; i += 1) {
        const response = await limited.app.inject({ method: 'POST', url: '/v1/auth/sign-in/email', payload: { email: 'x@example.test', password: 'wrong-password-here' } });
        codes.push(response.statusCode);
        if (response.statusCode === 429) body = response.json();
      }
      expect(codes.slice(-2)).toEqual([429, 429]);
      expect(body.error?.code).toBe('rate_limited');
    } finally {
      await limited.close();
    }
  });

  it('orphan objects of a removed asset never block re-upload: PUT of a fresh object overwrites', async () => {
    const memoryId = await register(alice);
    const data = await jpegBuffer(19, 19, { r: 5, g: 6, b: 7 });
    const assetId = randomUUID();
    const key = `o/${alice.id}/${memoryId}/${assetId}/photo_original`;
    await stack.storage.client.send(new PutObjectCommand({ Bucket: stack.storage.bucket, Key: key, Body: Buffer.from('stale'), ContentType: 'image/jpeg' }));
    const result = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data, assetId });
    expect(result.status).toBe('verified');
  });
});

describe('job queue integration (pg-boss on real Postgres)', () => {
  it('[NFR-013] PgBossQueue sends a job and the worker runs the handler to completion', async () => {
    const stack = await startStack();
    let worker: Awaited<ReturnType<typeof startWorker>> | undefined;
    const boss = new PgBoss({ connectionString: stack.config.database.url, supervise: false, schedule: false });
    boss.on('error', () => undefined);
    try {
      await boss.start();
      for (const name of Object.values(JOBS)) await boss.createQueue(name);
      worker = await startWorker({ ...stack.config, worker: { healthPort: 0 }, server: { ...stack.config.server, host: '127.0.0.1' } });
      const alice = await createUser(stack, 'Queue');
      const id = randomUUID();
      await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: alice.headers, payload: memoryBody() });
      await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: alice.headers });
      await new PgBossQueue(boss).enqueue(JOBS.memoryPurge, { memoryId: id });
      let remaining = 1;
      for (let i = 0; i < 60 && remaining > 0; i += 1) {
        remaining = (await stack.database.pool.query('select count(*)::int as n from memories where id = $1', [id])).rows[0].n;
        if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, 500));
      }
      expect(remaining).toBe(0);
    } finally {
      await worker?.close();
      await boss.stop({ graceful: false });
      await stack.close();
    }
  });
});
