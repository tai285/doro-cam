import { verifyPassword } from 'better-auth/crypto';
import { and, eq, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import type { AppConfig } from '../../config/env.ts';
import type { Database } from '../../db/client.ts';
import { session, storageObjects, user, usersProfile } from '../../db/schema.ts';
import { ForbiddenError, NotFoundError } from '../../lib/errors.ts';
import { type Auth, loadCredentialHash } from '../auth/auth.ts';
import type { Guard } from '../auth/plugin.ts';

export const DELETION_GRACE_DAYS = 7;

const meSchema = z.object({
  id: z.string(),
  email: z.string(),
  name: z.string(),
  emailVerified: z.boolean(),
  createdAt: z.string(),
  storage: z.object({ usedBytes: z.number(), quotaBytes: z.number() }),
  deletionRequestedAt: z.string().nullable(),
  deletionScheduledFor: z.string().nullable(),
});

const sessionSchema = z.object({
  id: z.string(),
  current: z.boolean(),
  userAgent: z.string().nullable(),
  ipAddress: z.string().nullable(),
  createdAt: z.string(),
  expiresAt: z.string(),
});

export async function storageUsedBytes(database: Database, ownerId: string): Promise<number> {
  const rows = await database.db
    .select({ total: sql<string>`coalesce(sum(${storageObjects.bytes}), 0)` })
    .from(storageObjects)
    .where(eq(storageObjects.ownerId, ownerId));
  return Number(rows[0]?.total ?? 0);
}

/** Current user, storage usage (WEB-005), device sessions (AUTH-004) and account deletion (PRIV-004, WEB-006). */
export function meRoutes(deps: { auth: Auth; database: Database; guard: Guard; config: AppConfig }): FastifyPluginAsync {
  const { database, guard, config } = deps;
  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.get('/v1/me', { schema: { response: { 200: meSchema } } }, async (request) => {
      const principal = await guard(request);
      const rows = await database.db.select().from(user).where(eq(user.id, principal.userId));
      const me = rows[0];
      if (me === undefined) {
        throw new NotFoundError('Account not found.', 'user.not_found');
      }
      await database.db.insert(usersProfile).values({ userId: me.id }).onConflictDoNothing();
      const profile = (await database.db.select().from(usersProfile).where(eq(usersProfile.userId, me.id)))[0];
      const requested = profile?.deletionRequestedAt ?? null;
      return {
        id: me.id,
        email: me.email,
        name: me.name,
        emailVerified: me.emailVerified,
        createdAt: me.createdAt.toISOString(),
        storage: { usedBytes: await storageUsedBytes(database, me.id), quotaBytes: config.limits.storageQuotaBytes },
        deletionRequestedAt: requested?.toISOString() ?? null,
        deletionScheduledFor:
          requested === null ? null : new Date(requested.getTime() + DELETION_GRACE_DAYS * 86_400_000).toISOString(),
      };
    });

    typed.get('/v1/me/sessions', { schema: { response: { 200: z.object({ items: z.array(sessionSchema) }) } } }, async (request) => {
      const principal = await guard(request);
      const rows = await database.db.select().from(session).where(eq(session.userId, principal.userId));
      const now = Date.now();
      return {
        items: rows
          .filter((row) => row.expiresAt.getTime() > now)
          .map((row) => ({
            id: row.id,
            current: row.id === principal.sessionId,
            userAgent: row.userAgent,
            ipAddress: row.ipAddress,
            createdAt: row.createdAt.toISOString(),
            expiresAt: row.expiresAt.toISOString(),
          })),
      };
    });

    typed.delete(
      '/v1/me/sessions/:sessionId',
      { schema: { params: z.object({ sessionId: z.uuid() }), response: { 204: z.null() } } },
      async (request, reply) => {
        const principal = await guard(request);
        const removed = await database.db
          .delete(session)
          .where(and(eq(session.id, request.params.sessionId), eq(session.userId, principal.userId)))
          .returning({ id: session.id });
        if (removed.length === 0) {
          throw new NotFoundError('Session not found.', 'session.not_found');
        }
        return reply.status(204).send(null);
      },
    );

    typed.post(
      '/v1/me/deletion',
      {
        schema: {
          body: z.object({ password: z.string().min(1).max(128) }),
          response: { 200: z.object({ scheduledFor: z.string() }) },
        },
      },
      async (request) => {
        const principal = await guard(request);
        // Re-authentication is required before scheduling deletion (docs/architecture/security.md).
        const hash = await loadCredentialHash(database, principal.userId);
        if (hash === null || !(await verifyPassword({ hash, password: request.body.password }))) {
          throw new ForbiddenError('The password is incorrect.', 'auth.reauthentication_failed');
        }
        const now = new Date();
        await database.db
          .insert(usersProfile)
          .values({ userId: principal.userId, deletionRequestedAt: now })
          .onConflictDoUpdate({ target: usersProfile.userId, set: { deletionRequestedAt: now } });
        return { scheduledFor: new Date(now.getTime() + DELETION_GRACE_DAYS * 86_400_000).toISOString() };
      },
    );

    typed.delete('/v1/me/deletion', { schema: { response: { 204: z.null() } } }, async (request, reply) => {
      const principal = await guard(request);
      await database.db
        .update(usersProfile)
        .set({ deletionRequestedAt: null })
        .where(eq(usersProfile.userId, principal.userId));
      return reply.status(204).send(null);
    });
  };
}
