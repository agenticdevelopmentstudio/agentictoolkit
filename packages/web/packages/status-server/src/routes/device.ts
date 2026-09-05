import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { Context } from 'hono';
import { z } from 'zod';
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { and, eq, lt } from 'drizzle-orm';
import type { Db } from '../libsql/client';
import type { AuthVars } from '../middleware/auth';
import type { AuthUser } from '../storage/auth-store';
import { deviceAuthorizations, apiTokens } from '../libsql/schema';
import { mintApiToken, deleteApiToken } from '../storage/token-store';
import { rateLimit } from '../middleware/rate-limit';
import { readValidatedBody } from './read-body';

// ---------------------------------------------------------------------------
// RFC 8628-shaped device authorization flow.
//
//   1. A CLI POSTs /auth/device (public) → gets a long `device_code`, a short
//      human `user_code`, and a `verification_uri` to open in a browser.
//   2. The human opens the URI (the dashboard's /device page), where a SIGNED-IN
//      approver (any viewer/admin) approves or denies the request.
//   3. The CLI polls POST /auth/device/token (public) with its `device_code`;
//      once approved it gets the minted bearer token EXACTLY ONCE, then the row
//      is deleted (single-use).
//
// Only the sha256 of each code is stored — never the plaintext. `token_raw` is
// the sole, tightly-scoped exception to hash-only-at-rest: it holds the minted
// secret ONLY between approval and the single successful poll, then the row (and
// its secret) is deleted in one atomic delete-returning. It is NEVER selected in
// any list path.
// ---------------------------------------------------------------------------

/** Human-typeable user-code alphabet: no vowels (no accidental words) and no
 *  0/1/O/I/U (no visually ambiguous glyphs). */
const USER_CODE_ALPHABET = 'BCDFGHJKLMNPQRSTVWXZ23456789';
/** Grant lifetime: the whole request→approve→poll dance must finish within this. */
const DEVICE_TTL_MS = 900_000; // 15 min
/** Polling floor the CLI is told to honour (also the server-side slow_down gate). */
const POLL_INTERVAL_SEC = 5;
/** Minted device-token lifetime. */
const TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

