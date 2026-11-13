import { and, asc, eq, isNull, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { presets } from '../../db/schema.ts';
import { ConflictError, NotFoundError } from '../../lib/errors.ts';
import type { Services } from '../context.ts';
import { recordChange } from '../sync/change-log.ts';

const presetBody = z.object({
  name: z.string().trim().min(1).max(80),
  experienceId: z.string().min(1).max(64),
  intent: z.record(z.string(), z.unknown()),
  profile: z.object({ id: z.string().min(1).max(64), version: z.number().int().positive() }).nullable().optional(),
  live: z.boolean().default(false),
  source: z.enum(['user', 'suggested']).default('user'),
});

const presetSchema = z.object({
  id: z.string(),
  name: z.string(),
  experienceId: z.string(),
  intent: z.record(z.string(), z.unknown()),
  profile: z.object({ id: z.string(), version: z.number() }).nullable(),
  live: z.boolean(),
  source: z.enum(['user', 'suggested']),
  version: z.number(),
  createdAt: z.string(),
  updatedAt: z.string(),
});

type PresetRow = typeof presets.$inferSelect;

function toDto(row: PresetRow): z.infer<typeof presetSchema> {
  return {
    id: row.id,
    name: row.name,
    experienceId: row.experienceId,
    intent: row.intent,
    profile: row.profileId === null ? null : { id: row.profileId, version: row.profileVersion ?? 1 },
    live: row.live,
    source: row.source,
    version: row.version,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

/** Preset sync: create, edit, rename and delete custom presets (EXP-006, EXP-007, WEB-008). */
export function presetRoutes(services: Services): FastifyPluginAsync {
  const db = services.database.db;
  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();
    const params = z.object({ presetId: z.uuid() });

    typed.get('/v1/presets', { schema: { response: { 200: z.object({ items: z.array(presetSchema) }) } } }, async (request) => {
      const principal = await services.guard(request);
      const rows = await db
        .select()
        .from(presets)
        .where(and(eq(presets.ownerId, principal.userId), isNull(presets.deletedAt)))
        .orderBy(asc(presets.createdAt), asc(presets.id));
      return { items: rows.map(toDto) };
    });

    typed.put(
      '/v1/presets/:presetId',
      { schema: { params, body: presetBody, response: { 200: presetSchema } } },
      async (request) => {
        const principal = await services.guard(request);
        const body = request.body;
        const existing = (await db.select().from(presets).where(eq(presets.id, request.params.presetId)))[0];
        if (existing !== undefined && existing.ownerId !== principal.userId) {
          throw new ConflictError('A preset with this id already exists.', 'preset.conflict');
        }
        const values = {
          name: body.name,
          experienceId: body.experienceId,
          intent: body.intent,
          profileId: body.profile?.id ?? null,
          profileVersion: body.profile?.version ?? null,
          live: body.live,
          source: body.source,
        };
        const row = await db.transaction(async (tx) => {
          const saved = (
            existing === undefined
              ? await tx.insert(presets).values({ id: request.params.presetId, ownerId: principal.userId, ...values }).returning()
              : await tx
                  .update(presets)
                  .set({ ...values, deletedAt: null, version: sql`${presets.version} + 1`, updatedAt: new Date() })
                  .where(eq(presets.id, request.params.presetId))
                  .returning()
          )[0];
          if (saved === undefined) {
            throw new Error('preset save returned no row');
          }
          await recordChange(tx, { ownerId: principal.userId, entity: 'preset', entityId: saved.id, op: 'upsert' });
          return saved;
        });
        return toDto(row);
      },
    );

    typed.delete('/v1/presets/:presetId', { schema: { params, response: { 204: z.null() } } }, async (request, reply) => {
      const principal = await services.guard(request);
      const existing = (
        await db.select().from(presets).where(and(eq(presets.id, request.params.presetId), eq(presets.ownerId, principal.userId)))
      )[0];
      if (existing === undefined || existing.deletedAt !== null) {
        throw new NotFoundError('Preset not found.', 'preset.not_found');
      }
      await db.transaction(async (tx) => {
        await tx.update(presets).set({ deletedAt: new Date(), updatedAt: new Date() }).where(eq(presets.id, existing.id));
        await recordChange(tx, { ownerId: principal.userId, entity: 'preset', entityId: existing.id, op: 'delete' });
      });
      return reply.status(204).send(null);
    });
  };
}
