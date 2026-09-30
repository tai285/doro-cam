import { GetObjectCommand, PutObjectCommand, UploadPartCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config/env.ts';
import { createStorage } from '../src/lib/storage.ts';
import { baseEnv } from './helpers/env.ts';

const config = loadConfig(baseEnv());

describe('createStorage', () => {
  it('[ADR-0008] confirms that the configured bucket is reachable', async () => {
    const storage = createStorage(config.s3);
    try {
      await expect(storage.checkBucket()).resolves.toBeUndefined();
      expect(storage.bucket).toBe(config.s3.bucket);
    } finally {
      storage.close();
    }
  });

  it('rejects when the bucket does not exist', async () => {
    const storage = createStorage({ ...config.s3, bucket: 'no-such-bucket-for-tests' });
    try {
      await expect(storage.checkBucket()).rejects.toThrow();
    } finally {
      storage.close();
    }
  });

  it('fails fast (no long retry loop) when the endpoint is unreachable', async () => {
    const storage = createStorage({ ...config.s3, endpoint: 'http://127.0.0.1:1' });
    const started = Date.now();
    try {
      await expect(storage.checkBucket()).rejects.toThrow();
      expect(Date.now() - started).toBeLessThan(5000);
    } finally {
      storage.close();
    }
  });

  describe('presigned URLs', () => {
    it('[SYNC-003] single PUT URLs carry no default checksum parameters', async () => {
      const storage = createStorage(config.s3);
      try {
        const url = new URL(
          await getSignedUrl(storage.client, new PutObjectCommand({ Bucket: storage.bucket, Key: 'k' }), { expiresIn: 60 }),
        );
        expect([...url.searchParams.keys()].filter((name) => name.toLowerCase().includes('checksum'))).toEqual([]);
      } finally {
        storage.close();
      }
    });

    it('[SYNC-003] multipart part URLs carry no default checksum parameters', async () => {
      const storage = createStorage(config.s3);
      try {
        const url = new URL(
          await getSignedUrl(
            storage.client,
            new UploadPartCommand({ Bucket: storage.bucket, Key: 'k', UploadId: 'u', PartNumber: 1 }),
            { expiresIn: 60 },
          ),
        );
        expect([...url.searchParams.keys()].filter((name) => name.toLowerCase().includes('checksum'))).toEqual([]);
      } finally {
        storage.close();
      }
    });

    it('[SYNC-003] a URL signed by the API client really uploads and downloads against storage', async () => {
      const storage = createStorage(config.s3);
      const key = `test/api-${crypto.randomUUID()}.bin`;
      const payload = new Uint8Array(4096).map((_, index) => index % 251);
      try {
        const putUrl = await getSignedUrl(storage.client, new PutObjectCommand({ Bucket: storage.bucket, Key: key }), { expiresIn: 60 });
        const put = await fetch(putUrl, { method: 'PUT', body: payload });
        expect(put.status).toBe(200);

        const getUrl = await getSignedUrl(storage.client, new GetObjectCommand({ Bucket: storage.bucket, Key: key }), { expiresIn: 60 });
        const got = new Uint8Array(await (await fetch(getUrl)).arrayBuffer());
        expect(Buffer.from(got).equals(Buffer.from(payload))).toBe(true);
      } finally {
        storage.close();
      }
    });
  });
});
