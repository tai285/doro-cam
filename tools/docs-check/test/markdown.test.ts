import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  extractHeadings,
  extractLinks,
  headingSlugs,
  slugify,
  stripFencedCode,
  stripInlineCode,
} from '../src/markdown.ts';

describe('stripFencedCode', () => {
  it('blanks backtick and tilde fences but keeps the line count', () => {
    const input = ['a', '```ts', 'code', '```', 'b', '~~~', 'x', '~~~', 'c'].join('\n');
    assert.equal(stripFencedCode(input), ['a', '', '', '', 'b', '', '', '', 'c'].join('\n'));
  });

  it('only closes a fence with the same character and at least the same length', () => {
    const input = ['````', '```', '~~~~', 'still code', '````', 'after'].join('\n');
    assert.equal(stripFencedCode(input), ['', '', '', '', '', 'after'].join('\n'));
  });

  it('does not close a fence with a line that has trailing text', () => {
    const input = ['```', '``` not a close', 'code', '```', 'text'].join('\n');
    assert.equal(stripFencedCode(input), ['', '', '', '', 'text'].join('\n'));
  });

  it('treats an unclosed fence as code until the end of the document', () => {
    assert.equal(stripFencedCode('a\n```\nb\nc'), 'a\n\n\n');
  });
});

describe('stripInlineCode', () => {
  it('replaces single and double backtick spans with spaces of equal length', () => {
    assert.equal(stripInlineCode('x `a` y ``b ` c`` z'), `x ${' '.repeat(3)} y ${' '.repeat(9)} z`);
  });

  it('leaves an unmatched backtick alone', () => {
    assert.equal(stripInlineCode('it`s fine'), 'it`s fine');
  });
});

describe('extractLinks', () => {
  it('finds inline links, images, titles, angle brackets and reference definitions with line numbers', () => {
    const markdown = [
      'See [a](a.md) and ![img](i.png "Title").',
      'Nested [text [x]](b.md#frag) and [angle](<c.md>).',
      '',
      '[ref]: e.md "ref title"',
    ].join('\n');
    assert.deepEqual(extractLinks(markdown), [
      { target: 'a.md', line: 1 },
      { target: 'i.png', line: 1 },
      { target: 'b.md#frag', line: 2 },
      { target: 'c.md', line: 2 },
      { target: 'e.md', line: 4 },
    ]);
  });

  it('ignores links in inline code and fenced code', () => {
    const markdown = ['`[x](inline.md)`', '```', '[y](fenced.md)', '```', '[z](real.md)'].join('\n');
    assert.deepEqual(extractLinks(markdown), [{ target: 'real.md', line: 5 }]);
  });
});

describe('slugify and headingSlugs', () => {
  it('follows GitHub rules for punctuation, case and spaces', () => {
    assert.equal(slugify('Specs — exact contracts'), 'specs--exact-contracts');
    assert.equal(slugify('ADR-0001: Flutter & native'), 'adr-0001-flutter--native');
    assert.equal(slugify('Use `motion_clip` [link](x.md)'), 'use-motion_clip-link');
    assert.equal(slugify('Café 30 fps'), 'café-30-fps');
  });

  it('numbers duplicate headings and strips closing hashes', () => {
    const markdown = ['# Title #', '## Same', '## Same', '### Same', '```', '# Not a heading', '```'].join('\n');
    assert.deepEqual([...headingSlugs(markdown)], ['title', 'same', 'same-1', 'same-2']);
  });

  it('reports heading levels and lines', () => {
    assert.deepEqual(extractHeadings('# One\ntext\n### Three'), [
      { level: 1, text: 'One', line: 1 },
      { level: 3, text: 'Three', line: 3 },
    ]);
  });

  it('does not treat "#hashtag" without a space as a heading', () => {
    assert.deepEqual(extractHeadings('#nope'), []);
  });
});
