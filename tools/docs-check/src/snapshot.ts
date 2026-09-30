import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

/** Where the documentation lives, relative to the repository root (POSIX separators). */
export interface Layout {
  docsDir: string;
  indexFile: string;
  requirementsFile: string;
  adrDir: string;
  tasksDir: string;
}

export const DEFAULT_LAYOUT: Layout = {
  docsDir: 'docs',
  indexFile: 'docs/README.md',
  requirementsFile: 'docs/product/requirements.md',
  adrDir: 'docs/decisions/adr',
  tasksDir: 'docs/tasks',
};

export type PathKind = 'file' | 'dir';

/** A read-only view of the repository used by all checks. */
export interface Snapshot {
  /** Scanned Markdown documents: POSIX path relative to root → content (LF line endings). */
  readonly docs: ReadonlyMap<string, string>;
  kindOf(relativePath: string): PathKind | null;
  readText(relativePath: string): string | null;
}

function normalizeNewlines(text: string): string {
  return text.replace(/\r\n?/g, '\n');
}

function collectMarkdown(root: string, relativeDir: string, into: Map<string, string>): void {
  const absoluteDir = path.join(root, relativeDir);
  const entries = readdirSync(absoluteDir, { withFileTypes: true }).sort((a, b) =>
    a.name.localeCompare(b.name),
  );
  for (const entry of entries) {
    const relativePath = path.posix.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      collectMarkdown(root, relativePath, into);
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      into.set(relativePath, normalizeNewlines(readFileSync(path.join(root, relativePath), 'utf8')));
    }
  }
}

/** Top-level folders searched for package-level AGENTS.md files. */
const AGENT_FILE_ROOTS = ['apps', 'packages', 'services', 'tools'] as const;
const AGENT_FILE_NAME = 'AGENTS.md';
const SKIPPED_DIRECTORIES = new Set(['node_modules', '.dart_tool', 'build', 'dist', 'coverage', 'fixtures', '.git']);

function collectNestedAgentFiles(root: string, relativeDir: string, into: Map<string, string>): void {
  const absoluteDir = path.join(root, relativeDir);
  if (!existsSync(absoluteDir)) {
    return;
  }
  const entries = readdirSync(absoluteDir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const relativePath = path.posix.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRECTORIES.has(entry.name)) {
        collectNestedAgentFiles(root, relativePath, into);
      }
    } else if (entry.isFile() && entry.name === AGENT_FILE_NAME) {
      into.set(relativePath, normalizeNewlines(readFileSync(path.join(root, relativePath), 'utf8')));
    }
  }
}

/**
 * Loads root-level Markdown files, every Markdown file under `layout.docsDir`, and package-level
 * AGENTS.md files under apps/, packages/, services/ and tools/. Everything else (source,
 * fixtures, node_modules) is not scanned but can still be a link target.
 */
export function loadSnapshot(root: string, layout: Layout = DEFAULT_LAYOUT): Snapshot {
  const absoluteRoot = path.resolve(root);
  const docs = new Map<string, string>();
  for (const entry of readdirSync(absoluteRoot, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.endsWith('.md')) {
      docs.set(entry.name, normalizeNewlines(readFileSync(path.join(absoluteRoot, entry.name), 'utf8')));
    }
  }
  if (existsSync(path.join(absoluteRoot, layout.docsDir))) {
    collectMarkdown(absoluteRoot, layout.docsDir, docs);
  }
  for (const agentRoot of AGENT_FILE_ROOTS) {
    collectNestedAgentFiles(absoluteRoot, agentRoot, docs);
  }

  return {
    docs,
    kindOf(relativePath) {
      const absolute = path.join(absoluteRoot, relativePath);
      if (!existsSync(absolute)) {
        return null;
      }
      return statSync(absolute).isDirectory() ? 'dir' : 'file';
    },
    readText(relativePath) {
      const cached = docs.get(relativePath);
      if (cached !== undefined) {
        return cached;
      }
      const absolute = path.join(absoluteRoot, relativePath);
      if (!existsSync(absolute) || statSync(absolute).isDirectory()) {
        return null;
      }
      return normalizeNewlines(readFileSync(absolute, 'utf8'));
    },
  };
}

/**
 * Resolves a link target found in `fromFile` to a repository-relative POSIX path.
 * Returns null when the target escapes the repository root.
 */
export function resolveLinkPath(fromFile: string, target: string): string | null {
  const joined = target.startsWith('/')
    ? target.slice(1)
    : path.posix.join(path.posix.dirname(fromFile), target);
  const normalized = path.posix.normalize(joined === '' ? '.' : joined).replace(/\/$/, '');
  if (normalized === '..' || normalized.startsWith('../')) {
    return null;
  }
  return normalized;
}
