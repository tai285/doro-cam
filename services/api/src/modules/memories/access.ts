import { and, eq, isNull } from 'drizzle-orm';
import type { Executor } from '../../lib/db-types.ts';
import { albumItems, albumMembers, albums, memories } from '../../db/schema.ts';

export type MemoryRow = typeof memories.$inferSelect;
export type AccessRole = 'owner' | 'editor' | 'contributor' | 'viewer';

export interface MemoryAccess {
  memory: MemoryRow;
  role: AccessRole;
  isOwner: boolean;
  /** Whether this caller may see the Memory's location (PRIV-002, SHR-006). */
  canSeeLocation: boolean;
  /** Whether this caller may download the unmodified original (SHR-005). */
  canDownloadOriginal: boolean;
}

const RANK: Record<AccessRole, number> = { owner: 3, editor: 2, contributor: 1, viewer: 0 };

/**
 * The single place that decides whether a user may reach a Memory. The owner always can. Anyone else
 * needs membership of a live album that contains it, and a trashed Memory is invisible to them (invariant 6).
 * Returns null for "no access" and for "does not exist" alike, so callers answer 404 and never reveal which.
 */
export async function resolveMemoryAccess(
  executor: Executor,
  userId: string,
  memoryId: string,
  options: { includeTrashed?: boolean } = {},
): Promise<MemoryAccess | null> {
  const memory = (await executor.select().from(memories).where(eq(memories.id, memoryId)))[0];
  if (memory === undefined) {
    return null;
  }
  if (memory.ownerId === userId) {
    if (memory.deletedAt !== null && options.includeTrashed !== true) {
      return null;
    }
    return { memory, role: 'owner', isOwner: true, canSeeLocation: true, canDownloadOriginal: true };
  }
  if (memory.deletedAt !== null) {
    return null;
  }
  const memberships = await executor
    .select({
      role: albumMembers.role,
      shareLocation: albums.shareLocation,
      allowOriginalDownload: albums.allowOriginalDownload,
    })
    .from(albumItems)
    .innerJoin(albums, and(eq(albums.id, albumItems.albumId), isNull(albums.deletedAt)))
    .innerJoin(albumMembers, and(eq(albumMembers.albumId, albumItems.albumId), eq(albumMembers.userId, userId)))
    .where(eq(albumItems.memoryId, memoryId));
  if (memberships.length === 0) {
    return null;
  }
  const best = memberships.reduce((a, b) => (RANK[a.role] >= RANK[b.role] ? a : b));
  return {
    memory,
    role: best.role,
    isOwner: false,
    canSeeLocation: memberships.some((m) => m.shareLocation) && memory.locationShared,
    canDownloadOriginal: memberships.some((m) => m.allowOriginalDownload),
  };
}
