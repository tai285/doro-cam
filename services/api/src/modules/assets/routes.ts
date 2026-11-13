import {
  AbortMultipartUploadCommand,
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListPartsCommand,
} from '@aws-sdk/client-s3';
import { and, eq, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import sharp from 'sharp';
import { z } from 'zod';
import { assets, memories, storageObjects } from '../../db/schema.ts';
import { AppError, ConflictError, ForbiddenError, NotFoundError } from '../../lib/errors.ts';
import { presignGet, presignPart, presignPut } from '../../lib/presign.ts';
import { JOBS } from '../../lib/queue.ts';
import type { Services } from '../context.ts';
import { resolveMemoryAccess } from '../memories/access.ts';
import { assetKey, isServable } from '../memories/serialize.ts';
import { clientAssetRoleSchema } from '../memories/schemas.ts';
import { nextSeq, recordChange } from '../sync/change-log.ts';
import { type ClientRole, checkUpload, planUpload } from './rules.ts';
import { refreshStorageBytes } from './verify.ts';
import { storageUsedBytes } from '../me/routes.ts';

const params = z.object({ memoryId: z.uuid(), assetId: z.uuid() });

const createUploadBody = z.object({
  role: clientAssetRoleSchema,
  mime: z.string().min(3).max(100),
  bytes: z.number().int().positive(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/i, 'must be 64 hexadecimal characters'),
  width: z.number().int().positive().optional(),
  height: z.number().int().positive().optional(),
  durationMs: z.number().int().nonnegative().optional(),
});

const signedUrl = z.object({ url: z.string(), expiresAt: z.string() });

const createUploadResponse = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('complete'), status: z.literal('complete'), deduplicated: z.boolean() }),
  z.object({ mode: z.literal('single'), ...signedUrl.shape, headers: z.record(z.string(), z.string()) }),
  z.object({
    mode: z.literal('multipart'),
    uploadId: z.string(),
    partSize: z.number(),
    partCount: z.number(),
    expiresAt: z.string(),
    parts: z.array(z.object({ partNumber: z.number(), url: z.string() })),
    completed: z.array(z.object({ partNumber: z.number(), etag: z.string() })),
  }),
]);

const completeBody = z.object({
  uploadId: z.string().optional(),
  parts: z.array(z.object({ partNumber: z.number().int().positive(), etag: z.string().min(1) })).optional(),
});

const statusResponse = z.object({ status: z.enum(['pending', 'uploading', 'uploaded', 'verified', 'ready', 'failed']) });

class UploadError extends AppError {}

async function listAllParts(services: Services, key: string, uploadId: string) {
  const parts: Array<{ partNumber: number; etag: string }> = [];
  let marker: string | undefined;
  for (;;) {
    const page = await services.storage.client.send(
      new ListPartsCommand({
        Bucket: services.storage.bucket,
        Key: key,
        UploadId: uploadId,
        ...(marker === undefined ? {} : { PartNumberMarker: marker }),
      }),
    );
    for (const part of page.Parts ?? []) {
      if (part.PartNumber !== undefined && part.ETag !== undefined) {
        parts.push({ partNumber: part.PartNumber, etag: part.ETag });
      }
    }
    if (page.IsTruncated !== true || page.NextPartNumberMarker === undefined) {
      return parts;
    }
    marker = page.NextPartNumberMarker;
  }
}

async function objectSize(services: Services, key: string): Promise<number | null> {
  try {
    const head = await services.storage.client.send(new HeadObjectCommand({ Bucket: services.storage.bucket, Key: key }));
    return head.ContentLength ?? null;
  } catch {
    return null;
  }
}

