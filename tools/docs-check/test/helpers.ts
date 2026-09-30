import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compareErrors, type DocError, formatError } from '../src/errors.ts';
import { DEFAULT_LAYOUT, loadSnapshot, type Snapshot } from '../src/snapshot.ts';

const here = path.dirname(fileURLToPath(import.meta.url));

export const FIXTURES_DIR = path.join(here, '..', 'fixtures');
export const REPO_ROOT = path.join(here, '..', '..', '..');
export const CLI_PATH = path.join(here, '..', 'src', 'cli.ts');

export function fixture(name: string): Snapshot {
  return loadSnapshot(path.join(FIXTURES_DIR, name), DEFAULT_LAYOUT);
}

/** Sorted, human-readable error lines: makes assertion failures easy to read. */
export function lines(errors: readonly DocError[]): string[] {
  return [...errors].sort(compareErrors).map(formatError);
}
