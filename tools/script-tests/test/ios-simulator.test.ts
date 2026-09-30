import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const script = path.join(repoRoot, 'scripts', 'ios-simulator.sh');
const tempDirs: string[] = [];

after(() => {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
  }
});

interface FakeDevice {
  name: string;
  udid: string;
  isAvailable?: boolean;
}

/** Builds `simctl list devices available -j` output: runtime key -> devices. */
function devicesJson(runtimes: Record<string, FakeDevice[]>): string {
  return JSON.stringify({
    devices: Object.fromEntries(
      Object.entries(runtimes).map(([runtime, devices]) => [
        `com.apple.CoreSimulator.SimRuntime.${runtime}`,
        devices.map((d) => ({ isAvailable: true, ...d })),
      ]),
    ),
  });
}

/** C:\a\b -> /c/a/b so the path works inside Git Bash as well as on Linux and macOS. */
function toPosix(p: string): string {
  return p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, drive: string) => `/${drive.toLowerCase()}`);
}

/**
 * Runs scripts/ios-simulator.sh with fake `xcrun` and `xcodebuild` on PATH. The fake xcrun prints
 * the given device list and records every call, so tests can assert which simulator was booted.
 */
function run(devices: string, env: Record<string, string> = {}) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'ios-sim-test-'));
  tempDirs.push(dir);
  writeFileSync(path.join(dir, 'devices.json'), devices);
  const log = path.join(dir, 'calls.log');

  writeFileSync(
    path.join(dir, 'xcrun'),
    [
      '#!/usr/bin/env bash',
      `echo "xcrun $*" >> "${toPosix(log)}"`,
      'if [ "$1" = simctl ] && [ "$2" = list ] && [ "$3" = runtimes ]; then',
      '  echo "iOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6"',
      'elif [ "$1" = simctl ] && [ "$2" = list ] && [ "$3" = devices ]; then',
      `  cat "${toPosix(path.join(dir, 'devices.json'))}"`,
      'fi',
      'exit 0',
      '',
    ].join('\n'),
  );
  writeFileSync(
    path.join(dir, 'xcodebuild'),
    '#!/usr/bin/env bash\necho "Xcode 16.4"\necho "Build version 16F6"\n',
  );
  chmodSync(path.join(dir, 'xcrun'), 0o755);
  chmodSync(path.join(dir, 'xcodebuild'), 0o755);

  const result = spawnSync('bash', [toPosix(script)], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${dir}${path.delimiter}${process.env.PATH ?? ''}`, ...env },
  });
  const calls = spawnSync('bash', ['-c', `cat "${toPosix(log)}" 2>/dev/null || true`], {
    encoding: 'utf8',
  }).stdout;
  return { status: result.status, stdout: result.stdout.trim(), stderr: result.stderr, calls };
}

const IPHONE_12_PRO_MAX = 'iPhone 12 Pro Max';

describe('scripts/ios-simulator.sh', () => {
  it('[NFR-016] picks the iPhone 12 Pro Max when present and boots exactly that simulator', () => {
    const result = run(
      devicesJson({
        'iOS-18-6': [
          { name: 'iPhone 16', udid: 'UDID-16' },
          { name: IPHONE_12_PRO_MAX, udid: 'UDID-12PM' },
        ],
        'iOS-26-2': [{ name: 'iPhone 17', udid: 'UDID-17' }],
      }),
    );
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'UDID-12PM');
    assert.match(
      result.stderr,
      /Selected iPhone 12 Pro Max on com\.apple\.CoreSimulator\.SimRuntime\.iOS-18-6/,
    );
    assert.match(result.calls, /xcrun simctl boot UDID-12PM/);
    assert.match(result.calls, /xcrun simctl bootstatus UDID-12PM -b/);
  });

  it('prefers the iOS 18 runtime over a newer one for the same device name', () => {
    const result = run(
      devicesJson({
        'iOS-18-6': [{ name: 'iPhone 16 Pro Max', udid: 'UDID-18' }],
        'iOS-26-2': [{ name: 'iPhone 16 Pro Max', udid: 'UDID-26' }],
      }),
    );
    assert.equal(result.stdout, 'UDID-18');
  });

  it('follows the device preference order when the first choice is missing', () => {
    const result = run(
      devicesJson({
        'iOS-18-6': [
          { name: 'iPhone 16', udid: 'UDID-16' },
          { name: 'iPhone 16 Pro Max', udid: 'UDID-16PM' },
          { name: 'iPhone SE (3rd generation)', udid: 'UDID-SE' },
        ],
      }),
    );
    assert.equal(result.stdout, 'UDID-16PM');
  });

  it('falls back to the newest runtime when the preferred major has no matching device', () => {
    const result = run(
      devicesJson({
        'iOS-17-5': [{ name: 'iPhone 15', udid: 'UDID-OLD' }],
        'iOS-26-2': [{ name: 'iPhone 16 Pro', udid: 'UDID-26' }],
      }),
    );
    assert.equal(result.stdout, 'UDID-26');
  });

  it('falls back to any available iPhone when no preferred device exists', () => {
    const result = run(
      devicesJson({
        'iOS-18-6': [
          { name: 'iPad Pro 13-inch', udid: 'UDID-IPAD' },
          { name: 'iPhone SE (3rd generation)', udid: 'UDID-SE' },
        ],
      }),
    );
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'UDID-SE');
    assert.match(result.stderr, /Selected fallback iPhone SE/);
  });

  it('ignores unavailable devices and non-iOS runtimes', () => {
    const result = run(
      devicesJson({
        'iOS-18-6': [{ name: IPHONE_12_PRO_MAX, udid: 'UDID-BROKEN', isAvailable: false }],
        'tvOS-18-5': [{ name: IPHONE_12_PRO_MAX, udid: 'UDID-TV' }],
        'iOS-26-2': [{ name: 'iPhone 16', udid: 'UDID-OK' }],
      }),
    );
    assert.equal(result.stdout, 'UDID-OK');
  });

  it('honours DEVICE_NAME and IOS_RUNTIME_MAJOR overrides', () => {
    const result = run(
      devicesJson({
        'iOS-18-6': [{ name: 'iPhone 16', udid: 'UDID-18' }],
        'iOS-26-2': [{ name: 'iPhone 17 Pro', udid: 'UDID-26' }],
      }),
      { DEVICE_NAME: 'iPhone 17 Pro', IOS_RUNTIME_MAJOR: '26' },
    );
    assert.equal(result.stdout, 'UDID-26');
  });

  it('fails without booting anything when no iPhone simulator exists', () => {
    const result = run(
      devicesJson({ 'iOS-18-6': [{ name: 'iPad Pro 13-inch', udid: 'UDID-IPAD' }] }),
    );
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.calls, /simctl boot /);
  });

  it('prints only the UDID on stdout so callers can capture it', () => {
    const result = run(devicesJson({ 'iOS-18-6': [{ name: IPHONE_12_PRO_MAX, udid: 'UDID-12PM' }] }));
    assert.equal(result.stdout.split('\n').length, 1);
    assert.match(result.stderr, /Xcode: Xcode 16\.4/);
  });
});
