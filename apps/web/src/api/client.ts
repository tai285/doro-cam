import type {
  Album,
  AlbumMember,
  DeviceSession,
  DownloadLink,
  InsightsReport,
  Me,
  Memory,
  MemoryPage,
  Preset,
  PresetSuggestion,
} from './types.ts';

/** Where the API lives. In development the Vite dev server and the API are different origins. */
export function apiBase(): string {
  const configured = import.meta.env.VITE_API_URL as string | undefined;
  return (configured ?? 'http://localhost:3000').replace(/\/+$/, '');
}

/** An error response in the documented envelope (docs/specs/api.md), or a network failure (status 0). */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly requestId: string | null;

  constructor(status: number, code: string, message: string, requestId: string | null = null) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.requestId = requestId;
  }
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  headers?: Record<string, string>;
}

/** Sends a credentialed JSON request and returns the parsed body (undefined for 204). */
export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${apiBase()}${path}`, {
      method: options.method ?? 'GET',
      credentials: 'include',
      headers: {
        ...(options.body === undefined ? {} : { 'content-type': 'application/json' }),
        ...options.headers,
      },
      ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
    });
  } catch {
    throw new ApiError(
      0,
      'network.unreachable',
      'Could not reach the server. Check your connection and try again.',
    );
  }
  if (response.status === 204) {
    return undefined as T;
  }
  const text = await response.text();
  let data: unknown;
  try {
    data = text === '' ? undefined : JSON.parse(text);
  } catch {
    data = undefined;
  }
  if (!response.ok) {
    const envelope =
      (data as
        | {
            error?: { code?: string; message?: string; requestId?: string };
            message?: string;
            code?: string;
          }
        | undefined) ?? {};
    // Better Auth answers with { code, message }; everything else uses the { error } envelope.
    throw new ApiError(
      response.status,
      envelope.error?.code ?? envelope.code ?? 'request.failed',
      envelope.error?.message ?? envelope.message ?? 'Something went wrong.',
      envelope.error?.requestId ?? null,
    );
  }
  return data as T;
}

function query(params: Record<string, string | number | boolean | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) {
      search.set(key, String(value));
    }
  }
  const text = search.toString();
  return text === '' ? '' : `?${text}`;
}

/** Turns a relative media path (served by the API for sanitized media) into an absolute URL. */
export function mediaHref(url: string): string {
  return url.startsWith('/') ? `${apiBase()}${url}` : url;
}

export const api = {
  // auth (Better Auth, mounted under /v1/auth)
  signUp: (input: { name: string; email: string; password: string }) =>
    request<unknown>('/v1/auth/sign-up/email', { method: 'POST', body: input }),
  signIn: (input: { email: string; password: string }) =>
    request<unknown>('/v1/auth/sign-in/email', { method: 'POST', body: input }),
  signOut: () => request<unknown>('/v1/auth/sign-out', { method: 'POST', body: {} }),
  requestPasswordReset: (email: string, redirectTo: string) =>
    request<unknown>('/v1/auth/request-password-reset', {
      method: 'POST',
      body: { email, redirectTo },
    }),
  resetPassword: (token: string, newPassword: string) =>
    request<unknown>('/v1/auth/reset-password', { method: 'POST', body: { token, newPassword } }),

  // account
  me: () => request<Me>('/v1/me'),
  sessions: () => request<{ items: DeviceSession[] }>('/v1/me/sessions'),
  revokeSession: (id: string) => request<undefined>(`/v1/me/sessions/${id}`, { method: 'DELETE' }),
  requestDeletion: (password: string) =>
    request<{ scheduledFor: string }>('/v1/me/deletion', { method: 'POST', body: { password } }),
  cancelDeletion: () => request<undefined>('/v1/me/deletion', { method: 'DELETE' }),

  // memories
  memories: (params: {
    cursor?: string;
    kind?: string;
    favorite?: boolean;
    trashed?: boolean;
    limit?: number;
  }) => request<MemoryPage>(`/v1/memories${query(params)}`),
  memory: (id: string) => request<Memory>(`/v1/memories/${id}`),
  patchMemory: (
    id: string,
    body: {
      caption?: string | null;
      favorite?: boolean;
      removeLocation?: true;
      locationShared?: boolean;
    },
  ) => request<Memory>(`/v1/memories/${id}`, { method: 'PATCH', body }),
  trashMemory: (id: string) => request<Memory>(`/v1/memories/${id}/trash`, { method: 'POST' }),
  restoreMemory: (id: string) => request<Memory>(`/v1/memories/${id}/restore`, { method: 'POST' }),
  deleteMemory: (id: string) =>
    request<{ status: 'purging' }>(`/v1/memories/${id}`, { method: 'DELETE' }),
  emptyTrash: () =>
    request<{ status: 'purging'; count: number }>('/v1/memories/trash/empty', { method: 'POST' }),
  download: (memoryId: string, assetId: string) =>
    request<DownloadLink>(`/v1/memories/${memoryId}/assets/${assetId}/download`),

  // albums
  albums: () => request<{ items: Album[] }>('/v1/albums'),
  createAlbum: (body: {
    title: string;
    description?: string | null;
    kind?: 'album' | 'trip';
    startsOn?: string | null;
    endsOn?: string | null;
  }) => request<Album>('/v1/albums', { method: 'POST', body }),
  album: (id: string) => request<{ album: Album; members: AlbumMember[] }>(`/v1/albums/${id}`),
  patchAlbum: (
    id: string,
    body: Partial<
      Pick<
        Album,
        | 'title'
        | 'description'
        | 'allowOriginalDownload'
        | 'shareLocation'
        | 'autoAddDuringTrip'
        | 'startsOn'
        | 'endsOn'
      >
    >,
  ) => request<Album>(`/v1/albums/${id}`, { method: 'PATCH', body }),
  deleteAlbum: (id: string) => request<undefined>(`/v1/albums/${id}`, { method: 'DELETE' }),
  albumMemories: (id: string) => request<{ items: Memory[] }>(`/v1/albums/${id}/memories`),
  addToAlbum: (id: string, memoryIds: string[]) =>
    request<{ added: number }>(`/v1/albums/${id}/items`, { method: 'POST', body: { memoryIds } }),
  removeFromAlbum: (id: string, memoryId: string) =>
    request<undefined>(`/v1/albums/${id}/items/${memoryId}`, { method: 'DELETE' }),
  tripProposals: (id: string) =>
    request<{ memoryIds: string[] }>(`/v1/albums/${id}/trip-proposals`),
  createInvite: (id: string, body: { role: 'editor' | 'contributor' | 'viewer'; email?: string }) =>
    request<{ id: string; token: string; role: string; expiresAt: string }>(
      `/v1/albums/${id}/invites`,
      { method: 'POST', body },
    ),
  acceptInvite: (token: string) =>
    request<{ albumId: string; role: string }>('/v1/invites/accept', {
      method: 'POST',
      body: { token },
    }),
  changeMemberRole: (id: string, userId: string, role: 'editor' | 'contributor' | 'viewer') =>
    request<AlbumMember>(`/v1/albums/${id}/members/${userId}`, { method: 'PATCH', body: { role } }),
  removeMember: (id: string, userId: string) =>
    request<undefined>(`/v1/albums/${id}/members/${userId}`, { method: 'DELETE' }),

  // presets and insights
  presets: () => request<{ items: Preset[] }>('/v1/presets'),
  savePreset: (
    id: string,
    body: {
      name: string;
      experienceId: string;
      intent: Record<string, unknown>;
      profile?: { id: string; version: number } | null;
      live?: boolean;
    },
  ) => request<Preset>(`/v1/presets/${id}`, { method: 'PUT', body }),
  deletePreset: (id: string) => request<undefined>(`/v1/presets/${id}`, { method: 'DELETE' }),
  insights: (
    params: { from?: string; to?: string; albumId?: string; experienceId?: string } = {},
  ) => request<InsightsReport>(`/v1/insights/summary${query(params)}`),
  suggestions: () => request<{ items: PresetSuggestion[] }>('/v1/insights/preset-suggestions'),
  dismissSuggestion: (key: string) =>
    request<undefined>(`/v1/insights/preset-suggestions/${key}/dismiss`, { method: 'POST' }),
  acceptSuggestion: (key: string, name?: string) =>
    request<{ presetId: string }>(`/v1/insights/preset-suggestions/${key}/accept`, {
      method: 'POST',
      body: name === undefined ? {} : { name },
    }),
};
