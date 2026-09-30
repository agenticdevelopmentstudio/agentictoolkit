<!-- leaf: implement-status-web/src · source: status-web-src.md -->

**Rules** (cite as `implement-status-web/src#<slug>`):

- `status-user-shape` MUST
- `header-auth-state-shape` MUST
- `header-auth-source-type` MUST
- `session-query-key` MUST
- `session-key-invalidation-precondition` MUST
- `auth-me-url` MUST
- `auth-me-transport` MUST
- `auth-me-single-request` MUST
- `auth-me-non-ok-throws` MUST
- `auth-me-user-resolves` MUST
- `auth-me-signed-out-resolves-null` MUST
- `auth-me-network-failure-propagates` MUST
- `auth-me-body-parse-failure-propagates` MUST
- `auth-me-no-shape-validation` MUST
- `session-query-config` MUST
- `session-query-dedupe` MUST
- `session-return-shape` MUST
- `session-kept-across-errors` MUST
- `session-error-not-exposed` MUST
- `session-query-defaults-inherited` MUST
- `session-client-resolution` MUST
- `header-signed-out-state` MUST
- `header-loading-spinner` MUST
- `header-signed-in-name` MUST
- `header-signed-in-fields` MUST
- `header-role-not-projected` MUST
- `logout-request` MUST
- `logout-navigation` MUST
- `logout-outcome-ignored` MUST
- `logout-rejection-unhandled` MUST
- `no-switch-href` MUST

# Status Web Src

## Overview

The two top-level modules of the `status-web` package's `src/` root.

`header-auth.ts` is the dashboard's client-side view of the status backend's
**local** session (the `status_auth` httpOnly cookie set by `/api/auth/login`,
not adh SSO). Because the cookie is httpOnly, the client learns the session only
by asking `GET {base}/auth/me`. The module exports `fetchStatusUser` (one
request, strict "non-OK is infrastructure trouble, not sign-out" semantics),
`useStatusUser` (the one shared React-Query cache entry under
`STATUS_AUTH_QUERY_KEY`, read by the header seam, the board gate and the
landing page), and `useStatusHeaderAuth` (the injectable auth source a host
passes to its own header component). It declares its own
`StatusHeaderAuthState` shape so the package carries no dependency on any
site's header package. It is published as the `./header-auth` subpath and
re-exported from the package barrel.

`types.ts` is type-only: the wire DTOs the dashboard reads from the status
backend (`StatusResponse`, `UptimeResponse`, `DeploymentDTO`,
`HistoryResponse`, `IntegrationsResponse` and their element types). It has no
runtime code and is imported by the package's own components and hooks; it is
not re-exported from the barrel.

## Behavioral Requirements

### Session data shapes (`header-auth.ts`)

- **status-user-shape**: `StatusUser` MUST carry `email: string`, an optional `displayName` that MAY be `string`, `null`, or absent, and `role` restricted to exactly `"pending"`, `"viewer"`, or `"admin"`.
- **header-auth-state-shape**: `StatusHeaderAuthState` MUST carry `user: { name: string } | null` plus the optional fields `authLoading?: boolean`, `loginHref?: string`, `signupHref?: string`, and `onLogout?: () => void` — the common subset a host header's auth slot takes, declared locally rather than imported.
- **header-auth-source-type**: `StatusHeaderAuthSource` MUST be a zero-argument hook type returning `StatusHeaderAuthState`; `useStatusHeaderAuth` MUST be a stable module-level constant of that type so a host can pass it to its header unchanged.
- **session-query-key**: `STATUS_AUTH_QUERY_KEY` MUST be the readonly tuple `["status-auth-me"]`, and it MUST be the only query key under which the session is cached.
- **session-key-invalidation-precondition**: A login or signup flow that sets the session cookie MUST invalidate `STATUS_AUTH_QUERY_KEY` afterwards; the doc comment on the constant documents this as a caller obligation because the login page caches a fresh `{ user: null }` and the post-login navigation is client-side. This module does not perform the invalidation itself.

### `fetchStatusUser(api, fetchImpl = fetch)`

- **auth-me-url**: `fetchStatusUser` MUST request the URL `api.url("/auth/me")` — the path resolved through the caller's `StatusApiClient` (with the default base `"/api"` this is `"/api/auth/me"`).
- **auth-me-transport**: `fetchStatusUser` MUST issue the request through its `fetchImpl` argument (defaulting to the global `fetch`) with no `init` object — a plain `GET` with no custom headers, no explicit `credentials` option and no abort signal — and MUST NOT route it through `api.fetch`.
- **auth-me-single-request**: Each call to `fetchStatusUser` MUST issue exactly one request; it MUST NOT retry on its own (retry belongs to `useStatusUser`).
- **auth-me-non-ok-throws**: When the response's `ok` is false, `fetchStatusUser` MUST reject with an `Error` whose message is `auth/me unavailable (HTTP <status>)`, and it MUST NOT resolve `null` for any non-OK status (the backend never answers this route with a 401, so any non-OK is infrastructure trouble, not sign-out).
- **auth-me-user-resolves**: When the response is OK and its JSON body's `user` is an object, `fetchStatusUser` MUST resolve that object unchanged.
- **auth-me-signed-out-resolves-null**: When the response is OK and its JSON body's `user` is `null` or absent, `fetchStatusUser` MUST resolve `null`.
- **auth-me-network-failure-propagates**: When `fetchImpl` rejects (connection failure, DNS failure), `fetchStatusUser` MUST reject with that same error, unwrapped.
- **auth-me-body-parse-failure-propagates**: When an OK response's body is not valid JSON, `fetchStatusUser` MUST reject with the error `res.json()` raises.
- **auth-me-no-shape-validation**: `fetchStatusUser` MUST NOT validate the fields of a returned `user` object at runtime; the body is cast to `{ user: StatusUser | null }` and a `user` missing `email` or carrying an unlisted `role` is returned as-is.

