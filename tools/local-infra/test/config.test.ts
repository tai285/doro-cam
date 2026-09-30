import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ConfigError, loadConfig } from '../src/config.ts';

describe('loadConfig', () => {
  it('[NFR-013] returns the dev defaults when no environment is set', () => {
    const config = loadConfig({});
    assert.equal(config.databaseUrl, 'postgres://doro:doro_dev_password@127.0.0.1:5432/doro');
    assert.deepEqual(config.s3, {
      endpoint: 'http://127.0.0.1:9000',
      region: 'garage',
      bucket: 'doro-media',
      accessKeyId: 'GK0123456789abcdef01234567',
      secretAccessKey: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    });
    assert.deepEqual(config.corsOrigins, ['http://localhost:5173']);
  });

  it('applies overrides, trimming whitespace and ignoring empty values', () => {
    const config = loadConfig({
      DATABASE_URL: '  postgresql://u:p@db.internal:6543/app ',
      S3_ENDPOINT: 'https://s3.example.com',
      S3_REGION: '',
      S3_BUCKET: 'my-bucket-1',
      S3_CORS_ORIGINS: 'https://a.example.com, http://localhost:3000 ,',
    });
    assert.equal(config.databaseUrl, 'postgresql://u:p@db.internal:6543/app');
    assert.equal(config.s3.endpoint, 'https://s3.example.com');
    assert.equal(config.s3.region, 'garage');
    assert.equal(config.s3.bucket, 'my-bucket-1');
    assert.deepEqual(config.corsOrigins, ['https://a.example.com', 'http://localhost:3000']);
  });

  const invalid: ReadonlyArray<[string, NodeJS.ProcessEnv, RegExp]> = [
    ['a non-URL database URL', { DATABASE_URL: 'not a url' }, /DATABASE_URL is not a valid URL/],
    ['a non-postgres database URL', { DATABASE_URL: 'mysql://x/y' }, /DATABASE_URL must use/],
    ['a non-URL S3 endpoint', { S3_ENDPOINT: '::' }, /S3_ENDPOINT is not a valid URL/],
    ['a non-http S3 endpoint', { S3_ENDPOINT: 'ftp://x' }, /S3_ENDPOINT must use/],
    ['an uppercase bucket', { S3_BUCKET: 'Bucket' }, /S3_BUCKET/],
    ['a too-short bucket', { S3_BUCKET: 'ab' }, /S3_BUCKET/],
    ['a bucket ending in a hyphen', { S3_BUCKET: 'abc-' }, /S3_BUCKET/],
    ['a malformed access key id', { S3_ACCESS_KEY_ID: 'AKIA123' }, /S3_ACCESS_KEY_ID/],
    ['a malformed secret', { S3_SECRET_ACCESS_KEY: 'short' }, /S3_SECRET_ACCESS_KEY/],
    ['an origin with a path', { S3_CORS_ORIGINS: 'http://localhost:5173/app' }, /bare origin/],
    ['an origin with a trailing slash', { S3_CORS_ORIGINS: 'http://localhost:5173/' }, /bare origin/],
    ['a non-http origin', { S3_CORS_ORIGINS: 'ftp://x.example.com' }, /S3_CORS_ORIGINS entry must use/],
    ['only separators in origins', { S3_CORS_ORIGINS: ' , ,' }, /at least one origin/],
  ];
  for (const [name, env, message] of invalid) {
    it(`rejects ${name}`, () => {
      assert.throws(() => loadConfig(env), (error: unknown) => {
        assert.ok(error instanceof ConfigError);
        assert.match(error.message, message);
        return true;
      });
    });
  }
});
