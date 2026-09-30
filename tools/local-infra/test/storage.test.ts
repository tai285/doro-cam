import assert from 'node:assert/strict';
import path from 'node:path';
import { describe, it } from 'node:test';
import { PutObjectCommand, UploadPartCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { COMPOSE_FILE, composeArgs } from '../src/compose.ts';
import {
  ABORT_INCOMPLETE_UPLOAD_DAYS,
  buildCorsConfiguration,
  buildLifecycleConfiguration,
  createS3Client,
} from '../src/storage.ts';

describe('buildCorsConfiguration', () => {
  it('[SYNC-003] allows direct browser PUT/GET/HEAD and exposes ETag for multipart completion', () => {
    const config = buildCorsConfiguration(['http://localhost:5173', 'https://app.example.com']);
    assert.deepEqual(config.CORSRules, [
      {
        AllowedOrigins: ['http://localhost:5173', 'https://app.example.com'],
        AllowedMethods: ['GET', 'PUT', 'HEAD'],
        AllowedHeaders: ['*'],
        ExposeHeaders: ['ETag'],
        MaxAgeSeconds: 3600,
      },
    ]);
  });

  it('does not alias the caller\'s array', () => {
    const origins = ['http://localhost:5173'];
    const config = buildCorsConfiguration(origins);
    origins.push('http://evil.example.com');
    assert.deepEqual(config.CORSRules?.[0]?.AllowedOrigins, ['http://localhost:5173']);
  });
});

describe('buildLifecycleConfiguration', () => {
  it('[SYNC-003] aborts incomplete multipart uploads after the given days', () => {
    assert.deepEqual(buildLifecycleConfiguration(7), {
      Rules: [
        {
          ID: 'abort-incomplete-multipart-uploads',
          Status: 'Enabled',
          Filter: { Prefix: '' },
          AbortIncompleteMultipartUpload: { DaysAfterInitiation: 7 },
        },
      ],
    });
    assert.equal(ABORT_INCOMPLETE_UPLOAD_DAYS, 7);
  });

  for (const bad of [0, -1, 1.5, Number.NaN]) {
    it(`rejects ${bad} days`, () => {
      assert.throws(() => buildLifecycleConfiguration(bad), RangeError);
    });
  }
});

describe('createS3Client', () => {
  it('uses path-style addressing and the configured endpoint and region', async () => {
    const client = createS3Client({
      endpoint: 'http://127.0.0.1:9000',
      region: 'garage',
      bucket: 'doro-media',
      accessKeyId: 'GK0123456789abcdef01234567',
      secretAccessKey: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    });
    assert.equal(await client.config.region(), 'garage');
    assert.equal(await client.config.forcePathStyle, true);
    const endpoint = await client.config.endpoint?.();
    assert.equal(endpoint?.hostname, '127.0.0.1');
    assert.equal(endpoint?.port, 9000);
    client.destroy();
  });
});

describe('presigned URLs', () => {
  const client = createS3Client({
    endpoint: 'http://127.0.0.1:9000',
    region: 'garage',
    bucket: 'doro-media',
    accessKeyId: 'GK0123456789abcdef01234567',
    secretAccessKey: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  });

  it('[SYNC-003] single PUT URLs carry no default checksum parameters', async () => {
    const url = new URL(
      await getSignedUrl(client, new PutObjectCommand({ Bucket: 'doro-media', Key: 'k' }), { expiresIn: 60 }),
    );
    assert.equal(url.searchParams.get('X-Amz-Expires'), '60');
    for (const name of url.searchParams.keys()) {
      assert.ok(!name.toLowerCase().includes('checksum'), `unexpected checksum parameter ${name}`);
    }
  });

  it('[SYNC-003] multipart part URLs carry no default checksum parameters', async () => {
    const url = new URL(
      await getSignedUrl(
        client,
        new UploadPartCommand({ Bucket: 'doro-media', Key: 'k', UploadId: 'u', PartNumber: 2 }),
        { expiresIn: 60 },
      ),
    );
    assert.equal(url.searchParams.get('partNumber'), '2');
    assert.equal(url.searchParams.get('uploadId'), 'u');
    for (const name of url.searchParams.keys()) {
      assert.ok(!name.toLowerCase().includes('checksum'), `unexpected checksum parameter ${name}`);
    }
  });
});

describe('compose helpers', () => {
  it('resolves the compose file relative to the repository regardless of cwd', () => {
    assert.equal(path.basename(COMPOSE_FILE), 'docker-compose.yml');
    assert.equal(path.basename(path.dirname(COMPOSE_FILE)), 'infrastructure');
  });

  it('prefixes compose arguments with the file flag', () => {
    assert.deepEqual(composeArgs('up', '-d'), ['compose', '-f', COMPOSE_FILE, 'up', '-d']);
    assert.deepEqual(composeArgs(), ['compose', '-f', COMPOSE_FILE]);
  });
});
