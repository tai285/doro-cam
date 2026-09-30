import { type DocError, docError } from '../errors.ts';
import { extractLinks } from '../markdown.ts';
import { type Layout, resolveLinkPath, type Snapshot } from '../snapshot.ts';

const EXTERNAL_RE = /^[a-z][a-z0-9+.-]*:/i;

/** Every Markdown file under the docs directory must be reachable by following links from the index. */
export function checkIndexReachability(snapshot: Snapshot, layout: Layout): DocError[] {
  if (!snapshot.docs.has(layout.indexFile)) {
    return [docError('index', layout.indexFile, null, 'documentation index not found')];
  }

  const reachable = new Set<string>([layout.indexFile]);
  const queue = [layout.indexFile];
  while (queue.length > 0) {
    const file = queue.shift();
    const content = file === undefined ? undefined : snapshot.docs.get(file);
    if (file === undefined || content === undefined) {
      continue;
    }
    for (const { target } of extractLinks(content)) {
      if (EXTERNAL_RE.test(target)) {
        continue;
      }
      const pathPart = target.split('#')[0]?.split('?')[0] ?? '';
      if (pathPart === '') {
        continue;
      }
      let decoded: string;
      try {
        decoded = decodeURIComponent(pathPart);
      } catch {
        continue; // reported by the links check
      }
      const resolved = resolveLinkPath(file, decoded);
      if (resolved !== null && snapshot.docs.has(resolved) && !reachable.has(resolved)) {
        reachable.add(resolved);
        queue.push(resolved);
      }
    }
  }

  const prefix = `${layout.docsDir}/`;
  const errors: DocError[] = [];
  for (const file of snapshot.docs.keys()) {
    if (file.startsWith(prefix) && !reachable.has(file)) {
      errors.push(docError('index', file, null, `not reachable from ${layout.indexFile}; link it from the index or a linked page`));
    }
  }
  return errors;
}
