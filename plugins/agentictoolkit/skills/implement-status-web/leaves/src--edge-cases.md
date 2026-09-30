<!-- leaf: implement-status-web/src--edge-cases · source: status-web-src.md -->

# Status Web Src

**Rules** (cite as `implement-status-web/src--edge-cases#<slug>`):

- `signed-out-answer-vs-failure` MUST — HTTP 200 { user: null } → fetchStatusUser resolves null (MUST); any non-OK status, including 401 and 403 → rejects …
- `empty-or-missing-body-field` MUST — HTTP 200 {} → resolves null, read as signed-out (MUST, per body.user ?? null).
- `malformed-body` MUST — HTTP 200 with non-JSON body → rejects with the parse error; React Query retries (MUST).
- `partial-user-object` MUST — HTTP 200 { user: { role: "viewer" } } (no email, no displayName) → resolved unchanged (MUST, per …
- `empty-display-name` MUST — displayName: "" → header name falls back to email (MUST; || rather than ??).
- `transient-failure-with-cached-session` MUST — backend restart, proxy 500, or network blip after a successful load → cached user is kept and the fetch retried up to 3 …
- `timeout` MUST — no request timeout or abort signal is set on /auth/me or /auth/logout (MUST NOT be assumed); a hung request stays …
- `logout-failure` MUST — logout POST returns non-OK or rejects → navigation to / happens anyway (MUST); on reload the session is re-read, so an …
- `concurrent-consumers` MUST — header, board gate and landing page mounting at once share one query and one request (MUST).

## Edge Cases

- **Signed-out answer vs. failure**: HTTP 200 `{ user: null }` → `fetchStatusUser` resolves `null` (MUST); any non-OK status, including 401 and 403 → rejects (MUST). Signed-out is never inferred from a status code.
- **Empty or missing body field**: HTTP 200 `{}` → resolves `null`, read as signed-out (MUST, per `body.user ?? null`).
- **Malformed body**: HTTP 200 with non-JSON body → rejects with the parse error; React Query retries (MUST).
- **Partial user object**: HTTP 200 `{ user: { role: "viewer" } }` (no `email`, no `displayName`) → resolved unchanged (MUST, per auth-me-no-shape-validation); `useStatusHeaderAuth` then returns `user.name` as `undefined` despite the `string` type.
- **Empty display name**: `displayName: ""` → header name falls back to `email` (MUST; `||` rather than `??`).
- **Transient failure with cached session**: backend restart, proxy 500, or network blip after a successful load → cached user is kept and the fetch retried up to 3 times (MUST); the header never flashes signed-out.
- **Cold-load failure**: backend unreachable on the very first load → after four failed attempts the hook returns `user: null, isPending: false`, and the header shows login/signup links; see the open question on first-load-failure-projection.
- **Offline / disconnected**: `fetch` rejects → treated like any failure above (error kept out of `user`, retried); no offline detection of its own.
- **Timeout**: no request timeout or abort signal is set on `/auth/me` or `/auth/logout` (MUST NOT be assumed); a hung request stays pending until the browser gives up, and on first load `isPending` stays true (header spinner) for that whole time.
- **Cancellation**: `fetchStatusUser` accepts no abort signal; React Query's query-function signal is not forwarded, so an unmounted query's in-flight request is not aborted.
- **Logout failure**: logout POST returns non-OK or rejects → navigation to `/` happens anyway (MUST); on reload the session is re-read, so an un-cleared cookie shows the user still signed in. A rejection surfaces as an unhandled promise rejection.
- **Logout double-invoke**: calling `onLogout` twice issues two POSTs; each navigates to `/` when it settles. No guard exists.
- **Concurrent consumers**: header, board gate and landing page mounting at once share one query and one request (MUST).
- **Login without invalidation**: a login flow that sets the cookie but does not invalidate `STATUS_AUTH_QUERY_KEY` leaves the cached `{ user: null }` in place for up to the 60,000 ms `staleTime` (documented caller obligation).
- **Injected client fetch**: a `StatusApiClient` built with a custom `fetch` is honoured by `onLogout` (via `api.fetch`) but not by `useStatusUser`, whose `fetchStatusUser(api)` call uses the global `fetch` with only `api.url`.
- **Optional DTO fields**: `phaseConfirmedAt` absent → consumers use `createdAt`; `missingEnv`, `unreachable`, `correlated` absent → treated as empty/false by consumers.
