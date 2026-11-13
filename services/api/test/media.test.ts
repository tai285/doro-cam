import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { MediaError, extractPoster, probe, stripMetadata, transcodeToWebMp4 } from '../src/modules/media/ffmpeg.ts';
import { transcodeAsset } from '../src/modules/media/transcode.ts';
import { createUser, jpegBuffer, memoryBody, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';
import { makeVideo, probeBuffer } from './helpers/video.ts';

const GPS = '+03.1390+101.6869/';

interface MemoryJson {
  assets: Array<{ id: string; role: string; status: string; mime: string; durationMs: number | null }>;
  thumbnail: { url: string } | null;
  display: { url: string } | null;
}

describe('ffmpeg helpers', () => {
  it('[MOT-006] probe reads duration, size and streams of a real clip', async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-ff-'));
    try {
      const file = path.join(dir, 'a.mov');
      await writeFile(file, await makeVideo({ container: 'mov' }));
      const info = await probe(file);
      expect(info).toMatchObject({ width: 320, height: 240, hasAudio: true, hasVideo: true });
      expect(info.durationMs).toBeGreaterThan(1500);
      expect(info.durationMs).toBeLessThan(2600);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('[MOT-006] transcodes to H.264 + AAC fast-start MP4, with and without audio, and drops metadata', async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-ff-'));
    try {
      for (const audio of [true, false]) {
        const input = path.join(dir, `in-${String(audio)}.mov`);
        const output = path.join(dir, `out-${String(audio)}.mp4`);
        await writeFile(input, await makeVideo({ audio, container: 'mov', location: GPS }));
        await transcodeToWebMp4(input, output);
        const result = await probeBuffer(await readFile(output));
        expect(result.streams.find((s) => s.codec_type === 'video')?.codec_name).toBe('h264');
        expect(result.streams.some((s) => s.codec_type === 'audio')).toBe(audio);
        expect(JSON.stringify(result.format.tags ?? {})).not.toContain('3.139');
        // fast-start: the moov atom comes before mdat
        const bytes = await readFile(output);
        expect(bytes.indexOf('moov')).toBeLessThan(bytes.indexOf('mdat'));
      }
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('[VID-006] extracts a JPEG poster no larger than the requested long edge', async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-ff-'));
    try {
      const input = path.join(dir, 'a.mp4');
      await writeFile(input, await makeVideo());
      const out = path.join(dir, 'p.jpg');
      await extractPoster(input, out, 0.5, 160);
      const { default: sharp } = await import('sharp');
      const meta = await sharp(out).metadata();
      expect(meta.format).toBe('jpeg');
      expect(meta.width).toBe(160);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('[PRIV-002] stripMetadata removes location tags without re-encoding', async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-ff-'));
    try {
      const input = path.join(dir, 'a.mp4');
      const original = await makeVideo({ location: GPS });
      expect(JSON.stringify((await probeBuffer(original)).format.tags)).toContain('3.139');
      await writeFile(input, original);
      const out = path.join(dir, 'b.mp4');
      await stripMetadata(input, out);
      const cleaned = await probeBuffer(await readFile(out));
      expect(JSON.stringify(cleaned.format.tags ?? {})).not.toContain('3.139');
      expect(cleaned.streams.find((s) => s.codec_type === 'video')?.codec_name).toBe('h264'); // copied, not re-encoded
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('wraps tool failures in MediaError', async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-ff-'));
    try {
      const junk = path.join(dir, 'junk');
      await writeFile(junk, 'not a video');
      await expect(probe(junk)).rejects.toBeInstanceOf(MediaError);
      await expect(transcodeToWebMp4(junk, path.join(dir, 'o.mp4'))).rejects.toBeInstanceOf(MediaError);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe('media jobs', () => {
  let stack: Stack;
  let alice: TestUser;

  const register = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    expect((await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: memoryBody(overrides) })).statusCode).toBe(201);
    return id;
  };
  const detail = async (user: TestUser, id: string) =>
    (await stack.app.inject({ method: 'GET', url: `/v1/memories/${id}`, headers: user.headers })).json() as MemoryJson;

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[MOT-006] a verified motion clip gets a browser-playable motion_web rendition and a poster thumbnail', async () => {
    const memoryId = await register(alice, { kind: 'motion' });
    const clip = await makeVideo({ container: 'mov', location: GPS });
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'motion_clip', mime: 'video/quicktime', data: clip });
    const memory = await detail(alice, memoryId);
    const web = memory.assets.find((a) => a.role === 'motion_web');
    expect(web).toMatchObject({ status: 'ready', mime: 'video/mp4' });
    expect(web?.durationMs).toBeGreaterThan(1500);
    expect(memory.assets.some((a) => a.role === 'thumbnail')).toBe(true);
    expect(memory.thumbnail).not.toBeNull();
    const download = (await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${web!.id}/download`, headers: alice.headers })).json() as { url: string };
    const bytes = Buffer.from(await (await fetch(download.url)).arrayBuffer());
    const result = await probeBuffer(bytes);
    expect(result.streams.find((s) => s.codec_type === 'video')?.codec_name).toBe('h264');
    expect(result.streams.some((s) => s.codec_type === 'audio')).toBe(true);
    // original untouched
    expect(memory.assets.find((a) => a.id === assetId)?.status).toBe('verified');
  });

  it('[MOT-006] transcoding is idempotent', async () => {
    const memoryId = await register(alice, { kind: 'motion' });
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'motion_clip', mime: 'video/mp4', data: await makeVideo({ audio: false }) });
    const before = (await detail(alice, memoryId)).assets.length;
    expect(await transcodeAsset(stack.services, assetId)).toBe('exists');
    expect((await detail(alice, memoryId)).assets).toHaveLength(before);
  });

  it('[VID-005][VID-006] a video gets a web rendition, a poster and a thumbnail, and the poster is its display image', async () => {
    const memoryId = await register(alice, { kind: 'video' });
    await uploadAsset(stack, alice, memoryId, { role: 'video_original', mime: 'video/mp4', data: await makeVideo({ seconds: 3 }) });
    const memory = await detail(alice, memoryId);
    expect(memory.assets.map((a) => a.role).sort()).toEqual(['thumbnail', 'video_original', 'video_poster', 'video_web']);
    expect(memory.display).not.toBeNull();
    expect(memory.thumbnail).not.toBeNull();
    const poster = Buffer.from(await (await fetch(memory.display!.url)).arrayBuffer());
    const { default: sharp } = await import('sharp');
    expect((await sharp(poster).metadata()).format).toBe('jpeg');
  });

  it('a corrupt clip is recorded as failed and never throws, so the upload still completes', async () => {
    const memoryId = await register(alice, { kind: 'motion' });
    const { assetId, status } = await uploadAsset(stack, alice, memoryId, { role: 'motion_clip', mime: 'video/mp4', data: Buffer.from('definitely not a video, just bytes'.repeat(20)) });
    expect(status).toBe('verified');
    expect(await transcodeAsset(stack.services, assetId)).toBe('failed');
    expect((await detail(alice, memoryId)).assets.map((a) => a.role)).toEqual(['motion_clip']);
  });

  it('skips unknown assets, non-video roles and assets that are not verified yet', async () => {
    expect(await transcodeAsset(stack.services, randomUUID())).toBe('skipped');
    const memoryId = await register(alice);
    const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'thumbnail', mime: 'image/jpeg', data: await jpegBuffer(10, 10) });
    expect(await transcodeAsset(stack.services, assetId)).toBe('skipped');
    const motionId = await register(alice, { kind: 'motion' });
    const pending = randomUUID();
    await stack.database.pool.query(
      "insert into assets (id, memory_id, owner_id, role, status, mime, bytes, sha256) values ($1, $2, $3, 'motion_clip', 'uploading', 'video/mp4', 10, decode($4, 'hex'))",
      [pending, motionId, alice.id, 'a'.repeat(64)],
    );
    expect(await transcodeAsset(stack.services, pending)).toBe('skipped');
  });

  describe('sharing videos without location', () => {
    let bob: TestUser;
    beforeAll(async () => {
      bob = await createUser(stack, 'Bob');
    });

    const share = async (shareLocation: boolean) => {
      const album = (await stack.app.inject({ method: 'POST', url: '/v1/albums', headers: alice.headers, payload: { title: 'Clips', shareLocation } })).json() as { id: string };
      const token = ((await stack.app.inject({ method: 'POST', url: `/v1/albums/${album.id}/invites`, headers: alice.headers, payload: { role: 'viewer' } })).json() as { token: string }).token;
      await stack.app.inject({ method: 'POST', url: '/v1/invites/accept', headers: bob.headers, payload: { token } });
      const memoryId = await register(alice, { kind: 'motion', location: { lat: 3.139, lon: 101.6869 } });
      const { assetId } = await uploadAsset(stack, alice, memoryId, { role: 'motion_clip', mime: 'video/mp4', data: await makeVideo({ location: GPS }) });
      await stack.app.inject({ method: 'POST', url: `/v1/albums/${album.id}/items`, headers: alice.headers, payload: { memoryIds: [memoryId] } });
      return { memoryId, assetId };
    };

    it('[PRIV-002] a member without location access receives a clip with the location tags removed', async () => {
      const { memoryId, assetId } = await share(false);
      const link = (await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${assetId}/download`, headers: bob.headers })).json() as { url: string; sanitized: boolean };
      expect(link.sanitized).toBe(true);
      const content = await stack.app.inject({ method: 'GET', url: link.url, headers: bob.headers });
      expect(content.statusCode).toBe(200);
      expect(content.headers['content-type']).toBe('video/mp4');
      const tags = JSON.stringify((await probeBuffer(content.rawPayload)).format.tags ?? {});
      expect(tags).not.toContain('3.139');
      expect(tags).not.toContain('101.68');
    });

    it('[PRIV-002] the owner still gets the untouched file with its tags', async () => {
      const { memoryId, assetId } = await share(false);
      const link = (await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${assetId}/download`, headers: alice.headers })).json() as { url: string; sanitized: boolean };
      expect(link.sanitized).toBe(false);
      const bytes = Buffer.from(await (await fetch(link.url)).arrayBuffer());
      expect(JSON.stringify((await probeBuffer(bytes)).format.tags)).toContain('3.139');
    });

    it('[PRIV-002] an unreadable file is refused instead of leaked', async () => {
      const { memoryId, assetId } = await share(false);
      await stack.database.pool.query("update assets set mime = 'video/mp4' where id = $1", [assetId]);
      const key = (await stack.database.pool.query('select o.key from assets a join storage_objects o on o.id = a.storage_object_id where a.id = $1', [assetId])).rows[0].key as string;
      const { PutObjectCommand } = await import('@aws-sdk/client-s3');
      await stack.storage.client.send(new PutObjectCommand({ Bucket: stack.storage.bucket, Key: key, Body: Buffer.from('garbage') }));
      const content = await stack.app.inject({ method: 'GET', url: `/v1/memories/${memoryId}/assets/${assetId}/content`, headers: bob.headers });
      expect(content.statusCode).toBe(409);
      expect((content.json() as { error: { code: string } }).error.code).toBe('asset.not_sanitizable');
    });
  });
});
