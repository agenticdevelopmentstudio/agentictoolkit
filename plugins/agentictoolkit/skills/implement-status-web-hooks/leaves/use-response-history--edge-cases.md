<!-- leaf: implement-status-web-hooks/use-response-history--edge-cases · source: status-web-hooks-use-response-history.md -->

# useResponseHistory

**Rules** (cite as `implement-status-web-hooks/use-response-history--edge-cases#<slug>`):

- `zero-or-negative-hours` MUST
- `non-finite-hours` MUST
- `empty-points` MUST
- `all-null-points` MUST
- `malformed-body` MUST
- `hours-mismatch` MUST
- `204-response` MUST
- `server-error` MUST
- `unreachable-server` MUST
- `error-after-success` MUST
- `hung-request` MUST
- `hours-change-mid-flight` MUST
- `background-tab` MUST
- `unmount` MUST

## Edge Cases

- **zero-or-negative-hours**: `useResponseHistory(0)` or a negative value MUST still fetch, sending `hours=0` or `hours=-5` as-is; how the backend `/response-history` route treats it (empty series, clamping, or an error status) is owned by that route, and the hook MUST surface whichever it returns.
- **non-finite-hours**: `NaN` or `Infinity` MUST be sent as the literal text `hours=NaN` or `hours=Infinity`, and cached under a key holding that value; the hook performs no numeric validation, and its one caller only passes the finite constants from `SPANS`.
- **large-window**: The largest window the caller uses is 2,160 hours (90 days); the hook applies no upper bound of its own.
- **empty-points**: A successful response with `points: []` MUST resolve as data; the hook applies no emptiness check (`OverviewStats` separately hides the card sparkline when fewer than two non-null points exist).
- **all-null-points**: A series whose every entry is `null` MUST resolve as data unchanged; per the doc comment this means no data or all checks down in every bucket.
- **malformed-body**: A body that is valid JSON but not shaped like `ResponseHistory` (for example missing `points`) MUST resolve as data unchanged; the hook performs no shape validation, and a consumer reading `data.points` receives `undefined` (the caller's `?? []` fallback covers that case).
- **hours-mismatch**: If the backend's `hours` field differs from the requested value, the hook MUST return the body unchanged; it does not compare the two.
- **204-response**: A `204 No Content` response is `ok`, so the hook MUST call `response.json()` on the empty body, which rejects and puts the query in its error state.
- **server-error**: A non-2xx status, including the `401` the route documents, MUST produce `Error("response-history <status>")`; retries follow the host `QueryClient` policy (React Query's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected `fetch` MUST surface as the query error with no hook-level retry, fallback data, or message rewriting; the 60-second poll continues to attempt refetches while mounted.
- **error-after-success**: When a poll fails after an earlier success, React Query MUST keep the previous `data` alongside the new `error`, so the caller keeps drawing the last good series.
- **hung-request**: With no timeout or abort signal from the hook, a request that never settles MUST leave the query in its fetching state; React Query does not start the next interval refetch while one is still in flight.
- **hours-change-mid-flight**: When `hours` changes while a request is in flight, the new window MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new window's data.
- **background-tab**: Because `refetchIntervalInBackground` is not set, React Query's default MUST apply: interval refetches pause while the browser tab is hidden.
- **unmount**: When the last component using a given `hours` unmounts, interval polling for that key MUST stop; the cached result remains until the host `QueryClient`'s garbage-collection time elapses.
