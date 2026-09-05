import { describe, it, expect, beforeAll } from 'vitest';
import {
  createUser,
  findUserByEmail,
  getUserById,
  listUsers,
  setUserRoleGuarded,
  deleteUserGuarded,
  countAdmins,
  roleForEmail,
  createSession,
  resolveSession,
  revokeSession,
} from '../src/storage/auth-store';
import { hashPassword, verifyPassword } from '../src/auth/password';
import * as schema from '../src/libsql/schema';
import { freshDb } from './helpers/db';
import { testConfig } from './helpers/config';

describe('auth-store', () => {
  beforeAll(() => {
    process.env.ADMIN_EMAILS = 'boss@example.com';
  });

  it('hashes and verifies passwords', async () => {
    const h = await hashPassword('s3cret');
    expect(h).not.toBe('s3cret');
    expect(await verifyPassword('s3cret', h)).toBe(true);
    expect(await verifyPassword('nope', h)).toBe(false);
  });

  it('creates and finds users with lower-cased email', async () => {
    const db = await freshDb();
    const u = await createUser(db, { email: 'A@B.com', displayName: 'A', role: 'pending' });
    expect(u.email).toBe('a@b.com');
    expect((await findUserByEmail(db, 'a@b.com'))?.id).toBe(u.id);
    expect((await getUserById(db, u.id))?.email).toBe('a@b.com');
  });

  it('roleForEmail honors ADMIN_EMAILS', () => {
    expect(roleForEmail('BOSS@example.com', testConfig())).toBe('admin');
    expect(roleForEmail('rando@x.com', testConfig())).toBe('pending');
  });

  it('sessions resolve to the user; garbage/revoked/expired tokens are null', async () => {
    const db = await freshDb();
    const u = await createUser(db, { email: 'x@y.com', displayName: 'X', role: 'viewer' });
    const token = await createSession(db, u.id);
    expect((await resolveSession(db, token))?.id).toBe(u.id);
    expect(await resolveSession(db, 'garbage')).toBeNull();
    expect(await resolveSession(db, undefined)).toBeNull();
    await revokeSession(db, token);
    expect(await resolveSession(db, token)).toBeNull();
    const expired = await createSession(db, u.id, -1000);
    expect(await resolveSession(db, expired)).toBeNull();
  });

  it('lists, re-roles, counts admins, and deletes (cascading sessions)', async () => {
    const db = await freshDb();
    const a = await createUser(db, { email: 'a@a.com', displayName: 'A', role: 'admin' });
    const b = await createUser(db, { email: 'b@b.com', displayName: 'B', role: 'pending' });
    await createSession(db, a.id);
    expect((await listUsers(db)).length).toBe(2);
    expect(await countAdmins(db)).toBe(1);
    await setUserRoleGuarded(db, b.id, 'viewer');
    expect((await getUserById(db, b.id))?.role).toBe('viewer');
    // The store itself refuses to remove the last admin (see last-admin-guard tests).
    expect(await deleteUserGuarded(db, a.id)).toBe('blocked');
    await setUserRoleGuarded(db, b.id, 'admin');
    expect(await deleteUserGuarded(db, a.id)).toBe(true); // b now covers admin; a's sessions cascade
    expect((await db.select().from(schema.sessions)).length).toBe(0);
    expect(await countAdmins(db)).toBe(1);
    expect(await deleteUserGuarded(db, 'missing-id')).toBe(false);
  });
});
