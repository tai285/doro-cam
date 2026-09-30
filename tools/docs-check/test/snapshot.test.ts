import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { resolveLinkPath } from '../src/snapshot.ts';
import { fixture } from './helpers.ts';

describe('resolveLinkPath', () => {
  it('resolves relative to the linking file', () => {
    assert.equal(resolveLinkPath('docs/a/b.md', '../c.md'), 'docs/c.md');
    assert.equal(resolveLinkPath('docs/a/b.md', './d/e.md'), 'docs/a/d/e.md');
    assert.equal(resolveLinkPath('README.md', 'docs/'), 'docs');
  });

  it('treats a leading slash as the repository root', () => {
    assert.equal(resolveLinkPath('docs/a/b.md', '/AGENTS.md'), 'AGENTS.md');
  });

  it('returns null when the target escapes the root', () => {
    assert.equal(resolveLinkPath('docs/a.md', '../../x.md'), null);
    assert.equal(resolveLinkPath('README.md', '..'), null);
  });
});

describe('loadSnapshot', () => {
  it('scans root Markdown and everything under docs/, sorted, with LF newlines', () => {
    const snapshot = fixture('index');
    assert.deepEqual(
      [...snapshot.docs.keys()],
      [
        'README.md',
        'docs/a.md',
        'docs/c.md',
        'docs/orphan.md',
        'docs/README.md',
        'docs/sub/b.md',
        'docs/sub/orphan2.md',
      ],
    );
    for (const content of snapshot.docs.values()) {
      assert.equal(content.includes('\r'), false);
    }
  });

  it('reports path kinds and reads files outside the scanned set', () => {
    const snapshot = fixture('links');
    assert.equal(snapshot.kindOf('docs'), 'dir');
    assert.equal(snapshot.kindOf('docs/b.md'), 'file');
    assert.equal(snapshot.kindOf('docs/missing.md'), null);
    assert.equal(snapshot.readText('docs/sub/c.md'), '# C\n');
    assert.equal(snapshot.readText('docs/sub'), null);
    assert.equal(snapshot.readText('docs/nope.md'), null);
  });
});
