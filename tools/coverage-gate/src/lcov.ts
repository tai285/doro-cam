export interface FileCoverage {
  file: string;
  linesFound: number;
  linesHit: number;
  branchesFound: number;
  branchesHit: number;
}

export interface Ratio {
  found: number;
  hit: number;
  /** Percentage rounded to two decimals, or null when there was nothing to measure. */
  percent: number | null;
}

export interface CoverageSummary {
  files: number;
  lines: Ratio;
  branches: Ratio;
}

/** Forward slashes, so Windows paths from Dart match the same globs as POSIX paths. */
function normalizePath(file: string): string {
  return file.replace(/\\/g, '/');
}

/**
 * Parses an lcov.info report (Dart `flutter test --coverage`, Vitest, Node's test runner).
 * Totals come from LF/LH and BRF/BRH when present, otherwise from the DA and BRDA records.
 */
export function parseLcov(text: string): FileCoverage[] {
  const files: FileCoverage[] = [];
  let current: { file: string; daFound: number; daHit: number; brdaFound: number; brdaHit: number } & {
    lf?: number;
    lh?: number;
    brf?: number;
    brh?: number;
  } | null = null;

  const close = (): void => {
    if (current === null) {
      return;
    }
    files.push({
      file: current.file,
      linesFound: current.lf ?? current.daFound,
      linesHit: current.lh ?? current.daHit,
      branchesFound: current.brf ?? current.brdaFound,
      branchesHit: current.brh ?? current.brdaHit,
    });
    current = null;
  };

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.startsWith('SF:')) {
      close();
      current = { file: normalizePath(line.slice(3)), daFound: 0, daHit: 0, brdaFound: 0, brdaHit: 0 };
    } else if (current === null) {
      continue;
    } else if (line.startsWith('DA:')) {
      const hits = Number(line.slice(3).split(',')[1]);
      current.daFound += 1;
      if (hits > 0) {
        current.daHit += 1;
      }
    } else if (line.startsWith('BRDA:')) {
      const taken = line.slice(5).split(',')[3];
      current.brdaFound += 1;
      if (taken !== undefined && taken !== '-' && Number(taken) > 0) {
        current.brdaHit += 1;
      }
    } else if (line.startsWith('LF:')) {
      current.lf = Number(line.slice(3));
    } else if (line.startsWith('LH:')) {
      current.lh = Number(line.slice(3));
    } else if (line.startsWith('BRF:')) {
      current.brf = Number(line.slice(4));
    } else if (line.startsWith('BRH:')) {
      current.brh = Number(line.slice(4));
    } else if (line === 'end_of_record') {
      close();
    }
  }
  close();
  return files;
}

/** Converts a glob (`**`, `*`, `?`) to an anchored regular expression over POSIX-style paths. */
export function globToRegExp(glob: string): RegExp {
  let pattern = '';
  for (let i = 0; i < glob.length; i += 1) {
    const char = glob.charAt(i);
    if (char === '*') {
      if (glob.charAt(i + 1) === '*') {
        // "**/" matches zero or more directories; a trailing "**" matches everything.
        if (glob.charAt(i + 2) === '/') {
          pattern += '(?:.*/)?';
          i += 2;
        } else {
          pattern += '.*';
          i += 1;
        }
      } else {
        pattern += '[^/]*';
      }
    } else if (char === '?') {
      pattern += '[^/]';
    } else {
      pattern += char.replace(/[.+^${}()|[\]\\]/g, '\\$&');
    }
  }
  return new RegExp(`^${pattern}$`);
}

export function isExcluded(file: string, globs: readonly string[]): boolean {
  const normalized = normalizePath(file);
  return globs.some((glob) => globToRegExp(glob).test(normalized));
}

function ratio(found: number, hit: number): Ratio {
  return { found, hit, percent: found === 0 ? null : Math.round((hit / found) * 10000) / 100 };
}

/** Totals coverage over every file that is not excluded. */
export function summarize(records: readonly FileCoverage[], exclude: readonly string[]): CoverageSummary {
  const included = records.filter((record) => !isExcluded(record.file, exclude));
  const sum = (pick: (record: FileCoverage) => number): number =>
    included.reduce((total, record) => total + pick(record), 0);
  return {
    files: included.length,
    lines: ratio(sum((r) => r.linesFound), sum((r) => r.linesHit)),
    branches: ratio(sum((r) => r.branchesFound), sum((r) => r.branchesHit)),
  };
}
