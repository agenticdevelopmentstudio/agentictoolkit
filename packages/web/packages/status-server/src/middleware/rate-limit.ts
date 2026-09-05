import type { MiddlewareHandler } from 'hono';

// Fixed-window per-IP rate limiter for the PRE-AUTH surface. Login/signup are
// unauthenticated and each attempt burns a bcrypt verification on the API
// thread, so with no ceiling credential stuffing doubles as a CPU attack.
// In-memory by design (single-instance backend): each process bounds the
// traffic it actually serves.

interface Bucket {
  count: number;
  resetAt: number;
}

/** Hard ceiling on distinct keys held at once. Reached only under an attack that
 *  mints keys faster than the window expires them; we then drop the whole table
 *  (every entry is about to expire anyway) rather than grow without bound. */
const MAX_BUCKETS = 50_000;

/**
 * The client IP, taken from the RIGHTMOST `x-forwarded-for` entry.
 *
 * XFF is a chain each hop APPENDS to, so the leftmost value is whatever the
 * client sent — attacker-controlled. Keying on it (as this first did) lets a
 * scripted attacker rotate a forged IP per request, mint a fresh bucket every
 * time, and walk straight through the ceiling. The rightmost entry is the one
 * added by the hop we actually trust (the platform edge, which is the last thing
 * to touch the header before our loopback proxy forwards it verbatim), so that
 * is the only value with any authority.
 *
 * A request with no XFF at all reached us over loopback with no edge in front —
 * local dev or a direct container call — and keys as `local`.
 */
function clientIp(header: string | undefined): string {
  if (!header) return 'local';
  const hops = header.split(',').map((s) => s.trim()).filter(Boolean);
  return hops[hops.length - 1] ?? 'local';
}

export function rateLimit(opts: { max: number; windowMs?: number }): MiddlewareHandler {
  const windowMs = opts.windowMs ?? 60_000;
  const buckets = new Map<string, Bucket>();
  let lastSweepAt = 0;

  /** Drop expired buckets. Runs at most once per window (or when the hard cap is
   *  hit) — NOT on every request past a size threshold, which turned the limiter
   *  itself into an O(n)-per-request cost exactly when it was under attack. */
  const sweep = (now: number): void => {
    lastSweepAt = now;
    for (const [k, b] of buckets) if (b.resetAt <= now) buckets.delete(k);
    if (buckets.size >= MAX_BUCKETS) {
      // Still over the cap with nothing expired: someone is minting keys faster
      // than the window retires them. Every live bucket lapses within windowMs, so
      // dropping the table costs at most one window of accounting and keeps memory
      // bounded.
      console.error(`[rate-limit] bucket table exceeded ${MAX_BUCKETS} live keys — dropping it`);
      buckets.clear();
    }
  };

  return async (c, next) => {
    const now = Date.now();
    if (now - lastSweepAt >= windowMs || buckets.size >= MAX_BUCKETS) sweep(now);

    const ip = clientIp(c.req.header('x-forwarded-for'));
    let bucket = buckets.get(ip);
    if (!bucket || bucket.resetAt <= now) {
      bucket = { count: 0, resetAt: now + windowMs };
      buckets.set(ip, bucket);
    }
    bucket.count += 1;
    if (bucket.count > opts.max) {
      const retryAfterSec = Math.max(1, Math.ceil((bucket.resetAt - now) / 1000));
      c.header('Retry-After', String(retryAfterSec));
      return c.json({ error: { message: 'Too many attempts — try again shortly' } }, 429);
    }
    await next();
  };
}
