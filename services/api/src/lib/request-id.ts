import { randomUUID } from 'node:crypto';

/** Accepts a caller-supplied ID only if it is short and made of safe characters (it is echoed in logs and headers). */
const SAFE_REQUEST_ID = /^[A-Za-z0-9._-]{8,64}$/;

export const REQUEST_ID_HEADER = 'x-request-id';

export function resolveRequestId(incoming: string | string[] | undefined): string {
  const candidate = Array.isArray(incoming) ? incoming[0] : incoming;
  if (candidate !== undefined && SAFE_REQUEST_ID.test(candidate)) {
    return candidate;
  }
  return randomUUID();
}
