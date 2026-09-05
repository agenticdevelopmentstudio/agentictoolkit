/**
 * A fleet peer's base URL, in the exact form the backend stores and accepts.
 *
 * This is a deliberate mirror of `src/peers/base-url.ts` — the board is a separate
 * Next app with its own build, so it cannot import the backend's module, and the
 * backend stays the authority: it normalizes and validates every write regardless of
 * what the UI sent. Duplicating the rules here only moves the feedback earlier — the
 * editor's dirty check compares against the value the server will actually keep, and a
 * typo reads as a sentence under the field instead of coming back as a 400. Keep the
 * two files in step; `peer-url.test.ts` asserts the same cases the backend's do.
 */

/** The canonical stored form: `scheme://host[:port][/path]`, lower-cased, default port
 *  dropped, no trailing slash, no query/fragment. Total — an unparseable string falls
 *  back to trim + strip, because the editor normalizes on every keystroke, long before
 *  what is typed is a URL at all. */
export function normalizePeerBaseUrl(value: string): string {
  const trimmed = value.trim();
  try {
    // `new URL()` lower-cases the scheme and host and drops a default port, which is
    // what keeps `https://Lewis.example.com:443/` from becoming a second peer row.
    const u = new URL(trimmed);
    return `${u.protocol}//${u.host}${u.pathname}`.replace(/\/+$/, "");
  } catch {
    return trimmed.replace(/\/+$/, "");
  }
}

/** Whether the backend will accept this as a peer base URL: an absolute http(s) URL. */
export function isValidPeerBaseUrl(value: string): boolean {
  try {
    const { protocol } = new URL(value.trim());
    return protocol === "http:" || protocol === "https:";
  } catch {
    return false;
  }
}
