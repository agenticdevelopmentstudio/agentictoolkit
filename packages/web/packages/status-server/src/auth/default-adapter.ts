import { parse } from 'hono/utils/cookie';
import { timingSafeEqual } from 'node:crypto';
import type { StatusConfig } from '../config/port';
import type { Storage } from '../storage/ports';
import { TOKEN_PREFIX } from '../storage/ports';
import { SESSION_COOKIE } from './cookie';
import type { AuthGate, AuthRequest, AuthVars } from './port';

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

function bearerOf(req: AuthRequest): string | undefined {
  const header = req.header('Authorization');
  return header?.startsWith('Bearer ') ? header.slice(7).trim() : undefined;
}

function sessionTokenOf(req: AuthRequest): string | undefined {
  const cookieHeader = req.header('Cookie');
  return cookieHeader ? parse(cookieHeader)[SESSION_COOKIE] : undefined;
}

/** The default `AuthGate`: session cookie, `sts_` API bearer tokens, PEER_TOKEN and
 *  AUTH_DISABLED against this package's own libsql-backed `Storage`. `websites/main`
 *  wires this in today; a host that wants a different mechanism (its own SSO, a
 *  different session store, …) implements `AuthGate` directly and never touches this
 *  file.
 *
 *  Resolution order: AUTH_DISABLED (local dev) → user session cookie
 *  (viewer/admin) → `sts_` API bearer token (admin/view by the token's role) →
 *  machine PEER_TOKEN (only the `/snapshot` fleet read). Cookie stays FIRST: the
 *  status BFF forwards the session cookie VALUE as an inert `Authorization: Bearer`
 *  header, so the token branch is gated to bearers that start with `sts_` — a
 *  dashboard request resolves via its cookie and never pays a dead token lookup.
 *  `pending` users and everyone else resolve to `null` (the Hono binding turns that
 *  into 401) — they have no dashboard access until an admin approves them. The old
 *  human VIEW_TOKEN/ADMIN_TOKEN paths are gone. */
export function createDefaultAuthGate(storage: Storage, config: StatusConfig): AuthGate {
  return {
    async authenticate(req: AuthRequest): Promise<AuthVars | null> {
      if (config.authDisabled) {
        return { tier: 'admin', user: null, token: null };
      }

      const user = await storage.auth.resolveSession(sessionTokenOf(req));
      if (user && (user.role === 'admin' || user.role === 'viewer')) {
        return { tier: user.role === 'admin' ? 'admin' : 'view', user, token: null };
      }

      // API bearer tokens (`sts_…`). Only attempted when the bearer carries the
      // status token prefix, so the BFF's inert cookie-as-bearer header never
      // reaches (and never fails) this lookup. An `sts_` bearer that fails to
      // validate (unknown / revoked / expired) resolves to `null` — it does NOT
      // fall through to the peer check.
      const raw = bearerOf(req);
      if (raw?.startsWith(TOKEN_PREFIX)) {
        const token = await storage.tokens.validateApiToken(raw);
        return token ? { tier: token.role === 'admin' ? 'admin' : 'view', user: null, token } : null;
      }

      const peer = config.peerToken;
      if (peer && req.path === '/snapshot' && safeEqual(bearerOf(req) ?? '', peer)) {
        return { tier: 'view', user: null, token: null };
      }

      return null;
    },
  };
}
