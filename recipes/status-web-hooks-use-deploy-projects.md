---
id: b14c03d8-1b93-41e0-9f92-76a81171cee9
title: useDeployProjects
domain: agentictoolkit://recipes/status-web-hooks-use-deploy-projects
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React Query hook and fetch helpers for the status dashboard's deploy-projects
  snapshot and unconfigured partition, with a fresh-fetch latch.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://recipes/status-web-api
related:
- agentictoolkit://recipes/status-web-api
references: []
approved-by: ''
approved-date: ''
---

# useDeployProjects

## Overview

`use-deploy-projects.ts` is the status dashboard's client for the backend's deploy-projects enumeration: every deploy project (Vercel, Railway, Cloudflare Pages) seen in the deployments table, used when an operator browses projects to wire a monitored endpoint and when Auto Configure plans its wiring. The module exports:

- the data shapes `DeployProject`, `DeployProjectsResponse` and `UnconfiguredResponse`;
- two imperative fetch helpers, `fetchDeployProjects` (`GET /deploy-projects`) and `fetchUnconfigured` (`GET /deploy-projects/unconfigured`), shared by the hook, the Auto Configure run and the config-status badges so they "never drift on URL / flag / shape";
- a module-level fresh-fetch latch and its arming function `armFreshDeployProjectsFetch`;
- the React Query hook `useDeployProjects`, which caches the snapshot under the query key `["deploy-projects"]`.

