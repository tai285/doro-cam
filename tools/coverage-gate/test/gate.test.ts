import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { applyRatchet, evaluatePackage, RATCHET_TOLERANCE, runGate } from '../src/gate.ts';
import type { CoverageSummary } from '../src/lcov.ts';
import { parsePolicy, PolicyError, type PackagePolicy, serializePolicy } from '../src/policy.ts';

const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src', 'cli.ts');
const tempDirs: string[] = [];

after(() => {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
  }
});

const summary = (lines: number | null, branches: number | null = null): CoverageSummary => ({
  files: 1,
  lines: { found: 100, hit: lines ?? 0, percent: lines },
  branches: { found: branches === null ? 0 : 100, hit: branches ?? 0, percent: branches },
});

const pkg = (overrides: Partial<PackagePolicy> = {}): PackagePolicy => ({
  name: 'apps/demo',
  report: 'apps/demo/coverage/lcov.info',
  exclude: [],
  min: { lines: 90 },
  ratchet: {},
  ...overrides,
});

describe('parsePolicy', () => {
  const valid = {
    packages: [
      {
        name: 'a',
        report: 'a/lcov.info',
        exclude: ['**/*.g.dart'],
        min: { lines: 95, branches: 90 },
        ratchet: { lines: 99.5 },
      },
    ],
  };

  it('reads a valid policy', () => {
    assert.deepEqual(parsePolicy(JSON.stringify(valid)), valid);
  });

  it('defaults exclude and ratchet', () => {
    const parsed = parsePolicy(JSON.stringify({ packages: [{ name: 'a', report: 'r', min: { lines: 80 } }] }));
    assert.deepEqual(parsed.packages[0], { name: 'a', report: 'r', exclude: [], min: { lines: 80 }, ratchet: {} });
  });

  const invalid: ReadonlyArray<[string, unknown, RegExp]> = [
    ['no packages', {}, /non-empty "packages"/],
    ['an empty package list', { packages: [] }, /non-empty "packages"/],
    ['a non-object package', { packages: [1] }, /packages\[0\] must be an object/],
    ['a missing name', { packages: [{ report: 'r', min: { lines: 1 } }] }, /name must be a non-empty string/],
    ['a missing report', { packages: [{ name: 'a', min: { lines: 1 } }] }, /needs a "report" path/],
    ['a missing min.lines', { packages: [{ name: 'a', report: 'r' }] }, /needs min\.lines/],
    ['min.lines out of range', { packages: [{ name: 'a', report: 'r', min: { lines: 101 } }] }, /min\.lines must be a number between 0 and 100/],
    ['a negative ratchet', { packages: [{ name: 'a', report: 'r', min: { lines: 1 }, ratchet: { branches: -1 } }] }, /ratchet\.branches must be/],
    ['a non-numeric threshold', { packages: [{ name: 'a', report: 'r', min: { lines: '90' } }] }, /min\.lines must be a number/],
    ['thresholds that are not an object', { packages: [{ name: 'a', report: 'r', min: 90 }] }, /min must be an object/],
    ['a bad exclude list', { packages: [{ name: 'a', report: 'r', min: { lines: 1 }, exclude: [1] }] }, /exclude must be an array of glob strings/],
    ['duplicate names', { packages: [{ name: 'a', report: 'r', min: { lines: 1 } }, { name: 'a', report: 'r2', min: { lines: 1 } }] }, /used twice/],
  ];
  for (const [name, data, message] of invalid) {
    it(`rejects ${name}`, () => {
      assert.throws(() => parsePolicy(JSON.stringify(data)), (error: unknown) => {
        assert.ok(error instanceof PolicyError);
        assert.match(error.message, message);
        return true;
      });
    });
  }

  it('rejects text that is not JSON', () => {
    assert.throws(() => parsePolicy('{oops'), /not valid JSON/);
  });

  it('serializes with a trailing newline and round-trips', () => {
    const text = serializePolicy(parsePolicy(JSON.stringify(valid)));
    assert.ok(text.endsWith('}\n'));
    assert.deepEqual(parsePolicy(text), valid);
  });
});

