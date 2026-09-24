---
id: eb7e9eeb-86f3-4053-827a-ea259833c6ad
title: Status Web API
domain: agentictoolkit://recipes/status-web-api
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status dashboard's same-origin JSON/SSE port (StatusApiClient), its Provider/hook
  wiring, and the monitored-sites and peers configuration-CRUD clients built on it.
platforms:
- typescript
- web
tags:
- status
- web
- api-client
- config
- peers
- monitoring
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
related:
- agentictoolkit://recipes/status-server-routes
- agentictoolkit://recipes/status-server-peers
- agentictoolkit://recipes/status-server-monitor-endpoint-kinds
references:
- packages/web/packages/status-web/src/api/client.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/monitored-sites.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/monitored-sites.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/peers.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/endpoint-kinds.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Web API

## Overview

`status-web`'s one port onto its backend, and the two configuration-CRUD clients
built on it. `client.ts` defines `StatusApiClient` — `url`, `fetch`, `json`, and
`eventSource`, all resolved relative to a `basePath` — plus `createStatusApiClient`,
a `defaultClient` singleton, a React context, `StatusApiProvider`, and the
`useStatusApi` hook every panel and hook call instead of naming a base path
themselves. `monitored-sites.ts` is the monitoring-configuration client: groups,
sites, endpoints, integrations, and ignored deploy projects, each with a
backend-`Row` type mapped to a frontend `View` type. `peers.ts` is the
fleet-membership client: list/create/update/delete for the peer monitors this
one polls, including the shared-secret `token` field's write-only semantics.
All three files talk to the status backend through the caller-supplied
`StatusApiClient`, never naming `/api` themselves except in `client.ts`'s one
`DEFAULT_API_BASE` constant.

## Behavioral Requirements

### client.ts

- **default-base-path**: `createStatusApiClient` MUST default `basePath` to
  `DEFAULT_API_BASE` (the fixed string `"/api"`) when the caller supplies no
  `basePath` option.
- **url-join**: `url(path)` MUST return `${basePath}${path}` — a plain string
  concatenation with no encoding, normalization, or leading-slash correction.
- **late-fetch-resolution**: `fetch(path, init)` MUST resolve which `fetch`
  implementation to call — `fetchImpl` if the client was constructed with one,
  otherwise `globalThis.fetch` — at the time of each call, not once when
  `createStatusApiClient` runs.
- **json-content-type**: `json<T>(path, init)` MUST send a
  `"Content-Type": "application/json"` header on every request, and MUST let
  any `Content-Type` present in `init.headers` take precedence over that
  default (the headers object is built as
  `{"Content-Type": "application/json", ...(init?.headers ?? {})}`).
- **json-ok-body**: `json<T>` MUST return the parsed `await res.json()` body
  for any successful (`res.ok`) response whose status is not `204`.
- **json-204-empty**: `json<T>` MUST return `undefined` for a successful
  response with status `204`, without calling `res.json()`.
- **json-error-message**: `json<T>` MUST throw an `Error` when `res.ok` is
  `false`, with a message of exactly `${method} ${url} → ${status}`, where
  `method` is `init?.method` if given, else `"GET"`, and `url` is
  `this.url(path)`.
- **json-error-detail**: the thrown error message MUST be suffixed with
  ` — ${text}` when the failed response's body parses as JSON and yields a
  usable detail string, checked in this order: a string `error` field, then
  `error.message`, then a top-level `message` field; the message MUST carry
  no such suffix when the body does not parse as JSON or none of those
  fields is present.
- **event-source-target**: `eventSource(path)` MUST return
  `new EventSource(this.url(path))`.
- **provider-client-selection**: `StatusApiProvider` MUST use the `client`
  prop when one is given, and otherwise MUST construct a `StatusApiClient`
  via `createStatusApiClient({basePath})`.
- **provider-memoization**: the client `StatusApiProvider` supplies to its
  subtree MUST be memoized (`useMemo`) on `[client, basePath]`, so a
  re-render of the provider with the same `client`/`basePath` identity MUST
  NOT construct a new client instance.
- **hook-fallback**: `useStatusApi()` MUST return the nearest ancestor
  `StatusApiProvider`'s client when one is mounted, and MUST otherwise
  return the module-level `defaultClient` singleton, built once at module
  load via `createStatusApiClient()` with no arguments.

### monitored-sites.ts

