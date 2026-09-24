---
id: ae44bde0-fcb3-49ff-9c8e-83ca6d3c5f69
title: Status Server
domain: agentictoolkit://recipes/status-server-src
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: HTTP API server for monitoring deployment health with periodic status checks,
  single-flight scheduling, and cached status summaries.
platforms:
- typescript
- web
tags:
- http-api
- monitoring
- scheduler
- caching
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a backend HTTP server with no visual component.

## States

Not applicable — this is a backend HTTP server with no visual states. Runtime state machines (scheduler idle/running/wedged) are documented in Behavioral Requirements.

## Accessibility

Not applicable — this is a backend HTTP server with no user-facing accessibility concerns.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vector-001 | health-endpoint | Scheduler has completed a cycle within freshness window; call `GET /health` | Status 200, response `{status: 'ok', lastCycleAt: <ISO string>}`; with no scheduler injected the same 200 carries `lastCycleAt: null` |
| vector-002 | health-endpoint | Scheduler started but has not completed a cycle within the staleness window; call `GET /health` | Status 503, response `{status: 'stale', lastCycleAt: <last completed ISO string, or null if none>}` |
| vector-003 | version-endpoint | Call `GET /version` | Status 200, response `{name: 'status-backend', version: <config.appVersion>}` |
| vector-004 | status-summary-endpoint, status-summary-caching | Call `GET /public/status-summary`, change health data, call again within 30 seconds, then again after 31 seconds | Second response equals the first (same `generatedAt`, old status); third reflects the new state |
| vector-005 | status-summary-endpoint | Call `GET /public/status-summary` with unknown status (all services status unknown); buildStatusSummary creates snapshot with services.length > 0 but all services.status === 'unknown' | Response status is `'unknown'` (not `'healthy'`), `operational: false` |
| vector-006 | public-path-cors, status-summary-endpoint | Call `GET /public/status-summary` with arbitrary `Origin` header | `Access-Control-Allow-Origin` equals the request's `Origin` value |
| vector-007 | authenticated-path-cors | Call `GET /live` with `Origin: https://evil.example.com` not in `config.corsAllowedHosts` | Response has no `Access-Control-Allow-Origin` header |
| vector-008 | body-size-limit | POST a 1,048,577-byte body (1 byte over limit) to the pre-auth `POST /hooks/vercel` | Status 413, response `{error: {message: 'request body too large'}}` |
| vector-009 | scheduler-single-flight | Call `runNow()` with a cycle that stays open, then call `runNow()` again before it settles | Second call resolves false (coalesced); after the cycle settles the first resolves true; the cycle ran once |
| vector-010 | scheduler-watchdog | `intervalMs: 1000`, `cycleTimeoutMs: 5000`; the boot cycle hangs forever, later cycles resolve; advance 4s, then 4s more | After 4s the cycle ran once and `lastCycleAt()` is null; after 8s the watchdog has logged and released the lock, a later tick ran a fresh cycle, and `lastCycleAt()` is non-null |

## Edge Cases