describe('evaluatePackage', () => {
  it('[NFR-014] passes at or above the policy floor', () => {
    assert.deepEqual(evaluatePackage(pkg(), summary(90)).errors, []);
    assert.deepEqual(evaluatePackage(pkg(), summary(100)).errors, []);
  });

  it('[NFR-014] fails below the policy floor and says by how much it is missing', () => {
    const { errors } = evaluatePackage(pkg(), summary(89.99));
    assert.deepEqual(errors, ['lines coverage 89.99% is below the policy floor 90.00%']);
  });

  it('[NFR-014] fails when branch coverage is below its floor', () => {
    const { errors } = evaluatePackage(pkg({ min: { lines: 90, branches: 90 } }), summary(95, 80));
    assert.deepEqual(errors, ['branches coverage 80.00% is below the policy floor 90.00%']);
  });

  it('reports every failing kind at once', () => {
    const { errors } = evaluatePackage(pkg({ min: { lines: 90, branches: 90 } }), summary(50, 50));
    assert.equal(errors.length, 2);
  });

  it('[NFR-014] the ratchet fails when coverage drops below the recorded value', () => {
    const { errors } = evaluatePackage(pkg({ ratchet: { lines: 98.5 } }), summary(97));
    assert.deepEqual(errors, ['lines coverage 97.00% fell below the recorded 98.50% (coverage may not decrease)']);
  });

  it('the ratchet tolerates rounding noise up to the tolerance', () => {
    const just = evaluatePackage(pkg({ ratchet: { lines: 98.5 } }), summary(98.5 - RATCHET_TOLERANCE));
    assert.deepEqual(just.errors, []);
    const beyond = evaluatePackage(pkg({ ratchet: { lines: 98.5 } }), summary(98.5 - RATCHET_TOLERANCE - 0.001));
    assert.equal(beyond.errors.length, 1);
  });

  it('ignores branches entirely when the policy has no branch threshold (for example Dart)', () => {
    assert.deepEqual(evaluatePackage(pkg(), summary(95, null)).errors, []);
    assert.deepEqual(evaluatePackage(pkg(), summary(95, 10)).errors, []);
  });

  it('fails when there is nothing to measure', () => {
    assert.deepEqual(evaluatePackage(pkg(), summary(null)).errors, [
      'no lines were measured (the report is empty, or every file is excluded)',
    ]);
    const branches = evaluatePackage(pkg({ min: { lines: 90, branches: 90 } }), summary(95, null));
    assert.deepEqual(branches.errors, ['no branches were measured (the report is empty, or every file is excluded)']);
  });

  it('proposes a ratchet that only goes up and rounds down', () => {
    const higher = evaluatePackage(pkg({ ratchet: { lines: 90 } }), summary(97.999));
    assert.equal(higher.nextRatchet.lines, 97.99);
    const same = evaluatePackage(pkg({ ratchet: { lines: 97.99 } }), summary(97.99 - RATCHET_TOLERANCE / 2));
    assert.equal(same.nextRatchet.lines, 97.99);
  });

  it('proposes a branch ratchet only for packages that gate branches', () => {
    assert.equal(evaluatePackage(pkg({ min: { lines: 90, branches: 90 } }), summary(95, 96.789)).nextRatchet.branches, 96.78);
    assert.equal(evaluatePackage(pkg(), summary(95, 96.789)).nextRatchet.branches, undefined);
  });

  it('does not raise the ratchet on a failing result', () => {
    const { nextRatchet } = evaluatePackage(pkg({ ratchet: { lines: 99 } }), summary(80));
    assert.deepEqual(nextRatchet, { lines: 99 });
  });
});

function tempRepo(files: Record<string, string>): string {
  const root = mkdtempSync(path.join(os.tmpdir(), 'cov-gate-'));
  tempDirs.push(root);
  for (const [name, content] of Object.entries(files)) {
    mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
    writeFileSync(path.join(root, name), content);
  }
  return root;
}

const lcov = (hit: number, found: number, file = 'lib/a.dart') => `SF:${file}\nLF:${found}\nLH:${hit}\nend_of_record\n`;

describe('runGate', () => {
  const policy = parsePolicy(
    JSON.stringify({
      packages: [
        { name: 'one', report: 'one/lcov.info', min: { lines: 90 }, ratchet: { lines: 95 } },
        { name: 'two', report: 'two/lcov.info', exclude: ['**/*.g.dart'], min: { lines: 80 } },
      ],
    }),
  );

  it('reads each report, applies exclusions, and evaluates', () => {
    const root = tempRepo({
      'one/lcov.info': lcov(96, 100),
      'two/lcov.info': lcov(9, 10) + lcov(0, 50, 'lib/messages.g.dart'),
    });
    const results = runGate(root, policy);
    assert.deepEqual(results.map((r) => [r.name, r.errors]), [['one', []], ['two', []]]);
    assert.equal(results[1]?.summary?.lines.percent, 90);
  });

  it('reports a missing report as an error that names the path', () => {
    const root = tempRepo({ 'one/lcov.info': lcov(96, 100) });
    const results = runGate(root, policy);
    assert.match(results[1]?.errors[0] ?? '', /coverage report not found at two\/lcov\.info/);
  });

  it('limits the run to the requested packages', () => {
    const root = tempRepo({ 'one/lcov.info': lcov(96, 100) });
    const results = runGate(root, policy, { only: ['one'] });
    assert.deepEqual(results.map((r) => r.name), ['one']);
  });

  it('rejects a requested package that is not in the policy', () => {
    const root = tempRepo({ 'one/lcov.info': lcov(96, 100) });
    const results = runGate(root, policy, { only: ['one', 'nope'] });
    assert.deepEqual(results.find((r) => r.name === 'nope')?.errors, ['is not in the coverage policy']);
  });
});

