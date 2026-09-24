---
id: 4bd200d7-f9d2-4348-af53-95ea02272c79
title: useConfigStatus
domain: agentictoolkit://recipes/status-web-hooks-use-config-status
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'React hook that assembles the shared configuration-status model from two
  cached queries: local config rosters and the server''s deploy-project partition.'
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-activity-ttl
references: []
approved-by: ''
approved-date: ''
---

# useConfigStatus

## Overview

`useConfigStatus` is the single access point for configuration health in the status web app. It reads two react-query queries and folds them into one `ConfigStatus<EndpointView, DeployProject>` model (the shape defined by `@agentic-toolkit/deploy-platform/engine`), so every "configured?" surface — the Overview banner, the Config page badges, the board rail — renders the same numbers from the same cache.

The two queries are deliberately separate:

- `["configure-data"]` (`CONFIGURE_DATA_KEY`) — four local-database reads: groups, sites, integrations and all endpoints (`ConfigureData`).
- `["configure-classification"]` (`CONFIGURE_CLASSIFICATION_KEY`) — the server's classified deploy-project partition from `GET /deploy-projects/unconfigured` (`UnconfiguredResponse`), which is a live scan of Vercel, Railway and Cloudflare.

The source comment on `useConfigureData` records why: the classification used to be a fifth leg of the same `Promise.all`, and "one flaky provider took the ENTIRE config editor down with it". The module also exports `invalidateConfigQueries`, which invalidates both keys together.

## Behavioral Requirements

### Query keys and invalidation

- **configure-data-key**: The module MUST export `CONFIGURE_DATA_KEY` equal to the tuple `["configure-data"]`.
- **classification-key**: The module MUST export `CONFIGURE_CLASSIFICATION_KEY` equal to the tuple `["configure-classification"]`.
- **invalidate-both**: `invalidateConfigQueries(qc)` MUST invalidate the query under `CONFIGURE_DATA_KEY` and the query under `CONFIGURE_CLASSIFICATION_KEY`, starting both invalidations together (in parallel).
- **invalidate-result**: `invalidateConfigQueries` MUST return a `Promise<void>` that resolves to `undefined` once both invalidations have settled successfully.
- **invalidate-rejection**: If either invalidation rejects, the promise returned by `invalidateConfigQueries` MUST reject with that reason (it is a plain `Promise.all`).

### Roster query (`configure-data`)

- **roster-reads**: The roster query function MUST issue exactly four reads in parallel — `listGroups`, `listSites`, `listIntegrations` and `listAllEndpoints` from `api/monitored-sites` — each passed the `StatusApiClient` from `useStatusApi()`.
- **roster-shape**: The roster query MUST resolve to a `ConfigureData` object `{ groups, sites, integrations, endpoints }` whose four arrays are the four read results unchanged, in that field mapping.
- **roster-all-or-nothing**: If any one of the four roster reads rejects, the roster query MUST fail as a whole (no partial `ConfigureData`), because the four reads share one `Promise.all`.
- **roster-private**: The roster query hook (`useConfigureData`) MUST NOT be exported; the source comment states "`useConfigStatus` is the one access point", so components read endpoints only through the shared status model.
- **roster-no-provider-dependency**: The roster query MUST NOT depend on the deploy-project classification; a classification failure MUST NOT prevent `configure` from being populated.

### Classification query (`configure-classification`)

- **classification-fetch**: The classification query function MUST call `fetchUnconfigured(api)` with no options, so it requests `/deploy-projects/unconfigured` without `?fresh=1` and is served from the server route's shared 30-second provider cache (the cache itself is owned by the backend route).
- **classification-no-interval**: The classification query MUST NOT set a `refetchInterval`; it refetches on mount, on whatever refresh the host `QueryClient` applies, and on explicit invalidation.
- **classification-http-error**: A non-2xx response MUST fail the classification query with the error `fetchUnconfigured` throws, whose message is `deploy-projects/unconfigured <status>` (for example `deploy-projects/unconfigured 502`).

### Enablement

- **enabled-default**: `useConfigStatus()` called with no argument MUST behave as `useConfigStatus({ enabled: true })`.
- **enabled-forwarded**: The `enabled` flag MUST be passed to both the roster query and the classification query.
- **enabled-false-no-fetch**: With `enabled: false`, this consumer's observers MUST NOT trigger a fetch; any other enabled consumer of the same keys still drives the shared queries, and this consumer still reads whatever those queries have cached.

### Status model assembly (`buildStatus`)