- **endpoint-optional-field-defaults**: `toEndpoint` MUST default each of
  `environment`, `platform`, `deployProject`, and `expectBody` to `null` when
  the corresponding `EndpointRow` field is `undefined`, and MUST preserve an
  explicit non-`undefined` value (including an explicit `null`) unchanged.
- **endpoint-ignore-warning-default**: `toEndpoint` MUST default
  `ignoreProjectWarning` to `false` when `EndpointRow.ignoreProjectWarning` is
  `undefined`.
- **endpoint-dns-defaults**: `toEndpoint` MUST default each of `dnsCheckA`,
  `dnsCheckAaaa`, and `dnsCheckCname` to `true` when the corresponding
  `EndpointRow` field is `undefined`, and MUST preserve an explicit `false`
  value rather than overwriting it.
- **site-group-rename**: `toSite` MUST map `SiteRow.siteGroupId` to
  `SiteView.groupId`; the resulting `SiteView` MUST NOT carry a
  `siteGroupId` field.
- **group-crud**: `listGroups`, `createGroup`, `updateGroup`, and
  `deleteGroup` MUST call `GET`, `POST`, `PATCH`, and `DELETE` respectively
  against `/config/site-groups` (a specific group by appending `/{id}` for
  update and delete), and each of `listGroups`/`createGroup`/`updateGroup`
  MUST return its result mapped through `toGroup`.
- **site-crud**: `listSites`, `createSite`, and `updateSite` MUST call `GET`,
  `POST`, and `PATCH` against `/config/sites` (a specific site by appending
  `/{id}` for update), each returning its result mapped through `toSite`;
  `createSite`'s request body MUST rename the caller's `groupId` to
  `siteGroupId`.
- **endpoint-list-scope**: `listEndpoints(api, siteId)` MUST request
  `/config/endpoints?siteId={siteId}` (URL-encoded) and MUST map every
  returned row through `toEndpoint`; `listAllEndpoints` MUST request the bare
  `/config/endpoints` path with no `siteId` query parameter.
- **endpoint-kind-required**: `createEndpoint`'s parameter type (`Partial<Omit<EndpointView, "id" | "siteId">> & { url: string }`) leaves `kind` optional, and the client passes `body.kind` through unchecked — `monitored-sites.ts` only re-exports `ENDPOINT_KINDS` from `@/lib/endpoint-kinds` and never validates against it. A caller that omits `kind` sends no `kind` field; the status-server's create-endpoint schema accepts it as an optional string and the `kind` column defaults to `"http"`, so the endpoint is stored as an HTTP monitor.
- **endpoint-write-field-list**: `createEndpoint` and `updateEndpoint` MUST
  send exactly the fields named on `EndpointWriteFields` (every `EndpointView`
  field except `id` and `siteId`, plus `siteId`/`url` on create); a field the
  caller omits from `body` MUST be sent as `undefined`, and an `undefined`
  field MUST NOT appear in the serialized JSON body at all.
- **integration-crud**: `listIntegrations`, `createIntegration`,
  `updateIntegration`, and `deleteIntegration` MUST call `GET`, `POST`,
  `PATCH`, and `DELETE` against `/config/integrations` (a specific
  integration by `/{id}`), passing the caller's `body` object to
  `JSON.stringify` unmodified — no field allow-list is applied, unlike the
  group/site/endpoint functions.
- **ignored-projects-list**: `listIgnoredProjects` MUST return the result of
  `GET /config/ignored-projects` unmodified (no per-row mapping).
- **ignore-project-fanout**: `ignoreProjects` MUST issue one
  `POST /config/ignored-projects` request per project in its input array, in
  parallel via `Promise.all`, and MUST reject as soon as any one of those
  requests rejects; the outcome of every other request already in flight at
  that point MUST NOT be awaited or reported.
- **unignore-project-id**: `unignoreProject` MUST build its request path as
  `DELETE /config/ignored-projects/{id}`, where `{id}` is
  `encodeURIComponent` applied to the string `${platform}|${projectName}`.

### peers.ts

- **peer-token-write-semantics**: a caller's `Partial<PeerWrite>` update MUST
  be interpreted as: a `string` value for `token` sets or replaces the stored
  token; `null` clears it; omitting the `token` key from the update object
  MUST leave the stored token unchanged, since a redacted token cannot be
  echoed back to distinguish "no change" from "clear."
- **peer-view-redaction**: `PeerView` MUST NOT carry the raw token value; it
  MUST carry only `hasToken`, a boolean indicating whether a token is set.
