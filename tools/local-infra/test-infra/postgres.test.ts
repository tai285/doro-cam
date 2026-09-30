import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import pg from 'pg';
import { config } from './helpers.ts';

describe('local Postgres', () => {
  const client = new pg.Client({ connectionString: config.databaseUrl });

  before(async () => {
    await client.connect();
  });
  after(async () => {
    await client.end();
  });

  it('[NFR-013] is PostgreSQL 17 or newer (ADR-0007)', async () => {
    const { rows } = await client.query<{ major: number }>(
      "select current_setting('server_version_num')::int / 10000 as major",
    );
    const major = rows[0]?.major ?? 0;
    assert.ok(major >= 17, `expected Postgres >= 17, got ${major}`);
  });

  it('[NFR-013] supports transactions with rollback', async () => {
    await client.query('create temp table tx_probe (id int primary key)');
    await client.query('begin');
    await client.query('insert into tx_probe values (1)');
    await client.query('rollback');
    const { rows } = await client.query<{ count: string }>('select count(*) from tx_probe');
    assert.equal(rows[0]?.count, '0');
  });

  it('[NFR-013] supports SKIP LOCKED, which pg-boss relies on (ADR-0010)', async () => {
    await client.query('create temp table queue_probe (id int primary key)');
    await client.query('insert into queue_probe values (1), (2)');
    const { rows } = await client.query<{ id: number }>(
      'select id from queue_probe order by id for update skip locked limit 1',
    );
    assert.deepEqual(rows, [{ id: 1 }]);
  });

  it('[NFR-013] can generate UUIDs server-side', async () => {
    const { rows } = await client.query<{ id: string }>('select gen_random_uuid()::text as id');
    assert.match(rows[0]?.id ?? '', /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});
