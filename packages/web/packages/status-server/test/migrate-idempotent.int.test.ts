import { describe, it, expect } from 'vitest';
import { sql } from 'drizzle-orm';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import * as schema from '../src/libsql/schema';
import { MIGRATIONS_FOLDER, migrateDb } from '../src/libsql/client';

// migrateDb is called on every boot of an embedded-file host, not just the first —
// drizzle records each applied migration in `__drizzle_migrations` and must skip it
// on a re-run rather than re-executing (and erroring on) a migration whose tables
// already exist.

describe('migrateDb is idempotent', () => {
  it('re-running against an already-migrated DB is a no-op', async () => {
    const db = drizzle(createClient({ url: ':memory:' }), { schema });

    await migrateDb(db, MIGRATIONS_FOLDER);
    const applied = await db.all<{ hash: string }>(sql`select hash from __drizzle_migrations order by id`);
    expect(applied.length).toBeGreaterThan(0);

    await expect(migrateDb(db, MIGRATIONS_FOLDER)).resolves.toBeUndefined();
    const appliedAgain = await db.all<{ hash: string }>(sql`select hash from __drizzle_migrations order by id`);
    expect(appliedAgain).toEqual(applied);
  });

  it('a third run still leaves the schema queryable', async () => {
    const db = drizzle(createClient({ url: ':memory:' }), { schema });
    await migrateDb(db, MIGRATIONS_FOLDER);
    await migrateDb(db, MIGRATIONS_FOLDER);
    await migrateDb(db, MIGRATIONS_FOLDER);

    // A migration re-applied over existing tables would fail loudly (duplicate
    // column/table) long before this — this just confirms the DB is left in a
    // normal, working state, not merely that migrateDb didn't throw.
    const rows = await db.all(sql`select count(*) as n from site_groups`);
    expect(rows[0]).toEqual({ n: 0 });
  });
});
