import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { loadConfig } from '../src/config.ts';
import { createS3Client } from '../src/storage.ts';

export const config = loadConfig();
export const bucket = config.s3.bucket;

export function newClient() {
  return createS3Client(config.s3);
}

export function sha256Hex(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

export function randomPayload(bytes: number): Buffer {
  return randomBytes(bytes);
}

/** Unique key under a test-only prefix so runs never collide. */
export function testKey(name: string): string {
  return `test/${randomUUID()}/${name}`;
}

/** fetch() with a Buffer body, returning the response after asserting nothing about it. */
export async function put(url: string, body: Buffer, headers: Record<string, string> = {}): Promise<Response> {
  return fetch(url, { method: 'PUT', body: new Uint8Array(body), headers });
}

export async function getBytes(url: string): Promise<{ response: Response; bytes: Buffer }> {
  const response = await fetch(url);
  return { response, bytes: Buffer.from(await response.arrayBuffer()) };
}

export const MIB = 1024 * 1024;
