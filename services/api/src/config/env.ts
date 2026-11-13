import { z } from 'zod';

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

const url = (protocols: readonly string[]) =>
  z
    .string()
    .trim()
    .refine(
      (value) => {
        try {
          return protocols.includes(new URL(value).protocol);
        } catch {
          return false;
        }
      },
      { message: `must be a URL using ${protocols.join(' or ')}` },
    );

const port = z.coerce.number().int().min(0).max(65535);

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().trim().min(1).default('0.0.0.0'),
  PORT: port.default(3000),
  WORKER_HEALTH_PORT: port.default(3001),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  DATABASE_URL: url(['postgres:', 'postgresql:']),
  S3_ENDPOINT: url(['http:', 'https:']),
  S3_REGION: z.string().trim().min(1).default('garage'),
  S3_BUCKET: z
    .string()
    .trim()
    .regex(/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/, 'must be 3-63 lowercase letters, digits or hyphens'),
  S3_ACCESS_KEY_ID: z.string().trim().min(1),
  S3_SECRET_ACCESS_KEY: z.string().trim().min(1),
  AUTH_SECRET: z.string().trim().min(32, 'must be at least 32 characters').optional(),
  PUBLIC_BASE_URL: url(['http:', 'https:']).default('http://localhost:3000'),
  WEB_ORIGINS: z.string().trim().default('http://localhost:5173'),
  AUTH_RATE_LIMIT_PER_MINUTE: z.coerce.number().int().positive().default(30),
  STORAGE_QUOTA_BYTES: z.coerce.number().int().positive().default(10 * 1024 ** 3),
});

export interface AppConfig {
  nodeEnv: 'development' | 'test' | 'production';
  logLevel: 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
  server: { host: string; port: number };
  worker: { healthPort: number };
  database: { url: string };
  s3: { endpoint: string; region: string; bucket: string; accessKeyId: string; secretAccessKey: string };
  auth: { secret: string; baseUrl: string; webOrigins: string[] };
  limits: { storageQuotaBytes: number; authPerMinute: number };
}

/** Development and test fall back to a fixed secret so the stack starts without setup; production must provide one. */
const DEV_AUTH_SECRET = 'dev-only-insecure-auth-secret-do-not-use-in-production';

/**
 * Parses environment variables and fails fast with every problem listed at once.
 * Error messages name the variable and the rule but never echo the value (secrets, credentials in URLs).
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  // An empty value counts as unset: Number('') is 0, so PORT= would otherwise silently mean "any port".
  const present = Object.fromEntries(
    Object.entries(env).filter(([, value]) => value !== undefined && value.trim() !== ''),
  );
  const result = envSchema.safeParse(present);
  if (!result.success) {
    const problems = result.error.issues.map((issue) => {
      const name = issue.path.join('.');
      const missing = issue.code === 'invalid_type' && present[name] === undefined;
      return `  - ${name}: ${missing ? 'is required' : issue.message}`;
    });
    throw new ConfigError(`Invalid configuration:\n${problems.join('\n')}`);
  }
  const e = result.data;
  if (e.NODE_ENV === 'production' && e.AUTH_SECRET === undefined) {
    throw new ConfigError('Invalid configuration:\n  - AUTH_SECRET: is required in production');
  }
  return {
    nodeEnv: e.NODE_ENV,
    logLevel: e.LOG_LEVEL,
    server: { host: e.HOST, port: e.PORT },
    worker: { healthPort: e.WORKER_HEALTH_PORT },
    database: { url: e.DATABASE_URL },
    s3: {
      endpoint: e.S3_ENDPOINT,
      region: e.S3_REGION,
      bucket: e.S3_BUCKET,
      accessKeyId: e.S3_ACCESS_KEY_ID,
      secretAccessKey: e.S3_SECRET_ACCESS_KEY,
    },
    auth: {
      secret: e.AUTH_SECRET ?? DEV_AUTH_SECRET,
      baseUrl: e.PUBLIC_BASE_URL.replace(/\/+$/, ''),
      webOrigins: e.WEB_ORIGINS.split(',').map((origin) => origin.trim()).filter((origin) => origin !== ''),
    },
    limits: { storageQuotaBytes: e.STORAGE_QUOTA_BYTES, authPerMinute: e.AUTH_RATE_LIMIT_PER_MINUTE },
  };
}
