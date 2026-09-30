import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { extractTags, findTestFiles, isTestFile } from '../src/traceability/scan.ts';
import { runTraceability } from '../src/traceability/run.ts';
import { parseWaivers } from '../src/traceability/waivers.ts';
import { formatError } from '../src/errors.ts';
import { FIXTURES_DIR, REPO_ROOT } from './helpers.ts';

const TRACEABILITY_CLI = path.join(REPO_ROOT, 'tools', 'docs-check', 'src', 'traceability-cli.ts');

/**
 * The scanner reads test *source text* for bracketed requirement tags, so these tests must never
 * contain a literal bracketed ID (it would count as coverage). Tags are built at runtime instead.
 */
const tag = (id: string) => `[${id}]`;

const fixtureRoot = (name: string) => path.join(FIXTURES_DIR, name);
const errorLines = (root: string) => runTraceability(root).errors.map(formatError);

describe('isTestFile', () => {
  const yes = [
    'a.test.ts',
    'a.test.tsx',
    'smoke.spec.ts',
    'router_test.dart',
    'CapabilityProbeTest.kt',
    'CapabilityProbeTests.kt',
    'CapabilityProbeTests.swift',
    'CapabilityProbeTest.swift',
  ];
  const no = ['a.ts', 'test.ts', 'pump_app.dart', 'notes_test.md', 'a.test.ts.bak', 'Probe.kt', 'helpers.tsx'];
  for (const name of yes) {
    it(`accepts ${name}`, () => assert.equal(isTestFile(name), true));
  }
  for (const name of no) {
    it(`rejects ${name}`, () => assert.equal(isTestFile(name), false));
  }
});

describe('findTestFiles', () => {
  it('finds tests in every supported language, sorted, relative and POSIX-style', () => {
    assert.deepEqual(findTestFiles(fixtureRoot('trace-valid')), [
      'apps/mobile/test/router_test.dart',
      'apps/web/e2e/smoke.spec.ts',
      'packages/cam/android/src/test/kotlin/CapabilityProbeTest.kt',
      'packages/cam/ios/Tests/CapabilityProbeTests.swift',
      'services/api/test/health.test.ts',
    ]);
  });

  it('skips dependency, build and fixture folders', () => {
    assert.deepEqual(findTestFiles(fixtureRoot('trace-problems')), ['test/a.test.ts']);
  });

  it('returns nothing for a repository without tests', () => {
    assert.deepEqual(findTestFiles(fixtureRoot('valid')), []);
  });
});

describe('extractTags', () => {
  it('finds every tag with its line, in order', () => {
    const source = [`it('${tag('CAM-002')} and ${tag('CAM-001')}', () => {});`, '', `// ${tag('NFR-007')}`].join('\n');
    assert.deepEqual(extractTags('t.ts', source), [
      { id: 'CAM-002', file: 't.ts', line: 1 },
      { id: 'CAM-001', file: 't.ts', line: 1 },
      { id: 'NFR-007', file: 't.ts', line: 3 },
    ]);
  });

  it('ignores task IDs and malformed or lowercase IDs', () => {
    assert.deepEqual(extractTags('t.ts', `${tag('CAM-T-001')} ${tag('cam-001')} ${tag('CAM-1')} ${tag('CAM-0001')} CAM-001`), []);
  });

  it('does not treat array indexing or links as tags', () => {
    assert.deepEqual(extractTags('t.ts', 'const x = a[0]; [link](CAM-001)'), []);
  });
});

describe('parseWaivers', () => {
  it('reads valid waivers', () => {
    const result = parseWaivers('[{"requirement":"NFR-001","reason":"Process requirement."}]');
    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.waivers, [{ requirement: 'NFR-001', reason: 'Process requirement.', index: 1 }]);
  });

  it('accepts an empty list', () => {
    assert.deepEqual(parseWaivers('[]'), { waivers: [], errors: [] });
  });

  it('reports invalid JSON', () => {
    const result = parseWaivers('[ {');
    assert.equal(result.waivers.length, 0);
    assert.match(result.errors[0] ?? '', /^is not valid JSON: /);
  });

  it('reports a top-level value that is not an array', () => {
    assert.deepEqual(parseWaivers('{"a":1}').errors, [
      'must contain a JSON array of { "requirement", "reason" } objects',
    ]);
  });

  it('reports entries that are not objects', () => {
    assert.deepEqual(parseWaivers('[1, null, "x"]').errors, [
      'waiver 1 must be an object',
      'waiver 2 must be an object',
      'waiver 3 must be an object',
    ]);
  });

  it('reports missing, malformed and duplicate fields, dropping the invalid entries', () => {
    const result = parseWaivers(
      JSON.stringify([
        { reason: 'no requirement' },
        { requirement: 'nfr-1', reason: 'bad id' },
        { requirement: 'NFR-001', reason: '  ' },
        { requirement: 'NFR-002', reason: 'first' },
        { requirement: 'NFR-002', reason: 'second' },
        { requirement: 'NFR-003', reason: 42 },
      ]),
    );
    assert.deepEqual(result.errors, [
      'waiver 1 needs a "requirement" ID',
      'waiver 2 needs a "requirement" ID',
      'waiver 3 (NFR-001) needs a non-empty reason',
      'waiver 5 (NFR-002) duplicates waiver 4',
      'waiver 6 (NFR-003) needs a non-empty reason',
    ]);
    assert.deepEqual(result.waivers, [{ requirement: 'NFR-002', reason: 'first', index: 4 }]);
  });
});

