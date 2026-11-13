import { and, desc, eq, inArray } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { dataExports } from '../../db/schema.ts';
import { ConflictError, NotFoundError } from '../../lib/errors.ts';
import { presignGet } from '../../lib/presign.ts';
import { JOBS } from '../../lib/queue.ts';
import type { Services } from '../context.ts';

/** Exports are kept for a week; the archive object is removed afterwards by the sweep. */
export const EXPORT_RETENTION_DAYS = 7;

const exportSchema = z.object({
  id: z.string(),
  status: z.enum(['pending', 'building', 'ready', 'failed']),
  bytes: z.number().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  expiresAt: z.string(),
  failureReason: z.string().nullable(),
  download: z.object({ url: z.string(), expiresAt: z.string(), filename: z.string() }).nullable(),
});

type Row = typeof dataExports.$inferSelect;

/** Data export: request an archive, poll it, download it (WEB-010, PRIV-006). */
export function exportRoutes(services: Services): FastifyPluginAsync {
  const db = services.database.db;
  const present = async (row: Row): Promise<z.infer<typeof exportSchema>> => {
    const live = row.status === 'ready' && row.objectKey !== null && row.expiresAt.getTime() > Date.now();
    const signed = live ? await presignGet(services.storage, row.objectKey as string, { filename: `doro-cam-export-${row.createdAt.toISOString().slice(0, 10)}.zip`, contentType: 'application/zip' }) : null;
    return {
      id: row.id,
      status: row.status,
      bytes: row.bytes,
      createdAt: row.createdAt.toISOString(),
      completedAt: row.completedAt?.toISOString() ?? null,
      expiresAt: row.expiresAt.toISOString(),
      failureReason: row.failureReason,
      download: signed === null ? null : { url: signed.url, expiresAt: signed.expiresAt, filename: `doro-cam-export-${row.createdAt.toISOString().slice(0, 10)}.zip` },
    };
  };

  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.post('/v1/me/exports', { schema: { response: { 202: exportSchema } } }, async (request, reply) => {
      const principal = await services.guard(request);
      const active = await db
        .select({ id: dataExports.id })
        .from(dataExports)
        .where(and(eq(dataExports.ownerId, principal.userId), inArray(dataExports.status, ['pending', 'building'])));
      if (active.length > 0) {
        throw new ConflictError('An export is already being prepared.', 'export.in_progress');
      }
      const created = (
        await db
          .insert(dataExports)
          .values({ ownerId: principal.userId, expiresAt: new Date(Date.now() + EXPORT_RETENTION_DAYS * 86_400_000) })
          .returning()
      )[0] as Row;
      await services.jobs.enqueue(JOBS.exportBuild, { exportId: created.id });
      const fresh = (await db.select().from(dataExports).where(eq(dataExports.id, created.id)))[0] as Row;
      return reply.status(202).send(await present(fresh));
    });

    typed.get('/v1/me/exports', { schema: { response: { 200: z.object({ items: z.array(exportSchema) }) } } }, async (request) => {
      const principal = await services.guard(request);
      const rows = await db.select().from(dataExports).where(eq(dataExports.ownerId, principal.userId)).orderBy(desc(dataExports.createdAt)).limit(10);
      return { items: await Promise.all(rows.map(present)) };
    });

    typed.get(
      '/v1/me/exports/:exportId',
      { schema: { params: z.object({ exportId: z.uuid() }), response: { 200: exportSchema } } },
      async (request) => {
        const principal = await services.guard(request);
        const row = (await db.select().from(dataExports).where(and(eq(dataExports.id, request.params.exportId), eq(dataExports.ownerId, principal.userId))))[0];
        if (row === undefined) {
          throw new NotFoundError('Export not found.', 'export.not_found');
        }
        return present(row);
      },
    );
  };
}
