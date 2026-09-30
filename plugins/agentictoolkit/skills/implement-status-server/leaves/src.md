<!-- leaf: implement-status-server/src · source: status-server-src.md -->

**Rules** (cite as `implement-status-server/src#<slug>`):

- `create-app` MUST
- `app-deps-interface` MUST
- `health-endpoint` MUST
- `version-endpoint` MUST
- `status-summary-endpoint` MUST
- `status-summary-caching` MUST
- `public-path-cors` MUST
- `authenticated-path-cors` MUST
- `body-size-limit` MUST
- `error-handler` MUST
- `auth-seam` MUST
- `route-registration-order` MUST
- `build-status-summary` MUST
- `status-rollup-logic` MUST
- `down-sites-list` MUST
- `create-scheduler` MUST
- `scheduler-interface` MUST
- `scheduler-single-flight` MUST
- `scheduler-watchdog` MUST
- `scheduler-coalescing` MUST
- `scheduler-manual-flag` MUST
- `scheduler-staleness-signal` MUST
- `scheduler-next-cycle-grid` MUST

# Status Server

## Overview

Status server is an HTTP API built on OpenAPIHono that provides real-time and historical monitoring of deployment and service health. It maintains a periodic monitoring loop via a scheduler with deadlock prevention, caches expensive status computations to prevent thundering herd on the public endpoint, and gates authenticated endpoints behind an auth middleware seam. The server is designed to run as a long-lived backend process with health-check observability.

## Behavioral Requirements

