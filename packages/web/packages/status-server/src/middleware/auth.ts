import { createMiddleware } from 'hono/factory';
import { HTTPException } from 'hono/http-exception';
import type { Context, MiddlewareHandler } from 'hono';
import { timingSafeEqual } from 'node:crypto';
import type { StatusConfig } from '../config/port';
import type { Db } from '../libsql/client';
import { resolveSession, type AuthUser } from '../storage/auth-store';
import { readSessionCookie } from '../auth/cookie';
import { TOKEN_PREFIX, validateApiToken, type TokenPrincipal } from '../storage/token-store';

export type Tier = 'view' | 'admin';

/** Context variables every route can read: the coarse `tier` (back-compat with
 *  the config/reads routers), the resolved `user` (null for machine/peer,
 *  token, or AUTH_DISABLED callers), and — when the caller authenticated with an
 *  `sts_` bearer — the `token` principal (null otherwise, so `/auth/me` and later
 *  MCP can tell WHICH kind of principal is on the request). */
export type AuthVars = { tier: Tier; user: AuthUser | null; token: TokenPrincipal | null };

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

export function bearer(c: Context): string | undefined {
  const header = c.req.header('Authorization');
  return header?.startsWith('Bearer ') ? header.slice(7).trim() : undefined;
}

/** Authenticates the request and records {tier, user, token} on the context.
 *  Resolution order: AUTH_DISABLED (local dev) → user session cookie
 *  (viewer/admin) → `sts_` API bearer token (admin/view by the token's role) →
 *  machine PEER_TOKEN (only the `/snapshot` fleet read). Cookie stays FIRST: the
 *  status BFF forwards the session cookie VALUE as an inert `Authorization: Bearer`
 *  header, so the token branch is gated to bearers that start with `sts_` — a
 *  dashboard request resolves via its cookie and never pays a dead token lookup.
 *  `pending` users and everyone else get 401 — they have no dashboard access until
 *  an admin approves them. The old human VIEW_TOKEN/ADMIN_TOKEN paths are gone. */
export function requireAuth(db: Db, config: StatusConfig): MiddlewareHandler<{ Variables: AuthVars }> {
  return createMiddleware<{ Variables: AuthVars }>(async (c, next) => {
    if (config.authDisabled) {
      c.set('tier', 'admin');
      c.set('user', null);
      c.set('token', null);
      return next();
    }

    const user = await resolveSession(db, readSessionCookie(c));
    if (user && (user.role === 'admin' || user.role === 'viewer')) {
      c.set('tier', user.role === 'admin' ? 'admin' : 'view');
      c.set('user', user);
      c.set('token', null);
      return next();
    }

    // API bearer tokens (`sts_…`). Only attempted when the bearer carries the
    // status token prefix, so the BFF's inert cookie-as-bearer header never
    // reaches (and never fails) this lookup. An `sts_` bearer that fails to
    // validate (unknown / revoked / expired) is a hard 401 — it does NOT fall
    // through to the peer check.
    const raw = bearer(c);
    if (raw?.startsWith(TOKEN_PREFIX)) {
      const token = await validateApiToken(db, raw);
      if (!token) throw new HTTPException(401, { message: 'Unauthorized' });
      c.set('tier', token.role === 'admin' ? 'admin' : 'view');
      c.set('user', null);
      c.set('token', token);
      return next();
    }

    const peer = config.peerToken;
    if (peer && c.req.path === '/snapshot' && safeEqual(bearer(c) ?? '', peer)) {
      c.set('tier', 'view');
      c.set('user', null);
      c.set('token', null);
      return next();
    }

    throw new HTTPException(401, { message: 'Unauthorized' });
  });
}

/** Per-route guard for write/config/admin endpoints. Runs AFTER requireAuth. */
export const requireAdmin = createMiddleware<{ Variables: { tier: Tier } }>(async (c, next) => {
  if (c.get('tier') !== 'admin') throw new HTTPException(403, { message: 'Admin required' });
  return next();
});
