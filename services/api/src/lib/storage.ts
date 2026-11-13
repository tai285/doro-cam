import { HeadBucketCommand, S3Client } from '@aws-sdk/client-s3';
import type { AppConfig } from '../config/env.ts';

export interface Storage {
  /** Used by the API and worker for their own reads and writes. */
  client: S3Client;
  /** Signs URLs handed to clients; points at the publicly reachable storage address (S3_PUBLIC_ENDPOINT). */
  presignClient: S3Client;
  bucket: string;
  /** Resolves when the bucket exists and the credentials can reach it. */
  checkBucket(): Promise<void>;
  close(): void;
}

/**
 * Path-style client for any S3-compatible provider (Garage, R2, S3, B2).
 *
 * The AWS SDK's default "flexible checksums" would embed a CRC32 of an *empty* body into every
 * presigned URL, so every real upload would fail validation. Checksums are only calculated when an
 * operation requires them. Integrity is ensured by our own SHA-256 verification (ADR-0008).
 */
export function createStorage(config: AppConfig['s3']): Storage {
  const make = (endpoint: string) =>
    new S3Client({
      endpoint,
      region: config.region,
      forcePathStyle: true,
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
      credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
      // Readiness probes must fail fast rather than retry for a long time.
      maxAttempts: 1,
      requestHandler: { requestTimeout: 3000, connectionTimeout: 2000 },
    });
  const client = make(config.endpoint);
  // Signing is offline, so a client for the public address never needs to reach it from the server.
  const presignClient = config.publicEndpoint === config.endpoint ? client : make(config.publicEndpoint);
  return {
    client,
    presignClient,
    bucket: config.bucket,
    async checkBucket() {
      await client.send(new HeadBucketCommand({ Bucket: config.bucket }));
    },
    close() {
      client.destroy();
      if (presignClient !== client) {
        presignClient.destroy();
      }
    },
  };
}
