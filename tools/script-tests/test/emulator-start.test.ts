import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const script = path.join(repoRoot, 'scripts', 'emulator-start.sh');
const tempDirs: string[] = [];

after(() => {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
  }
});

/** C:\a\b -> /c/a/b so the path works inside Git Bash as well as on Linux and macOS. */
function toPosix(p: string): string {
  return p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, drive: string) => `/${drive.toLowerCase()}`);
}

interface Scenario {
  /** Number of `getprop sys.boot_completed` calls that answer 0 before answering 1. Infinity = never boots. */
  bootsAfterPolls: number;
  /** An emulator is already listed by `adb devices`. */
  alreadyRunning?: boolean;
  /** The fake emulator process exits immediately. */
  emulatorExits?: boolean;
  /** Omit these tools from PATH. */
  without?: Array<'emulator' | 'adb'>;
  env?: Record<string, string>;
  args?: string[];
}

/**
 * Runs scripts/emulator-start.sh with fake `emulator` and `adb`. The fake adb counts boot polls, and
 * the fake emulator records its arguments and whether it was killed.
 */
function run(scenario: Scenario) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'emu-test-'));
  tempDirs.push(dir);
  const p = (name: string) => toPosix(path.join(dir, name));

  const fakeEmulator = [
    '#!/usr/bin/env bash',
    `echo "$*" > "${p('emulator.args')}"`,
    `echo $$ > "${p('emulator.pid')}"`,
    scenario.emulatorExits === true ? 'exit 0' : `trap 'echo killed > "${p('emulator.killed')}"; exit 0' TERM`,
    scenario.emulatorExits === true ? '' : 'while true; do sleep 0.1; done',
    '',
  ].join('\n');

  const fakeAdb = [
    '#!/usr/bin/env bash',
    'case "$1" in',
    '  devices)',
    scenario.alreadyRunning === true
      ? '    printf "List of devices attached\\nemulator-5556\\tdevice\\n" ;;'
      : `    if [ -f "${p('booted')}" ]; then printf "List of devices attached\\nemulator-5554\\tdevice\\n"; else echo "List of devices attached"; fi ;;`,
    '  start-server) ;;',
    '  shell)',
    '    if [ "$2" = getprop ]; then',
    `      n=$(cat "${p('polls')}" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "${p('polls')}"`,
    `      if [ $n -gt ${Number.isFinite(scenario.bootsAfterPolls) ? scenario.bootsAfterPolls : 1000000} ]; then touch "${p('booted')}"; printf "1\\r\\n"; else printf "0\\r\\n"; fi`,
    `    else echo "$*" >> "${p('adb.shell')}"; fi ;;`,
    'esac',
    'exit 0',
    '',
  ].join('\n');

  const binDir = path.join(dir, 'bin');
  spawnSync('bash', ['-c', `mkdir -p "${toPosix(binDir)}"`]);
  const tools: Record<string, string> = { emulator: fakeEmulator, adb: fakeAdb };
  for (const [name, content] of Object.entries(tools)) {
    if (scenario.without?.includes(name as 'emulator' | 'adb') === true) {
      continue;
    }
    const file = path.join(binDir, name);
    writeFileSync(file, content);
    chmodSync(file, 0o755);
  }

  const result = spawnSync('bash', [toPosix(script), ...(scenario.args ?? [])], {
    encoding: 'utf8',
    timeout: 60_000,
    env: {
      ...process.env,
      PATH: `${binDir}${path.delimiter}${process.env.PATH ?? ''}`,
      BOOT_TIMEOUT: '5',
      POLL_INTERVAL: '0.1',
      ...scenario.env,
    },
  });
  const read = (name: string) => (existsSync(path.join(dir, name)) ? readFileSync(path.join(dir, name), 'utf8').trim() : null);
  // A successfully booted emulator is meant to keep running after the script exits, so the test
  // must stop the fake it started or it would spin forever.
  const pid = read('emulator.pid');
  if (pid !== null) {
    spawnSync('bash', ['-c', `kill -9 ${pid} 2>/dev/null; true`]);
  }
  return {
    status: result.status,
    stdout: result.stdout.trim(),
    stderr: result.stderr,
    emulatorArgs: read('emulator.args'),
    killed: read('emulator.killed') === 'killed',
    polls: Number(read('polls') ?? 0),
    adbShell: read('adb.shell'),
  };
}

describe('scripts/emulator-start.sh', () => {
  it('[NFR-016] boots the default AVD headless and prints the serial once Android reports boot completed', () => {
    const result = run({ bootsAfterPolls: 3 });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'emulator-5554');
    assert.match(result.emulatorArgs ?? '', /^-avd doro_api35 -no-window -no-audio -no-snapshot-save -gpu swiftshader_indirect$/);
    assert.ok(result.polls >= 4, `expected to poll until boot, polled ${result.polls} times`);
    assert.match(result.adbShell ?? '', /input keyevent 82/);
  });

  it('boots a named AVD with custom emulator flags', () => {
    const result = run({ bootsAfterPolls: 0, args: ['my_avd'], env: { EMULATOR_ARGS: '-no-window -wipe-data' } });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.emulatorArgs, '-avd my_avd -no-window -wipe-data');
  });

  it('reuses an emulator that is already running instead of starting another', () => {
    const result = run({ bootsAfterPolls: 0, alreadyRunning: true });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'emulator-5556');
    assert.equal(result.emulatorArgs, null, 'must not launch a second emulator');
    assert.match(result.stderr, /already running/);
  });

  it('times out with exit 1 when Android never finishes booting, and stops the emulator it started', () => {
    const result = run({ bootsAfterPolls: Number.POSITIVE_INFINITY, env: { BOOT_TIMEOUT: '1' } });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /did not finish booting within 1s/);
    assert.equal(result.stdout, '');
    assert.equal(result.killed, true, 'the emulator process must be terminated on timeout');
  });

  it('fails fast when the emulator process dies before booting', () => {
    const result = run({ bootsAfterPolls: Number.POSITIVE_INFINITY, emulatorExits: true, env: { BOOT_TIMEOUT: '30' } });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /emulator process exited before Android booted/);
  });

  for (const tool of ['emulator', 'adb'] as const) {
    it(`reports a missing ${tool} with exit 127 and a hint`, () => {
      const result = run({ bootsAfterPolls: 0, without: [tool] });
      assert.equal(result.status, 127);
      assert.match(result.stderr, new RegExp(`'${tool}' not found on PATH`));
      assert.match(result.stderr, /source scripts\/dev-env\.sh/);
    });
  }
});