- **empty-until-both**: When either the roster data or the classification data is `undefined`, `status` MUST be the constant `EMPTY_STATUS`: empty `unconfiguredSites`, `unmonitoredProjects` and `addableProjects`, `noDomainProjects` of `0`, an empty `unmonitoredByPlatform` map, and `counts` of `{ sites: 0, projects: 0, total: 0 }`.
- **unconfigured-sites-predicate**: `status.unconfiguredSites` MUST be the roster `endpoints` filtered by this app's `endpointUnconfigured` predicate (in `lib/config-status`), preserving roster order.
- **paused-fold**: The predicate MUST treat an endpoint with `isActive === false` as opted out exactly like `ignoreProjectWarning === true`, so a paused, unwired endpoint is NOT counted in `unconfiguredSites`; an endpoint whose `isActive` is `undefined` MUST NOT be treated as paused.
- **endpoint-classification**: Under that predicate an endpoint MUST count as unconfigured only when its `kind` is not one of `health`, `custom` or `dns`, it lacks a truthy `platform` or a truthy `deployProject`, and it is not opted out.
- **projects-from-server**: `status.unmonitoredProjects` MUST be the server's `unconfigured.pending` array as received, with no client-side re-classification.
- **addable-from-server**: `status.addableProjects` MUST be the server's `unconfigured.addable` array as received.
- **no-domain-count**: `status.noDomainProjects` MUST equal `unconfigured.noDomain.length` (a count, not the array).
- **server-sites-ignored**: The server's `unconfigured.unconfiguredSites` (`{id, name}` only) MUST NOT be used; the endpoint axis is derived client-side because the banner renders each endpoint's url, site and environment, which the server's minimal shape omits.
- **by-platform-tally**: `status.unmonitoredByPlatform` MUST map each canonical platform key to the number of `unmonitoredProjects` with that platform, where the key is `platformCanon(p.platform)`: `"cloudflare-pages"` maps to `"cloudflare"`, `null`/`undefined` maps to `""`, and every other value maps to itself.
- **counts**: `status.counts.sites` MUST equal `unconfiguredSites.length`, `status.counts.projects` MUST equal `unmonitoredProjects.length`, and `status.counts.total` MUST equal their sum.
- **memoized-status**: `status` MUST be recomputed only when the roster data reference or the classification data reference changes; the same pair of data references MUST yield the same `status` object across renders.

### Return value (`UseConfigStatus`)

- **return-shape**: The hook MUST return `{ status, configure, isLoading, error, refetch }`.
- **configure-raw**: `configure` MUST be the roster query's data, `undefined` until the first roster load resolves.
- **is-loading-rosters-only**: `isLoading` MUST reflect only the roster query's `isLoading`; a pending or failed classification MUST NOT hold `isLoading` true.
- **error-precedence**: `error` MUST be the roster query's error when it is non-nullish, otherwise the classification query's error (roster-first order).
- **error-classification-reported**: When only the classification query has failed, `error` MUST be that failure, so a dead scan is never read as "zero gaps / all clear".
- **error-single-slot**: When both queries have failed, `error` MUST carry only the roster error; the classification error is not surfaced through this hook.
- **refetch-both**: `refetch()` MUST refetch the roster query and the classification query in parallel and return a promise of both results (a two-element array from `Promise.all`).
- **refetch-stable**: The `refetch` function identity MUST change only when either underlying query's `refetch` identity changes.

### Caching, concurrency and side effects

- **shared-cache**: Multiple components calling `useConfigStatus` under one `QueryClient` MUST share the two cached queries; additional callers MUST NOT cause additional fetches beyond react-query's own deduplication.
- **side-effects**: The hook's only side effects MUST be the network reads made through `StatusApiClient` (four roster reads and one classification read per query run); it MUST NOT write storage, log, or mutate server state.
- **no-timeout-no-cancel**: The hook MUST NOT impose its own timeout, retry policy or cancellation on either query; those come from the host `QueryClient` defaults and from `StatusApiClient`.
- **client-only**: The module MUST be a client module (`"use client"`), since it uses React hooks and the react-query cache.

## Appearance

Not applicable — this is a React data hook, not a visual component.

## States

Not applicable — this is a React data hook, not a visual component.

## Accessibility

