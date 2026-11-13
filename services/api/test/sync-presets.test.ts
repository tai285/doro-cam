import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createUser, jpegBuffer, memoryBody, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';

interface Change { seq: number; entity: string; entityId: string; op: string }
interface Feed { items: Change[]; nextCursor: number; hasMore: boolean }

describe('sync change feed', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const feed = async (user: TestUser, cursor: number, limit = 100) =>
    (await stack.app.inject({ method: 'GET', url: `/v1/sync/changes?cursor=${cursor}&limit=${limit}`, headers: user.headers })).json() as Feed;

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[SYNC-006] reports upserts and tombstones in order, only for the caller', async () => {
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: alice.headers, payload: memoryBody() });
    await stack.app.inject({ method: 'PATCH', url: `/v1/memories/${id}`, headers: alice.headers, payload: { favorite: true } });
    await stack.app.inject({ method: 'POST', url: `/v1/memories/${id}/trash`, headers: alice.headers });
    const mine = await feed(alice, 0);
    const forMemory = mine.items.filter((c) => c.entityId === id);
    expect(forMemory.map((c) => c.op)).toEqual(['upsert', 'upsert', 'delete']);
    expect(forMemory.every((c, i, all) => i === 0 || c.seq > all[i - 1]!.seq)).toBe(true);
    expect((await feed(bob, 0)).items).toEqual([]);
  });

  it('[SYNC-006] pages with a cursor and reports hasMore', async () => {
    const carol = await createUser(stack, 'Carol');
    for (let i = 0; i < 5; i += 1) {
      await stack.app.inject({ method: 'PUT', url: `/v1/memories/${randomUUID()}`, headers: carol.headers, payload: memoryBody() });
    }
    const first = await feed(carol, 0, 2);
    expect(first.items).toHaveLength(2);
    expect(first.hasMore).toBe(true);
    const second = await feed(carol, first.nextCursor, 2);
    const third = await feed(carol, second.nextCursor, 2);
    expect(third.items).toHaveLength(1);
    expect(third.hasMore).toBe(false);
    const all = [...first.items, ...second.items, ...third.items].map((c) => c.seq);
    expect(new Set(all).size).toBe(5);
    expect(await feed(carol, third.nextCursor)).toMatchObject({ items: [], hasMore: false, nextCursor: third.nextCursor });
  });

  it('[SYNC-006] an upload being verified shows up as a Memory change so other devices refresh it', async () => {
    const dave = await createUser(stack, 'Dave');
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/memories/${id}`, headers: dave.headers, payload: memoryBody() });
    const before = (await feed(dave, 0)).nextCursor;
    await uploadAsset(stack, dave, id, { role: 'thumbnail', mime: 'image/jpeg', data: await jpegBuffer(20, 20) });
    const after = await feed(dave, before);
    expect(after.items.some((c) => c.entityId === id && c.op === 'upsert')).toBe(true);
  });

  it('validates the query', async () => {
    const response = await stack.app.inject({ method: 'GET', url: '/v1/sync/changes?cursor=-1', headers: alice.headers });
    expect(response.statusCode).toBe(400);
    expect((await stack.app.inject({ method: 'GET', url: '/v1/sync/changes?limit=0', headers: alice.headers })).statusCode).toBe(400);
  });
});

describe('presets', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const body = (overrides: Record<string, unknown> = {}) => ({
    name: 'Street 35',
    experienceId: 'mirrorless',
    intent: { scenario: 'street', zoom: 1.5 },
    profile: { id: 'warm-film', version: 1 },
    live: true,
    ...overrides,
  });

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[EXP-007] creates, lists, edits and deletes presets with version and change feed entries', async () => {
    const id = randomUUID();
    const created = await stack.app.inject({ method: 'PUT', url: `/v1/presets/${id}`, headers: alice.headers, payload: body() });
    expect(created.statusCode).toBe(200);
    expect(created.json()).toMatchObject({ id, name: 'Street 35', live: true, source: 'user', version: 1, profile: { id: 'warm-film', version: 1 } });

    const edited = await stack.app.inject({ method: 'PUT', url: `/v1/presets/${id}`, headers: alice.headers, payload: body({ name: 'Street 28', profile: null }) });
    expect(edited.json()).toMatchObject({ name: 'Street 28', version: 2, profile: null });

    const list = (await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: alice.headers })).json() as { items: Array<{ id: string }> };
    expect(list.items.map((p) => p.id)).toEqual([id]);

    expect((await stack.app.inject({ method: 'DELETE', url: `/v1/presets/${id}`, headers: alice.headers })).statusCode).toBe(204);
    expect(((await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: alice.headers })).json() as { items: unknown[] }).items).toEqual([]);
    expect((await stack.app.inject({ method: 'DELETE', url: `/v1/presets/${id}`, headers: alice.headers })).statusCode).toBe(404);

    const changes = (await stack.app.inject({ method: 'GET', url: '/v1/sync/changes', headers: alice.headers })).json() as Feed;
    expect(changes.items.filter((c) => c.entityId === id).map((c) => c.op)).toEqual(['upsert', 'upsert', 'delete']);
  });

  it('[EXP-007] presets are private: another user cannot see, overwrite or delete them', async () => {
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/presets/${id}`, headers: alice.headers, payload: body() });
    expect(((await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: bob.headers })).json() as { items: unknown[] }).items).toEqual([]);
    expect((await stack.app.inject({ method: 'PUT', url: `/v1/presets/${id}`, headers: bob.headers, payload: body({ name: 'Mine now' }) })).statusCode).toBe(409);
    expect((await stack.app.inject({ method: 'DELETE', url: `/v1/presets/${id}`, headers: bob.headers })).statusCode).toBe(404);
    expect(((await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: alice.headers })).json() as { items: Array<{ name: string }> }).items[0]!.name).toBe('Street 35');
  });

  it('[EXP-007] validates names and ids', async () => {
    expect((await stack.app.inject({ method: 'PUT', url: `/v1/presets/${randomUUID()}`, headers: alice.headers, payload: body({ name: '   ' }) })).statusCode).toBe(400);
    expect((await stack.app.inject({ method: 'PUT', url: '/v1/presets/nope', headers: alice.headers, payload: body() })).statusCode).toBe(400);
    expect((await stack.app.inject({ method: 'PUT', url: `/v1/presets/${randomUUID()}`, headers: alice.headers, payload: { name: 'x' } })).statusCode).toBe(400);
  });

  it('[EXP-007] re-creating a deleted preset id brings it back', async () => {
    const id = randomUUID();
    await stack.app.inject({ method: 'PUT', url: `/v1/presets/${id}`, headers: alice.headers, payload: body({ name: 'Old' }) });
    await stack.app.inject({ method: 'DELETE', url: `/v1/presets/${id}`, headers: alice.headers });
    const back = await stack.app.inject({ method: 'PUT', url: `/v1/presets/${id}`, headers: alice.headers, payload: body({ name: 'New' }) });
    expect(back.json()).toMatchObject({ name: 'New' });
    expect(((await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: alice.headers })).json() as { items: Array<{ id: string }> }).items.some((p) => p.id === id)).toBe(true);
  });
});
