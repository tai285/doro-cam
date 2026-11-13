import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config/env.ts';
import { presignGet, presignPut } from '../src/lib/presign.ts';
import { createStorage } from '../src/lib/storage.ts';
import { baseEnv } from './helpers/env.ts';

describe('public storage endpoint', () => {
  it('[NFR-013] defaults to the internal endpoint and can be overridden for clients', () => {
    expect(loadConfig(baseEnv()).s3.publicEndpoint).toBe(loadConfig(baseEnv()).s3.endpoint);
    const config = loadConfig(baseEnv({ S3_PUBLIC_ENDPOINT: 'https://media.example.com' }));
    expect(config.s3.endpoint).toBe('http://127.0.0.1:9000');
    expect(config.s3.publicEndpoint).toBe('https://media.example.com');
    expect(() => loadConfig(baseEnv({ S3_PUBLIC_ENDPOINT: 'not a url' }))).toThrow(/S3_PUBLIC_ENDPOINT/);
  });

  it('[NFR-013] presigned URLs point at the public address while server-side calls keep the internal one', async () => {
    const config = loadConfig(baseEnv({ S3_PUBLIC_ENDPOINT: 'https://media.example.com' }));
    const storage = createStorage(config.s3);
    try {
      expect(storage.presignClient).not.toBe(storage.client);
      expect(new URL((await presignPut(storage, 'k/one', 'image/jpeg')).url).origin).toBe('https://media.example.com');
      expect(new URL((await presignGet(storage, 'k/one')).url).origin).toBe('https://media.example.com');
      await expect(storage.checkBucket()).resolves.toBeUndefined(); // the API still reaches storage internally
    } finally {
      storage.close();
    }
  });

  it('reuses one client when both addresses are the same', () => {
    const storage = createStorage(loadConfig(baseEnv()).s3);
    expect(storage.presignClient).toBe(storage.client);
    storage.close();
  });
});
