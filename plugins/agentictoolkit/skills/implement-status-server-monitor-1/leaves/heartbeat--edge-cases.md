<!-- leaf: implement-status-server-monitor-1/heartbeat--edge-cases · source: status-server-monitor-heartbeat.md -->

# Status Server Monitor Heartbeat

**Rules** (cite as `implement-status-server-monitor-1/heartbeat--edge-cases#<slug>`):

- `null-and-empty-input` MUST — url of null or '' MUST no-op with no network call (noop-null-or-empty-url); this is the type's own documented range …
- `boundary-values` SHOULD — the 5,000ms AbortSignal.timeout deadline is a wall-clock boundary this file cannot make deterministic on its own; a …
- `concurrent-access` MUST — pingHeartbeat holds no module-level mutable state (unlike alerts.ts's queue), so two or more concurrent or overlapping …
- `error-states` MUST — a non-2xx response is logged and treated as a failed check-in without throwing (non-2xx-logged-not-thrown) — MUST. A …
- `offline-disconnected-state` MUST — loss of connectivity to the check-in URL mid-request is indistinguishable from any other network failure this file …

## Edge Cases

- **Null and empty input**: `url` of `null` or `''` MUST no-op with no network call (noop-null-or-empty-url); this is the type's own documented range (`string | null`) plus JavaScript's falsy-string coercion, not a validation gap. A non-empty but malformed `url` string (e.g. `'not a url'`) is not specially checked by this file — `fetch` itself throws synchronously constructing the request, and that throw occurs inside the same `try` block as the `await fetch(...)` call, so it is caught and logged exactly like any other network failure (network-failure-logged-not-thrown) — MUST.
- **Boundary values**: the 5,000ms `AbortSignal.timeout` deadline is a wall-clock boundary this file cannot make deterministic on its own; a response that settles at exactly 5,000ms is a race between the response and the abort, a property of `AbortSignal.timeout` itself rather than a guarantee this file makes — SHOULD be treated as "may or may not abort" rather than a precise cutoff.
- **Concurrent access**: `pingHeartbeat` holds no module-level mutable state (unlike `alerts.ts`'s queue), so two or more concurrent or overlapping calls simply run independent `fetch` calls with independent `AbortSignal` instances; neither the outcome nor the logging of one call can affect another (independent-per-call-no-shared-state) — MUST. Nothing in this file prevents a caller from invoking it concurrently with itself; the sole real caller, `cycle-runner.ts`, only ever calls it once per full sync and only after the rest of that sync's phase has completed, which is a fact about that caller, external to this file.
- **Error states**: a non-2xx response is logged and treated as a failed check-in without throwing (non-2xx-logged-not-thrown) — MUST. A rejected `fetch` — a DNS failure, a connection refused, a TLS error, or the 5,000ms abort firing — is caught and logged identically via the same `catch` block, with no distinction made between a genuine network failure and a self-inflicted timeout (network-failure-logged-not-thrown) — MUST.
- **Offline / disconnected state**: loss of connectivity to the check-in URL mid-request is indistinguishable from any other network failure this file handles — it folds into the same `catch` block, logged once, with no retry and no backoff of any kind. The only recovery path is the next full sync (per the module's own header comment, roughly every ~5 minutes) calling `pingHeartbeat` again from scratch; that cadence is decided entirely by the caller (`cycle-runner.ts`, `index.ts`/`scheduler.ts`), external to this file — MUST.
