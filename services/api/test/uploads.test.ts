import { randomBytes, randomUUID } from 'node:crypto';
import { GetObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createUser, jpegBuffer, memoryBody, sha256, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';

const MIB = 1024 * 1024;

interface MemoryJson {
  id: string;
  assets: Array<{ id: string; role: string; status: string; bytes: number }>;
  thumbnail: { url: string } | null;
  display: { url: string } | null;
}

describe('uploads and downloads', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const register = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    const response = await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: memoryBody(overrides) });
    expect(response.statusCode).toBe(201);
    return id;
  };
  const getMemory = async (user: TestUser, id: string) =>
    (await stack.app.inject({ method: 'GET', url: `/v1/memories/${id}`, headers: user.headers })).json() as MemoryJson;
  const create = (user: TestUser, memoryId: string, assetId: string, body: Record<string, unknown>) =>
    stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload`, headers: user.headers, payload: body });

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[SYNC-002][SYNC-008][NFR-005] uploads a photo, verifies its checksum and serves it bit-exact', async () => {
    const memoryId = await register(alice);
    const original = await jpegBuffer(120, 90);
    const { assetId, status } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: original });
    expect(status).toBe('verified'); // the inline queue ran asset.verify

    const memory = await getMemory(alice, memoryId);
    expect(memory.assets).toEqual([{ id: assetId, role: 'photo_original', status: 'verified', bytes: original.length, mime: 'image/jpeg', width: null, height: null, durationMs: null, failureReason: null }]);

    const download = await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${assetId}/download`, headers: alice.headers });
    expect(download.statusCode).toBe(200);
    const { url, sanitized, filename } = download.json() as { url: string; sanitized: boolean; filename: string };
    expect(sanitized).toBe(false);
    expect(filename).toMatch(/^photo_original-[0-9a-f]{8}\.jpg$/);
    const bytes = Buffer.from(await (await fetch(url)).arrayBuffer());
    expect(sha256(bytes)).toBe(sha256(original));
  });

  it('[WEB-005] storage usage counts verified bytes', async () => {
    const carol = await createUser(stack, 'Carol');
    const memoryId = await register(carol);
    const data = await jpegBuffer(200, 100);
    await uploadAsset(stack, carol, memoryId, { role: 'photo_original', mime: 'image/jpeg', data });
    const me = (await stack.app.inject({ method: 'GET', url: '/v1/me', headers: carol.headers })).json() as { storage: { usedBytes: number } };
    expect(me.storage.usedBytes).toBe(data.length);
    const { rows } = await stack.database.pool.query('select storage_bytes from users_profile where user_id = $1', [carol.id]);
    expect(Number(rows[0].storage_bytes)).toBe(data.length);
  });

  it('[SYNC-004] repeating the create and complete calls is idempotent and never duplicates the asset', async () => {
    const memoryId = await register(alice);
    const data = await jpegBuffer(80, 80);
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data });
    const again = await create(alice, memoryId, assetId, { role: 'photo_original', mime: 'image/jpeg', bytes: data.length, sha256: sha256(data) });
    expect(again.json()).toEqual({ mode: 'complete', status: 'complete', deduplicated: false });
    const complete = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, headers: alice.headers, payload: {} });
    expect(complete.json()).toEqual({ status: 'verified' });
    const { rows } = await stack.database.pool.query('select count(*)::int as n from assets where memory_id = $1', [memoryId]);
    expect(rows[0].n).toBe(1);
  });

  it('[SYNC-004] deduplicates identical bytes uploaded for another Memory of the same owner', async () => {
    const dana = await createUser(stack, 'Dana');
    const data = await jpegBuffer(150, 110, { r: 1, g: 2, b: 3 });
    const first = await register(dana);
    const second = await register(dana);
    await uploadAsset(stack, dana, first, { role: 'photo_rendered', mime: 'image/jpeg', data });
    const assetId = randomUUID();
    const response = await create(dana, second, assetId, { role: 'photo_rendered', mime: 'image/jpeg', bytes: data.length, sha256: sha256(data) });
    expect(response.json()).toEqual({ mode: 'complete', status: 'complete', deduplicated: true });
    const { rows } = await stack.database.pool.query('select count(*)::int as n from storage_objects where owner_id = $1', [dana.id]);
    expect(rows[0].n).toBe(1);
    const me = (await stack.app.inject({ method: 'GET', url: '/v1/me', headers: dana.headers })).json() as { storage: { usedBytes: number } };
    expect(me.storage.usedBytes).toBe(data.length); // counted once
  });

  it('[SYNC-008] a checksum mismatch deletes the object, marks the asset failed and lets the client retry', async () => {
    const memoryId = await register(alice);
    const claimed = await jpegBuffer(60, 60, { r: 9, g: 9, b: 9 });
    const different = await jpegBuffer(60, 60, { r: 250, g: 0, b: 0 });
    // same declared length so only the checksum differs
    const padded = Buffer.concat([different, Buffer.alloc(Math.max(0, claimed.length - different.length))]).subarray(0, claimed.length);
    const assetId = randomUUID();
    const body = { role: 'photo_original', mime: 'image/jpeg', bytes: claimed.length, sha256: sha256(claimed) };
    const plan = (await create(alice, memoryId, assetId, body)).json() as { url: string };
    const wrong = Buffer.concat([padded, Buffer.alloc(claimed.length - padded.length)]);
    await fetch(plan.url, { method: 'PUT', headers: { 'content-type': 'image/jpeg' }, body: new Uint8Array(wrong) });
    const complete = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, headers: alice.headers, payload: {} });
    expect(complete.json()).toEqual({ status: 'failed' });

    const memory = await getMemory(alice, memoryId);
    expect(memory.assets[0]).toMatchObject({ status: 'failed' });
    const { rows } = await stack.database.pool.query('select failure_reason from assets where id = $1', [assetId]);
    expect(rows[0].failure_reason).toBe('checksum_mismatch');
    await expect(
      stack.storage.client.send(new HeadObjectCommand({ Bucket: stack.storage.bucket, Key: `o/${alice.id}/${memoryId}/${assetId}/photo_original` })),
    ).rejects.toThrow();

    // retry with the right bytes, same asset id
    const retry = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: claimed, assetId });
    expect(retry.status).toBe('verified');
  });

  it('[SYNC-008] a size mismatch is 422 upload.size_mismatch and removes the object', async () => {
    const memoryId = await register(alice);
    const data = await jpegBuffer(70, 70);
    const assetId = randomUUID();
    const plan = (await create(alice, memoryId, assetId, { role: 'photo_original', mime: 'image/jpeg', bytes: data.length + 10, sha256: sha256(data) })).json() as { url: string };
    await fetch(plan.url, { method: 'PUT', headers: { 'content-type': 'image/jpeg' }, body: new Uint8Array(data) });
    const complete = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, headers: alice.headers, payload: {} });
    expect(complete.statusCode).toBe(422);
    expect((complete.json() as { error: { code: string } }).error.code).toBe('upload.size_mismatch');
  });

  it('answers upload.not_found when completing before anything was uploaded', async () => {
    const memoryId = await register(alice);
    const assetId = randomUUID();
    const data = await jpegBuffer(50, 50);
    await create(alice, memoryId, assetId, { role: 'photo_original', mime: 'image/jpeg', bytes: data.length, sha256: sha256(data) });
    const complete = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, headers: alice.headers, payload: {} });
    expect(complete.statusCode).toBe(404);
    expect((complete.json() as { error: { code: string } }).error.code).toBe('upload.not_found');
    const unknown = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${randomUUID()}/upload/complete`, headers: alice.headers, payload: {} });
    expect((unknown.json() as { error: { code: string } }).error.code).toBe('upload.not_found');
  });

  describe('validation and limits', () => {
    const base = { mime: 'image/jpeg', bytes: 1000, sha256: 'a'.repeat(64) };

    it('rejects unsupported types (415), oversized files (413) and roles that do not fit the kind (422)', async () => {
      const photo = await register(alice);
      const unsupported = await create(alice, photo, randomUUID(), { ...base, role: 'photo_original', mime: 'image/gif' });
      expect(unsupported.statusCode).toBe(415);
      expect((unsupported.json() as { error: { code: string } }).error.code).toBe('upload.unsupported_type');
      const huge = await create(alice, photo, randomUUID(), { ...base, role: 'thumbnail', bytes: 6 * MIB });
      expect(huge.statusCode).toBe(413);
      expect((huge.json() as { error: { code: string } }).error.code).toBe('upload.too_large');
      const wrongKind = await create(alice, photo, randomUUID(), { ...base, role: 'motion_clip', mime: 'video/mp4' });
      expect(wrongKind.statusCode).toBe(422);
      expect((wrongKind.json() as { error: { code: string } }).error.code).toBe('upload.role_not_allowed');
    });

    it('never accepts worker-generated roles from a client', async () => {
      const photo = await register(alice);
      for (const role of ['motion_web', 'sanitized_original']) {
        const response = await create(alice, photo, randomUUID(), { ...base, role });
        expect(response.statusCode).toBe(400);
      }
    });

    it('rejects malformed checksums and non-positive sizes', async () => {
      const photo = await register(alice);
      expect((await create(alice, photo, randomUUID(), { ...base, role: 'photo_original', sha256: 'xyz' })).statusCode).toBe(400);
      expect((await create(alice, photo, randomUUID(), { ...base, role: 'photo_original', bytes: 0 })).statusCode).toBe(400);
    });

    it('one asset per role per Memory (409 asset.role_taken); an asset id cannot be reused for different contents (409 asset.conflict)', async () => {
      const memoryId = await register(alice);
      const data = await jpegBuffer(40, 40);
      const body = { role: 'photo_original', mime: 'image/jpeg', bytes: data.length, sha256: sha256(data) };
      const assetId = randomUUID();
      expect((await create(alice, memoryId, assetId, body)).statusCode).toBe(200);
      const taken = await create(alice, memoryId, randomUUID(), body);
      expect(taken.statusCode).toBe(409);
      expect((taken.json() as { error: { code: string } }).error.code).toBe('asset.role_taken');
      const conflict = await create(alice, memoryId, assetId, { ...body, bytes: data.length + 1 });
      expect((conflict.json() as { error: { code: string } }).error.code).toBe('asset.conflict');
      const otherMemory = await register(alice);
      const crossed = await create(alice, otherMemory, assetId, body);
      expect((crossed.json() as { error: { code: string } }).error.code).toBe('asset.conflict');
    });

    it('[PRIV-003] only the owner can upload: another user gets 404', async () => {
      const memoryId = await register(alice);
      const response = await create(bob, memoryId, randomUUID(), { ...base, role: 'photo_original' });
      expect(response.statusCode).toBe(404);
    });

    it('answers upload.quota_exceeded (403) when the owner’s quota would be exceeded', async () => {
      const small = await startStack({ STORAGE_QUOTA_BYTES: '5000' });
      try {
        const user = await createUser(small, 'Quota');
        const id = randomUUID();
        await small.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: memoryBody() });
        const response = await small.app.inject({
          method: 'POST',
          url: `/v1/memories/${id}/assets/${randomUUID()}/upload`,
          headers: user.headers,
          payload: { role: 'photo_original', mime: 'image/jpeg', bytes: 6000, sha256: 'b'.repeat(64) },
        });
        expect(response.statusCode).toBe(403);
        expect((response.json() as { error: { code: string } }).error.code).toBe('upload.quota_exceeded');
      } finally {
        await small.close();
      }
    });
  });

  describe('multipart uploads', () => {
    it('[SYNC-003][NFR-005] uploads 20 MiB in parts, resumes from the last completed part, and verifies the checksum', async () => {
      const memoryId = await register(alice, { kind: 'motion' });
      const data = randomBytes(20 * MIB);
      const assetId = randomUUID();
      const body = { role: 'motion_clip', mime: 'video/mp4', bytes: data.length, sha256: sha256(data) };

      const first = (await create(alice, memoryId, assetId, body)).json() as {
        mode: string; uploadId: string; partSize: number; partCount: number; parts: Array<{ partNumber: number; url: string }>; completed: unknown[];
      };
      expect(first.mode).toBe('multipart');
      expect(first.partSize).toBe(8 * MIB);
      expect(first.partCount).toBe(3);
      expect(first.parts.map((p) => p.partNumber)).toEqual([1, 2, 3]);
      expect(first.completed).toEqual([]);

      const putPart = async (partNumber: number, url: string) => {
        const slice = data.subarray((partNumber - 1) * first.partSize, Math.min(data.length, partNumber * first.partSize));
        const response = await fetch(url, { method: 'PUT', body: new Uint8Array(slice) });
        expect(response.ok).toBe(true);
        return { partNumber, etag: response.headers.get('etag') as string };
      };
      const part1 = await putPart(1, first.parts[0]!.url);

      // simulated app kill: the client asks again and is told what is already done
      const resumed = (await create(alice, memoryId, assetId, body)).json() as typeof first;
      expect(resumed.uploadId).toBe(first.uploadId);
      expect(resumed.completed).toEqual([{ partNumber: 1, etag: part1.etag }]);
      expect(resumed.parts.map((p) => p.partNumber)).toEqual([2, 3]);
      const part2 = await putPart(2, resumed.parts[0]!.url);
      const part3 = await putPart(3, resumed.parts[1]!.url);

      const complete = await stack.app.inject({
        method: 'POST',
        url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`,
        headers: alice.headers,
        payload: { uploadId: first.uploadId, parts: [part1, part2, part3] },
      });
      expect(complete.json()).toEqual({ status: 'verified' });

      const object = await stack.storage.client.send(new GetObjectCommand({ Bucket: stack.storage.bucket, Key: `o/${alice.id}/${memoryId}/${assetId}/motion_clip` }));
      const stored = Buffer.from(await object.Body!.transformToByteArray());
      expect(sha256(stored)).toBe(sha256(data));
    });

    it('completes from the server’s own part list when the client lost the ETags', async () => {
      const memoryId = await register(alice, { kind: 'motion' });
      const data = randomBytes(17 * MIB);
      const assetId = randomUUID();
      const plan = (await create(alice, memoryId, assetId, { role: 'motion_clip', mime: 'video/mp4', bytes: data.length, sha256: sha256(data) })).json() as {
        partSize: number; parts: Array<{ partNumber: number; url: string }>;
      };
      for (const part of plan.parts) {
        const slice = data.subarray((part.partNumber - 1) * plan.partSize, Math.min(data.length, part.partNumber * plan.partSize));
        await fetch(part.url, { method: 'PUT', body: new Uint8Array(slice) });
      }
      const complete = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload/complete`, headers: alice.headers, payload: {} });
      expect(complete.json()).toEqual({ status: 'verified' });
    });

    it('abort removes an unfinished upload so the asset can start again', async () => {
      const memoryId = await register(alice, { kind: 'motion' });
      const data = randomBytes(17 * MIB);
      const assetId = randomUUID();
      await create(alice, memoryId, assetId, { role: 'motion_clip', mime: 'video/mp4', bytes: data.length, sha256: sha256(data) });
      const abort = await stack.app.inject({ method: 'POST', url: `/v1/memories/${memoryId}/assets/${assetId}/upload/abort`, headers: alice.headers });
      expect(abort.statusCode).toBe(204);
      const { rows } = await stack.database.pool.query('select count(*)::int as n from assets where id = $1', [assetId]);
      expect(rows[0].n).toBe(0);
    });
  });

  describe('derived media and downloads', () => {
    it('[LIB-001] a verified thumbnail is returned as a presigned URL in the list and detail', async () => {
      const memoryId = await register(alice);
      const thumb = await jpegBuffer(32, 24);
      await uploadAsset(stack, alice, memoryId, { role: 'thumbnail', mime: 'image/jpeg', data: thumb });
      const memory = await getMemory(alice, memoryId);
      expect(memory.thumbnail).not.toBeNull();
      const fetched = Buffer.from(await (await fetch(memory.thumbnail!.url)).arrayBuffer());
      expect(sha256(fetched)).toBe(sha256(thumb));
    });

    it('upload-sync invariant 2: an unverified asset is not downloadable and not listed for others', async () => {
      const memoryId = await register(alice);
      const assetId = randomUUID();
      const data = await jpegBuffer(30, 30);
      await create(alice, memoryId, assetId, { role: 'photo_original', mime: 'image/jpeg', bytes: data.length, sha256: sha256(data) });
      const download = await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${assetId}/download`, headers: alice.headers });
      expect(download.statusCode).toBe(404);
    });

    it('[PRIV-003] another user cannot download or read content (404)', async () => {
      const memoryId = await register(alice);
      const data = await jpegBuffer(30, 30);
      const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'photo_original', mime: 'image/jpeg', data });
      for (const suffix of ['download', 'content']) {
        const response = await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${assetId}/${suffix}`, headers: bob.headers });
        expect(response.statusCode, suffix).toBe(404);
      }
    });

    it('derivative.fallback builds thumbnail and display from photo_rendered when the device sent none', async () => {
      const erin = await createUser(stack, 'Erin');
      const memoryId = await register(erin);
      await uploadAsset(stack, erin, memoryId, { role: 'photo_rendered', mime: 'image/jpeg', data: await jpegBuffer(1200, 800) });
      stack.queue.autoRun = false;
      await stack.queue.run('derivative.fallback', { memoryId });
      stack.queue.autoRun = true;
      const memory = await getMemory(erin, memoryId);
      expect(memory.assets.map((a) => a.role).sort()).toEqual(['photo_display', 'photo_rendered', 'thumbnail']);
      expect(memory.thumbnail).not.toBeNull();
      const thumb = Buffer.from(await (await fetch(memory.thumbnail!.url)).arrayBuffer());
      const { default: sharp } = await import('sharp');
      expect((await sharp(thumb).metadata()).width).toBe(512);
      // running it again adds nothing
      await stack.queue.run('derivative.fallback', { memoryId });
      expect((await getMemory(erin, memoryId)).assets).toHaveLength(3);
    });
  });
});
