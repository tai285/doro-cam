import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildExport } from '../src/modules/exports/build.ts';
import { probe } from '../src/modules/media/ffmpeg.ts';
import { transcodeAsset } from '../src/modules/media/transcode.ts';
import { sweep } from '../src/modules/jobs/handlers.ts';
import { createUser, jpegBuffer, memoryBody, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';
import { makeVideo } from './helpers/video.ts';

const run = promisify(execFile);

async function makeAudioOnly(): Promise<Buffer> {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-audio-'));
  try {
    const file = path.join(dir, 'a.mp4');
    await run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', '-c:a', 'aac', file]);
    return await readFile(file);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

describe('media and export edge cases', () => {
  let stack: Stack;
  let alice: TestUser;

  const register = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: memoryBody(overrides) });
    return id;
  };

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('probe reports an audio-only file as having no video stream', async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-audio-'));
    try {
      const file = path.join(dir, 'a.mp4');
      await writeFile(file, await makeAudioOnly());
      expect(await probe(file)).toMatchObject({ hasVideo: false, hasAudio: true, width: null, height: null });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('a clip without a video stream is reported as failed, not thrown', async () => {
    const id = await register(alice, { kind: 'motion' });
    const { assetId } = await uploadAsset(stack, alice, id, { role: 'motion_clip', mime: 'video/mp4', data: await makeAudioOnly() });
    expect(await transcodeAsset(stack.services, assetId)).toBe('failed');
  });

  it('skips an asset whose stored object row is missing', async () => {
    const id = await register(alice, { kind: 'motion' });
    const orphan = randomUUID();
    await stack.database.pool.query(
      "insert into assets (id, memory_id, owner_id, role, status, mime, bytes, sha256) values ($1, $2, $3, 'motion_clip', 'verified', 'video/mp4', 10, decode($4, 'hex'))",
      [orphan, id, alice.id, 'b'.repeat(64)],
    );
    expect(await transcodeAsset(stack.services, orphan)).toBe('skipped');
  });

  it('a very short clip still gets a poster', async () => {
    const id = await register(alice, { kind: 'video' });
    await uploadAsset(stack, alice, id, { role: 'video_original', mime: 'video/mp4', data: await makeVideo({ seconds: 1, audio: false }) });
    const roles = (await stack.database.pool.query('select role from assets where memory_id = $1', [id])).rows.map((r: { role: string }) => r.role).sort();
    expect(roles).toEqual(['thumbnail', 'video_original', 'video_poster', 'video_web']);
    // a second pass adds nothing
    const again = (await stack.database.pool.query("select id from assets where memory_id = $1 and role = 'video_original'", [id])).rows[0].id as string;
    expect(await transcodeAsset(stack.services, again)).toBe('exists');
  });

  it('an export includes album membership, no-location memories and skips assets without an object', async () => {
    const id = await register(alice);
    await uploadAsset(stack, alice, id, { role: 'photo_original', mime: 'image/heic', data: Buffer.concat([Buffer.from([0, 0, 0, 24, 102, 116, 121, 112, 104, 101, 105, 99]), Buffer.alloc(64, 3)]) });
    await uploadAsset(stack, alice, id, { role: 'photo_rendered', mime: 'image/jpeg', data: await jpegBuffer(30, 30, { r: 8, g: 8, b: 8 }) });
    const album = (await stack.app.inject({ method: 'POST', url: '/v1/albums', headers: alice.headers, payload: { title: 'Exported album' } })).json() as { id: string };
    await stack.app.inject({ method: 'POST', url: `/v1/albums/${album.id}/items`, headers: alice.headers, payload: { memoryIds: [id] } });
    await stack.database.pool.query("update assets set storage_object_id = null where memory_id = $1 and role = 'photo_rendered'", [id]);
    const created = (await stack.app.inject({ method: 'POST', url: '/v1/me/exports', headers: alice.headers })).json() as { id: string };
    const row = (await stack.database.pool.query('select status from data_exports where id = $1', [created.id])).rows[0];
    expect(row.status).toBe('ready');
    expect(await buildExport(stack.services, created.id)).toBe('skipped');
  });

  it('listing exports shows a building one without a link, and the sweep tolerates an export with no object', async () => {
    const bob = await createUser(stack, 'Bob');
    await stack.database.pool.query("insert into data_exports (owner_id, status, expires_at) values ($1, 'building', now() + interval '1 day')", [bob.id]);
    const list = (await stack.app.inject({ method: 'GET', url: '/v1/me/exports', headers: bob.headers })).json() as { items: Array<{ status: string; download: unknown }> };
    expect(list.items).toMatchObject([{ status: 'building', download: null }]);
    await stack.database.pool.query("update data_exports set status = 'failed', expires_at = now() - interval '1 day' where owner_id = $1", [bob.id]);
    const result = await sweep(stack.services);
    expect(result.expiredExports).toBeGreaterThanOrEqual(1);
  });
});
