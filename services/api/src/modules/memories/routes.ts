import { and, desc, eq, isNotNull, isNull, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { memories } from '../../db/schema.ts';
import { BadRequestError, ConflictError, NotFoundError } from '../../lib/errors.ts';
import { newPublicHandle } from '../../lib/ids.ts';
import { JOBS } from '../../lib/queue.ts';
import type { Services } from '../context.ts';
import { nextSeq, recordChange } from '../sync/change-log.ts';
import { type MemoryRow, resolveMemoryAccess } from './access.ts';
import {
  listQuery,
  memoryParams,
  memorySchema,
  patchMemoryBody,
  type RegisterMemoryBody,
  registerMemoryBody,
} from './schemas.ts';
import { loadAssets, loadKeys, serializeMemory } from './serialize.ts';

function encodeCursor(row: Pick<MemoryRow, 'capturedAt' | 'id'>): string {
  return Buffer.from(`${row.capturedAt.toISOString()}|${row.id}`).toString('base64url');
}

function decodeCursor(cursor: string): { capturedAt: Date; id: string } {
  const [iso, id] = Buffer.from(cursor, 'base64url').toString().split('|');
  const capturedAt = new Date(iso ?? '');
  if (iso === undefined || id === undefined || Number.isNaN(capturedAt.getTime()) || !z.uuid().safeParse(id).success) {
    throw new BadRequestError('The cursor is invalid.', undefined, 'request.invalid_cursor');
  }
  return { capturedAt, id };
}

/** Typed columns extracted from the device-reported capture metadata for analytics (ADR-0007). */
export function analyticsColumns(capture: RegisterMemoryBody['capture']) {
  return {
    focalLength35mm: capture.focalLength35mmEq ?? null,
    iso: capture.isoApplied ?? null,
    exposureTimeNs: capture.exposureTimeNsApplied ?? null,
    aperture: capture.aperture ?? null,
    lensKind: capture.lensKind ?? null,
  };
}

function sameImmutableFields(existing: MemoryRow, body: RegisterMemoryBody): boolean {
  return (
    existing.kind === body.kind &&
    existing.capturedAt.getTime() === new Date(body.capturedAt).getTime() &&
    existing.capturedTz === body.capturedTz &&
    existing.experienceId === body.experienceId
  );
}

/** Memory registration, library, detail, edits and trash (MEM-004, MEM-006, MEM-007, WEB-002, WEB-003, SYNC-004). */
export function memoryRoutes(services: Services): FastifyPluginAsync {
  const { database, storage, guard, jobs } = services;
  const db = database.db;

  const present = async (userId: string, memory: MemoryRow, options: { includeTrashed?: boolean } = {}) => {
    const access = await resolveMemoryAccess(db, userId, memory.id, options);
    if (access === null) {
      throw new NotFoundError('Memory not found.', 'memory.not_found');
    }
    const assetsByMemory = await loadAssets(db, [memory.id]);
    const rows = assetsByMemory.get(memory.id) ?? [];
    return serializeMemory(db, storage, access, access.memory, rows, await loadKeys(db, rows));
  };

  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.put(
      '/v1/memories/:memoryId',
      {
        schema: {
          params: memoryParams,
          body: registerMemoryBody,
          response: { 200: memorySchema, 201: memorySchema },
        },
      },
      async (request, reply) => {
        const principal = await guard(request);
        const body = request.body;
        const existing = (await db.select().from(memories).where(eq(memories.id, request.params.memoryId)))[0];
        if (existing !== undefined) {
          if (existing.ownerId !== principal.userId || !sameImmutableFields(existing, body)) {
            throw new ConflictError('A Memory with this id already exists with different immutable fields.', 'memory.conflict');
          }
          return reply.status(200).send(await present(principal.userId, existing, { includeTrashed: true }));
        }

        const seq = await nextSeq(db);
        const inserted = await db.transaction(async (tx) => {
          const row = (
            await tx
              .insert(memories)
              .values({
                id: request.params.memoryId,
                ownerId: principal.userId,
                kind: body.kind,
                capturedAt: new Date(body.capturedAt),
                capturedTz: body.capturedTz,
                experienceId: body.experienceId,
                profileId: body.profile?.id ?? null,
                profileVersion: body.profile?.version ?? null,
                presetId: body.presetId ?? null,
                scenario: body.scenario ?? null,
                ...analyticsColumns(body.capture),
                capture: body.capture,
                lat: body.location?.lat ?? null,
                lon: body.location?.lon ?? null,
                locationAccuracyM: body.location?.accuracyM ?? null,
                caption: body.caption ?? null,
                favorite: body.favorite ?? false,
                aspectRatio: body.aspectRatio ?? null,
                publicHandle: newPublicHandle(),
                changeSeq: seq,
              })
              .returning()
          )[0];
          /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
          if (row === undefined) {
            throw new Error('insert returned no row');
          }
          await recordChange(tx, { ownerId: principal.userId, entity: 'memory', entityId: row.id, op: 'upsert', seq });
          return row;
        });
        return reply.status(201).send(await present(principal.userId, inserted));
      },
    );

    typed.get(
      '/v1/memories',
      {
        schema: {
          querystring: listQuery,
          response: { 200: z.object({ items: z.array(memorySchema), nextCursor: z.string().nullable() }) },
        },
      },
      async (request) => {
        const principal = await guard(request);
        const { limit, cursor, kind, favorite, trashed } = request.query;
        const conditions = [
          eq(memories.ownerId, principal.userId),
          trashed ? isNotNull(memories.deletedAt) : isNull(memories.deletedAt),
        ];
        if (kind !== undefined) {
          conditions.push(eq(memories.kind, kind));
        }
        if (favorite !== undefined) {
          conditions.push(eq(memories.favorite, favorite));
        }
        if (cursor !== undefined) {
          const after = decodeCursor(cursor);
          conditions.push(sql`(${memories.capturedAt}, ${memories.id}) < (${after.capturedAt.toISOString()}::timestamptz, ${after.id}::uuid)`);
        }
        const rows = await db
          .select()
          .from(memories)
          .where(and(...conditions))
          .orderBy(desc(memories.capturedAt), desc(memories.id))
          .limit(limit + 1);
        const page = rows.slice(0, limit);
        const assetsByMemory = await loadAssets(
          db,
          page.map((row) => row.id),
        );
        const allAssets = [...assetsByMemory.values()].flat();
        const keys = await loadKeys(db, allAssets);
        const items = await Promise.all(
          page.map((row) =>
            serializeMemory(db, storage, { isOwner: true, canSeeLocation: true }, row, assetsByMemory.get(row.id) ?? [], keys),
          ),
        );
        return { items, nextCursor: rows.length > limit && page.length > 0 ? encodeCursor(page[page.length - 1] as MemoryRow) : null };
      },
    );

    typed.get(
      '/v1/memories/:memoryId',
      { schema: { params: memoryParams, response: { 200: memorySchema } } },
      async (request) => {
        const principal = await guard(request);
        const access = await resolveMemoryAccess(db, principal.userId, request.params.memoryId, { includeTrashed: true });
        if (access === null) {
          throw new NotFoundError('Memory not found.', 'memory.not_found');
        }
        const rows = (await loadAssets(db, [access.memory.id])).get(access.memory.id) ?? [];
        return serializeMemory(db, storage, access, access.memory, rows, await loadKeys(db, rows));
      },
    );

    typed.patch(
      '/v1/memories/:memoryId',
      { schema: { params: memoryParams, body: patchMemoryBody, response: { 200: memorySchema } } },
      async (request) => {
        const principal = await guard(request);
        const access = await resolveMemoryAccess(db, principal.userId, request.params.memoryId);
        if (access === null || !access.isOwner) {
          throw new NotFoundError('Memory not found.', 'memory.not_found');
        }
        const ifMatch = request.headers['if-match'];
        if (typeof ifMatch === 'string' && Number(ifMatch) !== access.memory.version) {
          throw new ConflictError('The Memory changed since you loaded it.', 'conflict.version', { currentVersion: access.memory.version });
        }
        const body = request.body;
        const seq = await nextSeq(db);
        const updated = await db.transaction(async (tx) => {
          const row = (
            await tx
              .update(memories)
              .set({
                ...(body.caption === undefined ? {} : { caption: body.caption }),
                ...(body.favorite === undefined ? {} : { favorite: body.favorite }),
                ...(body.locationShared === undefined ? {} : { locationShared: body.locationShared }),
                ...(body.removeLocation === true ? { lat: null, lon: null, locationAccuracyM: null, locationShared: false } : {}),
                version: sql`${memories.version} + 1`,
                changeSeq: seq,
                updatedAt: new Date(),
              })
              .where(eq(memories.id, access.memory.id))
              .returning()
          )[0];
          /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
          if (row === undefined) {
            throw new NotFoundError('Memory not found.', 'memory.not_found');
          }
          await recordChange(tx, { ownerId: principal.userId, entity: 'memory', entityId: row.id, op: 'upsert', seq });
          return row;
        });
        return present(principal.userId, updated);
      },
    );

    const setTrashed = async (userId: string, memoryId: string, trashed: boolean) => {
      const access = await resolveMemoryAccess(db, userId, memoryId, { includeTrashed: true });
      if (access === null || !access.isOwner) {
        throw new NotFoundError('Memory not found.', 'memory.not_found');
      }
      if ((access.memory.deletedAt !== null) === trashed) {
        return access.memory; // already in the requested state: idempotent
      }
      const seq = await nextSeq(db);
      return db.transaction(async (tx) => {
        const row = (
          await tx
            .update(memories)
            .set({ deletedAt: trashed ? new Date() : null, version: sql`${memories.version} + 1`, changeSeq: seq, updatedAt: new Date() })
            .where(eq(memories.id, memoryId))
            .returning()
        )[0];
        /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
        if (row === undefined) {
          throw new NotFoundError('Memory not found.', 'memory.not_found');
        }
        await recordChange(tx, { ownerId: userId, entity: 'memory', entityId: memoryId, op: trashed ? 'delete' : 'upsert', seq });
        return row;
      });
    };

    typed.post(
      '/v1/memories/:memoryId/trash',
      { schema: { params: memoryParams, response: { 200: memorySchema } } },
      async (request) => {
        const principal = await guard(request);
        return present(principal.userId, await setTrashed(principal.userId, request.params.memoryId, true), { includeTrashed: true });
      },
    );

    typed.post(
      '/v1/memories/:memoryId/restore',
      { schema: { params: memoryParams, response: { 200: memorySchema } } },
      async (request) => {
        const principal = await guard(request);
        return present(principal.userId, await setTrashed(principal.userId, request.params.memoryId, false));
      },
    );

    typed.delete(
      '/v1/memories/:memoryId',
      { schema: { params: memoryParams, response: { 202: z.object({ status: z.literal('purging') }) } } },
      async (request, reply) => {
        const principal = await guard(request);
        const access = await resolveMemoryAccess(db, principal.userId, request.params.memoryId, { includeTrashed: true });
        if (access === null || !access.isOwner) {
          throw new NotFoundError('Memory not found.', 'memory.not_found');
        }
        if (access.memory.deletedAt === null) {
          throw new ConflictError('Move the Memory to the trash before deleting it permanently.', 'memory.not_trashed');
        }
        await jobs.enqueue(JOBS.memoryPurge, { memoryId: access.memory.id });
        return reply.status(202).send({ status: 'purging' as const });
      },
    );

    typed.post(
      '/v1/memories/trash/empty',
      { schema: { response: { 202: z.object({ status: z.literal('purging'), count: z.number() }) } } },
      async (request, reply) => {
        const principal = await guard(request);
        const trashed = await db
          .select({ id: memories.id })
          .from(memories)
          .where(and(eq(memories.ownerId, principal.userId), isNotNull(memories.deletedAt)));
        for (const row of trashed) {
          await jobs.enqueue(JOBS.memoryPurge, { memoryId: row.id });
        }
        return reply.status(202).send({ status: 'purging' as const, count: trashed.length });
      },
    );
  };
}
