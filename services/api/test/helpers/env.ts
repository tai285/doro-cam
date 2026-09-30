/**
 * Test configuration. Integration tests use the local stack from `pnpm infra:up` (Postgres + Garage S3);
 * CI starts the same stack. Values match .env.example and can be overridden through the environment.
 */
const DEV_DEFAULTS: Record<string, string> = {
  NODE_ENV: 'test',
  LOG_LEVEL: 'silent',
  DATABASE_URL: 'postgres://doro:doro_dev_password@127.0.0.1:5432/doro',
  S3_ENDPOINT: 'http://127.0.0.1:9000',
  S3_REGION: 'garage',
  S3_BUCKET: 'doro-media',
  S3_ACCESS_KEY_ID: 'GK0123456789abcdef01234567',
  S3_SECRET_ACCESS_KEY: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
};

const OVERRIDABLE = ['DATABASE_URL', 'S3_ENDPOINT', 'S3_REGION', 'S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY'];

export function baseEnv(overrides: Record<string, string | undefined> = {}): NodeJS.ProcessEnv {
  const env: Record<string, string | undefined> = { ...DEV_DEFAULTS };
  for (const key of OVERRIDABLE) {
    const fromProcess = process.env[key];
    if (fromProcess !== undefined && fromProcess !== '') {
      env[key] = fromProcess;
    }
  }
  return { ...env, ...overrides };
}
