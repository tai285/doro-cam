import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { DeleteObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildExport, exportKey } from '../src/modules/exports/build.ts';
import { deleteUser, sweep } from '../src/modules/jobs/handlers.ts';
import { createUser, jpegBuffer, memoryBody, sha256, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';
import { makeVideo } from './helpers/video.ts';

const run = promisify(execFile);

interface ExportJson {
  id: string;
  status: string;
  bytes: number | null;
  failureReason: string | null;
  download: { url: string; filename: string } | null;
}

describe('data export', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const api = (user: TestUser, method: 'GET' | 'POST', url: string) => stack.app.inject({ method, url, headers: user.headers });
  const register = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: memoryBody(overrides) });
    return id;
  };
  const exists = (key: string) => stack.storage.client.send(new HeadObjectCommand({ Bucket: stack.storage.bucket, Key: key })).then(() => true, () => false);

  /** Downloads the archive and lists/reads it with the system unzip. */
  const openZip = async (url: string) => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-zip-'));
    const file = path.join(dir, 'a.zip');
    await writeFile(file, Buffer.from(await (await fetch(url)).arrayBuffer()));
    const list = (await run('unzip', ['-Z1', file])).stdout.split('\n').filter((line) => line !== '');
    const read = async (name: string) => (await run('unzip', ['-p', file, name], { encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 })).stdout;
    return { list, read, cleanup: () => rm(dir, { recursive: true, force: true }) };
  };

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[WEB-010][PRIV-006] builds an archive of originals and metadata, and the files are bit-exact', async () => {
    const photoId = await register(alice, { caption: 'Pier', location: { lat: 3.139, lon: 101.6869 } });
    const photo = await jpegBuffer(90, 60, { r: 10, g: 20, b: 30 });
    await uploadAsset(stack, alice, photoId, { role: 'photo_original', mime: 'image/jpeg', data: photo });
    await uploadAsset(stack, alice, photoId, { role: 'thumbnail', mime: 'image/jpeg', data: await jpegBuffer(20, 20) });
    const motionId = await register(alice, { kind: 'motion', capturedAt: '2026-11-02T09:30:00.000Z' });
    const clip = await makeVideo({ audio: false });
    await uploadAsset(stack, alice, motionId, { role: 'motion_clip', mime: 'video/mp4', data: clip });
    const trashed = await register(alice);
    await uploadAsset(stack, alice, trashed, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(30, 30, { r: 1, g: 1, b: 1 }) });
    await api(alice, 'POST', `/v1/memories/${trashed}/trash`);
    await stack.app.inject({ method: 'PUT', url: `/v1/presets/${randomUUID()}`, headers: alice.headers, payload: { name: 'Street', experienceId: 'mirrorless', intent: { scenario: 'street' } } });

    const created = await api(alice, 'POST', '/v1/me/exports');
    expect(created.statusCode).toBe(202);
    const done = (await api(alice, 'GET', `/v1/me/exports/${(created.json() as ExportJson).id}`)).json() as ExportJson;
    expect(done.status).toBe('ready');
    expect(done.download?.filename).toMatch(/^doro-cam-export-\d{4}-\d{2}-\d{2}\.zip$/);

    const zip = await openZip(done.download!.url);
    try {
      expect(zip.list).toContain('metadata.json');
      const files = zip.list.filter((name) => name !== 'metadata.json');
      expect(files.some((name) => name.endsWith('/photo_original.jpg'))).toBe(true);
      expect(files.some((name) => name.endsWith('/motion_clip.mp4'))).toBe(true);
      expect(files.some((name) => name.includes('thumbnail') || name.includes('motion_web'))).toBe(false); // derived renditions are not archived
      expect(files).toHaveLength(2); // the trashed Memory is not included

      const metadata = JSON.parse((await zip.read('metadata.json')).toString()) as {
        account: { email: string };
        memories: Array<{ id: string; caption: string | null; location: unknown; files: Array<{ file: string; sha256: string; bytes: number }> }>;
        presets: Array<{ name: string }>;
      };
      expect(metadata.account.email).toBe(alice.email);
      expect(metadata.memories.map((m) => m.id).sort()).toEqual([photoId, motionId].sort());
      const photoEntry = metadata.memories.find((m) => m.id === photoId)!;
      expect(photoEntry).toMatchObject({ caption: 'Pier', location: { lat: 3.139, lon: 101.6869 } });
      expect(metadata.presets.map((p) => p.name)).toEqual(['Street']);
      const photoFile = photoEntry.files[0]!;
      expect(photoFile.sha256).toBe(sha256(photo));
      expect(sha256(await zip.read(photoFile.file))).toBe(sha256(photo));
      const clipFile = metadata.memories.find((m) => m.id === motionId)!.files[0]!;
      expect(sha256(await zip.read(clipFile.file))).toBe(sha256(clip));
    } finally {
      await zip.cleanup();
    }
    expect(done.bytes).toBeGreaterThan(photo.length + clip.length);
  });

  it('[WEB-010] an account with no memories still gets a valid archive', async () => {
    const empty = await createUser(stack, 'Empty');
    const created = (await api(empty, 'POST', '/v1/me/exports')).json() as ExportJson;
    const done = (await api(empty, 'GET', `/v1/me/exports/${created.id}`)).json() as ExportJson;
    expect(done.status).toBe('ready');
    const zip = await openZip(done.download!.url);
    try {
      expect(zip.list).toEqual(['metadata.json']);
      expect((JSON.parse((await zip.read('metadata.json')).toString()) as { memories: unknown[] }).memories).toEqual([]);
    } finally {
      await zip.cleanup();
    }
  });

  it('only one export can be in progress at a time (409 export.in_progress)', async () => {
    const carol = await createUser(stack, 'Carol');
    stack.queue.autoRun = false;
    try {
      const first = await api(carol, 'POST', '/v1/me/exports');
      expect(first.statusCode).toBe(202);
      expect((first.json() as ExportJson).status).toBe('pending');
      expect((first.json() as ExportJson).download).toBeNull();
      const second = await api(carol, 'POST', '/v1/me/exports');
      expect(second.statusCode).toBe(409);
      expect((second.json() as { error: { code: string } }).error.code).toBe('export.in_progress');
    } finally {
      stack.queue.autoRun = true;
    }
    const pending = stack.queue.enqueued.filter((job) => job.name === 'export.build').at(-1)!;
    await stack.queue.run('export.build', pending.payload);
    const list = (await api(carol, 'GET', '/v1/me/exports')).json() as { items: ExportJson[] };
    expect(list.items.map((item) => item.status)).toEqual(['ready']);
    expect((await api(carol, 'POST', '/v1/me/exports')).statusCode).toBe(202); // allowed again once finished
  });

  it('[PRIV-003] exports are private: other users get 404, anonymous callers 401', async () => {
    const created = (await api(alice, 'POST', '/v1/me/exports')).json() as ExportJson;
    expect((await api(bob, 'GET', `/v1/me/exports/${created.id}`)).statusCode).toBe(404);
    expect(((await api(bob, 'GET', '/v1/me/exports')).json() as { items: unknown[] }).items).toEqual([]);
    expect((await stack.app.inject({ method: 'GET', url: `/v1/me/exports/${created.id}` })).statusCode).toBe(401);
    expect((await stack.app.inject({ method: 'POST', url: '/v1/me/exports' })).statusCode).toBe(401);
    expect((await api(alice, 'GET', `/v1/me/exports/${randomUUID()}`)).statusCode).toBe(404);
    expect((await api(alice, 'GET', '/v1/me/exports/nope')).statusCode).toBe(400);
  });

  it('records a failure with a reason when a file cannot be read, and building twice does nothing', async () => {
    const dana = await createUser(stack, 'Dana');
    const memoryId = await register(dana);
    const { assetId } = await uploadAsset(stack, dana, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(44, 44, { r: 5, g: 5, b: 5 }) });
    const key = (await stack.database.pool.query('select o.key from assets a join storage_objects o on o.id = a.storage_object_id where a.id = $1', [assetId])).rows[0].key as string;
    await stack.storage.client.send(new DeleteObjectCommand({ Bucket: stack.storage.bucket, Key: key }));
    const created = (await api(dana, 'POST', '/v1/me/exports')).json() as ExportJson;
    const failed = (await api(dana, 'GET', `/v1/me/exports/${created.id}`)).json() as ExportJson;
    expect(failed.status).toBe('failed');
    expect(failed.failureReason).toBeTruthy();
    expect(failed.download).toBeNull();
    expect(await buildExport(stack.services, created.id)).toBe('skipped');
    expect(await buildExport(stack.services, randomUUID())).toBe('skipped');
  });

  it('the sweep removes expired exports and their archive objects', async () => {
    const erin = await createUser(stack, 'Erin');
    const created = (await api(erin, 'POST', '/v1/me/exports')).json() as ExportJson;
    const key = exportKey(erin.id, created.id);
    expect(await exists(key)).toBe(true);
    await stack.database.pool.query("update data_exports set expires_at = now() - interval '1 minute' where id = $1", [created.id]);
    const afterExpiry = (await api(erin, 'GET', `/v1/me/exports/${created.id}`)).json() as ExportJson;
    expect(afterExpiry.download).toBeNull(); // no link once expired, even before the sweep
    const result = await sweep(stack.services);
    expect(result.expiredExports).toBeGreaterThanOrEqual(1);
    expect(await exists(key)).toBe(false);
    expect((await api(erin, 'GET', `/v1/me/exports/${created.id}`)).statusCode).toBe(404);
  });

  it('[PRIV-004] deleting an account also removes its export archives', async () => {
    const fred = await createUser(stack, 'Fred');
    const created = (await api(fred, 'POST', '/v1/me/exports')).json() as ExportJson;
    const key = exportKey(fred.id, created.id);
    expect(await exists(key)).toBe(true);
    await deleteUser(stack.services, fred.id);
    expect(await exists(key)).toBe(false);
  });

  it('the downloaded archive is a valid zip that unzip -t accepts', async () => {
    const gina = await createUser(stack, 'Gina');
    const memoryId = await register(gina);
    await uploadAsset(stack, gina, memoryId, { role: 'photo_original', mime: 'image/jpeg', data: await jpegBuffer(60, 60, { r: 90, g: 90, b: 9 }) });
    const done = (await api(gina, 'GET', `/v1/me/exports/${((await api(gina, 'POST', '/v1/me/exports')).json() as ExportJson).id}`)).json() as ExportJson;
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-zip-'));
    try {
      const file = path.join(dir, 'a.zip');
      await writeFile(file, Buffer.from(await (await fetch(done.download!.url)).arrayBuffer()));
      const { stdout } = await run('unzip', ['-t', file]);
      expect(stdout).toContain('No errors detected');
      expect((await readFile(file)).subarray(0, 2).toString()).toBe('PK');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