- **Empty service list**: When storage contains zero services (snapshot.services.length === 0), buildStatusSummary counts total as 0 and all sub-counts as 0; the all-unknown override does not apply (it requires `total > 0`), so status is the snapshot's `overall` — with no services and no open issues that is `'healthy'` with `operational: true` and empty `downSites`.
- **No scheduler provided**: When `opts.scheduler` is undefined, `/health` MUST return 200 `{status: 'ok', lastCycleAt: null}` (no staleness signal), `cronRoutes` is not mounted, and `streamRoutes` receives `undefined` (its schedule frame reports a null next cycle and `POST /live/check` answers 503 `no scheduler`).
- **Concurrent status-summary builds during cache miss**: When two or more simultaneous requests arrive after cache expiry, `cachedSingleFlight` MUST ensure only one `buildStatusSummary` call runs; all requests MUST wait and share the result.
- **Origin parsing failure**: When an origin is not in the list verbatim and cannot be parsed as a URL, isAllowedOrigin MUST catch the parse error and return false, so no `Access-Control-Allow-Origin` is sent.
- **Cycle runs past watchdog timeout**: When a cycle is still running at watchdog expiry, the watchdog releases the single-flight lock WITHOUT waiting for the cycle to complete; a new tick can then start even though the first cycle is still in flight. When the abandoned cycle settles, its `release` is a no-op because `cycleSeq` has moved on, so it cannot free the newer cycle's lock; if it resolves, it does set `lastCycleAt` (see the open question on abandoned-cycle-last-cycle-at).
- **Manual run during interval tick**: When `runNow()` is called during a scheduled interval tick, MUST coalesce: return false if a cycle was already in flight (whether from the interval or a previous manual call), else run a manual cycle and return true; in both cases a started scheduler re-anchors the grid when `runNow()` resolves.
- **Cycle error on boot**: When the initial cycle on `start()` throws an error, the error MUST be caught and logged; the scheduler MUST continue and not crash; `lastCycleAt()` remains null until a cycle completes successfully.
- **Very long cycle followed by rapid runNow**: If a cycle takes 4 minutes and finishes, then `runNow()` is called immediately, re-anchoring happens and the next automatic tick is a full interval from the runNow completion, not from the original boot anchor.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `AppDeps.storage` | `Storage` | Required | Pluggable data store abstraction for reading deployment, service, and issue status. |
| `AppDeps.scheduler` | `Scheduler \| undefined` | undefined | Optional periodic monitoring loop. If omitted, `/health` returns `lastCycleAt: null` and staleness is not signaled. |
| `AppDeps.config` | `StatusConfig` | Required | Configuration object passed to every route factory; `createApp` itself reads `appVersion` and `corsAllowedHosts`. |
| `AppDeps.auth` | `AuthGate` | Required | Authentication port implementing principal resolution and tier checks (e.g., view, admin). |
| `AppDeps.seed` | `SeedRoster \| undefined` | `[]` | Optional seed roster (`readonly SeedEndpoint[]`) that `POST /config/seed` creates in an empty configuration; omitted or empty, seed creates only the provider connections. |
| `createScheduler.intervalMs` | `number` | Required | Interval in milliseconds between automatic monitoring cycle ticks. |
| `createScheduler.cycleTimeoutMs` | `number` | `max(3 * intervalMs, 120000)` | Hard timeout in milliseconds for a single cycle. If exceeded, the watchdog releases the lock. Defaults to 3× interval, floored at 2 minutes. |
| `createScheduler.staleAfterMs` | `number` | `max(5 * intervalMs, 300000)` | Duration in milliseconds without a completed cycle before the loop is marked stale. Defaults to 5× interval, floored at 5 minutes. |
| `STATUS_SUMMARY_CACHE_MS` | `30000` | Hardcoded | TTL in milliseconds for the `/public/status-summary` response cache. Public landing page headline status may lag reality by up to this window. |
| `MAX_BODY_BYTES` | `1048576` | Hardcoded | Exported global request body size limit in bytes (1 MB). Applied after CORS and before any route handler via `bodyLimit` middleware. |

## Deep Linking

Not applicable — this is a backend HTTP server without client-side deep linking concerns.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| Error message: `request body too large` | Hardcoded en | HTTP 413 response when body exceeds MAX_BODY_BYTES |
| Error message: `Internal Server Error` | Hardcoded en | HTTP 500 response when an unhandled non-HTTP error occurs |
| Cycle timeout error log | `cycle exceeded {{cycleTimeoutMs}}ms — abandoning it and releasing the scheduler (self-heal)` | Console error when watchdog fires |
| Cycle failure error log | `cycle failed: {{error}}` | Console error when cycle throws |

## Accessibility Options

Not applicable — this is a backend HTTP server with no user-facing accessibility options.

## Feature Flags

Not applicable — the server's core features (health, version, status, auth) are not behind feature flags in the given source.

## Analytics

Not applicable — the given source does not implement event tracking or analytics calls.

## Privacy

**Data collected**: No PII collected by the server itself. The `/public/status-summary` endpoint exposes aggregated deployment status (service names, down/degraded indicators) and timestamps from open issues; this data is intentionally public.

**Storage**: Status data is persisted via the pluggable `Storage` interface; the server does not specify where or how storage is implemented.

