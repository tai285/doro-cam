/**
 * Configuration for the local development stack. Defaults match infrastructure/docker-compose.yml
 * and the public dev-only credentials in .env.example. Nothing here is used in production.
 */

export interface S3Config {
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
}

export interface InfraConfig {
  databaseUrl: string;
  s3: S3Config;
  corsOrigins: string[];
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

const DEFAULTS = {
  DATABASE_URL: 'postgres://doro:doro_dev_password@127.0.0.1:5432/doro',
  S3_ENDPOINT: 'http://127.0.0.1:9000',
  S3_REGION: 'garage',
  S3_BUCKET: 'doro-media',
  S3_ACCESS_KEY_ID: 'GK0123456789abcdef01234567',
  S3_SECRET_ACCESS_KEY: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  S3_CORS_ORIGINS: 'http://localhost:5173',
} as const;

// Garage requires key IDs of the form GK + 24 hex characters and 64 hex character secrets.
const ACCESS_KEY_ID_RE = /^GK[0-9a-f]{24}$/;
const SECRET_KEY_RE = /^[0-9a-f]{64}$/;
const BUCKET_RE = /^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/;

function pick(env: NodeJS.ProcessEnv, key: keyof typeof DEFAULTS): string {
  const value = env[key];
  return value === undefined || value.trim() === '' ? DEFAULTS[key] : value.trim();
}

function parseUrl(name: string, value: string, protocols: readonly string[]): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new ConfigError(`${name} is not a valid URL: "${value}"`);
  }
  if (!protocols.includes(url.protocol)) {
    throw new ConfigError(`${name} must use one of ${protocols.join(', ')} (got "${url.protocol}")`);
  }
  return url;
}

/** Reads and validates configuration from environment variables, failing fast on invalid values. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): InfraConfig {
  const databaseUrl = pick(env, 'DATABASE_URL');
  parseUrl('DATABASE_URL', databaseUrl, ['postgres:', 'postgresql:']);

  const endpoint = pick(env, 'S3_ENDPOINT');
  parseUrl('S3_ENDPOINT', endpoint, ['http:', 'https:']);

  const bucket = pick(env, 'S3_BUCKET');
  if (!BUCKET_RE.test(bucket)) {
    throw new ConfigError(`S3_BUCKET "${bucket}" must be 3-63 chars of lowercase letters, digits, or hyphens`);
  }

  const accessKeyId = pick(env, 'S3_ACCESS_KEY_ID');
  if (!ACCESS_KEY_ID_RE.test(accessKeyId)) {
    throw new ConfigError('S3_ACCESS_KEY_ID must match GK followed by 24 lowercase hex characters');
  }
  const secretAccessKey = pick(env, 'S3_SECRET_ACCESS_KEY');
  if (!SECRET_KEY_RE.test(secretAccessKey)) {
    throw new ConfigError('S3_SECRET_ACCESS_KEY must be 64 lowercase hex characters');
  }

  const corsOrigins = pick(env, 'S3_CORS_ORIGINS')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin !== '');
  if (corsOrigins.length === 0) {
    throw new ConfigError('S3_CORS_ORIGINS must list at least one origin');
  }
  for (const origin of corsOrigins) {
    const url = parseUrl('S3_CORS_ORIGINS entry', origin, ['http:', 'https:']);
    if (url.origin !== origin) {
      throw new ConfigError(`S3_CORS_ORIGINS entry "${origin}" must be a bare origin such as "${url.origin}"`);
    }
  }

  return {
    databaseUrl,
    s3: { endpoint, region: pick(env, 'S3_REGION'), bucket, accessKeyId, secretAccessKey },
    corsOrigins,
  };
}
