import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const script = path.join(repoRoot, 'scripts', 'run-with-retry.sh');
const tempDirs: string[] = [];

after(() => {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function toPosix(p: string): string {
  return p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, drive: string) => `/${drive.toLowerCase()}`);
}

/**
 * Creates a fake command. `behaviors[n]` is what attempt n does: 'ok', 'fail' or 'hang'. The command
 * counts its own invocations in a file, so tests can assert how often it was run.
 */
function fakeCommand(behaviors: Array<'ok' | 'fail' | 'hang'>) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'retry-test-'));
  tempDirs.push(dir);
  const counter = path.join(dir, 'count');
  const hung = path.join(dir, 'hung');
  const file = path.join(dir, 'fake-command');
  writeFileSync(
    file,
    [
      '#!/usr/bin/env bash',
      `n=$(cat "${toPosix(counter)}" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "${toPosix(counter)}"`,
      `behaviors=(${behaviors.join(' ')})`,
      'behavior="${behaviors[$((n-1))]:-${behaviors[${#behaviors[@]}-1]}}"',
      'echo "attempt $n runs: $behavior"',
      'case "$behavior" in',
      '  ok) exit 0 ;;',
      '  fail) echo "attempt $n failed" >&2; exit 7 ;;',
      `  hang) trap 'echo terminated > "${toPosix(hung)}"; exit 143' TERM; while true; do sleep 0.1; done ;;`,
      'esac',
      '',
    ].join('\n'),
  );
  chmodSync(file, 0o755);
  return {
    command: toPosix(file),
    runs: () => Number(existsSync(counter) ? readFileSync(counter, 'utf8').trim() : 0),
    wasTerminated: () => existsSync(hung),
  };
}

function run(args: string[]) {
  const result = spawnSync('bash', [toPosix(script), ...args], { encoding: 'utf8', timeout: 60_000 });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe('scripts/run-with-retry.sh', () => {
  it('runs a passing command once and exits 0', () => {
    const fake = fakeCommand(['ok']);
    const result = run(['--attempts', '3', '--timeout', '5', '--', fake.command]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fake.runs(), 1);
    assert.match(result.stdout, /attempt 1 runs: ok/);
  });

  it('retries a failing command and succeeds when a later attempt passes', () => {
    const fake = fakeCommand(['fail', 'fail', 'ok']);
    const result = run(['--attempts', '3', '--timeout', '5', '--', fake.command]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fake.runs(), 3);
    assert.match(result.stderr, /attempt 1 of 3 failed with exit code 7/);
    assert.match(result.stderr, /attempt 2 of 3 failed with exit code 7/);
  });

  it('[NFR-016] kills a stalled attempt after the timeout and retries it', () => {
    const fake = fakeCommand(['hang', 'ok']);
    const started = Date.now();
    const result = run(['--attempts', '2', '--timeout', '1', '--', fake.command]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fake.runs(), 2);
    assert.match(result.stderr, /attempt 1 of 2 timed out after 1s/);
    assert.equal(fake.wasTerminated(), true, 'the stalled process must be terminated');
    assert.ok(Date.now() - started < 30_000);
  });

  it('gives up after the last attempt with the failing exit code', () => {
    const fake = fakeCommand(['fail']);
    const result = run(['--attempts', '2', '--timeout', '5', '--', fake.command]);
    assert.equal(result.status, 7);
    assert.equal(fake.runs(), 2);
    assert.match(result.stderr, /all 2 attempts failed/);
  });

  it('exits 124 when every attempt stalls', () => {
    const fake = fakeCommand(['hang']);
    const result = run(['--attempts', '2', '--timeout', '1', '--', fake.command]);
    assert.equal(result.status, 124);
    assert.equal(fake.runs(), 2);
    assert.match(result.stderr, /all 2 attempts failed/);
  });

  it('defaults to 3 attempts', () => {
    const fake = fakeCommand(['fail']);
    const result = run(['--timeout', '5', '--', fake.command]);
    assert.equal(result.status, 7);
    assert.equal(fake.runs(), 3);
  });

  it('passes the command arguments through unchanged', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'retry-args-'));
    tempDirs.push(dir);
    const file = path.join(dir, 'echo-args');
    writeFileSync(file, '#!/usr/bin/env bash\nfor a in "$@"; do echo "arg=[$a]"; done\n');
    chmodSync(file, 0o755);
    const result = run(['--attempts', '1', '--timeout', '5', '--', toPosix(file), 'one two', '--flag', 'x=y']);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /arg=\[one two\]/);
    assert.match(result.stdout, /arg=\[--flag\]/);
    assert.match(result.stdout, /arg=\[x=y\]/);
  });

  const usageErrors: ReadonlyArray<[string, string[]]> = [
    ['no command after --', ['--attempts', '2', '--']],
    ['no -- separator', ['--attempts', '2', 'true']],
    ['non-numeric attempts', ['--attempts', 'many', '--', 'true']],
    ['zero attempts', ['--attempts', '0', '--', 'true']],
    ['non-numeric timeout', ['--timeout', 'soon', '--', 'true']],
    ['an unknown option', ['--bogus', '1', '--', 'true']],
    ['a missing option value', ['--attempts']],
  ];
  for (const [name, args] of usageErrors) {
    it(`exits 2 with usage for ${name}`, () => {
      const result = run(args);
      assert.equal(result.status, 2);
      assert.match(result.stderr, /usage:/);
    });
  }
});
