import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
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

const post = (body: unknown) => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

function cookieVal(res: Response, name: string): string {
  const m = (res.headers.get('set-cookie') ?? '').match(new RegExp(`${name}=[^;]+`));
  if (!m) throw new Error(`no ${name} cookie`);
  return m[0];
}
function sessionCookie(res: Response): string {
  return cookieVal(res, 'status_auth');
}

/** Mock the three GitHub endpoints; `profileEmail=null` forces the /user/emails fallback. */
function mockGithub(profile: { id: number; login: string; name: string | null; email: string | null }, primaryEmail = 'primary@gh.com') {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.includes('login/oauth/access_token')) return new Response(JSON.stringify({ access_token: 'gho_x' }), { status: 200 });
      if (u.endsWith('/user')) return new Response(JSON.stringify(profile), { status: 200 });
      if (u.endsWith('/user/emails')) {
        return new Response(JSON.stringify([
          { email: 'unverified@gh.com', primary: false, verified: false },
          { email: primaryEmail, primary: true, verified: true },
        ]), { status: 200 });
      }
      throw new Error(`unexpected fetch ${u}`);
    }),
  );
}

/** Drive a full GitHub login (start → callback) and return the callback response. */
async function githubLogin(app: App, profile: { id: number; login: string; name: string | null; email: string | null }, primaryEmail?: string): Promise<Response> {
  const start = await app.request('/auth/github/start');
  const stateCookie = cookieVal(start, 'gh_oauth_state');
  mockGithub(profile, primaryEmail);
  return app.request(`/auth/github/callback?code=abc&state=${stateCookie.split('=')[1]}`, { headers: { Cookie: stateCookie } });
}

async function meEmailRole(app: App, cookie: string): Promise<{ email: string; role: string } | null> {
  const body = (await (await app.request('/auth/me', { headers: { Cookie: cookie } })).json()) as { user: { email: string; role: string } | null };
  return body.user;
}

