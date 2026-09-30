import path from 'node:path';
import { type DocError, docError } from '../errors.ts';
import { stripFencedCode } from '../markdown.ts';
import type { Layout, Snapshot } from '../snapshot.ts';

const TASK_ID = '[A-Z][A-Z0-9]*-T-\\d{3}';
const TASK_HEADING_RE = new RegExp(`^###\\s+(${TASK_ID})(?:\\s+(.*))?$`);
const TASK_LIKE_HEADING_RE = /^###\s+[A-Z][A-Z0-9]*-T-/;
const TASK_ID_RE = new RegExp(`^${TASK_ID}$`);
const ANY_HEADING_RE = /^ {0,3}#{1,6}\s/;
const FIELD_RE = /^-\s+\*\*([A-Za-z][A-Za-z ]*):\*\*\s*(.*)$/;
const STATUS_RE = /^(todo|in-progress|blocked|done)\b(.*)$/;
const BLOCKED_REASON_RE = /^\s*\(\s*\S.*\)\s*$/;
const NOT_APPLICABLE_RE = /^n\/a\b(.*)$/i;
const LEADING_REASON_RE = /^\s*\([^)]*\S[^)]*\)/;
// The lookbehind stops "T-003" inside a task ID such as "CAM-T-003" from matching.
const REQUIREMENT_ID_RE = /(?<![A-Za-z0-9-])[A-Z][A-Z0-9]*-\d{3}\b/g;

export const REQUIRED_TASK_FIELDS = ['Status', 'Depends', 'Requirements', 'Acceptance', 'Tests'] as const;

export type TaskStatus = 'todo' | 'in-progress' | 'blocked' | 'done';

export interface TaskField {
  value: string;
  line: number;
}

export interface Task {
  id: string;
  title: string;
  file: string;
  line: number;
  fields: Map<string, TaskField>;
}

export interface ParsedTasks {
  tasks: Task[];
  errors: DocError[];
}

/** Parses `### <ID> <title>` sections and their `- **Field:** value` lines. */
export function parseTasks(file: string, markdown: string): ParsedTasks {
  const tasks: Task[] = [];
  const errors: DocError[] = [];
  let current: Task | null = null;

  stripFencedCode(markdown)
    .split('\n')
    .forEach((text, index) => {
      const line = index + 1;
      const heading = TASK_HEADING_RE.exec(text);
      if (heading?.[1] !== undefined) {
        const title = heading[2]?.trim() ?? '';
        current = { id: heading[1], title, file, line, fields: new Map() };
        tasks.push(current);
        if (title === '') {
          errors.push(docError('tasks', file, line, `task ${heading[1]} has no title`));
        }
        return;
      }
      if (TASK_LIKE_HEADING_RE.test(text)) {
        errors.push(docError('tasks', file, line, `malformed task ID in heading "${text.trim()}"`));
        current = null;
        return;
      }
      if (ANY_HEADING_RE.test(text)) {
        current = null;
        return;
      }
      const field = FIELD_RE.exec(text);
      if (current !== null && field?.[1] !== undefined) {
        const name = field[1].trim();
        if (current.fields.has(name)) {
          errors.push(docError('tasks', file, line, `task ${current.id} repeats field "${name}"`));
        } else {
          current.fields.set(name, { value: (field[2] ?? '').trim(), line });
        }
      }
    });
  return { tasks, errors };
}

export function taskStatus(task: Task): TaskStatus | null {
  const value = task.fields.get('Status')?.value ?? '';
  const status = STATUS_RE.exec(value)?.[1];
  return status === 'todo' || status === 'in-progress' || status === 'blocked' || status === 'done'
    ? status
    : null;
}

function parseDepends(value: string): string[] {
  if (value.trim().toLowerCase() === 'none') {
    return [];
  }
  return value
    .split(',')
    .map((part) => part.trim())
    .filter((part) => part !== '');
}

/** Finds dependency cycles; each cycle is reported once, as the list of IDs in order. */
export function findCycles(graph: ReadonlyMap<string, readonly string[]>): string[][] {
  const state = new Map<string, 'visiting' | 'done'>();
  const stack: string[] = [];
  const cycles: string[][] = [];
  const reported = new Set<string>();

  const visit = (node: string): void => {
    state.set(node, 'visiting');
    stack.push(node);
    for (const next of graph.get(node) ?? []) {
      if (!graph.has(next)) {
        continue;
      }
      const nextState = state.get(next);
      if (nextState === 'visiting') {
        const cycle = stack.slice(stack.indexOf(next));
        const key = [...cycle].sort().join(',');
        if (!reported.has(key)) {
          reported.add(key);
          cycles.push([...cycle, next]);
        }
      } else if (nextState === undefined) {
        visit(next);
      }
    }
    stack.pop();
    state.set(node, 'done');
  };

  for (const node of [...graph.keys()].sort()) {
    if (!state.has(node)) {
      visit(node);
    }
  }
  return cycles;
}

