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
});

export interface AppConfig {
  nodeEnv: 'development' | 'test' | 'production';
  logLevel: 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
  server: { host: string; port: number };
  worker: { healthPort: number };
  database: { url: string };
  s3: { endpoint: string; region: string; bucket: string; accessKeyId: string; secretAccessKey: string };
}

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
  };
}
