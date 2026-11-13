import { createHash, randomUUID } from 'node:crypto';
import {
  AbortMultipartUploadCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
} from '@aws-sdk/client-s3';
import { and, eq, inArray, isNotNull, isNull, lt, sql } from 'drizzle-orm';
import sharp from 'sharp';
import { assets, dataExports, idempotencyKeys, memories, storageObjects, user, usersProfile } from '../../db/schema.ts';
import { type JobHandler, type JobName, JOBS } from '../../lib/queue.ts';
import { verifyAsset, refreshStorageBytes } from '../assets/verify.ts';
import { buildExport } from '../exports/build.ts';
import { transcodeAsset } from '../media/transcode.ts';
import type { JobServices } from '../context.ts';
import { DELETION_GRACE_DAYS } from '../me/routes.ts';
import { assetKey } from '../memories/serialize.ts';
import { nextSeq, pruneChanges, recordChange } from '../sync/change-log.ts';

export const TRASH_RETENTION_DAYS = 30;
export const CHANGE_RETENTION_DAYS = 90;
const DAY_MS = 86_400_000;

async function deleteKeys(services: JobServices, keys: readonly string[]): Promise<void> {
  const { storage } = services;
  for (let i = 0; i < keys.length; i += 1000) {
    await storage.client.send(
      new DeleteObjectsCommand({
        Bucket: storage.bucket,
        Delete: { Objects: keys.slice(i, i + 1000).map((Key) => ({ Key })), Quiet: true },
      }),
    );
  }
}

/** Permanently removes a Memory, its asset rows and any stored object nobody else references (MEM-007). Idempotent. */
export async function purgeMemory(services: JobServices, memoryId: string): Promise<boolean> {
  const db = services.database.db;
  const memory = (await db.select().from(memories).where(eq(memories.id, memoryId)))[0];
  if (memory === undefined) {
    return false;
  }
  const rows = await db.select().from(assets).where(eq(assets.memoryId, memoryId));
  for (const asset of rows) {
    if (asset.uploadId !== null) {
      await services.storage.client
        .send(
          new AbortMultipartUploadCommand({
            Bucket: services.storage.bucket,
            Key: assetKey(asset.ownerId, asset.memoryId, asset.id, asset.role),
            UploadId: asset.uploadId,
          }),
        )
        .catch(() => undefined);
    }
  }
  const orphanKeys: string[] = [];
  await db.transaction(async (tx) => {
    const objectIds = rows.flatMap((row) => (row.storageObjectId === null ? [] : [row.storageObjectId]));
    await tx.delete(memories).where(eq(memories.id, memoryId)); // assets and album items cascade
    for (const objectId of objectIds) {
      const updated = (
        await tx
          .update(storageObjects)
          .set({ refCount: sql`${storageObjects.refCount} - 1` })
          .where(eq(storageObjects.id, objectId))
          .returning()
      )[0];
      if (updated !== undefined && updated.refCount <= 0) {
        orphanKeys.push(updated.key);
        await tx.delete(storageObjects).where(eq(storageObjects.id, objectId));
      }
    }
    await recordChange(tx, { ownerId: memory.ownerId, entity: 'memory', entityId: memoryId, op: 'delete' });
    await refreshStorageBytes(tx, memory.ownerId);
  });
  // Objects are removed after the rows are committed: a crash leaves an orphan object, never a row pointing at nothing.
  await deleteKeys(services, orphanKeys);
  return true;
}

/** Deletes an account: every Memory and object, then the user row (PRIV-004). Resumable and idempotent. */
export async function deleteUser(services: JobServices, userId: string): Promise<boolean> {
  const db = services.database.db;
  const target = (await db.select({ id: user.id }).from(user).where(eq(user.id, userId)))[0];
  if (target === undefined) {
    return false;
  }
  const { storage } = services;
  for (const prefix of [`o/${userId}/`, `exports/${userId}/`]) {
    let token: string | undefined;
    do {
      const page = await storage.client.send(
        new ListObjectsV2Command({ Bucket: storage.bucket, Prefix: prefix, ...(token === undefined ? {} : { ContinuationToken: token }) }),
      );
      await deleteKeys(
        services,
        (page.Contents ?? []).flatMap((object) => (object.Key === undefined ? [] : [object.Key])),
      );
      token = page.IsTruncated === true ? page.NextContinuationToken : undefined;
    } while (token !== undefined);
  }
  await db.delete(user).where(eq(user.id, userId)); // cascades to every row the user owns
  return true;
}

