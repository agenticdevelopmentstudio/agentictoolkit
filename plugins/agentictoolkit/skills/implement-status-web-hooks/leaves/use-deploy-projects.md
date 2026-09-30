<!-- leaf: implement-status-web-hooks/use-deploy-projects · source: status-web-hooks-use-deploy-projects.md -->

**Rules** (cite as `implement-status-web-hooks/use-deploy-projects#<slug>`):

- `deploy-project-shape` MUST
- `environment-per-entry` MUST
- `wired-flag` MUST
- `ignored-flag` MUST
- `domains-list` MUST
- `deploy-projects-response-shape` MUST
- `verified-platforms-meaning` MUST
- `verified-platforms-absent` MUST
- `unconfigured-response-shape` MUST
- `response-cast-unvalidated` MUST
- `deploy-projects-path` MUST
- `deploy-projects-fresh-path` MUST
- `deploy-projects-fresh-default` MUST
- `deploy-projects-no-store` MUST
- `deploy-projects-http-error` MUST
- `deploy-projects-success` MUST
- `deploy-projects-single-request` MUST
- `unconfigured-path` MUST
- `unconfigured-fresh-path` MUST
- `unconfigured-no-store` MUST
- `unconfigured-http-error` MUST
- `unconfigured-success` MUST
- `unconfigured-single-request` MUST
- `latch-initial-armed` MUST
- `latch-arm` MUST
- `latch-read-at-start` MUST
- `latch-disarm-on-success` MUST
- `latch-kept-on-failure` MUST
- `latch-scope` MUST
- `hook-query-key` MUST
- `hook-enabled-default` MUST
- `hook-enabled-false` MUST
- `hook-stale-time` MUST
- `hook-client-source` MUST
- `hook-return` MUST
- `hook-retry-policy` MUST
- `client-only` MUST
- `single-threaded` MUST
- `dedup-by-query-key` MUST
- `network-only-effect` MUST
- `panel-refresh-line-display-them` MAY — The rejection messages are hard-coded English and are not localized; callers such as the Config panel's refresh line …

# useDeployProjects

## Overview

`use-deploy-projects.ts` is the status dashboard's client for the backend's deploy-projects enumeration: every deploy project (Vercel, Railway, Cloudflare Pages) seen in the deployments table, used when an operator browses projects to wire a monitored endpoint and when Auto Configure plans its wiring. The module exports:

- the data shapes `DeployProject`, `DeployProjectsResponse` and `UnconfiguredResponse`;
- two imperative fetch helpers, `fetchDeployProjects` (`GET /deploy-projects`) and `fetchUnconfigured` (`GET /deploy-projects/unconfigured`), shared by the hook, the Auto Configure run and the config-status badges so they "never drift on URL / flag / shape";
- a module-level fresh-fetch latch and its arming function `armFreshDeployProjectsFetch`;
- the React Query hook `useDeployProjects`, which caches the snapshot under the query key `["deploy-projects"]`.

All requests go through the injected `StatusApiClient` (see status-web-api), so paths are relative to the host's API base.

## Behavioral Requirements

### Data shapes

- **deploy-project-shape**: A `DeployProject` MUST carry `platform` (string, as recorded on deploys: `vercel`, `railway` or `cloudflare-pages`), `projectName` (string), `environment` (string or null), `environments` (string array), `latestAt` (string or null), `deployCount` (number), `latestStatus` (string or null: `success`, `failed`, `building`, `queued` or `canceled`), `wired` (boolean), `ignored` (boolean), `domain` (string or null), `domains` (string array), `gitRepo`, `gitBranch`, `rootDirectory` and `framework` (each string or null).
- **environment-per-entry**: `environment` MUST name the deploy environment one entry represents for Railway (enumerated once per environment, such as production, staging or testing, each with its own domain) and MUST be null for Vercel and Cloudflare, whose environment is encoded in the project name.
- **wired-flag**: `wired` MUST be true when the project is already referenced by a monitored endpoint.
- **ignored-flag**: `ignored` MUST be true when an operator has exempted the project from the "unconfigured" warning.
- **domains-list**: `domains` MUST list every domain the project serves (canonical plus redirect aliases); for Cloudflare and Railway, which have one host, it is the single-element list of `domain`.
- **deploy-projects-response-shape**: A `DeployProjectsResponse` MUST carry `projects` (a `DeployProject` array) and MAY carry `verifiedPlatforms` (string array).
- **verified-platforms-meaning**: `verifiedPlatforms` MUST list only the platforms the enumeration listed live and completely; only a platform in this list proves, by a project's absence from `projects`, that the project is gone upstream.
- **verified-platforms-absent**: When a response omits `verifiedPlatforms` (a backend that predates the field), a consumer MUST treat every wiring as live.
- **unconfigured-response-shape**: An `UnconfiguredResponse` MUST carry `pending`, `addable` and `noDomain` (each a `DeployProject` array, the project axis) and `unconfiguredSites` (an array of `{ id: string; name: string }`, the endpoint axis).
- **response-cast-unvalidated**: Both fetch helpers MUST return the parsed JSON body cast to the declared response type with no runtime shape validation; the server (the status-server `/deploy-projects` routes) owns the shape.

### fetchDeployProjects