/** Upload sessions, completion and authorized downloads (SYNC-002..004, SYNC-008, WEB-004, PRIV-002, PRIV-003). */
export function assetRoutes(services: Services): FastifyPluginAsync {
  const { database, storage, guard, jobs, config } = services;
  const db = database.db;

  const loadOwnedMemory = async (userId: string, memoryId: string) => {
    const access = await resolveMemoryAccess(db, userId, memoryId);
    if (access === null || !access.isOwner) {
      throw new NotFoundError('Memory not found.', 'memory.not_found');
    }
    return access.memory;
  };

  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.post(
      '/v1/memories/:memoryId/assets/:assetId/upload',
      { schema: { params, body: createUploadBody, response: { 200: createUploadResponse } } },
      async (request) => {
        const principal = await guard(request);
        const memory = await loadOwnedMemory(principal.userId, request.params.memoryId);
        const { role, mime, bytes, sha256, width, height, durationMs } = request.body;
        const assetId = request.params.assetId;

        const check = checkUpload(role as ClientRole, memory.kind, mime, bytes);
        if (!check.ok) {
          if (check.code === 'too_large') {
            throw new UploadError(413, 'upload.too_large', 'The file is larger than allowed for this kind of media.');
          }
          if (check.code === 'unsupported_type') {
            throw new UploadError(415, 'upload.unsupported_type', `${mime} is not accepted for ${role}.`);
          }
          throw new UploadError(422, 'upload.role_not_allowed', `${role} is not valid for a ${memory.kind} Memory.`);
        }

        let asset = (await db.select().from(assets).where(eq(assets.id, assetId)))[0];
        if (asset !== undefined && (asset.memoryId !== memory.id || asset.ownerId !== principal.userId)) {
          throw new ConflictError('This asset id belongs to a different Memory.', 'asset.conflict');
        }
        if (asset !== undefined && (asset.role !== role || asset.bytes !== bytes || asset.sha256.toString('hex') !== sha256.toLowerCase())) {
          throw new ConflictError('The asset was registered with different contents.', 'asset.conflict');
        }
        if (asset !== undefined && (asset.status === 'verified' || asset.status === 'ready')) {
          return { mode: 'complete' as const, status: 'complete' as const, deduplicated: false };
        }

        const key = assetKey(principal.userId, memory.id, assetId, role);
        const digest = Buffer.from(sha256, 'hex');

        if (asset === undefined) {
          const sameRole = (await db.select().from(assets).where(and(eq(assets.memoryId, memory.id), eq(assets.role, role))))[0];
          if (sameRole !== undefined) {
            if (sameRole.status !== 'failed') {
              throw new ConflictError(`This Memory already has a ${role} asset.`, 'asset.role_taken');
            }
            await db.delete(assets).where(eq(assets.id, sameRole.id));
          }

          const existingObject = (
            await db
              .select()
              .from(storageObjects)
              .where(and(eq(storageObjects.ownerId, principal.userId), eq(storageObjects.sha256, digest), eq(storageObjects.bytes, bytes)))
          )[0];
          if (existingObject === undefined) {
            const used = await storageUsedBytes(database, principal.userId);
            if (used + bytes > config.limits.storageQuotaBytes) {
              throw new UploadError(403, 'upload.quota_exceeded', 'Your storage quota is full.');
            }
          }

          const seq = await nextSeq(db);
          const created = await db.transaction(async (tx) => {
            const row = (
              await tx
                .insert(assets)
                .values({
                  id: assetId,
                  memoryId: memory.id,
                  ownerId: principal.userId,
                  role,
                  mime,
                  bytes,
                  sha256: digest,
                  width: width ?? null,
                  height: height ?? null,
                  durationMs: durationMs ?? null,
                  status: existingObject === undefined ? 'uploading' : 'verified',
                  storageObjectId: existingObject?.id ?? null,
                })
                .returning()
            )[0];
            /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
            if (row === undefined) {
              throw new Error('insert returned no row');
            }
            if (existingObject !== undefined) {
              await tx
                .update(storageObjects)
                .set({ refCount: sql`${storageObjects.refCount} + 1` })
                .where(eq(storageObjects.id, existingObject.id));
              await tx
                .update(memories)
                .set({ version: sql`${memories.version} + 1`, changeSeq: seq, updatedAt: new Date() })
                .where(eq(memories.id, memory.id));
              await recordChange(tx, { ownerId: principal.userId, entity: 'memory', entityId: memory.id, op: 'upsert', seq });
              await refreshStorageBytes(tx, principal.userId);
            }
            return row;
          });
          if (existingObject !== undefined) {
            return { mode: 'complete' as const, status: 'complete' as const, deduplicated: true };
          }
          asset = created;
        } else if (asset.status === 'failed') {
          await db.update(assets).set({ status: 'uploading', failureReason: null, uploadId: null, updatedAt: new Date() }).where(eq(assets.id, assetId));
          asset = { ...asset, status: 'uploading', uploadId: null };
        }

        const plan = planUpload(bytes);
        if (plan.mode === 'single') {
          const signed = await presignPut(storage, key, mime);
          return { mode: 'single' as const, ...signed, headers: { 'content-type': mime } };
        }

        let uploadId = asset.uploadId;
        if (uploadId === null) {
          const created = await storage.client.send(
            new CreateMultipartUploadCommand({ Bucket: storage.bucket, Key: key, ContentType: mime }),
          );
          if (created.UploadId === undefined) {
            throw new UploadError(503, 'service.unavailable', 'Storage did not start the upload.');
          }
          uploadId = created.UploadId;
          await db.update(assets).set({ uploadId, updatedAt: new Date() }).where(eq(assets.id, assetId));
        }
        const completed = await listAllParts(services, key, uploadId).catch(() => []);
        const done = new Set(completed.map((part) => part.partNumber));
        const parts: Array<{ partNumber: number; url: string }> = [];
        let expiresAt = new Date().toISOString();
        for (let partNumber = 1; partNumber <= plan.partCount; partNumber += 1) {
          if (!done.has(partNumber)) {
            const signed = await presignPart(storage, key, uploadId, partNumber);
            parts.push({ partNumber, url: signed.url });
            expiresAt = signed.expiresAt;
          }
        }
        return { mode: 'multipart' as const, uploadId, partSize: plan.partSize, partCount: plan.partCount, expiresAt, parts, completed };
      },
    );

    typed.post(
      '/v1/memories/:memoryId/assets/:assetId/upload/complete',
      { schema: { params, body: completeBody, response: { 200: statusResponse } } },
      async (request) => {
        const principal = await guard(request);
        const memory = await loadOwnedMemory(principal.userId, request.params.memoryId);
        const asset = (
          await db.select().from(assets).where(and(eq(assets.id, request.params.assetId), eq(assets.memoryId, memory.id)))
        )[0];
        if (asset === undefined) {
          throw new UploadError(404, 'upload.not_found', 'There is no upload for this asset.');
        }
        if (asset.status !== 'uploading') {
          return { status: asset.status }; // already completed (or verified): idempotent
        }
        const key = assetKey(principal.userId, memory.id, asset.id, asset.role);

        if (asset.uploadId !== null) {
          try {
            const parts = request.body.parts ?? (await listAllParts(services, key, asset.uploadId));
            await storage.client.send(
              new CompleteMultipartUploadCommand({
                Bucket: storage.bucket,
                Key: key,
                UploadId: asset.uploadId,
                MultipartUpload: {
                  Parts: [...parts]
                    .sort((a, b) => a.partNumber - b.partNumber)
                    .map((part) => ({ PartNumber: part.partNumber, ETag: part.etag })),
                },
              }),
            );
          } catch (error) {
            // A retry after a lost response finds the upload already completed: fall through to the size check.
            if ((await objectSize(services, key)) === null) {
              throw new UploadError(404, 'upload.not_found', 'The upload session expired. Start the upload again.');
            }
            void error;
          }
        }

        const size = await objectSize(services, key);
        if (size === null) {
          throw new UploadError(404, 'upload.not_found', 'The file has not been uploaded.');
        }
        if (size !== asset.bytes) {
          await storage.client.send(new DeleteObjectCommand({ Bucket: storage.bucket, Key: key }));
          await db.update(assets).set({ status: 'pending', uploadId: null, updatedAt: new Date() }).where(eq(assets.id, asset.id));
          throw new UploadError(422, 'upload.size_mismatch', 'The uploaded file size differs from the declared size.');
        }

        await db.update(assets).set({ status: 'uploaded', updatedAt: new Date() }).where(eq(assets.id, asset.id));
        await jobs.enqueue(JOBS.assetVerify, { assetId: asset.id });
        const final = (await db.select({ status: assets.status }).from(assets).where(eq(assets.id, asset.id)))[0];
        return { status: final?.status ?? 'uploaded' };
      },
    );

    typed.post(
      '/v1/memories/:memoryId/assets/:assetId/upload/abort',
      { schema: { params, response: { 204: z.null() } } },
      async (request, reply) => {
        const principal = await guard(request);
        const memory = await loadOwnedMemory(principal.userId, request.params.memoryId);
        const asset = (
          await db.select().from(assets).where(and(eq(assets.id, request.params.assetId), eq(assets.memoryId, memory.id)))
        )[0];
        if (asset !== undefined && asset.status === 'uploading') {
          const key = assetKey(principal.userId, memory.id, asset.id, asset.role);
          if (asset.uploadId !== null) {
            await storage.client
              .send(new AbortMultipartUploadCommand({ Bucket: storage.bucket, Key: key, UploadId: asset.uploadId }))
              .catch(() => undefined);
          }
          await db.delete(assets).where(eq(assets.id, asset.id));
        }
        return reply.status(204).send(null);
      },
    );

    const loadServable = async (userId: string, memoryId: string, assetId: string) => {
      const access = await resolveMemoryAccess(db, userId, memoryId, { includeTrashed: true });
      if (access === null) {
        throw new NotFoundError('Asset not found.', 'asset.not_found');
      }
      const row = (await db.select().from(assets).where(and(eq(assets.id, assetId), eq(assets.memoryId, memoryId))))[0];
      if (row === undefined || !isServable(row)) {
        throw new NotFoundError('Asset not found.', 'asset.not_found');
      }
      const object =
        row.storageObjectId === null
          ? undefined
          : (await db.select().from(storageObjects).where(eq(storageObjects.id, row.storageObjectId)))[0];
      if (object === undefined) {
        throw new NotFoundError('Asset not found.', 'asset.not_found');
      }
      const isOriginal = row.role === 'photo_original' || row.role === 'video_original';
      if (!access.isOwner && isOriginal && !access.canDownloadOriginal) {
        throw new ForbiddenError('The album owner does not allow original downloads.', 'download.original_not_allowed');
      }
      return { access, asset: row, key: object.key };
    };

    typed.get(
      '/v1/memories/:memoryId/assets/:assetId/download',
      {
        schema: {
          params,
          response: { 200: z.object({ url: z.string(), expiresAt: z.string(), sanitized: z.boolean(), filename: z.string() }) },
        },
      },
      async (request) => {
        const principal = await guard(request);
        const { access, asset, key } = await loadServable(principal.userId, request.params.memoryId, request.params.assetId);
        const extension = asset.mime === 'image/jpeg' ? 'jpg' : (asset.mime.split('/')[1] ?? 'bin');
        const filename = `${asset.role}-${access.memory.id.slice(0, 8)}.${extension}`;
        if (!access.isOwner && !access.canSeeLocation) {
          // Non-owners who may not see location never receive the raw object (PRIV-002).
          return {
            url: `/v1/memories/${access.memory.id}/assets/${asset.id}/content`,
            expiresAt: new Date(Date.now() + 600_000).toISOString(),
            sanitized: true,
            filename,
          };
        }
        const signed = await presignGet(storage, key, { filename, contentType: asset.mime });
        return { ...signed, sanitized: false, filename };
      },
    );

    typed.get(
      '/v1/memories/:memoryId/assets/:assetId/content',
      { schema: { params } },
      async (request, reply) => {
        const principal = await guard(request);
        const { access, asset, key } = await loadServable(principal.userId, request.params.memoryId, request.params.assetId);
        const object = await storage.client.send(new GetObjectCommand({ Bucket: storage.bucket, Key: key }));
        if (access.isOwner || access.canSeeLocation) {
          return reply.header('content-type', asset.mime).header('cache-control', 'private, no-store').send(object.Body);
        }
        if (asset.mime !== 'image/jpeg') {
          throw new ConflictError('This kind of file cannot be shared without location metadata.', 'asset.not_sanitizable');
        }
        const body = Buffer.from(await (object.Body as { transformToByteArray(): Promise<Uint8Array> }).transformToByteArray());
        // sharp drops EXIF/XMP (including GPS) unless asked to keep it; rotate() bakes in the orientation first.
        const clean = await sharp(body).rotate().jpeg({ quality: 92 }).toBuffer();
        return reply.header('content-type', 'image/jpeg').header('cache-control', 'private, no-store').send(clean);
      },
    );
  };
}