/** Task sections are complete, reference real tasks and requirements, and form an acyclic graph. */
export function checkTasks(snapshot: Snapshot, layout: Layout, requirementIds: ReadonlySet<string>): DocError[] {
  const errors: DocError[] = [];
  const tasks = new Map<string, Task>();

  for (const [file, content] of snapshot.docs) {
    if (path.posix.dirname(file) !== layout.tasksDir || path.posix.basename(file) === 'README.md') {
      continue;
    }
    const parsed = parseTasks(file, content);
    errors.push(...parsed.errors);
    for (const task of parsed.tasks) {
      const existing = tasks.get(task.id);
      if (existing !== undefined) {
        errors.push(docError('tasks', file, task.line, `duplicate task ID ${task.id} (first defined in ${existing.file}:${existing.line})`));
        continue;
      }
      tasks.set(task.id, task);
    }
  }

  const graph = new Map<string, string[]>();
  for (const task of tasks.values()) {
    for (const field of REQUIRED_TASK_FIELDS) {
      if (!task.fields.has(field)) {
        errors.push(docError('tasks', task.file, task.line, `task ${task.id} is missing field "${field}"`));
      }
    }

    const status = task.fields.get('Status');
    if (status !== undefined) {
      const match = STATUS_RE.exec(status.value);
      if (match === null) {
        errors.push(docError('tasks', task.file, status.line, `task ${task.id} has invalid status "${status.value}"`));
      } else if (match[1] === 'blocked' && !BLOCKED_REASON_RE.test(match[2] ?? '')) {
        errors.push(docError('tasks', task.file, status.line, `task ${task.id} is blocked without a "(reason)"`));
      }
    }

    const tests = task.fields.get('Tests');
    if (tests !== undefined) {
      const notApplicable = NOT_APPLICABLE_RE.exec(tests.value);
      if (tests.value === '') {
        errors.push(docError('tasks', task.file, tests.line, `task ${task.id} has an empty Tests field`));
      } else if (notApplicable !== null && !LEADING_REASON_RE.test(notApplicable[1] ?? '')) {
        errors.push(docError('tasks', task.file, tests.line, `task ${task.id} has "n/a" Tests without a "(reason)"`));
      }
    }

    const requirements = task.fields.get('Requirements');
    if (requirements !== undefined) {
      const ids = requirements.value.match(REQUIREMENT_ID_RE) ?? [];
      if (ids.length === 0) {
        errors.push(docError('tasks', task.file, requirements.line, `task ${task.id} lists no requirement IDs`));
      }
      for (const id of ids) {
        if (!requirementIds.has(id)) {
          errors.push(docError('tasks', task.file, requirements.line, `task ${task.id} references unknown requirement ${id}`));
        }
      }
    }

    const depends = task.fields.get('Depends');
    const dependencies: string[] = [];
    if (depends !== undefined) {
      for (const dependency of parseDepends(depends.value)) {
        if (!TASK_ID_RE.test(dependency)) {
          errors.push(docError('tasks', task.file, depends.line, `task ${task.id} has invalid dependency "${dependency}"`));
        } else if (dependency === task.id) {
          errors.push(docError('tasks', task.file, depends.line, `task ${task.id} depends on itself`));
        } else if (!tasks.has(dependency)) {
          errors.push(docError('tasks', task.file, depends.line, `task ${task.id} depends on unknown task ${dependency}`));
        } else {
          dependencies.push(dependency);
        }
      }
    }
    graph.set(task.id, dependencies);
  }

  for (const task of tasks.values()) {
    if (taskStatus(task) !== 'done') {
      continue;
    }
    for (const dependency of graph.get(task.id) ?? []) {
      const dependencyTask = tasks.get(dependency);
      if (dependencyTask !== undefined && taskStatus(dependencyTask) !== 'done') {
        const line = task.fields.get('Depends')?.line ?? task.line;
        errors.push(docError('tasks', task.file, line, `task ${task.id} is done but depends on unfinished task ${dependency}`));
      }
    }
  }

  for (const cycle of findCycles(graph)) {
    const first = cycle[0];
    const task = first === undefined ? undefined : tasks.get(first);
    if (task !== undefined) {
      errors.push(docError('tasks', task.file, task.line, `dependency cycle: ${cycle.join(' -> ')}`));
    }
  }
  return errors;
}
