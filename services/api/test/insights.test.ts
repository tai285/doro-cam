import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  apertureBucket,
  computeInsights,
  findPresetSuggestions,
  focalBucket,
  type InsightRow,
  isoBucket,
  localHour,
  shutterBucket,
  timeOfDayBucket,
} from '../src/modules/insights/compute.ts';
import { createUser, memoryBody, startStack, type Stack, type TestUser } from './helpers/stack.ts';

const row = (overrides: Partial<InsightRow> = {}): InsightRow => ({
  capturedAt: new Date('2026-05-10T04:00:00.000Z'),
  capturedTz: 'Asia/Kuala_Lumpur',
  experienceId: 'mirrorless',
  profileId: 'natural',
  scenario: 'street',
  lensKind: 'wide',
  focalLength35mm: 26,
  iso: 200,
  exposureTimeNs: 8_000_000,
  aperture: 1.8,
  ...overrides,
});

describe('insight buckets', () => {
  it('[ANL-001] focal length buckets cover the boundaries', () => {
    expect([12, 23.9, 24, 35, 36, 50, 51, 85, 86, 200].map(focalBucket)).toEqual([
      '<24 mm', '<24 mm', '24-35 mm', '24-35 mm', '36-50 mm', '36-50 mm', '51-85 mm', '51-85 mm', '>85 mm', '>85 mm',
    ]);
  });
  it('[ANL-003] ISO, shutter and aperture buckets cover the boundaries', () => {
    expect([50, 100, 101, 400, 401, 1600, 1601, 6400, 6401].map(isoBucket)).toEqual(['≤100', '≤100', '101-400', '101-400', '401-1600', '401-1600', '1601-6400', '1601-6400', '>6400']);
    expect([1e9, 1e9 / 30 + 1, 1e9 / 125 + 1, 1e9 / 500 + 1, 1e6].map(shutterBucket)).toEqual([
      'slower than 1/30', 'slower than 1/30', '1/30-1/125', '1/126-1/500', 'faster than 1/500',
    ]);
    expect([1, 1.9, 2, 2.8, 3, 5.6, 5.7, 8].map(apertureBucket)).toEqual(['f/1.0-1.9', 'f/1.0-1.9', 'f/2.0-2.9', 'f/2.0-2.9', 'f/3.0-5.6', 'f/3.0-5.6', 'f/5.7+', 'f/5.7+']);
  });
  it('[ANL-003] time of day uses the hour in the zone the photo was shot in', () => {
    expect(localHour(row({ capturedAt: new Date('2026-05-10T14:00:00Z'), capturedTz: 'Asia/Tokyo' }))).toBe(23);
    expect(localHour(row({ capturedAt: new Date('2026-05-10T14:00:00Z'), capturedTz: 'Not/AZone' }))).toBe(14);
    expect([0, 4, 5, 10, 11, 15, 16, 21, 22, 23].map(timeOfDayBucket)).toEqual([
      'Night (22-5)', 'Night (22-5)', 'Morning (5-11)', 'Morning (5-11)', 'Midday (11-16)', 'Midday (11-16)', 'Evening (16-22)', 'Evening (16-22)', 'Night (22-5)', 'Night (22-5)',
    ]);
  });
});

