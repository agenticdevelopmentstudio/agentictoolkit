<!-- leaf: implement-status-server/src--part-2 · source: status-server-src.md -->

# Status Server — continued (part 2)

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

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| Error message: `request body too large` | Hardcoded en | HTTP 413 response when body exceeds MAX_BODY_BYTES |
| Error message: `Internal Server Error` | Hardcoded en | HTTP 500 response when an unhandled non-HTTP error occurs |
| Cycle timeout error log | `cycle exceeded {{cycleTimeoutMs}}ms — abandoning it and releasing the scheduler (self-heal)` | Console error when watchdog fires |
| Cycle failure error log | `cycle failed: {{error}}` | Console error when cycle throws |

## Privacy

**Data collected**: No PII collected by the server itself. The `/public/status-summary` endpoint exposes aggregated deployment status (service names, down/degraded indicators) and timestamps from open issues; this data is intentionally public.

**Storage**: Status data is persisted via the pluggable `Storage` interface; the server does not specify where or how storage is implemented.

**Transmission**: HTTP responses are sent over CORS-gated HTTPS (by convention; the server does not enforce TLS itself). Authenticated routes pass through the `AuthGate` port, which owns the credential mechanism (the default adapter lives in `auth/default-adapter`).

**Retention**: Retention policy is determined by the `Storage` implementation; the server does not enforce data deletion or expiry.

## Platform Notes

- **TypeScript/Node.js**: Source uses OpenAPIHono (a type-safe HTTP framework) with Hono middleware. CORS, body-limit, and error handling are middleware layers. Single-flight caching uses a custom utility (`cachedSingleFlight` from `@agentic-toolkit/deploy-platform/util`). Scheduler uses `setInterval` and `setTimeout` for interval-based and watchdog timing. Storage is an abstract interface (`Storage` port), allowing pluggable implementations (e.g., Drizzle ORM).
- **Swift/Concurrency**: A port would use a server framework for HTTP (the source is a server, not a client), GCD or Swift Concurrency actors for scheduling, and a persistent store (CoreData or similar) for storage. Route registration would map to async/await handler functions. Single-flight would use an actor-protected boolean flag. Staleness tracking would use optional `Date` instead of `Date | null`.
- **Kotlin/Coroutines**: A port would use a server framework such as Ktor server for HTTP, `CoroutineScope` with structured concurrency for scheduling, and Room or SQLite for storage. Watchdog would use `withTimeout` or `launch` with `cancel()`. Single-flight would use a Mutex or atomic boolean.
- **C#/.NET**: A port would use ASP.NET Core for HTTP, `Timer` or `BackgroundService` for scheduling, and Entity Framework Core for storage. Single-flight would use `SemaphoreSlim` or a flag with lock. Staleness tracking would use `DateTime?`. CORS middleware is built into ASP.NET Core.
- **WinUI 3**: The server half ports to an ASP.NET Core minimal-API host (in-process in the WinUI 3 app via `WebApplication.CreateSlimBuilder` for a local monitor, or as a standalone service); the WinUI 3 client calls it with `HttpClient`. `createApp(opts: AppDeps)` becomes a `WebApplication BuildApp(AppDeps deps)` where `AppDeps` is a record of `IStorage`, `IScheduler?`, `StatusConfig`, `IAuthGate`, and `IReadOnlyList<SeedEndpoint>` (defaulting to empty), registered in DI; `OpenAPIHono`/`createRoute`/`zod` routes become `app.MapGet`/`MapPost` with typed `Results<Ok<T>, ...>` returns and `Microsoft.AspNetCore.OpenApi` (`AddOpenApi`/`MapOpenApi`) replacing `buildOpenApiSpec` behind `GET /doc`, and each `*Routes(...)` module becomes an extension method mapping a `RouteGroupBuilder`. Keep middleware order identical: CORS via `AddCors` with a policy whose `SetIsOriginAllowed` reflects any origin for `GET`/`HEAD` on `/health`, `/version`, and `/public/*` and otherwise applies the `isAllowedOrigin` full-origin-or-`new Uri(origin).Authority` check against `CorsAllowedHosts`, with `AllowCredentials()`, methods `GET, POST, PATCH, DELETE, OPTIONS`, and headers `Authorization, Content-Type`; then the 1,048,576-byte `MAX_BODY_BYTES` limit via `KestrelServerOptions.Limits.MaxRequestBodySize` plus a small middleware that maps `BadHttpRequestException` 413 to `{error:{message:'request body too large'}}` after CORS headers are set; then an `IExceptionHandler`/`UseExceptionHandler` that returns the exception's own status and message for a ported `HttpException` type and logs via `ILogger` and returns `Internal Server Error`/500 for anything else. The auth seam stays registration order: map `/health`, `/version`, `/public/status-summary`, auth, hooks, and `POST /auth/device` + `/auth/device/token` on an unauthenticated group, then everything else on a group with an endpoint filter (or `AddAuthentication` scheme wrapping `IAuthGate.Authenticate`) that stores tier/user/token in `HttpContext.Items` or claims and returns 401 `Unauthorized` on null, preserving the MCP/view-tier-before-`requireAdmin` and tokens/device-approval-before-users ordering. `cachedSingleFlight` with the 30-second `STATUS_SUMMARY_CACHE_MS` becomes a per-app cache holding one shared `Task<StatusSummary>` guarded by `SemaphoreSlim`/`Lazy<Task<T>>` (or `HybridCache.GetOrCreateAsync`), clearing the in-flight task on failure so the next request retries; `buildStatusSummary` stays private and keeps the one-`BuildSnapshot` call, four-bucket partition, all-unknown rule, and endpoint-failures-then-issues `downSites` ordering. `createScheduler` becomes an `IScheduler` implemented as a `BackgroundService`/`IHostedService` driving a `PeriodicTimer` (restart it to re-anchor the grid in `RunNow`/`RunNowDetached`), with `Interlocked.CompareExchange` on an `int inFlight` flag plus a `cycleSeq` counter replacing the event-loop guarantee, since .NET runs continuations on the thread pool; the watchdog becomes `Task.WhenAny(cycleTask, Task.Delay(cycleTimeoutMs))` that logs and releases the lock without awaiting the abandoned cycle, `Func<CycleContext, Task>` carries `Manual`, timestamps are `DateTimeOffset?` read through `TimeProvider` for testability, and `CycleStale`/`NextCycleAt` keep the exact default windows (3x interval floored at 2 minutes, 5x floored at 5 minutes) and grid-anchor math. On the WinUI 3 side, poll `/health` and `/public/status-summary` with a shared `HttpClient` (`GetFromJsonAsync` into records mirroring the `types.ts` wire types) from a `DispatcherQueueTimer` or `PeriodicTimer` loop, `await` off the UI thread, and marshal results back with `DispatcherQueue.TryEnqueue` before updating bound view models; the SSE stream route maps to reading `HttpClient.GetStreamAsync` line by line.