- **create-app**: MUST export `createApp(opts: AppDeps): OpenAPIHono<{Variables: AuthVars}>` that returns a configured HTTP application instance accepting the dependency injection object.
- **app-deps-interface**: Caller MUST provide `AppDeps` with fields `storage: Storage`, optional `scheduler?: Scheduler`, `config: StatusConfig`, `auth: AuthGate`, and optional `seed?: SeedRoster` (itself `readonly SeedEndpoint[]`); `createApp` passes `opts.seed ?? []` to `configRoutes`.
- **health-endpoint**: MUST expose `GET /health` returning `{status: 'ok'|'stale', lastCycleAt: string|null}` where `lastCycleAt` is `scheduler.lastCycleAt()` as an ISO string or null. It answers 503 with `status: 'stale'` only when `scheduler.cycleStale()` is true; otherwise (including when no scheduler was injected) it answers 200 with `status: 'ok'`. A stale response still carries the last completed cycle's timestamp when one exists.
- **version-endpoint**: MUST expose `GET /version` returning `{name: 'status-backend', version: string}`; the name is a hardcoded string and the version is `config.appVersion`.
- **status-summary-endpoint**: MUST expose `GET /public/status-summary` returning a cached, aggregated status object with fields `operational: boolean`, `status: 'healthy'|'degraded'|'down'|'unknown'`, `generatedAt: string`, `counts: {total, healthy, degraded, down, unknown}`, and `downSites: [{name: string, status: 'down'|'degraded', since?: string}]`.
- **status-summary-caching**: The `/public/status-summary` response MUST be cached for 30 seconds (`STATUS_SUMMARY_CACHE_MS`) via `cachedSingleFlight`, created once per `createApp` call; concurrent requests during a cache miss share one in-flight build instead of starting N builds. A failed build is never cached: the in-flight promise is cleared so the next request retries, and the rejection surfaces through the global error handler as a 500.
- **public-path-cors**: `GET` and `HEAD` requests to public paths (`/health`, `/version`, or any path starting with `/public/`) MUST accept any origin: the CORS origin callback reflects the request's `Origin` value, or returns `*` when the request has no origin. Other methods on public paths fall through to the allowlist check in authenticated-path-cors.
- **authenticated-path-cors**: All other requests MUST check `origin` against `config.corsAllowedHosts` via `isAllowedOrigin`: an empty origin is rejected; otherwise the origin matches if the full origin string is in the list, or if `new URL(origin).host` (hostname plus any port) is in the list. A matching origin is reflected; a non-matching one gets no `Access-Control-Allow-Origin`. The CORS middleware for every path sets `credentials: true`, allows methods `GET`, `POST`, `PATCH`, `DELETE`, `OPTIONS`, and allows headers `Authorization` and `Content-Type`.
- **body-size-limit**: All requests MUST be rejected with HTTP 413 and error response `{error: {message: 'request body too large'}}` when body size exceeds `MAX_BODY_BYTES` (1,048,576 bytes, exported); the `bodyLimit` middleware is registered after CORS (so a 413 still carries CORS headers) and before every route, including pre-auth ones such as `/hooks/*` that buffer the raw body.
- **error-handler**: Unhandled errors MUST be caught by the global error handler, logged with `console.error` if not an HTTPException, and returned as `{error: {message}}`: for an HTTPException the message and status are the exception's own; for any other error the message is the hardcoded `Internal Server Error` and the status is 500.
- **auth-seam**: The seam is registration order, not a path pattern. Only the routes registered before `app.use('*', requireAuth(opts.auth))` are public: `GET /health`, `GET /version`, `GET /public/status-summary`, `authRoutes`, `hooksRoutes`, and `devicePublicRoutes` (`POST /auth/device` and `POST /auth/device/token`). Every route registered after it, including `GET /doc` and the device-approval routes under `/auth/device/*`, MUST pass through `requireAuth`, which calls `AuthGate.authenticate`, sets `tier`, `user` and `token` on the context, or throws `HTTPException(401, 'Unauthorized')` when the gate resolves null.
- **route-registration-order**: MCP transport routes and view-tier reads MUST mount before `requireAdmin` middleware to allow view-tier callers to reach read-only MCP tools; `tokensRoutes` and `deviceApprovalRoutes` MUST mount before `usersRoutes` to prevent `usersRoutes` blanket `requireAdmin` at `/` from blocking view-tier token self-revoke and device approval.
- **build-status-summary**: The module-private (not exported) `buildStatusSummary(storage: Storage, config: StatusConfig)` MUST construct the summary from one `buildSnapshot` call (imported from `./routes/reads`) and return the same typed shape the `/public/status-summary` route declares, so the cache-hit and fresh paths share one type.
- **status-rollup-logic**: When building status summary, counts MUST partition services into exactly one bucket each (healthy, degraded, down, or unknown), so `total === healthy + degraded + down + unknown` by construction. Overall `status` MUST be `'unknown'` when there is at least one service and every service is unknown, so a status page never claims green on zero signal; otherwise it is the snapshot's `overall`. `operational` is true only when not all-unknown and `overall === 'healthy'`.
- **down-sites-list**: The `downSites` array MUST list endpoint failures first, then non-endpoint issues. Endpoint failures are services with status `'down'` or `'degraded'`, named `<group> · <name>` plus ` (<environment>)` when set, with `since` set to the `openedAt` of the open issue whose target is the service slug, and omitted when no such issue exists. Non-endpoint issues are open issues whose target is not a service slug, always `status: 'degraded'` with `since: openedAt`, named by the issue name plus ` (<environment>)` only when the name does not already contain the environment.
- **create-scheduler**: MUST export `createScheduler(opts: {cycle: (ctx: {manual: boolean}) => Promise<void>, intervalMs: number, cycleTimeoutMs?: number, staleAfterMs?: number}): Scheduler` that returns a scheduler instance.
- **scheduler-interface**: Scheduler MUST implement methods `start(): void`, `stop(): void`, `runNow(): Promise<boolean>`, `runNowDetached(): boolean`, `lastCycleAt(): Date|null`, `nextCycleAt(): Date|null`, and `cycleStale(): boolean`.
- **scheduler-single-flight**: Scheduler MUST NOT start a new monitoring cycle while one is already running (`inFlight` true); `runNow()` and `runNowDetached()` MUST return false when skipped because a cycle is in flight (coalesced), and interval ticks silently no-op.
- **scheduler-watchdog**: When a cycle runs, scheduler MUST start a watchdog timer (default 3× interval, minimum 2 minutes). If the cycle is still running when the watchdog fires, scheduler MUST log an error, release the single-flight lock, and allow the next tick to run WITHOUT waiting for the abandoned cycle to complete.
- **scheduler-coalescing**: When `runNow()` resolves (whether it ran a cycle or coalesced), and the scheduler is started, it MUST re-anchor the interval grid so the next automatic tick fires a full interval later. `runNowDetached()` starts the cycle without awaiting it and re-anchors immediately when it starts one; when it coalesces it returns false without re-anchoring. Neither re-arms a stopped scheduler.
- **scheduler-manual-flag**: The `cycle` callback MUST receive a context object with `manual: boolean` that is true for out-of-band manual runs and false for periodic/boot ticks; this lets cycles apply different work (e.g., full deploy sync on manual vs. cheaper periodic check).
- **scheduler-staleness-signal**: Scheduler MUST track staleness: `cycleStale()` returns true when no cycle has COMPLETED within the staleness window (default 5× interval, minimum 5 minutes, measured from the last completed cycle, or from `start()` before the first one), and false while stopped or never started. `/health` uses it to report a wedged loop as 503 instead of green.
- **scheduler-next-cycle-grid**: `nextCycleAt()` MUST return the next firing time computed from the current interval grid ANCHOR (when `start()`, `runNow()` or `runNowDetached()` last armed the timer), not from the timestamp of the last completed cycle, and MUST return null while stopped; this keeps client-side countdown counters aligned even when cycles run at variable pace.
- **abandoned-cycle-last-cycle-at**: NEEDS REVIEW: Not implemented in source. The `cycleTimeoutMs` doc comment declares that an abandoned cycle does NOT advance `lastCycleAt`, but `tick` sets `last = new Date()` after the awaited cycle resolves with no check of `cycleSeq`, so an abandoned cycle that later resolves does advance it.
- **scheduler-concurrency**: The scheduler runs on the single-threaded JS event loop; `inFlight` flips in `tick`'s first synchronous slice, so the check-then-start in `runNowDetached` cannot interleave with another caller. There is no retry, backoff or cancellation of a cycle: a thrown cycle is logged as `cycle failed:` and the next tick runs on schedule.

