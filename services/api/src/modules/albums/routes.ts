import { and, asc, desc, eq, inArray, isNull, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { albumInvites, albumItems, albumMembers, albums, memories, user } from '../../db/schema.ts';
import { AppError, BadRequestError, ConflictError, ForbiddenError, NotFoundError } from '../../lib/errors.ts';
import { newToken, sha256Hex } from '../../lib/ids.ts';
import type { Services } from '../context.ts';
import { resolveMemoryAccess } from '../memories/access.ts';
import { memorySchema } from '../memories/schemas.ts';
import { loadAssets, loadKeys, serializeMemory } from '../memories/serialize.ts';
import { type AlbumAction, type AlbumRole, can } from './permissions.ts';

const albumParams = z.object({ albumId: z.uuid() });
const roleSchema = z.enum(['owner', 'editor', 'contributor', 'viewer']);
const inviteRoleSchema = z.enum(['editor', 'contributor', 'viewer']);
const dateString = z.iso.date();

const albumSettings = z.object({
  title: z.string().trim().min(1).max(120),
  description: z.string().max(2000).nullable().optional(),
  kind: z.enum(['album', 'trip']).default('album'),
  startsOn: dateString.nullable().optional(),
  endsOn: dateString.nullable().optional(),
  allowOriginalDownload: z.boolean().optional(),
  shareLocation: z.boolean().optional(),
  autoAddDuringTrip: z.boolean().optional(),
});

const albumSchema = z.object({
  id: z.string(),
  ownerId: z.string(),
  kind: z.enum(['album', 'trip']),
  title: z.string(),
  description: z.string().nullable(),
  startsOn: z.string().nullable(),
  endsOn: z.string().nullable(),
  coverMemoryId: z.string().nullable(),
  allowOriginalDownload: z.boolean(),
  shareLocation: z.boolean(),
  autoAddDuringTrip: z.boolean(),
  role: roleSchema,
  memberCount: z.number(),
  itemCount: z.number(),
  createdAt: z.string(),
  updatedAt: z.string(),
});

const memberSchema = z.object({
  userId: z.string(),
  name: z.string(),
  role: roleSchema,
  joinedAt: z.string(),
});

type AlbumRow = typeof albums.$inferSelect;

class InviteError extends AppError {}

function checkTripDates(kind: string, startsOn: string | null | undefined, endsOn: string | null | undefined): void {
  if (kind === 'trip' && (startsOn === null || startsOn === undefined || endsOn === null || endsOn === undefined)) {
    throw new BadRequestError('A trip needs a start and end date.', undefined, 'album.trip_dates_required');
  }
  if (startsOn !== null && startsOn !== undefined && endsOn !== null && endsOn !== undefined && endsOn < startsOn) {
    throw new BadRequestError('The end date is before the start date.', undefined, 'album.invalid_dates');
  }
}

/** Albums, trips, members, invites and shared items (SHR-001..SHR-007, WEB-007). */
export function albumRoutes(services: Services): FastifyPluginAsync {
  const { database, storage, guard, mailer, config } = services;
  const db = database.db;

  /** Loads the album and the caller's role, or throws 404 (non-members cannot tell an album exists). */
  const loadMembership = async (userId: string, albumId: string, action: AlbumAction = 'view') => {
    const row = (
      await db
        .select({ album: albums, role: albumMembers.role })
        .from(albums)
        .innerJoin(albumMembers, and(eq(albumMembers.albumId, albums.id), eq(albumMembers.userId, userId)))
        .where(and(eq(albums.id, albumId), isNull(albums.deletedAt)))
    )[0];
    /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
    if (row === undefined) {
      throw new NotFoundError('Album not found.', 'album.not_found');
    }
    if (!can(row.role, action)) {
      throw new ForbiddenError('Your role does not allow that.', 'album.forbidden');
    }
    return row;
  };

  const toDto = async (album: AlbumRow, role: AlbumRole) => {
    const members = (await db.select({ n: sql<string>`count(*)` }).from(albumMembers).where(eq(albumMembers.albumId, album.id)))[0];
    const items = (await db.select({ n: sql<string>`count(*)` }).from(albumItems).where(eq(albumItems.albumId, album.id)))[0];
    return {
      id: album.id,
      ownerId: album.ownerId,
      kind: album.kind,
      title: album.title,
      description: album.description,
      startsOn: album.startsOn,
      endsOn: album.endsOn,
      coverMemoryId: album.coverMemoryId,
      allowOriginalDownload: album.allowOriginalDownload,
      shareLocation: album.shareLocation,
      autoAddDuringTrip: album.autoAddDuringTrip,
      role,
      memberCount: Number(members?.n ?? 0),
      itemCount: Number(items?.n ?? 0),
      createdAt: album.createdAt.toISOString(),
      updatedAt: album.updatedAt.toISOString(),
    };
  };

  return async (app) => {
    const typed = app.withTypeProvider<ZodTypeProvider>();

    typed.post('/v1/albums', { schema: { body: albumSettings, response: { 201: albumSchema } } }, async (request, reply) => {
      const principal = await guard(request);
      const body = request.body;
      checkTripDates(body.kind, body.startsOn, body.endsOn);
      const album = await db.transaction(async (tx) => {
        const created = (
          await tx
            .insert(albums)
            .values({
              ownerId: principal.userId,
              kind: body.kind,
              title: body.title,
              description: body.description ?? null,
              startsOn: body.startsOn ?? null,
              endsOn: body.endsOn ?? null,
              allowOriginalDownload: body.allowOriginalDownload ?? true,
              shareLocation: body.shareLocation ?? false,
              autoAddDuringTrip: body.autoAddDuringTrip ?? false,
            })
            .returning()
        )[0];
        /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
        if (created === undefined) {
          throw new Error('album insert returned no row');
        }
        await tx.insert(albumMembers).values({ albumId: created.id, userId: principal.userId, role: 'owner', invitedBy: null });
        return created;
      });
      return reply.status(201).send(await toDto(album, 'owner'));
    });

    typed.get('/v1/albums', { schema: { response: { 200: z.object({ items: z.array(albumSchema) }) } } }, async (request) => {
      const principal = await guard(request);
      const rows = await db
        .select({ album: albums, role: albumMembers.role })
        .from(albums)
        .innerJoin(albumMembers, and(eq(albumMembers.albumId, albums.id), eq(albumMembers.userId, principal.userId)))
        .where(isNull(albums.deletedAt))
        .orderBy(desc(albums.updatedAt), desc(albums.id));
      return { items: await Promise.all(rows.map((row) => toDto(row.album, row.role))) };
    });

    typed.get(
      '/v1/albums/:albumId',
      {
        schema: {
          params: albumParams,
          response: { 200: z.object({ album: albumSchema, members: z.array(memberSchema) }) },
        },
      },
      async (request) => {
        const principal = await guard(request);
        const { album, role } = await loadMembership(principal.userId, request.params.albumId);
        const members = await db
          .select({ userId: albumMembers.userId, name: user.name, role: albumMembers.role, joinedAt: albumMembers.joinedAt })
          .from(albumMembers)
          .innerJoin(user, eq(user.id, albumMembers.userId))
          .where(eq(albumMembers.albumId, album.id))
          .orderBy(asc(albumMembers.joinedAt));
        return {
          album: await toDto(album, role),
          members: members.map((member) => ({ ...member, joinedAt: member.joinedAt.toISOString() })),
        };
      },
    );

    typed.patch(
      '/v1/albums/:albumId',
      { schema: { params: albumParams, body: albumSettings.partial(), response: { 200: albumSchema } } },
      async (request) => {
        const principal = await guard(request);
        const { album, role } = await loadMembership(principal.userId, request.params.albumId, 'edit_album');
        const body = request.body;
        const kind = body.kind ?? album.kind;
        const startsOn = body.startsOn === undefined ? album.startsOn : body.startsOn;
        const endsOn = body.endsOn === undefined ? album.endsOn : body.endsOn;
        checkTripDates(kind, startsOn, endsOn);
        const updated = (
          await db
            .update(albums)
            .set({
              ...(body.title === undefined ? {} : { title: body.title }),
              ...(body.description === undefined ? {} : { description: body.description }),
              kind,
              startsOn,
              endsOn,
              ...(body.allowOriginalDownload === undefined ? {} : { allowOriginalDownload: body.allowOriginalDownload }),
              ...(body.shareLocation === undefined ? {} : { shareLocation: body.shareLocation }),
              ...(body.autoAddDuringTrip === undefined ? {} : { autoAddDuringTrip: body.autoAddDuringTrip }),
              updatedAt: new Date(),
            })
            .where(eq(albums.id, album.id))
            .returning()
        )[0];
        /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
        if (updated === undefined) {
          throw new NotFoundError('Album not found.', 'album.not_found');
        }
        return toDto(updated, role);
      },
    );

    typed.delete('/v1/albums/:albumId', { schema: { params: albumParams, response: { 204: z.null() } } }, async (request, reply) => {
      const principal = await guard(request);
      const { album } = await loadMembership(principal.userId, request.params.albumId, 'delete_album');
      await db.update(albums).set({ deletedAt: new Date(), updatedAt: new Date() }).where(eq(albums.id, album.id));
      return reply.status(204).send(null);
    });

    // ---- items --------------------------------------------------------------------------------

    typed.get(
      '/v1/albums/:albumId/memories',
      { schema: { params: albumParams, response: { 200: z.object({ items: z.array(memorySchema) }) } } },
      async (request) => {
        const principal = await guard(request);
        const { album } = await loadMembership(principal.userId, request.params.albumId);
        const rows = await db
          .select({ memoryId: albumItems.memoryId })
          .from(albumItems)
          .innerJoin(memories, eq(memories.id, albumItems.memoryId))
          .where(and(eq(albumItems.albumId, album.id), isNull(memories.deletedAt)))
          .orderBy(desc(memories.capturedAt), desc(memories.id));
        const items = [];
        for (const row of rows) {
          const access = await resolveMemoryAccess(db, principal.userId, row.memoryId);
          if (access === null) {
            continue;
          }
          const memoryAssets = (await loadAssets(db, [row.memoryId])).get(row.memoryId) ?? [];
          items.push(await serializeMemory(db, storage, access, access.memory, memoryAssets, await loadKeys(db, memoryAssets)));
        }
        return { items };
      },
    );

    typed.post(
      '/v1/albums/:albumId/items',
      {
        schema: {
          params: albumParams,
          body: z.object({ memoryIds: z.array(z.uuid()).min(1).max(100) }),
          response: { 200: z.object({ added: z.number() }) },
        },
      },
      async (request) => {
        const principal = await guard(request);
        const { album } = await loadMembership(principal.userId, request.params.albumId, 'add_own_memories');
        const owned = await db
          .select({ id: memories.id })
          .from(memories)
          .where(and(inArray(memories.id, request.body.memoryIds), eq(memories.ownerId, principal.userId), isNull(memories.deletedAt)));
        // Members may add only Memories they own (sharing.md rule 4); anything else is reported as missing.
        if (owned.length !== new Set(request.body.memoryIds).size) {
          throw new NotFoundError('One or more Memories were not found.', 'memory.not_found');
        }
        const inserted = await db
          .insert(albumItems)
          .values(owned.map((row) => ({ albumId: album.id, memoryId: row.id, addedBy: principal.userId })))
          .onConflictDoNothing()
          .returning({ memoryId: albumItems.memoryId });
        await db.update(albums).set({ updatedAt: new Date() }).where(eq(albums.id, album.id));
        return { added: inserted.length };
      },
    );

    typed.delete(
      '/v1/albums/:albumId/items/:memoryId',
      { schema: { params: albumParams.extend({ memoryId: z.uuid() }), response: { 204: z.null() } } },
      async (request, reply) => {
        const principal = await guard(request);
        const { album, role } = await loadMembership(principal.userId, request.params.albumId, 'remove_own_memories');
        const item = (
          await db
            .select()
            .from(albumItems)
            .where(and(eq(albumItems.albumId, album.id), eq(albumItems.memoryId, request.params.memoryId)))
        )[0];
        if (item === undefined) {
          throw new NotFoundError('That Memory is not in this album.', 'memory.not_found');
        }
        const memory = (await db.select({ ownerId: memories.ownerId }).from(memories).where(eq(memories.id, item.memoryId)))[0];
        if (memory?.ownerId !== principal.userId && !can(role, 'remove_others_memories')) {
          throw new ForbiddenError('Your role does not allow removing other people’s Memories.', 'album.forbidden');
        }
        await db.delete(albumItems).where(and(eq(albumItems.albumId, album.id), eq(albumItems.memoryId, item.memoryId)));
        return reply.status(204).send(null);
      },
    );

    /** Trip auto-add never adds silently: it lists the caller's own Memories shot during the trip for confirmation. */
    typed.get(
      '/v1/albums/:albumId/trip-proposals',
      { schema: { params: albumParams, response: { 200: z.object({ memoryIds: z.array(z.string()) }) } } },
      async (request) => {
        const principal = await guard(request);
        const { album } = await loadMembership(principal.userId, request.params.albumId, 'add_own_memories');
        if (album.kind !== 'trip' || !album.autoAddDuringTrip || album.startsOn === null || album.endsOn === null) {
          return { memoryIds: [] };
        }
        const rows = await db
          .select({ id: memories.id })
          .from(memories)
          .where(
            and(
              eq(memories.ownerId, principal.userId),
              isNull(memories.deletedAt),
              sql`((${memories.capturedAt} at time zone ${memories.capturedTz})::date) between ${album.startsOn}::date and ${album.endsOn}::date`,
              sql`not exists (select 1 from ${albumItems} where ${albumItems.albumId} = ${album.id} and ${albumItems.memoryId} = ${memories.id})`,
            ),
          )
          .orderBy(asc(memories.capturedAt));
        return { memoryIds: rows.map((row) => row.id) };
      },
    );

    // ---- members & invites -------------------------------------------------------------------

    typed.post(
      '/v1/albums/:albumId/invites',
      {
        schema: {
          params: albumParams,
          body: z.object({
            role: inviteRoleSchema,
            expiresInDays: z.number().int().min(1).max(60).default(14),
            maxUses: z.number().int().min(1).max(100).default(1),
            email: z.email().optional(),
          }),
          response: { 201: z.object({ id: z.string(), token: z.string(), role: inviteRoleSchema, expiresAt: z.string(), maxUses: z.number() }) },
        },
      },
      async (request, reply) => {
        const principal = await guard(request);
        const { album } = await loadMembership(principal.userId, request.params.albumId, 'manage_members');
        const token = newToken();
        const expiresAt = new Date(Date.now() + request.body.expiresInDays * 86_400_000);
        const invite = (
          await db
            .insert(albumInvites)
            .values({
              albumId: album.id,
              role: request.body.role,
              tokenHash: sha256Hex(token),
              createdBy: principal.userId,
              expiresAt,
              maxUses: request.body.maxUses,
            })
            .returning()
        )[0];
        /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
        if (invite === undefined) {
          throw new Error('invite insert returned no row');
        }
        if (request.body.email !== undefined) {
          const link = `${config.auth.webOrigins[0] ?? config.auth.baseUrl}/invites/${token}`;
          await mailer.send({
            kind: 'album_invite',
            to: request.body.email,
            subject: `You're invited to “${album.title}” on Doro Cam`,
            text: `Join the album: ${link}`,
            link,
          });
        }
        // The token is returned exactly once; only its hash is stored (sharing.md rule 8).
        return reply.status(201).send({ id: invite.id, token, role: request.body.role, expiresAt: expiresAt.toISOString(), maxUses: invite.maxUses });
      },
    );

    typed.delete(
      '/v1/albums/:albumId/invites/:inviteId',
      { schema: { params: albumParams.extend({ inviteId: z.uuid() }), response: { 204: z.null() } } },
      async (request, reply) => {
        const principal = await guard(request);
        const { album } = await loadMembership(principal.userId, request.params.albumId, 'manage_members');
        await db
          .update(albumInvites)
          .set({ revokedAt: new Date() })
          .where(and(eq(albumInvites.id, request.params.inviteId), eq(albumInvites.albumId, album.id)));
        return reply.status(204).send(null);
      },
    );

    typed.post(
      '/v1/invites/accept',
      {
        schema: {
          body: z.object({ token: z.string().min(20).max(200) }),
          response: { 200: z.object({ albumId: z.string(), role: roleSchema }) },
        },
      },
      async (request) => {
        const principal = await guard(request);
        const invite = (await db.select().from(albumInvites).where(eq(albumInvites.tokenHash, sha256Hex(request.body.token))))[0];
        if (invite === undefined) {
          throw new NotFoundError('Invite not found.', 'invite.not_found');
        }
        if (invite.revokedAt !== null) {
          throw new InviteError(410, 'invite.revoked', 'This invite was revoked.');
        }
        if (invite.expiresAt.getTime() < Date.now()) {
          throw new InviteError(410, 'invite.expired', 'This invite has expired.');
        }
        const album = (await db.select().from(albums).where(and(eq(albums.id, invite.albumId), isNull(albums.deletedAt))))[0];
        /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
        if (album === undefined) {
          throw new NotFoundError('Album not found.', 'album.not_found');
        }
        const existing = (
          await db
            .select()
            .from(albumMembers)
            .where(and(eq(albumMembers.albumId, album.id), eq(albumMembers.userId, principal.userId)))
        )[0];
        if (existing !== undefined) {
          return { albumId: album.id, role: existing.role }; // already a member: accepting again is harmless and does not consume the invite
        }
        if (invite.uses >= invite.maxUses) {
          throw new InviteError(410, 'invite.exhausted', 'This invite has been used up.');
        }
        // The use is claimed atomically so two simultaneous accepts cannot exceed maxUses.
        const claimed = await db
          .update(albumInvites)
          .set({ uses: sql`${albumInvites.uses} + 1` })
          .where(and(eq(albumInvites.id, invite.id), sql`${albumInvites.uses} < ${albumInvites.maxUses}`))
          .returning({ id: albumInvites.id });
        if (claimed.length === 0) {
          throw new InviteError(410, 'invite.exhausted', 'This invite has been used up.');
        }
        await db.insert(albumMembers).values({ albumId: album.id, userId: principal.userId, role: invite.role, invitedBy: invite.createdBy });
        return { albumId: album.id, role: invite.role };
      },
    );

    typed.patch(
      '/v1/albums/:albumId/members/:userId',
      {
        schema: {
          params: albumParams.extend({ userId: z.uuid() }),
          body: z.object({ role: inviteRoleSchema }),
          response: { 200: memberSchema },
        },
      },
      async (request) => {
        const principal = await guard(request);
        const { album } = await loadMembership(principal.userId, request.params.albumId, 'manage_members');
        if (request.params.userId === album.ownerId) {
          throw new ConflictError('The owner’s role cannot be changed.', 'album.owner_cannot_leave');
        }
        const updated = (
          await db
            .update(albumMembers)
            .set({ role: request.body.role })
            .where(and(eq(albumMembers.albumId, album.id), eq(albumMembers.userId, request.params.userId)))
            .returning()
        )[0];
        /* v8 ignore next 3 -- defensive: concurrent delete between the statements */
        if (updated === undefined) {
          throw new NotFoundError('Member not found.', 'member.not_found');
        }
        const member = (await db.select({ name: user.name }).from(user).where(eq(user.id, updated.userId)))[0];
        return { userId: updated.userId, name: member?.name ?? '', role: updated.role, joinedAt: updated.joinedAt.toISOString() };
      },
    );

    /** A member may leave; the owner may remove others (SHR-007). The owner cannot leave. */
    typed.delete(
      '/v1/albums/:albumId/members/:userId',
      { schema: { params: albumParams.extend({ userId: z.uuid() }), response: { 204: z.null() } } },
      async (request, reply) => {
        const principal = await guard(request);
        const { album, role } = await loadMembership(principal.userId, request.params.albumId);
        const leaving = request.params.userId === principal.userId;
        if (request.params.userId === album.ownerId) {
          throw new ConflictError('The owner cannot leave their own album.', 'album.owner_cannot_leave');
        }
        if (!leaving && !can(role, 'manage_members')) {
          throw new ForbiddenError('Your role does not allow removing members.', 'album.forbidden');
        }
        const removed = await db
          .delete(albumMembers)
          .where(and(eq(albumMembers.albumId, album.id), eq(albumMembers.userId, request.params.userId)))
          .returning({ userId: albumMembers.userId });
        if (removed.length === 0) {
          throw new NotFoundError('Member not found.', 'member.not_found');
        }
        return reply.status(204).send(null);
      },
    );
  };
}
