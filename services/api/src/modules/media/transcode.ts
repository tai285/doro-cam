import { createHash, randomUUID } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { eq, sql } from 'drizzle-orm';
import sharp from 'sharp';
import { assets, memories, storageObjects } from '../../db/schema.ts';
import type { JobServices } from '../context.ts';
import { refreshStorageBytes } from '../assets/verify.ts';
import { assetKey } from '../memories/serialize.ts';
import { nextSeq, recordChange } from '../sync/change-log.ts';
import { extractPoster, MediaError, probe, transcodeToWebMp4 } from './ffmpeg.ts';

type DerivedRole = 'motion_web' | 'video_web' | 'video_poster' | 'thumbnail' | 'photo_display';

export type TranscodeOutcome = 'created' | 'exists' | 'skipped' | 'failed';

async function withTempDir<T>(work: (dir: string) => Promise<T>): Promise<T> {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'doro-media-'));
  try {
    return await work(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

export async function downloadToFile(services: Pick<JobServices, 'storage'>, key: string, file: string): Promise<void> {
  const object = await services.storage.client.send(new GetObjectCommand({ Bucket: services.storage.bucket, Key: key }));
  await pipeline(object.Body as Readable, createWriteStream(file));
}

/** Stores a generated file as a new, already verified asset (worker output is trusted: we made it). */
async function storeDerived(
  services: JobServices,
  source: { ownerId: string; memoryId: string },
  role: DerivedRole,
  file: string,
  mime: string,
  extra: { width?: number | null; height?: number | null; durationMs?: number | null } = {},
): Promise<boolean> {
  const db = services.database.db;
  const body = await readFile(file);
  const digest = createHash('sha256').update(body).digest();
  const assetId = randomUUID();
  const key = assetKey(source.ownerId, source.memoryId, assetId, role);
  await services.storage.client.send(new PutObjectCommand({ Bucket: services.storage.bucket, Key: key, Body: body, ContentType: mime }));
  const seq = await nextSeq(db);
  let stored = false;
  await db.transaction(async (tx) => {
    const object = (
      await tx
        .insert(storageObjects)
        .values({ ownerId: source.ownerId, key, bytes: body.length, sha256: digest, refCount: 1 })
        .onConflictDoNothing()
        .returning({ id: storageObjects.id })
    )[0];
    if (object === undefined) {
      return;
    }
    await tx.insert(assets).values({
      id: assetId,
      memoryId: source.memoryId,
      ownerId: source.ownerId,
      role,
      status: 'ready',
      mime,
      bytes: body.length,
      sha256: digest,
      width: extra.width ?? null,
      height: extra.height ?? null,
      durationMs: extra.durationMs ?? null,
      storageObjectId: object.id,
    });
    await tx
      .update(memories)
      .set({ version: sql`${memories.version} + 1`, changeSeq: seq, updatedAt: new Date() })
      .where(eq(memories.id, source.memoryId));
    await recordChange(tx, { ownerId: source.ownerId, entity: 'memory', entityId: source.memoryId, op: 'upsert', seq });
    await refreshStorageBytes(tx, source.ownerId);
    stored = true;
  });
  return stored;
}

/**
 * Makes browser-playable renditions of an uploaded clip or video (media-pipeline: motion.transcode /
 * video.transcode, VID-005, VID-006, MOT-006). Idempotent. A file ffmpeg cannot read is recorded as a
 * `skipped`/`failed` outcome rather than thrown, so one corrupt upload never poisons the queue.
 */
export async function transcodeAsset(services: JobServices, assetId: string): Promise<TranscodeOutcome> {
  const db = services.database.db;
  const source = (await db.select().from(assets).where(eq(assets.id, assetId)))[0];
  if (source === undefined || (source.role !== 'motion_clip' && source.role !== 'video_original')) {
    return 'skipped';
  }
  if (source.status !== 'verified' && source.status !== 'ready') {
    return 'skipped';
  }
  const webRole: DerivedRole = source.role === 'motion_clip' ? 'motion_web' : 'video_web';
  const siblings = await db.select({ role: assets.role }).from(assets).where(eq(assets.memoryId, source.memoryId));
  const have = new Set(siblings.map((row) => row.role));
  const needPoster = source.role === 'video_original' ? !have.has('video_poster') : !have.has('thumbnail');
  if (have.has(webRole) && !needPoster) {
    return 'exists';
  }
  const object =
    source.storageObjectId === null ? undefined : (await db.select().from(storageObjects).where(eq(storageObjects.id, source.storageObjectId)))[0];
  if (object === undefined) {
    return 'skipped';
  }

  try {
    return await withTempDir(async (dir) => {
      const input = path.join(dir, 'input');
      await downloadToFile(services, object.key, input);
      const info = await probe(input);
      if (!info.hasVideo) {
        throw new MediaError('no video stream');
      }
      let created = false;
      if (!have.has(webRole)) {
        const output = path.join(dir, 'web.mp4');
        await transcodeToWebMp4(input, output);
        const result = await probe(output);
        created = await storeDerived(services, source, webRole, output, 'video/mp4', { width: result.width, height: result.height, durationMs: result.durationMs });
      }
      if (needPoster) {
        const poster = path.join(dir, 'poster.jpg');
        await extractPoster(input, poster, Math.min(0.5, (info.durationMs ?? 0) / 2000));
        const size = (await stat(poster)).size;
        if (size > 0) {
          const role: DerivedRole = source.role === 'video_original' ? 'video_poster' : 'thumbnail';
          created = (await storeDerived(services, source, role, poster, 'image/jpeg', { width: info.width, height: info.height })) || created;
          if (source.role === 'video_original' && !have.has('thumbnail')) {
            const small = path.join(dir, 'thumb.jpg');
            await sharp(poster).resize({ width: 512, height: 512, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 80 }).toFile(small);
            const meta = await sharp(small).metadata();
            created = (await storeDerived(services, source, 'thumbnail', small, 'image/jpeg', { width: meta.width ?? null, height: meta.height ?? null })) || created;
          }
        }
      }
      return created ? 'created' : 'exists';
    });
  } catch (error) {
    if (error instanceof MediaError) {
      return 'failed';
    }
    throw error;
  }
}

/** Streams an object to a temp file for tools that need a path; used by sanitizing and export code. */
export async function streamToBuffer(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks);
}

export { createReadStream, withTempDir };