describe('computeInsights', () => {
  it('[ANL-001..005] returns empty distributions and no insights for no data', () => {
    const report = computeInsights([]);
    expect(report.total).toBe(0);
    expect(report.focalLength).toEqual({ total: 0, buckets: [] });
    expect(report.trend).toEqual([]);
    expect(report.insights).toEqual([]);
  });

  it('[ANL-001][ANL-002] counts distributions and shares, ignoring missing values', () => {
    const rows = [row(), row(), row({ focalLength35mm: 70, profileId: 'warm-film', lensKind: 'tele' }), row({ focalLength35mm: null, iso: null, aperture: null, exposureTimeNs: null, lensKind: null, profileId: null })];
    const report = computeInsights(rows);
    expect(report.total).toBe(4);
    expect(report.focalLength.total).toBe(3);
    expect(report.focalLength.buckets).toEqual([
      { label: '24-35 mm', count: 2, share: 2 / 3 },
      { label: '51-85 mm', count: 1, share: 1 / 3 },
    ]);
    expect(report.lens.buckets.map((b) => [b.label, b.count])).toEqual([['wide', 2], ['tele', 1]]);
    expect(report.profile.buckets[0]).toMatchObject({ label: 'natural', count: 2 });
    expect(report.experience.buckets).toEqual([{ label: 'mirrorless', count: 4, share: 1 }]);
  });

  it('[ANL-004] builds a month-by-month trend in order', () => {
    const report = computeInsights([
      row({ capturedAt: new Date('2026-03-02T00:00:00Z') }),
      row({ capturedAt: new Date('2026-01-20T00:00:00Z') }),
      row({ capturedAt: new Date('2026-03-15T00:00:00Z') }),
    ]);
    expect(report.trend).toEqual([{ month: '2026-01', count: 1 }, { month: '2026-03', count: 2 }]);
  });

  it('[ANL-005] writes plain-language insights that carry the numbers they are based on, only with enough data', () => {
    expect(computeInsights([row(), row(), row(), row()]).insights).toEqual([]); // under 5 samples: no claims
    const report = computeInsights(Array.from({ length: 8 }, (_, i) => row({ profileId: i < 6 ? 'natural' : 'warm-film' })));
    const focal = report.insights.find((i) => i.id === 'favorite-focal-length');
    expect(focal).toEqual({
      id: 'favorite-focal-length',
      text: 'You shoot most at 24-35 mm (100% of your photos).',
      basedOn: { focalLength: '24-35 mm', count: 8, of: 8 },
    });
    expect(report.insights.find((i) => i.id === 'favorite-profile')?.text).toBe('Your most used profile is natural (75%).');
    expect(report.insights.find((i) => i.id === 'typical-iso')?.basedOn).toMatchObject({ count: 8, of: 8 });
    expect(report.insights.find((i) => i.id === 'favorite-time')?.text).toContain('midday');
  });
});

describe('findPresetSuggestions', () => {
  it('[PRE-001] suggests only combinations that repeat enough and cover enough of the captures', () => {
    const street = Array.from({ length: 6 }, () => row());
    const oneOff = [row({ experienceId: 'instant', profileId: 'instant-warm', scenario: null })];
    const suggestions = findPresetSuggestions([...street, ...oneOff], new Set());
    expect(suggestions).toHaveLength(1);
    expect(suggestions[0]).toMatchObject({ experienceId: 'mirrorless', profileId: 'natural', scenario: 'street', lensKind: 'wide', supportingCount: 6, of: 7 });
    expect(findPresetSuggestions(street.slice(0, 4), new Set())).toEqual([]); // below the minimum count
    const diluted = [...street, ...Array.from({ length: 50 }, (_, i) => row({ scenario: `s${i}` }))];
    expect(findPresetSuggestions(diluted, new Set())).toEqual([]); // under the minimum share
  });

  it('[PRE-002] explains the pattern with the numbers behind it', () => {
    const rows = Array.from({ length: 10 }, () => row());
    const [suggestion] = findPresetSuggestions(rows, new Set());
    expect(suggestion!.explanation).toBe('10 of your 10 photos (100%) were taken with mirrorless, natural, street, wide, usually at ISO 101-400 and shutter 1/126-1/500.');
    expect(suggestion).toMatchObject({ isoRange: '101-400', shutterRange: '1/126-1/500' });
  });

  it('[PRE-002] leaves out ranges that are not clearly typical', () => {
    const rows = [...Array.from({ length: 3 }, () => row({ iso: 100 })), ...Array.from({ length: 3 }, () => row({ iso: 3200 }))];
    const [suggestion] = findPresetSuggestions(rows, new Set());
    expect(suggestion!.isoRange).toBeNull();
  });

  it('[PRE-003] never re-offers a dismissed pattern', () => {
    const rows = Array.from({ length: 8 }, () => row());
    const [first] = findPresetSuggestions(rows, new Set());
    expect(findPresetSuggestions(rows, new Set([first!.patternKey]))).toEqual([]);
  });

  it('[PRE-001] orders by support and is deterministic', () => {
    const a = Array.from({ length: 5 }, () => row({ scenario: 'a' }));
    const b = Array.from({ length: 7 }, () => row({ scenario: 'b' }));
    const result = findPresetSuggestions([...a, ...b], new Set());
    expect(result.map((s) => s.scenario)).toEqual(['b', 'a']);
    expect(findPresetSuggestions([...b, ...a], new Set()).map((s) => s.patternKey)).toEqual(result.map((s) => s.patternKey));
  });
});

