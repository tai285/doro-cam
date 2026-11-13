import { vi } from 'vitest';
import type {
  Album,
  AlbumMember,
  DeviceSession,
  InsightsReport,
  Me,
  Memory,
  Preset,
  PresetSuggestion,
} from '../api/types.ts';

/** A call the app made, recorded so tests can assert on what was sent. */
export interface Call {
  method: string;
  path: string;
  query: URLSearchParams;
  body: unknown;
}

export interface FakeState {
  signedIn: boolean;
  me: Me;
  sessions: DeviceSession[];
  memories: Memory[];
  albums: Array<{ album: Album; members: AlbumMember[]; memoryIds: string[] }>;
  presets: Preset[];
  suggestions: PresetSuggestion[];
  insights: InsightsReport;
  tripProposals: string[];
  /** Force the next response for a "METHOD /path" (exact) to fail with this status and error code. */
  failures: Map<string, { status: number; code: string; message?: string }>;
  calls: Call[];
}

const emptyDistribution = { total: 0, buckets: [] };

export const emptyInsights: InsightsReport = {
  total: 0,
  focalLength: emptyDistribution,
  lens: emptyDistribution,
  profile: emptyDistribution,
  experience: emptyDistribution,
  iso: emptyDistribution,
  shutter: emptyDistribution,
  aperture: emptyDistribution,
  timeOfDay: emptyDistribution,
  trend: [],
  insights: [],
};

export function makeMe(overrides: Partial<Me> = {}): Me {
  return {
    id: 'u-1',
    email: 'dorothy@example.test',
    name: 'Dorothy',
    emailVerified: true,
    createdAt: '2026-01-01T00:00:00.000Z',
    storage: { usedBytes: 2_500_000, quotaBytes: 10_737_418_240 },
    deletionRequestedAt: null,
    deletionScheduledFor: null,
    ...overrides,
  };
}

let counter = 0;

export function makeMemory(overrides: Partial<Memory> = {}): Memory {
  counter += 1;
  const id = overrides.id ?? `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`;
  return {
    id,
    ownerId: 'u-1',
    isOwner: true,
    kind: 'photo',
    capturedAt: '2026-11-01T09:30:00.000Z',
    capturedTz: 'Asia/Kuala_Lumpur',
    experienceId: 'mirrorless',
    profile: { id: 'natural', version: 1 },
    presetId: null,
    scenario: null,
    capture: {
      lensKind: 'wide',
      focalLength35mmEq: 26,
      aperture: 1.8,
      isoApplied: 200,
      exposureTimeNsApplied: 8_000_000,
      widthPx: 4000,
      heightPx: 3000,
      deviceMake: 'Honor',
      deviceModel: 'X9c',
    },
    location: null,
    caption: null,
    favorite: false,
    aspectRatio: null,
    version: 1,
    createdAt: '2026-11-01T09:31:00.000Z',
    updatedAt: '2026-11-01T09:31:00.000Z',
    deletedAt: null,
    assets: [
      {
        id: `${id}-orig`,
        role: 'photo_original',
        status: 'verified',
        mime: 'image/jpeg',
        bytes: 2_500_000,
        width: 4000,
        height: 3000,
        durationMs: null,
        failureReason: null,
      },
    ],
    thumbnail: { url: `https://media.test/${id}/thumb.jpg`, expiresAt: '2099-01-01T00:00:00.000Z' },
    display: { url: `https://media.test/${id}/display.jpg`, expiresAt: '2099-01-01T00:00:00.000Z' },
    ...overrides,
  };
}

export function makeAlbum(overrides: Partial<Album> = {}): Album {
  counter += 1;
  return {
    id: `a0000000-0000-4000-8000-${String(counter).padStart(12, '0')}`,
    ownerId: 'u-1',
    kind: 'album',
    title: 'Japan Trip',
    description: null,
    startsOn: null,
    endsOn: null,
    coverMemoryId: null,
    allowOriginalDownload: true,
    shareLocation: false,
    autoAddDuringTrip: false,
    role: 'owner',
    memberCount: 1,
    itemCount: 0,
    createdAt: '2026-11-01T00:00:00.000Z',
    updatedAt: '2026-11-01T00:00:00.000Z',
    ...overrides,
  };
}