All requests go through the injected `StatusApiClient` (see [status-web-api](agentictoolkit://recipes/status-web-api)), so paths are relative to the host's API base.

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

## Appearance

Not applicable — this is a data-fetching hook and client module, not a visual component.

## States

Not applicable — this is a data-fetching hook and client module, not a visual component.

## Accessibility

Not applicable — this is a data-fetching hook and client module, not a visual component.

## Conformance Test Vectors

No test in the source exercises this module directly; `use-config-status.dom.test.tsx` mocks `fetchUnconfigured` (resolving `{ pending: [...], addable: [], noDomain: [], unconfiguredSites: [] }` or rejecting with `Error("deploy-projects/unconfigured 502")`). The vectors below are traced to the module's code.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-projects-001 | deploy-projects-path, deploy-projects-no-store, deploy-projects-fresh-default | `fetchDeployProjects(api)` with a stub `api.fetch` | `api.fetch` called once with `"/deploy-projects"` and `{ cache: "no-store" }` |
| deploy-projects-002 | deploy-projects-fresh-path | `fetchDeployProjects(api, { fresh: true })` | `api.fetch` called with `"/deploy-projects?fresh=1"` and `{ cache: "no-store" }` |
| deploy-projects-003 | deploy-projects-success | Stub returns ok response with body `{ "projects": [], "verifiedPlatforms": ["vercel"] }` | Resolves to `{ projects: [], verifiedPlatforms: ["vercel"] }` |
| deploy-projects-004 | deploy-projects-http-error | Stub returns response with `ok: false`, `status: 502` | Rejects with `Error` message `deploy-projects 502` |
| deploy-projects-005 | unconfigured-path, unconfigured-no-store | `fetchUnconfigured(api)` | `api.fetch` called with `"/deploy-projects/unconfigured"` and `{ cache: "no-store" }` |
| deploy-projects-006 | unconfigured-fresh-path | `fetchUnconfigured(api, { fresh: true })` | `api.fetch` called with `"/deploy-projects/unconfigured?fresh=1"` |
| deploy-projects-007 | unconfigured-http-error | Stub returns `ok: false`, `status: 502` | Rejects with `Error` message `deploy-projects/unconfigured 502` |
| deploy-projects-008 | unconfigured-success, unconfigured-response-shape | Stub returns ok body `{ "pending": [{ "platform": "vercel", "projectName": "p" }], "addable": [], "noDomain": [], "unconfiguredSites": [] }` | Resolves to the same object |
| deploy-projects-009 | latch-initial-armed, latch-read-at-start | Fresh module load; mount `useDeployProjects()` | First request path is `/deploy-projects?fresh=1` |
| deploy-projects-010 | latch-disarm-on-success | After vector 009 succeeds, invalidate `["deploy-projects"]` | Second request path is `/deploy-projects` |
| deploy-projects-011 | latch-kept-on-failure | Fresh module load; first request returns `status: 500`; refetch | Both requests use `/deploy-projects?fresh=1`; query `status` is `"error"` after the first |
| deploy-projects-012 | latch-arm | After a successful fetch, call `armFreshDeployProjectsFetch()` then invalidate the query | Next request path is `/deploy-projects?fresh=1` |
| deploy-projects-013 | hook-enabled-false | Mount `useDeployProjects({ enabled: false })` | `api.fetch` is never called |
| deploy-projects-014 | hook-stale-time | Successful fetch, then remount an observer 30 s later | No new request; cached data returned |
| deploy-projects-015 | hook-query-key | Mount the hook with a test `QueryClient` | `queryClient.getQueryState(["deploy-projects"])` is defined |
| deploy-projects-016 | hook-return, deploy-projects-http-error | Hook fetch returns `status: 503`, retries disabled on the test `QueryClient` | Result `status` is `"error"`, `error.message` is `deploy-projects 503` |
| deploy-projects-017 | latch-scope | Latch armed; call `fetchUnconfigured(api)` | Path is `/deploy-projects/unconfigured`; latch remains armed |
| deploy-projects-018 | dedup-by-query-key | Mount two `useDeployProjects()` observers under one `QueryClient` | One request is sent |

## Edge Cases

- **Non-ok status**: Any status outside 200–299 (including 401, 404, 502) MUST reject with the status-only message; the response body is not read, so any server error detail is dropped from the message.
- **Malformed JSON body on ok response**: `r.json()` rejects with the platform's `SyntaxError`, which MUST propagate unchanged as the helper's rejection (and as the hook's query error); for the hook the latch stays armed.
- **Well-formed JSON of the wrong shape**: The body MUST be returned as-is with no validation (see response-cast-unvalidated); a missing `projects` array reaches callers undefined.
- **Missing `verifiedPlatforms`**: The field is optional; consumers MUST treat every wiring as live (verified-platforms-absent).
- **Empty `projects` array**: MUST resolve normally with an empty list.
- **Network failure or unreachable server**: The rejection from `api.fetch` (for example a `TypeError`) MUST propagate unchanged; no retry happens inside the helper, and the hook defers retries to the `QueryClient`.
- **Timeout**: The module sets no timeout; a hanging request MUST stay pending until the platform or the host's fetch gives up.
- **Cancellation**: The query function does not forward React Query's abort signal to `api.fetch`; a cancelled query's request MUST keep running, and if it succeeds it still disarms the latch.
- **Arm during an in-flight fetch**: The arm is lost when that fetch succeeds; see the open question on latch-arm-during-flight.
- **Several QueryClients in one page**: The latch is module-scoped, so the first successful fetch in any client MUST disarm it for all.
- **Server-side rendering**: The module is `"use client"`; its latch is initialized per client realm on load.
- **Offline**: No offline handling exists; requests fail as network failures.

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

## Deep Linking

Not applicable: the module only issues API requests and defines no routes or URL patterns.

## Localization

The rejection messages are hard-coded English and are not localized; callers such as the Config panel's refresh line MAY display them.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none, inline) | `deploy-projects <status>` | `Error` message when `GET /deploy-projects` is not ok |
| (none, inline) | `deploy-projects/unconfigured <status>` | `Error` message when `GET /deploy-projects/unconfigured` is not ok |

## Accessibility Options

Not applicable: the module renders nothing, so no display option affects it.

## Feature Flags

Not applicable: no code path in the module reads a feature flag.

## Analytics

Not applicable: the module emits no analytics events.

## Privacy

Not applicable: the module reads project metadata (names, domains, git repo and branch, deploy status) from the operator's own backend, holds it only in the in-memory React Query cache, and sends no credentials or personal data itself.

## Logging

Not applicable: the module contains no logging calls; failures surface only as rejected promises and query error state.

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-deploy-projects.ts`. It uses TanStack React Query's `useQuery` (query key, `enabled`, `staleTime`), the package's `StatusApiClient` port from `src/api/client.ts` (`api.fetch` with `RequestInit.cache: "no-store"`), and a module-level `let` as the page-load latch. `"use client"` marks it as a Next.js client module. Callers: `ConfigPanel.tsx` arms the latch before invalidating; `use-config-status.ts` polls `fetchUnconfigured`; `AutoConfigureProvider.tsx`, `ProjectBrowser.tsx`, `PlatformProjects.tsx`, `EndpointsSection.tsx` and `UnconfiguredProjectsBanner.tsx` consume the data.
- **SwiftUI**: Start from an `@Observable` (or `ObservableObject`) model on `@MainActor` holding `DeployProjectsResponse?` and an error, with `async` methods calling `URLSession.shared.data(for:)` using a `URLRequest` whose `cachePolicy` is `.reloadIgnoringLocalCacheData`; decode with `JSONDecoder` into `Codable` structs (optionals for the nullable fields, `verifiedPlatforms: [String]?`). The 60 s stale window and dedup must be hand-rolled (store a fetch timestamp and an in-flight `Task`), and the latch becomes a property on the model or a static on the service.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>` with a repository using Ktor or Retrofit plus `kotlinx.serialization` data classes; send `Cache-Control: no-store` (or OkHttp `CacheControl.FORCE_NETWORK`). Dedup and staleness come from a `Mutex` plus timestamp or a library such as Store; the latch is an `AtomicBoolean` in the repository singleton.
- **AppKit / UIKit**: Same `URLSession` and `Codable` service as SwiftUI, with a view controller or coordinator observing results via delegate, Combine publisher or closure; UI updates hop to the main queue.
- **WinUI 3**: Start from a service using a shared `HttpClient` with `GetAsync` and a `CacheControlHeaderValue { NoStore = true }` request header (or `HttpRequestMessage.Headers.CacheControl`), deserializing with `System.Text.Json` `JsonSerializer.DeserializeAsync<DeployProjectsResponse>` into records with nullable `string?` properties and `List<string>? VerifiedPlatforms`. Throw `HttpRequestException` (or a custom exception carrying the `deploy-projects <status>` message) when `!response.IsSuccessStatusCode`. Expose results from a ViewModel implementing `INotifyPropertyChanged` (for example CommunityToolkit.Mvvm `ObservableObject` with an `ObservableCollection<DeployProject>` for list binding), marshalling updates through `DispatcherQueue.TryEnqueue`. React Query's dedup, 60 s `staleTime` and retry policy have no built-in equivalent: cache the last `Task<DeployProjectsResponse>` and its completion time, and add retry via Polly if wanted. The latch becomes a `static` field (or a `volatile bool` in the service) cleared only after a successful await; consider a generation counter so an arm during an in-flight request is not lost. Pass a `CancellationToken` to `GetAsync`, which the source does not do.

## Design Decisions

**Decision**: Both fetch helpers pass `cache: "no-store"`.

**Rationale**: A refetch right after Add or Ignore, or on picker open, must reach the server for a fresh provider scan; the browser's HTTP cache would otherwise show stale wired, ignored and project data.

**Approved**: pending

---

**Decision**: The first hook fetch of a page load, and any fetch after an explicit arm, sends `?fresh=1`; the latch disarms only on success.

**Rationale**: A reload and the explicit Refresh must show, and Auto Configure must plan against, the live project list rather than the server's 30 s provider cache; keeping the latch armed after a failure keeps retries fresh, while later refetches in the same page load use normal caching.

**Approved**: pending

---

**Decision**: `fetchUnconfigured` defaults to the cache-served path; only the Auto Configure modal sends `fresh: true`.

**Rationale**: The route shares the sibling `/deploy-projects` 30 s provider cache, so the config-status badges' 60 s poll coalesces on it instead of fanning out a provider scan per tab per minute.

**Approved**: pending

---

**Decision**: The fetch helpers are exported functions separate from the hook.

**Rationale**: The hook, the imperative Auto Configure run and the badges share one URL, flag and response shape so they cannot drift.

**Approved**: pending

---

**Decision**: `verifiedPlatforms` is optional and its absence means "treat every wiring as live".

**Rationale**: A backend that predates the field sends nothing, and a provider that errored, timed out or fell back to its configured list is deliberately omitted, so a client can tell "deleted upstream" from "we couldn't look".

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | partial | performance |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | failed | reliability |

The module separates transport (the injected `StatusApiClient`), request shaping (the two fetch helpers) and caching (the React Query hook), which satisfies separation of concerns. No test exercises this module's own code; the only related test mocks `fetchUnconfigured` wholesale, so unit-test coverage fails. Every non-ok response becomes a thrown `Error` carrying the status and is surfaced to callers through promise rejection or query error state, so errors are explicit rather than swallowed. The caching strategy is deliberate (browser cache bypassed, 60 s client stale window, server 30 s cache bypassed on demand) but only partial, because an arm made while a fetch is in flight can be lost, leaving the next fetch cache-served contrary to the documented latch contract. No timeout is set on either request and React Query's abort signal is not forwarded, so a hung request stays pending indefinitely.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
