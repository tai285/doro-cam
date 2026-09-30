import { compose, runGarage } from './compose.ts';
import { loadConfig } from './config.ts';
import { bootstrapGarage } from './garage.ts';
import { configureBucket, createS3Client } from './storage.ts';

const config = loadConfig();

console.log('Starting Postgres and S3 storage...');
await compose('up', '-d', '--wait');

console.log('Bootstrapping storage...');
const result = await bootstrapGarage(runGarage, config.s3);
console.log(
  `  layout ${result.layoutApplied ? 'applied' : 'already applied'}, ` +
    `bucket ${result.bucketCreated ? 'created' : 'already exists'}, ` +
    `key ${result.keyImported ? 'imported' : 'already imported'}`,
);

const client = createS3Client(config.s3);
await configureBucket(client, config.s3.bucket, config.corsOrigins);
client.destroy();
console.log(`  CORS and lifecycle rules applied to "${config.s3.bucket}"`);

console.log(`Ready: Postgres ${new URL(config.databaseUrl).host}, S3 ${config.s3.endpoint}`);
