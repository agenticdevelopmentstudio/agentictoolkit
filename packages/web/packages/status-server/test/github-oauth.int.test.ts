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

function cookieVal(res: Response, name: string): string {
  const m = (res.headers.get('set-cookie') ?? '').match(new RegExp(`${name}=[^;]+`));
  if (!m) throw new Error(`no ${name} cookie`);
  return m[0];
}

function mockGithub(profile: { id: number; login: string; name: string | null; email: string | null }) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.includes('login/oauth/access_token')) return new Response(JSON.stringify({ access_token: 'gho_x' }), { status: 200 });
      if (u.endsWith('/user')) return new Response(JSON.stringify(profile), { status: 200 });
      if (u.endsWith('/user/emails')) {
        return new Response(JSON.stringify([{ email: profile.email ?? 'fallback@x.com', primary: true, verified: true }]), { status: 200 });
      }
      throw new Error(`unexpected fetch ${u}`);
    }),
  );
}

describe('GitHub OAuth', () => {
  beforeEach(() => {
    process.env.GITHUB_OAUTH_CLIENT_ID = 'cid';
    process.env.GITHUB_OAUTH_CLIENT_SECRET = 'secret';
    process.env.PUBLIC_BASE_URL = 'https://status.example.com';
    process.env.ADMIN_EMAILS = '';
    delete process.env.AUTH_DISABLED;
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('start redirects to GitHub and sets a state cookie', async () => {
    const res = await (await boot()).request('/auth/github/start');
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toContain('github.com/login/oauth/authorize');
    expect(res.headers.get('location')).toContain('redirect_uri=https%3A%2F%2Fstatus.example.com%2Fapi%2Fauth%2Fgithub%2Fcallback');
    expect(res.headers.get('set-cookie')).toContain('gh_oauth_state=');
  });

  it('callback upserts a pending user and logs them in', async () => {
    const app = await boot();
    const start = await app.request('/auth/github/start');
    const stateCookie = cookieVal(start, 'gh_oauth_state');
    const state = stateCookie.split('=')[1];
    mockGithub({ id: 42, login: 'octocat', name: 'Octo Cat', email: 'Octo@Cat.com' });
    const cb = await app.request(`/auth/github/callback?code=abc&state=${state}`, { headers: { Cookie: stateCookie } });
    expect(cb.status).toBe(302);
    expect(cb.headers.get('location')).toBe('/home');
    const me = await app.request('/auth/me', { headers: { Cookie: cookieVal(cb, 'status_auth') } });
    expect((await me.json() as { user: { email: string; role: string } | null }).user).toMatchObject({ email: 'octo@cat.com', role: 'pending' });
  });

  it('a second callback with the same GitHub id reuses the account', async () => {
    const app = await boot();
    const run = async () => {
      const start = await app.request('/auth/github/start');
      const stateCookie = cookieVal(start, 'gh_oauth_state');
      mockGithub({ id: 99, login: 'rey', name: null, email: 'rey@x.com' });
      return app.request(`/auth/github/callback?code=abc&state=${stateCookie.split('=')[1]}`, { headers: { Cookie: stateCookie } });
    };
    await run();
    await run();
    // No unique-constraint blow-up; the same email resolves to one account.
    const probe = cookieVal(await run(), 'status_auth');
    const me = await app.request('/auth/me', { headers: { Cookie: probe } });
    expect(((await me.json()) as { user: { email: string } }).user.email).toBe('rey@x.com');
  });

  it('rejects a mismatched OAuth state', async () => {
    const app = await boot();
    const stateCookie = cookieVal(await app.request('/auth/github/start'), 'gh_oauth_state');
    const cb = await app.request('/auth/github/callback?code=abc&state=WRONG', { headers: { Cookie: stateCookie } });
    expect(cb.status).toBe(400);
  });

  it('two CONCURRENT first callbacks for the same identity both log in (no unique-violation 500)', async () => {
    // The loser of the createUser race used to throw the raw unique-constraint
    // error straight to the generic 500 handler (unlike password signup, which
    // maps it). Both racers must resolve to the SAME account.
    const app = await boot();
    const s1 = cookieVal(await app.request('/auth/github/start'), 'gh_oauth_state');
    const s2 = cookieVal(await app.request('/auth/github/start'), 'gh_oauth_state');

    // Gate BOTH token exchanges so the two callbacks pass the "find existing
    // user" check before either has created the row — a deterministic race.
    let releaseGate!: () => void;
    const gate = new Promise<void>((r) => (releaseGate = r));
    let started = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) => {
        const u = String(url);
        if (u.includes('login/oauth/access_token')) {
          started++;
          await gate;
          return Response.json({ access_token: 'gho_x' });
        }
        if (u.endsWith('/user')) return Response.json({ id: 777, login: 'racer', name: 'Racer', email: 'racer@x.com' });
        if (u.endsWith('/user/emails')) return Response.json([{ email: 'racer@x.com', primary: true, verified: true }]);
        throw new Error(`unexpected fetch ${u}`);
      }),
    );

    const both = Promise.all([
      app.request(`/auth/github/callback?code=a&state=${s1.split('=')[1]}`, { headers: { Cookie: s1 } }),
      app.request(`/auth/github/callback?code=b&state=${s2.split('=')[1]}`, { headers: { Cookie: s2 } }),
    ]);
    await vi.waitFor(() => expect(started).toBe(2));
    releaseGate();
    const [r1, r2] = await both;

    expect([r1.status, r2.status]).toEqual([302, 302]);
    const me = await app.request('/auth/me', { headers: { Cookie: cookieVal(r2, 'status_auth') } });
    expect(((await me.json()) as { user: { email: string } }).user.email).toBe('racer@x.com');
  });

  it('a hung GitHub API cannot hold the pre-auth callback open — it 502s at the timeout', async () => {
    process.env.GITHUB_FETCH_TIMEOUT_MS = '60';
    try {
      const app = await boot();
      const stateCookie = cookieVal(await app.request('/auth/github/start'), 'gh_oauth_state');
      vi.stubGlobal(
        'fetch',
        vi.fn(
          (_url: string | URL, init?: RequestInit) =>
            new Promise<Response>((_resolve, reject) => {
              // Black-holed API: never answers, only honors the abort.
              init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
            }),
        ),
      );
      const t0 = Date.now();
      const cb = await app.request(`/auth/github/callback?code=abc&state=${stateCookie.split('=')[1]}`, {
        headers: { Cookie: stateCookie },
      });
      expect(cb.status).toBe(502);
      expect(Date.now() - t0).toBeLessThan(2_000);
    } finally {
      delete process.env.GITHUB_FETCH_TIMEOUT_MS;
    }
  });
});
