import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../../src/libsql/schema';
import { MIGRATIONS_FOLDER } from '../../src/libsql/client';

export type Db = ReturnType<typeof drizzle<typeof schema>>;

/** THE shared test-DB bootstrap: one in-memory DB with all migrations applied.
 *  This body had been copy-pasted (and had started drifting) across 14 test files —
 *  apply per-test tweaks (extra PRAGMAs etc.) AFTER calling this; don't fork it. */
export async function freshDb(): Promise<Db> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}
