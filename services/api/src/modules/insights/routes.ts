import { randomUUID } from 'node:crypto';
import { and, eq, gte, inArray, isNull, lte, type SQL } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { albumItems, memories, presets, presetSuggestionDismissals } from '../../db/schema.ts';
import { NotFoundError } from '../../lib/errors.ts';
import { albumMembers } from '../../db/schema.ts';
import type { Services } from '../context.ts';
import { recordChange } from '../sync/change-log.ts';
import { computeInsights, findPresetSuggestions, type InsightRow } from './compute.ts';

const bucketSchema = z.object({ label: z.string(), count: z.number(), share: z.number() });
const distributionSchema = z.object({ total: z.number(), buckets: z.array(bucketSchema) });

const reportSchema = z.object({
  total: z.number(),
  focalLength: distributionSchema,
  lens: distributionSchema,
  profile: distributionSchema,
  experience: distributionSchema,
  iso: distributionSchema,
  shutter: distributionSchema,
  aperture: distributionSchema,
  timeOfDay: distributionSchema,
  trend: z.array(z.object({ month: z.string(), count: z.number() })),
  insights: z.array(z.object({ id: z.string(), text: z.string(), basedOn: z.record(z.string(), z.union([z.number(), z.string()])) })),
});

const suggestionSchema = z.object({
  patternKey: z.string(),
  title: z.string(),
  explanation: z.string(),
  experienceId: z.string(),
  profileId: z.string().nullable(),
  scenario: z.string().nullable(),
  lensKind: z.string().nullable(),
  isoRange: z.string().nullable(),
  shutterRange: z.string().nullable(),
  supportingCount: z.number(),
  of: z.number(),
  share: z.number(),
});

/** Photography statistics and preset suggestions, always for the caller's own Memories only (ANL-*, PRE-*, WEB-009). */
export function insightsRoutes(services: Services): FastifyPluginAsync {
  const db = services.database.db;

  const loadRows = async (userId: string, filters: SQL[]): Promise<InsightRow[]> =>
    db
      .select({
        capturedAt: memories.capturedAt,
        capturedTz: memories.capturedTz,
        experienceId: memories.experienceId,
        profileId: memories.profileId,
        scenario: memories.scenario,
        lensKind: memories.lensKind,
        focalLength35mm: memories.focalLength35mm,
        iso: memories.iso,
        exposureTimeNs: memories.exposureTimeNs,
        aperture: memories.aperture,
      })
      .from(memories)
      .where(and(eq(memories.ownerId, userId), isNull(memories.deletedAt), ...filters));

  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.get(
      '/v1/insights/summary',
      {
        schema: {
          querystring: z.object({
            from: z.iso.datetime({ offset: true }).optional(),
            to: z.iso.datetime({ offset: true }).optional(),
            albumId: z.uuid().optional(),
            experienceId: z.string().max(64).optional(),
          }),
          response: { 200: reportSchema },
        },
      },
      async (request) => {
        const principal = await services.guard(request);
        const { from, to, albumId, experienceId } = request.query;
        const filters: SQL[] = [];
        if (from !== undefined) filters.push(gte(memories.capturedAt, new Date(from)));
        if (to !== undefined) filters.push(lte(memories.capturedAt, new Date(to)));
        if (experienceId !== undefined) filters.push(eq(memories.experienceId, experienceId));
        if (albumId !== undefined) {
          const member = (
            await db.select().from(albumMembers).where(and(eq(albumMembers.albumId, albumId), eq(albumMembers.userId, principal.userId)))
          )[0];
          if (member === undefined) {
            throw new NotFoundError('Album not found.', 'album.not_found');
          }
          const inAlbum = (await db.select({ id: albumItems.memoryId }).from(albumItems).where(eq(albumItems.albumId, albumId))).map((r) => r.id);
          if (inAlbum.length === 0) {
            return computeInsights([]);
          }
          filters.push(inArray(memories.id, inAlbum));
        }
        return computeInsights(await loadRows(principal.userId, filters));
      },
    );

    const suggestionsFor = async (userId: string) => {
      const dismissed = new Set(
        (await db.select({ key: presetSuggestionDismissals.patternKey }).from(presetSuggestionDismissals).where(eq(presetSuggestionDismissals.ownerId, userId))).map((r) => r.key),
      );
      return findPresetSuggestions(await loadRows(userId, []), dismissed);
    };

    typed.get(
      '/v1/insights/preset-suggestions',
      { schema: { response: { 200: z.object({ items: z.array(suggestionSchema) }) } } },
      async (request) => {
        const principal = await services.guard(request);
        return { items: await suggestionsFor(principal.userId) };
      },
    );

    const keyParams = z.object({ patternKey: z.string().regex(/^[0-9a-f]{24}$/) });

    typed.post(
      '/v1/insights/preset-suggestions/:patternKey/dismiss',
      { schema: { params: keyParams, response: { 204: z.null() } } },
      async (request, reply) => {
        const principal = await services.guard(request);
        await db
          .insert(presetSuggestionDismissals)
          .values({ ownerId: principal.userId, patternKey: request.params.patternKey })
          .onConflictDoNothing();
        return reply.status(204).send(null);
      },
    );

    /** Accepting turns a suggestion into a normal preset the user can still edit (PRE-003). */
    typed.post(
      '/v1/insights/preset-suggestions/:patternKey/accept',
      {
        schema: {
          params: keyParams,
          body: z.object({ name: z.string().trim().min(1).max(80).optional() }),
          response: { 201: z.object({ presetId: z.string() }) },
        },
      },
      async (request, reply) => {
        const principal = await services.guard(request);
        const suggestion = (await suggestionsFor(principal.userId)).find((s) => s.patternKey === request.params.patternKey);
        if (suggestion === undefined) {
          throw new NotFoundError('Suggestion not found.', 'suggestion.not_found');
        }
        const id = randomUUID();
        await db.transaction(async (tx) => {
          await tx.insert(presets).values({
            id,
            ownerId: principal.userId,
            name: request.body.name ?? suggestion.title,
            experienceId: suggestion.experienceId,
            intent: {
              ...(suggestion.scenario === null ? {} : { scenario: suggestion.scenario }),
              ...(suggestion.lensKind === null ? {} : { lensKind: suggestion.lensKind }),
            },
            profileId: suggestion.profileId,
            profileVersion: suggestion.profileId === null ? null : 1,
            source: 'suggested',
          });
          await recordChange(tx, { ownerId: principal.userId, entity: 'preset', entityId: id, op: 'upsert' });
          await tx
            .insert(presetSuggestionDismissals)
            .values({ ownerId: principal.userId, patternKey: suggestion.patternKey })
            .onConflictDoNothing();
        });
        return reply.status(201).send({ presetId: id });
      },
    );
  };
}
