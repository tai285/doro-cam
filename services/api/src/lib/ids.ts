import { createHash, randomBytes, randomInt } from 'node:crypto';

const BASE62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/** A 22-character random base62 string (about 131 bits): the non-guessable public handle of a Memory (MEM-008). */
export function newPublicHandle(): string {
  let handle = '';
  for (let i = 0; i < 22; i += 1) {
    handle += BASE62[randomInt(BASE62.length)];
  }
  return handle;
}

/** A URL-safe random token with 256 bits of entropy (used for album invites). */
export function newToken(): string {
  return randomBytes(32).toString('base64url');
}

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

export function stableHash(value: unknown): string {
  return sha256Hex(JSON.stringify(sortKeys(value)));
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortKeys);
  }
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, inner]) => [key, sortKeys(inner)]),
    );
  }
  return value;
}
