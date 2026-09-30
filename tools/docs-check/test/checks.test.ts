import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkAdrs } from '../src/checks/adrs.ts';
import { checkIndexReachability } from '../src/checks/index-reachability.ts';
import { checkLinks } from '../src/checks/links.ts';
import {
  checkRequirements,
  parseRequirementDefinitions,
  requirementReferencePattern,
} from '../src/checks/requirements.ts';
import { checkTasks, findCycles, parseTasks } from '../src/checks/tasks.ts';
import { DEFAULT_LAYOUT } from '../src/snapshot.ts';
import { fixture, lines } from './helpers.ts';

describe('checkLinks', () => {
  it('reports exactly the broken links, anchors and escapes in the fixture', () => {
    assert.deepEqual(lines(checkLinks(fixture('links'))), [
      'docs/a.md:5 [links] broken link "missing.md" (no such file: docs/missing.md)',
      'docs/a.md:6 [links] missing anchor "#nope" in docs/b.md',
      'docs/a.md:8 [links] missing anchor "#absent" in docs/a.md',
      'docs/a.md:10 [links] link "../../outside.md" escapes the repository root',
      'docs/a.md:12 [links] anchor "#x" used on non-Markdown target docs/sub',
      'docs/a.md:17 [links] broken link "img/missing.png" (no such file: docs/img/missing.png)',
      'docs/a.md:19 [links] malformed link target "b%E0.md"',
      'docs/a.md:21 [links] broken link "ref-missing.md" (no such file: docs/ref-missing.md)',
    ]);
  });
});

describe('checkRequirements', () => {
  it('parses table-row definitions only', () => {
    assert.deepEqual(parseRequirementDefinitions('| CAM-001 | a |\ntext CAM-002\n|CAM-003|b|'), [
      { id: 'CAM-001', line: 1 },
      { id: 'CAM-003', line: 3 },
    ]);
  });

  it('builds a reference pattern from defined prefixes that skips task IDs', () => {
    const pattern = requirementReferencePattern(['CAM-001', 'NFR-002']);
    assert.ok(pattern);
    assert.deepEqual('CAM-010, NFR-020, CAM-T-001, XCAM-001, ABC-001'.match(pattern), ['CAM-010', 'NFR-020']);
    assert.equal(requirementReferencePattern([]), null);
  });

  it('reports duplicates and unknown references, ignoring fenced code', () => {
    const result = checkRequirements(fixture('requirements'), DEFAULT_LAYOUT);
    assert.deepEqual(lines(result.errors), [
      'docs/other.md:3 [requirements] unknown requirement ID CAM-099',
      'docs/other.md:3 [requirements] unknown requirement ID NFR-777',
      'docs/other.md:5 [requirements] unknown requirement ID CAM-555',
      'docs/product/requirements.md:7 [requirements] duplicate requirement definition CAM-001',
    ]);
    assert.deepEqual([...result.definedIds].sort(), ['CAM-001', 'CAM-002', 'NFR-001']);
  });

  it('reports a missing requirements file', () => {
    assert.deepEqual(lines(checkRequirements(fixture('links'), DEFAULT_LAYOUT).errors), [
      'docs/product/requirements.md [requirements] requirements file not found',
    ]);
  });

  it('reports a requirements file without definitions', () => {
    assert.deepEqual(lines(checkRequirements(fixture('requirements-empty'), DEFAULT_LAYOUT).errors), [
      'docs/product/requirements.md [requirements] no requirement definitions found',
    ]);
  });
});

describe('checkAdrs', () => {
  it('validates names, titles, status, dates, sections, duplicates and references', () => {
    const dir = 'docs/decisions/adr';
    assert.deepEqual(lines(checkAdrs(fixture('adrs'), DEFAULT_LAYOUT)), [
      `${dir}/0002-missing-sections.md [adrs] missing section "## Alternatives"`,
      `${dir}/0002-missing-sections.md [adrs] missing section "## Consequences"`,
      `${dir}/0003-wrong-title.md:1 [adrs] reference to missing ADR-0033`,
      `${dir}/0003-wrong-title.md:1 [adrs] title number ADR-0033 does not match file number 0003`,
      `${dir}/0004-bad-status.md [adrs] invalid date "2026-02-30" (expected YYYY-MM-DD)`,
      `${dir}/0004-bad-status.md [adrs] invalid status "Maybe"`,
      `${dir}/0005-no-status-date.md [adrs] missing "Date:" line`,
      `${dir}/0005-no-status-date.md [adrs] missing "Status:" line`,
      `${dir}/0006-superseded.md [adrs] duplicate ADR number 0006 (also ${dir}/0006-duplicate-number.md)`,
      `${dir}/Bad_Name.md [adrs] ADR file name must match NNNN-kebab-case-title.md`,
      `${dir}/Bad_Name.md:1 [adrs] reference to missing ADR-0007`,
      `${dir}/README.md:2 [adrs] reference to missing ADR-0042`,
      'docs/ref.md:2 [adrs] reference to missing ADR-0077',
    ]);
  });
});

