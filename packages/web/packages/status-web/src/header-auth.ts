"use client";

import { useQuery } from "@tanstack/react-query";

/**
 * What the host's header needs from the status session. Declared HERE, not imported
 * from a header package: this package carries no dependency on any site's chrome. The
 * shape is the common subset every header auth slot takes (`user` + the login/logout
 * affordances), so the host passes {@link useStatusHeaderAuth} to its own header
 * component unchanged.
 */
export interface StatusHeaderAuthState {
  /** Signed-in account (`name` is what the header greets/initials), or null when signed out. */
  user: { name: string } | null;
  /** The first session load is still in flight — show a spinner, not login links. */
  authLoading?: boolean;
  loginHref?: string;
  signupHref?: string;
  onLogout?: () => void;
}

/** A React hook producing {@link StatusHeaderAuthState}; a stable module-level function. */
export type StatusHeaderAuthSource = () => StatusHeaderAuthState;

export interface StatusUser {
  email: string;
  displayName?: string | null;
  role: "pending" | "viewer" | "admin";
}

/** The one React-Query key for the session. Login/signup must INVALIDATE it after
 *  setting the cookie: the login page itself caches a fresh `{ user: null }`, and the
 *  post-login `router.push` is a client-side navigation, so without invalidation the
 *  header keeps rendering that cached signed-out state for the whole staleTime. */
export const STATUS_AUTH_QUERY_KEY = ["status-auth-me"] as const;

/**
 * Fetch the current session from `GET /api/auth/me`. The backend NEVER answers that
 * route with a 401 — signed-out is a definitive 200 `{ user: null }` — so any non-OK
 * response here is infrastructure trouble (the in-container proxy 500ing because the
 * backend hiccuped, a deploy restart, a network blip), NOT a sign-out. Those THROW,
 * so React Query keeps the last-known session and retries, instead of flashing the
 * signed-out header/board at a logged-in user mid-blip (the "visited the site and I
 * was suddenly logged out" bug). Exported for tests.
 */
export async function fetchStatusUser(fetchImpl: typeof fetch = fetch): Promise<StatusUser | null> {
  const res = await fetchImpl("/api/auth/me");
  if (!res.ok) throw new Error(`auth/me unavailable (HTTP ${res.status})`);
  const body = (await res.json()) as { user: StatusUser | null };
  return body.user ?? null;
}

/**
 * The status site's local session, resolved once and shared. The status-backend runs
 * its OWN local user auth (not adh SSO): the session is the `status_auth` httpOnly
 * cookie set by /api/auth/login. Because the cookie is httpOnly the client learns the
 * session by asking `GET /api/auth/me` through the proxy. The single React-Query key
 * (`status-auth-me`) dedupes across every consumer — the header seam, the board gate,
 * and the landing page all read this one cache entry. `isPending` is true only while
 * the first load is in flight (distinct from a resolved signed-out `null`).
 */
export function useStatusUser(): { user: StatusUser | null; isPending: boolean } {
  const { data, isPending } = useQuery({
    queryKey: STATUS_AUTH_QUERY_KEY,
    queryFn: () => fetchStatusUser(),
    staleTime: 60_000,
    // Transient failures retry (default backoff) and, because a query error never
    // clears already-cached data, the header keeps showing the signed-in user
    // throughout — sign-out only ever comes from a definitive `{ user: null }`.
    retry: 3,
  });
  return { user: data ?? null, isPending };
}

/**
 * The host header's injectable auth source, built on {@link useStatusUser}.
 *
 * Signed out → login + signup links (the only entry points to auth). Signed in → the
 * user's name + a sign-out that POSTs /api/auth/logout (clears the cookie) and returns
 * to the public landing `/`. No `resolveSwitchHref` is supplied, so the site switcher
 * navigates straight to siblings rather than through a silent adh-SSO redirect (wrong
 * for a non-adh session).
 */
export const useStatusHeaderAuth: StatusHeaderAuthSource = (): StatusHeaderAuthState => {
  const { user, isPending } = useStatusUser();

  if (!user) {
    // While the first /api/auth/me load is in flight, show the header spinner
    // rather than flashing login/signup links that may vanish a tick later.
    return { user: null, authLoading: isPending, loginHref: "/login", signupHref: "/signup" };
  }
  return {
    user: { name: user.displayName || user.email },
    onLogout: () => {
      void fetch("/api/auth/logout", { method: "POST" }).finally(() => {
        window.location.href = "/";
      });
    },
  };
};
