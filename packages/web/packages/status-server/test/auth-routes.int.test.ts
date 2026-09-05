import { describe, it, expect, beforeEach, afterEach } from 'vitest';
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

function sessionCookie(res: Response): string {
  const m = (res.headers.get('set-cookie') ?? '').match(/status_auth=[^;]+/);
  if (!m) throw new Error('no status_auth cookie in response');
  return m[0];
}

const post = (body: unknown) => ({
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

describe('/auth routes', () => {
  beforeEach(() => {
    process.env.ADMIN_EMAILS = 'boss@example.com';
    delete process.env.AUTH_DISABLED;
  });
  afterEach(() => {
    delete process.env.AUTH_DISABLED;
  });

  it('signup creates a pending user + session; me reflects it', async () => {
    const app = await boot();
    const res = await app.request('/auth/signup', post({ email: 'New@User.com', password: 'password123', displayName: 'New' }));
    expect(res.status).toBe(201);
    expect((await res.json() as { user: { email: string; role: string; displayName: string } | null }).user).toMatchObject({ email: 'new@user.com', role: 'pending', displayName: 'New' });
    const me = await app.request('/auth/me', { headers: { Cookie: sessionCookie(res) } });
    expect((await me.json() as { user: { email: string } | null }).user?.email).toBe('new@user.com');
  });

  it('signup with an ADMIN_EMAILS address is auto-admin', async () => {
    const app = await boot();
    const res = await app.request('/auth/signup', post({ email: 'boss@example.com', password: 'password123' }));
    expect((await res.json() as { user: { role: string } | null }).user?.role).toBe('admin');
  });

  it('duplicate signup is 409', async () => {
    const app = await boot();
    await app.request('/auth/signup', post({ email: 'a@b.com', password: 'password123' }));
    expect((await app.request('/auth/signup', post({ email: 'a@b.com', password: 'password123' }))).status).toBe(409);
  });

  it('weak/invalid signup body is 400', async () => {
    const app = await boot();
    expect((await app.request('/auth/signup', post({ email: 'not-an-email', password: 'x' }))).status).toBe(400);
  });

  it('login rejects a wrong password and accepts the right one', async () => {
    const app = await boot();
    await app.request('/auth/signup', post({ email: 'c@d.com', password: 'rightpass1' }));
    expect((await app.request('/auth/login', post({ email: 'c@d.com', password: 'wrong' }))).status).toBe(401);
    const ok = await app.request('/auth/login', post({ email: 'c@d.com', password: 'rightpass1' }));
    expect(ok.status).toBe(200);
    const me = await app.request('/auth/me', { headers: { Cookie: sessionCookie(ok) } });
    expect((await me.json() as { user: { email: string } | null }).user?.email).toBe('c@d.com');
  });

  it('logout clears the session', async () => {
    const app = await boot();
    const cookie = sessionCookie(await app.request('/auth/signup', post({ email: 'e@f.com', password: 'password123' })));
    await app.request('/auth/logout', { method: 'POST', headers: { Cookie: cookie } });
    const me = await app.request('/auth/me', { headers: { Cookie: cookie } });
    expect((await me.json() as { user: { email: string } | null }).user).toBeNull();
  });

  it('me is 200 + null without a cookie (never 401)', async () => {
    const app = await boot();
    const me = await app.request('/auth/me');
    expect(me.status).toBe(200);
    expect((await me.json() as { user: { email: string } | null }).user).toBeNull();
  });
});
