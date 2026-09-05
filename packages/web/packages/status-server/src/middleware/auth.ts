import { createMiddleware } from 'hono/factory';
import { HTTPException } from 'hono/http-exception';
import type { Context, MiddlewareHandler } from 'hono';
import type { AuthGate, AuthVars, Tier } from '../auth/port';

export type { Tier, AuthVars } from '../auth/port';

export function bearer(c: Context): string | undefined {
  const header = c.req.header('Authorization');
  return header?.startsWith('Bearer ') ? header.slice(7).trim() : undefined;
}

/** Thin Hono binding for the host's `AuthGate` (`../auth/port`): resolves the
 *  request through the gate and records {tier, user, token} on the context, or
 *  turns a `null` resolution into the 401 every route downstream expects. All
 *  authentication MECHANISM lives in the gate (the default one is
 *  `../auth/default-adapter`) — this function only translates gate → HTTP. */
export function requireAuth(gate: AuthGate): MiddlewareHandler<{ Variables: AuthVars }> {
  return createMiddleware<{ Variables: AuthVars }>(async (c, next) => {
    const resolved = await gate.authenticate(c.req);
    if (!resolved) throw new HTTPException(401, { message: 'Unauthorized' });
    c.set('tier', resolved.tier);
    c.set('user', resolved.user);
    c.set('token', resolved.token);
    return next();
  });
}

/** Per-route guard for write/config/admin endpoints. Runs AFTER requireAuth. */
export const requireAdmin = createMiddleware<{ Variables: { tier: Tier } }>(async (c, next) => {
  if (c.get('tier') !== 'admin') throw new HTTPException(403, { message: 'Admin required' });
  return next();
});
