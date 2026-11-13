import { and, asc, eq, gt, lt, sql } from 'drizzle-orm';
import type { Executor } from '../../lib/db-types.ts';
import { changeLog } from '../../db/schema.ts';

export type ChangeEntity = 'memory' | 'asset' | 'preset' | 'album';

/** Takes the next global change sequence number. Every change to a synced entity gets one. */
export async function nextSeq(executor: Executor): Promise<number> {
  const result = await executor.execute<{ seq: string }>(sql`select nextval('change_seq') as seq`);
  const row = result.rows[0];
  if (row === undefined) {
    throw new Error('change_seq returned no value');
  }
  return Number(row.seq);
}

/** Appends a change to the feed and returns its sequence number. */
export async function recordChange(
  executor: Executor,
  change: { ownerId: string; entity: ChangeEntity; entityId: string; op: 'upsert' | 'delete'; seq?: number },
): Promise<number> {
  const seq = change.seq ?? (await nextSeq(executor));
  await executor
    .insert(changeLog)
    .values({ seq, ownerId: change.ownerId, entity: change.entity, entityId: change.entityId, op: change.op });
  return seq;
}

export interface ChangePage {
  items: Array<{ seq: number; entity: ChangeEntity; entityId: string; op: 'upsert' | 'delete'; at: string }>;
  nextCursor: number;
  hasMore: boolean;
}

/** Changes after `cursor`, oldest first. Retention is 90 days; older cursors need a full resync. */
export async function listChanges(executor: Executor, ownerId: string, cursor: number, limit: number): Promise<ChangePage> {
  const rows = await executor
    .select()
    .from(changeLog)
    .where(and(eq(changeLog.ownerId, ownerId), gt(changeLog.seq, cursor)))
    .orderBy(asc(changeLog.seq))
    .limit(limit + 1);
  const page = rows.slice(0, limit);
  return {
    items: page.map((row) => ({
      seq: row.seq,
      entity: row.entity,
      entityId: row.entityId,
      op: row.op,
      at: row.at.toISOString(),
    })),
    nextCursor: page.at(-1)?.seq ?? cursor,
    hasMore: rows.length > limit,
  };
}

/** Removes feed entries older than the retention window; returns how many were removed. */
export async function pruneChanges(executor: Executor, olderThan: Date): Promise<number> {
  const removed = await executor.delete(changeLog).where(lt(changeLog.at, olderThan)).returning({ seq: changeLog.seq });
  return removed.length;
}
