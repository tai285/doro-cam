import { describe, expect, it } from 'vitest';
import { ConfigError, loadConfig } from '../src/config/env.ts';

const REQUIRED = {
  DATABASE_URL: 'postgres://user:s3cret-pass@db.internal:5432/app',
  S3_ENDPOINT: 'https://s3.example.com',
  S3_BUCKET: 'my-bucket',
  S3_ACCESS_KEY_ID: 'AKIDEXAMPLE-KEY-ID',
  S3_SECRET_ACCESS_KEY: 'super-secret-access-key',
};

function messageOf(env: NodeJS.ProcessEnv): string {
  try {
    loadConfig(env);
  } catch (error) {
    expect(error).toBeInstanceOf(ConfigError);
    return (error as Error).message;
  }
  throw new Error('expected loadConfig to throw');
}

describe('loadConfig', () => {
  it('[NFR-013] applies defaults for optional values', () => {
    const config = loadConfig(REQUIRED);
    expect(config).toEqual({
      nodeEnv: 'development',
      logLevel: 'info',
      server: { host: '0.0.0.0', port: 3000 },
      worker: { healthPort: 3001 },
      database: { url: REQUIRED.DATABASE_URL },
      s3: {
        endpoint: 'https://s3.example.com',
        region: 'garage',
        bucket: 'my-bucket',
        accessKeyId: 'AKIDEXAMPLE-KEY-ID',
        secretAccessKey: 'super-secret-access-key',
      },
    });
  });

  it('reads overrides and coerces numeric strings', () => {
    const config = loadConfig({
      ...REQUIRED,
      NODE_ENV: 'production',
      LOG_LEVEL: 'warn',
      HOST: '127.0.0.1',
      PORT: '8080',
      WORKER_HEALTH_PORT: '0',
      S3_REGION: 'auto',
    });
    expect(config.nodeEnv).toBe('production');
    expect(config.logLevel).toBe('warn');
    expect(config.server).toEqual({ host: '127.0.0.1', port: 8080 });
    expect(config.worker.healthPort).toBe(0);
    expect(config.s3.region).toBe('auto');
  });

  it('trims whitespace around values', () => {
    const config = loadConfig({ ...REQUIRED, S3_BUCKET: '  my-bucket  ', HOST: ' 0.0.0.0 ' });
    expect(config.s3.bucket).toBe('my-bucket');
    expect(config.server.host).toBe('0.0.0.0');
  });

  it('treats empty values as unset, so PORT= does not become port 0', () => {
    const config = loadConfig({ ...REQUIRED, PORT: '', HOST: '   ', LOG_LEVEL: '' });
    expect(config.server).toEqual({ host: '0.0.0.0', port: 3000 });
    expect(config.logLevel).toBe('info');
  });

  it('names every missing required variable at once', () => {
    const message = messageOf({});
    for (const name of Object.keys(REQUIRED)) {
      expect(message).toContain(`${name}: is required`);
    }
  });

  it('treats an empty required variable as missing', () => {
    expect(messageOf({ ...REQUIRED, DATABASE_URL: '' })).toContain('DATABASE_URL: is required');
  });

  const invalid: ReadonlyArray<[string, Record<string, string>, RegExp]> = [
    ['a non-URL database URL', { DATABASE_URL: 'not a url' }, /DATABASE_URL: must be a URL using postgres:/],
    ['a non-postgres database URL', { DATABASE_URL: 'mysql://x/y' }, /DATABASE_URL: must be a URL/],
    ['a non-http S3 endpoint', { S3_ENDPOINT: 'ftp://x.example.com' }, /S3_ENDPOINT: must be a URL using http:/],
    ['an uppercase bucket', { S3_BUCKET: 'Bucket' }, /S3_BUCKET: must be 3-63/],
    ['a too-short bucket', { S3_BUCKET: 'ab' }, /S3_BUCKET/],
    ['a port above 65535', { PORT: '70000' }, /PORT/],
    ['a negative port', { PORT: '-1' }, /PORT/],
    ['a fractional port', { PORT: '80.5' }, /PORT/],
    ['a non-numeric port', { PORT: 'http' }, /PORT/],
    ['an unknown log level', { LOG_LEVEL: 'verbose' }, /LOG_LEVEL/],
    ['an unknown NODE_ENV', { NODE_ENV: 'staging' }, /NODE_ENV/],
  ];
  for (const [name, overrides, expected] of invalid) {
    it(`rejects ${name}`, () => {
      expect(messageOf({ ...REQUIRED, ...overrides })).toMatch(expected);
    });
  }

  it('[NFR-011] never echoes secret values or credentials embedded in URLs', () => {
    const message = messageOf({
      ...REQUIRED,
      DATABASE_URL: 'mysql://user:s3cret-pass@db.internal/app',
      S3_BUCKET: 'BAD BUCKET',
      PORT: 'nope',
    });
    expect(message).not.toContain('s3cret-pass');
    expect(message).not.toContain('super-secret-access-key');
    expect(message).not.toContain('nope');
  });

  it('reads process.env when called without arguments', () => {
    const before = { ...process.env };
    Object.assign(process.env, REQUIRED);
    try {
      expect(loadConfig().s3.bucket).toBe('my-bucket');
    } finally {
      for (const key of Object.keys(REQUIRED)) {
        if (before[key] === undefined) {
          delete process.env[key];
        } else {
          process.env[key] = before[key];
        }
      }
    }
  });
});
