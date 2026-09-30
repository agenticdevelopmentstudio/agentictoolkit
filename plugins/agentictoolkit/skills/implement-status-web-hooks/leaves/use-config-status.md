<!-- leaf: implement-status-web-hooks/use-config-status · source: status-web-hooks-use-config-status.md -->

**Rules** (cite as `implement-status-web-hooks/use-config-status#<slug>`):

- `configure-data-key` MUST
- `classification-key` MUST
- `invalidate-both` MUST
- `invalidate-result` MUST
- `invalidate-rejection` MUST
- `roster-reads` MUST
- `roster-shape` MUST
- `roster-all-or-nothing` MUST
- `roster-private` MUST
- `roster-no-provider-dependency` MUST
- `classification-fetch` MUST
- `classification-no-interval` MUST
- `classification-http-error` MUST
- `enabled-default` MUST
- `enabled-forwarded` MUST
- `enabled-false-no-fetch` MUST
- `empty-until-both` MUST
- `unconfigured-sites-predicate` MUST
- `paused-fold` MUST
- `endpoint-classification` MUST
- `projects-from-server` MUST
- `addable-from-server` MUST
- `no-domain-count` MUST
- `server-sites-ignored` MUST
- `by-platform-tally` MUST
- `counts` MUST
- `memoized-status` MUST
- `return-shape` MUST
- `configure-raw` MUST
- `is-loading-rosters-only` MUST
- `error-precedence` MUST
- `error-classification-reported` MUST
- `error-single-slot` MUST
- `refetch-both` MUST
- `refetch-stable` MUST
- `shared-cache` MUST
- `side-effects` MUST
- `no-timeout-no-cancel` MUST
- `client-only` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `boolean` | `true` | Forwarded to both queries; `false` parks this consumer's observers without fetching. |
| `StatusApiClient` (injected) | `StatusApiClient` | from `useStatusApi()` | Transport for all five reads; supplied by the app's API context. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | Owns caching, retry, stale time and any shared refresh; the hook sets none of these itself. |
| `CONFIGURE_DATA_KEY` | `readonly ["configure-data"]` | — | Exported cache key for the roster query. |
| `CONFIGURE_CLASSIFICATION_KEY` | `readonly ["configure-classification"]` | — | Exported cache key for the classification query. |

