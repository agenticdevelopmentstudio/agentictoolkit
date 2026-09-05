import { describe, it, expect, beforeAll } from 'vitest';
import { createLibsqlStorage } from '../src/libsql';
import { roleForEmail } from '../src/storage/ports';
import { hashPassword, verifyPassword } from '../src/auth/password';
import * as schema from '../src/libsql/schema';
import { freshDb } from './helpers/db';
import { testConfig } from './helpers/config';

const authOf = async () => createLibsqlStorage(await freshDb()).auth;

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
    const auth = await authOf();
    const u = await auth.createUser({ email: 'A@B.com', displayName: 'A', role: 'pending' });
    expect(u.email).toBe('a@b.com');
    expect((await auth.findUserByEmail('a@b.com'))?.id).toBe(u.id);
    expect((await auth.getUserById(u.id))?.email).toBe('a@b.com');
  });

  it('roleForEmail honors ADMIN_EMAILS', () => {
    expect(roleForEmail('BOSS@example.com', testConfig())).toBe('admin');
    expect(roleForEmail('rando@x.com', testConfig())).toBe('pending');
  });

  it('sessions resolve to the user; garbage/revoked/expired tokens are null', async () => {
    const auth = await authOf();
    const u = await auth.createUser({ email: 'x@y.com', displayName: 'X', role: 'viewer' });
    const token = await auth.createSession(u.id);
    expect((await auth.resolveSession(token))?.id).toBe(u.id);
    expect(await auth.resolveSession('garbage')).toBeNull();
    expect(await auth.resolveSession(undefined)).toBeNull();
    await auth.revokeSession(token);
    expect(await auth.resolveSession(token)).toBeNull();
    const expired = await auth.createSession(u.id, -1000);
    expect(await auth.resolveSession(expired)).toBeNull();
  });

  it('lists, re-roles, counts admins, and deletes (cascading sessions)', async () => {
    const db = await freshDb();
    const auth = createLibsqlStorage(db).auth;
    const a = await auth.createUser({ email: 'a@a.com', displayName: 'A', role: 'admin' });
    const b = await auth.createUser({ email: 'b@b.com', displayName: 'B', role: 'pending' });
    await auth.createSession(a.id);
    expect((await auth.listUsers()).length).toBe(2);
    expect(await auth.countAdmins()).toBe(1);
    await auth.setUserRoleGuarded(b.id, 'viewer');
    expect((await auth.getUserById(b.id))?.role).toBe('viewer');
    // The store itself refuses to remove the last admin (see last-admin-guard tests).
    expect(await auth.deleteUserGuarded(a.id)).toBe('blocked');
    await auth.setUserRoleGuarded(b.id, 'admin');
    expect(await auth.deleteUserGuarded(a.id)).toBe(true); // b now covers admin; a's sessions cascade
    expect((await db.select().from(schema.sessions)).length).toBe(0);
    expect(await auth.countAdmins()).toBe(1);
    expect(await auth.deleteUserGuarded('missing-id')).toBe(false);
  });
});
