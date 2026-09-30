import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const script = path.join(repoRoot, 'scripts', 'check-synthetic-camera.sh');
const MARKER = 'dorocam.synthetic-camera.v1';
const tempDirs: string[] = [];

after(() => {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function toPosix(p: string): string {
  return p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, drive: string) => `/${drive.toLowerCase()}`);
}

function workDir(): string {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'synthetic-check-'));
  tempDirs.push(dir);
  return dir;
}

/** Builds a zip (APK-like) with the given entries, deflate-compressed, using Python's zipfile. */
function makeZip(file: string, entries: Record<string, string>): void {
  const result = spawnSync(
    'python3',
    [
      '-c',
      'import json,sys,zipfile\n' +
        'entries=json.loads(sys.argv[2])\n' +
        'with zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED) as z:\n' +
        '    for name,text in entries.items(): z.writestr(name,text)\n',
      file,
      JSON.stringify(entries),
    ],
    { encoding: 'utf8' },
  );
  assert.equal(result.status, 0, result.stderr);
}

function run(...args: string[]) {
  const result = spawnSync('bash', [toPosix(script), ...args.map((a) => (path.isAbsolute(a) ? toPosix(a) : a))], {
    encoding: 'utf8',
  });
  return { status: result.status, stderr: result.stderr, stdout: result.stdout };
}

describe('scripts/check-synthetic-camera.sh', () => {
  it('[NFR-016] debug APK containing the marker satisfies --expect-present', () => {
    const apk = path.join(workDir(), 'app-debug.apk');
    makeZip(apk, { 'classes.dex': `dex\n035\0 ${MARKER} more code`, 'AndroidManifest.xml': '<manifest/>' });
    const result = run('--expect-present', apk);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /marker is present/);
  });

  it('[NFR-016] release APK without the marker satisfies --expect-absent', () => {
    const apk = path.join(workDir(), 'app-release.apk');
    makeZip(apk, { 'classes.dex': 'dex\n035\0 ordinary code only', 'res/raw/a.txt': 'hello' });
    const result = run('--expect-absent', apk);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /no synthetic camera marker/);
  });

  it('[NFR-016] fails and names the leaking file when a release APK contains the marker', () => {
    const apk = path.join(workDir(), 'app-release.apk');
    makeZip(apk, { 'classes.dex': 'fine', 'classes2.dex': `oops ${MARKER} oops` });
    const result = run('--expect-absent', apk);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /leaked into/);
    assert.match(result.stderr, /- classes2\.dex/);
    assert.doesNotMatch(result.stderr, /- classes\.dex/);
  });

  it('[NFR-016] fails --expect-present when a debug artifact lacks the marker (no vacuous pass)', () => {
    const apk = path.join(workDir(), 'app-debug.apk');
    makeZip(apk, { 'classes.dex': 'nothing special' });
    const result = run('--expect-present', apk);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /was NOT found/);
  });

  it('scans every file of a directory bundle such as an iOS .app', () => {
    const app = path.join(workDir(), 'Runner.app');
    mkdirSync(path.join(app, 'Frameworks'), { recursive: true });
    writeFileSync(path.join(app, 'Runner'), 'binary without the marker');
    writeFileSync(path.join(app, 'Frameworks', 'Runner.debug.dylib'), Buffer.from(`\0\0${MARKER}\0`));
    assert.equal(run('--expect-present', app).status, 0);
    const leak = run('--expect-absent', app);
    assert.equal(leak.status, 1);
    assert.match(leak.stderr, /Frameworks[\\/]Runner\.debug\.dylib/);
  });

  it('scans a single file', () => {
    const file = path.join(workDir(), 'Runner');
    writeFileSync(file, Buffer.from(`xx${MARKER}xx`));
    assert.equal(run('--expect-present', file).status, 0);
    assert.equal(run('--expect-absent', file).status, 1);
  });

  it('honours a custom marker', () => {
    const file = path.join(workDir(), 'blob.bin');
    writeFileSync(file, 'hello custom-marker-123 world');
    assert.equal(run('--expect-present', file, 'custom-marker-123').status, 0);
    assert.equal(run('--expect-absent', file, 'custom-marker-123').status, 1);
    assert.equal(run('--expect-absent', file).status, 0, 'default marker is not in the file');
  });

  it('does not match a marker that is only partially present', () => {
    const file = path.join(workDir(), 'partial.bin');
    writeFileSync(file, 'dorocam.synthetic-camera.v');
    assert.equal(run('--expect-absent', file).status, 0);
  });

  it('exits 2 for a missing artifact', () => {
    const result = run('--expect-absent', path.join(workDir(), 'nope.apk'));
    assert.equal(result.status, 2);
    assert.match(result.stderr, /artifact not found/);
  });

  it('exits 2 and prints usage for bad arguments', () => {
    assert.equal(run().status, 2);
    assert.equal(run('--expect-present').status, 2);
    const bad = run('--whatever', 'x');
    assert.equal(bad.status, 2);
    assert.match(bad.stderr, /usage:/);
  });
});
