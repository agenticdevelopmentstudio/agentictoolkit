import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { StatusConfig } from '../config/port';
import type { AuthVars } from '../middleware/auth';
import type { Storage } from '../storage/ports';
import { roleForEmail, toAuthUser, isUniqueViolation, TOKEN_PREFIX } from '../storage/ports';
import { hashPassword, verifyPassword, DUMMY_PASSWORD_HASH } from '../auth/password';
import { setSessionCookie, clearSessionCookie, readSessionCookie } from '../auth/cookie';
import { githubRoutes } from '../auth/github';
import { rateLimit } from '../middleware/rate-limit';
import { bearer } from '../middleware/auth';

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
export function authRoutes(storage: Storage, config: StatusConfig): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  // Per-IP ceilings on the two credential routes: unauthenticated, and each
  // attempt costs a bcrypt run on the API thread — brute force is also a CPU
  // attack without these. /auth/me stays unlimited (the header probes it).
  app.use('/auth/login', rateLimit({ max: 10 }));
  app.use('/auth/signup', rateLimit({ max: 5 }));

  app.post('/auth/signup', async (c) => {
    const { email, password, displayName } = parse(signupBody.safeParse(await readJson(c)));
    const normalized = email.toLowerCase();
    if (await storage.auth.findUserByEmail(normalized)) {
      throw new HTTPException(409, { message: 'An account with this email already exists' });
    }
    const passwordHash = await hashPassword(password);
    let user;
    try {
      user = await storage.auth.createUser({
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
    setSessionCookie(c, await storage.auth.createSession(user.id), config);
    return c.json({ user: toAuthUser(user) }, 201);
  });

  app.post('/auth/login', async (c) => {
    const { email, password } = parse(loginBody.safeParse(await readJson(c)));
    const user = await storage.auth.findUserByEmail(email);
    // Always run bcrypt (against a dummy hash when there's no real one) so the
    // response time can't distinguish "unknown email" from "wrong password".
    const ok = await verifyPassword(password, user?.passwordHash ?? DUMMY_PASSWORD_HASH);
    if (!user || !user.passwordHash || !ok) {
      throw new HTTPException(401, { message: 'Invalid email or password' });
    }
    setSessionCookie(c, await storage.auth.createSession(user.id), config);
    return c.json({ user: toAuthUser(user) });
  });

  app.post('/auth/logout', async (c) => {
    // A CLI/device caller logs out by revoking its own bearer token (no cookie
    // to clear). Cookie logout is unchanged — always revoke + clear the session.
    const raw = bearer(c);
    if (raw?.startsWith(TOKEN_PREFIX)) {
      const token = await storage.tokens.validateApiToken(raw);
      if (token) await storage.tokens.revokeApiToken(token.id);
    }
    await storage.auth.revokeSession(readSessionCookie(c));
    clearSessionCookie(c);
    return c.json({ ok: true });
  });

  // Never 401 — the public landing + header probe this to learn "are you signed in?".
  // This route sits BEFORE the requireAuth seam, so a bearer token isn't yet
  // resolved on the context — validate it inline to answer for a token principal.
  app.get('/auth/me', async (c) => {
    const user = await storage.auth.resolveSession(readSessionCookie(c));
    if (!user) {
      const raw = bearer(c);
      if (raw?.startsWith(TOKEN_PREFIX)) {
        const token = await storage.tokens.validateApiToken(raw);
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
  app.route('/', githubRoutes(storage, config));

  return app;
}
