import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

/** Test files in every language the project uses (Dart, TypeScript, Playwright, Kotlin, Swift). */
const TEST_FILE_PATTERNS: readonly RegExp[] = [
  /\.test\.tsx?$/,
  /\.spec\.tsx?$/,
  /_test\.dart$/,
  /Tests?\.kt$/,
  /Tests?\.swift$/,
];

const SKIPPED_DIRECTORIES = new Set([
  'node_modules',
  '.dart_tool',
  '.git',
  'build',
  'dist',
  'coverage',
  'fixtures',
  'Pods',
  '.gradle',
  'playwright-report',
  'test-results',
]);

export function isTestFile(fileName: string): boolean {
  return TEST_FILE_PATTERNS.some((pattern) => pattern.test(fileName));
}

/** Repository-relative POSIX paths of every test file, sorted. */
export function findTestFiles(root: string): string[] {
  const found: string[] = [];
  const walk = (relativeDir: string): void => {
    const absoluteDir = path.join(root, relativeDir);
    for (const entry of readdirSync(absoluteDir, { withFileTypes: true })) {
      const relativePath = relativeDir === '' ? entry.name : path.posix.join(relativeDir, entry.name);
      if (entry.isDirectory()) {
        if (!SKIPPED_DIRECTORIES.has(entry.name)) {
          walk(relativePath);
        }
      } else if (entry.isFile() && isTestFile(entry.name)) {
        found.push(relativePath);
      }
    }
  };
  walk('');
  return found.sort();
}

export interface TestTag {
  id: string;
  file: string;
  line: number;
}

// Matches a bracketed requirement ID such as [CAM-010]. Task IDs (CAM-T-001) do not match.
const TAG_RE = /\[([A-Z][A-Z0-9]*-\d{3})\]/g;

/**
 * Finds requirement tags anywhere in a test file: in test names, strings and comments. Swift test
 * method names cannot contain brackets, so Swift tests carry their tags in comments.
 */
export function extractTags(file: string, content: string): TestTag[] {
  const tags: TestTag[] = [];
  content.split('\n').forEach((line, index) => {
    for (const match of line.matchAll(TAG_RE)) {
      const id = match[1];
      if (id !== undefined) {
        tags.push({ id, file, line: index + 1 });
      }
    }
  });
  return tags;
}

export function scanTags(root: string): { tags: TestTag[]; testFiles: string[] } {
  const testFiles = findTestFiles(root);
  const tags = testFiles.flatMap((file) =>
    extractTags(file, readFileSync(path.join(root, file), 'utf8').replace(/\r\n?/g, '\n')),
  );
  return { tags, testFiles };
}
