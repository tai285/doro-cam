import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';
import {
  AbortMultipartUploadCommand,
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  DeleteObjectCommand,
  GetBucketCorsCommand,
  GetBucketLifecycleConfigurationCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListMultipartUploadsCommand,
  ListPartsCommand,
  PutObjectCommand,
  UploadPartCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { bucket, config, getBytes, MIB, newClient, put, randomPayload, sha256Hex, testKey } from './helpers.ts';

const client = newClient();
const createdKeys: string[] = [];

after(async () => {
  for (const Key of createdKeys) {
    await client.send(new DeleteObjectCommand({ Bucket: bucket, Key }));
  }
  client.destroy();
});

describe('local S3: bucket configuration', () => {
  it('[SYNC-003] has the abort-incomplete-multipart lifecycle rule (7 days)', async () => {
    const { Rules } = await client.send(new GetBucketLifecycleConfigurationCommand({ Bucket: bucket }));
    const rule = Rules?.find((r) => r.ID === 'abort-incomplete-multipart-uploads');
    assert.ok(rule, 'lifecycle rule missing');
    assert.equal(rule.Status, 'Enabled');
    assert.equal(rule.AbortIncompleteMultipartUpload?.DaysAfterInitiation, 7);
  });

  it('[SYNC-003] allows browser PUT/GET/HEAD from the configured origins and exposes ETag', async () => {
    const { CORSRules } = await client.send(new GetBucketCorsCommand({ Bucket: bucket }));
    const rule = CORSRules?.[0];
    assert.ok(rule, 'CORS rule missing');
    assert.deepEqual(rule.AllowedOrigins, config.corsOrigins);
    assert.deepEqual([...(rule.AllowedMethods ?? [])].sort(), ['GET', 'HEAD', 'PUT']);
    assert.ok(rule.ExposeHeaders?.includes('ETag'));
  });

  it('[PRIV-003] rejects unauthenticated access to the bucket', async () => {
    const key = testKey('private.bin');
    const response = await fetch(`${config.s3.endpoint}/${bucket}/${key}`);
    assert.ok(response.status === 403 || response.status === 404, `unexpected status ${response.status}`);
    const listing = await fetch(`${config.s3.endpoint}/${bucket}?list-type=2`);
    assert.equal(listing.status, 403, 'anonymous bucket listing must be denied');
  });
});

describe('local S3: single presigned PUT/GET (ADR-0008)', () => {
  it('[NFR-005] round-trips an object with an identical SHA-256', async () => {
    const key = testKey('photo.jpg');
    createdKeys.push(key);
    const payload = randomPayload(2 * MIB + 123);

    const putUrl = await getSignedUrl(client, new PutObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 60 });
    const putResponse = await put(putUrl, payload);
    assert.equal(putResponse.status, 200);

    const head = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    assert.equal(head.ContentLength, payload.length);

    const getUrl = await getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 60 });
    const { response, bytes } = await getBytes(getUrl);
    assert.equal(response.status, 200);
    assert.equal(sha256Hex(bytes), sha256Hex(payload));
  });

  it('[WEB-004] honours response-content-disposition on presigned downloads', async () => {
    const key = testKey('named.jpg');
    createdKeys.push(key);
    await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: randomPayload(1024) }));
    const url = await getSignedUrl(
      client,
      new GetObjectCommand({
        Bucket: bucket,
        Key: key,
        ResponseContentDisposition: 'attachment; filename="DoroCam_20260930_original.jpg"',
      }),
      { expiresIn: 60 },
    );
    const { response } = await getBytes(url);
    assert.equal(response.headers.get('content-disposition'), 'attachment; filename="DoroCam_20260930_original.jpg"');
  });

  it('[PRIV-003] rejects an expired presigned URL, and a freshly presigned URL works again', async () => {
    const key = testKey('expired.bin');
    createdKeys.push(key);
    const payload = randomPayload(64);
    await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: payload }));
    const command = new GetObjectCommand({ Bucket: bucket, Key: key });
    const expired = await getSignedUrl(client, command, { expiresIn: 1 });
    await new Promise((resolve) => setTimeout(resolve, 2500));

    const rejected = await getBytes(expired);
    // Providers differ: AWS S3 answers 403 AccessDenied, Garage answers 400 InvalidRequest.
    // Clients must therefore treat both as "re-presign and retry" (docs/specs/upload-sync.md).
    assert.ok([400, 403].includes(rejected.response.status), `unexpected status ${rejected.response.status}`);
    assert.notDeepEqual(rejected.bytes, payload, 'expired URL must not return the object');

    const fresh = await getSignedUrl(client, command, { expiresIn: 60 });
    const accepted = await getBytes(fresh);
    assert.equal(accepted.response.status, 200);
    assert.equal(sha256Hex(accepted.bytes), sha256Hex(payload));
  });

  it('[PRIV-003] rejects a presigned URL whose key was tampered with', async () => {
    const key = testKey('signed.bin');
    const other = testKey('other.bin');
    createdKeys.push(key, other);
    await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: randomPayload(16) }));
    await client.send(new PutObjectCommand({ Bucket: bucket, Key: other, Body: randomPayload(16) }));
    const url = await getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 60 });
    const tampered = url.replace(encodeURI(key), encodeURI(other));
    assert.notEqual(tampered, url);
    const { response } = await getBytes(tampered);
    assert.equal(response.status, 403);
  });
});