describe('checkTasks', () => {
  it('parses fields and ignores headings inside fences', () => {
    const parsed = parseTasks('t.md', '### AB-T-001 Title\n- **Status:** todo\n```\n### AB-T-002 Hidden\n```\n');
    assert.deepEqual(parsed.errors, []);
    assert.equal(parsed.tasks.length, 1);
    assert.deepEqual(parsed.tasks[0]?.fields.get('Status'), { value: 'todo', line: 2 });
  });

  it('finds each cycle once', () => {
    const graph = new Map([
      ['A', ['B']],
      ['B', ['C']],
      ['C', ['A']],
      ['D', ['D2']],
      ['D2', ['D']],
      ['E', []],
    ]);
    assert.deepEqual(findCycles(graph), [
      ['A', 'B', 'C', 'A'],
      ['D', 'D2', 'D'],
    ]);
  });

  it('reports every malformed task in the fixture and nothing else', () => {
    const snapshot = fixture('tasks');
    const { definedIds } = checkRequirements(snapshot, DEFAULT_LAYOUT);
    assert.deepEqual(lines(checkTasks(snapshot, DEFAULT_LAYOUT, definedIds)), [
      'docs/tasks/phase-a.md:9 [tasks] task AAA-T-002 is missing field "Acceptance"',
      'docs/tasks/phase-a.md:9 [tasks] task AAA-T-002 is missing field "Depends"',
      'docs/tasks/phase-a.md:10 [tasks] task AAA-T-002 has invalid status "started"',
      'docs/tasks/phase-a.md:14 [tasks] task AAA-T-003 is blocked without a "(reason)"',
      'docs/tasks/phase-a.md:15 [tasks] task AAA-T-003 depends on unknown task AAA-T-999',
      'docs/tasks/phase-a.md:15 [tasks] task AAA-T-003 has invalid dependency "not-a-task"',
      'docs/tasks/phase-a.md:16 [tasks] task AAA-T-003 references unknown requirement CAM-404',
      'docs/tasks/phase-a.md:21 [tasks] task AAA-T-004 is done but depends on unfinished task AAA-T-005',
      'docs/tasks/phase-a.md:25 [tasks] dependency cycle: AAA-T-005 -> AAA-T-006 -> AAA-T-005',
      'docs/tasks/phase-a.md:36 [tasks] task AAA-T-006 repeats field "Acceptance"',
      'docs/tasks/phase-a.md:38 [tasks] task AAA-T-007 has no title',
      'docs/tasks/phase-a.md:40 [tasks] task AAA-T-007 depends on itself',
      'docs/tasks/phase-a.md:41 [tasks] task AAA-T-007 lists no requirement IDs',
      'docs/tasks/phase-a.md:44 [tasks] malformed task ID in heading "### AAA-T-08 Malformed id"',
      'docs/tasks/phase-b.md:3 [tasks] duplicate task ID AAA-T-001 (first defined in docs/tasks/phase-a.md:3)',
    ]);
  });
});

describe('checkIndexReachability', () => {
  it('reports docs that cannot be reached from the index, including orphan chains', () => {
    assert.deepEqual(lines(checkIndexReachability(fixture('index'), DEFAULT_LAYOUT)), [
      'docs/orphan.md [index] not reachable from docs/README.md; link it from the index or a linked page',
      'docs/sub/orphan2.md [index] not reachable from docs/README.md; link it from the index or a linked page',
    ]);
  });

  it('reports a missing index', () => {
    assert.deepEqual(lines(checkIndexReachability(fixture('links'), DEFAULT_LAYOUT)), [
      'docs/README.md [index] documentation index not found',
    ]);
  });
});