- **peer-write-passthrough**: `createPeer` and `updatePeer` MUST serialize
  the caller's `body`/`Partial<PeerWrite>` object directly via
  `JSON.stringify`, with no field allow-list step — unlike
  `monitored-sites.ts`'s group/site/endpoint functions, which rebuild an
  explicit `fields` object before stringifying.
- **peer-crud-routes**: `listPeers`, `createPeer`, `updatePeer`, and
  `deletePeer` MUST call `GET`, `POST`, `PATCH`, and `DELETE` respectively
  against `/config/peers` (a specific peer by `/{id}` for update and
  delete).

## Appearance

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component.

## States

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component.

## Accessibility

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-api-001 | json-204-empty | `json<void>` call whose `fetch` resolves `{ok: true, status: 204}` | resolves `undefined`; `res.json()` is never invoked |
| status-web-api-002 | json-ok-body | `json<T>` call whose `fetch` resolves `{ok: true, status: 200, json: () => ({a: 1})}` | resolves `{a: 1}` |
| status-web-api-003 | json-error-message, json-error-detail, site-crud | `updateSite(api, "x", {name: "New"})`; `fetch` resolves `{ok: false, status: 404}` with JSON body `{"error": "not found"}` | rejects with `Error("PATCH /api/config/sites/x → 404 — not found")` |
| status-web-api-004 | json-error-detail, peer-crud-routes | `createPeer(api, {...})`; `fetch` resolves `{ok: false, status: 500}` with a body that fails to parse as JSON | rejects with `Error("POST /api/config/peers → 500")` — no ` — ` suffix |
| status-web-api-005 | url-join | `basePath: "/api"`, `path: "/config/peers"` | `url(path) === "/api/config/peers"` |
| status-web-api-006 | event-source-target | default client, `path: "/live/stream"` | `eventSource(path)` constructs `new EventSource("/api/live/stream")` |
| status-web-api-007 | (n/a — mapper passthrough, traced to `monitored-sites.test.ts`) | `toGroup({id: "g", slug: "s", name: "N", retentionDays: 14})` | returns `{id: "g", slug: "s", name: "N", retentionDays: 14}` |
| status-web-api-008 | site-group-rename (traced to `monitored-sites.test.ts`) | `toSite({id: "s1", slug: "site", name: "Site", siteGroupId: "g1"})` | `groupId === "g1"` |
| status-web-api-009 | endpoint-optional-field-defaults (traced to `monitored-sites.test.ts`) | `toEndpoint(row)` with `row.environment` absent | `environment === null` |
| status-web-api-010 | endpoint-dns-defaults (traced to `monitored-sites.test.ts`) | `toEndpoint(row)` with `dnsCheckA`/`dnsCheckAaaa`/`dnsCheckCname` all absent | all three `=== true` |
| status-web-api-011 | endpoint-dns-defaults (traced to `monitored-sites.test.ts`) | `toEndpoint(row)` with `dnsCheckCname: false`, the other two absent | `dnsCheckCname === false`, `dnsCheckA === true` |
| status-web-api-012 | peer-token-write-semantics, peer-write-passthrough | `updatePeer(api, "p1", {label: "x"})` | serialized request body is `{"label":"x"}` — no `token` key present at all |
| status-web-api-013 | peer-token-write-semantics | `updatePeer(api, "p1", {token: null})` | serialized request body includes `"token":null` |
| status-web-api-014 | ignore-project-fanout | `ignoreProjects(api, [{platform: "vercel", projectName: "a"}, {platform: "railway", projectName: "b"}])` | exactly two `POST /config/ignored-projects` requests are issued, via `Promise.all`, not sequential `await`s |
| status-web-api-015 | unignore-project-id | `unignoreProject(api, "vercel", "my/app")` | request path is `DELETE /config/ignored-projects/vercel%7Cmy%2Fapp` |

## Edge Cases

- **Null and empty input**: `toEndpoint` MUST turn an absent `environment`,
  `platform`, `deployProject`, or `expectBody` into `null`, and an absent
  `ignoreProjectWarning` into `false` (endpoint-optional-field-defaults,
  endpoint-ignore-warning-default). `ignoreProjects` called with an empty
  array MUST resolve immediately via `Promise.all([])`, issuing no request.
  `listEndpoints`/`unignoreProject` perform no client-side check that
  `siteId`/`platform`/`projectName` is non-empty before URL-encoding it into
  the request; an empty string is sent to the backend as-is.
