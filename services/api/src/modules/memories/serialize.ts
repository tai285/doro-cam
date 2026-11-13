import { inArray } from 'drizzle-orm';
import type { Executor } from '../../lib/db-types.ts';
import { presignGet } from '../../lib/presign.ts';
import type { Storage } from '../../lib/storage.ts';
import { assets, storageObjects } from '../../db/schema.ts';
import type { MemoryAccess, MemoryRow } from './access.ts';
import type { MemoryDto } from './schemas.ts';

export type AssetRow = typeof assets.$inferSelect;

export function assetKey(ownerId: string, memoryId: string, assetId: string, role: string): string {
  return `o/${ownerId}/${memoryId}/${assetId}/${role}`;
}

/** Assets the owner may use for display; nobody sees an asset before it is verified (upload-sync invariant 2). */
export function isServable(asset: Pick<AssetRow, 'status'>): boolean {
  return asset.status === 'verified' || asset.status === 'ready';
}

export async function loadAssets(executor: Executor, memoryIds: readonly string[]): Promise<Map<string, AssetRow[]>> {
  const byMemory = new Map<string, AssetRow[]>();
  if (memoryIds.length === 0) {
    return byMemory;
  }
  const rows = await executor.select().from(assets).where(inArray(assets.memoryId, [...memoryIds]));
  for (const row of rows) {
    byMemory.set(row.memoryId, [...(byMemory.get(row.memoryId) ?? []), row]);
  }
  return byMemory;
}

/** Object keys for assets that have a stored object (deduplicated assets share their source's key). */
export async function loadKeys(executor: Executor, rows: readonly AssetRow[]): Promise<Map<string, string>> {
  const objectIds = rows.flatMap((row) => (row.storageObjectId === null ? [] : [row.storageObjectId]));
  const keys = new Map<string, string>();
  if (objectIds.length === 0) {
    return keys;
  }
  const objects = await executor.select().from(storageObjects).where(inArray(storageObjects.id, objectIds));
  const byId = new Map(objects.map((object) => [object.id, object.key]));
  for (const row of rows) {
    const key = row.storageObjectId === null ? undefined : byId.get(row.storageObjectId);
    if (key !== undefined) {
      keys.set(row.id, key);
    }
  }
  return keys;
}

function pickMedia(rows: readonly AssetRow[], ...roles: string[]): AssetRow | undefined {
  for (const role of roles) {
    const match = rows.find((row) => row.role === role && isServable(row));
    if (match !== undefined) {
      return match;
    }
  }
  return undefined;
}

/**
 * Builds the API shape of a Memory for one caller. Location is omitted unless the caller may see it
 * (PRIV-002); for callers who may not, media is addressed through the authorizing content endpoint,
 * which serves metadata-stripped copies, instead of a presigned URL to the raw object.
 */
export async function serializeMemory(
  executor: Executor,
  storage: Storage,
  access: Pick<MemoryAccess, 'isOwner' | 'canSeeLocation'>,
  memory: MemoryRow,
  rows: readonly AssetRow[],
  keys: ReadonlyMap<string, string>,
): Promise<MemoryDto> {
  void executor;
  const mediaUrl = async (asset: AssetRow | undefined) => {
    if (asset === undefined) {
      return null;
    }
    if (!access.isOwner && !access.canSeeLocation) {
      return {
        url: `/v1/memories/${memory.id}/assets/${asset.id}/content`,
        expiresAt: new Date(Date.now() + 600_000).toISOString(),
      };
    }
    const key = keys.get(asset.id);
    return key === undefined ? null : presignGet(storage, key, { contentType: asset.mime });
  };

  const showLocation = access.canSeeLocation && memory.lat !== null && memory.lon !== null;
  return {
    id: memory.id,
    ownerId: memory.ownerId,
    isOwner: access.isOwner,
    kind: memory.kind,
    capturedAt: memory.capturedAt.toISOString(),
    capturedTz: memory.capturedTz,
    experienceId: memory.experienceId,
    profile: memory.profileId === null ? null : { id: memory.profileId, version: memory.profileVersion ?? 1 },
    presetId: memory.presetId,
    scenario: memory.scenario,
    capture: access.canSeeLocation ? memory.capture : stripLocationFromCapture(memory.capture),
    location: showLocation ? { lat: memory.lat as number, lon: memory.lon as number, accuracyM: memory.locationAccuracyM } : null,
    ...(access.isOwner ? { locationShared: memory.locationShared, publicHandle: memory.publicHandle } : {}),
    caption: memory.caption,
    favorite: memory.favorite,
    aspectRatio: memory.aspectRatio,
    version: memory.version,
    createdAt: memory.createdAt.toISOString(),
    updatedAt: memory.updatedAt.toISOString(),
    deletedAt: memory.deletedAt?.toISOString() ?? null,
    assets: rows
      .filter((row) => access.isOwner || isServable(row))
      .map((row) => ({
        id: row.id,
        role: row.role,
        status: row.status,
        mime: row.mime,
        bytes: row.bytes,
        width: row.width,
        height: row.height,
        durationMs: row.durationMs,
        failureReason: access.isOwner ? row.failureReason : null,
      })),
    thumbnail: await mediaUrl(pickMedia(rows, 'thumbnail', 'video_poster', 'photo_display', 'photo_rendered')),
    display: await mediaUrl(pickMedia(rows, 'photo_display', 'photo_rendered', 'video_poster', 'photo_original')),
  };
}

/** Removes anything that could carry a position from device-reported capture metadata. */
export function stripLocationFromCapture(capture: Record<string, unknown>): Record<string, unknown> {
  const blocked = /^(gps|location|latitude|longitude|lat|lon|altitude)/i;
  return Object.fromEntries(Object.entries(capture).filter(([key]) => !blocked.test(key)));
}