function sha256Hex(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

/** A `device_code`: 32 random bytes as hex (64 chars). */
function generateDeviceCode(): string {
  return randomBytes(32).toString('hex');
}

/** A `user_code`: 8 chars from the safe alphabet, grouped `XXXX-XXXX`. Uses
 *  `randomInt` per char (rejection-sampled, unbiased) rather than `% len`. */
function generateUserCode(): string {
  let s = '';
  for (let i = 0; i < 8; i++) s += USER_CODE_ALPHABET[randomInt(USER_CODE_ALPHABET.length)];
  return `${s.slice(0, 4)}-${s.slice(4)}`;
}

/** Normalize a user-supplied code before hashing: the alphabet is upper-case and
 *  the format is `XXXX-XXXX`, so an approver who retypes it lower-cased or with
 *  stray whitespace still matches the stored hash. */
function hashUserCode(userCode: string): string {
  return sha256Hex(userCode.trim().toUpperCase());
}

export const requestSchema = z.object({ label: z.string().max(200).optional() });
export const tokenSchema = z.object({ device_code: z.string().min(1) });
export const userCodeSchema = z.object({ user_code: z.string().min(1) });

/**
 * The two PUBLIC device routes — mounted PRE-seam beside authRoutes (they are
 * reached by an as-yet-unauthenticated CLI). Both are per-IP rate-limited
 * (max 10/window), mirroring /auth/login: a request-flood or a poll-flood is an
 * unauthenticated cost the container must bound.
 */
export function devicePublicRoutes(db: Db): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  app.use('/auth/device', rateLimit({ max: 10 }));
  // The poll route needs headroom OVER the advertised cadence: interval 5s ⇒ 12
  // polls/min, so a compliant client polling a still-pending grant would blow a
  // max:10/min limiter in its own happy path (and the CLI reads 429 as an error,
  // not slow_down). 30 gives 2.5× headroom (12/min steady + retry/jitter) so a
  // compliant client can never 429; the per-flow throttle is still the in-app
  // slow_down gate (lastPollAt < 5s) — this HTTP limiter is only the per-IP backstop.
  app.use('/auth/device/token', rateLimit({ max: 30 }));

  // Request a grant. Opportunistically reap expired rows first so the table never
  // accumulates dead grants (and a recycled user_code can't collide with a stale one).
  app.post('/auth/device', async (c) => {
    const { label } = await readValidatedBody(c, requestSchema);
    await db.delete(deviceAuthorizations).where(lt(deviceAuthorizations.expiresAt, new Date()));

    const deviceCode = generateDeviceCode();
    const userCode = generateUserCode();
    const expiresAt = new Date(Date.now() + DEVICE_TTL_MS);
    await db.insert(deviceAuthorizations).values({
      deviceCodeHash: sha256Hex(deviceCode),
      userCodeHash: hashUserCode(userCode),
      cliLabel: label?.trim() || '',
      expiresAt,
    });

    // The approver opens this in a browser; derive the origin from the request so
    // no extra config is needed (the CLI just follows the URL we hand back).
    const origin = new URL(c.req.url).origin;
    c.header('Cache-Control', 'no-store');
    return c.json(
      {
        device_code: deviceCode,
        user_code: userCode,
        verification_uri: `${origin}/device?code=${userCode}`,
        interval: POLL_INTERVAL_SEC,
        expires_in: Math.floor(DEVICE_TTL_MS / 1000),
      },
      201,
    );
  });

  // Poll for the token. Returns an RFC-8628 error tag while pending/denied/expired,
  // or the minted token EXACTLY ONCE on the approved path (row deleted after).
  app.post('/auth/device/token', async (c) => {
    const { device_code } = await readValidatedBody(c, tokenSchema);
    const [row] = await db
      .select()
      .from(deviceAuthorizations)
      .where(eq(deviceAuthorizations.deviceCodeHash, sha256Hex(device_code)))
      .limit(1);

    // Unknown code, or a grant already consumed by an earlier successful poll.
    if (!row) return c.json({ error: 'expired' as const });

    const now = Date.now();
    if (row.expiresAt.getTime() <= now) {
      await db.delete(deviceAuthorizations).where(eq(deviceAuthorizations.id, row.id));
      return c.json({ error: 'expired' as const });
    }
    if (row.status === 'denied') {
      await db.delete(deviceAuthorizations).where(eq(deviceAuthorizations.id, row.id));
      return c.json({ error: 'denied' as const });
    }
    if (row.status === 'approved') {
      // SINGLE-USE, atomic: delete-returning both reads the held secret AND
      // consumes the row in one statement — a second concurrent poll's delete
      // matches zero rows and falls through to `expired`. This is the "null +
      // delete" the secret's at-rest exception requires: the row (and its
      // token_raw) ceases to exist here, so no separate null is needed.
      c.header('Cache-Control', 'no-store');
      const [consumed] = await db
        .delete(deviceAuthorizations)
        .where(eq(deviceAuthorizations.id, row.id))
        .returning();
      if (!consumed?.tokenRaw || !consumed.tokenId) return c.json({ error: 'expired' as const });
      // role + expiry come from the minted token row (still live — only the grant
      // was consumed). token_raw itself is never selected from a list path.
      const [tok] = await db.select().from(apiTokens).where(eq(apiTokens.id, consumed.tokenId)).limit(1);
      if (!tok) return c.json({ error: 'expired' as const });
      return c.json({ token: consumed.tokenRaw, role: tok.role, expires_at: tok.expiresAt?.toISOString() ?? null });
    }

    // Still pending. Rate the polling: a poll landing < interval since the last
    // ACCEPTED poll is told to slow down (and does NOT advance the clock, so the
    // client can't walk the window forward by hammering it).
    if (row.lastPollAt && now - row.lastPollAt.getTime() < POLL_INTERVAL_SEC * 1000) {
      return c.json({ error: 'slow_down' as const });
    }
    await db
      .update(deviceAuthorizations)
      .set({ lastPollAt: new Date() })
      .where(eq(deviceAuthorizations.id, row.id));
    return c.json({ error: 'authorization_pending' as const });
  });

  return app;
}

/** The signed-in session user, or a 403 — an AUTH_DISABLED (null user) or token
 *  principal cannot approve a device grant (no honest approver identity). */
function requireSessionUser(c: Context<{ Variables: AuthVars }>): AuthUser {
  const user = c.get('user');
  if (!user) throw new HTTPException(403, { message: 'Approving a device requires a signed-in user' });
  return user;
}

