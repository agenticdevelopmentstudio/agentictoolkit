<!-- leaf: implement-status-web/src--test-vectors · source: status-web-src.md -->

# Status Web Src

**Rules** (cite as `implement-status-web/src--test-vectors#<slug>`):

- `unknown-uptimeday-status-fail-compile-assigning-servicestatusdto` MUST — The types.ts requirements are compile-time shapes with no runtime behavior; a port verifies them with type-level …

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-src-001 | auth-me-user-resolves (traced to `header-auth.test.ts`) | `fetchStatusUser(createStatusApiClient(), fetchImpl)` where `fetchImpl` resolves HTTP 200 `{"user":{"email":"a@b.c","displayName":"A","role":"admin"}}` | resolves `{ email: "a@b.c", displayName: "A", role: "admin" }` |
| status-web-src-002 | auth-me-signed-out-resolves-null (traced to `header-auth.test.ts`) | same call; `fetchImpl` resolves HTTP 200 `{"user":null}` | resolves `null` |
| status-web-src-003 | auth-me-non-ok-throws (traced to `header-auth.test.ts`) | same call; `fetchImpl` resolves HTTP 500 `{}` | rejects with an `Error` whose message matches `HTTP 500` (exactly `auth/me unavailable (HTTP 500)`) |
| status-web-src-004 | auth-me-network-failure-propagates (traced to `header-auth.test.ts`) | same call; `fetchImpl` rejects with `TypeError("fetch failed")` | rejects with that `TypeError` (message `fetch failed`) |
| status-web-src-005 | auth-me-signed-out-resolves-null | same call; `fetchImpl` resolves HTTP 200 `{}` | resolves `null` (`user` absent reads as signed-out) |
| status-web-src-006 | auth-me-non-ok-throws | same call; `fetchImpl` resolves HTTP 401 `{"user":null}` | rejects with `auth/me unavailable (HTTP 401)`; never resolves `null` |
| status-web-src-007 | auth-me-url, auth-me-transport | `createStatusApiClient({ basePath: "/proxy" })`; recording `fetchImpl` | `fetchImpl` called once with the single argument `"/proxy/auth/me"` and no `init` |
| status-web-src-008 | auth-me-body-parse-failure-propagates | `fetchImpl` resolves HTTP 200 with body `not json` | rejects with the JSON parse error from `res.json()` |
| status-web-src-009 | session-query-key | read `STATUS_AUTH_QUERY_KEY` | deep-equals `["status-auth-me"]` |
| status-web-src-010 | header-signed-out-state, header-loading-spinner | `useStatusUser` yields `{ user: null, isPending: true }` | `useStatusHeaderAuth()` returns `{ user: null, authLoading: true, loginHref: "/login", signupHref: "/signup" }` |
| status-web-src-011 | header-signed-out-state | `useStatusUser` yields `{ user: null, isPending: false }` | returns `{ user: null, authLoading: false, loginHref: "/login", signupHref: "/signup" }` |
| status-web-src-012 | header-signed-in-name, header-signed-in-fields | user `{ email: "a@b.c", displayName: "Ann", role: "viewer" }` | returns `user: { name: "Ann" }`, a function `onLogout`, and no `authLoading`/`loginHref`/`signupHref` keys |
| status-web-src-013 | header-signed-in-name | user `{ email: "a@b.c", displayName: "", role: "viewer" }` | `user.name === "a@b.c"` |
| status-web-src-014 | header-signed-in-name | user `{ email: "a@b.c", displayName: null, role: "admin" }` | `user.name === "a@b.c"` |
| status-web-src-015 | logout-request, logout-navigation | signed-in state, default client; call `onLogout()`; `api.fetch` resolves HTTP 200 | one `fetch("/api/auth/logout", { method: "POST" })`; afterwards `window.location.href === "/"` |
| status-web-src-016 | logout-navigation, logout-outcome-ignored | as 015 but `api.fetch` resolves HTTP 500 | `window.location.href === "/"`; no error thrown synchronously; the query key is not invalidated |
| status-web-src-017 | logout-navigation, logout-rejection-unhandled | as 015 but `api.fetch` rejects | `window.location.href === "/"`; an unhandled promise rejection carrying the fetch error is raised |
| status-web-src-018 | session-kept-across-errors | cache holds user `U`; next refetch (all four attempts) rejects with HTTP 503 | `useStatusUser()` still returns `{ user: U, isPending: false }` |
| status-web-src-019 | session-query-dedupe | two components calling `useStatusUser` mount in the same render with an empty cache | exactly one `/auth/me` request is issued |
| status-web-src-020 | session-query-config | first load; `fetchImpl` rejects every time | `/auth/me` is attempted 4 times (1 + `retry: 3`) before the query settles into error |

The `types.ts` requirements are compile-time shapes with no runtime behavior; a port verifies them with type-level assertions (e.g. assigning `"unknown"` to `UptimeDay["status"]` MUST fail to compile, and assigning it to `ServiceStatusDTO["status"]` MUST compile) rather than runtime vectors.
