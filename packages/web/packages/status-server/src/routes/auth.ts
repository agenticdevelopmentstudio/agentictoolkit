import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { AuthVars } from '../middleware/auth';
import {
  findUserByEmail,
  createUser,
  createSession,
  revokeSession,
  resolveSession,
  roleForEmail,
  toAuthUser,
  isUniqueViolation,
} from '../storage/auth-store';
import { hashPassword, verifyPassword, DUMMY_PASSWORD_HASH } from '../auth/password';
import { setSessionCookie, clearSessionCookie, readSessionCookie } from '../auth/cookie';
import { githubRoutes } from '../auth/github';
import { rateLimit } from '../middleware/rate-limit';
import { bearer } from '../middleware/auth';
import { TOKEN_PREFIX, validateApiToken, revokeApiToken } from '../storage/token-store';

export const signupBody = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  // The shared SignupCard has no name field and posts displayName: "" — accept
  // empty/absent and fall back to the email in the handler (no spurious 400).
  displayName: z.string().optional(),
});
export const loginBody = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

async function readJson(c: { req: { json: () => Promise<unknown> } }): Promise<unknown> {
  try {
    return await c.req.json();
  } catch {
    throw new HTTPException(400, { message: 'Invalid JSON' });
  }
}

function parse<T>(result: { success: true; data: T } | { success: false }): T {
  if (!result.success) throw new HTTPException(400, { message: 'Invalid request body' });
  return result.data;
}

/**
 * PUBLIC auth routes — they sit BEFORE the requireAuth seam (they mint the very
 * session that seam checks). The session lives in the httpOnly `status_auth`
 * cookie; the browser reaches these through the Next BFF, which forwards both the
 * cookie and 302 Location verbatim.
 */
export function authRoutes(db: Db, config: StatusConfig): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  // Per-IP ceilings on the two credential routes: unauthenticated, and each
  // attempt costs a bcrypt run on the API thread — brute force is also a CPU
  // attack without these. /auth/me stays unlimited (the header probes it).
  app.use('/auth/login', rateLimit({ max: 10 }));
  app.use('/auth/signup', rateLimit({ max: 5 }));

  app.post('/auth/signup', async (c) => {
    const { email, password, displayName } = parse(signupBody.safeParse(await readJson(c)));
    const normalized = email.toLowerCase();
    if (await findUserByEmail(db, normalized)) {
      throw new HTTPException(409, { message: 'An account with this email already exists' });
    }
    const passwordHash = await hashPassword(password);
    let user;
    try {
      user = await createUser(db, {
        email: normalized,
        displayName: displayName?.trim() || normalized,
        role: roleForEmail(normalized, config),
        passwordHash,
      });
    } catch (err) {
      // A concurrent signup for the same email can pass the check above and lose
      // the insert race — surface it as 409, not an opaque 500.
      if (isUniqueViolation(err)) throw new HTTPException(409, { message: 'An account with this email already exists' });
      throw err;
    }
    setSessionCookie(c, await createSession(db, user.id), config);
    return c.json({ user: toAuthUser(user) }, 201);
  });

  app.post('/auth/login', async (c) => {
    const { email, password } = parse(loginBody.safeParse(await readJson(c)));
    const user = await findUserByEmail(db, email);
    // Always run bcrypt (against a dummy hash when there's no real one) so the
    // response time can't distinguish "unknown email" from "wrong password".
    const ok = await verifyPassword(password, user?.passwordHash ?? DUMMY_PASSWORD_HASH);
    if (!user || !user.passwordHash || !ok) {
      throw new HTTPException(401, { message: 'Invalid email or password' });
    }
    setSessionCookie(c, await createSession(db, user.id), config);
    return c.json({ user: toAuthUser(user) });
  });

  app.post('/auth/logout', async (c) => {
    // A CLI/device caller logs out by revoking its own bearer token (no cookie
    // to clear). Cookie logout is unchanged — always revoke + clear the session.
    const raw = bearer(c);
    if (raw?.startsWith(TOKEN_PREFIX)) {
      const token = await validateApiToken(db, raw);
      if (token) await revokeApiToken(db, token.id);
    }
    await revokeSession(db, readSessionCookie(c));
    clearSessionCookie(c);
    return c.json({ ok: true });
  });

  // Never 401 — the public landing + header probe this to learn "are you signed in?".
  // This route sits BEFORE the requireAuth seam, so a bearer token isn't yet
  // resolved on the context — validate it inline to answer for a token principal.
  app.get('/auth/me', async (c) => {
    const user = await resolveSession(db, readSessionCookie(c));
    if (!user) {
      const raw = bearer(c);
      if (raw?.startsWith(TOKEN_PREFIX)) {
        const token = await validateApiToken(db, raw);
        if (token) {
          return c.json({
            principal: { kind: 'token' as const, role: token.role, name: token.name, expiresAt: token.expiresAt },
          });
        }
      }
    }
    return c.json({ user });
  });

  // GitHub OAuth start + callback (also public).
  app.route('/', githubRoutes(db, config));

  return app;
}