- **Boundary values**: none of `retentionDays`, `checkIntervalSeconds`, or
  `expectedStatus` is range-checked by this module before being sent;
  `environment` and `platform` are typed against the `ENVIRONMENTS`/
  `PLATFORMS` constants but, like `kind` (see `endpoint-kind-required`),
  nothing in `monitored-sites.ts` validates membership in either list
  before a request is sent.
- **Concurrent access**: this is single-threaded browser JavaScript; no two
  calls into these files ever interleave on the same value. Multiple
  concurrent calls to `json`/`fetch`/`eventSource` are independent — no
  shared mutable state exists outside each call's own closures (the
  `defaultClient` singleton is stateless: only `basePath` and a resolved
  `fetch` reference). `ignore-project-fanout`'s `Promise.all` deliberately
  issues its N requests concurrently; when one rejects, the already-issued
  sibling requests continue running to completion in the background, but
  neither their results nor their errors are surfaced.
- **Error states**: a non-ok HTTP response from any of these functions MUST
  surface as the crafted `Error` from `json-error-message`/`json-error-detail`.
  A network-level failure — `fetch()` itself rejecting because the request
  never reached a server (offline, DNS failure, CORS) — is caught nowhere in
  `client.ts`, `monitored-sites.ts`, or `peers.ts`; it propagates to the
  caller as whatever error `fetch()` produces, which is a different shape
  than the `${method} ${url} → ${status}` message a non-ok response
  produces.
- **Offline or disconnected state**: the same uncaught-`fetch()`-rejection
  behavior above covers a `json`/`fetch` call made while offline. For
  `eventSource(path)`, this file only constructs the native `EventSource`
  object; reconnection after the connection drops is entirely the browser's
  native `EventSource` behavior — none of these three files listens for or
  reacts to an SSE `error` event, or re-creates the `EventSource` itself.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `basePath` | `string` | `DEFAULT_API_BASE` (`"/api"`) | `createStatusApiClient`/`StatusApiProvider` option; every relative `path` is joined onto this prefix by `url()`. |
| `fetch` | `typeof fetch` | `globalThis.fetch` | `createStatusApiClient` option; injected to install a test double or a `fetch` polyfill, resolved fresh on every call (late-fetch-resolution). |
| `client` | `StatusApiClient` | none — the provider builds its own | `StatusApiProvider` prop; when given, `useStatusApi()` returns it verbatim instead of a provider-constructed client. |
| `body.environment` | one of `ENVIRONMENTS` (`"production" \| "staging" \| "testing"`) | none — caller-supplied | endpoint create/update field; not validated against `ENVIRONMENTS` by this module. |
| `body.platform` | one of `PLATFORMS` (`"vercel" \| "railway" \| "cloudflare" \| "crunchy"`) | none — caller-supplied | endpoint create/update field; not validated against `PLATFORMS` by this module. |
| `body.kind` | one of `ENDPOINT_KINDS` (`"http" \| "frontend" \| "admin" \| "health" \| "custom" \| "dns"`) | none — caller-supplied, optional in the type | omitted → server default `"http"`, per `endpoint-kind-required`. |
| `body.token` (peers) | `string \| null` | omitted key = leave unchanged | see `peer-token-write-semantics`. |

## Deep Linking

Not applicable: `client.ts`, `monitored-sites.ts`, and `peers.ts` are a JSON/SSE API client and configuration-CRUD module, not a navigable UI surface — none of the three constructs or consumes a page route or deep link.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not an i18n key) | `${method} ${url} → ${status}` (plus an optional ` — ${text}` detail suffix) | `client.ts`'s `json<T>` throws this as a plain `Error` message on every non-ok response (json-error-message, json-error-detail); it is English-only and never sourced from a localization resource. |

## Accessibility Options

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component; none of the three files renders anything or reads a motion, contrast, or color-differentiation setting.

## Feature Flags

Not applicable: none of `client.ts`, `monitored-sites.ts`, or `peers.ts` references a feature-flag key or gate; every exported function always executes the same logic.

## Analytics

Not applicable: none of the three files calls the package's telemetry client (`src/telemetry/client.ts`) or any other analytics API.

## Privacy

- **Data collected**: `peers.ts`'s `PeerWrite.token` (a fleet shared secret) is
  the one sensitive value the given sources handle; `monitored-sites.ts` and
  `client.ts` carry only operational/infrastructure configuration (site,
  group, and endpoint records), never end-user personal data.
