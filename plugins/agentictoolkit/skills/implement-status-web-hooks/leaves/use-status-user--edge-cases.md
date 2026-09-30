<!-- leaf: implement-status-web-hooks/use-status-user--edge-cases · source: status-web-hooks-use-status-user.md -->

# useStatusUser

**Rules** (cite as `implement-status-web-hooks/use-status-user--edge-cases#<slug>`):

- `first-load-in-flight` MUST — The hook MUST return null, the same value as signed out (use-status-user-006). Callers that must not flash signed-out …
- `first-load-fails-with-nothing-cached` MUST — After 4 failed attempts the hook MUST return null. The doc comment covers this as "unknown", and a later refetch …
- `transient-failure-while-signed-in` MUST — The hook MUST keep returning the cached user (use-status-user-007). A 5xx from the proxy, a deploy restart or a network …
- `backend-returns-401-or-403` MUST — This is treated like any other non-OK status. The query function MUST throw, and the cached session MUST be kept. The …
- `ok-response-with-a-non-json-body` MUST — res.json() rejects, and the query MUST treat the rejection as a failure: it is retried and the cached session is kept.
- `ok-response-missing-user` MUST — The hook MUST resolve to null (use-status-user-011).
- `unexpected-role-or-missing-email` MUST — The hook MUST pass the value through unchanged (use-status-user-013). Role-gated callers then compare against the known …
- `sign-in-without-invalidation` MUST — If a login flow sets the cookie but does not invalidate ["status-auth-me"], the hook MUST keep returning the cached …
- `sign-out` MUST — The logout action in useStatusHeaderAuth POSTs /auth/logout and then does a full page navigation to /. That reload …
- `concurrent-consumers` MUST — Several components mounting at the same moment MUST share one request through the single key (use-status-user-009).
- `offline` MUST — While disconnected, a failed fetch is retried and the cached session is kept. After reconnecting, the query library's …

## Edge Cases

- **First load in flight**: The hook MUST return `null`, the same value as signed out (use-status-user-006). Callers that must not flash signed-out UI MUST use the session hook's `isPending` instead, as `HomeGate` and `useStatusHeaderAuth` do.
- **First load fails with nothing cached**: After 4 failed attempts the hook MUST return `null`. The doc comment covers this as "unknown", and a later refetch trigger (focus, reconnect or remount) retries the load (use-status-user-008).
- **Transient failure while signed in**: The hook MUST keep returning the cached user (use-status-user-007). A 5xx from the proxy, a deploy restart or a network blip MUST NOT sign the user out.
- **Backend returns 401 or 403**: This is treated like any other non-OK status. The query function MUST throw, and the cached session MUST be kept. The source relies on the backend never sending 401 on this route, so this client has no path that turns an auth error into a sign-out.
- **OK response with a non-JSON body**: `res.json()` rejects, and the query MUST treat the rejection as a failure: it is retried and the cached session is kept.
- **OK response missing `user`**: The hook MUST resolve to `null` (use-status-user-011).
- **Unexpected `role` or missing `email`**: The hook MUST pass the value through unchanged (use-status-user-013). Role-gated callers then compare against the known values, so an unknown role matches neither `"admin"` nor `"viewer"`.
- **Sign-in without invalidation**: If a login flow sets the cookie but does not invalidate `["status-auth-me"]`, the hook MUST keep returning the cached `null` until the 60,000 ms fresh window ends and a refetch trigger fires.
- **Sign-out**: The logout action in `useStatusHeaderAuth` POSTs `/auth/logout` and then does a full page navigation to `/`. That reload discards the cache, so the next load MUST return `null`. This hook itself never clears the cache.
- **Concurrent consumers**: Several components mounting at the same moment MUST share one request through the single key (use-status-user-009).
- **Offline**: While disconnected, a failed fetch is retried and the cached session is kept. After reconnecting, the query library's reconnect trigger MUST refetch a stale session.
- **No timeout or cancellation**: The query function passes no abort signal and sets no timeout. A hung request stays pending until the browser gives up, and the hook keeps returning its current value meanwhile.
