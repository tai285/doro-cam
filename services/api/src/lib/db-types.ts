import type { NodePgDatabase } from 'drizzle-orm/node-postgres';

/** A database handle or the transaction handle passed to `db.transaction` callbacks: both run queries. */
export type Db = NodePgDatabase;
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
export type Executor = Db | Tx;
