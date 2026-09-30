import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { S3Config } from '../src/config.ts';
import { bootstrapGarage, GarageError, type GarageRunner, parseNodeStatus } from '../src/garage.ts';

const s3: S3Config = {
  endpoint: 'http://127.0.0.1:9000',
  region: 'garage',
  bucket: 'doro-media',
  accessKeyId: 'GK0123456789abcdef01234567',
  secretAccessKey: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
};

// Captured from `garage status` (v2.1.0) on a fresh and on a provisioned node.
const FRESH_STATUS = [
  '==== HEALTHY NODES ====',
  'ID                Hostname      Address         Tags  Zone  Capacity          DataAvail  Version',
  '714c4795cd743c04  e58641d0725b  127.0.0.1:3901              NO ROLE ASSIGNED             v2.1.0',
  '',
].join('\n');
const PROVISIONED_STATUS = [
  '==== HEALTHY NODES ====',
  'ID                Hostname      Address         Tags  Zone  Capacity   DataAvail    Version',
  '714c4795cd743c04  e58641d0725b  127.0.0.1:3901  []    dc1   1000.0 MB  40.0 GB (50%)  v2.1.0',
  '',
].join('\n');

/** A scripted fake of the Garage CLI. `failing` lists command prefixes that exit non-zero. */
function fakeRunner(status: string, failing: readonly string[] = []) {
  const calls: string[] = [];
  const run: GarageRunner = async (args) => {
    const command = args.join(' ');
    calls.push(command);
    if (failing.some((prefix) => command.startsWith(prefix))) {
      throw new Error(`exit 1: ${command}`);
    }
    return args[0] === 'status' ? status : '';
  };
  return { run, calls };
}

describe('parseNodeStatus', () => {
  it('reads the node ID and reports a missing role', () => {
    assert.deepEqual(parseNodeStatus(FRESH_STATUS), { id: '714c4795cd743c04', hasRole: false });
  });

  it('reports an assigned role', () => {
    assert.deepEqual(parseNodeStatus(PROVISIONED_STATUS), { id: '714c4795cd743c04', hasRole: true });
  });

  it('ignores log lines and headings', () => {
    const noisy = `2026-09-30 INFO something\n${FRESH_STATUS}`;
    assert.equal(parseNodeStatus(noisy).id, '714c4795cd743c04');
  });

  it('throws when no node is listed', () => {
    assert.throws(() => parseNodeStatus('==== HEALTHY NODES ====\n'), GarageError);
    assert.throws(() => parseNodeStatus(''), /could not find a node ID/);
  });

  it('throws for a multi-node cluster', () => {
    const two = `${FRESH_STATUS}aaaaaaaaaaaaaaaa  other  10.0.0.2:3901  NO ROLE ASSIGNED\n`;
    assert.throws(() => parseNodeStatus(two), /single-node cluster, found 2/);
  });
});

describe('bootstrapGarage', () => {
  it('[NFR-013] provisions a fresh cluster in order', async () => {
    const { run, calls } = fakeRunner(FRESH_STATUS, ['bucket info', 'key info']);
    const result = await bootstrapGarage(run, s3);
    assert.deepEqual(result, { layoutApplied: true, bucketCreated: true, keyImported: true });
    assert.deepEqual(calls, [
      'status',
      'layout assign -z dc1 -c 1G 714c4795cd743c04',
      'layout apply --version 1',
      'bucket info doro-media',
      'bucket create doro-media',
      `key info ${s3.accessKeyId}`,
      `key import --yes -n doro-dev ${s3.accessKeyId} ${s3.secretAccessKey}`,
      `bucket allow --read --write --owner doro-media --key ${s3.accessKeyId}`,
    ]);
  });

  it('[NFR-013] leaves a provisioned cluster untouched (idempotent) but re-asserts permissions', async () => {
    const { run, calls } = fakeRunner(PROVISIONED_STATUS);
    const result = await bootstrapGarage(run, s3);
    assert.deepEqual(result, { layoutApplied: false, bucketCreated: false, keyImported: false });
    assert.deepEqual(calls, [
      'status',
      'bucket info doro-media',
      `key info ${s3.accessKeyId}`,
      `bucket allow --read --write --owner doro-media --key ${s3.accessKeyId}`,
    ]);
  });

  it('creates only what is missing on a partially provisioned cluster', async () => {
    const { run, calls } = fakeRunner(PROVISIONED_STATUS, ['key info']);
    const result = await bootstrapGarage(run, s3);
    assert.deepEqual(result, { layoutApplied: false, bucketCreated: false, keyImported: true });
    assert.ok(calls.some((call) => call.startsWith('key import')));
    assert.ok(!calls.some((call) => call.startsWith('bucket create')));
  });

  it('stops at the first real failure and reports it', async () => {
    const { run, calls } = fakeRunner(FRESH_STATUS, ['layout assign']);
    await assert.rejects(bootstrapGarage(run, s3), /layout assign/);
    assert.deepEqual(calls, ['status', 'layout assign -z dc1 -c 1G 714c4795cd743c04']);
  });

  it('fails immediately when Garage is not reachable', async () => {
    const { run, calls } = fakeRunner(FRESH_STATUS, ['status']);
    await assert.rejects(bootstrapGarage(run, s3), /exit 1: status/);
    assert.deepEqual(calls, ['status']);
  });

  it('fails when permissions cannot be granted', async () => {
    const { run } = fakeRunner(PROVISIONED_STATUS, ['bucket allow']);
    await assert.rejects(bootstrapGarage(run, s3), /bucket allow/);
  });
});
