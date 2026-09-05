import { describe, it, expect, beforeEach } from 'vitest';
import { createApp } from '../src/app';
import { sessionHeaders } from './helpers/auth';
import { freshDb } from './helpers/db';
import { TOKEN_PREFIX } from '../src/storage/token-store';
import { testConfig } from './helpers/config';

type App = ReturnType<typeof createApp>;

function bearer(raw: string): { Authorization: string } {
  return { Authorization: `Bearer ${raw}` };
}

/** Boot a fresh in-memory app plus an admin SESSION cookie (the only principal
 *  allowed to mint). */
async function setup(): Promise<{ app: App; admin: string; db: Awaited<ReturnType<typeof freshDb>> }> {
  const db = await freshDb();
  const app = createApp({ db, config: testConfig() });
  const admin = (await sessionHeaders(db, 'admin')).Cookie;
  return { app, admin, db };
}

/** Mint a token through the REAL route (POST /tokens) as an admin session, and
 *  return its id + the raw secret (shown exactly once). */
async function mint(
  app: App,
  admin: string,
  role: 'admin' | 'user',
  expiresAt?: string,
): Promise<{ id: string; token: string }> {
  const res = await app.request('/tokens', {
    method: 'POST',
    headers: { Cookie: admin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: `t-${role}`, role, ...(expiresAt ? { expiresAt } : {}) }),
  });
  if (res.status !== 201) throw new Error(`mint failed: ${res.status}`);
  return (await res.json()) as { id: string; token: string };
}