- **Storage**: none of the three files persists any value locally; every
  read returns a fresh `fetch` response, and nothing is cached or written to
  disk or `localStorage` by this module.
- **Transmission**: `peers.ts` sends `token` as a JSON request-body field
  (via `createPeer`/`updatePeer`), never in a URL or query string. The
  transport scheme is whatever `basePath` resolves through — ordinarily a
  same-origin path, so TLS is inherited from the hosting page rather than
  enforced by these files themselves.
- **Retention**: none — a call's `token` value is not retained by these
  files beyond the single outbound request; `PeerView.hasToken` is the only
  signal a subsequent read returns, per peer-view-redaction.

## Logging

Not applicable: none of `client.ts`, `monitored-sites.ts`, or `peers.ts` calls `console.*` or any logger; the thrown `Error` from `json<T>` is the only signal these files produce, and it propagates to the caller rather than being logged here.

## Platform Notes

- **SwiftUI**: model `StatusApiClient` as a small `Sendable` struct or an
  `actor` wrapping `URLSession` (`url`/`data(for:)` in place of
  `fetch`/`json`), decoding with `JSONDecoder` in place of `res.json()`, and
  throwing a typed `Error` in place of the crafted `Error` message; expose it
  through a `@Observable` environment object or an `EnvironmentKey` as the
  analogue of `StatusApiProvider`/`useStatusApi`. `eventSource`'s SSE stream
  has no Foundation counterpart — a port needs `URLSession`'s
  `bytes(for:)` async sequence with a manual `text/event-stream` line parser,
  or a small third-party SSE client.
- **Compose**: build the same shape over Ktor's `HttpClient` (or OkHttp) with
  `kotlinx.serialization` in place of `res.json()`; expose the client through
  a `CompositionLocal` as the analogue of the React context/`Provider`. As on
  Apple, there is no native `EventSource`; a port needs OkHttp's SSE support
  or a manual chunked-response reader over the same `HttpClient`.
- **React/Web**: the source. `client.ts` uses the browser's native `fetch`
  and `EventSource` and a React `Context`/`useMemo`/`useContext` trio for
  provider/hook wiring; `monitored-sites.ts` and `peers.ts` are plain
  `async`/`Promise`-returning functions with no framework dependency beyond
  the `StatusApiClient` type they're given. Tests are colocated
  (`monitored-sites.test.ts`) and run under Vitest.
- **AppKit / UIKit**: the same `URLSession`-based client as the SwiftUI
  bullet applies unchanged — this layer has no view-framework dependency —
  but with no environment-value system, the client is typically handed to
  view controllers through a plain injected singleton or dependency-injection
  container rather than an environment key.
- **WinUI 3**: model `StatusApiClient` as a class exposing
  `Task<T> JsonAsync<T>(string path, ...)` and `Task<HttpResponseMessage>
  FetchAsync(...)` built on a shared `HttpClient` instance, with
  `System.Text.Json` in place of `res.json()` and a thrown, typed exception
  in place of the crafted `Error` message; `Task`/`async`/`await` replace
  `Promise`/`async`/`await` directly. `GroupRow`/`SiteRow`/`EndpointRow` and
  their `View` counterparts become `record` types; the `toGroup`/`toSite`/
  `toEndpoint` mappers become static methods or constructors on those
  records. A bound UI would surface results through `ObservableCollection`/
  `INotifyPropertyChanged`, which none of these three files has a
  counterpart for since they return plain arrays, not a live-bound
  collection. `Windows.Storage` has no role here either, since none of these
  files persists anything. .NET has no built-in SSE client analogous to
  `EventSource`; a port needs `HttpClient`'s streaming response with a
  manual `text/event-stream` parser, or a NuGet SSE package.

## Design Decisions

**Decision**: `useStatusApi()` falls back to a single module-level
`defaultClient` singleton, built once at import time with no `basePath` or
`fetch` override, shared by every caller that has no ancestor
`StatusApiProvider`.
**Rationale**: matches the source directly — `const defaultClient =
createStatusApiClient();` is declared at module scope, and the doc comment on
`useStatusApi` states it returns "the same-origin default when no provider is
mounted."
**Approved**: pending.

