<!-- leaf: implement-status-web-hooks/use-config-status--edge-cases · source: status-web-hooks-use-config-status.md -->

# useConfigStatus

**Rules** (cite as `implement-status-web-hooks/use-config-status--edge-cases#<slug>`):

- `classification-pending` MUST — While the classification query has not resolved, status MUST be EMPTY_STATUS even though the endpoint axis could be …
- `classification-failed` MUST — status MUST stay EMPTY_STATUS (both axes zero) while error carries the failure and configure stays populated (MUST).
- `roster-failed-classification-succeeded` MUST — configure is undefined, status is EMPTY_STATUS, and error is the roster error (MUST).
- `both-failed` MUST — Only the roster error is returned in error; the classification error is dropped from this hook's result but remains on …
- `empty-rosters` MUST — Four empty arrays with a loaded classification MUST yield unconfiguredSites: [] and counts.sites: 0; project counts …
- `empty-classification` MUST — pending, addable and noDomain all empty MUST yield counts.projects: 0, noDomainProjects: 0 and an empty …
- `null-or-unknown-platform-on-a-pending-project` MUST — null MUST tally under the key ""; an unrecognized string MUST tally under itself unchanged (MUST).
- `malformed-server-body` MUST — The classification response is cast, not validated (r.json() as Promise<UnconfiguredResponse> in fetchUnconfigured); a …
- `disabled-consumer-with-warm-cache` MUST — With enabled: false and another enabled consumer having populated both keys, this consumer MUST return the full model …
- `concurrent-callers` MUST — JavaScript runs single-threaded; concurrent mounts share one in-flight query per key through react-query deduplication, …
- `offline-unreachable-server` MUST — Each failing read rejects its query and surfaces through error per the precedence rule; the hook adds no retry or …
- `cancellation` MUST — The hook does not cancel in-flight reads on unmount or disable; cancellation, if any, is react-query's own behavior …

## Edge Cases

- **Classification pending**: While the classification query has not resolved, `status` MUST be `EMPTY_STATUS` even though the endpoint axis could be computed from loaded rosters; `isLoading` is `false` and `error` is `undefined`, so the hook gives no signal distinguishing "classification still loading" from "zero gaps" (MUST, as implemented).
- **Classification failed**: `status` MUST stay `EMPTY_STATUS` (both axes zero) while `error` carries the failure and `configure` stays populated (MUST).
- **Roster failed, classification succeeded**: `configure` is `undefined`, `status` is `EMPTY_STATUS`, and `error` is the roster error (MUST).
- **Both failed**: Only the roster error is returned in `error`; the classification error is dropped from this hook's result but remains on its own query in the cache (MUST).
- **Empty rosters**: Four empty arrays with a loaded classification MUST yield `unconfiguredSites: []` and `counts.sites: 0`; project counts still come from the server (MUST).
- **Empty classification**: `pending`, `addable` and `noDomain` all empty MUST yield `counts.projects: 0`, `noDomainProjects: 0` and an empty `unmonitoredByPlatform` map (MUST).
- **Null or unknown platform on a pending project**: `null` MUST tally under the key `""`; an unrecognized string MUST tally under itself unchanged (MUST).
- **Malformed server body**: The classification response is cast, not validated (`r.json() as Promise<UnconfiguredResponse>` in `fetchUnconfigured`); a body missing `pending` or `noDomain` makes `buildStatus` throw during render when it reads `.length` or iterates. This is a fact of the source; the response shape is owned by the backend route `GET /deploy-projects/unconfigured` (MUST, as implemented).
- **Disabled consumer with warm cache**: With `enabled: false` and another enabled consumer having populated both keys, this consumer MUST return the full model from cache (MUST).
- **Concurrent callers**: JavaScript runs single-threaded; concurrent mounts share one in-flight query per key through react-query deduplication, so there is no interleaving to order (MUST).
- **Offline / unreachable server**: Each failing read rejects its query and surfaces through `error` per the precedence rule; the hook adds no retry or timeout of its own (MUST).
- **Cancellation**: The hook does not cancel in-flight reads on unmount or disable; cancellation, if any, is react-query's own behavior (MUST, as implemented).
