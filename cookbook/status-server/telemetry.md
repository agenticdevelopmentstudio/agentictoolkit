---
id: a7c2b9e1-5d4f-4a2c-9e6f-8b3a1c5d7e2f
title: Status Server Telemetry
domain: agentictoolkit://cookbook/status-server/telemetry
type: ingredient
version: 1.0.1
status: review
language: en
created: 2026-09-24
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Telemetry data collection and persistence abstraction for production visibility
  dashboards
platforms:
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a data abstraction layer, not a visual component.

## States

Not applicable — this is a data abstraction layer, not a visual component.

## Accessibility

Not applicable — this is a data abstraction layer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|----|----|----|
| telemetry-001 | collect-operation, collect-fetcher-call, collect-success-result | Fetcher returning `{ ok: true, items: [{id: '1', issueKey: 'GT-1', project: 'web', title: 'Error', culprit: null, level: 'error', count: 5, userCount: 2, firstSeen: '2026-09-24T00:00:00Z', lastSeen: '2026-09-24T12:00:00Z', permalink: 'https://sentry.io/...' }], complete: true }` and a Store that appends | Collect invokes fetcher and store; returns `{ ok: true, count: 1 }` |
| telemetry-002 | collect-fetch-failure-handling | Fetcher returning `{ ok: false, items: [], complete: true }` | Collect does not call store.save(); returns `{ ok: false, count: 0 }` |
| telemetry-003 | collect-fetch-success, collect-success-result | Fetcher returning `{ ok: true, items: [item1, item2], complete: false }` | Collect returns `{ ok: true, count: 2 }` and passes `{ complete: false }` to store.save() |
| telemetry-004 | collect-fetch-success | Fetcher returning `{ ok: true, items: [item1] }` with `complete` omitted | `store.save` receives `([item1], { complete: true })`; collect returns `{ ok: true, count: 1 }` |
| telemetry-005 | collect-telemetry-concurrent | Configuration with both GlitchTip and PostHog; both fetchers return `ok: true` with items | Both fetchers are invoked concurrently; both stores receive save() calls; collectTelemetry returns without error |
| telemetry-006 | collect-telemetry-guarded | Configuration with all three GlitchTip credentials set, `POSTHOG_API_KEY` empty | Errors collect runs; analytics collect is not called; only the errors store receives `save()` |
| telemetry-007 | collect-telemetry-fail-soft | Both providers configured; `storage.telemetry.errors.save` rejects; analytics poll succeeds | `"[telemetry] errors collection failed"` logged; analytics collection completes; recordObservations receives `{ source: 'glitchtip', configured: true, reachable: false }`; collectTelemetry resolves |
| telemetry-008 | telemetry-snapshot-structure | Call `emptySnapshot()` | Returns `{ generatedAt: "", errors: [], analytics: [] }` |
| telemetry-009 | complete-flag-semantics | Fetcher returns `{ ok: true, items: [item1], complete: false }` to a reconciling store | `store.save` receives `([item1], { complete: false })` unchanged; honoring it is the store's job |
| telemetry-010 | collect-telemetry-observations | collectTelemetry called with both providers configured and reachable | recordObservations is called with `{ source: 'glitchtip', configured: true, reachable: true }` |

## Edge Cases

