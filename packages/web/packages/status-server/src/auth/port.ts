import type { AuthUser, TokenPrincipal } from '../storage/ports';

export type Tier = 'view' | 'admin';

/** Context variables every route can read: the coarse `tier` (back-compat with
 *  the config/reads routers), the resolved `user` (null for machine/peer,
 *  token, or AUTH_DISABLED callers), and — when the caller authenticated with an
 *  `sts_` bearer — the `token` principal (null otherwise, so `/auth/me` and later
 *  MCP can tell WHICH kind of principal is on the request). */
export type AuthVars = { tier: Tier; user: AuthUser | null; token: TokenPrincipal | null };

/** The minimal structural view of an incoming request an `AuthGate` needs — Hono's
 *  `c.req` satisfies this directly, so a Hono host never has to construct one. */
export interface AuthRequest {
  readonly path: string;
  header(name: string): string | undefined;
}

/** The host's auth port: resolves an incoming request to the {tier, user, token}
 *  context, or `null` for an ordinary unauthenticated/rejected request. A gate never
 *  throws for an unauthenticated caller and knows nothing about HTTP status codes —
 *  that translation into a 401 is the Hono binding's job (`../middleware/auth`), so a
 *  host can swap in its own gate (a different session store, an org SSO check, …)
 *  without status-server's HTTP layer changing at all. */
export interface AuthGate {
  authenticate(req: AuthRequest): Promise<AuthVars | null>;
}
