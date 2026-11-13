import { createHash } from 'node:crypto';
import type { Readable } from 'node:stream';
import { DeleteObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { and, eq, sql } from 'drizzle-orm';
import { assets, memories, storageObjects, usersProfile } from '../../db/schema.ts';
import { JOBS } from '../../lib/queue.ts';
import type { JobServices } from '../context.ts';
import { nextSeq, recordChange } from '../sync/change-log.ts';

export type VerifyOutcome = 'verified' | 'checksum_mismatch' | 'skipped' | 'missing_object';

/** SHA-256 of an object, streamed so a 2 GiB clip never sits in memory. */
export async function hashObject(services: Pick<JobServices, 'storage'>, key: string): Promise<string> {
  const response = await services.storage.client.send(new GetObjectCommand({ Bucket: services.storage.bucket, Key: key }));
  const hash = createHash('sha256');
  for await (const chunk of response.Body as Readable) {
    hash.update(chunk as Buffer);
  }
  return hash.digest('hex');
}

/**
 * Worker step that makes an uploaded asset trustworthy (docs/specs/upload-sync.md §5, SYNC-008, NFR-005).
 * Idempotent: only assets in `uploaded` are processed, so a retried job does nothing the second time.
 */
export async function verifyAsset(services: JobServices, assetId: string): Promise<VerifyOutcome> {
  const { database, storage } = services;
  const db = database.db;
  const asset = (await db.select().from(assets).where(eq(assets.id, assetId)))[0];
  if (asset === undefined || asset.status !== 'uploaded') {
    return 'skipped';
  }
  const key = `o/${asset.ownerId}/${asset.memoryId}/${asset.id}/${asset.role}`;

  let actual: string;
  try {
    actual = await hashObject(services, key);
  } catch {
    await markFailed(services, assetId, asset.ownerId, asset.memoryId, 'object_missing');
    return 'missing_object';
  }

  if (actual !== asset.sha256.toString('hex')) {
    await storage.client.send(new DeleteObjectCommand({ Bucket: storage.bucket, Key: key }));
    await markFailed(services, assetId, asset.ownerId, asset.memoryId, 'checksum_mismatch');
    return 'checksum_mismatch';
  }

  const seq = await nextSeq(db);
  let duplicateKey: string | null = null;
  await db.transaction(async (tx) => {
    const inserted = await tx
      .insert(storageObjects)
      .values({ ownerId: asset.ownerId, key, bytes: asset.bytes, sha256: asset.sha256, refCount: 1 })
      .onConflictDoNothing()
      .returning({ id: storageObjects.id });
    let objectId = inserted[0]?.id;
    if (objectId === undefined) {
      // The owner already stores identical bytes: share that object and drop the copy we just uploaded.
      const existing = (
        await tx
          .update(storageObjects)
          .set({ refCount: sql`${storageObjects.refCount} + 1` })
          .where(
            and(
              eq(storageObjects.ownerId, asset.ownerId),
              eq(storageObjects.sha256, asset.sha256),
              eq(storageObjects.bytes, asset.bytes),
            ),
          )
          .returning({ id: storageObjects.id, key: storageObjects.key })
      )[0];
      /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
      if (existing === undefined) {
        throw new Error('storage object conflict without an existing row');
      }
      objectId = existing.id;
      duplicateKey = existing.key === key ? null : key;
    }
    await tx
      .update(assets)
      .set({ status: 'verified', storageObjectId: objectId, uploadId: null, failureReason: null, updatedAt: new Date() })
      .where(eq(assets.id, assetId));
    await tx
      .update(memories)
      .set({ version: sql`${memories.version} + 1`, changeSeq: seq, updatedAt: new Date() })
      .where(eq(memories.id, asset.memoryId));
    await recordChange(tx, { ownerId: asset.ownerId, entity: 'memory', entityId: asset.memoryId, op: 'upsert', seq });
    await refreshStorageBytes(tx, asset.ownerId);
  });
  if (duplicateKey !== null) {
    await storage.client.send(new DeleteObjectCommand({ Bucket: storage.bucket, Key: duplicateKey }));
  }
  // Browser-playable renditions and posters are made by the worker (VID-005, VID-006, MOT-006).
  if (asset.role === 'motion_clip') {
    await services.jobs.enqueue(JOBS.motionTranscode, { assetId });
  } else if (asset.role === 'video_original') {
    await services.jobs.enqueue(JOBS.videoTranscode, { assetId });
  }
  return 'verified';
}

async function markFailed(services: JobServices, assetId: string, ownerId: string, memoryId: string, reason: string): Promise<void> {
  const db = services.database.db;
  const seq = await nextSeq(db);
  await db.transaction(async (tx) => {
    await tx.update(assets).set({ status: 'failed', failureReason: reason, uploadId: null, updatedAt: new Date() }).where(eq(assets.id, assetId));
    await tx
      .update(memories)
      .set({ version: sql`${memories.version} + 1`, changeSeq: seq, updatedAt: new Date() })
      .where(eq(memories.id, memoryId));
    await recordChange(tx, { ownerId, entity: 'memory', entityId: memoryId, op: 'upsert', seq });
  });
}

/** Keeps users_profile.storage_bytes equal to the bytes of the owner's stored objects. */
export async function refreshStorageBytes(
  executor: Pick<JobServices['database']['db'], 'insert' | 'update' | 'select'>,
  ownerId: string,
): Promise<void> {
  const total = (
    await executor
      .select({ total: sql<string>`coalesce(sum(${storageObjects.bytes}), 0)` })
      .from(storageObjects)
      .where(eq(storageObjects.ownerId, ownerId))
  )[0];
  const bytes = Number(total?.total ?? 0);
  await executor
    .insert(usersProfile)
    .values({ userId: ownerId, storageBytes: bytes })
    .onConflictDoUpdate({ target: usersProfile.userId, set: { storageBytes: bytes } });
}
