import { execFile } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import type { GarageRunner } from './garage.ts';

const execFileAsync = promisify(execFile);

const here = path.dirname(fileURLToPath(import.meta.url));

/** Absolute path of infrastructure/docker-compose.yml, independent of the working directory. */
export const COMPOSE_FILE = path.resolve(here, '..', '..', '..', 'infrastructure', 'docker-compose.yml');

export function composeArgs(...args: string[]): string[] {
  return ['compose', '-f', COMPOSE_FILE, ...args];
}

export async function compose(...args: string[]): Promise<string> {
  const { stdout } = await execFileAsync('docker', composeArgs(...args), { maxBuffer: 10 * 1024 * 1024 });
  return stdout;
}

/** Runs the Garage CLI in the compose container. execFile avoids any shell or path rewriting. */
export const runGarage: GarageRunner = async (args) => {
  try {
    return await compose('exec', '-T', 'garage', '/garage', ...args);
  } catch (error) {
    const stderr = (error as { stderr?: string }).stderr?.trim();
    throw new Error(`garage ${args.join(' ')} failed${stderr ? `: ${stderr}` : ''}`, { cause: error });
  }
};
