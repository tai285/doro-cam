import { type DocError, docError } from '../errors.ts';
import { extractLinks, headingSlugs } from '../markdown.ts';
import { resolveLinkPath, type Snapshot } from '../snapshot.ts';

const EXTERNAL_RE = /^[a-z][a-z0-9+.-]*:/i;

function safeDecode(value: string): string | null {
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
}

/** Every relative link in a scanned document must resolve to an existing file/dir, and anchors to a heading. */
export function checkLinks(snapshot: Snapshot): DocError[] {
  const errors: DocError[] = [];
  const slugCache = new Map<string, Set<string>>();
  const slugsOf = (file: string): Set<string> => {
    let slugs = slugCache.get(file);
    if (slugs === undefined) {
      slugs = headingSlugs(snapshot.readText(file) ?? '');
      slugCache.set(file, slugs);
    }
    return slugs;
  };

  for (const [file, content] of snapshot.docs) {
    for (const { target, line } of extractLinks(content)) {
      if (EXTERNAL_RE.test(target)) {
        continue;
      }
      const hashIndex = target.indexOf('#');
      const rawPath = (hashIndex === -1 ? target : target.slice(0, hashIndex)).split('?')[0] ?? '';
      const rawAnchor = hashIndex === -1 ? null : target.slice(hashIndex + 1);

      const decodedPath = safeDecode(rawPath);
      const decodedAnchor = rawAnchor === null ? null : safeDecode(rawAnchor);
      if (decodedPath === null || (rawAnchor !== null && decodedAnchor === null)) {
        errors.push(docError('links', file, line, `malformed link target "${target}"`));
        continue;
      }

      const resolved = decodedPath === '' ? file : resolveLinkPath(file, decodedPath);
      if (resolved === null) {
        errors.push(docError('links', file, line, `link "${target}" escapes the repository root`));
        continue;
      }
      const kind = snapshot.kindOf(resolved);
      if (kind === null) {
        errors.push(docError('links', file, line, `broken link "${target}" (no such file: ${resolved})`));
        continue;
      }
      if (decodedAnchor === null || decodedAnchor === '') {
        continue;
      }
      if (kind !== 'file' || !resolved.endsWith('.md')) {
        errors.push(docError('links', file, line, `anchor "#${decodedAnchor}" used on non-Markdown target ${resolved}`));
        continue;
      }
      if (!slugsOf(resolved).has(decodedAnchor)) {
        errors.push(docError('links', file, line, `missing anchor "#${decodedAnchor}" in ${resolved}`));
      }
    }
  }
  return errors;
}
