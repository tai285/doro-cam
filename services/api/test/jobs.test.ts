import { randomUUID } from 'node:crypto';
import { HeadObjectCommand } from '@aws-sdk/client-s3';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { newPublicHandle, newToken, sha256Hex, stableHash } from '../src/lib/ids.ts';
import { LogMailer, OutboxMailer } from '../src/lib/mailer.ts';
import { InlineQueue, JOBS } from '../src/lib/queue.ts';
import { presignGet } from '../src/lib/presign.ts';
import { MIB, SINGLE_UPLOAD_MAX_BYTES, checkUpload, planUpload } from '../src/modules/assets/rules.ts';
import { createJobHandlers, deleteUser, purgeMemory, sweep } from '../src/modules/jobs/handlers.ts';
import { createUser, jpegBuffer, memoryBody, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';

describe('ids', () => {
  it('[MEM-008] public handles are 22 base62 characters and do not repeat', () => {
    const handles = new Set(Array.from({ length: 200 }, newPublicHandle));
    expect(handles.size).toBe(200);
    for (const handle of handles) expect(handle).toMatch(/^[0-9A-Za-z]{22}$/);
  });
  it('invite tokens are 256-bit url-safe strings and hashing is stable', () => {
    expect(newToken()).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(newToken()).not.toBe(newToken());
    expect(sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
  it('stableHash ignores key order at every depth', () => {
    expect(stableHash({ a: 1, b: { c: [1, { y: 2, x: 1 }] } })).toBe(stableHash({ b: { c: [1, { x: 1, y: 2 }] }, a: 1 }));
    expect(stableHash({ a: 1 })).not.toBe(stableHash({ a: 2 }));
  });
});

describe('mailers and queue', () => {
  it('OutboxMailer keeps messages and finds the last one by kind', async () => {
    const mailer = new OutboxMailer();
    await mailer.send({ kind: 'verify_email', to: 'a@x.test', subject: 's', text: 't', link: 'http://l/1' });
    await mailer.send({ kind: 'reset_password', to: 'a@x.test', subject: 's', text: 't', link: 'http://l/2' });
    expect(mailer.last()?.link).toBe('http://l/2');
    expect(mailer.last('verify_email')?.link).toBe('http://l/1');
    expect(mailer.last('album_invite')).toBeUndefined();
  });
  it('LogMailer writes the message to the log instead of delivering it', async () => {
    const info = vi.fn();
    await new LogMailer({ info }).send({ kind: 'verify_email', to: 'a@x.test', subject: 'Hi', text: 't', link: 'http://l/1' });
    expect(info).toHaveBeenCalledWith({ mail: { kind: 'verify_email', to: 'a@x.test', subject: 'Hi', link: 'http://l/1' } }, expect.stringContaining('not delivered'));
  });
  it('InlineQueue runs handlers, can defer them, and fails loudly for an unregistered job', async () => {
    const queue = new InlineQueue();
    const seen: unknown[] = [];
    queue.register(JOBS.assetVerify, async (payload) => void seen.push(payload));
    await queue.enqueue(JOBS.assetVerify, { assetId: 'a' });
    queue.autoRun = false;
    await queue.enqueue(JOBS.assetVerify, { assetId: 'b' });
    expect(seen).toEqual([{ assetId: 'a' }]);
    expect(queue.enqueued).toHaveLength(2);
    await expect(queue.run(JOBS.memoryPurge, {})).rejects.toThrow('no handler registered');
  });
});

describe('upload rules', () => {
  it('[SYNC-003] plans single uploads up to 16 MiB and multipart above, with the documented part size', () => {
    expect(planUpload(1)).toEqual({ mode: 'single' });
    expect(planUpload(SINGLE_UPLOAD_MAX_BYTES)).toEqual({ mode: 'single' });
    expect(planUpload(SINGLE_UPLOAD_MAX_BYTES + 1)).toEqual({ mode: 'multipart', partSize: 8 * MIB, partCount: 3 });
    expect(planUpload(200 * MIB)).toEqual({ mode: 'multipart', partSize: 8 * MIB, partCount: 25 });
    const huge = 4096 * MIB;
    const plan = planUpload(huge) as { partSize: number; partCount: number };
    expect(plan.partSize % MIB).toBe(0);
    expect(plan.partCount).toBeLessThanOrEqual(10_000);
    const larger = planUpload(100_000 * MIB) as { partSize: number; partCount: number };
    expect(larger.partCount).toBeLessThanOrEqual(10_000);
    expect(larger.partSize).toBeGreaterThan(8 * MIB);
  });
  it('accepts and rejects role, kind, type and size combinations', () => {
    expect(checkUpload('photo_original', 'photo', 'image/heic', 5 * MIB)).toEqual({ ok: true });
    expect(checkUpload('photo_original', 'video', 'image/jpeg', 1)).toEqual({ ok: false, code: 'role_not_allowed' });
    expect(checkUpload('thumbnail', 'video', 'image/jpeg', 1)).toEqual({ ok: true });
    expect(checkUpload('motion_clip', 'motion', 'image/jpeg', 1)).toEqual({ ok: false, code: 'unsupported_type' });
    expect(checkUpload('photo_display', 'photo', 'image/jpeg', 21 * MIB)).toEqual({ ok: false, code: 'too_large' });
  });
});

describe('background jobs', () => {
  let stack: Stack;
  let alice: TestUser;

  const register = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: memoryBody(overrides) });
    return id;
  };
  const objectExists = async (key: string) =>
    stack.storage.client.send(new HeadObjectCommand({ Bucket: stack.storage.bucket, Key: key })).then(() => true, () => false);
  const keyOf = async (assetId: string) => (await stack.database.pool.query('select o.key from assets a join storage_objects o on o.id = a.storage_object_id where a.id = $1', [assetId])).rows[0]?.key as string | undefined;

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[MEM-007] purging deletes the rows and the stored objects, and is idempotent', async () => {
    const memoryId = await register(alice);
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(33, 44) });
    const key = (await keyOf(assetId))!;
    expect(await objectExists(key)).toBe(true);
    expect(await purgeMemory(stack.services, memoryId)).toBe(true);
    expect(await objectExists(key)).toBe(false);
    expect((await stack.database.pool.query('select count(*)::int as n from memories where id = $1', [memoryId])).rows[0].n).toBe(0);
    expect((await stack.database.pool.query('select count(*)::int as n from assets where memory_id = $1', [memoryId])).rows[0].n).toBe(0);
    expect(await purgeMemory(stack.services, memoryId)).toBe(false);
    const me = (await stack.app.inject({ method: 'GET', url: '/v1/me', headers: alice.headers })).json() as { storage: { usedBytes: number } };
    expect(me.storage.usedBytes).toBe(0);
  });

  it('[MEM-007] a shared object survives until its last Memory is purged', async () => {
    const data = await jpegBuffer(55, 66, { r: 4, g: 5, b: 6 });
    const first = await register(alice);
    const second = await register(alice);
    const { assetId } = await uploadAsset(stack, alice, first, { role: 'photo_rendered', mime: 'image/jpeg', data });
    await uploadAsset(stack, alice, second, { role: 'photo_rendered', mime: 'image/jpeg', data });
    const key = (await keyOf(assetId))!;
    await purgeMemory(stack.services, first);
    expect(await objectExists(key)).toBe(true);
    await purgeMemory(stack.services, second);
    expect(await objectExists(key)).toBe(false);
  });

  it('[PRIV-004] deleting an account removes every row and object the user owned, and nothing else', async () => {
    const victim = await createUser(stack, 'Victim');
    const bystander = await createUser(stack, 'Bystander');
    const mine = await register(victim);
    const theirs = await register(bystander);
    const { assetId } = await uploadAsset(stack, victim, mine, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(21, 21, { r: 7, g: 7, b: 7 }) });
    const { assetId: otherAsset } = await uploadAsset(stack, bystander, theirs, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(22, 22, { r: 8, g: 8, b: 8 }) });
    await stack.app.inject({ method: 'POST', url: '/v1/albums', headers: victim.headers, payload: { title: 'Mine' } });
    await stack.app.inject({ method: 'PUT', url: `/v1/presets/${randomUUID()}`, headers: victim.headers, payload: { name: 'P', experienceId: 'mirrorless', intent: {} } });
    const victimKey = (await keyOf(assetId))!;
    const otherKey = (await keyOf(otherAsset))!;

    expect(await deleteUser(stack.services, victim.id)).toBe(true);
    expect(await objectExists(victimKey)).toBe(false);
    expect(await objectExists(otherKey)).toBe(true);
    for (const table of ['memories', 'assets', 'albums', 'presets', 'storage_objects', 'session', 'account', 'users_profile', 'change_log']) {
      const column = table === 'session' || table === 'account' ? 'user_id' : table === 'users_profile' ? 'user_id' : 'owner_id';
      expect((await stack.database.pool.query(`select count(*)::int as n from "${table}" where ${column} = $1`, [victim.id])).rows[0].n, table).toBe(0);
    }
    expect((await stack.database.pool.query('select count(*)::int as n from "user" where id = $1', [victim.id])).rows[0].n).toBe(0);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/me', headers: victim.headers })).statusCode).toBe(401);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/me', headers: bystander.headers })).statusCode).toBe(200);
    expect(await deleteUser(stack.services, victim.id)).toBe(false); // idempotent
  });

  it('[PRIV-004] the sweep deletes accounts only after the 7-day grace period', async () => {
    const early = await createUser(stack, 'Early');
    const due = await createUser(stack, 'Due');
    await stack.app.inject({ method: 'POST', url: '/v1/me/deletion', headers: early.headers, payload: { password: early.password } });
    await stack.app.inject({ method: 'POST', url: '/v1/me/deletion', headers: due.headers, payload: { password: due.password } });
    await stack.database.pool.query("update users_profile set deletion_requested_at = now() - interval '8 days' where user_id = $1", [due.id]);
    await stack.database.pool.query("update users_profile set deletion_requested_at = now() - interval '6 days' where user_id = $1", [early.id]);
    const result = await sweep(stack.services);
    expect(result.deletedUsers).toBe(1);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/me', headers: early.headers })).statusCode).toBe(200);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/me', headers: due.headers })).statusCode).toBe(401);
  });

  it('[MEM-007] the sweep purges Memories trashed more than 30 days ago and keeps newer trash', async () => {
    const old = await register(alice);
    const recent = await register(alice);
    for (const id of [old, recent]) await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: alice.headers });
    await stack.database.pool.query("update memories set deleted_at = now() - interval '31 days' where id = $1", [old]);
    await stack.database.pool.query("update memories set deleted_at = now() - interval '29 days' where id = $1", [recent]);
    const result = await sweep(stack.services);
    expect(result.purgedMemories).toBeGreaterThanOrEqual(1);
    expect((await stack.database.pool.query('select id from memories where id = any($1)', [[old, recent]])).rows.map((r: { id: string }) => r.id)).toEqual([recent]);
  });

  it('the sweep creates missing derivatives only for renderings older than ten minutes, and prunes old feed entries and keys', async () => {
    const erin = await createUser(stack, 'Erin');
    const memoryId = await register(erin);
    await uploadAsset(stack, erin, memoryId, { role: 'photo_rendered', mime: 'image/jpeg', data: await jpegBuffer(900, 600) });
    expect((await sweep(stack.services)).derivatives).toBe(0); // too fresh: the device may still be uploading its own
    await stack.database.pool.query("update assets set updated_at = now() - interval '20 minutes' where memory_id = $1", [memoryId]);
    expect((await sweep(stack.services)).derivatives).toBe(2);
    expect((await sweep(stack.services)).derivatives).toBe(0);

    await stack.database.pool.query("update change_log set at = now() - interval '91 days' where owner_id = $1", [erin.id]);
    await stack.database.pool.query("insert into idempotency_keys (key, owner_id, route, request_hash, status_code, response, created_at) values ('k', $1, 'r', 'h', 200, '{}', now() - interval '2 days')", [erin.id]);
    const result = await sweep(stack.services);
    expect(result.prunedChanges).toBeGreaterThan(0);
    expect(result.prunedKeys).toBe(1);
  });

  it('job handlers dispatch by name and reject malformed payloads', async () => {
    const handlers = createJobHandlers(stack.services);
    expect(Object.keys(handlers).sort()).toEqual(Object.values(JOBS).sort());
    await expect(handlers[JOBS.memoryPurge]({})).rejects.toThrow('missing "memoryId"');
    await expect(handlers[JOBS.userDelete]({ userId: 5 })).rejects.toThrow('missing "userId"');
    await expect(handlers[JOBS.assetVerify]({ assetId: randomUUID() })).resolves.toBeUndefined(); // unknown asset: nothing to do
    await expect(handlers[JOBS.derivativeFallback]({ memoryId: randomUUID() })).resolves.toBeUndefined();
    await expect(handlers[JOBS.sweep]({})).resolves.toBeUndefined();
  });

  it('presigned download URLs carry a safe filename', async () => {
    const memoryId = await register(alice);
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(10, 10, { r: 99, g: 1, b: 1 }) });
    const signed = await presignGet(stack.storage, (await keyOf(assetId))!, { filename: 'My "Photo" ../x.jpg', contentType: 'image/jpeg' });
    const response = await fetch(signed.url);
    expect(response.headers.get('content-disposition')).toBe('attachment; filename="My__Photo__.._x.jpg"');
    expect(new Date(signed.expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  it('verification marks the asset failed when its object has vanished', async () => {
    const memoryId = await register(alice);
    const data = await jpegBuffer(12, 12, { r: 3, g: 3, b: 3 });
    const assetId = randomUUID();
    await stack.database.pool.query(
      "insert into assets (id, memory_id, owner_id, role, status, mime, bytes, sha256) values ($1, $2, $3, 'photo_original', 'uploaded', 'image/jpeg', $4, decode($5, 'hex'))",
      [assetId, memoryId, alice.id, data.length, 'a'.repeat(64)],
    );
    const { verifyAsset } = await import('../src/modules/assets/verify.ts');
    expect(await verifyAsset(stack.services, assetId)).toBe('missing_object');
    expect((await stack.database.pool.query('select status, failure_reason from assets where id = $1', [assetId])).rows[0]).toEqual({ status: 'failed', failure_reason: 'object_missing' });
    expect(await verifyAsset(stack.services, assetId)).toBe('skipped');
  });
});