Not applicable — this is a React data hook, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| config-status-001 | roster-no-provider-dependency, error-classification-reported, classification-http-error | Roster reads return 1 group, 1 site, 1 integration, 1 endpoint; `fetchUnconfigured` rejects with `Error("deploy-projects/unconfigured 502")` (from `use-config-status.dom.test.tsx`) | `configure.sites`, `configure.endpoints`, `configure.integrations` each have length 1; `error` is an `Error` whose message contains `502` |
| config-status-002 | unconfigured-sites-predicate, projects-from-server, counts | Endpoint `{ kind: "http", platform: null, deployProject: null, ignoreProjectWarning: false, isActive: true }`; classification `{ pending: [{ platform: "vercel", projectName: "p" }], addable: [], noDomain: [], unconfiguredSites: [] }` (from `use-config-status.dom.test.tsx`) | `status.counts.total` is `2` (1 site + 1 project); `error` is falsy |
| config-status-003 | empty-until-both | Roster data loaded; classification still pending | `status` equals `EMPTY_STATUS`; `counts.total` is `0`; `isLoading` is `false`; `configure` is populated |
| config-status-004 | paused-fold | Endpoint `{ kind: "http", platform: null, deployProject: null, ignoreProjectWarning: false, isActive: false }`; classification with empty arrays | `status.unconfiguredSites` is empty; `counts.sites` is `0` |
| config-status-005 | paused-fold | Endpoint `{ kind: "http", platform: null, deployProject: null }` with `isActive` absent; classification with empty arrays | `status.unconfiguredSites` contains the endpoint; `counts.sites` is `1` |
| config-status-006 | endpoint-classification | Endpoints of kind `health`, `dns` and `custom`, all with `platform: null` | `status.unconfiguredSites` is empty |
| config-status-007 | endpoint-classification | Endpoint `{ kind: "http", platform: "vercel", deployProject: "web" }` | Not in `status.unconfiguredSites` |
| config-status-008 | by-platform-tally | `pending` platforms `["cloudflare-pages", "cloudflare", "vercel", null]` | `unmonitoredByPlatform` is `{ cloudflare: 2, vercel: 1, "": 1 }`; `counts.projects` is `4` |
| config-status-009 | no-domain-count, addable-from-server | `noDomain` has 3 entries, `addable` has 2 entries | `status.noDomainProjects` is `3`; `status.addableProjects` is the same 2-entry array |
| config-status-010 | error-precedence, error-single-slot | Roster read rejects with `Error("A")`; classification rejects with `Error("B")` | `error` is `Error("A")`; `configure` is `undefined`; `status` equals `EMPTY_STATUS` |
| config-status-011 | roster-all-or-nothing | `listIntegrations` rejects; the other three reads resolve | `configure` is `undefined`; `error` is the `listIntegrations` rejection |
| config-status-012 | invalidate-both, invalidate-result | Call `invalidateConfigQueries(qc)` on a client holding both keys | Both `["configure-data"]` and `["configure-classification"]` are marked invalid and refetched if observed; the promise resolves to `undefined` |
| config-status-013 | enabled-false-no-fetch | Mount `useConfigStatus({ enabled: false })` with no other consumer | No roster read and no `fetchUnconfigured` call occur; `status` equals `EMPTY_STATUS` |
| config-status-014 | refetch-both | Call `refetch()` after both queries loaded | One more run of the four roster reads and one more `fetchUnconfigured` call; the promise resolves to a two-element array |
| config-status-015 | classification-fetch | Classification query runs | `fetchUnconfigured` is called with only the api argument; the request path is `/deploy-projects/unconfigured` (no `?fresh=1`) |
| config-status-016 | configure-data-key, classification-key | Read the exported constants | `CONFIGURE_DATA_KEY` deep-equals `["configure-data"]`; `CONFIGURE_CLASSIFICATION_KEY` deep-equals `["configure-classification"]` |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `boolean` | `true` | Forwarded to both queries; `false` parks this consumer's observers without fetching. |
| `StatusApiClient` (injected) | `StatusApiClient` | from `useStatusApi()` | Transport for all five reads; supplied by the app's API context. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | Owns caching, retry, stale time and any shared refresh; the hook sets none of these itself. |
| `CONFIGURE_DATA_KEY` | `readonly ["configure-data"]` | — | Exported cache key for the roster query. |
| `CONFIGURE_CLASSIFICATION_KEY` | `readonly ["configure-classification"]` | — | Exported cache key for the classification query. |

## Deep Linking

Not applicable: the hook is a data source with no route or URL of its own; its only URLs are the backend API paths it fetches.

## Localization

Not applicable: the hook produces no user-facing strings; the only text it can surface is the untranslated developer error message `deploy-projects/unconfigured <status>` thrown by `fetchUnconfigured`, which consumers decide whether to display.

## Accessibility Options

Not applicable: the hook renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; the `enabled` option is a per-call parameter, not a flag.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: the hook reads the operator's own monitoring configuration and deploy-project metadata from the app's backend, stores it only in the in-memory react-query cache, and handles no credentials or personal data (integration `tokenEnvVar` is an environment-variable name, not a secret).

## Logging

