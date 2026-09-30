import type { S3Config } from './config.ts';

/** Runs the Garage CLI inside the container and returns stdout. Rejects on a non-zero exit. */
export type GarageRunner = (args: readonly string[]) => Promise<string>;

export class GarageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GarageError';
  }
}

const NODE_LINE_RE = /^([0-9a-f]{16})\s+(.*)$/;

interface NodeStatus {
  id: string;
  hasRole: boolean;
}

/** Parses the single node listed by `garage status`. */
export function parseNodeStatus(statusOutput: string): NodeStatus {
  const nodes = statusOutput
    .split('\n')
    .map((line) => NODE_LINE_RE.exec(line.trim()))
    .filter((match): match is RegExpExecArray => match !== null);
  const first = nodes[0];
  if (first?.[1] === undefined) {
    throw new GarageError('could not find a node ID in `garage status` output');
  }
  if (nodes.length > 1) {
    throw new GarageError(`expected a single-node cluster, found ${nodes.length} nodes`);
  }
  return { id: first[1], hasRole: !(first[2] ?? '').includes('NO ROLE ASSIGNED') };
}

export interface BootstrapResult {
  layoutApplied: boolean;
  bucketCreated: boolean;
  keyImported: boolean;
}

async function succeeds(run: GarageRunner, args: readonly string[]): Promise<boolean> {
  try {
    await run(args);
    return true;
  } catch {
    return false;
  }
}

/**
 * Brings a fresh single-node Garage to a usable state, or leaves an already-provisioned one
 * untouched: cluster layout, bucket, imported dev key, and key permissions. Safe to run repeatedly.
 */
export async function bootstrapGarage(run: GarageRunner, s3: S3Config): Promise<BootstrapResult> {
  const node = parseNodeStatus(await run(['status']));

  let layoutApplied = false;
  if (!node.hasRole) {
    await run(['layout', 'assign', '-z', 'dc1', '-c', '1G', node.id]);
    await run(['layout', 'apply', '--version', '1']);
    layoutApplied = true;
  }

  let bucketCreated = false;
  if (!(await succeeds(run, ['bucket', 'info', s3.bucket]))) {
    await run(['bucket', 'create', s3.bucket]);
    bucketCreated = true;
  }

  let keyImported = false;
  if (!(await succeeds(run, ['key', 'info', s3.accessKeyId]))) {
    await run(['key', 'import', '--yes', '-n', 'doro-dev', s3.accessKeyId, s3.secretAccessKey]);
    keyImported = true;
  }

  await run(['bucket', 'allow', '--read', '--write', '--owner', s3.bucket, '--key', s3.accessKeyId]);
  return { layoutApplied, bucketCreated, keyImported };
}
