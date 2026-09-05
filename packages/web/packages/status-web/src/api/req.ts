/** The admin API fetch helper shared by every `src/api/*` module: JSON in, JSON out,
 *  against the same-origin `/api/*` BFF proxy (the Next route handler attaches the
 *  session's bearer token server-side, so nothing here carries credentials). */

/** A backend error body. The status API answers `{ error: { message } }`; the Next
 *  route handlers use a flat `{ error }` / `{ message }`. Accept all three rather than
 *  silently dropping the sentence because the shape didn't match. */
interface ErrorBody {
  error?: string | { message?: string };
  message?: string;
}

/** The server's own error sentence as a suffix — empty when the body is missing,
 *  unparseable, or carries none. */
async function detail(res: Response): Promise<string> {
  const body = (await res.json().catch(() => null)) as ErrorBody | null;
  const text = typeof body?.error === "string" ? body.error : (body?.error?.message ?? body?.message);
  return text ? ` — ${text}` : "";
}

/**
 * Fetch JSON, THROWING on any non-OK response so a 401/409/500 body can never be read
 * as data by a caller expecting rows.
 *
 * The message keeps the `METHOD url → status` prefix the editor sections' error line
 * has always shown, and appends the server's own sentence when there is one: without
 * it a 409 "A peer with that base URL already exists" would reach the user as a bare
 * "→ 409", which says nothing about what to fix.
 */
export async function req<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, {
    ...init,
    headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  if (!r.ok) throw new Error(`${init?.method ?? "GET"} ${url} → ${r.status}${await detail(r)}`);
  return (r.status === 204 ? undefined : await r.json()) as T;
}
