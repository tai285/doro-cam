import { randomUUID } from 'node:crypto';
import exifr from 'exifr';
import sharp from 'sharp';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ALL_ACTIONS, ALL_ROLES, type AlbumAction, type AlbumRole, can } from '../src/modules/albums/permissions.ts';
import { createUser, memoryBody, startStack, type Stack, type TestUser, uploadAsset } from './helpers/stack.ts';

interface AlbumJson { id: string; role: AlbumRole; title: string; memberCount: number; itemCount: number; allowOriginalDownload: boolean; shareLocation: boolean }

describe('album permission matrix (pure)', () => {
  const expected: Record<AlbumAction, AlbumRole[]> = {
    view: ['owner', 'editor', 'contributor', 'viewer'],
    add_own_memories: ['owner', 'editor', 'contributor'],
    remove_own_memories: ['owner', 'editor', 'contributor'],
    remove_others_memories: ['owner', 'editor'],
    edit_album: ['owner', 'editor'],
    manage_members: ['owner'],
    delete_album: ['owner'],
  };
  for (const action of ALL_ACTIONS) {
    for (const role of ALL_ROLES) {
      const allowed = expected[action].includes(role);
      it(`[SHR-003] ${role} ${allowed ? 'may' : 'may not'} ${action}`, () => {
        expect(can(role, action)).toBe(allowed);
      });
    }
  }
});

