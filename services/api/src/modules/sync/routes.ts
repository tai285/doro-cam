import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import type { Services } from '../context.ts';
import { listChanges } from './change-log.ts';

const query = z.object({
  cursor: z.coerce.number().int().min(0).default(0),
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

const response = z.object({
  items: z.array(
    z.object({
      seq: z.number(),
      entity: z.enum(['memory', 'asset', 'preset', 'album']),
      entityId: z.string(),
      op: z.enum(['upsert', 'delete']),
      at: z.string(),
    }),
  ),
  nextCursor: z.number(),
  hasMore: z.boolean(),
});

/** Pull-based change feed with tombstones (SYNC-006, docs/specs/api.md). Clients re-fetch entities named in the feed. */
export function syncRoutes(services: Services): FastifyPluginAsync {
  return async (app) => {
    app.withTypeProvider<ZodTypeProvider>().get('/v1/sync/changes', { schema: { querystring: query, response: { 200: response } } }, async (request) => {
      const principal = await services.guard(request);
      return listChanges(services.database.db, principal.userId, request.query.cursor, request.query.limit);
    });
  };
}
