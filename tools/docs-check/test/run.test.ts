import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { describe, it } from 'node:test';
import { formatError } from '../src/errors.ts';
import { runAllChecks } from '../src/run.ts';
import { DEFAULT_LAYOUT, loadSnapshot } from '../src/snapshot.ts';
import { CLI_PATH, FIXTURES_DIR, fixture, lines, REPO_ROOT } from './helpers.ts';

describe('runAllChecks', () => {
  it('accepts a complete, valid documentation set', () => {
    assert.deepEqual(lines(runAllChecks(fixture('valid'))), []);
  });

  it('combines all checks on a broken set', () => {
    const errors = runAllChecks(fixture('links'));
    const checks = new Set(errors.map((error) => error.check));
    assert.deepEqual([...checks].sort(), ['index', 'links', 'requirements']);
  });

  it('passes on the real repository documentation', () => {
    const errors = runAllChecks(loadSnapshot(REPO_ROOT, DEFAULT_LAYOUT));
    assert.deepEqual(lines(errors), []);
  });
});

describe('formatError', () => {
  it('includes the line only when present', () => {
    assert.equal(formatError({ check: 'links', file: 'a.md', line: 3, message: 'm' }), 'a.md:3 [links] m');
    assert.equal(formatError({ check: 'index', file: 'b.md', line: null, message: 'n' }), 'b.md [index] n');
  });
});

describe('cli', () => {
  const run = (root: string) =>
    spawnSync(process.execPath, [CLI_PATH, root], { encoding: 'utf8' });

  it('exits 0 with a summary for a valid set', () => {
    const result = run(path.join(FIXTURES_DIR, 'valid'));
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /docs-check: 9 Markdown files, 0 error\(s\)/);
  });

  it('exits 1 and prints each error for a broken set', () => {
    const result = run(path.join(FIXTURES_DIR, 'index'));
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.deepEqual(result.stderr.trimEnd().split(/\r?\n/), [
      'docs/orphan.md [index] not reachable from docs/README.md; link it from the index or a linked page',
      'docs/product/requirements.md [requirements] requirements file not found',
      'docs/sub/orphan2.md [index] not reachable from docs/README.md; link it from the index or a linked page',
      'docs-check: 7 Markdown files, 3 error(s)',
    ]);
  });
});