describe('local S3: multipart with per-part presigned PUTs (ADR-0008, docs/specs/upload-sync.md)', () => {
  const PART_SIZE = 5 * MIB;

  async function startUpload(key: string): Promise<string> {
    const { UploadId } = await client.send(new CreateMultipartUploadCommand({ Bucket: bucket, Key: key }));
    assert.ok(UploadId);
    return UploadId;
  }

  async function uploadPart(key: string, uploadId: string, partNumber: number, body: Buffer): Promise<string> {
    const url = await getSignedUrl(
      client,
      new UploadPartCommand({ Bucket: bucket, Key: key, UploadId: uploadId, PartNumber: partNumber }),
      { expiresIn: 300 },
    );
    const response = await put(url, body);
    assert.equal(response.status, 200, `part ${partNumber} upload failed`);
    const etag = response.headers.get('etag');
    assert.ok(etag, `part ${partNumber} returned no ETag`);
    return etag;
  }

  it('[SYNC-003] uploads out of order, lists parts, completes, and verifies the checksum', async () => {
    const key = testKey('motion.mp4');
    createdKeys.push(key);
    const parts = [randomPayload(PART_SIZE), randomPayload(PART_SIZE), randomPayload(1 * MIB + 7)];
    const whole = Buffer.concat(parts);
    const uploadId = await startUpload(key);

    const etags = new Map<number, string>();
    for (const number of [3, 1]) {
      etags.set(number, await uploadPart(key, uploadId, number, parts[number - 1] as Buffer));
    }

    // A resumed client asks which parts are already stored (ListParts) and only sends the rest.
    const listed = await client.send(new ListPartsCommand({ Bucket: bucket, Key: key, UploadId: uploadId }));
    assert.deepEqual(
      listed.Parts?.map((part) => part.PartNumber),
      [1, 3],
    );
    assert.equal(listed.Parts?.[0]?.ETag, etags.get(1));
    assert.equal(listed.Parts?.[1]?.Size, parts[2]?.length);

    etags.set(2, await uploadPart(key, uploadId, 2, parts[1] as Buffer));

    await client.send(
      new CompleteMultipartUploadCommand({
        Bucket: bucket,
        Key: key,
        UploadId: uploadId,
        MultipartUpload: { Parts: [1, 2, 3].map((n) => ({ PartNumber: n, ETag: etags.get(n) as string })) },
      }),
    );

    const head = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    assert.equal(head.ContentLength, whole.length);

    const url = await getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 60 });
    const { bytes } = await getBytes(url);
    assert.equal(sha256Hex(bytes), sha256Hex(whole));
  });

  it('[SYNC-003] re-uploading an existing part number replaces it safely (retry after a kill)', async () => {
    const key = testKey('retry.bin');
    createdKeys.push(key);
    const first = randomPayload(PART_SIZE);
    const second = randomPayload(PART_SIZE);
    const last = randomPayload(2048);
    const uploadId = await startUpload(key);

    await uploadPart(key, uploadId, 1, first);
    const retried = await uploadPart(key, uploadId, 1, second);
    const lastEtag = await uploadPart(key, uploadId, 2, last);

    await client.send(
      new CompleteMultipartUploadCommand({
        Bucket: bucket,
        Key: key,
        UploadId: uploadId,
        MultipartUpload: {
          Parts: [
            { PartNumber: 1, ETag: retried },
            { PartNumber: 2, ETag: lastEtag },
          ],
        },
      }),
    );
    const url = await getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 60 });
    const { bytes } = await getBytes(url);
    assert.equal(sha256Hex(bytes), sha256Hex(Buffer.concat([second, last])));
  });

  it('[SYNC-003] rejects completion with a wrong ETag', async () => {
    const key = testKey('bad-etag.bin');
    const uploadId = await startUpload(key);
    await uploadPart(key, uploadId, 1, randomPayload(1024));
    await assert.rejects(
      client.send(
        new CompleteMultipartUploadCommand({
          Bucket: bucket,
          Key: key,
          UploadId: uploadId,
          MultipartUpload: { Parts: [{ PartNumber: 1, ETag: '"00000000000000000000000000000000"' }] },
        }),
      ),
    );
    await client.send(new AbortMultipartUploadCommand({ Bucket: bucket, Key: key, UploadId: uploadId }));
  });

  it('[SYNC-003] abort removes the upload and its stored parts', async () => {
    const key = testKey('abort.bin');
    const uploadId = await startUpload(key);
    await uploadPart(key, uploadId, 1, randomPayload(PART_SIZE));

    await client.send(new AbortMultipartUploadCommand({ Bucket: bucket, Key: key, UploadId: uploadId }));

    const uploads = await client.send(new ListMultipartUploadsCommand({ Bucket: bucket, Prefix: key }));
    assert.equal(uploads.Uploads?.length ?? 0, 0);
    await assert.rejects(client.send(new ListPartsCommand({ Bucket: bucket, Key: key, UploadId: uploadId })));
  });
});
