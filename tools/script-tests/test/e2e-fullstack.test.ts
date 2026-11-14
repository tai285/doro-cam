import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const script = path.join(repoRoot, 'scripts', 'e2e-fullstack.sh');

describe('scripts/e2e-fullstack.sh', () => {
  it('is valid bash', () => {
    const result = spawnSync('bash', ['-n', script], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  });

  it('stops with exit code 2 and says how to fix it when the S3 storage is not running', () => {
    // port 1 is never listening; nothing else (server, emulator, browser) may be started before this check
    const result = spawnSync('bash', [script], {
      encoding: 'utf8',
      timeout: 30_000,
      env: { ...process.env, FULLSTACK_S3_PORT: '1', FULLSTACK_LOGS: path.join(repoRoot, 'node_modules', '.cache', 'e2e-fullstack-test') },
    });
    assert.equal(result.status, 2);
    assert.match(result.stderr, /pnpm infra:up/);
    assert.doesNotMatch(result.stdout, /== api \+ worker/);
  });
});
