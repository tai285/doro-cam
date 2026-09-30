import path from 'node:path';
import { type DocError, docError } from '../errors.ts';
import { extractHeadings, stripFencedCode } from '../markdown.ts';
import type { Layout, Snapshot } from '../snapshot.ts';

const ADR_FILE_RE = /^(\d{4})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$/;
const TITLE_RE = /^# ADR-(\d{4}): \S/;
const STATUS_RE = /^Status:\s*(.*)$/m;
const STATUS_VALUE_RE = /^(?:Proposed|Accepted|Deprecated|Superseded by ADR-\d{4})\b/;
const DATE_RE = /^Date:\s*(.*)$/m;
const REFERENCE_RE = /\bADR-(\d{4})\b/g;
const TEMPLATE_NUMBER = '0000';

export const REQUIRED_ADR_SECTIONS = ['Context', 'Decision', 'Alternatives', 'Consequences'] as const;

function isValidIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function checkAdrContent(file: string, number: string, content: string): DocError[] {
  const errors: DocError[] = [];
  const firstLine = content.split('\n')[0] ?? '';
  const titleNumber = TITLE_RE.exec(firstLine)?.[1];
  if (titleNumber === undefined) {
    errors.push(docError('adrs', file, 1, 'first line must be "# ADR-NNNN: Title"'));
  } else if (titleNumber !== number) {
    errors.push(docError('adrs', file, 1, `title number ADR-${titleNumber} does not match file number ${number}`));
  }

  const status = STATUS_RE.exec(content)?.[1]?.trim();
  if (status === undefined) {
    errors.push(docError('adrs', file, null, 'missing "Status:" line'));
  } else if (!STATUS_VALUE_RE.test(status)) {
    errors.push(docError('adrs', file, null, `invalid status "${status}"`));
  }

  const date = DATE_RE.exec(content)?.[1]?.trim();
  if (date === undefined) {
    errors.push(docError('adrs', file, null, 'missing "Date:" line'));
  } else if (!isValidIsoDate(date)) {
    errors.push(docError('adrs', file, null, `invalid date "${date}" (expected YYYY-MM-DD)`));
  }

  const sections = new Set(
    extractHeadings(content)
      .filter((heading) => heading.level === 2)
      .map((heading) => heading.text.trim()),
  );
  for (const section of REQUIRED_ADR_SECTIONS) {
    if (!sections.has(section)) {
      errors.push(docError('adrs', file, null, `missing section "## ${section}"`));
    }
  }
  return errors;
}

/** ADR files are well-formed, uniquely numbered, and every ADR-NNNN reference resolves. */
export function checkAdrs(snapshot: Snapshot, layout: Layout): DocError[] {
  const errors: DocError[] = [];
  const numbers = new Map<string, string>();

  for (const [file, content] of snapshot.docs) {
    if (path.posix.dirname(file) !== layout.adrDir) {
      continue;
    }
    const name = path.posix.basename(file);
    if (name === 'README.md') {
      continue;
    }
    const number = ADR_FILE_RE.exec(name)?.[1];
    if (number === undefined) {
      errors.push(docError('adrs', file, null, 'ADR file name must match NNNN-kebab-case-title.md'));
      continue;
    }
    const existing = numbers.get(number);
    if (existing !== undefined) {
      errors.push(docError('adrs', file, null, `duplicate ADR number ${number} (also ${existing})`));
      continue;
    }
    numbers.set(number, file);
    if (number !== TEMPLATE_NUMBER) {
      errors.push(...checkAdrContent(file, number, content));
    }
  }

  for (const [file, markdown] of snapshot.docs) {
    stripFencedCode(markdown)
      .split('\n')
      .forEach((line, index) => {
        for (const match of line.matchAll(REFERENCE_RE)) {
          const number = match[1];
          if (number !== undefined && !numbers.has(number)) {
            errors.push(docError('adrs', file, index + 1, `reference to missing ${match[0]}`));
          }
        }
      });
  }
  return errors;
}