describe('insights API', () => {
  let stack: Stack;
  let alice: TestUser;
  let bob: TestUser;

  const add = async (user: TestUser, overrides: Record<string, unknown> = {}) =>
    stack.app.inject({ method: 'PUT', url: `/v1/memories/${randomUUID()}`, headers: user.headers, payload: memoryBody(overrides) });

  beforeAll(async () => {
    stack = await startStack();
    alice = await createUser(stack, 'Alice');
    bob = await createUser(stack, 'Bob');
    for (let i = 0; i < 8; i += 1) {
      await add(alice, { capturedAt: `2026-04-${10 + i}T04:00:00.000Z` });
    }
    await add(alice, { capturedAt: '2026-06-01T04:00:00.000Z', experienceId: 'instant', profile: { id: 'instant-warm', version: 1 }, capture: { lensKind: 'tele', focalLength35mmEq: 70, isoApplied: 800 } });
    await add(bob, { experienceId: 'film' });
  });
  afterAll(async () => {
    await stack.close();
  });

  it('[WEB-009][ANL-001] summarizes only the caller’s own Memories', async () => {
    const response = await stack.app.inject({ method: 'GET', url: '/v1/insights/summary', headers: alice.headers });
    expect(response.statusCode).toBe(200);
    const report = response.json() as ReturnType<typeof computeInsights>;
    expect(report.total).toBe(9);
    expect(report.experience.buckets.map((b) => b.label)).toEqual(['mirrorless', 'instant']);
    expect(report.trend).toEqual([{ month: '2026-04', count: 8 }, { month: '2026-06', count: 1 }]);
    const bobReport = (await stack.app.inject({ method: 'GET', url: '/v1/insights/summary', headers: bob.headers })).json() as typeof report;
    expect(bobReport.total).toBe(1);
  });

  it('[ANL-002] filters by time range and Experience', async () => {
    const ranged = (await stack.app.inject({ method: 'GET', url: '/v1/insights/summary?from=2026-05-01T00:00:00Z&to=2026-12-31T00:00:00Z', headers: alice.headers })).json() as { total: number };
    expect(ranged.total).toBe(1);
    const byExperience = (await stack.app.inject({ method: 'GET', url: '/v1/insights/summary?experienceId=mirrorless', headers: alice.headers })).json() as { total: number };
    expect(byExperience.total).toBe(8);
  });

  it('[ANL-002] filters by album and refuses an album the caller is not in', async () => {
    const album = (await stack.app.inject({ method: 'POST', url: '/v1/albums', headers: alice.headers, payload: { title: 'A' } })).json() as { id: string };
    const empty = (await stack.app.inject({ method: 'GET', url: `/v1/insights/summary?albumId=${album.id}`, headers: alice.headers })).json() as { total: number };
    expect(empty.total).toBe(0);
    const some = (await stack.database.pool.query('select id from memories where owner_id = $1 limit 3', [alice.id])).rows.map((r: { id: string }) => r.id);
    await stack.app.inject({ method: 'POST', url: `/v1/albums/${album.id}/items`, headers: alice.headers, payload: { memoryIds: some } });
    const filtered = (await stack.app.inject({ method: 'GET', url: `/v1/insights/summary?albumId=${album.id}`, headers: alice.headers })).json() as { total: number };
    expect(filtered.total).toBe(3);
    expect((await stack.app.inject({ method: 'GET', url: `/v1/insights/summary?albumId=${album.id}`, headers: bob.headers })).statusCode).toBe(404);
  });

  it('[PRE-002] lists a suggestion with its explanation; [PRE-003] dismissal is remembered', async () => {
    const list = (await stack.app.inject({ method: 'GET', url: '/v1/insights/preset-suggestions', headers: alice.headers })).json() as { items: Array<{ patternKey: string; explanation: string; supportingCount: number }> };
    expect(list.items).toHaveLength(1);
    expect(list.items[0]!.supportingCount).toBe(8);
    expect(list.items[0]!.explanation).toMatch(/^8 of your 9 photos \(89%\)/);

    const dismissed = await stack.app.inject({ method: 'POST', url: `/v1/insights/preset-suggestions/${list.items[0]!.patternKey}/dismiss`, headers: alice.headers });
    expect(dismissed.statusCode).toBe(204);
    expect((await stack.app.inject({ method: 'POST', url: `/v1/insights/preset-suggestions/${list.items[0]!.patternKey}/dismiss`, headers: alice.headers })).statusCode).toBe(204);
    const after = (await stack.app.inject({ method: 'GET', url: '/v1/insights/preset-suggestions', headers: alice.headers })).json() as { items: unknown[] };
    expect(after.items).toEqual([]);
  });

  it('[PRE-003] accepting creates an editable preset marked as suggested; it is never applied automatically', async () => {
    const carol = await createUser(stack, 'Carol');
    for (let i = 0; i < 6; i += 1) {
      await add(carol);
    }
    expect(((await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: carol.headers })).json() as { items: unknown[] }).items).toEqual([]);
    const [suggestion] = ((await stack.app.inject({ method: 'GET', url: '/v1/insights/preset-suggestions', headers: carol.headers })).json() as { items: Array<{ patternKey: string }> }).items;
    const accepted = await stack.app.inject({ method: 'POST', url: `/v1/insights/preset-suggestions/${suggestion!.patternKey}/accept`, headers: carol.headers, payload: { name: 'My street look' } });
    expect(accepted.statusCode).toBe(201);
    const presets = ((await stack.app.inject({ method: 'GET', url: '/v1/presets', headers: carol.headers })).json() as { items: Array<{ name: string; source: string; experienceId: string; intent: Record<string, unknown> }> }).items;
    expect(presets).toHaveLength(1);
    expect(presets[0]).toMatchObject({ name: 'My street look', source: 'suggested', experienceId: 'mirrorless', intent: { scenario: 'street', lensKind: 'wide' } });
    expect(((await stack.app.inject({ method: 'GET', url: '/v1/insights/preset-suggestions', headers: carol.headers })).json() as { items: unknown[] }).items).toEqual([]);
    const unknown = await stack.app.inject({ method: 'POST', url: `/v1/insights/preset-suggestions/${'0'.repeat(24)}/accept`, headers: carol.headers, payload: {} });
    expect(unknown.statusCode).toBe(404);
  });

  it('[PRE-003] suggestions cannot be dismissed or accepted across users, and keys are validated', async () => {
    const [suggestion] = ((await stack.app.inject({ method: 'GET', url: '/v1/insights/preset-suggestions', headers: bob.headers })).json() as { items: unknown[] }).items;
    expect(suggestion).toBeUndefined();
    expect((await stack.app.inject({ method: 'POST', url: '/v1/insights/preset-suggestions/not-a-key/dismiss', headers: bob.headers })).statusCode).toBe(400);
  });
});