- **Empty items array**: When a fetcher returns `ok: true` with an empty `items` array, `collect` MUST call `store.save([], { complete })` and return `{ ok: true, count: 0 }`, allowing stores to interpret emptiness as "no current issues" (if complete) or "no data this page" (if incomplete).
- **Null and undefined complete flag**: If a fetcher omits `complete`, `collect` MUST default it to `true` before passing to `store.save()`.
- **Fetcher network timeout**: The GlitchTip and PostHog fetchers catch their own timeouts and HTTP failures, log them with `console.warn`, and return `ok: false`. Any rejection that still escapes `collect()` is caught by the `.catch` on that stream's promise in `collectTelemetry`, logged, and not re-thrown; the other stream continues.
- **Store persistence failure**: If `store.save()` rejects, `collect()` rejects with that error and never returns a count. In `collectTelemetry` the stream's `.catch` logs it; for the errors stream this also records GlitchTip `reachable: false`, even though the provider answered.
- **Unconfigured provider**: If any of a provider's three credentials is unset or empty, `collectTelemetry` MUST skip calling `collect()` for that stream. For GlitchTip it still records `{ source: "glitchtip", configured: false, reachable: true }` (unconfigured is not unreachable); an unconfigured PostHog records nothing.
- **Concurrent provider outages**: If both streams fail concurrently, each failure is handled independently; `collectTelemetry` still records its one GlitchTip observation with `reachable: false`, and no observation for PostHog.
- **Observation recording failure**: If `recordObservations()` throws, `collectTelemetry` MUST catch it, log it, and MUST NOT abort the overall cycle; the platform-health row is not recorded for this cycle; telemetry collection has already finished by then and `collectTelemetry` resolves normally.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusConfig.credentials.GLITCHTIP_URL` | string or undefined | undefined | Base URL of GlitchTip instance; unset or empty = unconfigured |
| `StatusConfig.credentials.GLITCHTIP_API_TOKEN` | string or undefined | undefined | GlitchTip API token; unset or empty = unconfigured |
| `StatusConfig.credentials.GLITCHTIP_ORG` | string or undefined | undefined | GlitchTip organization identifier; unset or empty = unconfigured |
| `StatusConfig.credentials.POSTHOG_HOST` | string or undefined | undefined | PostHog host URL; unset or empty = unconfigured |
| `StatusConfig.credentials.POSTHOG_API_KEY` | string or undefined | undefined | PostHog API key; unset or empty = unconfigured |
| `StatusConfig.credentials.POSTHOG_PROJECT_ID` | string or undefined | undefined | PostHog project identifier; unset or empty = unconfigured |

## Deep Linking

Not applicable: this is server-side logic with no URL routing or deep-link surface.

## Localization

Not applicable: telemetry data is not user-facing; error logs use hardcoded English category prefixes (e.g., `"[telemetry] errors collection failed"`).

## Accessibility Options

Not applicable: this is server-side data logic with no visual or interactive surface.

## Feature Flags

Not applicable: feature control is handled at the configuration layer (provider credentials presence/absence); this module has no feature-flag consumption.

## Analytics

Not applicable: this module collects telemetry for external dashboards; it does not emit events itself.

## Privacy

`buildErrorsFetcher` and `buildAnalyticsFetcher` read the `GLITCHTIP_API_TOKEN` and `POSTHOG_API_KEY` secrets from `StatusConfig.credentials` and pass them only to the provider fetchers; this module never logs or persists them, though its `console.error` calls log caught error objects as-is. Analytics metrics are anonymous aggregates, and ErrorDTO carries only a `userCount`, not user identities. Credential storage belongs to `StatusConfig` and the environment.

## Logging

Subsystem: (no fixed subsystem; uses `console.error()`)

| Event | Level | Message |
|-------|-------|---------|
| Errors fetcher collection failure | error | `"[telemetry] errors collection failed"` |
| Analytics fetcher collection failure | error | `"[telemetry] analytics collection failed"` |
| Platform health observation recording failure | error | `"[telemetry] recording GlitchTip platform health failed"` |

## Platform Notes

- **Web (TypeScript)**: Implemented in `packages/web/packages/status-server/src/telemetry/` using `async/await` and `Promise.all()` for concurrency. Fetchers are type-parameterized interfaces; concrete adapters (GlitchTip, PostHog) are wired at the composition root (`server.ts`). Stores are opaque to this module; they are chosen at the storage composition root (`../libsql/index.ts`), implemented in `../libsql/stores/telemetry-store.ts`, and handed in via `Storage.telemetry`.
- **Windows / .NET (WinUI 3)**: Use `Task` and `Task.WhenAll()` for concurrent polling. Define `IFetcher<T>` and `IStore<T>` as generic interfaces with `Task<FetchResult<T>>` and `Task` return types. Concrete fetchers use a shared `HttpClient` for provider requests. Use `System.Collections.Generic.List<T>` for item collections. Error logging via `System.Diagnostics.Debug.WriteLine()` or a logger interface. Configuration via dependency injection of a `IStatusConfig` instance.
- **iOS / Swift**: Use `async/await` and `Task.withTaskGroup()` for concurrent fetching. Define `Fetcher` and `Store` as protocols with async methods. Implement fetchers using `URLSession`. Errors caught via `do/catch`; platform health recorded via the Storage layer's async methods. Configuration passed as a struct to the composition root.
- **Android / Kotlin**: Use coroutines and `coroutineScope { ... }` to launch concurrent `async { ... }` blocks. Define `Fetcher<T>` and `Store<T>` as interfaces with suspend functions. Implement via `OkHttpClient` for networking. Errors caught with `try/catch` in `runBlocking()` or within a coroutine context. Configuration injected via Hilt or a service locator.
- **Python**: Use `asyncio.gather()` for concurrent polling. Define `Fetcher` and `Store` as abstract base classes with async methods. Implement fetchers using `aiohttp`. Errors logged via the `logging` module. Configuration as a dataclass or dict.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/telemetry/collect.ts` |
| web | `packages/web/packages/status-server/src/telemetry/ports.ts` |
| web | `packages/web/packages/status-server/src/telemetry/server.ts` |
| web | `packages/web/packages/status-server/src/telemetry/types.ts` |

