import {
  type BucketLifecycleConfiguration,
  type CORSConfiguration,
  PutBucketCorsCommand,
  PutBucketLifecycleConfigurationCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import type { S3Config } from './config.ts';

/** Days after which an unfinished multipart upload is aborted (docs/specs/upload-sync.md). */
export const ABORT_INCOMPLETE_UPLOAD_DAYS = 7;

/**
 * Path-style client for any S3-compatible provider (Garage, R2, S3, B2).
 *
 * The AWS SDK's default "flexible checksums" would embed a CRC32 of an *empty* body into every
 * presigned URL (x-amz-checksum-crc32=AAAAAA==), so every real upload would fail validation.
 * Checksums are therefore only calculated when an operation requires them. Integrity is ensured
 * by our own SHA-256 verification instead (ADR-0008, docs/specs/upload-sync.md).
 */
export function createS3Client(config: S3Config): S3Client {
  return new S3Client({
    endpoint: config.endpoint,
    region: config.region,
    forcePathStyle: true,
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
    credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
  });
}

/**
 * Browsers upload and download directly to storage with presigned URLs, so storage must allow
 * cross-origin PUT/GET/HEAD and expose ETag (needed to complete multipart uploads from the web).
 */
export function buildCorsConfiguration(origins: readonly string[]): CORSConfiguration {
  return {
    CORSRules: [
      {
        AllowedOrigins: [...origins],
        AllowedMethods: ['GET', 'PUT', 'HEAD'],
        AllowedHeaders: ['*'],
        ExposeHeaders: ['ETag'],
        MaxAgeSeconds: 3600,
      },
    ],
  };
}

export function buildLifecycleConfiguration(abortAfterDays: number): BucketLifecycleConfiguration {
  if (!Number.isInteger(abortAfterDays) || abortAfterDays < 1) {
    throw new RangeError(`abortAfterDays must be a positive integer (got ${abortAfterDays})`);
  }
  return {
    Rules: [
      {
        ID: 'abort-incomplete-multipart-uploads',
        Status: 'Enabled',
        Filter: { Prefix: '' },
        AbortIncompleteMultipartUpload: { DaysAfterInitiation: abortAfterDays },
      },
    ],
  };
}

/** Applies CORS and lifecycle rules to the bucket. PUT semantics make this idempotent. */
export async function configureBucket(client: S3Client, bucket: string, origins: readonly string[]): Promise<void> {
  await client.send(
    new PutBucketCorsCommand({ Bucket: bucket, CORSConfiguration: buildCorsConfiguration(origins) }),
  );
  await client.send(
    new PutBucketLifecycleConfigurationCommand({
      Bucket: bucket,
      LifecycleConfiguration: buildLifecycleConfiguration(ABORT_INCOMPLETE_UPLOAD_DAYS),
    }),
  );
}