describe('albums and sharing', () => {
  let stack: Stack;
  let owner: TestUser;
  let editor: TestUser;
  let contributor: TestUser;
  let viewer: TestUser;
  let outsider: TestUser;

  const api = (user: TestUser, method: 'GET' | 'POST' | 'PATCH' | 'DELETE' | 'PUT', url: string, payload?: unknown) =>
    stack.app.inject({ method, url, headers: user.headers, ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }) });

  const newAlbum = async (user: TestUser, body: Record<string, unknown> = {}) => {
    const response = await api(user, 'POST', '/v1/albums', { title: 'Japan Trip', ...body });
    expect(response.statusCode).toBe(201);
    return response.json() as AlbumJson;
  };
  const newMemory = async (user: TestUser, overrides: Record<string, unknown> = {}) => {
    const id = randomUUID();
    expect((await api(user, 'PUT', `/v1/memories/${id}`, memoryBody(overrides))).statusCode).toBe(201);
    return id;
  };
  const invite = async (user: TestUser, albumId: string, role: string, extra: Record<string, unknown> = {}) =>
    (await api(user, 'POST', `/v1/albums/${albumId}/invites`, { role, ...extra })).json() as { token: string; id: string };
  const join = async (user: TestUser, token: string) => api(user, 'POST', '/v1/invites/accept', { token });
  /** An album with one member per role. */
  const populated = async (body: Record<string, unknown> = {}) => {
    const album = await newAlbum(owner, body);
    for (const [user, role] of [[editor, 'editor'], [contributor, 'contributor'], [viewer, 'viewer']] as const) {
      expect((await join(user, (await invite(owner, album.id, role)).token)).statusCode).toBe(200);
    }
    return album;
  };

  beforeAll(async () => {
    stack = await startStack();
    [owner, editor, contributor, viewer, outsider] = await Promise.all(['Olive', 'Eddie', 'Connie', 'Vera', 'Otto'].map((name) => createUser(stack, name)));
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[SHR-001] creates an album with the creator as its owner, and lists it only for members', async () => {
    const album = await newAlbum(owner, { description: 'Spring 2027' });
    expect(album).toMatchObject({ role: 'owner', memberCount: 1, itemCount: 0, allowOriginalDownload: true, shareLocation: false });
    const mine = (await api(owner, 'GET', '/v1/albums')).json() as { items: AlbumJson[] };
    expect(mine.items.map((a) => a.id)).toContain(album.id);
    const theirs = (await api(outsider, 'GET', '/v1/albums')).json() as { items: AlbumJson[] };
    expect(theirs.items.map((a) => a.id)).not.toContain(album.id);
    expect((await api(outsider, 'GET', `/v1/albums/${album.id}`)).statusCode).toBe(404);
  });

  it('[SHR-002] a trip needs dates and the end cannot precede the start', async () => {
    const noDates = await api(owner, 'POST', '/v1/albums', { title: 'Trip', kind: 'trip' });
    expect((noDates.json() as { error: { code: string } }).error.code).toBe('album.trip_dates_required');
    const reversed = await api(owner, 'POST', '/v1/albums', { title: 'Trip', kind: 'trip', startsOn: '2027-04-10', endsOn: '2027-04-01' });
    expect((reversed.json() as { error: { code: string } }).error.code).toBe('album.invalid_dates');
    const ok = await api(owner, 'POST', '/v1/albums', { title: 'Trip', kind: 'trip', startsOn: '2027-04-01', endsOn: '2027-04-10' });
    expect(ok.statusCode).toBe(201);
  });

  it('[SHR-003] invites: joining gives the invited role; the token is only stored hashed', async () => {
    const album = await newAlbum(owner);
    const { token } = await invite(owner, album.id, 'contributor');
    const { rows } = await stack.database.pool.query('select token_hash from album_invites where album_id = $1', [album.id]);
    expect(rows[0].token_hash).not.toContain(token);
    expect(rows[0].token_hash).toMatch(/^[0-9a-f]{64}$/);
    const joined = await join(contributor, token);
    expect(joined.json()).toEqual({ albumId: album.id, role: 'contributor' });
    const detail = (await api(contributor, 'GET', `/v1/albums/${album.id}`)).json() as { album: AlbumJson; members: Array<{ role: string }> };
    expect(detail.album.role).toBe('contributor');
    expect(detail.members.map((m) => m.role).sort()).toEqual(['contributor', 'owner']);
  });

  it('[SHR-003] invite errors: unknown 404, revoked/expired/exhausted 410; accepting twice is harmless', async () => {
    const album = await newAlbum(owner);
    expect((await join(viewer, 'x'.repeat(43))).statusCode).toBe(404);

    const revoked = await invite(owner, album.id, 'viewer');
    expect((await api(owner, 'DELETE', `/v1/albums/${album.id}/invites/${revoked.id}`)).statusCode).toBe(204);
    const revokedResponse = await join(viewer, revoked.token);
    expect(revokedResponse.statusCode).toBe(410);
    expect((revokedResponse.json() as { error: { code: string } }).error.code).toBe('invite.revoked');

    const expired = await invite(owner, album.id, 'viewer');
    await stack.database.pool.query("update album_invites set expires_at = now() - interval '1 minute' where id = $1", [expired.id]);
    expect(((await join(viewer, expired.token)).json() as { error: { code: string } }).error.code).toBe('invite.expired');

    const single = await invite(owner, album.id, 'viewer');
    expect((await join(viewer, single.token)).statusCode).toBe(200);
    expect((await join(viewer, single.token)).statusCode).toBe(200); // already a member
    const exhausted = await join(outsider, single.token);
    expect(exhausted.statusCode).toBe(410);
    expect((exhausted.json() as { error: { code: string } }).error.code).toBe('invite.exhausted');
  });

  it('[SHR-003] simultaneous accepts of a single-use invite admit exactly one person', async () => {
    const album = await newAlbum(owner);
    const { token } = await invite(owner, album.id, 'viewer');
    const racers = await Promise.all([createUser(stack, 'R1'), createUser(stack, 'R2'), createUser(stack, 'R3')]);
    const results = await Promise.all(racers.map((racer) => join(racer, token)));
    expect(results.filter((r) => r.statusCode === 200)).toHaveLength(1);
    expect(results.filter((r) => r.statusCode === 410)).toHaveLength(2);
  });

  it('[SHR-003] only the owner manages invites and members; an editor is forbidden (403)', async () => {
    const album = await populated();
    expect((await api(editor, 'POST', `/v1/albums/${album.id}/invites`, { role: 'viewer' })).statusCode).toBe(403);
    expect((await api(contributor, 'PATCH', `/v1/albums/${album.id}/members/${viewer.id}`, { role: 'editor' })).statusCode).toBe(403);
    expect((await api(editor, 'DELETE', `/v1/albums/${album.id}/members/${viewer.id}`)).statusCode).toBe(403);
    expect((await api(outsider, 'POST', `/v1/albums/${album.id}/invites`, { role: 'viewer' })).statusCode).toBe(404);
    const promoted = await api(owner, 'PATCH', `/v1/albums/${album.id}/members/${viewer.id}`, { role: 'contributor' });
    expect(promoted.json()).toMatchObject({ userId: viewer.id, role: 'contributor' });
  });

  it('[SHR-007] members can leave, the owner can remove others, the owner cannot leave', async () => {
    const album = await populated();
    expect((await api(viewer, 'DELETE', `/v1/albums/${album.id}/members/${viewer.id}`)).statusCode).toBe(204);
    expect((await api(viewer, 'GET', `/v1/albums/${album.id}`)).statusCode).toBe(404);
    expect((await api(owner, 'DELETE', `/v1/albums/${album.id}/members/${contributor.id}`)).statusCode).toBe(204);
    const ownerLeaves = await api(owner, 'DELETE', `/v1/albums/${album.id}/members/${owner.id}`);
    expect(ownerLeaves.statusCode).toBe(409);
    expect((ownerLeaves.json() as { error: { code: string } }).error.code).toBe('album.owner_cannot_leave');
    expect((await api(owner, 'PATCH', `/v1/albums/${album.id}/members/${owner.id}`, { role: 'viewer' })).statusCode).toBe(409);
  });

  it('[SHR-001][SHR-004] who may add Memories: owner/editor/contributor add only their own; viewer cannot', async () => {
    const album = await populated();
    const mine = { owner: await newMemory(owner), editor: await newMemory(editor), contributor: await newMemory(contributor), viewer: await newMemory(viewer) };
    for (const [name, user] of [['owner', owner], ['editor', editor], ['contributor', contributor]] as const) {
      const response = await api(user, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [mine[name]] });
      expect(response.json(), name).toEqual({ added: 1 });
    }
    expect((await api(viewer, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [mine.viewer] })).statusCode).toBe(403);
    // a contributor cannot add someone else's Memory; it is reported as not found
    const others = await api(contributor, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [mine.owner] });
    expect(others.statusCode).toBe(404);
    // adding twice adds nothing new
    expect((await api(owner, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [mine.owner] })).json()).toEqual({ added: 0 });
    const items = (await api(viewer, 'GET', `/v1/albums/${album.id}/memories`)).json() as { items: Array<{ id: string }> };
    expect(items.items.map((m) => m.id).sort()).toEqual([mine.owner, mine.editor, mine.contributor].sort());
  });

  it('[SHR-001] removing: own always (non-viewer), others’ only for owner/editor, and the Memory itself is not deleted', async () => {
    const album = await populated();
    const owned = { owner: await newMemory(owner), contributor: await newMemory(contributor) };
    await api(owner, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [owned.owner] });
    await api(contributor, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [owned.contributor] });
    expect((await api(contributor, 'DELETE', `/v1/albums/${album.id}/items/${owned.owner}`)).statusCode).toBe(403);
    expect((await api(viewer, 'DELETE', `/v1/albums/${album.id}/items/${owned.owner}`)).statusCode).toBe(403);
    expect((await api(editor, 'DELETE', `/v1/albums/${album.id}/items/${owned.contributor}`)).statusCode).toBe(204);
    expect((await api(owner, 'DELETE', `/v1/albums/${album.id}/items/${owned.owner}`)).statusCode).toBe(204);
    expect((await api(owner, 'DELETE', `/v1/albums/${album.id}/items/${owned.owner}`)).statusCode).toBe(404);
    expect((await api(contributor, 'GET', `/v1/memories/${owned.contributor}`)).statusCode).toBe(200);
  });

  it('[SHR-001] album edit and delete follow the matrix', async () => {
    const album = await populated();
    expect((await api(contributor, 'PATCH', `/v1/albums/${album.id}`, { title: 'Nope' })).statusCode).toBe(403);
    const renamed = await api(editor, 'PATCH', `/v1/albums/${album.id}`, { title: 'Japan 2027' });
    expect(renamed.json()).toMatchObject({ title: 'Japan 2027', role: 'editor' });
    expect((await api(editor, 'DELETE', `/v1/albums/${album.id}`)).statusCode).toBe(403);
    expect((await api(owner, 'DELETE', `/v1/albums/${album.id}`)).statusCode).toBe(204);
    expect((await api(viewer, 'GET', `/v1/albums/${album.id}`)).statusCode).toBe(404);
  });

  it('[PRIV-003] members read shared Memories; non-members and trashed Memories are 404', async () => {
    const album = await populated();
    const id = await newMemory(owner, { caption: 'Shibuya' });
    await api(owner, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [id] });
    const seen = await api(viewer, 'GET', `/v1/memories/${id}`);
    expect(seen.statusCode).toBe(200);
    expect(seen.json()).toMatchObject({ id, isOwner: false, caption: 'Shibuya' });
    expect((seen.json() as { publicHandle?: string }).publicHandle).toBeUndefined();
    expect((await api(outsider, 'GET', `/v1/memories/${id}`)).statusCode).toBe(404);
    expect((await api(viewer, 'PATCH', `/v1/memories/${id}`, { favorite: true })).statusCode).toBe(404); // members never edit the owner's Memory
    await api(owner, 'POST', `/v1/memories/${id}/trash`);
    expect((await api(viewer, 'GET', `/v1/memories/${id}`)).statusCode).toBe(404);
    const listed = (await api(viewer, 'GET', `/v1/albums/${album.id}/memories`)).json() as { items: unknown[] };
    expect(listed.items).toHaveLength(0);
  });

  it('[SHR-002] trip proposals list the caller’s own Memories shot during the trip, in the shot time zone, and add nothing silently', async () => {
    const album = await newAlbum(contributor, { kind: 'trip', startsOn: '2027-04-01', endsOn: '2027-04-03', autoAddDuringTrip: true });
    const inTrip = await newMemory(contributor, { capturedAt: '2027-04-02T10:00:00.000Z' });
    // 2027-04-03 23:30 in Tokyo is 14:30 UTC on 2027-04-03: inside. 2027-04-04 00:30 Tokyo is 2027-04-03 15:30 UTC: outside by local date.
    const lateInTokyo = await newMemory(contributor, { capturedAt: '2027-04-03T14:30:00.000Z', capturedTz: 'Asia/Tokyo' });
    const afterInTokyo = await newMemory(contributor, { capturedAt: '2027-04-03T15:30:00.000Z', capturedTz: 'Asia/Tokyo' });
    const before = await newMemory(contributor, { capturedAt: '2027-03-30T10:00:00.000Z' });
    const proposals = (await api(contributor, 'GET', `/v1/albums/${album.id}/trip-proposals`)).json() as { memoryIds: string[] };
    expect(proposals.memoryIds.sort()).toEqual([inTrip, lateInTokyo].sort());
    expect(proposals.memoryIds).not.toContain(afterInTokyo);
    expect(proposals.memoryIds).not.toContain(before);
    expect(((await api(contributor, 'GET', `/v1/albums/${album.id}`)).json() as { album: AlbumJson }).album.itemCount).toBe(0);
    await api(contributor, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [inTrip] });
    const after = (await api(contributor, 'GET', `/v1/albums/${album.id}/trip-proposals`)).json() as { memoryIds: string[] };
    expect(after.memoryIds).not.toContain(inTrip);
  });

  it('[SHR-002] a plain album has no proposals', async () => {
    const album = await newAlbum(owner);
    const proposals = (await api(owner, 'GET', `/v1/albums/${album.id}/trip-proposals`)).json() as { memoryIds: string[] };
    expect(proposals.memoryIds).toEqual([]);
  });

  describe('downloads and location privacy', () => {
    /** A JPEG that really carries GPS EXIF, so the leak test inspects actual file metadata. */
    const gpsJpeg = async () =>
      sharp({ create: { width: 160, height: 120, channels: 3, background: { r: 30, g: 140, b: 200 } } })
        .jpeg()
        .withExif({ IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '3/1 8/1 0/1', GPSLongitudeRef: 'E', GPSLongitude: '101/1 41/1 0/1' } })
        .toBuffer();

    const sharedMemory = async (albumBody: Record<string, unknown>, memoryOverrides: Record<string, unknown> = {}) => {
      const album = await populated(albumBody);
      const memoryId = await newMemory(owner, { location: { lat: 3.139, lon: 101.686 }, ...memoryOverrides });
      const data = await gpsJpeg();
      const { assetId } = await uploadAsset(stack, owner, memoryId, { role: 'photo_original', mime: 'image/jpeg', data });
      await uploadAsset(stack, owner, memoryId, { role: 'photo_rendered', mime: 'image/jpeg', data: await gpsJpeg() });
      await api(owner, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [memoryId] });
      return { album, memoryId, assetId, data };
    };

    it('[PRIV-002][SHR-006] the fixture really contains GPS (so the next tests prove something)', async () => {
      const gps = await exifr.gps(await gpsJpeg());
      expect(gps?.latitude).toBeCloseTo(3.1333, 3);
    });

    it('[PRIV-002][SHR-006] with location hidden, a Viewer sees no coordinates and downloads a file with no GPS tags', async () => {
      const { memoryId, assetId } = await sharedMemory({ shareLocation: false });
      const memory = (await api(viewer, 'GET', `/v1/memories/${memoryId}`)).json() as { location: unknown; thumbnail: { url: string } | null; display: { url: string } | null };
      expect(memory.location).toBeNull();
      expect(memory.display?.url).toBe(`/v1/memories/${memoryId}/assets/${memory.display ? (await stack.database.pool.query("select id from assets where memory_id = $1 and role = 'photo_rendered'", [memoryId])).rows[0].id : ''}/content`);

      const download = (await api(viewer, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`)).json() as { url: string; sanitized: boolean };
      expect(download.sanitized).toBe(true);
      expect(download.url).not.toContain('X-Amz-Signature'); // never a link to the raw object
      const content = await api(viewer, 'GET', download.url);
      expect(content.statusCode).toBe(200);
      expect(content.headers['content-type']).toBe('image/jpeg');
      const body = content.rawPayload;
      expect(await exifr.gps(body)).toBeUndefined();
      const tags = await exifr.parse(body, true);
      expect(JSON.stringify(tags ?? {})).not.toMatch(/GPS/i);
      expect((await sharp(body).metadata()).width).toBe(160); // still a usable image
    });

    it('[PRIV-002] the owner always gets the raw original, GPS intact', async () => {
      const { memoryId, assetId, data } = await sharedMemory({ shareLocation: false });
      const download = (await api(owner, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`)).json() as { url: string; sanitized: boolean };
      expect(download.sanitized).toBe(false);
      const bytes = Buffer.from(await (await fetch(download.url)).arrayBuffer());
      expect(bytes.equals(data)).toBe(true);
      expect((await exifr.gps(bytes))?.latitude).toBeDefined();
    });

    it('[SHR-006] location is shown only when the album shares it AND the Memory’s own sharing allows it', async () => {
      const { memoryId } = await sharedMemory({ shareLocation: true });
      // album shares, but the Memory has not opted in
      expect(((await api(viewer, 'GET', `/v1/memories/${memoryId}`)).json() as { location: unknown }).location).toBeNull();
      expect((await api(owner, 'PATCH', `/v1/memories/${memoryId}`, { locationShared: true })).statusCode).toBe(200);
      expect(((await api(viewer, 'GET', `/v1/memories/${memoryId}`)).json() as { location: { lat: number } }).location).toMatchObject({ lat: 3.139 });
      // the owner pulls the location back
      await api(owner, 'PATCH', `/v1/memories/${memoryId}`, { removeLocation: true });
      expect(((await api(viewer, 'GET', `/v1/memories/${memoryId}`)).json() as { location: unknown }).location).toBeNull();
    });

    it('[PRIV-002] once location is shared, members get the unmodified object through a signed URL', async () => {
      const { memoryId, assetId } = await sharedMemory({ shareLocation: true });
      await api(owner, 'PATCH', `/v1/memories/${memoryId}`, { locationShared: true });
      const download = (await api(viewer, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`)).json() as { sanitized: boolean };
      expect(download.sanitized).toBe(false);
    });

    it('[SHR-005] original downloads can be switched off for members, but rendered media stays available', async () => {
      const { memoryId, assetId } = await sharedMemory({ allowOriginalDownload: false });
      const denied = await api(viewer, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`);
      expect(denied.statusCode).toBe(403);
      expect((denied.json() as { error: { code: string } }).error.code).toBe('download.original_not_allowed');
      const rendered = (await stack.database.pool.query("select id from assets where memory_id = $1 and role = 'photo_rendered'", [memoryId])).rows[0].id as string;
      expect((await api(viewer, 'GET', `/v1/memories/${memoryId}/assets/${rendered}/download`)).statusCode).toBe(200);
      // the owner is never restricted by their own album setting
      expect((await api(owner, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`)).statusCode).toBe(200);
    });

    it('[PRIV-002] a non-sanitizable file (HEIC) is refused rather than leaked', async () => {
      const album = await populated({ shareLocation: false });
      const memoryId = await newMemory(owner, { location: { lat: 1, lon: 2 } });
      const heic = Buffer.concat([Buffer.from([0, 0, 0, 24, 102, 116, 121, 112, 104, 101, 105, 99]), Buffer.alloc(100, 7)]);
      const { assetId } = await uploadAsset(stack, owner, memoryId, { role: 'photo_original', mime: 'image/heic', data: heic });
      await api(owner, 'POST', `/v1/albums/${album.id}/items`, { memoryIds: [memoryId] });
      const content = await api(viewer, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/content`);
      expect(content.statusCode).toBe(409);
      expect((content.json() as { error: { code: string } }).error.code).toBe('asset.not_sanitizable');
    });

    it('[PRIV-003] outsiders get 404 for shared media, and a deleted Memory disappears for members', async () => {
      const { memoryId, assetId } = await sharedMemory({});
      expect((await api(outsider, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`)).statusCode).toBe(404);
      await api(owner, 'POST', `/v1/memories/${memoryId}/trash`);
      expect((await api(viewer, 'GET', `/v1/memories/${memoryId}/assets/${assetId}/download`)).statusCode).toBe(404);
    });
  });
});