Not applicable: the source contains no log calls; failures are surfaced through the returned `error` field instead.

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor` store holding `configure: ConfigureData?`, the classification response, and a computed `status`. Run the four roster reads in one `async let` group (or `withThrowingTaskGroup`) so they fail together, and the classification in a separate `Task` so it cannot blank the rosters. Share one store instance through the environment to replace react-query's shared cache; expose `refresh()` that awaits both loads.
- **Compose**: A `ViewModel` exposing `StateFlow<UseConfigStatus>`; roster reads with `coroutineScope { awaitAll(...) }`, classification in a sibling `launch` with its own `runCatching`. Combine the two flows with `combine` and `map` for `buildStatus`; `stateIn(viewModelScope, SharingStarted.WhileSubscribed(), ...)` gives the "enabled observers drive the shared source" behavior.
- **React/Web**: Source platform. `hooks/use-config-status.ts` uses `@tanstack/react-query` `useQuery` twice, `useMemo` for `buildStatus` and `useCallback` for `refetch`; it depends on `lib/config-status.ts` (the paused-monitor fold over the engine's `endpointConfigStatus`), `lib/deploy-view.ts` (re-exports `platformCanon` from `@agentic-toolkit/deploy-platform/canon`), `hooks/use-deploy-projects.ts` (`fetchUnconfigured`, `UnconfiguredResponse`, `DeployProject`) and `api/monitored-sites.ts` (the four list calls). Tests: `hooks/use-config-status.dom.test.tsx`.
- **AppKit / UIKit**: Same store as SwiftUI, observed via Observation tracking or Combine `@Published`; view controllers call the store rather than issuing reads, keeping the "one access point" rule.
- **WinUI 3**: Implement a singleton `ConfigStatusService : INotifyPropertyChanged` registered in the DI container (the stand-in for the shared `QueryClient` cache). Use one `HttpClient` for all reads and `System.Text.Json` (`JsonSerializer.DeserializeAsync<UnconfiguredResponse>`) for bodies. Load rosters with `await Task.WhenAll(listGroups, listSites, listIntegrations, listAllEndpoints)` so any fault fails the roster load; load the classification in a separate `Task` wrapped in its own `try/catch` so its failure only sets `Error`. Expose `Groups`/`Sites`/`Integrations`/`Endpoints` as `ObservableCollection<T>` for the editor, `Status` as an immutable record rebuilt when either load completes, `IsLoading` bound to the roster task only, and `Error` set roster-first. Build `UnmonitoredByPlatform` as `Dictionary<string,int>` with the same `cloudflare-pages` to `cloudflare` normalization. Marshal property changes to the UI thread with `DispatcherQueue.TryEnqueue`. Unlike react-query, nothing deduplicates concurrent loads or refreshes automatically: guard with a cached in-flight `Task` per load and add an explicit refresh timer if the host needs the shared periodic refresh.

## Design Decisions

**Decision**: Split the classification out of the roster query into its own key.
**Rationale**: The source records that one flaky provider in the old five-leg `Promise.all` emptied Settings ▸ Sites and Settings ▸ Platforms while the rows sat readable in SQLite; the rosters must not depend on a third party being up.
**Approved**: pending

**Decision**: Keep reporting the classification failure through `error` while `isLoading` tracks rosters only.
**Rationale**: "A dead classification must never be read as zero gaps / all clear", but it "no longer parks the editor in a permanent skeleton". Roster-first precedence means a double failure surfaces only the roster error.
**Approved**: pending

**Decision**: Take the project axis whole from the server; derive the endpoint axis client-side.
**Rationale**: The server is the single source of truth for which projects need monitoring; the endpoint axis stays local because the banner needs each endpoint's url, site and environment, which the server's `{id,name}` shape omits, and the raw endpoints are already loaded for the editor.
**Approved**: pending

**Decision**: Fold `isActive === false` into the engine's `ignoreProjectWarning` at the app boundary (`lib/config-status`).
**Rationale**: `isActive` means nothing to the engine's other consumers; the server applies the identical fold in its own adapter (`autoConfigureOptedOut`), so browser and server agree on the same endpoint.
**Approved**: pending

**Decision**: Return `EMPTY_STATUS` until both queries have data.
**Rationale**: `buildStatus` needs both halves to produce a consistent model; the trade-off, recorded under Edge Cases, is that a pending classification is indistinguishable from zero gaps through `status` alone.
**Approved**: pending

**Decision**: Use the cache-served classification request (no `fresh`) with no `refetchInterval`.
**Rationale**: The source says the badges' refresh "coalesces on" the server's 30-second single-flight cache instead of fanning out a provider scan per tab per minute; only the Auto Configure modal forces a fresh scan.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | performance |

The hook separates fetching (two private query hooks), classification (the engine plus the app's paused fold in `lib/config-status`) and model assembly (the pure `buildStatus`), and keeps the roster query private so there is one access point. Unit coverage exists in `use-config-status.dom.test.tsx` for the scan-failure and both-loaded paths, but not for `enabled: false`, `refetch`, `invalidateConfigQueries`, the paused fold through this hook, or the per-platform tally, hence partial. Error handling is explicit for a single failure, but when both queries fail only the roster error is returned, and a malformed classification body is cast rather than validated and throws during render, hence partial. Caching uses shared react-query keys, a joint invalidation helper, and the server's 30-second cache instead of a polling interval.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
