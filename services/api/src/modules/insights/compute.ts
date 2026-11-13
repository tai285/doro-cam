import { createHash } from 'node:crypto';

/** The columns analytics needs. Extracted from capture metadata when a Memory is registered (ADR-0007). */
export interface InsightRow {
  capturedAt: Date;
  capturedTz: string;
  experienceId: string;
  profileId: string | null;
  scenario: string | null;
  lensKind: string | null;
  focalLength35mm: number | null;
  iso: number | null;
  exposureTimeNs: number | null;
  aperture: number | null;
}

export interface Bucket {
  label: string;
  count: number;
  share: number;
}

export interface Distribution {
  total: number;
  buckets: Bucket[];
}

function distribution(values: ReadonlyArray<string | null>, order?: readonly string[]): Distribution {
  const counts = new Map<string, number>();
  let total = 0;
  for (const value of values) {
    if (value === null) {
      continue;
    }
    total += 1;
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  const labels = order === undefined ? [...counts.keys()].sort((a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0) || a.localeCompare(b)) : order.filter((label) => counts.has(label));
  return {
    total,
    buckets: labels.map((label) => ({ label, count: counts.get(label) ?? 0, share: total === 0 ? 0 : (counts.get(label) ?? 0) / total })),
  };
}

const FOCAL_ORDER = ['<24 mm', '24-35 mm', '36-50 mm', '51-85 mm', '>85 mm'] as const;
const ISO_ORDER = ['≤100', '101-400', '401-1600', '1601-6400', '>6400'] as const;
const SHUTTER_ORDER = ['slower than 1/30', '1/30-1/125', '1/126-1/500', 'faster than 1/500'] as const;
const APERTURE_ORDER = ['f/1.0-1.9', 'f/2.0-2.9', 'f/3.0-5.6', 'f/5.7+'] as const;
const TIME_ORDER = ['Night (22-5)', 'Morning (5-11)', 'Midday (11-16)', 'Evening (16-22)'] as const;

export function focalBucket(mm: number): (typeof FOCAL_ORDER)[number] {
  if (mm < 24) return FOCAL_ORDER[0];
  if (mm <= 35) return FOCAL_ORDER[1];
  if (mm <= 50) return FOCAL_ORDER[2];
  if (mm <= 85) return FOCAL_ORDER[3];
  return FOCAL_ORDER[4];
}

export function isoBucket(iso: number): (typeof ISO_ORDER)[number] {
  if (iso <= 100) return ISO_ORDER[0];
  if (iso <= 400) return ISO_ORDER[1];
  if (iso <= 1600) return ISO_ORDER[2];
  if (iso <= 6400) return ISO_ORDER[3];
  return ISO_ORDER[4];
}

export function shutterBucket(exposureNs: number): (typeof SHUTTER_ORDER)[number] {
  const seconds = exposureNs / 1e9;
  if (seconds > 1 / 30) return SHUTTER_ORDER[0];
  if (seconds > 1 / 125) return SHUTTER_ORDER[1];
  if (seconds > 1 / 500) return SHUTTER_ORDER[2];
  return SHUTTER_ORDER[3];
}

export function apertureBucket(f: number): (typeof APERTURE_ORDER)[number] {
  if (f < 2) return APERTURE_ORDER[0];
  if (f < 3) return APERTURE_ORDER[1];
  if (f <= 5.6) return APERTURE_ORDER[2];
  return APERTURE_ORDER[3];
}

/** Local hour of the capture in the time zone it was shot in ("shot at 21:00 local"). */
export function localHour(row: Pick<InsightRow, 'capturedAt' | 'capturedTz'>): number {
  try {
    const hour = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', hourCycle: 'h23', timeZone: row.capturedTz }).format(row.capturedAt);
    return Number(hour);
  } catch {
    return row.capturedAt.getUTCHours();
  }
}

export function timeOfDayBucket(hour: number): (typeof TIME_ORDER)[number] {
  if (hour >= 22 || hour < 5) return TIME_ORDER[0];
  if (hour < 11) return TIME_ORDER[1];
  if (hour < 16) return TIME_ORDER[2];
  return TIME_ORDER[3];
}

export interface InsightsReport {
  total: number;
  focalLength: Distribution;
  lens: Distribution;
  profile: Distribution;
  experience: Distribution;
  iso: Distribution;
  shutter: Distribution;
  aperture: Distribution;
  timeOfDay: Distribution;
  trend: Array<{ month: string; count: number }>;
  /** Plain-language findings. Each one carries the numbers it is based on (ANL-005). */
  insights: Array<{ id: string; text: string; basedOn: Record<string, number | string> }>;
}

/** Aggregates a set of Memories into distributions, a monthly trend and deterministic insights (ANL-001..ANL-005). */
export function computeInsights(rows: readonly InsightRow[]): InsightsReport {
  const focalLength = distribution(rows.map((r) => (r.focalLength35mm === null ? null : focalBucket(r.focalLength35mm))), FOCAL_ORDER);
  const lens = distribution(rows.map((r) => r.lensKind));
  const profile = distribution(rows.map((r) => r.profileId));
  const experience = distribution(rows.map((r) => r.experienceId));
  const iso = distribution(rows.map((r) => (r.iso === null ? null : isoBucket(r.iso))), ISO_ORDER);
  const shutter = distribution(rows.map((r) => (r.exposureTimeNs === null ? null : shutterBucket(r.exposureTimeNs))), SHUTTER_ORDER);
  const aperture = distribution(rows.map((r) => (r.aperture === null ? null : apertureBucket(r.aperture))), APERTURE_ORDER);
  const timeOfDay = distribution(rows.map((r) => timeOfDayBucket(localHour(r))), TIME_ORDER);

  const byMonth = new Map<string, number>();
  for (const row of rows) {
    const month = row.capturedAt.toISOString().slice(0, 7);
    byMonth.set(month, (byMonth.get(month) ?? 0) + 1);
  }
  const trend = [...byMonth.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([month, count]) => ({ month, count }));

  const insights: InsightsReport['insights'] = [];
  const top = (name: string, d: Distribution, id: string, phrase: (label: string, percent: number) => string) => {
    const first = d.buckets.reduce<Bucket | undefined>((best, b) => (best === undefined || b.count > best.count ? b : best), undefined);
    if (first !== undefined && d.total >= 5) {
      insights.push({
        id,
        text: phrase(first.label, Math.round(first.share * 100)),
        basedOn: { [name]: first.label, count: first.count, of: d.total },
      });
    }
  };
  top('focalLength', focalLength, 'favorite-focal-length', (label, pct) => `You shoot most at ${label} (${pct}% of your photos).`);
  top('profile', profile, 'favorite-profile', (label, pct) => `Your most used profile is ${label} (${pct}%).`);
  top('timeOfDay', timeOfDay, 'favorite-time', (label, pct) => `You take most photos in the ${label.toLowerCase()} (${pct}%).`);
  top('iso', iso, 'typical-iso', (label, pct) => `Your typical ISO range is ${label} (${pct}%).`);

  return { total: rows.length, focalLength, lens, profile, experience, iso, shutter, aperture, timeOfDay, trend, insights };
}

export interface PresetSuggestion {
  patternKey: string;
  title: string;
  explanation: string;
  experienceId: string;
  profileId: string | null;
  scenario: string | null;
  lensKind: string | null;
  isoRange: string | null;
  shutterRange: string | null;
  supportingCount: number;
  of: number;
  share: number;
}

export const MIN_PATTERN_COUNT = 5;
export const MIN_PATTERN_SHARE = 0.15;

/**
 * Finds recurring combinations of Experience, profile, scenario and lens (PRE-001). A combination is
 * suggested only when it repeats at least MIN_PATTERN_COUNT times and covers at least MIN_PATTERN_SHARE
 * of the user's captures, and the explanation states those numbers (PRE-002). Nothing is applied automatically.
 */
export function findPresetSuggestions(rows: readonly InsightRow[], dismissedKeys: ReadonlySet<string>): PresetSuggestion[] {
  const groups = new Map<string, InsightRow[]>();
  for (const row of rows) {
    const key = [row.experienceId, row.profileId ?? '-', row.scenario ?? '-', row.lensKind ?? '-'].join('|');
    groups.set(key, [...(groups.get(key) ?? []), row]);
  }
  const suggestions: PresetSuggestion[] = [];
  for (const [key, members] of groups) {
    const share = rows.length === 0 ? 0 : members.length / rows.length;
    if (members.length < MIN_PATTERN_COUNT || share < MIN_PATTERN_SHARE) {
      continue;
    }
    const patternKey = createHash('sha256').update(key).digest('hex').slice(0, 24);
    if (dismissedKeys.has(patternKey)) {
      continue;
    }
    const first = members[0] as InsightRow;
    const common = (pick: (row: InsightRow) => string | null): string | null => {
      const d = distribution(members.map(pick));
      const best = d.buckets[0];
      return best !== undefined && best.share >= 0.6 ? best.label : null;
    };
    const isoRange = common((r) => (r.iso === null ? null : isoBucket(r.iso)));
    const shutterRange = common((r) => (r.exposureTimeNs === null ? null : shutterBucket(r.exposureTimeNs)));
    const pieces = [first.experienceId, first.profileId, first.scenario, first.lensKind].filter((piece): piece is string => piece !== null);
    suggestions.push({
      patternKey,
      title: pieces.join(' · '),
      explanation: `${members.length} of your ${rows.length} photos (${Math.round(share * 100)}%) were taken with ${pieces.join(', ')}${isoRange === null ? '' : `, usually at ISO ${isoRange}`}${shutterRange === null ? '' : ` and shutter ${shutterRange}`}.`,
      experienceId: first.experienceId,
      profileId: first.profileId,
      scenario: first.scenario,
      lensKind: first.lensKind,
      isoRange,
      shutterRange,
      supportingCount: members.length,
      of: rows.length,
      share,
    });
  }
  return suggestions.sort((a, b) => b.supportingCount - a.supportingCount || a.patternKey.localeCompare(b.patternKey));
}
