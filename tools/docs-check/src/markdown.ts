/**
 * Minimal, dependency-free Markdown helpers used by the docs checks.
 * They intentionally cover only the CommonMark/GFM subset used in this repository.
 * Line numbers are always preserved so errors can point at the source line.
 */

export interface Link {
  target: string;
  line: number;
}

const FENCE_OPEN_RE = /^ {0,3}(`{3,}|~{3,})/;
const FENCE_CLOSE_RE = /^ {0,3}(`{3,}|~{3,})\s*$/;

/** Replaces the contents of fenced code blocks (including fence lines) with empty lines. */
export function stripFencedCode(markdown: string): string {
  const lines = markdown.split('\n');
  let fence: string | null = null;
  const out: string[] = [];
  for (const line of lines) {
    if (fence === null) {
      const open = FENCE_OPEN_RE.exec(line);
      if (open?.[1] !== undefined) {
        fence = open[1];
        out.push('');
      } else {
        out.push(line);
      }
      continue;
    }
    const close = FENCE_CLOSE_RE.exec(line);
    const marker = close?.[1];
    if (marker !== undefined && marker[0] === fence[0] && marker.length >= fence.length) {
      fence = null;
    }
    out.push('');
  }
  return out.join('\n');
}

/** Replaces inline code spans with spaces of equal length (keeps columns and line count). */
export function stripInlineCode(markdown: string): string {
  return markdown
    .split('\n')
    .map((line) => line.replace(/(`+)(.+?)\1/g, (span) => ' '.repeat(span.length)))
    .join('\n');
}

/** Fenced and inline code removed: the text that is actually prose. */
export function stripCode(markdown: string): string {
  return stripInlineCode(stripFencedCode(markdown));
}

const INLINE_LINK_RE =
  /!?\[(?:[^[\]]|\[[^[\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g;
const REFERENCE_DEF_RE = /^ {0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$/;

/** Extracts inline links, images and reference definitions outside code. */
export function extractLinks(markdown: string): Link[] {
  const links: Link[] = [];
  stripCode(markdown)
    .split('\n')
    .forEach((line, index) => {
      const lineNumber = index + 1;
      const reference = REFERENCE_DEF_RE.exec(line);
      if (reference?.[1] !== undefined) {
        links.push({ target: reference[1], line: lineNumber });
        return;
      }
      for (const match of line.matchAll(INLINE_LINK_RE)) {
        if (match[1] !== undefined) {
          links.push({ target: match[1], line: lineNumber });
        }
      }
    });
  return links;
}

/** GitHub-style heading anchor slug (without duplicate suffixes). */
export function slugify(headingText: string): string {
  return headingText
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<[^>]+>/g, '')
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\p{M} _-]/gu, '')
    .replace(/ /g, '-');
}

const HEADING_RE = /^ {0,3}(#{1,6})\s+(.+?)(?:\s+#+)?\s*$/;

export interface Heading {
  level: number;
  text: string;
  line: number;
}

/** ATX headings outside fenced code. */
export function extractHeadings(markdown: string): Heading[] {
  const headings: Heading[] = [];
  stripFencedCode(markdown)
    .split('\n')
    .forEach((line, index) => {
      const match = HEADING_RE.exec(line);
      const hashes = match?.[1];
      const text = match?.[2];
      if (hashes === undefined || text === undefined) {
        return;
      }
      headings.push({ level: hashes.length, text, line: index + 1 });
    });
  return headings;
}

/** All anchor slugs a document exposes, with GitHub's `-1`, `-2` duplicate suffixes. */
export function headingSlugs(markdown: string): Set<string> {
  const seen = new Map<string, number>();
  const slugs = new Set<string>();
  for (const heading of extractHeadings(markdown)) {
    const base = slugify(heading.text);
    const count = seen.get(base) ?? 0;
    slugs.add(count === 0 ? base : `${base}-${count}`);
    seen.set(base, count + 1);
  }
  return slugs;
}
