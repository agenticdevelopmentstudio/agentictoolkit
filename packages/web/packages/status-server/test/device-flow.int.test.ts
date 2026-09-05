import { describe, it, expect, beforeEach } from 'vitest';
import { createApp } from '../src/app';
import { sessionHeaders } from './helpers/auth';
import { freshDb } from './helpers/db';
import { deviceAuthorizations } from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import { testConfig } from './helpers/config';

type App = ReturnType<typeof createApp>;

function json(body: unknown): { headers: Record<string, string>; body: string } {
  return { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

/** POST /auth/device (public) → the grant's codes. */
async function request(app: App, label?: string): Promise<{ device_code: string; user_code: string; verification_uri: string; interval: number; expires_in: number }> {
  const res = await app.request('/auth/device', { method: 'POST', ...json(label ? { label } : {}) });
  expect(res.status).toBe(201);
  return res.json() as Promise<{ device_code: string; user_code: string; verification_uri: string; interval: number; expires_in: number }>;
}

/** POST /auth/device/token (public) → the poll body. */
async function poll(app: App, deviceCode: string): Promise<Record<string, unknown>> {
  const res = await app.request('/auth/device/token', { method: 'POST', ...json({ device_code: deviceCode }) });
  expect(res.status).toBe(200);
  return res.json() as Promise<Record<string, unknown>>;
}

async function approve(app: App, cookie: string, userCode: string): Promise<Response> {
  return app.request('/auth/device/approve', {
    method: 'POST',
    headers: { Cookie: cookie, 'Content-Type': 'application/json' },
    body: JSON.stringify({ user_code: userCode }),
  });
}

async function setup(): Promise<{ app: App; db: Db; viewer: string; admin: string }> {
  const db = await freshDb();
  const app = createApp({ db, config: testConfig() });
  const viewer = (await sessionHeaders(db, 'viewer')).Cookie;
  const admin = (await sessionHeaders(db, 'admin')).Cookie;
  return { app, db, viewer, admin };
}

describe('device flow — RFC 8628-shaped CLI authorization', () => {
  beforeEach(() => {
    delete process.env.AUTH_DISABLED;
    delete process.env.PEER_TOKEN;
  });

  it('happy path: request → pending → approve (viewer) → poll returns a user token that authenticates; second poll is single-use', async () => {
    const { app, viewer } = await setup();
    const grant = await request(app, 'my-cli');
    expect(grant.device_code).toMatch(/^[0-9a-f]{64}$/);
    expect(grant.user_code).toMatch(/^[BCDFGHJKLMNPQRSTVWXZ23456789]{4}-[BCDFGHJKLMNPQRSTVWXZ23456789]{4}$/);
    expect(grant.interval).toBe(5);
    expect(grant.expires_in).toBe(900);
    expect(grant.verification_uri.endsWith(`/device?code=${grant.user_code}`)).toBe(true);

    // Before approval, the CLI is told to keep waiting.
    expect(await poll(app, grant.device_code)).toEqual({ error: 'authorization_pending' });

    // A signed-in viewer approves — mints a `user`-role token.
    const ap = await approve(app, viewer, grant.user_code);
    expect(ap.status).toBe(200);
    expect(await ap.json()).toEqual({ status: 'approved' });

    // The next poll hands back the token exactly once.
    const got = await poll(app, grant.device_code);
    expect(typeof got.token).toBe('string');
    expect((got.token as string).startsWith('sts_')).toBe(true);
    expect(got.role).toBe('user');
    expect(typeof got.expires_at).toBe('string');

    // The token authenticates a viewer route (200) but not an admin one (403).
    const bearer = { Authorization: `Bearer ${got.token as string}` };
    expect((await app.request('/fleet', { headers: bearer })).status).toBe(200);
    expect((await app.request('/users', { headers: bearer })).status).toBe(403);

    // Single-use: the grant row is consumed, so a second poll yields nothing.
    expect(await poll(app, grant.device_code)).toEqual({ error: 'expired' });
  });

  it('an admin approver mints an admin-role token', async () => {
    const { app, admin } = await setup();
    const grant = await request(app);
    expect((await approve(app, admin, grant.user_code)).status).toBe(200);
    const got = await poll(app, grant.device_code);
    expect(got.role).toBe('admin');
    // An admin token passes requireAdmin.
    expect((await app.request('/users', { headers: { Authorization: `Bearer ${got.token as string}` } })).status).toBe(200);
  });

  it('deny → the poll returns `denied`', async () => {
    const { app, viewer } = await setup();
    const grant = await request(app);
    const res = await app.request('/auth/device/deny', {
      method: 'POST',
      headers: { Cookie: viewer, 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_code: grant.user_code }),
    });
    expect(res.status).toBe(200);
    expect(await poll(app, grant.device_code)).toEqual({ error: 'denied' });
    // Denied grants are single-use too — the poll consumed the row.
    expect(await poll(app, grant.device_code)).toEqual({ error: 'expired' });
  });

  it('an expired grant polls `expired`', async () => {
    const { app, db } = await setup();
    const grant = await request(app);
    // Backdate the grant past its TTL.
    await db.update(deviceAuthorizations).set({ expiresAt: new Date(Date.now() - 1000) });
    expect(await poll(app, grant.device_code)).toEqual({ error: 'expired' });
  });

  it('polling faster than the interval returns `slow_down`', async () => {
    const { app } = await setup();
    const grant = await request(app);
    expect(await poll(app, grant.device_code)).toEqual({ error: 'authorization_pending' });
    // Immediate re-poll (< 5s since the last accepted poll).
    expect(await poll(app, grant.device_code)).toEqual({ error: 'slow_down' });
  });

  it('an unknown device_code polls `expired`', async () => {
    const { app } = await setup();
    expect(await poll(app, 'deadbeef'.repeat(8))).toEqual({ error: 'expired' });
  });

  it('approval requires a signed-in user: an AUTH_DISABLED principal is 403', async () => {
    process.env.AUTH_DISABLED = '1';
    const db = await freshDb();
    const app = createApp({ db, config: testConfig() });
    const grant = await request(app);
    // No cookie → AUTH_DISABLED admits the request but c.get('user') is null.
    const res = await app.request('/auth/device/approve', { method: 'POST', ...json({ user_code: grant.user_code }) });
    expect(res.status).toBe(403);
    // The grant is untouched — still pending.
    expect(await poll(app, grant.device_code)).toEqual({ error: 'authorization_pending' });
  });

  it('a device (token) principal cannot approve — approval is session-only (403)', async () => {
    const { app, admin } = await setup();
    // Mint an admin API token via the real route, then try to approve WITH it.
    const mintRes = await app.request('/tokens', {
      method: 'POST',
      headers: { Cookie: admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'ci', role: 'admin' }),
    });
    const { token } = (await mintRes.json()) as { token: string };
    const grant = await request(app);
    const res = await app.request('/auth/device/approve', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_code: grant.user_code }),
    });
    expect(res.status).toBe(403);
  });

  it('user_code is single-use: approving twice is 409, and the losing approval leaves no orphaned token', async () => {
    const { app, viewer, admin } = await setup();
    const grant = await request(app);
    expect((await approve(app, viewer, grant.user_code)).status).toBe(200);
    // A second approval (even by a different signed-in user) is rejected.
    expect((await approve(app, admin, grant.user_code)).status).toBe(409);
    // The losing approval minted-then-discarded its own token — it must not
    // litter the table alongside the winner's.
    const list = await app.request('/tokens', { headers: { Cookie: admin } });
    const tokens = (await list.json()) as Array<Record<string, unknown>>;
    expect(tokens.filter((t) => t.kind === 'device').length).toBe(1);
  });

  it('GET /auth/device/pending shows the request to a signed-in approver; 404 for an unknown code', async () => {
    const { app, viewer } = await setup();
    const grant = await request(app, 'my laptop');
    const res = await app.request(`/auth/device/pending?user_code=${grant.user_code}`, { headers: { Cookie: viewer } });
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.label).toBe('my laptop');
    expect(body.status).toBe('pending');
    expect(typeof body.expiresAt).toBe('string');

    const missing = await app.request('/auth/device/pending?user_code=ZZZZ-ZZZZ', { headers: { Cookie: viewer } });
    expect(missing.status).toBe(404);
  });

  it('GET /auth/device/pending reports an already-handled grant as non-pending', async () => {
    const { app, viewer } = await setup();
    const grant = await request(app);
    expect((await approve(app, viewer, grant.user_code)).status).toBe(200);
    const res = await app.request(`/auth/device/pending?user_code=${grant.user_code}`, { headers: { Cookie: viewer } });
    expect(res.status).toBe(200);
    expect((await res.json() as Record<string, unknown>).status).toBe('approved');
  });

  it('the approval trio is not admin-gated: a viewer session may approve', async () => {
    // (covered by the happy path, but assert the negative: no cookie → not 200)
    const { app } = await setup();
    const grant = await request(app);
    const res = await app.request('/auth/device/approve', { method: 'POST', ...json({ user_code: grant.user_code }) });
    // Post-seam with no session cookie and auth ENABLED → requireAuth 401s first.
    expect(res.status).toBe(401);
  });

  it('the token is stored hashed only — the raw secret never appears in a token listing', async () => {
    const { app, admin, viewer } = await setup();
    const grant = await request(app);
    expect((await approve(app, viewer, grant.user_code)).status).toBe(200);
    const got = await poll(app, grant.device_code);
    const list = await app.request('/tokens', { headers: { Cookie: admin } });
    const tokens = (await list.json()) as Array<Record<string, unknown>>;
    // The device token is listed (kind 'device') but its raw value is nowhere.
    expect(tokens.some((t) => t.kind === 'device')).toBe(true);
    expect(JSON.stringify(tokens)).not.toContain(got.token as string);
  });

  it('the request route is rate-limited at max 10/window', async () => {
    const { app } = await setup();
    const ip = { 'x-forwarded-for': '203.0.113.55', 'Content-Type': 'application/json' };
    for (let i = 0; i < 10; i++) {
      const res = await app.request('/auth/device', { method: 'POST', headers: ip, body: JSON.stringify({}) });
      expect(res.status).toBe(201);
    }
    const blocked = await app.request('/auth/device', { method: 'POST', headers: ip, body: JSON.stringify({}) });
    expect(blocked.status).toBe(429);
  });

  it('the poll route has its own budget (max 30/window) with headroom over the 12/min cadence', async () => {
    const { app } = await setup();
    const ip = { 'x-forwarded-for': '198.51.100.77', 'Content-Type': 'application/json' };
    const poll = () =>
      app.request('/auth/device/token', {
        method: 'POST',
        headers: ip,
        body: JSON.stringify({ device_code: 'deadbeef' }),
      });
    // The poll budget is independent of the request budget and higher: a compliant
    // 12/min poller must never 429, so it clears past 10 (the request-route ceiling).
    for (let i = 0; i < 30; i++) {
      const res = await poll();
      expect(res.status).toBe(200);
    }
    const blocked = await poll();
    expect(blocked.status).toBe(429);
  });
});