**Transmission**: HTTP responses are sent over CORS-gated HTTPS (by convention; the server does not enforce TLS itself). Authenticated routes pass through the `AuthGate` port, which owns the credential mechanism (the default adapter lives in `auth/default-adapter`).

**Retention**: Retention policy is determined by the `Storage` implementation; the server does not enforce data deletion or expiry.

## Logging

All logging is plain `console.error`; there is no logger subsystem or category.

| Event | Level | Message | When |
|-------|-------|---------|------|
| Cycle timeout exceeded | error | `cycle exceeded ${cycleTimeoutMs}ms — abandoning it and releasing the scheduler (self-heal)` | Watchdog timer fires during cycle execution |
| Cycle execution error | error | `cycle failed:` followed by the error as a second argument | The cycle callback throws an unhandled error |
| Unhandled HTTP error | error | Full error object logged to console | A non-HTTPException is caught by the global error handler |

## Platform Notes

- **TypeScript/Node.js**: Source uses OpenAPIHono (a type-safe HTTP framework) with Hono middleware. CORS, body-limit, and error handling are middleware layers. Single-flight caching uses a custom utility (`cachedSingleFlight` from `@agentic-toolkit/deploy-platform/util`). Scheduler uses `setInterval` and `setTimeout` for interval-based and watchdog timing. Storage is an abstract interface (`Storage` port), allowing pluggable implementations (e.g., Drizzle ORM).
- **Swift/Concurrency**: A port would use a server framework for HTTP (the source is a server, not a client), GCD or Swift Concurrency actors for scheduling, and a persistent store (CoreData or similar) for storage. Route registration would map to async/await handler functions. Single-flight would use an actor-protected boolean flag. Staleness tracking would use optional `Date` instead of `Date | null`.
- **Kotlin/Coroutines**: A port would use a server framework such as Ktor server for HTTP, `CoroutineScope` with structured concurrency for scheduling, and Room or SQLite for storage. Watchdog would use `withTimeout` or `launch` with `cancel()`. Single-flight would use a Mutex or atomic boolean.
- **C#/.NET**: A port would use ASP.NET Core for HTTP, `Timer` or `BackgroundService` for scheduling, and Entity Framework Core for storage. Single-flight would use `SemaphoreSlim` or a flag with lock. Staleness tracking would use `DateTime?`. CORS middleware is built into ASP.NET Core.
- **WinUI 3**: Not applicable — status-server is a backend HTTP server, not a UI component. A WinUI 3 client would call the HTTP API using `HttpClient` to fetch health and status summaries.

## Design Decisions

**Decision**: Single-flight caching on the public `/public/status-summary` endpoint.

**Rationale**: The public status endpoint is the only route anonymous traffic can reach. A cache miss triggers an expensive `buildStatusSummary` call (one full snapshot read + aggregation). Without single-flight, a burst of requests landing on an expired cache would start N concurrent expensive builds, causing a thundering herd. Single-flight ensures only one build per cache window, protecting the database from O(request rate) load spikes.

**Approved**: pending

---

**Decision**: Grid-based periodic scheduling with re-anchoring after manual runs.

**Rationale**: Periodic status checks should fire on a predictable cadence so client-side countdown timers are accurate. When a manual `runNow()` resolves (which may take much longer than the interval), re-anchoring the timer ensures the next automatic tick is a full interval away from the completion, rather than firing moments later and bunching cycles. This keeps the periodic grid stable even when manual runs are long.

**Approved**: pending

---

**Decision**: Watchdog timer with cycle abandonment rather than blocking.

**Rationale**: Monitoring loops must never wedge. A single un-timed-out async operation deep in a cycle can cause `inFlight` to remain true forever, causing all later ticks to no-op while the process continues serving ever-staler data. The watchdog hard-caps cycle duration (3× interval, minimum 2 minutes) and releases the lock, allowing the loop to continue. The abandoned cycle is left to settle asynchronously, but does not hold future ticks hostage. This was the design response to a 32-hour outage where a deployed loop remained wedged.

**Approved**: pending

---

**Decision**: No automatic retry or backoff on cycle failures.

