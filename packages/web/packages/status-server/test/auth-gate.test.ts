import { describe, it, expect } from 'vitest';
import { Hono } from 'hono';
import { requireAuth, type AuthVars } from '../src/middleware/auth';
import type { AuthGate } from '../src/auth/port';

// Proves the port is host-implementable: a hand-written `AuthGate` that never
// touches `Storage` or `StatusConfig` — just an incoming header — still plugs
// into `requireAuth` and the app's 401 behaviour unchanged.
const headerGate: AuthGate = {
  async authenticate(req) {
    return req.header('X-Test-User') === 'admin' ? { tier: 'admin', user: null, token: null } : null;
  },
};

function appWith(gate: AuthGate) {
  const app = new Hono<{ Variables: AuthVars }>();
  app.use('*', requireAuth(gate));
  app.get('/read', (c) => c.json({ ok: true }));
  return app;
}

describe('AuthGate (host-implementable port)', () => {
  it('grants 200 when the gate resolves the request', async () => {
    const res = await appWith(headerGate).request('/read', { headers: { 'X-Test-User': 'admin' } });
    expect(res.status).toBe(200);
  });

  it('rejects with 401 when the gate resolves to null', async () => {
    const res = await appWith(headerGate).request('/read');
    expect(res.status).toBe(401);
  });
});
