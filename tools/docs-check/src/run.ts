import { checkAdrs } from './checks/adrs.ts';
import { checkIndexReachability } from './checks/index-reachability.ts';
import { checkLinks } from './checks/links.ts';
import { checkRequirements } from './checks/requirements.ts';
import { checkTasks } from './checks/tasks.ts';
import { compareErrors, type DocError } from './errors.ts';
import { DEFAULT_LAYOUT, type Layout, type Snapshot } from './snapshot.ts';

/** Runs every documentation check and returns errors sorted by file and line. */
export function runAllChecks(snapshot: Snapshot, layout: Layout = DEFAULT_LAYOUT): DocError[] {
  const requirements = checkRequirements(snapshot, layout);
  return [
    ...checkLinks(snapshot),
    ...requirements.errors,
    ...checkAdrs(snapshot, layout),
    ...checkTasks(snapshot, layout, requirements.definedIds),
    ...checkIndexReachability(snapshot, layout),
  ].sort(compareErrors);
}
