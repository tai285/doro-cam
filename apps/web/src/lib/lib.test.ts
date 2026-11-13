import { describe, expect, it } from 'vitest';
import { api, ApiError, apiBase, mediaHref, request } from '../api/client.ts';
import { installFakeApi } from '../test/fake-api.ts';
import {
  formatBytes,
  formatCaptured,
  formatDate,
  formatShutter,
  memoryLabel,
  percent,
  usedShare,
} from './format.ts';

describe('format', () => {
  it('[WEB-005] formats byte counts with 1024-based units', () => {
    expect(
      [0, 1, 1023, 1024, 1536, 10 * 1024, 1024 ** 2, 5 * 1024 ** 3, 1024 ** 4 * 3, 1024 ** 5].map(
        formatBytes,
      ),
    ).toEqual([
      '0 B',
      '1 B',
      '1023 B',
      '1 KB',
      '1.5 KB',
      '10 KB',
      '1 MB',
      '5 GB',
      '3 TB',
      '1024 TB',
    ]);
    expect(formatBytes(150 * 1024 ** 2)).toBe('150 MB');
    expect(formatBytes(-1)).toBe('—');
    expect(formatBytes(Number.NaN)).toBe('—');
  });

  it('[WEB-003] formats the capture time in the zone it was shot in', () => {
    expect(formatCaptured('2026-11-01T14:00:00.000Z', 'Asia/Tokyo')).toBe('1 Nov 2026, 23:00');
    expect(formatCaptured('2026-11-01T14:00:00.000Z', 'Not/AZone')).toBe('1 Nov 2026, 14:00');
    expect(formatDate('2026-11-20T00:00:00.000Z')).toMatch(/Nov 2026$/);
  });

  it('[CAM-050] formats shutter speeds as fractions, or seconds when slow', () => {
    expect(formatShutter(8_000_000)).toBe('1/125 s');
    expect(formatShutter(33_333_333)).toBe('1/30 s');
    expect(formatShutter(1_000_000_000)).toBe('1 s');
    expect(formatShutter(2_500_000_000)).toBe('2.5 s');
  });

  it('formats shares and usage', () => {
    expect(percent(0.256)).toBe('26%');
    expect(usedShare(5, 10)).toBe(0.5);
    expect(usedShare(50, 10)).toBe(1);
    expect(usedShare(5, 0)).toBe(0);
  });

  it('labels memories by caption or by kind and date', () => {
    const base = { capturedAt: '2026-11-01T09:30:00.000Z', capturedTz: 'UTC' };
    expect(memoryLabel({ ...base, caption: 'Hello', kind: 'photo' })).toBe('Hello');
    expect(memoryLabel({ ...base, caption: '   ', kind: 'photo' })).toBe(
      'Photo from 1 Nov 2026, 09:30',
    );
    expect(memoryLabel({ ...base, caption: null, kind: 'motion' })).toBe(
      'Motion memory from 1 Nov 2026, 09:30',
    );
    expect(memoryLabel({ ...base, caption: null, kind: 'video' })).toBe(
      'Video from 1 Nov 2026, 09:30',
    );
  });
});

describe('api client', () => {
  it('uses the configured API origin and turns relative media paths into absolute URLs', () => {
    expect(apiBase()).toBe('http://localhost:3000');
    expect(mediaHref('/v1/x')).toBe('http://localhost:3000/v1/x');
    expect(mediaHref('https://cdn.test/a.jpg')).toBe('https://cdn.test/a.jpg');
  });

  it('sends credentials with every request and JSON bodies with a content type', async () => {
    const fake = installFakeApi({ signedIn: false });
    await api.signIn({ email: 'a@b.test', password: 'x' }).catch(() => undefined);
    const call = (globalThis.fetch as unknown as { mock: { calls: Array<[string, RequestInit]> } })
      .mock.calls[0];
    expect(call?.[0]).toBe('http://localhost:3000/v1/auth/sign-in/email');
    expect(call?.[1]).toMatchObject({
      method: 'POST',
      credentials: 'include',
      headers: { 'content-type': 'application/json' },
    });
    expect(fake.state.calls).toHaveLength(1);
  });

  it('maps the documented error envelope to ApiError with code, message and request id', async () => {
    installFakeApi();
    const error = await request('/v1/memories/missing').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({
      status: 404,
      code: 'memory.not_found',
      message: 'Memory not found.',
      requestId: 'req-1',
    });
  });

  it('maps Better Auth error bodies and non-JSON failures', async () => {
    installFakeApi({ signedIn: false });
    expect(
      await api.signIn({ email: 'a@b.test', password: 'nope' }).catch((e: unknown) => e),
    ).toMatchObject({ status: 401, code: 'INVALID_EMAIL_OR_PASSWORD' });
    const original = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(new Response('<html>bad gateway</html>', { status: 502 }));
    expect(await request('/anything').catch((e: unknown) => e)).toMatchObject({
      status: 502,
      code: 'request.failed',
      message: 'Something went wrong.',
    });
    globalThis.fetch = original;
  });

  it('reports an unreachable server as status 0', async () => {
    const original = globalThis.fetch;
    globalThis.fetch = () => Promise.reject(new TypeError('Failed to fetch'));
    expect(await request('/v1/me').catch((e: unknown) => e)).toMatchObject({
      status: 0,
      code: 'network.unreachable',
    });
    globalThis.fetch = original;
  });

  it('returns undefined for 204 and builds query strings without empty values', async () => {
    const fake = installFakeApi();
    await expect(api.cancelDeletion()).resolves.toBeUndefined();
    await api.memories({ limit: 5, trashed: false });
    expect(fake.calls('GET', '/v1/memories')[0]?.query.toString()).toBe('limit=5&trashed=false');
    await api.insights();
    expect(fake.calls('GET', '/v1/insights/summary')[0]?.query.toString()).toBe('');
  });
});
