export interface Thresholds {
  lines?: number;
  branches?: number;
}

export interface PackagePolicy {
  /** Display name, usually the package path. */
  name: string;
  /** lcov report path, relative to the repository root. */
  report: string;
  /** Globs (over paths as written in the report) of files left out, for example generated code. */
  exclude: string[];
  /** Policy floors from docs/development/testing-strategy.md. They only change with the owner's approval. */
  min: Thresholds;
  /** The best coverage reached so far. Coverage may never fall below it. */
  ratchet: Thresholds;
}

export interface CoveragePolicy {
  packages: PackagePolicy[];
}

export class PolicyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PolicyError';
  }
}

function percent(value: unknown, where: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 100) {
    throw new PolicyError(`${where} must be a number between 0 and 100`);
  }
  return value;
}

function thresholds(value: unknown, where: string): Thresholds {
  if (value === undefined) {
    return {};
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new PolicyError(`${where} must be an object with optional "lines" and "branches"`);
  }
  const record = value as Record<string, unknown>;
  const result: Thresholds = {};
  const lines = percent(record.lines, `${where}.lines`);
  const branches = percent(record.branches, `${where}.branches`);
  if (lines !== undefined) {
    result.lines = lines;
  }
  if (branches !== undefined) {
    result.branches = branches;
  }
  return result;
}

/** Parses and validates coverage-policy.json, naming the offending package and field on errors. */
export function parsePolicy(text: string): CoveragePolicy {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new PolicyError(`coverage policy is not valid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
  const packages = (data as { packages?: unknown } | null)?.packages;
  if (!Array.isArray(packages) || packages.length === 0) {
    throw new PolicyError('coverage policy must contain a non-empty "packages" array');
  }
  const seen = new Set<string>();
  return {
    packages: (packages as unknown[]).map((entry, index) => {
      const where = `packages[${index}]`;
      if (typeof entry !== 'object' || entry === null || Array.isArray(entry)) {
        throw new PolicyError(`${where} must be an object`);
      }
      const record = entry as Record<string, unknown>;
      if (typeof record.name !== 'string' || record.name === '') {
        throw new PolicyError(`${where}.name must be a non-empty string`);
      }
      if (seen.has(record.name)) {
        throw new PolicyError(`${where}.name "${record.name}" is used twice`);
      }
      seen.add(record.name);
      if (typeof record.report !== 'string' || record.report === '') {
        throw new PolicyError(`${where} (${record.name}) needs a "report" path`);
      }
      const exclude = record.exclude ?? [];
      if (!Array.isArray(exclude) || exclude.some((glob) => typeof glob !== 'string')) {
        throw new PolicyError(`${where}.exclude must be an array of glob strings`);
      }
      const min = thresholds(record.min, `${where}.min`);
      if (min.lines === undefined) {
        throw new PolicyError(`${where} (${record.name}) needs min.lines`);
      }
      return {
        name: record.name,
        report: record.report,
        exclude: exclude as string[],
        min,
        ratchet: thresholds(record.ratchet, `${where}.ratchet`),
      };
    }),
  };
}

export function serializePolicy(policy: CoveragePolicy): string {
  return `${JSON.stringify(policy, null, 2)}\n`;
}
