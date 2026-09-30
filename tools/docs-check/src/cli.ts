import path from 'node:path';
import { formatError } from './errors.ts';
import { runAllChecks } from './run.ts';
import { DEFAULT_LAYOUT, loadSnapshot } from './snapshot.ts';

const root = path.resolve(process.argv[2] ?? process.cwd());
const snapshot = loadSnapshot(root, DEFAULT_LAYOUT);
const errors = runAllChecks(snapshot, DEFAULT_LAYOUT);

for (const error of errors) {
  console.error(formatError(error));
}
const summary = `docs-check: ${snapshot.docs.size} Markdown files, ${errors.length} error(s)`;
if (errors.length > 0) {
  console.error(summary);
  process.exitCode = 1;
} else {
  console.log(summary);
}
