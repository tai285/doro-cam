import { type DocError, docError } from '../errors.ts';
import { stripFencedCode } from '../markdown.ts';
import type { Layout, Snapshot } from '../snapshot.ts';

export interface RequirementDefinition {
  id: string;
  line: number;
}

const DEFINITION_RE = /^\|\s*([A-Z][A-Z0-9]*-\d{3})\s*\|/;

/** A requirement is defined by a table row whose first cell is its ID. */
export function parseRequirementDefinitions(markdown: string): RequirementDefinition[] {
  const definitions: RequirementDefinition[] = [];
  stripFencedCode(markdown)
    .split('\n')
    .forEach((line, index) => {
      const id = DEFINITION_RE.exec(line)?.[1];
      if (id !== undefined) {
        definitions.push({ id, line: index + 1 });
      }
    });
  return definitions;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Builds a matcher for references using only the prefixes that the requirements file defines. */
export function requirementReferencePattern(definedIds: Iterable<string>): RegExp | null {
  const prefixes = new Set<string>();
  for (const id of definedIds) {
    const prefix = id.slice(0, id.lastIndexOf('-'));
    prefixes.add(escapeRegExp(prefix));
  }
  if (prefixes.size === 0) {
    return null;
  }
  return new RegExp(`(?<![A-Za-z0-9-])(?:${[...prefixes].sort().join('|')})-\\d{3}\\b`, 'g');
}

export interface RequirementsResult {
  errors: DocError[];
  definedIds: Set<string>;
}

/** Requirement IDs are unique, and every reference outside fenced code resolves to a definition. */
export function checkRequirements(snapshot: Snapshot, layout: Layout): RequirementsResult {
  const errors: DocError[] = [];
  const content = snapshot.docs.get(layout.requirementsFile);
  if (content === undefined) {
    errors.push(docError('requirements', layout.requirementsFile, null, 'requirements file not found'));
    return { errors, definedIds: new Set() };
  }

  const definedIds = new Set<string>();
  for (const { id, line } of parseRequirementDefinitions(content)) {
    if (definedIds.has(id)) {
      errors.push(docError('requirements', layout.requirementsFile, line, `duplicate requirement definition ${id}`));
    }
    definedIds.add(id);
  }

  const pattern = requirementReferencePattern(definedIds);
  if (pattern === null) {
    errors.push(docError('requirements', layout.requirementsFile, null, 'no requirement definitions found'));
    return { errors, definedIds };
  }

  for (const [file, markdown] of snapshot.docs) {
    stripFencedCode(markdown)
      .split('\n')
      .forEach((line, index) => {
        for (const match of line.matchAll(pattern)) {
          if (!definedIds.has(match[0])) {
            errors.push(docError('requirements', file, index + 1, `unknown requirement ID ${match[0]}`));
          }
        }
      });
  }
  return { errors, definedIds };
}