**Decision**: mounting a bare `<StatusApiProvider>` with no `client` or
`basePath` prop builds a brand-new `StatusApiClient` (via `useMemo`) rather
than reusing the module's `defaultClient`; it behaves identically (same
default `basePath`, same global `fetch`) but is a distinct object reference.
**Rationale**: `useMemo(() => client ?? createStatusApiClient({basePath}),
[client, basePath])` always calls `createStatusApiClient` when `client` is
falsy — it never falls back to the outer `defaultClient` constant, even
though the two clients are behaviorally interchangeable.
**Approved**: pending.

**Decision**: `EndpointWriteFields` is derived from `EndpointView`
(`Partial<Omit<EndpointView, "id" | "siteId">>`) instead of being hand-listed.
**Rationale**: the inline comment states this directly: "Exactly EndpointView's
writable fields (derived — adding a column to EndpointView can't silently
drop it from create/update)." A new `EndpointView` field automatically
becomes writable through `createEndpoint`/`updateEndpoint` with no second
edit required.
**Approved**: pending.

**Decision**: `ignoreProjects` fans its per-project calls out with
`Promise.all` rather than a sequential loop or a concurrency-limited batch.
**Rationale**: the doc comment states the unique `(platform, projectName)`
index makes a re-ignore idempotent, and that issuing the batch in parallel
makes ignoring a large batch cost one round-trip's latency rather than N; the
documented tradeoff is that one project's failure rejects the whole batch
immediately (`Promise.all` semantics) instead of reporting a per-project
partial result.
**Approved**: pending.

**Decision**: `peers.ts`'s `createPeer`/`updatePeer` serialize the caller's
object directly, while `monitored-sites.ts`'s group/site/endpoint functions
rebuild an explicit `fields` object before serializing.
**Rationale**: this is a genuine divergence between the two sibling files,
not a typo — `monitored-sites.ts`'s comments explain its allow-list exists
because the hub's own generated API-type package does not match the status
backend's schema for these routes, a concern `peers.ts`'s simpler
`PeerWrite` shape does not have.
**Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | failed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | partial | Security |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | partial | Security |
| [secure-data-storage](agenticdevelopercookbook://compliance/privacy-and-data#secure-data-storage) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | partial | Internationalization |

`separation-of-concerns` passes: all three files are pure request-building and mapping functions with no JSX and no DOM access; `monitored-sites.ts` and `peers.ts` depend only on the `StatusApiClient` port passed in as an argument, never constructing their own `fetch` call or base path. `unit-test-coverage` is `partial`: `monitored-sites.ts`'s three mapping functions (`toGroup`, `toSite`, `toEndpoint`) are directly tested by `monitored-sites.test.ts`; `client.ts` and `peers.ts` have no test file found in the repository. `explicit-error-handling` is `partial`: `json<T>` explicitly throws a crafted `Error` on a non-ok HTTP status, but a network-level failure — the underlying `fetch()` call rejecting outright (offline, DNS failure, CORS) — is caught nowhere in these three files and propagates as whatever error `fetch()` itself produces, not the `${method} ${url} → ${status}` shape. `error-response-handling` passes: every non-ok JSON response is normalized into one thrown `Error` carrying method, URL, status, and an optional detail string, and a `204` response is explicitly distinguished from every other `ok` status. `timeout-configuration` fails: none of the three files sets a request timeout or uses an `AbortController`/`AbortSignal`; a hung request waits indefinitely. `retry-with-backoff` fails: no retry logic exists anywhere in `client.ts`, `monitored-sites.ts`, or `peers.ts`; a failed call is not retried by this module. `data-integrity` passes: every mapping function (`toGroup`/`toSite`/`toEndpoint`) is deterministic and total — every field has a defined fallback, so no field is ever silently dropped — and `ignoreProjects`'s `Promise.all` surfaces the first rejection rather than continuing past it unreported. `secure-transport` is `partial`: `peers.ts` sends a peer's `token` only as a JSON body field, never in a URL or query string, but neither this file nor `client.ts` requires an `https://` `basePath`; the transport scheme is whatever the caller configures. `token-lifecycle` is `partial`: `PeerWrite`'s write semantics support rotation (a new `token` string) and revocation (`null`) through an explicit caller action, but no expiration, automatic rotation, or lifetime policy exists anywhere in these three files. `secure-data-storage` passes: none of the three files persists any value — token, credential, or otherwise — to a local store; every read is a fresh network response, so this check's storage requirement has nothing to violate. `no-hardcoded-strings` is `partial`: `client.ts`'s `json<T>` throws an English-only diagnostic message (`${method} ${url} → ${status}` plus an optional detail) that is never sourced from a localization resource.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
