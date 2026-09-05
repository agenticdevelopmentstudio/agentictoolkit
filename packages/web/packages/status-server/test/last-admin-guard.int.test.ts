import { describe, it, expect, beforeEach } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import {
  createUser,
  createSession,
  countAdmins,
  setUserRoleGuarded,
  deleteUserGuarded,
} from '../src/storage/auth-store';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';

// The last-admin guard used to be a separate countAdmins() read before the
// write — two concurrent demotes/deletes of two different admins both passed
// the count===2 check and left ZERO admins: a permanent lockout (only an admin
// can promote). The guard now lives INSIDE the write statement, and SQLite's
// statement-level serialization makes the race structurally impossible: the
// concurrent case reduces to the sequential one tested here.

async function freshDb(): Promise<Db> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

describe('atomic last-admin guard (store)', () => {
  let db: Db;
  beforeEach(async () => {
    db = await freshDb();
  });

  const admin = (email: string) => createUser(db, { email, displayName: email, role: 'admin' });

  it('blocks demoting the last admin, in the statement itself', async () => {
    const a = await admin('a@x.com');
    expect(await setUserRoleGuarded(db, a.id, 'viewer')).toBe('blocked');
    expect(await countAdmins(db)).toBe(1);
  });

  it('two demote attempts can never remove both admins', async () => {
    const a = await admin('a@x.com');
    const b = await admin('b@x.com');
    const first = await setUserRoleGuarded(db, a.id, 'viewer');
    const second = await setUserRoleGuarded(db, b.id, 'viewer');
    expect(first).not.toBe('blocked');
    expect(second).toBe('blocked');
    expect(await countAdmins(db)).toBe(1);
  });

  it('admin→admin and non-admin changes pass the guard untouched', async () => {
    const a = await admin('a@x.com');
    const v = await createUser(db, { email: 'v@x.com', displayName: 'v', role: 'viewer' });
    expect(await setUserRoleGuarded(db, a.id, 'admin')).toMatchObject({ role: 'admin' });
    expect(await setUserRoleGuarded(db, v.id, 'pending')).toMatchObject({ role: 'pending' });
    expect(await setUserRoleGuarded(db, 'missing-id', 'viewer')).toBeUndefined();
  });

  it('blocks deleting the last admin and keeps their sessions', async () => {
    const a = await admin('a@x.com');
    await createSession(db, a.id);
    expect(await deleteUserGuarded(db, a.id)).toBe('blocked');
    expect(await countAdmins(db)).toBe(1);
    expect((await db.select().from(schema.sessions)).length).toBe(1); // blocked delete must not strip sessions
  });

  it('two delete attempts can never remove both admins', async () => {
    const a = await admin('a@x.com');
    const b = await admin('b@x.com');
    expect(await deleteUserGuarded(db, a.id)).toBe(true);
    expect(await deleteUserGuarded(db, b.id)).toBe('blocked');
    expect(await countAdmins(db)).toBe(1);
  });

  it('deletes a non-admin (and their sessions) normally', async () => {
    await admin('a@x.com');
    const v = await createUser(db, { email: 'v@x.com', displayName: 'v', role: 'viewer' });
    await createSession(db, v.id);
    expect(await deleteUserGuarded(db, v.id)).toBe(true);
    expect((await db.select().from(schema.sessions)).length).toBe(0);
    expect(await deleteUserGuarded(db, 'missing-id')).toBe(false);
  });
});