describe('auth edge cases', () => {
  beforeEach(() => {
    process.env.GITHUB_OAUTH_CLIENT_ID = 'cid';
    process.env.GITHUB_OAUTH_CLIENT_SECRET = 'secret';
    process.env.PUBLIC_BASE_URL = 'https://status.example.com';
    process.env.ADMIN_EMAILS = '';
    delete process.env.AUTH_DISABLED;
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.AUTH_DISABLED;
  });

  it('GitHub: private profile email falls back to the primary verified /user/emails address', async () => {
    const app = await boot();
    const cb = await githubLogin(app, { id: 1, login: 'noemail', name: 'No Email', email: null }, 'fallback@gh.com');
    expect(cb.status).toBe(302);
    expect((await meEmailRole(app, sessionCookie(cb)))?.email).toBe('fallback@gh.com');
  });

  it('GitHub: a github email in ADMIN_EMAILS is provisioned as admin', async () => {
    process.env.ADMIN_EMAILS = 'boss@gh.com';
    const app = await boot();
    const cb = await githubLogin(app, { id: 2, login: 'boss', name: 'Boss', email: 'Boss@GH.com' });
    expect((await meEmailRole(app, sessionCookie(cb)))?.role).toBe('admin');
  });

  it('GitHub: logging in with the email of an existing password account LINKS, not duplicates', async () => {
    process.env.ADMIN_EMAILS = 'dual@x.com'; // make the password account an admin so we can list users
    const app = await boot();
    const signup = await app.request('/auth/signup', post({ email: 'dual@x.com', password: 'password123' }));
    const adminCookie = sessionCookie(signup);
    // Same email arrives via GitHub with a distinct githubId.
    const cb = await githubLogin(app, { id: 9001, login: 'dual', name: 'Dual', email: 'dual@x.com' });
    expect(cb.status).toBe(302);
    // Still exactly ONE account (the unique-email index was not tripped).
    const users = (await (await app.request('/users', { headers: { Cookie: adminCookie } })).json()) as unknown[];
    expect(users).toHaveLength(1);
    // And the original password login still works.
    expect((await app.request('/auth/login', post({ email: 'dual@x.com', password: 'password123' }))).status).toBe(200);
  });

  it('GitHub: /auth/github/start 500s when the client id is not configured', async () => {
    process.env.GITHUB_OAUTH_CLIENT_ID = '';
    const app = await boot();
    expect((await app.request('/auth/github/start')).status).toBe(500);
  });

  it('GitHub: /auth/github/start 500s when PUBLIC_BASE_URL (+ RAILWAY_PUBLIC_DOMAIN) is unset', async () => {
    delete process.env.PUBLIC_BASE_URL;
    delete process.env.RAILWAY_PUBLIC_DOMAIN;
    const app = await boot();
    expect((await app.request('/auth/github/start')).status).toBe(500);
  });

  it('GitHub: a non-200 from /user fails the callback (502), never creating a githubId="undefined" account', async () => {
    const app = await boot();
    const start = await app.request('/auth/github/start');
    const stateCookie = cookieVal(start, 'gh_oauth_state');
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) => {
        const u = String(url);
        if (u.includes('login/oauth/access_token')) return new Response(JSON.stringify({ access_token: 'gho_x' }), { status: 200 });
        if (u.endsWith('/user')) return new Response(JSON.stringify({ message: 'Bad credentials' }), { status: 401 });
        throw new Error(`unexpected fetch ${u}`);
      }),
    );
    const cb = await app.request(`/auth/github/callback?code=abc&state=${stateCookie.split('=')[1]}`, { headers: { Cookie: stateCookie } });
    expect(cb.status).toBe(502);
  });

  it('signup without displayName defaults it to the email', async () => {
    const app = await boot();
    const res = await app.request('/auth/signup', post({ email: 'noname@x.com', password: 'password123' }));
    expect((await res.json() as { user: { displayName: string } }).user.displayName).toBe('noname@x.com');
  });

  it('signup tolerates an EMPTY displayName (the shared SignupCard posts "")', async () => {
    const app = await boot();
    const res = await app.request('/auth/signup', post({ email: 'empty@x.com', password: 'password123', displayName: '' }));
    expect(res.status).toBe(201);
    expect((await res.json() as { user: { displayName: string } }).user.displayName).toBe('empty@x.com');
  });

  it('/users PATCH rejects an unknown role with 400', async () => {
    process.env.ADMIN_EMAILS = 'admin@x.com';
    const app = await boot();
    const adminCookie = sessionCookie(await app.request('/auth/signup', post({ email: 'admin@x.com', password: 'password123' })));
    const list = (await (await app.request('/users', { headers: { Cookie: adminCookie } })).json()) as { id: string }[];
    const res = await app.request(`/users/${list[0].id}`, {
      method: 'PATCH',
      headers: { Cookie: adminCookie, 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: 'superuser' }),
    });
    expect(res.status).toBe(400);
  });

  it('a session keeps working across requests; logout is idempotent', async () => {
    const app = await boot();
    const cookie = sessionCookie(await app.request('/auth/signup', post({ email: 'persist@x.com', password: 'password123' })));
    expect((await meEmailRole(app, cookie))?.email).toBe('persist@x.com');
    expect((await app.request('/auth/logout', { method: 'POST', headers: { Cookie: cookie } })).status).toBe(200);
    // Second logout with the (now-revoked) cookie still succeeds, doesn't throw.
    expect((await app.request('/auth/logout', { method: 'POST', headers: { Cookie: cookie } })).status).toBe(200);
    expect(await meEmailRole(app, cookie)).toBeNull();
  });

  it('login is case-insensitive on the email', async () => {
    const app = await boot();
    await app.request('/auth/signup', post({ email: 'Mixed@Case.com', password: 'password123' }));
    expect((await app.request('/auth/login', post({ email: 'mixed@case.com', password: 'password123' }))).status).toBe(200);
    expect((await app.request('/auth/login', post({ email: 'MIXED@CASE.COM', password: 'password123' }))).status).toBe(200);
  });
});