export function makePreset(overrides: Partial<Preset> = {}): Preset {
  counter += 1;
  return {
    id: `b0000000-0000-4000-8000-${String(counter).padStart(12, '0')}`,
    name: 'Street 35',
    experienceId: 'mirrorless',
    intent: { scenario: 'street' },
    profile: { id: 'warm-film', version: 1 },
    live: false,
    source: 'user',
    version: 1,
    createdAt: '2026-11-01T00:00:00.000Z',
    updatedAt: '2026-11-01T00:00:00.000Z',
    ...overrides,
  };
}

export interface FakeApi {
  state: FakeState;
  /** Calls matching a method and a path pattern (string prefix or RegExp). */
  calls(method: string, path: string | RegExp): Call[];
}

function respond(status: number, body?: unknown): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
  });
}
const error = (status: number, code: string, message = 'Something went wrong.') =>
  respond(status, { error: { code, message, requestId: 'req-1' } });

/** Replaces fetch with an in-memory implementation of the API. Call `vi.unstubAllGlobals()` (done in the test setup) to restore it. */
export function installFakeApi(initial: Partial<FakeState> = {}): FakeApi {
  const state: FakeState = {
    signedIn: true,
    me: makeMe(),
    sessions: [
      {
        id: 's-1',
        current: true,
        userAgent: 'Firefox on Linux',
        ipAddress: null,
        createdAt: '2026-11-01T00:00:00.000Z',
        expiresAt: '2026-12-01T00:00:00.000Z',
      },
    ],
    memories: [],
    albums: [],
    presets: [],
    suggestions: [],
    insights: emptyInsights,
    tripProposals: [],
    failures: new Map(),
    calls: [],
    ...initial,
  };

  const memoryOf = (id: string) => state.memories.find((memory) => memory.id === id);
  const albumOf = (id: string) => state.albums.find((entry) => entry.album.id === id);

  const handle = (
    method: string,
    path: string,
    query: URLSearchParams,
    body: Record<string, unknown>,
  ): Response => {
    const forced = state.failures.get(`${method} ${path}`);
    if (forced !== undefined) {
      state.failures.delete(`${method} ${path}`);
      return error(forced.status, forced.code, forced.message);
    }
    let m: RegExpMatchArray | null;

    // ---- auth
    if (method === 'POST' && path === '/v1/auth/sign-in/email') {
      if (body.email === 'unverified@example.test')
        return respond(403, { code: 'EMAIL_NOT_VERIFIED', message: 'Email not verified' });
      if (body.password !== 'correct-password')
        return respond(401, {
          code: 'INVALID_EMAIL_OR_PASSWORD',
          message: 'Invalid email or password',
        });
      state.signedIn = true;
      return respond(200, { ok: true });
    }
    if (method === 'POST' && path === '/v1/auth/sign-up/email') return respond(200, { ok: true });
    if (method === 'POST' && path === '/v1/auth/sign-out') {
      state.signedIn = false;
      return respond(200, { success: true });
    }
    if (
      method === 'POST' &&
      (path === '/v1/auth/request-password-reset' || path === '/v1/auth/reset-password')
    )
      return respond(200, { status: true });

    // everything below needs a session
    if (!state.signedIn) return error(401, 'auth.unauthenticated', 'Authentication is required.');

    if (method === 'GET' && path === '/v1/me') return respond(200, state.me);
    if (method === 'GET' && path === '/v1/me/sessions')
      return respond(200, { items: state.sessions });
    if ((m = path.match(/^\/v1\/me\/sessions\/(.+)$/)) && method === 'DELETE') {
      state.sessions = state.sessions.filter((s) => s.id !== m?.[1]);
      return respond(204);
    }
    if (method === 'POST' && path === '/v1/me/deletion') {
      if (body.password !== 'correct-password')
        return error(403, 'auth.reauthentication_failed', 'The password is incorrect.');
      const when = '2026-11-20T00:00:00.000Z';
      state.me = {
        ...state.me,
        deletionRequestedAt: '2026-11-13T00:00:00.000Z',
        deletionScheduledFor: when,
      };
      return respond(200, { scheduledFor: when });
    }
    if (method === 'DELETE' && path === '/v1/me/deletion') {
      state.me = { ...state.me, deletionRequestedAt: null, deletionScheduledFor: null };
      return respond(204);
    }

    // ---- memories
    if (method === 'GET' && path === '/v1/memories') {
      const trashed = query.get('trashed') === 'true';
      let list = state.memories.filter((memory) => (memory.deletedAt !== null) === trashed);
      const kind = query.get('kind');
      if (kind !== null) list = list.filter((memory) => memory.kind === kind);
      if (query.get('favorite') === 'true') list = list.filter((memory) => memory.favorite);
      list = [...list].sort((a, b) => b.capturedAt.localeCompare(a.capturedAt));
      const limit = Number(query.get('limit') ?? 50);
      const start = Number(query.get('cursor') ?? 0);
      const items = list.slice(start, start + limit);
      return respond(200, {
        items,
        nextCursor: start + limit < list.length ? String(start + limit) : null,
      });
    }
    if (method === 'POST' && path === '/v1/memories/trash/empty') {
      const trashed = state.memories.filter((memory) => memory.deletedAt !== null);
      state.memories = state.memories.filter((memory) => memory.deletedAt === null);
      return respond(202, { status: 'purging', count: trashed.length });
    }
    if ((m = path.match(/^\/v1\/memories\/([^/]+)$/))) {
      const memory = memoryOf(m[1] ?? '');
      if (memory === undefined) return error(404, 'memory.not_found', 'Memory not found.');
      if (method === 'GET') return respond(200, memory);
      if (method === 'PATCH') {
        if (typeof body.caption === 'string' || body.caption === null)
          memory.caption = body.caption;
        if (typeof body.favorite === 'boolean') memory.favorite = body.favorite;
        if (body.removeLocation === true) memory.location = null;
        memory.version += 1;
        return respond(200, memory);
      }
      if (method === 'DELETE') {
        state.memories = state.memories.filter((x) => x.id !== memory.id);
        return respond(202, { status: 'purging' });
      }
    }
    if ((m = path.match(/^\/v1\/memories\/([^/]+)\/(trash|restore)$/)) && method === 'POST') {
      const memory = memoryOf(m[1] ?? '');
      if (memory === undefined) return error(404, 'memory.not_found');
      memory.deletedAt = m[2] === 'trash' ? '2026-11-13T00:00:00.000Z' : null;
      return respond(200, memory);
    }
    if (
      (m = path.match(/^\/v1\/memories\/([^/]+)\/assets\/([^/]+)\/download$/)) &&
      method === 'GET'
    ) {
      return respond(200, {
        url: `https://media.test/${m[1] ?? ''}/${m[2] ?? ''}?sig=1`,
        expiresAt: '2099-01-01T00:00:00.000Z',
        sanitized: false,
        filename: 'photo_original-0000.jpg',
      });
    }

    // ---- albums
    if (path === '/v1/albums' && method === 'GET')
      return respond(200, { items: state.albums.map((entry) => entry.album) });
    if (path === '/v1/albums' && method === 'POST') {
      const album = makeAlbum({
        title: String(body.title),
        kind: body.kind === 'trip' ? 'trip' : 'album',
        startsOn: (body.startsOn as string | undefined) ?? null,
        endsOn: (body.endsOn as string | undefined) ?? null,
      });
      state.albums.push({
        album,
        members: [
          { userId: state.me.id, name: state.me.name, role: 'owner', joinedAt: album.createdAt },
        ],
        memoryIds: [],
      });
      return respond(201, album);
    }
    if (path === '/v1/invites/accept' && method === 'POST') {
      if (body.token === 'expired-token-expired-token-expired') return error(410, 'invite.expired');
      if (body.token === 'unknown-token-unknown-token-unknown')
        return error(404, 'invite.not_found');
      const entry = state.albums[0];
      return entry === undefined
        ? error(404, 'invite.not_found')
        : respond(200, { albumId: entry.album.id, role: 'contributor' });
    }
    if ((m = path.match(/^\/v1\/albums\/([^/]+)(?:\/(.+))?$/))) {
      const entry = albumOf(m[1] ?? '');
      if (entry === undefined) return error(404, 'album.not_found', 'Album not found.');
      const sub = m[2];
      if (sub === undefined && method === 'GET')
        return respond(200, {
          album: {
            ...entry.album,
            itemCount: entry.memoryIds.length,
            memberCount: entry.members.length,
          },
          members: entry.members,
        });
      if (sub === undefined && method === 'PATCH') {
        Object.assign(entry.album, body);
        return respond(200, entry.album);
      }
      if (sub === undefined && method === 'DELETE') {
        state.albums = state.albums.filter((x) => x !== entry);
        return respond(204);
      }
      if (sub === 'memories')
        return respond(200, { items: entry.memoryIds.flatMap((id) => memoryOf(id) ?? []) });
      if (sub === 'items' && method === 'POST') {
        const ids = (body.memoryIds as string[]).filter((id) => !entry.memoryIds.includes(id));
        entry.memoryIds.push(...ids);
        return respond(200, { added: ids.length });
      }
      if ((sub ?? '').startsWith('items/') && method === 'DELETE') {
        entry.memoryIds = entry.memoryIds.filter((id) => id !== (sub ?? '').slice(6));
        return respond(204);
      }
      if (sub === 'trip-proposals') return respond(200, { memoryIds: state.tripProposals });
      if (sub === 'invites' && method === 'POST')
        return respond(201, {
          id: 'i-1',
          token: 'tok-tok-tok-tok-tok-tok-tok-tok-tok',
          role: body.role,
          expiresAt: '2026-12-01T00:00:00.000Z',
        });
      if ((sub ?? '').startsWith('members/')) {
        const userId = (sub ?? '').slice(8);
        if (method === 'PATCH') {
          const member = entry.members.find((x) => x.userId === userId);
          if (member === undefined) return error(404, 'member.not_found');
          member.role = body.role as AlbumMember['role'];
          return respond(200, member);
        }
        if (method === 'DELETE') {
          entry.members = entry.members.filter((x) => x.userId !== userId);
          return respond(204);
        }
      }
    }

    // ---- presets and insights
    if (path === '/v1/presets' && method === 'GET') return respond(200, { items: state.presets });
    if ((m = path.match(/^\/v1\/presets\/([^/]+)$/))) {
      const id = m[1] ?? '';
      if (method === 'PUT') {
        const existing = state.presets.find((p) => p.id === id);
        const saved = makePreset({
          ...(existing ?? {}),
          id,
          name: String(body.name),
          experienceId: String(body.experienceId),
          intent: body.intent as Record<string, unknown>,
          live: body.live === true,
          profile: (body.profile as Preset['profile']) ?? null,
        });
        state.presets =
          existing === undefined
            ? [...state.presets, saved]
            : state.presets.map((p) => (p.id === id ? saved : p));
        return respond(200, saved);
      }
      if (method === 'DELETE') {
        state.presets = state.presets.filter((p) => p.id !== id);
        return respond(204);
      }
    }
    if (path === '/v1/insights/summary') return respond(200, state.insights);
    if (path === '/v1/insights/preset-suggestions' && method === 'GET')
      return respond(200, { items: state.suggestions });
    if (
      (m = path.match(/^\/v1\/insights\/preset-suggestions\/([^/]+)\/(dismiss|accept)$/)) &&
      method === 'POST'
    ) {
      state.suggestions = state.suggestions.filter((s) => s.patternKey !== m?.[1]);
      return m[2] === 'dismiss' ? respond(204) : respond(201, { presetId: 'p-new' });
    }
    return error(404, 'route.not_found', `No route for ${method} ${path}`);
  };

  const fetchStub = vi.fn((input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(
      typeof input === 'string' ? input : input instanceof URL ? input.href : input.url,
    );
    const method = init?.method ?? 'GET';
    const body =
      typeof init?.body === 'string' ? (JSON.parse(init.body) as Record<string, unknown>) : {};
    state.calls.push({
      method,
      path: url.pathname,
      query: url.searchParams,
      body: Object.keys(body).length === 0 ? undefined : body,
    });
    return Promise.resolve(handle(method, url.pathname, url.searchParams, body));
  });
  vi.stubGlobal('fetch', fetchStub);

  return {
    state,
    calls: (method, path) =>
      state.calls.filter(
        (call) =>
          call.method === method &&
          (typeof path === 'string' ? call.path === path : path.test(call.path)),
      ),
  };
}
