import { readFileSync } from 'node:fs';
import path from 'node:path';
import { parseRequirementDefinitions } from '../checks/requirements.ts';
import { parseTasks, taskStatus } from '../checks/tasks.ts';
import { compareErrors, type DocError, docError } from '../errors.ts';
import { DEFAULT_LAYOUT, type Layout, loadSnapshot } from '../snapshot.ts';
import { scanTags } from './scan.ts';
import { parseWaivers, type Waiver } from './waivers.ts';

export const WAIVERS_FILE = 'docs/product/traceability-waivers.json';
const REQUIREMENT_ID_RE = /(?<![A-Za-z0-9-])[A-Z][A-Z0-9]*-\d{3}\b/g;

export interface RequirementCoverage {
  id: string;
  tagCount: number;
  /** Test files carrying at least one tag for this requirement, sorted. */
  files: string[];
  waived: boolean;
  /** Done tasks that list this requirement. */
  doneTasks: string[];
}

export interface TraceabilityReport {
  requirements: RequirementCoverage[];
  summary: {
    requirementsDefined: number;
    requirementsWithTests: number;
    requirementsWaived: number;
    doneTasksChecked: number;
    tagsFound: number;
    testFilesScanned: number;
  };
}

export interface TraceabilityResult {
  report: TraceabilityReport;
  errors: DocError[];
}

function readIfExists(file: string): string | null {
  try {
    return readFileSync(file, 'utf8');
  } catch {
    return null;
  }
}

/**
 * Proves NFR-015 mechanically: every requirement of a `done` task must be covered by at least one
 * test tagged with its ID, or carry a reasoned waiver. Tags must reference real requirements, and
 * waivers must stay honest (no unknown IDs, no waivers for requirements that now have tests).
 */
export function runTraceability(root: string, layout: Layout = DEFAULT_LAYOUT): TraceabilityResult {
  const absoluteRoot = path.resolve(root);
  const snapshot = loadSnapshot(absoluteRoot, layout);
  const errors: DocError[] = [];

  const requirementsText = snapshot.docs.get(layout.requirementsFile);
  const empty: TraceabilityReport = {
    requirements: [],
    summary: { requirementsDefined: 0, requirementsWithTests: 0, requirementsWaived: 0, doneTasksChecked: 0, tagsFound: 0, testFilesScanned: 0 },
  };
  if (requirementsText === undefined) {
    return { report: empty, errors: [docError('traceability', layout.requirementsFile, null, 'requirements file not found')] };
  }
  const defined = new Set(parseRequirementDefinitions(requirementsText).map((definition) => definition.id));

  const { tags, testFiles } = scanTags(absoluteRoot);
  const filesByRequirement = new Map<string, Set<string>>();
  const tagCounts = new Map<string, number>();
  for (const tag of tags) {
    if (!defined.has(tag.id)) {
      errors.push(docError('traceability', tag.file, tag.line, `unknown requirement tag [${tag.id}]`));
      continue;
    }
    tagCounts.set(tag.id, (tagCounts.get(tag.id) ?? 0) + 1);
    const files = filesByRequirement.get(tag.id) ?? new Set<string>();
    files.add(tag.file);
    filesByRequirement.set(tag.id, files);
  }

  // Waivers.
  let waivers: Waiver[] = [];
  const waiverText = readIfExists(path.join(absoluteRoot, WAIVERS_FILE));
  if (waiverText !== null) {
    const parsed = parseWaivers(waiverText);
    waivers = parsed.waivers;
    for (const problem of parsed.errors) {
      errors.push(docError('traceability', WAIVERS_FILE, null, problem));
    }
  }
  const validWaivers = new Map<string, Waiver>();
  for (const waiver of waivers) {
    if (!defined.has(waiver.requirement)) {
      errors.push(docError('traceability', WAIVERS_FILE, null, `waiver ${waiver.index} names unknown requirement ${waiver.requirement}`));
    } else if ((tagCounts.get(waiver.requirement) ?? 0) > 0) {
      errors.push(
        docError(
          'traceability',
          WAIVERS_FILE,
          null,
          `waiver ${waiver.index} (${waiver.requirement}) is stale: the requirement now has tagged tests, so remove the waiver`,
        ),
      );
    } else {
      validWaivers.set(waiver.requirement, waiver);
    }
  }

  // Done tasks must be covered.
  const doneTasksByRequirement = new Map<string, string[]>();
  let doneTasksChecked = 0;
  for (const [file, content] of snapshot.docs) {
    if (path.posix.dirname(file) !== layout.tasksDir || path.posix.basename(file) === 'README.md') {
      continue;
    }
    for (const task of parseTasks(file, content).tasks) {
      if (taskStatus(task) !== 'done') {
        continue;
      }
      doneTasksChecked += 1;
      const field = task.fields.get('Requirements');
      const ids = [...new Set(field?.value.match(REQUIREMENT_ID_RE) ?? [])];
      for (const id of ids) {
        if (!defined.has(id)) {
          continue; // reported by the requirements and tasks checks
        }
        doneTasksByRequirement.set(id, [...(doneTasksByRequirement.get(id) ?? []), task.id]);
        if ((tagCounts.get(id) ?? 0) === 0 && !validWaivers.has(id)) {
          errors.push(
            docError(
              'traceability',
              file,
              field?.line ?? task.line,
              `task ${task.id} is done but requirement ${id} has no tagged test (add a test tagged [${id}] or a reasoned waiver)`,
            ),
          );
        }
      }
    }
  }

  const requirements: RequirementCoverage[] = [...defined].sort().map((id) => ({
    id,
    tagCount: tagCounts.get(id) ?? 0,
    files: [...(filesByRequirement.get(id) ?? [])].sort(),
    waived: validWaivers.has(id),
    doneTasks: [...new Set(doneTasksByRequirement.get(id) ?? [])].sort(),
  }));

  return {
    report: {
      requirements,
      summary: {
        requirementsDefined: requirements.length,
        requirementsWithTests: requirements.filter((r) => r.tagCount > 0).length,
        requirementsWaived: requirements.filter((r) => r.waived).length,
        doneTasksChecked,
        tagsFound: [...tagCounts.values()].reduce((sum, count) => sum + count, 0),
        testFilesScanned: testFiles.length,
      },
    },
    errors: errors.sort(compareErrors),
  };
}
