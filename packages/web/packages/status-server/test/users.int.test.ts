import { describe, it, expect, beforeEach } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

async function boot() {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return createApp({ db, config: testConfig() });
}

type App = Awaited<ReturnType<typeof boot>>;

function sessionCookie(res: Response): string {
  const m = (res.headers.get('set-cookie') ?? '').match(/status_auth=[^;]+/);
  if (!m) throw new Error('no status_auth cookie');
  return m[0];
}

const post = (body: unknown) => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

interface UserRow {
  id: string;
  email: string;
  role: string;
}

/** Sign up and return the session cookie. boss@example.com is admin via ADMIN_EMAILS. */
async function signup(app: App, email: string): Promise<string> {
  return sessionCookie(await app.request('/auth/signup', post({ email, password: 'password123' })));
}

async function listUsers(app: App, cookie: string): Promise<{ status: number; body: UserRow[] }> {
  const res = await app.request('/users', { headers: { Cookie: cookie } });
  return { status: res.status, body: res.ok ? ((await res.json()) as UserRow[]) : [] };
}

describe('/users admin management', () => {
  beforeEach(() => {
    process.env.ADMIN_EMAILS = 'boss@example.com';
    delete process.env.AUTH_DISABLED;
  });

  it('admin lists users; unauthenticated is 401', async () => {
    const app = await boot();
    const admin = await signup(app, 'boss@example.com');
    await signup(app, 'pending@x.com');
    const listed = await listUsers(app, admin);
    expect(listed.status).toBe(200);
    expect(listed.body).toHaveLength(2);
    expect((await app.request('/users')).status).toBe(401);
  });

  it('non-admin (viewer) is 403', async () => {
    const app = await boot();
    const admin = await signup(app, 'boss@example.com');
    const viewerCookie = await signup(app, 'v@x.com');
    const { body } = await listUsers(app, admin);
    const viewer = body.find((u) => u.email === 'v@x.com')!;
    await app.request(`/users/${viewer.id}`, { method: 'PATCH', headers: { Cookie: admin, 'Content-Type': 'application/json' }, body: JSON.stringify({ role: 'viewer' }) });
    expect((await app.request('/users', { headers: { Cookie: viewerCookie } })).status).toBe(403);
  });

  it('promotes a pending user to viewer', async () => {
    const app = await boot();
    const admin = await signup(app, 'boss@example.com');
    await signup(app, 'p@x.com');
    const { body } = await listUsers(app, admin);
    const p = body.find((u) => u.email === 'p@x.com')!;
    const res = await app.request(`/users/${p.id}`, { method: 'PATCH', headers: { Cookie: admin, 'Content-Type': 'application/json' }, body: JSON.stringify({ role: 'viewer' }) });
    expect(res.status).toBe(200);
    expect(((await res.json()) as UserRow).role).toBe('viewer');
  });

  it('refuses to demote or delete the last admin', async () => {
    const app = await boot();
    const admin = await signup(app, 'boss@example.com');
    const { body } = await listUsers(app, admin);
    const me = body.find((u) => u.email === 'boss@example.com')!;
    const demote = await app.request(`/users/${me.id}`, { method: 'PATCH', headers: { Cookie: admin, 'Content-Type': 'application/json' }, body: JSON.stringify({ role: 'viewer' }) });
    expect(demote.status).toBe(409);
    expect((await app.request(`/users/${me.id}`, { method: 'DELETE', headers: { Cookie: admin } })).status).toBe(409);
  });

  it('deletes a non-admin and 404s on a missing id', async () => {
    const app = await boot();
    const admin = await signup(app, 'boss@example.com');
    await signup(app, 'gone@x.com');
    const { body } = await listUsers(app, admin);
    const gone = body.find((u) => u.email === 'gone@x.com')!;
    expect((await app.request(`/users/${gone.id}`, { method: 'DELETE', headers: { Cookie: admin } })).status).toBe(200);
    expect((await app.request('/users/nope', { method: 'DELETE', headers: { Cookie: admin } })).status).toBe(404);
  });
});
