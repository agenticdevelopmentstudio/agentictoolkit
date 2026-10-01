---
id: b14c03d8-1b93-41e0-9f92-76a81171cee9
title: Deploy Projects State
domain: agentictoolkit://cookbook/status/dashboard/state/deploy-projects
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Cached state and fetch operations for the status dashboard's deploy-projects
  snapshot and unconfigured partition, with a fresh-fetch latch.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/api
references: []
approved-by: ''
approved-date: ''
---

# Deploy Projects State

## Overview

Deploy Projects is the status dashboard's client for the backend's deploy-projects enumeration: every deploy project (Vercel, Railway, Cloudflare Pages) seen in the deployments table, used when an operator browses projects to wire a monitored endpoint and when Auto Configure plans its wiring. The concept exposes:

- the data shapes `DeployProject`, `DeployProjectsResponse` and `UnconfiguredResponse`;
- two imperative read operations, the **deploy-projects read** (`GET /deploy-projects`) and the **unconfigured-partition read** (`GET /deploy-projects/unconfigured`), shared by the cached state, the Auto Configure run and the config-status badges so they "never drift on URL / flag / shape";
- a shared fresh-fetch latch and its arming operation;
- the cached state itself, which caches the snapshot under the cache key `["deploy-projects"]`.

All requests go through the injected status API client (see [status-web-api](agentictoolkit://cookbook/status/dashboard/api)), so paths are relative to the host's API base.

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
- **response-cast-unvalidated**: Both read operations MUST return the parsed response body as the declared response type with no runtime shape validation; the server (the status-server `/deploy-projects` routes) owns the shape.

### The deploy-projects read

- **deploy-projects-path**: The deploy-projects read (given the API client) MUST request the path `/deploy-projects`.
- **deploy-projects-fresh-path**: The deploy-projects read, given `{ fresh: true }`, MUST request the path `/deploy-projects?fresh=1`.
- **deploy-projects-fresh-default**: When the fresh option is omitted, the deploy-projects read MUST send the non-fresh path.
- **deploy-projects-no-store**: The deploy-projects read MUST bypass any local HTTP response cache so the browser cache never serves the body.
- **deploy-projects-http-error**: When the response is not ok (status outside 200–299), the deploy-projects read MUST fail with an error whose message is `deploy-projects <status>` (for example `deploy-projects 502`).
- **deploy-projects-success**: When the response is ok, the deploy-projects read MUST resolve with the parsed response body.
- **deploy-projects-single-request**: The deploy-projects read MUST send exactly one request per call, with no retry, no timeout and no cancellation of its own.

### The unconfigured-partition read

- **unconfigured-path**: The unconfigured-partition read (given the API client) MUST request the path `/deploy-projects/unconfigured`.
- **unconfigured-fresh-path**: The unconfigured-partition read, given `{ fresh: true }`, MUST request the path `/deploy-projects/unconfigured?fresh=1`.
- **unconfigured-no-store**: The unconfigured-partition read MUST bypass any local HTTP response cache.
- **unconfigured-http-error**: When the response is not ok, the unconfigured-partition read MUST fail with an error whose message is `deploy-projects/unconfigured <status>`.
- **unconfigured-success**: When the response is ok, the unconfigured-partition read MUST resolve with the parsed response body.
- **unconfigured-single-request**: The unconfigured-partition read MUST send exactly one request per call, with no retry, no timeout and no cancellation of its own.

### Fresh-fetch latch

- **latch-initial-armed**: The shared latch `nextFetchIsFresh` MUST start armed (true) when the concept is first loaded, so the first cached-state fetch of a page load requests `?fresh=1`.
- **latch-arm**: The arming operation MUST set the latch to armed and produce no result.
- **latch-read-at-start**: The cached state's fetch MUST read the latch once, before issuing the request, and pass that value as `fresh` to the deploy-projects read.
- **latch-disarm-on-success**: The cached state's fetch MUST disarm the latch only after the deploy-projects read resolves successfully.
- **latch-kept-on-failure**: When the deploy-projects read fails, the latch MUST stay in its prior state, so a retry of a failed fresh fetch is again fresh.
- **latch-scope**: The latch MUST be shared by every instance of the cached state in the running process (one per page load), and it MUST NOT affect the unconfigured-partition read or direct callers of the deploy-projects read, which choose `fresh` explicitly.
- **latch-arm-during-flight**: NEEDS REVIEW: Not implemented in source. An arm made while a fetch is already in flight is cleared when that fetch succeeds (the fetch sets the latch to false unconditionally, not only when it consumed an armed latch), so the documented contract "any fetch after arming requests `?fresh=1`" is unmet with no signal; settling it needs a decision on whether the success path should clear only the arm it read (for example a generation counter).

### The cached state

- **hook-query-key**: The cached state MUST register its query under the cache key `["deploy-projects"]`.
- **hook-enabled-default**: The cached state read with no argument MUST be enabled.
- **hook-enabled-false**: The cached state read with `{ enabled: false }` MUST NOT run its fetch.
- **hook-stale-time**: The query MUST use a freshness window of 60,000 ms, so data younger than 60 seconds is served from the shared cache without a refetch on mount.
- **hook-client-source**: The cached state MUST obtain its status API client from the app's API context.
- **hook-return**: The cached state MUST return the query result unchanged, so failures from the deploy-projects read surface as the query's error and error status.
- **hook-retry-policy**: The cached state MUST NOT set its own retry option; retry count and backoff are the shared cache's host-supplied defaults.
- **client-only**: This state has no server-only or universal-rendering variant; it requires a live client execution context.

### Ordering and concurrency

- **single-threaded**: All latch reads and writes MUST happen on a single execution thread; interleaving occurs only across the wait for the network request.
- **dedup-by-query-key**: Concurrent readers of the cached state under one shared cache MUST share one in-flight request, as the cache dedupes by query key.

### Side effects

- **network-only-effect**: The concept's only side effects MUST be HTTP GET requests through the status API client and mutation of the shared latch; it MUST NOT write to storage, log, or emit analytics.

## Appearance

Not applicable — this is a data-fetching concept, not a visual component.

## States

Not applicable — this is a data-fetching concept, not a visual component.

## Accessibility

Not applicable — this is a data-fetching concept, not a visual component.

## Conformance Test Vectors

No test in the source exercises this module directly; `use-config-status.dom.test.tsx` mocks the unconfigured-partition read (resolving `{ pending: [...], addable: [], noDomain: [], unconfiguredSites: [] }` or failing with an error whose message is `deploy-projects/unconfigured 502`). The vectors below are traced to the source's behavior.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-projects-001 | deploy-projects-path, deploy-projects-no-store, deploy-projects-fresh-default | Call the deploy-projects read with a stubbed transport | The transport is called once with path `"/deploy-projects"` and a no-store cache directive |
| deploy-projects-002 | deploy-projects-fresh-path | Call the deploy-projects read with `{ fresh: true }` | The transport is called with path `"/deploy-projects?fresh=1"` and a no-store cache directive |
| deploy-projects-003 | deploy-projects-success | Stub returns ok response with body `{ "projects": [], "verifiedPlatforms": ["vercel"] }` | Resolves to `{ projects: [], verifiedPlatforms: ["vercel"] }` |
| deploy-projects-004 | deploy-projects-http-error | Stub returns response with `ok: false`, `status: 502` | Fails with an error whose message is `deploy-projects 502` |
| deploy-projects-005 | unconfigured-path, unconfigured-no-store | Call the unconfigured-partition read | The transport is called with path `"/deploy-projects/unconfigured"` and a no-store cache directive |
| deploy-projects-006 | unconfigured-fresh-path | Call the unconfigured-partition read with `{ fresh: true }` | The transport is called with path `"/deploy-projects/unconfigured?fresh=1"` |
| deploy-projects-007 | unconfigured-http-error | Stub returns `ok: false`, `status: 502` | Fails with an error whose message is `deploy-projects/unconfigured 502` |
| deploy-projects-008 | unconfigured-success, unconfigured-response-shape | Stub returns ok body `{ "pending": [{ "platform": "vercel", "projectName": "p" }], "addable": [], "noDomain": [], "unconfiguredSites": [] }` | Resolves to the same object |
| deploy-projects-009 | latch-initial-armed, latch-read-at-start | Fresh process start; read the cached state | First request path is `/deploy-projects?fresh=1` |
| deploy-projects-010 | latch-disarm-on-success | After vector 009 succeeds, invalidate `["deploy-projects"]` | Second request path is `/deploy-projects` |
| deploy-projects-011 | latch-kept-on-failure | Fresh process start; first request returns `status: 500`; refetch | Both requests use `/deploy-projects?fresh=1`; query status is error after the first |
| deploy-projects-012 | latch-arm | After a successful fetch, call the arming operation then invalidate the query | Next request path is `/deploy-projects?fresh=1` |
| deploy-projects-013 | hook-enabled-false | Read the cached state with `{ enabled: false }` | The transport is never called |
| deploy-projects-014 | hook-stale-time | Successful fetch, then read again 30 s later | No new request; cached data returned |
| deploy-projects-015 | hook-query-key | Read the cached state under a test cache | The cache's state for `["deploy-projects"]` is defined |
| deploy-projects-016 | hook-return, deploy-projects-http-error | Cached-state fetch returns `status: 503`, retries disabled | Result status is error, error message is `deploy-projects 503` |
| deploy-projects-017 | latch-scope | Latch armed; call the unconfigured-partition read | Path is `/deploy-projects/unconfigured`; latch remains armed |
| deploy-projects-018 | dedup-by-query-key | Two concurrent readers of the cached state under one shared cache | One request is sent |

## Edge Cases

- **Non-ok status**: Any status outside 200–299 (including 401, 404, 502) MUST fail with the status-only message; the response body is not read, so any server error detail is dropped from the message.
- **Malformed body on ok response**: Parsing the response body fails with a syntax error, which MUST propagate unchanged as the read operation's failure (and as the cached state's query error); for the cached state the latch stays armed.
- **Well-formed body of the wrong shape**: The body MUST be returned as-is with no validation (see response-cast-unvalidated); a missing `projects` array reaches consumers as undefined.
- **Missing `verifiedPlatforms`**: The field is optional; consumers MUST treat every wiring as live (verified-platforms-absent).
- **Empty `projects` array**: MUST resolve normally with an empty list.
- **Network failure or unreachable server**: The failure from the transport MUST propagate unchanged; no retry happens inside the read operation, and the cached state defers retries to the shared cache.
- **Timeout**: The concept sets no timeout; a hanging request MUST stay pending until the transport or the host gives up.
- **Cancellation**: The cached state's fetch does not forward the shared cache's cancellation signal to the transport; a cancelled query's request MUST keep running, and if it succeeds it still disarms the latch.
- **Arm during an in-flight fetch**: The arm is lost when that fetch succeeds; see the open question on latch-arm-during-flight.
- **Several shared caches in one process**: The latch is shared process-wide, so the first successful fetch in any cache MUST disarm it for all.
- **Server-side rendering**: The concept requires a live client execution context; its latch is initialized per client realm on load.
- **Offline**: No offline handling exists; requests fail as network failures.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` (read argument) | boolean | `true` | When false, the query does not run. |
| `fresh` (read options) | boolean | undefined (non-fresh) | Appends `?fresh=1` to bypass the server's 30 s provider cache. |
| Status API client | injected client | — (required) | Injected transport; the cached state obtains it from the app's API context. |
| Status API provider | app context | same-origin client with base `/api` | Host-supplied API client or base path. |
| Shared cache | app context | — (host supplied) | Supplies retry, garbage-collection and refetch defaults. |
| Freshness window | number (ms) | `60000` | Hard-coded freshness window of the cached state's query. |
| Cache key | string array | `["deploy-projects"]` | Hard-coded; consumers invalidate or read state by this key. |
| Latch initial value | boolean | `true` | First fetch of each page load is fresh. |

## Deep Linking

Not applicable: the concept only issues API requests and defines no routes or URL patterns.

## Localization

The failure messages are hard-coded English and are not localized; consumers such as the Config panel's refresh line MAY display them.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none, inline) | `deploy-projects <status>` | Error message when `GET /deploy-projects` is not ok |
| (none, inline) | `deploy-projects/unconfigured <status>` | Error message when `GET /deploy-projects/unconfigured` is not ok |

## Accessibility Options

Not applicable: the concept renders nothing, so no display option affects it.

## Feature Flags

Not applicable: no code path in the concept reads a feature flag.

## Analytics

Not applicable: the concept emits no analytics events.

## Privacy

Not applicable: the concept reads project metadata (names, domains, git repo and branch, deploy status) from the operator's own backend, holds it only in the in-memory shared cache, and sends no credentials or personal data itself.

## Logging

Not applicable: the concept contains no logging calls; failures surface only as rejected results and query error state.

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-deploy-projects.ts`. It uses TanStack React Query's `useQuery` (query key, `enabled`, `staleTime`), the package's `StatusApiClient` port from `src/api/client.ts` (`api.fetch` with `RequestInit.cache: "no-store"`), and a module-level `let` as the page-load latch. The deploy-projects read and unconfigured-partition read are the exported functions `fetchDeployProjects` and `fetchUnconfigured`; the cached state is the hook `useDeployProjects`; the arming operation is `armFreshDeployProjectsFetch`. `"use client"` marks it as a Next.js client module. Callers: `ConfigPanel.tsx` arms the latch before invalidating; `use-config-status.ts` polls `fetchUnconfigured`; `AutoConfigureProvider.tsx`, `ProjectBrowser.tsx`, `PlatformProjects.tsx`, `EndpointsSection.tsx` and `UnconfiguredProjectsBanner.tsx` consume the data.
- **SwiftUI**: Start from an `@Observable` (or `ObservableObject`) model on `@MainActor` holding `DeployProjectsResponse?` and an error, with `async` methods calling `URLSession.shared.data(for:)` using a `URLRequest` whose `cachePolicy` is `.reloadIgnoringLocalCacheData`; decode with `JSONDecoder` into `Codable` structs (optionals for the nullable fields, `verifiedPlatforms: [String]?`). The 60 s stale window and dedup must be hand-rolled (store a fetch timestamp and an in-flight `Task`), and the latch becomes a property on the model or a static on the service.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>` with a repository using Ktor or Retrofit plus `kotlinx.serialization` data classes; send `Cache-Control: no-store` (or OkHttp `CacheControl.FORCE_NETWORK`). Dedup and staleness come from a `Mutex` plus timestamp or a library such as Store; the latch is an `AtomicBoolean` in the repository singleton.
- **AppKit / UIKit**: Same `URLSession` and `Codable` service as SwiftUI, with a view controller or coordinator observing results via delegate, Combine publisher or closure; UI updates hop to the main queue.
- **WinUI 3**: Start from a service using a shared `HttpClient` with `GetAsync` and a `CacheControlHeaderValue { NoStore = true }` request header (or `HttpRequestMessage.Headers.CacheControl`), deserializing with `System.Text.Json` `JsonSerializer.DeserializeAsync<DeployProjectsResponse>` into records with nullable `string?` properties and `List<string>? VerifiedPlatforms`. Throw `HttpRequestException` (or a custom exception carrying the `deploy-projects <status>` message) when `!response.IsSuccessStatusCode`. Expose results from a ViewModel implementing `INotifyPropertyChanged` (for example CommunityToolkit.Mvvm `ObservableObject` with an `ObservableCollection<DeployProject>` for list binding), marshalling updates through `DispatcherQueue.TryEnqueue`. The shared cache's dedup, 60 s freshness window and retry policy have no built-in equivalent: cache the last `Task<DeployProjectsResponse>` and its completion time, and add retry via Polly if wanted. The latch becomes a `static` field (or a `volatile bool` in the service) cleared only after a successful await; consider a generation counter so an arm during an in-flight request is not lost. Pass a `CancellationToken` to `GetAsync`, which the source does not do.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-deploy-projects.ts` |

## Design Decisions

**Decision**: Both read operations bypass the local HTTP response cache.

**Rationale**: A refetch right after Add or Ignore, or on picker open, must reach the server for a fresh provider scan; the browser's HTTP cache would otherwise show stale wired, ignored and project data. (Web platform: implemented as `cache: "no-store"`.)

**Approved**: pending

---

**Decision**: The first fetch of a page load, and any fetch after an explicit arm, sends `?fresh=1`; the latch disarms only on success.

**Rationale**: A reload and the explicit Refresh must show, and Auto Configure must plan against, the live project list rather than the server's 30 s provider cache; keeping the latch armed after a failure keeps retries fresh, while later refetches in the same page load use normal caching.

**Approved**: pending

---

**Decision**: The unconfigured-partition read defaults to the cache-served path; only the Auto Configure modal sends `fresh: true`.

**Rationale**: The route shares the sibling `/deploy-projects` 30 s provider cache, so the config-status badges' 60 s poll coalesces on it instead of fanning out a provider scan per tab per minute.

**Approved**: pending

---

**Decision**: The two read operations are exposed separately from the cached state.

**Rationale**: The cached state, the imperative Auto Configure run and the badges share one URL, flag and response shape so they cannot drift.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