### `useStatusUser()`

- **session-query-config**: `useStatusUser` MUST read the session through one React-Query query with key `STATUS_AUTH_QUERY_KEY`, query function `fetchStatusUser(api)` (where `api` is `useStatusApi()`), `staleTime` of 60,000 ms, and `retry` of 3 (up to four attempts per fetch, with React Query's default exponential backoff).
- **session-query-dedupe**: Every concurrent consumer of `useStatusUser` MUST share the single cache entry for `STATUS_AUTH_QUERY_KEY`, so simultaneous mounts issue one `/auth/me` request, not one per consumer.
- **session-return-shape**: `useStatusUser` MUST return `{ user, isPending }`, where `user` is the cached data or `null` when no data exists, and `isPending` is true only while the first load is in flight with no data yet.
- **session-kept-across-errors**: When a refetch fails after data has been cached, `useStatusUser` MUST keep returning the last cached user; a failed refetch MUST NOT change `user` to `null`. Sign-out is observed only when a fetch resolves a definitive `null`.
- **session-error-not-exposed**: `useStatusUser` MUST NOT expose the query's error or error state to its caller; only `user` and `isPending` are returned.
- **first-load-failure-projection**: NEEDS REVIEW: Not implemented in source. When the very first `/auth/me` load fails all four attempts, `isPending` becomes false with no cached data, so `useStatusUser` returns `user: null` — indistinguishable from a definitive signed-out answer — and the header shows login/signup links; this contradicts the doc comment that "sign-out only ever comes from a definitive `{ user: null }`", and the hook exposes no error signal to tell the two apart. Settling this needs a decision from the package owner on whether a cold-load failure should surface an error state (e.g. by returning `isError`) or remain projected to signed-out.
- **session-query-defaults-inherited**: `useStatusUser` MUST NOT override any other React-Query option; refetch-on-focus, refetch-on-reconnect and cache garbage-collection timing are whatever the host's `QueryClient` defaults are.
- **session-client-resolution**: `useStatusUser` MUST resolve its `StatusApiClient` through `useStatusApi()` — the nearest `StatusApiProvider`'s client, or the same-origin default client when none is mounted.

### `useStatusHeaderAuth()`

- **header-signed-out-state**: When `useStatusUser` returns `user: null`, `useStatusHeaderAuth` MUST return exactly `{ user: null, authLoading: isPending, loginHref: "/login", signupHref: "/signup" }`.
- **header-loading-spinner**: While the first session load is in flight, `useStatusHeaderAuth` MUST return `authLoading: true` together with `user: null`, so the host shows a spinner rather than flashing login links.
- **header-signed-in-name**: When a user is present, `useStatusHeaderAuth` MUST return `user.name` equal to `displayName` when it is a non-empty string, and otherwise (`null`, absent, or `""`) equal to `email`.
- **header-signed-in-fields**: When a user is present, `useStatusHeaderAuth` MUST return only `user` and `onLogout`; `authLoading`, `loginHref` and `signupHref` MUST be absent.
- **header-role-not-projected**: `useStatusHeaderAuth` MUST NOT include the user's `role` or `email` (other than as the name fallback) in the returned state.
- **logout-request**: Invoking `onLogout` MUST send one `POST` to `/auth/logout` through `api.fetch` (with the default base, `"/api/auth/logout"`), with no body and no idempotency key; clearing the cookie is the backend's responsibility (see status-server-auth).
- **logout-navigation**: After the logout request settles — fulfilled with any status, including non-OK, or rejected — `onLogout` MUST set `window.location.href` to `"/"`, a full-page navigation to the public landing page.
- **logout-outcome-ignored**: `onLogout` MUST NOT inspect the logout response's status and MUST NOT invalidate `STATUS_AUTH_QUERY_KEY`; the full-page navigation reloads the session from `/auth/me`, so a logout the backend did not honour shows the user still signed in after the reload.
- **logout-rejection-unhandled**: When the logout request rejects, the rejection MUST propagate out of the discarded `.finally(...)` promise as an unhandled promise rejection; `onLogout` does not catch it.
- **no-switch-href**: `useStatusHeaderAuth` MUST NOT supply a `resolveSwitchHref` (or any site-switch resolver), so a host's site switcher navigates straight to sibling sites instead of through an adh-SSO redirect.

