<!-- leaf: implement-status-server/telemetry · source: status-server-telemetry.md -->

**Rules** (cite as `implement-status-server/telemetry#<slug>`):

- `collect-operation` MUST
- `collect-fetcher-call` MUST
- `collect-fetch-failure-handling` MUST
- `collect-fetch-success` MUST
- `collect-success-result` MUST
- `fetcher-interface` MUST
- `fetch-result-structure` MUST
- `complete-flag-semantics` MUST
- `store-interface` MUST
- `error-dto-structure` MUST
- `analytics-metric-dto-structure` MUST
- `telemetry-snapshot-structure` MUST
- `collect-telemetry-concurrent` MUST
- `collect-telemetry-guarded` MUST
- `collect-telemetry-fail-soft` MUST
- `collect-telemetry-observations` MUST
- `telemetry-source-interface` MUST
- `fetcher-building` MUST
- `error-logging` MUST

# Status Server Telemetry

## Overview

Status Server Telemetry is a trigger-agnostic collection abstraction that decouples data fetching from persistence. It composes a source (Fetcher) with a sink (Store) for each data stream (errors, analytics), allowing the same collection logic to be driven by scheduled cycles, manual refreshes, or webhooks. Failed provider polls never overwrite good data, and a GlitchTip platform-health observation records whether the errors provider is configured and reachable, so downstream error rules freeze rather than falsely recover during an outage. PostHog gets no platform-health observation.

## Behavioral Requirements

