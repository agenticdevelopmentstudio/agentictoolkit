import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { getCookie, setCookie, deleteCookie } from 'hono/cookie';
import { randomBytes } from 'node:crypto';
import type { Db } from '../libsql/client';
import type { AuthVars } from '../middleware/auth';
import type { StatusConfig } from '../config/port';
import {
  findUserByGithubId,
  findUserByEmail,
  attachGithubId,
  createUser,
  createSession,
  roleForEmail,
  isUniqueViolation,
} from '../storage/auth-store';
import type { User } from '../libsql/schema';
import { setSessionCookie } from './cookie';

const STATE_COOKIE = 'gh_oauth_state';

/** fetch with the GitHub deadline — the only outbound fetches on a PRE-AUTH
 *  request path; un-deadlined, a hung GitHub API held the callback open for as
 *  long as the socket survived. `config.github.fetchTimeoutMs` (test-tunable);
 *  null keeps this default. */
async function ghFetch(url: string, init: RequestInit, config: StatusConfig): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(config.github.fetchTimeoutMs ?? 8_000) });
  } catch {
    throw new HTTPException(502, { message: 'GitHub is unreachable' });
  }
}

interface GithubProfile {
  githubId: string;
  email: string | null;
  displayName: string;
}

function authorizeUrl(state: string, config: StatusConfig): string {
  const params = new URLSearchParams({
    client_id: config.github.clientId,
    redirect_uri: `${config.publicBaseUrl}/api/auth/github/callback`,
    scope: 'read:user user:email',
    state,
    allow_signup: 'true',
  });
  return `https://github.com/login/oauth/authorize?${params.toString()}`;
}

/** Exchange the OAuth `code` for the GitHub identity (server-side; the secret
 *  never touches the browser). Falls back to /user/emails for the primary
 *  verified address when the profile email is private. */
async function exchangeCode(code: string, config: StatusConfig): Promise<GithubProfile> {
  const tokenRes = await ghFetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      client_id: config.github.clientId,
      client_secret: config.github.clientSecret,
      code,
    }),
  }, config);
  if (!tokenRes.ok) throw new HTTPException(502, { message: 'GitHub token exchange failed' });
  const token = ((await tokenRes.json()) as { access_token?: string }).access_token;
  if (!token) throw new HTTPException(401, { message: 'GitHub authorization failed' });

  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'User-Agent': 'status-backend',
  };
  // Check status BEFORE parsing: a non-200 body (revoked token, 403 rate-limit,
  // outage) is an error object, not a profile — trusting it would yield
  // id=undefined → githubId='undefined' and fuse every failed login into one row.
  const userRes = await ghFetch('https://api.github.com/user', { headers }, config);
  if (!userRes.ok) throw new HTTPException(502, { message: 'Could not read the GitHub profile' });
  const ghUser = (await userRes.json()) as { id?: number; login?: string; name: string | null; email: string | null };
  if (typeof ghUser.id !== 'number' || !Number.isFinite(ghUser.id)) {
    throw new HTTPException(502, { message: 'GitHub profile is missing an id' });
  }

  // Only ever adopt a PRIMARY + VERIFIED address (account-linking keys on email).
  let email = ghUser.email;
  if (!email) {
    const emailsRes = await ghFetch('https://api.github.com/user/emails', { headers }, config);
    if (emailsRes.ok) {
      const emails = (await emailsRes.json()) as { email: string; primary: boolean; verified: boolean }[];
      email = emails.find((e) => e.primary && e.verified)?.email ?? null;
    }
  }

  return {
    githubId: String(ghUser.id),
    email: email ? email.toLowerCase() : null,
    displayName: ghUser.name || ghUser.login || 'GitHub user',
  };
}

export function githubRoutes(db: Db, config: StatusConfig): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  app.get('/auth/github/start', (c) => {
    // Both are required: without publicBaseUrl the redirect_uri is relative and
    // GitHub rejects it, so fail fast here rather than bounce the user to a
    // GitHub error page with no recovery.
    if (!config.github.clientId || !config.publicBaseUrl) {
      throw new HTTPException(500, { message: 'GitHub login is not configured' });
    }
    const state = randomBytes(16).toString('hex');
    setCookie(c, STATE_COOKIE, state, { httpOnly: true, secure: config.cookieSecure, sameSite: 'Lax', path: '/', maxAge: 600 });
    return c.redirect(authorizeUrl(state, config));
  });

  app.get('/auth/github/callback', async (c) => {
    const code = c.req.query('code');
    const state = c.req.query('state');
    const expected = getCookie(c, STATE_COOKIE);
    deleteCookie(c, STATE_COOKIE, { path: '/' });
    if (!code || !state || !expected || state !== expected) {
      throw new HTTPException(400, { message: 'Invalid OAuth state' });
    }

    const profile = await exchangeCode(code, config);
    let user: User | undefined = await findUserByGithubId(db, profile.githubId);
    if (!user) {
      const existing = profile.email ? await findUserByEmail(db, profile.email) : undefined;
      try {
        if (existing) {
          user = (await attachGithubId(db, existing.id, profile.githubId)) ?? existing;
        } else {
          user = await createUser(db, {
            email: profile.email ?? `gh_${profile.githubId}@users.noreply.github.com`,
            displayName: profile.displayName,
            role: profile.email ? roleForEmail(profile.email, config) : 'pending',
            githubId: profile.githubId,
          });
        }
      } catch (err) {
        // Lost the create/attach race with a concurrent first login for the same
        // identity — the winner's row IS the account; log into it instead of
        // throwing the raw unique violation to the generic 500 handler.
        if (!isUniqueViolation(err)) throw err;
        user =
          (await findUserByGithubId(db, profile.githubId)) ??
          (profile.email ? await findUserByEmail(db, profile.email) : undefined);
        if (!user) throw err;
      }
    }

    setSessionCookie(c, await createSession(db, user.id), config);
    return c.redirect('/home');
  });

  return app;
}