## Design Decisions

**Decision**: A failed provider poll (ok:false) is never persisted, and the Store is never called.

**Rationale**: This prevents transient provider outages from overwriting known-good data with an empty set. Downstream logic (error rules, trend tracking) can rely on `last_seen` only advancing when new data actually arrives. A blind spot (provider unreachable) is tracked separately via platform-health observations, not by sweeping historical records.

**Approved**: pending

---

**Decision**: The `complete` flag is threaded through `collect()` uninterpreted and passed to `store.save()` for the store to decide how to use it.

**Rationale**: Appending stores (e.g., trend tables) ignore `complete` because new records never conflict. Reconciling stores (e.g., current-issue tables) MUST respect `complete: false` to avoid false resolution of issues not in the current page. By making the distinction explicit at the interface level, we prevent a paginating fetcher from accidentally wiping unseen items.

**Approved**: pending

---

**Decision**: `collectTelemetry()` polls errors and analytics concurrently via `Promise.all()`, not serially.

**Rationale**: Polling both providers serially meant the cycle's duration equaled the sum of both timeouts, which, stacked on the deploy polls, helped blow the scheduler's cycle budget and trigger container restarts. Concurrent polling reduces the critical path to the slower provider's timeout alone.

**Approved**: pending

---

**Decision**: Unconfigured providers (missing credentials) are skipped, and the GlitchTip platform-health observation records `configured: false, reachable: true`.

**Rationale**: Unconfigured is not the same as unreachable — nothing was asked, so nothing failed. Recording `configured: false` tells downstream that the feature is off (e.g., GlitchTip integration disabled), allowing the status dashboard to distinguish between "we're not listening to this provider" and "we're listening but it's down". An absent observation row after removing env vars would leave a stale `configured: true` behind.

**Approved**: pending

---

**Decision**: Provider collection failures are caught individually and do not abort the cycle; each logs to `console.error()` and the `collectTelemetry` function continues.

**Rationale**: A provider outage (GlitchTip down, network unreachable) MUST NOT prevent analytics collection or platform-health recording. The fail-soft pattern ensures one provider's problems are isolated, and the GlitchTip platform-health row signals an errors-provider outage to downstream rules; an analytics failure is visible only in the logs.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |

**Separation of Concerns**: The `collect()` abstraction decouples fetching (provider API calls) from persistence (storage strategies). Each of `Fetcher`, `Store`, and `collectTelemetry`'s orchestration concerns is isolated behind an interface. Concrete adapters (GlitchTip fetcher, SQLite store, PostHog fetcher) are wired only at the composition root (`server.ts`), allowing tests and deployments to swap implementations without changing the core logic.

**Unit Test Coverage**: No test in the status-server package imports `collect`, `collectTelemetry`, `buildErrorsFetcher`, `buildAnalyticsFetcher` or `emptySnapshot`. Adjacent tests cover the GlitchTip fetcher, the errors store, and the HTTP telemetry routes, but the ok:false no-persist rule, `complete` defaulting, the configuration guards, fail-soft handling and the GlitchTip observation are untested at this layer.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | | Initial creation |