describe('api_tokens — sts_ bearer tokens on the tier seam', () => {
  beforeEach(() => {
    delete process.env.AUTH_DISABLED;
    delete process.env.PEER_TOKEN;
  });

  it('an admin session mints a token: 201 + no-store, sts_ raw shown once, never in the list', async () => {
    const { app, admin } = await setup();
    const res = await app.request('/tokens', {
      method: 'POST',
      headers: { Cookie: admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'ci', role: 'user' }),
    });
    expect(res.status).toBe(201);
    expect(res.headers.get('cache-control')).toBe('no-store');
    const body = (await res.json()) as Record<string, unknown> & { id: string; token: string };
    expect(typeof body.token).toBe('string');
    expect(body.token.startsWith(TOKEN_PREFIX)).toBe(true);
    expect(body.role).toBe('user');
    expect(body.prefix).toBe(body.token.slice(0, 12));
    // The persisted hash is never handed back, even at mint.
    expect(body.tokenHash).toBeUndefined();

    const list = await app.request('/tokens', { headers: { Cookie: admin } });
    expect(list.status).toBe(200);
    expect(list.headers.get('cache-control')).toBe('no-store');
    const tokens = (await list.json()) as Array<Record<string, unknown>>;
    expect(tokens).toHaveLength(1);
    expect(tokens[0].id).toBe(body.id);
    expect(tokens[0].token).toBeUndefined();
    expect(tokens[0].tokenHash).toBeUndefined();
    // Belt-and-braces: the raw secret must appear NOWHERE in the metadata list.
    expect(JSON.stringify(tokens)).not.toContain(body.token);
  });

  it('a user token authenticates a viewer route (200) but is refused an admin route (403)', async () => {
    const { app, admin } = await setup();
    const { token } = await mint(app, admin, 'user');
    expect((await app.request('/fleet', { headers: bearer(token) })).status).toBe(200);
    expect((await app.request('/users', { headers: bearer(token) })).status).toBe(403);
  });

  it('an admin token passes requireAdmin (GET /users → 200)', async () => {
    const { app, admin } = await setup();
    const { token } = await mint(app, admin, 'admin');
    expect((await app.request('/users', { headers: bearer(token) })).status).toBe(200);
  });

  it('an admin revokes a token → its next use is 401', async () => {
    const { app, admin } = await setup();
    const { id, token } = await mint(app, admin, 'user');
    expect((await app.request('/fleet', { headers: bearer(token) })).status).toBe(200);
    const del = await app.request(`/tokens/${id}`, { method: 'DELETE', headers: { Cookie: admin } });
    expect(del.status).toBe(204);
    expect((await app.request('/fleet', { headers: bearer(token) })).status).toBe(401);
  });

  it('an expired token is 401', async () => {
    const { app, admin } = await setup();
    const { token } = await mint(app, admin, 'user', new Date(Date.now() - 60_000).toISOString());
    expect((await app.request('/fleet', { headers: bearer(token) })).status).toBe(401);
  });

  it('a token may revoke ITSELF with its own bearer, but not another token', async () => {
    const { app, admin } = await setup();
    const a = await mint(app, admin, 'user');
    const b = await mint(app, admin, 'user');
    // A user token cannot revoke a DIFFERENT token (not admin, not self).
    expect(
      (await app.request(`/tokens/${b.id}`, { method: 'DELETE', headers: bearer(a.token) })).status,
    ).toBe(403);
    // ...but it can revoke itself.
    const self = await app.request(`/tokens/${a.id}`, { method: 'DELETE', headers: bearer(a.token) });
    expect(self.status).toBe(204);
    expect((await app.request('/fleet', { headers: bearer(a.token) })).status).toBe(401);
  });

  it('DELETE /tokens/:id 404s an unknown id (for an admin)', async () => {
    const { app, admin } = await setup();
    expect(
      (await app.request('/tokens/nope', { method: 'DELETE', headers: { Cookie: admin } })).status,
    ).toBe(404);
  });

  it('/auth/me answers the token principal shape for an sts_ bearer', async () => {
    const { app, admin } = await setup();
    const { token } = await mint(app, admin, 'admin');
    const me = await app.request('/auth/me', { headers: bearer(token) });
    expect(me.status).toBe(200);
    const body = (await me.json()) as { user?: unknown; principal?: unknown };
    expect(body.user).toBeUndefined();
    expect(body.principal).toEqual({ kind: 'token', role: 'admin', name: 't-admin', expiresAt: null });
  });

  it('/auth/me never 401s — an unknown sts_ bearer falls back to { user: null }', async () => {
    const { app } = await setup();
    const me = await app.request('/auth/me', { headers: bearer('sts_unknowntoken') });
    expect(me.status).toBe(200);
    expect(await me.json()).toEqual({ user: null });
  });

  it('POST /auth/logout revokes the bearer token (CLI logout)', async () => {
    const { app, admin } = await setup();
    const { token } = await mint(app, admin, 'user');
    const out = await app.request('/auth/logout', { method: 'POST', headers: bearer(token) });
    expect(out.status).toBe(200);
    expect((await app.request('/fleet', { headers: bearer(token) })).status).toBe(401);
  });

  it('minting under AUTH_DISABLED is 403 — a non-session principal has no honest created_by', async () => {
    process.env.AUTH_DISABLED = '1';
    const db = await freshDb();
    const app = createApp({ db, config: testConfig() });
    const res = await app.request('/tokens', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'x', role: 'user' }),
    });
    expect(res.status).toBe(403);
  });

  it('an admin token cannot mint another token (tokens cannot mint tokens → 403)', async () => {
    const { app, admin } = await setup();
    const { token } = await mint(app, admin, 'admin');
    const res = await app.request('/tokens', {
      method: 'POST',
      headers: { ...bearer(token), 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'child', role: 'user' }),
    });
    expect(res.status).toBe(403);
  });

  it('a garbage or unknown bearer is 401 on a gated route', async () => {
    const { app } = await setup();
    // Unknown sts_ token → the bearer branch validates, fails, and hard-401s.
    expect((await app.request('/fleet', { headers: bearer('sts_deadbeef') })).status).toBe(401);
    // A non-sts_ bearer is NOT treated as a token; with no peer configured it 401s too.
    expect((await app.request('/fleet', { headers: bearer('randomjunk') })).status).toBe(401);
  });

  it('a session cookie forwarded as an inert Bearer header still authenticates via the cookie', async () => {
    const { app, admin } = await setup();
    // The status BFF forwards the session cookie VALUE as `Authorization: Bearer <value>`.
    // That value is a 64-hex session token (no sts_ prefix), so the token branch is
    // skipped and the cookie resolves the admin — the request must not break.
    const cookieValue = admin.split('=')[1];
    const res = await app.request('/users', {
      headers: { Cookie: admin, ...bearer(cookieValue) },
    });
    expect(res.status).toBe(200);
  });
});
