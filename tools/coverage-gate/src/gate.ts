import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { type CoverageSummary, parseLcov, summarize } from './lcov.ts';
import type { CoveragePolicy, PackagePolicy, Thresholds } from './policy.ts';

/** Rounding noise between runs must not fail the ratchet. */
export const RATCHET_TOLERANCE = 0.01;

export interface PackageResult {
  name: string;
  summary: CoverageSummary | null;
  errors: string[];
  /** The ratchet this run would record: never lower than the current one. */
  nextRatchet: Thresholds;
}

const fmt = (value: number): string => `${value.toFixed(2)}%`;

/** Rounds down to two decimals so a recorded ratchet can never exceed what was actually reached. */
function floor2(value: number): number {
  return Math.floor(value * 100 + 1e-9) / 100;
}

function compare(
  kind: 'lines' | 'branches',
  actual: number | null,
  policy: PackagePolicy,
  errors: string[],
): number | null {
  const floor = policy.min[kind];
  const ratchet = policy.ratchet[kind];
  if (actual === null) {
    if (floor !== undefined || ratchet !== undefined) {
      errors.push(`no ${kind} were measured (the report is empty, or every file is excluded)`);
    }
    return null;
  }
  if (floor !== undefined && actual < floor) {
    errors.push(`${kind} coverage ${fmt(actual)} is below the policy floor ${fmt(floor)}`);
  }
  if (ratchet !== undefined && actual + RATCHET_TOLERANCE < ratchet) {
    errors.push(`${kind} coverage ${fmt(actual)} fell below the recorded ${fmt(ratchet)} (coverage may not decrease)`);
  }
  return actual;
}

/** Evaluates one package's summary against its floors and ratchet. */
export function evaluatePackage(policy: PackagePolicy, summary: CoverageSummary): PackageResult {
  const errors: string[] = [];
  const lines = compare('lines', summary.lines.percent, policy, errors);
  const branches = compare('branches', summary.branches.percent, policy, errors);

  const nextRatchet: Thresholds = { ...policy.ratchet };
  if (lines !== null && errors.length === 0) {
    nextRatchet.lines = Math.max(policy.ratchet.lines ?? 0, floor2(lines));
  }
  if (branches !== null && errors.length === 0 && policy.min.branches !== undefined) {
    nextRatchet.branches = Math.max(policy.ratchet.branches ?? 0, floor2(branches));
  }
  return { name: policy.name, summary, errors, nextRatchet };
}

export interface RunOptions {
  /** Only check these package names. */
  only?: readonly string[];
}

/** Reads every selected package's report and evaluates it. */
export function runGate(root: string, policy: CoveragePolicy, options: RunOptions = {}): PackageResult[] {
  const selected = policy.packages.filter((pkg) => options.only === undefined || options.only.includes(pkg.name));
  const unknown = (options.only ?? []).filter((name) => !policy.packages.some((pkg) => pkg.name === name));
  const results: PackageResult[] = unknown.map((name) => ({
    name,
    summary: null,
    errors: [`is not in the coverage policy`],
    nextRatchet: {},
  }));
  for (const pkg of selected) {
    const reportPath = path.join(root, pkg.report);
    if (!existsSync(reportPath)) {
      results.push({
        name: pkg.name,
        summary: null,
        errors: [`coverage report not found at ${pkg.report} (run that package's tests with coverage first)`],
        nextRatchet: { ...pkg.ratchet },
      });
      continue;
    }
    const summary = summarize(parseLcov(readFileSync(reportPath, 'utf8')), pkg.exclude);
    results.push(evaluatePackage(pkg, summary));
  }
  return results;
}

/** The policy with ratchets raised to what this run reached. Ratchets only ever go up. */
export function applyRatchet(policy: CoveragePolicy, results: readonly PackageResult[]): CoveragePolicy {
  return {
    packages: policy.packages.map((pkg) => {
      const result = results.find((r) => r.name === pkg.name);
      if (result === undefined || result.errors.length > 0) {
        return pkg;
      }
      const ratchet: Thresholds = { ...pkg.ratchet };
      for (const kind of ['lines', 'branches'] as const) {
        const next = result.nextRatchet[kind];
        if (next !== undefined && next > (pkg.ratchet[kind] ?? 0)) {
          ratchet[kind] = next;
        }
      }
      return { ...pkg, ratchet };
    }),
  };
}
