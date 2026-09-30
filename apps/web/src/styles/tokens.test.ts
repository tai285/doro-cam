import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const css = readFileSync(
  path.join(path.dirname(fileURLToPath(import.meta.url)), 'tokens.css'),
  'utf8',
);

/** Extracts `--name: #hex;` declarations from a CSS block. */
function colors(block: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const match of block.matchAll(/--([a-z-]+):\s*(#[0-9a-fA-F]{6})\s*;/g)) {
    const [, name, value] = match;
    if (name !== undefined && value !== undefined) {
      result[name] = value;
    }
  }
  return result;
}

const darkStart = css.indexOf('@media (prefers-color-scheme: dark)');
const light = colors(css.slice(0, darkStart));
const dark = colors(css.slice(darkStart));

function luminance(hex: string): number {
  const channels = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * (channels[0] ?? 0) + 0.7152 * (channels[1] ?? 0) + 0.0722 * (channels[2] ?? 0);
}

export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return ((hi ?? 0) + 0.05) / ((lo ?? 0) + 0.05);
}

describe('contrast helper', () => {
  it('matches known WCAG values', () => {
    expect(contrast('#000000', '#ffffff')).toBeCloseTo(21, 1);
    expect(contrast('#ffffff', '#ffffff')).toBeCloseTo(1, 3);
    expect(contrast('#777777', '#ffffff')).toBeCloseTo(4.48, 1);
    expect(contrast('#ffffff', '#777777')).toBeCloseTo(4.48, 1);
  });
});

describe('design tokens', () => {
  it('define the same set of colors for light and dark', () => {
    expect(Object.keys(dark).sort()).toEqual(Object.keys(light).sort());
    expect(Object.keys(light)).toEqual(
      expect.arrayContaining([
        'color-surface',
        'color-on-surface',
        'color-accent',
        'color-readout',
        'color-warning',
        'color-recording',
      ]),
    );
  });

  for (const [scheme, palette] of [
    ['light', light],
    ['dark', dark],
  ] as const) {
    describe(`${scheme} scheme`, () => {
      const pairs: ReadonlyArray<[string, string, number]> = [
        ['color-on-surface', 'color-surface', 4.5],
        ['color-on-surface', 'color-surface-raised', 4.5],
        ['color-on-surface-muted', 'color-surface', 4.5],
        ['color-on-surface-muted', 'color-surface-raised', 4.5],
        ['color-accent', 'color-surface', 4.5],
        ['color-accent', 'color-surface-raised', 4.5],
        ['color-on-accent', 'color-accent', 4.5],
        ['color-readout', 'color-surface', 4.5],
        ['color-warning', 'color-surface', 4.5],
        ['color-recording', 'color-surface', 3],
        ['color-border', 'color-surface', 1.5],
      ];
      for (const [foreground, background, minimum] of pairs) {
        it(`[NFR-007] ${foreground} on ${background} is at least ${String(minimum)}:1`, () => {
          const fg = palette[foreground];
          const bg = palette[background];
          expect(fg, foreground).toBeDefined();
          expect(bg, background).toBeDefined();
          expect(contrast(fg as string, bg as string)).toBeGreaterThanOrEqual(minimum);
        });
      }
    });
  }
});
