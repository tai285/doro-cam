import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { formatError } from './errors.ts';
import { runTraceability } from './traceability/run.ts';

// Usage: node traceability-cli.ts [root] [--json <file>]
const args = process.argv.slice(2);
const jsonIndex = args.indexOf('--json');
const jsonPath = jsonIndex === -1 ? undefined : args[jsonIndex + 1];
if (jsonIndex !== -1 && jsonPath === undefined) {
  console.error('--json needs a file path');
  process.exit(2);
}
const positional = jsonIndex === -1 ? args : args.filter((_, index) => index !== jsonIndex && index !== jsonIndex + 1);
const root = path.resolve(positional[0] ?? process.cwd());

const { report, errors } = runTraceability(root);
if (jsonPath !== undefined) {
  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
}

const { summary } = report;
const line =
  `traceability: ${summary.requirementsDefined} requirements defined, ` +
  `${summary.requirementsWithTests} with tagged tests, ${summary.requirementsWaived} waived; ` +
  `${summary.doneTasksChecked} done tasks checked, ${errors.length} error(s)`;

for (const error of errors) {
  console.error(formatError(error));
}
if (errors.length > 0) {
  console.error(line);
  process.exitCode = 1;
} else {
  console.log(line);
}
