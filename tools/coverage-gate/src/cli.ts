import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { applyRatchet, runGate } from './gate.ts';
import { PolicyError, parsePolicy, serializePolicy } from './policy.ts';

// Usage: node cli.ts [root] [--only name,name] [--update] [--policy file]
const args = process.argv.slice(2);
const flagValue = (flag: string): string | undefined => {
  const index = args.indexOf(flag);
  return index === -1 ? undefined : args[index + 1];
};
for (const flag of ['--only', '--policy']) {
  if (args.includes(flag) && flagValue(flag) === undefined) {
    console.error(`${flag} needs a value`);
    process.exit(2);
  }
}
const valueIndexes = new Set(
  ['--only', '--policy'].map((flag) => args.indexOf(flag) + 1).filter((index) => index > 0),
);
const positional = args.filter((arg, index) => !arg.startsWith('--') && !valueIndexes.has(index));
const root = path.resolve(positional[0] ?? process.cwd());
const policyPath = path.resolve(root, flagValue('--policy') ?? 'coverage-policy.json');
const only = flagValue('--only')?.split(',').map((name) => name.trim()).filter((name) => name !== '');
const update = args.includes('--update');

let policy;
try {
  policy = parsePolicy(readFileSync(policyPath, 'utf8'));
} catch (error) {
  console.error(error instanceof PolicyError ? error.message : `cannot read ${policyPath}: ${String(error)}`);
  process.exit(2);
}

const results = runGate(root, policy, only === undefined ? {} : { only });
let failures = 0;
for (const result of results) {
  const lines = result.summary?.lines.percent;
  const branches = result.summary?.branches.percent;
  const measured =
    result.summary === null
      ? 'no report'
      : `lines ${lines?.toFixed(2) ?? 'n/a'}%` + (branches === null || branches === undefined ? '' : `, branches ${branches.toFixed(2)}%`);
  if (result.errors.length === 0) {
    console.log(`ok    ${result.name}: ${measured}`);
  } else {
    failures += 1;
    console.error(`FAIL  ${result.name}: ${measured}`);
    for (const error of result.errors) {
      console.error(`        - ${error}`);
    }
  }
}

if (update && failures === 0) {
  const updated = serializePolicy(applyRatchet(policy, results));
  if (updated !== serializePolicy(policy)) {
    writeFileSync(policyPath, updated);
    console.log(`Ratchet raised in ${path.relative(root, policyPath)}.`);
  } else {
    console.log('Ratchet already at the current coverage.');
  }
}
console.log(`coverage-gate: ${results.length} package(s) checked, ${failures} failing`);
process.exitCode = failures > 0 ? 1 : 0;