- **collect-operation**: The `collect<T>` function MUST accept a `Fetcher<T>` and a `Store<T>` as parameters.
- **collect-fetcher-call**: `collect` MUST invoke `fetcher.fetch()` exactly once per call.
- **collect-fetch-failure-handling**: If `fetcher.fetch()` returns `ok: false`, `collect` MUST NOT call `store.save()` and MUST return `{ ok: false, count: 0 }`.
- **collect-fetch-success**: If `fetcher.fetch()` returns `ok: true`, `collect` MUST call `store.save(items, { complete: complete ?? true })` where `complete` is the fetcher's `FetchResult.complete` value (defaulting to `true` if undefined).
- **collect-success-result**: When `collect` completes successfully, it MUST return `{ ok: true, count: items.length }`.
- **fetcher-interface**: A Fetcher MUST expose a `fetch()` method returning `Promise<FetchResult<T>>`.
- **fetch-result-structure**: `FetchResult<T>` MUST contain: `ok: boolean`, `items: T[]`, and optionally `complete?: boolean`.
- **complete-flag-semantics**: The `complete` flag indicates whether `items` is the provider's entire current set (`true`) or one page of a paginated response (`false`); reconciling stores MUST respect this distinction to avoid false deletions of unseen items.
- **store-interface**: A Store MUST expose `save(items: T[], opts?: { complete?: boolean }): Promise<void>` and `load(): Promise<T[]>` methods.
- **store-save-semantics**: The Store implementation determines whether `save()` appends new items (append-only) or reconciles the entire set (upsert); the `complete` flag is threaded through for stores that need it.
- **error-dto-structure**: Each ErrorDTO MUST contain: `id` (stable identity), `issueKey` (upsert key), `project`, `title`, `culprit` (nullable), `level` (nullable), `count`, `userCount`, `firstSeen` (ISO string or null), `lastSeen` (ISO string or null), `permalink` (nullable).
- **analytics-metric-dto-structure**: Each AnalyticsMetricDTO MUST contain: `metric` (string), `window` (string), `scope` (string), `value` (number), `capturedAt` (ISO string).
- **telemetry-snapshot-structure**: A TelemetrySnapshot MUST contain: `generatedAt` (string, ISO by convention), `errors: ErrorDTO[]`, `analytics: AnalyticsMetricDTO[]`. `emptySnapshot()` MUST return `{ generatedAt: "", errors: [], analytics: [] }` — its `generatedAt` is the empty string, not an ISO timestamp.
- **collect-telemetry-concurrent**: `collectTelemetry(storage, config)` MUST poll errors and analytics fetchers concurrently via `Promise.all()`.
- **collect-telemetry-guarded**: `collectTelemetry` MUST NOT call `collect` for errors unless `glitchtipConfigured(config)` (all of `GLITCHTIP_URL`, `GLITCHTIP_API_TOKEN`, `GLITCHTIP_ORG` truthy), and MUST NOT call `collect` for analytics unless `posthogConfigured(config)` (all of `POSTHOG_HOST`, `POSTHOG_API_KEY`, `POSTHOG_PROJECT_ID` truthy). Both fetchers are still constructed on every call, configured or not.
- **collect-telemetry-fail-soft**: A rejection of `collect()` for either stream MUST be caught with a promise `.catch`, logged via `console.error`, and MUST NOT abort the other stream or reject `collectTelemetry`. For the errors stream, a rejection or an `ok: false` result sets GlitchTip `reachable` to `false`; the analytics outcome (success, `ok: false`, or rejection) is discarded and feeds no observation. An `ok: false` result is not logged by `collectTelemetry` itself; the GlitchTip and PostHog fetchers log their own failed polls with `console.warn`.
- **collect-telemetry-observations**: After both streams settle, `collectTelemetry` MUST call `storage.observations.recordObservations()` exactly once with the single observation `{ source: "glitchtip", configured, reachable }`, unconditionally (including when GlitchTip is unconfigured, where `reachable` is `true`), so downstream rules learn the feature is off or blind and freeze error rows instead of falsely recovering them.
- **telemetry-source-interface**: A TelemetrySource MUST expose `get(): Promise<TelemetrySnapshot>`. This module declares the interface only; per its doc comment, a `live` source reads `/telemetry` and a `stored` source reads `/errors` plus `/analytics`, implemented outside these sources.
- **fetcher-building**: `buildErrorsFetcher(config)` and `buildAnalyticsFetcher(config)` MUST construct the GlitchTip and PostHog fetchers from the three matching `config.credentials` values at call time (not via module-level environment snapshots), so a test or a config change is never stuck with a fetcher built at import time.
- **error-logging**: A rejected errors collection, a rejected analytics collection, and a rejected `recordObservations` call MUST each be logged via `console.error(message, err)` with the fixed messages listed under Logging; the error object is logged as-is.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusConfig.credentials.GLITCHTIP_URL` | string or undefined | undefined | Base URL of GlitchTip instance; unset or empty = unconfigured |
| `StatusConfig.credentials.GLITCHTIP_API_TOKEN` | string or undefined | undefined | GlitchTip API token; unset or empty = unconfigured |
| `StatusConfig.credentials.GLITCHTIP_ORG` | string or undefined | undefined | GlitchTip organization identifier; unset or empty = unconfigured |
| `StatusConfig.credentials.POSTHOG_HOST` | string or undefined | undefined | PostHog host URL; unset or empty = unconfigured |
| `StatusConfig.credentials.POSTHOG_API_KEY` | string or undefined | undefined | PostHog API key; unset or empty = unconfigured |
| `StatusConfig.credentials.POSTHOG_PROJECT_ID` | string or undefined | undefined | PostHog project identifier; unset or empty = unconfigured |

## Privacy

`buildErrorsFetcher` and `buildAnalyticsFetcher` read the `GLITCHTIP_API_TOKEN` and `POSTHOG_API_KEY` secrets from `StatusConfig.credentials` and pass them only to the provider fetchers; this module never logs or persists them, though its `console.error` calls log caught error objects as-is. Analytics metrics are anonymous aggregates, and ErrorDTO carries only a `userCount`, not user identities. Credential storage belongs to `StatusConfig` and the environment.

## Platform Notes

- **Web (TypeScript)**: Implemented in `packages/web/packages/status-server/src/telemetry/` using `async/await` and `Promise.all()` for concurrency. Fetchers are type-parameterized interfaces; concrete adapters (GlitchTip, PostHog) are wired at the composition root (`server.ts`). Stores are opaque to this module; they are chosen at the storage composition root (`../libsql/index.ts`), implemented in `../libsql/stores/telemetry-store.ts`, and handed in via `Storage.telemetry`.
- **Windows / .NET (WinUI 3)**: Use `Task` and `Task.WhenAll()` for concurrent polling. Define `IFetcher<T>` and `IStore<T>` as generic interfaces with `Task<FetchResult<T>>` and `Task` return types. Concrete fetchers use a shared `HttpClient` for provider requests. Use `System.Collections.Generic.List<T>` for item collections. Error logging via `System.Diagnostics.Debug.WriteLine()` or a logger interface. Configuration via dependency injection of a `IStatusConfig` instance.
- **iOS / Swift**: Use `async/await` and `Task.withTaskGroup()` for concurrent fetching. Define `Fetcher` and `Store` as protocols with async methods. Implement fetchers using `URLSession`. Errors caught via `do/catch`; platform health recorded via the Storage layer's async methods. Configuration passed as a struct to the composition root.
- **Android / Kotlin**: Use coroutines and `coroutineScope { ... }` to launch concurrent `async { ... }` blocks. Define `Fetcher<T>` and `Store<T>` as interfaces with suspend functions. Implement via `OkHttpClient` for networking. Errors caught with `try/catch` in `runBlocking()` or within a coroutine context. Configuration injected via Hilt or a service locator.
- **Python**: Use `asyncio.gather()` for concurrent polling. Define `Fetcher` and `Store` as abstract base classes with async methods. Implement fetchers using `aiohttp`. Errors logged via the `logging` module. Configuration as a dataclass or dict.