- **deploy-projects-path**: `fetchDeployProjects(api)` MUST request the path `/deploy-projects` through `api.fetch`.
- **deploy-projects-fresh-path**: `fetchDeployProjects(api, { fresh: true })` MUST request the path `/deploy-projects?fresh=1`.
- **deploy-projects-fresh-default**: When `opts` or `opts.fresh` is omitted, `fetchDeployProjects` MUST send the non-fresh path.
- **deploy-projects-no-store**: `fetchDeployProjects` MUST pass the request option `cache: "no-store"` so the browser HTTP cache never serves the body.
- **deploy-projects-http-error**: When the response is not ok (status outside 200–299), `fetchDeployProjects` MUST reject with an `Error` whose message is `deploy-projects <status>` (for example `deploy-projects 502`).
- **deploy-projects-success**: When the response is ok, `fetchDeployProjects` MUST resolve with the parsed JSON body.
- **deploy-projects-single-request**: `fetchDeployProjects` MUST send exactly one request per call, with no retry, no timeout and no abort signal of its own.

### fetchUnconfigured

- **unconfigured-path**: `fetchUnconfigured(api)` MUST request the path `/deploy-projects/unconfigured` through `api.fetch`.
- **unconfigured-fresh-path**: `fetchUnconfigured(api, { fresh: true })` MUST request the path `/deploy-projects/unconfigured?fresh=1`.
- **unconfigured-no-store**: `fetchUnconfigured` MUST pass the request option `cache: "no-store"`.
- **unconfigured-http-error**: When the response is not ok, `fetchUnconfigured` MUST reject with an `Error` whose message is `deploy-projects/unconfigured <status>`.
- **unconfigured-success**: When the response is ok, `fetchUnconfigured` MUST resolve with the parsed JSON body.
- **unconfigured-single-request**: `fetchUnconfigured` MUST send exactly one request per call, with no retry, no timeout and no abort signal of its own.

### Fresh-fetch latch

- **latch-initial-armed**: The module-level latch `nextFetchIsFresh` MUST start armed (true) at module load, so the first hook fetch of a page load requests `?fresh=1`.
- **latch-arm**: `armFreshDeployProjectsFetch()` MUST set the latch to armed and return nothing.
- **latch-read-at-start**: The hook's query function MUST read the latch once, before issuing the request, and pass that value as `fresh` to `fetchDeployProjects`.
- **latch-disarm-on-success**: The hook's query function MUST disarm the latch only after `fetchDeployProjects` resolves successfully.
- **latch-kept-on-failure**: When `fetchDeployProjects` rejects, the latch MUST stay in its prior state, so a retry of a failed fresh fetch is again fresh.
- **latch-scope**: The latch MUST be shared by every `useDeployProjects` instance in the JavaScript realm (one per page load), and it MUST NOT affect `fetchUnconfigured` or direct callers of `fetchDeployProjects`, which choose `fresh` explicitly.
- **latch-arm-during-flight**: NEEDS REVIEW: Not implemented in source. An arm made while a hook fetch is already in flight is cleared when that fetch succeeds (the query function sets the latch to false unconditionally, not only when it consumed an armed latch), so the documented contract "any fetch after `armFreshDeployProjectsFetch()` requests `?fresh=1`" is unmet with no signal; settling it needs a decision on whether the success path should clear only the arm it read (for example a generation counter).

### useDeployProjects

- **hook-query-key**: `useDeployProjects` MUST register a React Query query under the key `["deploy-projects"]`.
- **hook-enabled-default**: `useDeployProjects()` with no argument MUST be enabled.
- **hook-enabled-false**: `useDeployProjects({ enabled: false })` MUST NOT run the query function.
- **hook-stale-time**: The query MUST use a `staleTime` of 60,000 ms, so data younger than 60 seconds is served from the React Query cache without a refetch on mount.
- **hook-client-source**: The hook MUST obtain its `StatusApiClient` from `useStatusApi()`, which is the provider's client or the same-origin default.
- **hook-return**: The hook MUST return the `UseQueryResult<DeployProjectsResponse>` unchanged, so errors from `fetchDeployProjects` surface as the query's `error` and `status: "error"`.
- **hook-retry-policy**: The hook MUST NOT set its own `retry` option; retry count and backoff are React Query's `QueryClient` defaults supplied by the host.
- **client-only**: The module MUST run only on the client (it is declared `"use client"`).

### Ordering and concurrency

- **single-threaded**: All latch reads and writes MUST happen on the JavaScript main thread; interleaving occurs only across the `await` of the network request.
- **dedup-by-query-key**: Concurrent `useDeployProjects` observers under one `QueryClient` MUST share one in-flight request, as React Query dedupes by query key.

### Side effects

- **network-only-effect**: The module's only side effects MUST be HTTP GET requests through `api.fetch` and mutation of the module-level latch; it MUST NOT write to storage, log, or emit analytics.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` (hook argument) | `boolean` | `true` | When false, the query does not run. |
| `opts.fresh` (fetch helpers) | `boolean` | `undefined` (non-fresh) | Appends `?fresh=1` to bypass the server's 30 s provider cache. |
| `api` (fetch helpers) | `StatusApiClient` | — (required) | Injected client; the hook obtains it from `useStatusApi()`. |
| `StatusApiProvider` | React context | same-origin client with base `/api` | Host-supplied API client or base path. |
| `QueryClient` | React Query context | — (host supplied) | Supplies retry, gc and refetch defaults. |
| `staleTime` | `number` (ms) | `60000` | Hard-coded freshness window of the hook's query. |
| Query key | `string[]` | `["deploy-projects"]` | Hard-coded; callers invalidate or read state by this key. |
| Latch initial value | `boolean` | `true` | First hook fetch of each page load is fresh. |

## Localization

The rejection messages are hard-coded English and are not localized; callers such as the Config panel's refresh line MAY display them.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none, inline) | `deploy-projects <status>` | `Error` message when `GET /deploy-projects` is not ok |
| (none, inline) | `deploy-projects/unconfigured <status>` | `Error` message when `GET /deploy-projects/unconfigured` is not ok |