**Rationale**: Each cycle is try/caught; errors are logged to the console but do not crash the process or block future ticks. Automatic retry with backoff is not implemented in the source — failed cycles simply mark the service as data-stale (`/health` returns 503 after staleness window), and the caller (a deployment platform) must decide whether to restart the process, page on-call, or wait for the next tick to succeed. This delegates retry policy to the operator, matching the code's philosophy of exposing problems rather than hiding them.

**Approved**: pending

---

**Decision**: Staleness is measured from boot timestamp before the first cycle completes.

**Rationale**: A monitoring loop that never completes a cycle should not appear healthy. If `lastCycleAt` is null (no completed cycle yet), staleness is measured from `startedAt` so the loop trips stale even with zero signal. Within the first staleness window after boot `/health` still reports `ok`; only a loop that has not completed a cycle by the end of that window reports `stale`.

**Approved**: pending

---

**Decision**: Status summary collapses to `'unknown'` (not `'healthy'`) when all services are unknown.

**Rationale**: A status page must never claim green when it can't tell. When there is at least one service and every monitored service has status `'unknown'` (e.g., before the first probe cycle), the 3-state rollup collapses to `'healthy'`. This is overridden to `'unknown'` explicitly so the public headline never shows green on zero signal. This is a deliberate contract: `operational: true` only when the overall rollup is healthy, never when it's unknown.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | reliability |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | performance |
| [api-design-conventions](agenticdevelopercookbook://compliance/access-patterns#api-design-conventions) | passed | access-patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | access-patterns |

Separation of concerns: The server is composed of modular route handlers (authRoutes, usersRoutes, reads, etc.) that are injected into `createApp`, separating business logic (each route module) from infrastructure (middleware, CORS, error handling, auth seam). Storage is an abstract interface (port), decoupling data access from the HTTP layer. The scheduler is a separate concern, injected as optional dependency and used only by specific routes (stream, health).

Unit test coverage: `test/scheduler.test.ts` covers single-flight, grid re-anchoring, the manual flag, coalescing, watchdog self-heal and staleness; `test/health.int.test.ts`, `test/status-summary.int.test.ts` and `test/body-limit.int.test.ts` cover the public routes, the summary rollup, caching, the stampede guard, CORS and the 413 cap. `isAllowedOrigin` and `isPublicPath` are module-private and exercised only through the app.

Timeout handling: The scheduler implements a hard timeout (cycleTimeoutMs) on each cycle via a watchdog timer. If a cycle exceeds the timeout, the watchdog releases the single-flight lock and logs an error, preventing the process from wedging. It does not cancel the abandoned cycle, and a late resolution still advances `lastCycleAt`, hence partial. Long-running network operations (fetch within the cycle callback) are subject to the cycle timeout, not managed independently by the server.

Error recovery: The scheduler catches all cycle errors (try/catch inside tick) and logs them; errors do not crash the process or stop future ticks. Failed cycles do not advance `lastCycleAt` (an abandoned cycle that later resolves does, contrary to its doc comment), so `/health` can detect that the last-completed timestamp is stale. The watchdog timer prevents a single hung await from breaking the loop.

Health observability: The server exposes `/health` with status and `lastCycleAt` timestamp, providing visibility into whether the monitoring loop is running and keeping up. Stale detection via `cycleStale()` signals when the loop is wedged. Errors are logged to console (see Logging section).

Caching strategy: The `/public/status-summary` endpoint uses a 30-second cache with single-flight pattern. Cache invalidation is time-based (TTL); the next `buildStatusSummary` call happens automatically after 30 seconds. `createApp` never passes `fresh`, so there is no explicit invalidation; a failed build is not cached.

API design conventions: The server follows REST conventions: GET for reads (`/health`, `/version`, `/public/status-summary`), POST/PATCH/DELETE for mutations, standard HTTP status codes (200 for success, 503 for service unavailable, 413 for payload too large, 500 for server error). The OpenAPI spec is served at `GET /doc`, behind the auth seam.

Error response handling: All HTTP errors are returned in the format `{error: {message: "..."}}` with appropriate status codes. Non-HTTP exceptions are logged and returned as 500 with message `Internal Server Error`; a failed auth resolution is 401 `Unauthorized`. The caller is responsible for parsing error responses and deciding whether to retry (e.g., 503 from `/health` indicates staleness, not a client error).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | | Initial creation |
