import { GetObjectCommand, PutObjectCommand, UploadPartCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { Storage } from './storage.ts';

export const UPLOAD_URL_TTL_SECONDS = 3600;
export const DOWNLOAD_URL_TTL_SECONDS = 600;

export interface SignedUrl {
  url: string;
  expiresAt: string;
}

function expiry(seconds: number): string {
  return new Date(Date.now() + seconds * 1000).toISOString();
}

export async function presignPut(storage: Storage, key: string, contentType: string): Promise<SignedUrl> {
  const url = await getSignedUrl(
    storage.presignClient,
    new PutObjectCommand({ Bucket: storage.bucket, Key: key, ContentType: contentType }),
    { expiresIn: UPLOAD_URL_TTL_SECONDS, signableHeaders: new Set(['content-type']) },
  );
  return { url, expiresAt: expiry(UPLOAD_URL_TTL_SECONDS) };
}

export async function presignPart(storage: Storage, key: string, uploadId: string, partNumber: number): Promise<SignedUrl> {
  const url = await getSignedUrl(
    storage.presignClient,
    new UploadPartCommand({ Bucket: storage.bucket, Key: key, UploadId: uploadId, PartNumber: partNumber }),
    { expiresIn: UPLOAD_URL_TTL_SECONDS },
  );
  return { url, expiresAt: expiry(UPLOAD_URL_TTL_SECONDS) };
}

export async function presignGet(
  storage: Storage,
  key: string,
  options: { filename?: string; contentType?: string } = {},
): Promise<SignedUrl> {
  const url = await getSignedUrl(
    storage.presignClient,
    new GetObjectCommand({
      Bucket: storage.bucket,
      Key: key,
      ...(options.filename === undefined
        ? {}
        : { ResponseContentDisposition: `attachment; filename="${options.filename.replace(/[^A-Za-z0-9._-]/g, '_')}"` }),
      ...(options.contentType === undefined ? {} : { ResponseContentType: options.contentType }),
    }),
    { expiresIn: DOWNLOAD_URL_TTL_SECONDS },
  );
  return { url, expiresAt: expiry(DOWNLOAD_URL_TTL_SECONDS) };
}