describe('runTraceability', () => {
  it('[NFR-015] passes when every requirement of a done task is tested or validly waived', () => {
    const { report, errors } = runTraceability(fixtureRoot('trace-valid'));
    assert.deepEqual(errors.map(formatError), []);
    assert.deepEqual(
      report.requirements.map((r) => ({ id: r.id, tags: r.tagCount, waived: r.waived, doneTasks: r.doneTasks })),
      [
        { id: 'CAM-001', tags: 4, waived: false, doneTasks: ['AAA-T-001'] },
        { id: 'CAM-002', tags: 1, waived: false, doneTasks: [] },
        { id: 'NFR-001', tags: 0, waived: true, doneTasks: ['AAA-T-002'] },
        { id: 'NFR-002', tags: 1, waived: false, doneTasks: [] },
      ],
    );
    assert.deepEqual(report.summary, {
      requirementsDefined: 4,
      requirementsWithTests: 3,
      requirementsWaived: 1,
      doneTasksChecked: 2,
      tagsFound: 6,
      testFilesScanned: 5,
    });
  });

  it('lists the files that cover a requirement', () => {
    const cam001 = runTraceability(fixtureRoot('trace-valid')).report.requirements.find((r) => r.id === 'CAM-001');
    assert.deepEqual(cam001?.files, [
      'apps/web/e2e/smoke.spec.ts',
      'packages/cam/android/src/test/kotlin/CapabilityProbeTest.kt',
      'packages/cam/ios/Tests/CapabilityProbeTests.swift',
      'services/api/test/health.test.ts',
    ]);
  });

  it('[NFR-015] reports every kind of problem, with locations', () => {
    assert.deepEqual(errorLines(fixtureRoot('trace-problems')), [
      'docs/product/traceability-waivers.json [traceability] waiver 1 (NFR-001) is stale: the requirement now has tagged tests, so remove the waiver',
      'docs/product/traceability-waivers.json [traceability] waiver 2 names unknown requirement CAM-777',
      'docs/product/traceability-waivers.json [traceability] waiver 3 (NFR-002) needs a non-empty reason',
      'docs/product/traceability-waivers.json [traceability] waiver 4 needs a "requirement" ID',
      `docs/tasks/phase-a.md:13 [traceability] task AAA-T-002 is done but requirement CAM-002 has no tagged test (add a test tagged ${tag('CAM-002')} or a reasoned waiver)`,
      `docs/tasks/phase-a.md:27 [traceability] task AAA-T-004 is done but requirement NFR-002 has no tagged test (add a test tagged ${tag('NFR-002')} or a reasoned waiver)`,
      `test/a.test.ts:5 [traceability] unknown requirement tag ${tag('CAM-999')}`,
    ]);
  });

  it('does not count tests inside node_modules', () => {
    const cam002 = runTraceability(fixtureRoot('trace-problems')).report.requirements.find((r) => r.id === 'CAM-002');
    assert.equal(cam002?.tagCount, 0);
  });

  it('reports a waiver file that is not an array', () => {
    assert.deepEqual(errorLines(fixtureRoot('trace-waiver-file-invalid')), [
      'docs/product/traceability-waivers.json [traceability] must contain a JSON array of { "requirement", "reason" } objects',
    ]);
  });

  it('reports a waiver file that is not valid JSON', () => {
    const errors = errorLines(fixtureRoot('trace-waiver-json-broken'));
    assert.equal(errors.length, 1);
    assert.match(errors[0] ?? '', /^docs\/product\/traceability-waivers\.json \[traceability\] is not valid JSON: /);
  });

  it('works without a waiver file', () => {
    const { report, errors } = runTraceability(fixtureRoot('requirements'));
    assert.deepEqual(errors, []);
    assert.equal(report.summary.requirementsWaived, 0);
    assert.equal(report.summary.testFilesScanned, 0);
  });

  it('reports a missing requirements file', () => {
    const { errors } = runTraceability(fixtureRoot('links'));
    assert.deepEqual(errors.map(formatError), [
      'docs/product/requirements.md [traceability] requirements file not found',
    ]);
  });

  it('[NFR-015] passes on the real repository', () => {
    const { errors, report } = runTraceability(REPO_ROOT);
    assert.deepEqual(errors.map(formatError), []);
    assert.ok(report.summary.requirementsWithTests > 0, 'the real repo has tagged tests');
  });
});

describe('traceability CLI', () => {
  const run = (...args: string[]) => spawnSync(process.execPath, [TRACEABILITY_CLI, ...args], { encoding: 'utf8' });

  it('exits 0 and prints a summary for a covered repository', () => {
    const result = run(fixtureRoot('trace-valid'));
    assert.equal(result.status, 0, result.stderr);
    assert.equal(
      result.stdout.trim(),
      'traceability: 4 requirements defined, 3 with tagged tests, 1 waived; 2 done tasks checked, 0 error(s)',
    );
  });

  it('exits 1 and lists every problem on stderr', () => {
    const result = run(fixtureRoot('trace-problems'));
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /task AAA-T-002 is done but requirement CAM-002 has no tagged test/);
    assert.match(result.stderr, /traceability: 4 requirements defined, .* 7 error\(s\)/);
  });

  it('rejects --json without a file path', () => {
    const result = run(fixtureRoot('trace-valid'), '--json');
    assert.equal(result.status, 2);
    assert.match(result.stderr, /--json needs a file path/);
  });

  it('writes the full report as JSON with --json', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'trace-'));
    try {
      const out = path.join(dir, 'report.json');
      const result = run(fixtureRoot('trace-valid'), '--json', out);
      assert.equal(result.status, 0, result.stderr);
      const report = JSON.parse(readFileSync(out, 'utf8')) as {
        summary: { requirementsDefined: number };
        requirements: Array<{ id: string }>;
      };
      assert.equal(report.summary.requirementsDefined, 4);
      assert.deepEqual(report.requirements.map((r) => r.id), ['CAM-001', 'CAM-002', 'NFR-001', 'NFR-002']);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
