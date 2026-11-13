import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createUser, memoryBody, startStack, type Stack, type TestUser } from './helpers/stack.ts';

interface MemoryJson {
  id: string;
  version: number;
  caption: string | null;
  favorite: boolean;
  deletedAt: string | null;
  location: { lat: number; lon: number } | null;
  publicHandle?: string;
  capture: Record<string, unknown>;
}

describe('memories', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const put = (user: TestUser, id: string, body: Record<string, unknown> = memoryBody()) =>
    stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: user.headers, payload: body });

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[SYNC-004][MEM-002] registers a Memory idempotently: 201 then 200 with the same body', async () => {
    const id = randomUUID();
    const first = await put(alice, id);
    expect(first.statusCode).toBe(201);
    const created = first.json() as MemoryJson;
    expect(created).toMatchObject({ id, version: 1, favorite: false, caption: null, deletedAt: null });
    expect(created.capture).toMatchObject({ isoApplied: 200, focalLength35mmEq: 26 });

    const again = await put(alice, id);
    expect(again.statusCode).toBe(200);
    expect((again.json() as MemoryJson).id).toBe(id);
    const { rows } = await stack.database.pool.query('select count(*)::int as n from memories where id = $1', [id]);
    expect(rows[0].n).toBe(1);
  });

  it('[MEM-008] gives every Memory a unique 22-character base62 public handle, visible only to its owner', async () => {
    const handles = new Set<string>();
    for (let i = 0; i < 5; i += 1) {
      const created = (await put(alice, randomUUID())).json() as MemoryJson;
      expect(created.publicHandle).toMatch(/^[0-9A-Za-z]{22}$/);
      handles.add(created.publicHandle as string);
    }
    expect(handles.size).toBe(5);
  });

  it('[SYNC-004] answers 409 memory.conflict when immutable fields differ, and when another user owns the id', async () => {
    const id = randomUUID();
    await put(alice, id);
    const changed = await put(alice, id, memoryBody({ capturedAt: '2026-01-01T00:00:00.000Z' }));
    expect(changed.statusCode).toBe(409);
    expect((changed.json() as { error: { code: string } }).error.code).toBe('memory.conflict');
    const stolen = await put(bob, id);
    expect(stolen.statusCode).toBe(409);
  });

  it('[MEM-002] extracts typed analytics columns from the applied capture settings', async () => {
    const id = randomUUID();
    await put(alice, id);
    const { rows } = await stack.database.pool.query(
      'select focal_length_35mm, iso, exposure_time_ns, aperture, lens_kind from memories where id = $1',
      [id],
    );
    expect(rows[0]).toEqual({ focal_length_35mm: 26, iso: 200, exposure_time_ns: '8000000', aperture: 1.8, lens_kind: 'wide' });
  });

  it('validates the body: bad dates, half a location, unknown kind and oversized caption are 400', async () => {
    for (const bad of [
      memoryBody({ capturedAt: 'yesterday' }),
      memoryBody({ kind: 'hologram' }),
      memoryBody({ caption: 'x'.repeat(2001) }),
      memoryBody({ location: { lat: 95, lon: 0 } }),
      memoryBody({ aspectRatio: 'wide' }),
      { ...memoryBody(), capture: undefined },
    ]) {
      const response = await put(alice, randomUUID(), bad as Record<string, unknown>);
      expect(response.statusCode).toBe(400);
      expect((response.json() as { error: { code: string } }).error.code).toBe('request.invalid');
    }
    expect((await put(alice, 'not-a-uuid')).statusCode).toBe(400);
  });

  it('[PRIV-003] does not reveal other users’ Memories: detail, patch, trash and delete answer 404', async () => {
    const id = randomUUID();
    await put(alice, id);
    expect((await stack.app.inject({ method: 'GET', url: `/v1/memories/${id}`, headers: bob.headers })).statusCode).toBe(404);
    expect((await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: bob.headers, payload: { favorite: true } })).statusCode).toBe(404);
    expect((await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: bob.headers })).statusCode).toBe(404);
    expect((await stack.app.inject({ method: 'DELETE', url: `/v1/memories/${id}`, headers: bob.headers })).statusCode).toBe(404);
    const list = (await stack.app.inject({ method: 'GET', url: '/v1/memories', headers: bob.headers })).json() as { items: MemoryJson[] };
    expect(list.items.find((m) => m.id === id)).toBeUndefined();
  });

  it('[WEB-002][LIB-001] lists newest first with stable cursor pagination and no duplicates or gaps', async () => {
    const carol = await createUser(stack, 'Carol');
    const ids: string[] = [];
    for (let i = 0; i < 7; i += 1) {
      const id = randomUUID();
      ids.push(id);
      await put(carol, id, memoryBody({ capturedAt: `2026-02-0${i + 1}T10:00:00.000Z` }));
    }
    // two with the identical timestamp prove the (capturedAt, id) tiebreak
    const tieA = randomUUID();
    const tieB = randomUUID();
    await put(carol, tieA, memoryBody({ capturedAt: '2026-03-01T10:00:00.000Z' }));
    await put(carol, tieB, memoryBody({ capturedAt: '2026-03-01T10:00:00.000Z' }));

    const seen: string[] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const url: string = `/v1/memories?limit=3${cursor === null ? '' : `&cursor=${cursor}`}`;
      const page = (await stack.app.inject({ method: 'GET', url, headers: carol.headers })).json() as { items: MemoryJson[]; nextCursor: string | null };
      seen.push(...page.items.map((m) => m.id));
      cursor = page.nextCursor;
      pages += 1;
    } while (cursor !== null);
    expect(pages).toBe(3);
    expect(seen).toHaveLength(9);
    expect(new Set(seen).size).toBe(9);
    expect(seen.slice(0, 2).sort()).toEqual([tieA, tieB].sort());
    expect(seen.slice(2)).toEqual([...ids].reverse());
  });

  it('[WEB-002] filters by kind and favorite and rejects a bad cursor', async () => {
    const dave = await createUser(stack, 'Dave');
    const photo = randomUUID();
    const motion = randomUUID();
    await put(dave, photo);
    await put(dave, motion, memoryBody({ kind: 'motion', favorite: true }));
    const motions = (await stack.app.inject({ method: 'GET', url: '/v1/memories?kind=motion', headers: dave.headers })).json() as { items: MemoryJson[] };
    expect(motions.items.map((m) => m.id)).toEqual([motion]);
    const favorites = (await stack.app.inject({ method: 'GET', url: '/v1/memories?favorite=true', headers: dave.headers })).json() as { items: MemoryJson[] };
    expect(favorites.items.map((m) => m.id)).toEqual([motion]);
    const bad = await stack.app.inject({ method: 'GET', url: '/v1/memories?cursor=garbage', headers: dave.headers });
    expect(bad.statusCode).toBe(400);
    expect((bad.json() as { error: { code: string } }).error.code).toBe('request.invalid_cursor');
  });

  it('[MEM-004][MEM-006] edits caption and favorite, bumping the version', async () => {
    const id = randomUUID();
    await put(alice, id);
    const patched = await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: alice.headers, payload: { caption: 'Golden hour', favorite: true } });
    expect(patched.statusCode).toBe(200);
    expect(patched.json()).toMatchObject({ caption: 'Golden hour', favorite: true, version: 2 });
    const cleared = await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: alice.headers, payload: { caption: null } });
    expect(cleared.json()).toMatchObject({ caption: null, version: 3 });
    expect((await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: alice.headers, payload: {} })).statusCode).toBe(400);
  });

  it('[SYNC-007] If-Match rejects a stale version with 409 conflict.version', async () => {
    const id = randomUUID();
    await put(alice, id);
    const stale = await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: { ...alice.headers, 'if-match': '7' }, payload: { favorite: true } });
    expect(stale.statusCode).toBe(409);
    expect((stale.json() as { error: { code: string } }).error.code).toBe('conflict.version');
    const fresh = await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: { ...alice.headers, 'if-match': '1' }, payload: { favorite: true } });
    expect(fresh.statusCode).toBe(200);
  });

  it('[PRIV-001][MEM-003] stores location only when sent and removeLocation clears all three fields', async () => {
    const id = randomUUID();
    const created = (await put(alice, id, memoryBody({ location: { lat: 3.139, lon: 101.6869, accuracyM: 8 } }))).json() as MemoryJson;
    expect(created.location).toMatchObject({ lat: 3.139, lon: 101.6869 });
    const removed = (await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: alice.headers, payload: { removeLocation: true } })).json() as MemoryJson;
    expect(removed.location).toBeNull();
    const { rows } = await stack.database.pool.query('select lat, lon, location_accuracy_m from memories where id = $1', [id]);
    expect(rows[0]).toEqual({ lat: null, lon: null, location_accuracy_m: null });
    const noLocation = (await put(alice, randomUUID())).json() as MemoryJson;
    expect(noLocation.location).toBeNull();
  });

  it('[MEM-007] trash hides a Memory from the library, restore brings it back, both are idempotent', async () => {
    const id = randomUUID();
    await put(alice, id);
    const trashed = await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: alice.headers });
    expect(trashed.statusCode).toBe(200);
    expect((trashed.json() as MemoryJson).deletedAt).not.toBeNull();
    const again = await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: alice.headers });
    expect((again.json() as MemoryJson).version).toBe((trashed.json() as MemoryJson).version);

    const library = (await stack.app.inject({ method: 'GET', url: '/v1/memories?limit=200', headers: alice.headers })).json() as { items: MemoryJson[] };
    expect(library.items.some((m) => m.id === id)).toBe(false);
    const trash = (await stack.app.inject({ method: 'GET', url: '/v1/memories?trashed=true', headers: alice.headers })).json() as { items: MemoryJson[] };
    expect(trash.items.some((m) => m.id === id)).toBe(true);

    const restored = await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/restore`, headers: alice.headers });
    expect((restored.json() as MemoryJson).deletedAt).toBeNull();
    const back = (await stack.app.inject({ method: 'GET', url: '/v1/memories?limit=200', headers: alice.headers })).json() as { items: MemoryJson[] };
    expect(back.items.some((m) => m.id === id)).toBe(true);
  });

  it('[MEM-007] permanent delete requires the trash first, then purges the Memory', async () => {
    const id = randomUUID();
    await put(alice, id);
    const early = await stack.app.inject({ method: 'DELETE', url: `/v1/memories/${id}`, headers: alice.headers });
    expect(early.statusCode).toBe(409);
    expect((early.json() as { error: { code: string } }).error.code).toBe('memory.not_trashed');
    await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: alice.headers });
    const purge = await stack.app.inject({ method: 'DELETE', url: `/v1/memories/${id}`, headers: alice.headers });
    expect(purge.statusCode).toBe(202);
    expect((await stack.app.inject({ method: 'GET', url: `/v1/memories/${id}`, headers: alice.headers })).statusCode).toBe(404);
  });

  it('[MEM-007] emptying the trash purges every trashed Memory of the caller only', async () => {
    const erin = await createUser(stack, 'Erin');
    const ids = [randomUUID(), randomUUID()];
    for (const id of ids) {
      await put(erin, id);
      await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: erin.headers });
    }
    const keep = randomUUID();
    await put(erin, keep);
    const empty = await stack.app.inject({ method: 'POST', url: '/v1/memories/trash/empty', headers: erin.headers });
    expect(empty.json()).toMatchObject({ status: 'purging', count: 2 });
    const { rows } = await stack.database.pool.query('select id from memories where owner_id = $1', [erin.id]);
    expect(rows.map((r: { id: string }) => r.id)).toEqual([keep]);
  });
});
