import { createReadStream, createWriteStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { PutObjectCommand } from '@aws-sdk/client-s3';
import { and, eq, inArray, isNull } from 'drizzle-orm';
import yazl from 'yazl';
import { albumItems, albumMembers, albums, assets, dataExports, memories, presets, storageObjects, user } from '../../db/schema.ts';
import type { JobServices } from '../context.ts';
import { downloadToFile, withTempDir } from '../media/transcode.ts';

/** Roles that hold the user's own media. Derived renditions are regenerable and left out. */
const ARCHIVED_ROLES = ['photo_original', 'photo_rendered', 'motion_clip', 'video_original'] as const;
const EXTENSIONS: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/x-adobe-dng': 'dng',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
};

export function exportKey(ownerId: string, exportId: string): string {
  return `exports/${ownerId}/${exportId}.zip`;
}

/**
 * Builds the user's data archive (WEB-010, PRIV-006): every original/rendered file as-is under
 * memories/<date>_<id>/, plus metadata.json with account, Memory metadata, albums and presets.
 * Media is streamed from storage into the zip so memory use stays flat; the finished file is uploaded
 * once and offered through a short-lived link. Idempotent: a ready export is left alone.
 */
export async function buildExport(services: JobServices, exportId: string): Promise<'ready' | 'skipped' | 'failed'> {
  const db = services.database.db;
  const record = (await db.select().from(dataExports).where(eq(dataExports.id, exportId)))[0];
  if (record === undefined || (record.status !== 'pending' && record.status !== 'building')) {
    return 'skipped';
  }
  await db.update(dataExports).set({ status: 'building' }).where(eq(dataExports.id, exportId));
  const ownerId = record.ownerId;

  try {
    const profile = (await db.select({ id: user.id, name: user.name, email: user.email, createdAt: user.createdAt }).from(user).where(eq(user.id, ownerId)))[0];
    const owned = await db.select().from(memories).where(and(eq(memories.ownerId, ownerId), isNull(memories.deletedAt)));
    const ids = owned.map((memory) => memory.id);
    const rows = ids.length === 0 ? [] : await db.select().from(assets).where(inArray(assets.memoryId, ids));
    const objectIds = rows.flatMap((row) => (row.storageObjectId === null ? [] : [row.storageObjectId]));
    const objects = objectIds.length === 0 ? [] : await db.select().from(storageObjects).where(inArray(storageObjects.id, objectIds));
    const keyById = new Map(objects.map((object) => [object.id, object.key]));
    const userPresets = await db.select().from(presets).where(and(eq(presets.ownerId, ownerId), isNull(presets.deletedAt)));
    const memberships = await db
      .select({ albumId: albums.id, title: albums.title, role: albumMembers.role })
      .from(albumMembers)
      .innerJoin(albums, eq(albums.id, albumMembers.albumId))
      .where(and(eq(albumMembers.userId, ownerId), isNull(albums.deletedAt)));
    const items = ids.length === 0 ? [] : await db.select().from(albumItems).where(inArray(albumItems.memoryId, ids));

    const folder = (memory: (typeof owned)[number]) => `memories/${memory.capturedAt.toISOString().slice(0, 10)}_${memory.id.slice(0, 8)}`;
    const files: Array<{ name: string; key: string }> = [];
    const manifest = owned.map((memory) => {
      const memoryAssets = rows.filter((row) => row.memoryId === memory.id);
      const archived = memoryAssets.filter((row) => (ARCHIVED_ROLES as readonly string[]).includes(row.role) && (row.status === 'verified' || row.status === 'ready'));
      const fileNames = archived.flatMap((row) => {
        const key = row.storageObjectId === null ? undefined : keyById.get(row.storageObjectId);
        if (key === undefined) {
          return [];
        }
        const name = `${folder(memory)}/${row.role}.${EXTENSIONS[row.mime] ?? 'bin'}`;
        files.push({ name, key });
        return [{ role: row.role, file: name, mime: row.mime, bytes: row.bytes, sha256: row.sha256.toString('hex') }];
      });
      return {
        id: memory.id,
        kind: memory.kind,
        capturedAt: memory.capturedAt.toISOString(),
        capturedTz: memory.capturedTz,
        experienceId: memory.experienceId,
        profile: memory.profileId === null ? null : { id: memory.profileId, version: memory.profileVersion },
        scenario: memory.scenario,
        capture: memory.capture,
        location: memory.lat === null ? null : { lat: memory.lat, lon: memory.lon, accuracyM: memory.locationAccuracyM },
        caption: memory.caption,
        favorite: memory.favorite,
        aspectRatio: memory.aspectRatio,
        publicHandle: memory.publicHandle,
        albums: items.filter((item) => item.memoryId === memory.id).map((item) => item.albumId),
        files: fileNames,
      };
    });
    const metadata = {
      exportedAt: new Date().toISOString(),
      account: profile === undefined ? null : { id: profile.id, name: profile.name, email: profile.email, createdAt: profile.createdAt.toISOString() },
      memories: manifest,
      albums: memberships,
      presets: userPresets.map((preset) => ({ id: preset.id, name: preset.name, experienceId: preset.experienceId, intent: preset.intent, profileId: preset.profileId, live: preset.live })),
    };

    const key = exportKey(ownerId, exportId);
    const bytes = await withTempDir(async (dir) => {
      const file = path.join(dir, 'export.zip');
      const zip = new yazl.ZipFile();
      const out = createWriteStream(file);
      const finished = pipeline(zip.outputStream, out);
      zip.addBuffer(Buffer.from(JSON.stringify(metadata, null, 2)), 'metadata.json');
      // Each object is fetched to a temp file and added in order; yazl then streams the files into the archive.
      let n = 0;
      for (const entry of files) {
        n += 1;
        const local = path.join(dir, `part-${String(n)}`);
        await downloadToFile(services, entry.key, local);
        zip.addFile(local, entry.name, { compress: false });
      }
      zip.end();
      await finished;
      const size = (await stat(file)).size;
      await services.storage.client.send(
        new PutObjectCommand({ Bucket: services.storage.bucket, Key: key, Body: createReadStream(file), ContentLength: size, ContentType: 'application/zip' }),
      );
      return size;
    });

    await db.update(dataExports).set({ status: 'ready', objectKey: key, bytes, completedAt: new Date() }).where(eq(dataExports.id, exportId));
    return 'ready';
  } catch (error) {
    await db
      .update(dataExports)
      .set({ status: 'failed', failureReason: error instanceof Error ? error.message.slice(0, 300) : 'unknown error' })
      .where(eq(dataExports.id, exportId));
    return 'failed';
  }
}
