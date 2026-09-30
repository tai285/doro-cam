import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { globToRegExp, isExcluded, parseLcov, summarize } from '../src/lcov.ts';

const SAMPLE = [
  'TN:',
  'SF:lib\\app\\app.dart',
  'DA:1,1',
  'DA:2,0',
  'DA:3,4',
  'LF:3',
  'LH:2',
  'end_of_record',
  'SF:lib/src/messages.g.dart',
  'DA:1,0',
  'DA:2,0',
  'LF:2',
  'LH:0',
  'end_of_record',
  'SF:src/app.ts',
  'DA:1,1',
  'BRDA:1,0,0,1',
  'BRDA:1,0,1,0',
  'BRF:2',
  'BRH:1',
  'LF:1',
  'LH:1',
  'end_of_record',
  '',
].join('\n');

describe('parseLcov', () => {
  it('reads files with line and branch totals, normalizing Windows separators', () => {
    assert.deepEqual(parseLcov(SAMPLE), [
      { file: 'lib/app/app.dart', linesFound: 3, linesHit: 2, branchesFound: 0, branchesHit: 0 },
      { file: 'lib/src/messages.g.dart', linesFound: 2, linesHit: 0, branchesFound: 0, branchesHit: 0 },
      { file: 'src/app.ts', linesFound: 1, linesHit: 1, branchesFound: 2, branchesHit: 1 },
    ]);
  });

  it('computes totals from DA records when LF/LH are missing', () => {
    const records = parseLcov(['SF:a.dart', 'DA:1,3', 'DA:2,0', 'DA:3,1', 'end_of_record'].join('\n'));
    assert.deepEqual(records, [{ file: 'a.dart', linesFound: 3, linesHit: 2, branchesFound: 0, branchesHit: 0 }]);
  });

  it('computes branch totals from BRDA records when BRF/BRH are missing, treating "-" as not taken', () => {
    const records = parseLcov(['SF:a.ts', 'BRDA:1,0,0,2', 'BRDA:1,0,1,-', 'end_of_record'].join('\n'));
    assert.deepEqual(records, [{ file: 'a.ts', linesFound: 0, linesHit: 0, branchesFound: 2, branchesHit: 1 }]);
  });

  it('handles CRLF line endings and an empty report', () => {
    assert.equal(parseLcov(SAMPLE.replace(/\n/g, '\r\n')).length, 3);
    assert.deepEqual(parseLcov(''), []);
  });

  it('closes a file record that is still open at the end of the report', () => {
    assert.equal(parseLcov('SF:a.ts\nDA:1,1').length, 1);
  });
});

describe('globToRegExp / isExcluded', () => {
  it('matches ** across directories, * within a segment and ? for one character', () => {
    assert.ok(globToRegExp('**/*.g.dart').test('lib/src/messages.g.dart'));
    assert.ok(globToRegExp('**/*.g.dart').test('messages.g.dart'));
    assert.ok(!globToRegExp('**/*.g.dart').test('lib/src/messages.dart'));
    assert.ok(globToRegExp('lib/*.dart').test('lib/a.dart'));
    assert.ok(!globToRegExp('lib/*.dart').test('lib/src/a.dart'));
    assert.ok(globToRegExp('src/?.ts').test('src/a.ts'));
    assert.ok(!globToRegExp('src/?.ts').test('src/ab.ts'));
  });

  it('escapes regex metacharacters in the pattern', () => {
    assert.ok(globToRegExp('a+b.ts').test('a+b.ts'));
    assert.ok(!globToRegExp('a+b.ts').test('aab.ts'));
    assert.ok(!globToRegExp('file.ts').test('fileXts'));
  });

  it('isExcluded checks every pattern against the normalized path', () => {
    assert.equal(isExcluded('lib\\src\\messages.g.dart', ['**/*.g.dart']), true);
    assert.equal(isExcluded('lib/app.dart', ['**/*.g.dart', 'src/**']), false);
    assert.equal(isExcluded('src/deep/x.ts', ['src/**']), true);
    assert.equal(isExcluded('lib/app.dart', []), false);
  });
});

describe('summarize', () => {
  const records = parseLcov(SAMPLE);

  it('totals lines and branches across included files', () => {
    assert.deepEqual(summarize(records, []), {
      files: 3,
      lines: { found: 6, hit: 3, percent: 50 },
      branches: { found: 2, hit: 1, percent: 50 },
    });
  });

  it('leaves out excluded files', () => {
    assert.deepEqual(summarize(records, ['**/*.g.dart']), {
      files: 2,
      lines: { found: 4, hit: 3, percent: 75 },
      branches: { found: 2, hit: 1, percent: 50 },
    });
  });

  it('reports null percentages when there is nothing to measure', () => {
    assert.deepEqual(summarize([], []), {
      files: 0,
      lines: { found: 0, hit: 0, percent: null },
      branches: { found: 0, hit: 0, percent: null },
    });
    const noBranches = summarize(parseLcov('SF:a.dart\nLF:2\nLH:2\nend_of_record'), []);
    assert.equal(noBranches.branches.percent, null);
    assert.equal(noBranches.lines.percent, 100);
  });

  it('rounds percentages to two decimals', () => {
    const third = summarize(parseLcov('SF:a.ts\nLF:3\nLH:1\nend_of_record'), []);
    assert.equal(third.lines.percent, 33.33);
  });
});
