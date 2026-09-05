import type { StatusConfig } from '../config/port';

/**
 * The ONE definition of a peer's base URL — what counts as valid, and what the
 * canonical stored form is. The write path (`createPeer`/`updatePeer`) normalizes
 * with it and the request schema (`peerInsert`) validates with it, so a URL can
 * never be accepted in a shape the store would then rewrite.
 *
 * Canonicalization is what makes `uniq_peer_base_url` mean "one row per monitor":
 * the index is byte-exact, so anything that varies without changing the target —
 * case, a default port, a trailing slash — has to be folded out BEFORE the insert,
 * or the same monitor gets polled (and drawn on the fleet board) twice.
 */

/** The canonical stored form: `scheme://host[:port][/path]`, lower-cased, default
 *  port dropped, no trailing slash, no query/fragment (a base URL is concatenated
 *  with `/snapshot`, so neither could survive anyway). Total by design — an
 *  unparseable string falls back to trim + strip, because callers normalize before
 *  they know whether validation passed. */
export function normalizePeerBaseUrl(baseUrl: string): string {
  const trimmed = baseUrl.trim();
  try {
    // `new URL()` lower-cases the scheme and host and drops a default port for us,
    // which is exactly the folding the unique index needs.
    const u = new URL(trimmed);
    return `${u.protocol}//${u.host}${u.pathname}`.replace(/\/+$/, '');
  } catch {
    return trimmed.replace(/\/+$/, '');
  }
}

/** Whether a string is an absolute http(s) URL. Without this a typo
 *  ("lewis.example.com", "/status") would be stored happily and then fail every
 *  snapshot fetch as an unreachable peer — a validation error at the write is far
 *  cheaper to read than a permanently red fleet card. */
export function isValidPeerBaseUrl(baseUrl: string): boolean {
  try {
    const { protocol } = new URL(baseUrl.trim());
    return protocol === 'http:' || protocol === 'https:';
  } catch {
    return false;
  }
}

/** Whether two base URLs point at the same monitor, compared in canonical form. */
export function isSamePeerBaseUrl(a: string, b: string): boolean {
  return normalizePeerBaseUrl(a) === normalizePeerBaseUrl(b);
}

/** Whether `value` is THIS monitor's own URL — a monitor may never add itself as a
 *  peer (the two sibling deployments, `lewis` / `testing.lewis`, make pasting the
 *  wrong URL a one-keystroke mistake that would otherwise draw the same host twice:
 *  once live, once a poll-interval stale). An empty `config.publicBaseUrl` means the
 *  host's own URL is unknown, so nothing can be flagged as a self-match. */
export function isSelfPeerUrl(value: string, config: StatusConfig): boolean {
  return config.publicBaseUrl !== '' && isSamePeerBaseUrl(value, config.publicBaseUrl);
}

/** The message a duplicate `base_url` gets, shared by the HTTP route (as a 409) and
 *  the `add_peer` MCP tool, so both surfaces say the same actionable sentence. */
export const DUPLICATE_PEER_MESSAGE = 'A peer with that base URL already exists';

/**
 * Whether a driver error is the `uniq_peer_base_url` violation.
 *
 * libSQL reports it as `SQLITE_CONSTRAINT_UNIQUE` with the index named in the
 * message, and drizzle wraps the driver error, so walk the `cause` chain rather than
 * only the top error. Matching `SQLITE_CONSTRAINT` alone would be wrong: that prefix
 * also covers NOT NULL / CHECK / FOREIGN KEY, and reporting one of those as "duplicate
 * base URL" would send the reader looking for a conflict that doesn't exist.
 */
export function isDuplicatePeerError(err: unknown): boolean {
  for (let e: unknown = err, depth = 0; e !== null && e !== undefined && depth < 4; e = (e as { cause?: unknown }).cause, depth++) {
    const code = String((e as { code?: unknown }).code ?? '');
    const message = String((e as { message?: unknown }).message ?? '');
    if (code.includes('SQLITE_CONSTRAINT_UNIQUE') || /unique constraint failed/i.test(message)) return true;
  }
  return false;
}
