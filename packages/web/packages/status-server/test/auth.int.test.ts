import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Hono } from 'hono';
import type { Db } from '../src/libsql/client';
import { requireAuth, requireAdmin, type AuthVars } from '../src/middleware/auth';
import { createUser, createSession, type UserRole } from '../src/storage/auth-store';
import { freshDb } from './helpers/db';
import { testConfig } from './helpers/config';

function appWith(db: Db) {
  const app = new Hono<{ Variables: AuthVars }>();
  app.use('*', requireAuth(db, testConfig()));
  app.get('/read', (c) => c.json({ ok: true }));
  app.post('/write', requireAdmin, (c) => c.json({ ok: true }));
  app.get('/snapshot', (c) => c.json({ ok: true }));
  return app;
}

/** A session cookie for a freshly-created user of the given role. */
async function cookieFor(db: Db, role: UserRole): Promise<string> {
  const u = await createUser(db, { email: `${role}@x.com`, displayName: role, role });
  const token = await createSession(db, u.id);
  return `status_auth=${token}`;
}

describe('requireAuth (session-based)', () => {
  beforeEach(() => {
    process.env.PEER_TOKEN = 'peer';
    delete process.env.AUTH_DISABLED;
  });
  afterEach(() => {
    delete process.env.AUTH_DISABLED;
  });

  it('rejects with 401 when no session', async () => {
    const res = await appWith(await freshDb()).request('/read');
    expect(res.status).toBe(401);
  });

  it('lets a viewer read but 403s on an admin route', async () => {
    const db = await freshDb();
    const Cookie = await cookieFor(db, 'viewer');
    expect((await appWith(db).request('/read', { headers: { Cookie } })).status).toBe(200);
    expect((await appWith(db).request('/write', { method: 'POST', headers: { Cookie } })).status).toBe(403);
  });

  it('lets an admin hit an admin route', async () => {
    const db = await freshDb();
    const Cookie = await cookieFor(db, 'admin');
    expect((await appWith(db).request('/write', { method: 'POST', headers: { Cookie } })).status).toBe(200);
  });

  it('rejects a pending user with 401', async () => {
    const db = await freshDb();
    const Cookie = await cookieFor(db, 'pending');
    expect((await appWith(db).request('/read', { headers: { Cookie } })).status).toBe(401);
  });

  it('accepts PEER_TOKEN only on /snapshot', async () => {
    const db = await freshDb();
    const headers = { Authorization: 'Bearer peer' };
    expect((await appWith(db).request('/snapshot', { headers })).status).toBe(200);
    expect((await appWith(db).request('/read', { headers })).status).toBe(401);
  });

  it('AUTH_DISABLED=1 runs everyone as admin', async () => {
    process.env.AUTH_DISABLED = '1';
    const db = await freshDb();
    expect((await appWith(db).request('/write', { method: 'POST' })).status).toBe(200);
  });
});