describe('applyRatchet', () => {
  const policy = parsePolicy(
    JSON.stringify({
      packages: [
        { name: 'up', report: 'up/lcov.info', min: { lines: 80 }, ratchet: { lines: 90 } },
        { name: 'down', report: 'down/lcov.info', min: { lines: 80 }, ratchet: { lines: 90 } },
        { name: 'same', report: 'same/lcov.info', min: { lines: 80 }, ratchet: { lines: 92 } },
        { name: 'unchecked', report: 'u/lcov.info', min: { lines: 80 }, ratchet: { lines: 50 } },
      ],
    }),
  );

  it('[NFR-014] raises ratchets that improved, and never lowers or touches the rest', () => {
    const root = tempRepo({
      'up/lcov.info': lcov(97, 100),
      'down/lcov.info': lcov(85, 100),
      'same/lcov.info': lcov(92, 100),
    });
    const results = runGate(root, policy, { only: ['up', 'down', 'same'] });
    const next = applyRatchet(policy, results);
    assert.deepEqual(next.packages.map((p) => [p.name, p.ratchet.lines]), [
      ['up', 97],
      ['down', 90],
      ['same', 92],
      ['unchecked', 50],
    ]);
  });
});

describe('coverage-gate CLI', () => {
  const policyText = JSON.stringify({
    packages: [{ name: 'one', report: 'one/lcov.info', min: { lines: 90 }, ratchet: { lines: 95 } }],
  });
  const run = (root: string, ...args: string[]) => spawnSync(process.execPath, [CLI, root, ...args], { encoding: 'utf8' });

  it('exits 0 and prints a one-line result per package', () => {
    const root = tempRepo({ 'coverage-policy.json': policyText, 'one/lcov.info': lcov(96, 100) });
    const result = run(root);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /ok {4}one: lines 96\.00%/);
    assert.match(result.stdout, /1 package\(s\) checked, 0 failing/);
  });

  it('exits 1 and lists the reasons when coverage drops', () => {
    const root = tempRepo({ 'coverage-policy.json': policyText, 'one/lcov.info': lcov(91, 100) });
    const result = run(root);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /FAIL {2}one: lines 91\.00%/);
    assert.match(result.stderr, /fell below the recorded 95\.00%/);
  });

  it('--update raises the ratchet in the policy file, only upward', () => {
    const root = tempRepo({ 'coverage-policy.json': policyText, 'one/lcov.info': lcov(99, 100) });
    const result = run(root, '--update');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Ratchet raised/);
    assert.equal(parsePolicy(readFileSync(path.join(root, 'coverage-policy.json'), 'utf8')).packages[0]?.ratchet.lines, 99);

    const again = run(root, '--update');
    assert.match(again.stdout, /already at the current coverage/);
  });

  it('--update leaves the policy untouched when any package fails', () => {
    const root = tempRepo({ 'coverage-policy.json': policyText, 'one/lcov.info': lcov(50, 100) });
    const result = run(root, '--update');
    assert.equal(result.status, 1);
    assert.equal(readFileSync(path.join(root, 'coverage-policy.json'), 'utf8'), policyText);
  });

  it('--only selects packages and --policy selects another policy file', () => {
    const root = tempRepo({ 'other.json': policyText, 'one/lcov.info': lcov(96, 100) });
    const result = run(root, '--policy', 'other.json', '--only', 'one');
    assert.equal(result.status, 0, result.stderr);
  });

  it('exits 2 for a missing or invalid policy and for flags without values', () => {
    const empty = tempRepo({});
    assert.equal(run(empty).status, 2);
    const bad = tempRepo({ 'coverage-policy.json': '{"packages": []}' });
    const result = run(bad);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /non-empty "packages"/);
    assert.equal(run(bad, '--only').status, 2);
  });
});