/** Builds thumbnail and display JPEGs from `photo_rendered` when the device did not upload them (media-pipeline "derivative.fallback"). */
export async function deriveFallbacks(services: JobServices, memoryId: string): Promise<string[]> {
  const db = services.database.db;
  const { storage } = services;
  const rows = await db.select().from(assets).where(eq(assets.memoryId, memoryId));
  const rendered = rows.find((row) => row.role === 'photo_rendered' && (row.status === 'verified' || row.status === 'ready') && row.storageObjectId !== null);
  if (rendered === undefined || rendered.storageObjectId === null) {
    return [];
  }
  const source = (await db.select().from(storageObjects).where(eq(storageObjects.id, rendered.storageObjectId)))[0];
  if (source === undefined) {
    return [];
  }
  const missing = (['thumbnail', 'photo_display'] as const).filter((role) => !rows.some((row) => row.role === role));
  if (missing.length === 0) {
    return [];
  }
  const object = await storage.client.send(new GetObjectCommand({ Bucket: storage.bucket, Key: source.key }));
  const original = Buffer.from(await (object.Body as { transformToByteArray(): Promise<Uint8Array> }).transformToByteArray());
  const created: string[] = [];
  for (const role of missing) {
    const longEdge = role === 'thumbnail' ? 512 : 2048;
    const body = await sharp(original).rotate().resize({ width: longEdge, height: longEdge, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 82 }).toBuffer({ resolveWithObject: true });
    const assetId = randomUUID();
    const key = assetKey(rendered.ownerId, memoryId, assetId, role);
    await storage.client.send(new PutObjectCommand({ Bucket: storage.bucket, Key: key, Body: body.data, ContentType: 'image/jpeg' }));
    const digest = createHash('sha256').update(body.data).digest();
    const seq = await nextSeq(db);
    await db.transaction(async (tx) => {
      const stored = (
        await tx
          .insert(storageObjects)
          .values({ ownerId: rendered.ownerId, key, bytes: body.data.length, sha256: digest, refCount: 1 })
          .onConflictDoNothing()
          .returning({ id: storageObjects.id })
      )[0];
      if (stored === undefined) {
        return; // identical bytes already stored for this owner; nothing to add
      }
      await tx.insert(assets).values({
        id: assetId,
        memoryId,
        ownerId: rendered.ownerId,
        role,
        status: 'verified',
        mime: 'image/jpeg',
        bytes: body.data.length,
        sha256: digest,
        width: body.info.width,
        height: body.info.height,
        storageObjectId: stored.id,
      });
      await tx
        .update(memories)
        .set({ version: sql`${memories.version} + 1`, changeSeq: seq, updatedAt: new Date() })
        .where(eq(memories.id, memoryId));
      await recordChange(tx, { ownerId: rendered.ownerId, entity: 'memory', entityId: memoryId, op: 'upsert', seq });
      await refreshStorageBytes(tx, rendered.ownerId);
      created.push(role);
    });
  }
  return created;
}

/** Periodic housekeeping: trash expiry, due account deletions, fallback derivatives, feed and key retention. */
export async function sweep(services: JobServices, now: Date = new Date()): Promise<Record<string, number>> {
  const db = services.database.db;

  const expired = await db
    .select({ id: memories.id })
    .from(memories)
    .where(and(isNotNull(memories.deletedAt), lt(memories.deletedAt, new Date(now.getTime() - TRASH_RETENTION_DAYS * DAY_MS))));
  for (const row of expired) {
    await purgeMemory(services, row.id);
  }

  const dueUsers = await db
    .select({ userId: usersProfile.userId })
    .from(usersProfile)
    .where(and(isNotNull(usersProfile.deletionRequestedAt), lt(usersProfile.deletionRequestedAt, new Date(now.getTime() - DELETION_GRACE_DAYS * DAY_MS))));
  for (const row of dueUsers) {
    await deleteUser(services, row.userId);
  }

  const candidates = await db
    .selectDistinct({ memoryId: assets.memoryId })
    .from(assets)
    .where(and(eq(assets.role, 'photo_rendered'), inArray(assets.status, ['verified', 'ready']), lt(assets.updatedAt, new Date(now.getTime() - 10 * 60_000))));
  let derived = 0;
  for (const row of candidates) {
    derived += (await deriveFallbacks(services, row.memoryId)).length;
  }

  const staleExports = await db.select().from(dataExports).where(lt(dataExports.expiresAt, now));
  for (const old of staleExports) {
    if (old.objectKey !== null) {
      await deleteKeys(services, [old.objectKey]);
    }
    await db.delete(dataExports).where(eq(dataExports.id, old.id));
  }

  const prunedChanges = await pruneChanges(db, new Date(now.getTime() - CHANGE_RETENTION_DAYS * DAY_MS));
  const prunedKeys = (await db.delete(idempotencyKeys).where(lt(idempotencyKeys.createdAt, new Date(now.getTime() - DAY_MS))).returning({ key: idempotencyKeys.key })).length;
  void isNull;
  return { purgedMemories: expired.length, deletedUsers: dueUsers.length, derivatives: derived, prunedChanges, prunedKeys, expiredExports: staleExports.length };
}

function stringField(payload: Record<string, unknown>, name: string): string {
  const value = payload[name];
  if (typeof value !== 'string') {
    throw new Error(`job payload is missing "${name}"`);
  }
  return value;
}

export function createJobHandlers(services: JobServices): Record<JobName, JobHandler> {
  return {
    [JOBS.assetVerify]: async (payload) => {
      await verifyAsset(services, stringField(payload, 'assetId'));
    },
    [JOBS.derivativeFallback]: async (payload) => {
      await deriveFallbacks(services, stringField(payload, 'memoryId'));
    },
    [JOBS.memoryPurge]: async (payload) => {
      await purgeMemory(services, stringField(payload, 'memoryId'));
    },
    [JOBS.userDelete]: async (payload) => {
      await deleteUser(services, stringField(payload, 'userId'));
    },
    [JOBS.motionTranscode]: async (payload) => {
      await transcodeAsset(services, stringField(payload, 'assetId'));
    },
    [JOBS.videoTranscode]: async (payload) => {
      await transcodeAsset(services, stringField(payload, 'assetId'));
    },
    [JOBS.exportBuild]: async (payload) => {
      await buildExport(services, stringField(payload, 'exportId'));
    },
    [JOBS.sweep]: async () => {
      await sweep(services);
    },
  };
}
