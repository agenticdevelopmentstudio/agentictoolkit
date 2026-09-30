<!-- leaf: implement-status-web-hooks/use-uptime--edge-cases · source: status-web-hooks-use-uptime.md -->

# useUptime

**Rules** (cite as `implement-status-web-hooks/use-uptime--edge-cases#<slug>`):

- `zero-or-negative-days` MUST
- `fractional-days` MUST
- `non-finite-days` MUST
- `large-window` MUST
- `days-mismatch` MUST
- `empty-services` MUST
- `null-percentages` MUST
- `malformed-body` MUST
- `204-response` MUST
- `server-error` MUST
- `unreachable-server` MUST
- `error-after-success` MUST
- `hung-request` MUST
- `days-change-mid-flight` MUST
- `stale-data` MUST
- `unmount` MUST

## Edge Cases

- **zero-or-negative-days**: `useUptime(0)` or a negative value MUST still fetch, sending `days=0` or `days=-5` as-is. The backend `/uptime` route (`status-server/src/routes/reads.ts`) owns the response: its `intParam` maps `0` or an unparsable value to its default of 90, and its `clamp` bounds the result to 1–365, so `-5` becomes 1; the hook surfaces whatever arrives.
- **fractional-days**: `useUptime(1.5)` MUST send `days=1.5` and cache under `["uptime", 1.5]`; the backend's `parseInt` reads it as 1, so the response `days` field is `1` while the cache key holds `1.5`.
- **non-finite-days**: `NaN` or `Infinity` MUST be sent as the literal text `days=NaN` or `days=Infinity` and cached under a key holding that value; the hook performs no numeric validation, and both callers pass the constant `90`.
- **large-window**: A `days` value above 365 MUST be sent unchanged; the backend clamps it to 365, and the hook does not compare the requested and returned `days`.
- **days-mismatch**: If the backend's `days` field differs from the requested value, the hook MUST return the body unchanged.
- **empty-services**: A successful response with `services: []` MUST resolve as data; the hook applies no emptiness check (`overallUptimePercent` then yields `null`).
- **null-percentages**: A service or day whose `uptimePercent` is `null` (the backend's value when a service has zero checks) MUST resolve unchanged; the hook does not fill or drop it.
- **malformed-body**: A body that is valid JSON but not shaped like `UptimeResponse` (for example missing `services`) MUST resolve as data unchanged; the hook performs no shape validation, and both callers guard with `data?.services ?? []`.
- **204-response**: A `204 No Content` response is `ok`, so the hook MUST call `response.json()` on the empty body, which rejects and puts the query in its error state.
- **server-error**: A non-2xx status, including the `401` the route's OpenAPI entry documents, MUST produce `Error("uptime <status>")`; retries follow the host `QueryClient` policy (React Query's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected `fetch` MUST surface as the query error with no hook-level retry, fallback data, or message rewriting; with no polling, the query stays in error until a default React Query trigger or `refetch()` runs it again.
- **error-after-success**: When a refetch fails after an earlier success, React Query MUST keep the previous `data` alongside the new `error`, so callers keep showing the last good uptime.
- **hung-request**: With no timeout or abort signal from the hook, a request that never settles MUST leave the query in its fetching state indefinitely.
- **days-change-mid-flight**: When `days` changes while a request is in flight, the new window MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new window's data.
- **stale-data**: Because the hook sets no `refetchInterval`, uptime shown on a dashboard left open and focused MUST stay at the first-loaded values until a refocus, reconnect, remount, or `refetch()` triggers a new fetch.
- **unmount**: When the last component using a given `days` unmounts, the cached result MUST remain until the host `QueryClient`'s garbage-collection time elapses.