/**
 * The approval trio — mounted POST-seam (any authenticated viewer/admin session),
 * BEFORE usersRoutes so that router's `use('*', requireAdmin)` never leaks onto
 * these (a viewer must be able to approve a `user`-role token). NOT admin-gated.
 */
export function deviceApprovalRoutes(db: Db): Hono<{ Variables: AuthVars }> {
  const app = new Hono<{ Variables: AuthVars }>();

  // Look up a still-valid grant by its user_code, reaping it if expired. Returns
  // the row, or null (missing / expired) so callers answer 404 uniformly.
  async function findLiveByUserCode(userCode: string): Promise<typeof deviceAuthorizations.$inferSelect | null> {
    const [row] = await db
      .select()
      .from(deviceAuthorizations)
      .where(eq(deviceAuthorizations.userCodeHash, hashUserCode(userCode)))
      .limit(1);
    if (!row) return null;
    if (row.expiresAt.getTime() <= Date.now()) {
      await db.delete(deviceAuthorizations).where(eq(deviceAuthorizations.id, row.id));
      return null;
    }
    return row;
  }

  // Show the pending request so the approver sees WHAT they're approving. Returns
  // the grant's status too, so the page can distinguish "already handled" from a
  // live pending request without a second call.
  app.get('/auth/device/pending', async (c) => {
    requireSessionUser(c);
    const userCode = c.req.query('user_code');
    if (!userCode) throw new HTTPException(400, { message: 'user_code is required' });
    const row = await findLiveByUserCode(userCode);
    if (!row) throw new HTTPException(404, { message: 'code not found or expired' });
    return c.json({
      label: row.cliLabel,
      status: row.status,
      createdAt: row.createdAt.toISOString(),
      expiresAt: row.expiresAt.toISOString(),
    });
  });

  // Approve: mint a token at the APPROVER's tier (admin session → admin token,
  // viewer session → user token), stash the raw secret + token id on the grant,
  // mark it approved. The CLI's next poll collects the token and consumes the row.
  app.post('/auth/device/approve', async (c) => {
    const user = requireSessionUser(c);
    const { user_code } = await readValidatedBody(c, userCodeSchema);
    const row = await findLiveByUserCode(user_code);
    if (!row) throw new HTTPException(404, { message: 'code not found or expired' });
    if (row.status !== 'pending') throw new HTTPException(409, { message: 'This request has already been handled' });

    const role = c.get('tier') === 'admin' ? ('admin' as const) : ('user' as const);
    const { meta, raw } = await mintApiToken(db, {
      name: row.cliLabel || 'device',
      role,
      kind: 'device',
      createdBy: user.id,
      expiresAt: new Date(Date.now() + TOKEN_TTL_MS),
    });
    // Guard the write on still-pending status, so two racing approvers can't both
    // mint-and-stash onto the same grant (only the first update matches).
    const updated = await db
      .update(deviceAuthorizations)
      .set({ status: 'approved', tokenId: meta.id, tokenRaw: raw, approvedBy: user.id })
      .where(and(eq(deviceAuthorizations.id, row.id), eq(deviceAuthorizations.status, 'pending')))
      .returning({ id: deviceAuthorizations.id });
    if (updated.length === 0) {
      // Lost the race: the just-minted token was never disclosed (this update's
      // stash never landed), so it's dead on arrival — delete it rather than
      // leave an orphaned api_tokens row behind.
      await deleteApiToken(db, meta.id);
      throw new HTTPException(409, { message: 'This request has already been handled' });
    }
    return c.json({ status: 'approved' as const });
  });

  // Deny: mark the grant denied; the CLI's next poll gets `denied` and stops.
  app.post('/auth/device/deny', async (c) => {
    requireSessionUser(c);
    const { user_code } = await readValidatedBody(c, userCodeSchema);
    const row = await findLiveByUserCode(user_code);
    if (!row) throw new HTTPException(404, { message: 'code not found or expired' });
    if (row.status !== 'pending') throw new HTTPException(409, { message: 'This request has already been handled' });
    const updated = await db
      .update(deviceAuthorizations)
      .set({ status: 'denied' })
      .where(and(eq(deviceAuthorizations.id, row.id), eq(deviceAuthorizations.status, 'pending')))
      .returning({ id: deviceAuthorizations.id });
    if (updated.length === 0) throw new HTTPException(409, { message: 'This request has already been handled' });
    return c.json({ status: 'denied' as const });
  });

  return app;
}
