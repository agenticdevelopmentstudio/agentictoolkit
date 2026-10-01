---
id: eb7e9eeb-86f3-4053-827a-ea259833c6ad
title: Dashboard API
domain: agentictoolkit://cookbook/status/dashboard/api
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status dashboard's same-origin JSON/SSE port to its backend, the
  shared-client wiring consumers use to reach it, and the monitored-sites and
  peers configuration-CRUD clients built on it.
platforms:
- typescript
- web
tags:
- status
- api-client
- config
- peers
- monitoring
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
related:
- agentictoolkit://cookbook/status/service/routes
- agentictoolkit://cookbook/status/service/peers
- agentictoolkit://cookbook/status/service/monitor/endpoint-kinds
references:
- packages/web/packages/status-web/src/api/client.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/monitored-sites.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/monitored-sites.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/peers.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/endpoint-kinds.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Dashboard API

## Overview

The status dashboard's one port onto its backend, and the two configuration-CRUD clients
built on it. The API client exposes `url`, `request`, `requestJSON`, and
`openEventStream`, all resolved relative to a base path — plus a constructor, a
module-level default client singleton, and a client provider/accessor pair that
every panel and hook call instead of naming a base path themselves. The
monitoring-configuration client covers groups, sites, endpoints, integrations,
and ignored deploy projects, each with a backend row shape mapped to a frontend
view shape. The peer-fleet client is the fleet-membership client: list/create/update/delete
for the peer monitors this one polls, including the shared-secret `token`
field's write-only semantics. All three clients talk to the status backend
through the caller-supplied API client, never naming `/api` themselves except in
the client's one default-base-path constant.

## Behavioral Requirements

### API client

- **default-base-path**: Constructing the client MUST default the base path to
  a fixed `"/api"` string when the caller supplies no base-path option.
- **url-join**: The url operation MUST return `${basePath}${path}` — a plain
  string concatenation with no encoding, normalization, or leading-slash
  correction.
- **late-request-resolution**: The request operation MUST resolve which
  underlying network-request function to call — an injected one if the
  client was constructed with one, otherwise the platform's default — at the
  time of each call, not once when the client is constructed.
- **json-content-type**: The JSON-request operation MUST send a
  `"Content-Type": "application/json"` header on every request, and MUST let
  any `Content-Type` present in the caller's own headers take precedence over
  that default.
- **json-ok-body**: The JSON-request operation MUST return the parsed
  response body for any successful response whose status is not `204`.
- **json-204-empty**: The JSON-request operation MUST return nothing for a
  successful response with status `204`, without attempting to parse a body.
- **json-error-message**: The JSON-request operation MUST throw an error when
  the response is not successful, with a message of exactly
  `${method} ${url} → ${status}`, where `method` defaults to `"GET"` when the
  caller supplies none, and `url` is the request's resolved URL.
- **json-error-detail**: the thrown error message MUST be suffixed with
  ` — ${text}` when the failed response's body parses as JSON and yields a
  usable detail string, checked in this order: a string `error` field, then
  `error.message`, then a top-level `message` field; the message MUST carry
  no such suffix when the body does not parse as JSON or none of those
  fields is present.
- **event-stream-target**: The open-event-stream operation MUST open a
  Server-Sent-Events connection at the resolved URL for the given path.
- **provider-client-selection**: The client provider MUST use a
  caller-supplied client when one is given, and otherwise MUST construct one
  from the base-path option.
- **provider-memoization**: the client the provider supplies to its consumers
  MUST be cached for as long as the client/base-path identity is unchanged,
  so that re-evaluating the provider with the same identity MUST NOT
  construct a new client instance.
- **accessor-fallback**: The client accessor MUST return the nearest ancestor
  provider's client when one is active, and MUST otherwise return the
  module-level default client singleton, built once at load with no
  arguments.

### Monitoring configuration client

- **endpoint-optional-field-defaults**: The endpoint mapper MUST default each
  of `environment`, `platform`, `deployProject`, and `expectBody` to `null`
  when the corresponding backend row field is absent, and MUST preserve an
  explicit non-absent value (including an explicit `null`) unchanged.
- **endpoint-ignore-warning-default**: The endpoint mapper MUST default
  `ignoreProjectWarning` to `false` when the backend row's field is absent.
- **endpoint-dns-defaults**: The endpoint mapper MUST default each of
  `dnsCheckA`, `dnsCheckAaaa`, and `dnsCheckCname` to `true` when the
  corresponding backend row field is absent, and MUST preserve an explicit
  `false` value rather than overwriting it.
- **site-group-rename**: The site mapper MUST map the backend row's
  group-identifier field to the frontend view's `groupId` field; the
  resulting view MUST NOT carry the backend's original group-identifier
  field name.
- **group-crud**: Listing, creating, updating, and deleting groups MUST call
  `GET`, `POST`, `PATCH`, and `DELETE` respectively against
  `/config/site-groups` (a specific group by appending `/{id}` for update and
  delete), and each of the listing/creating/updating operations MUST return
  its result mapped through the group mapper.
- **site-crud**: Listing, creating, and updating sites MUST call `GET`,
  `POST`, and `PATCH` against `/config/sites` (a specific site by appending
  `/{id}` for update), each returning its result mapped through the site
  mapper; the create-site request body MUST rename the caller's `groupId`
  field to the backend's group-identifier field name.
- **endpoint-list-scope**: Listing endpoints by site MUST request
  `/config/endpoints?siteId={siteId}` (URL-encoded) and MUST map every
  returned row through the endpoint mapper; listing all endpoints MUST
  request the bare `/config/endpoints` path with no `siteId` query
  parameter.
- **endpoint-kind-required**: Creating an endpoint leaves `kind` optional in
  its input shape, and the client passes a caller-supplied `kind` through
  unchecked — the monitoring-configuration client only re-exports the list of
  valid endpoint kinds and never validates against it. A caller that omits
  `kind` sends no `kind` field; the status backend's create-endpoint contract
  accepts it as an optional string and defaults it server-side to `"http"`,
  so the endpoint is stored as an HTTP monitor.
- **endpoint-write-field-list**: Creating and updating an endpoint MUST send
  exactly the endpoint's own writable fields (every endpoint-view field
  except its identifier and site identifier, plus the site identifier/URL on
  create); a field the caller omits MUST be sent as absent, and an absent
  field MUST NOT appear in the serialized request body at all.
- **integration-crud**: Listing, creating, updating, and deleting
  integrations MUST call `GET`, `POST`, `PATCH`, and `DELETE` against
  `/config/integrations` (a specific integration by `/{id}`), passing the
  caller's body object through unmodified — no field allow-list is applied,
  unlike the group/site/endpoint operations.
- **ignored-projects-list**: Listing ignored projects MUST return the result
  of `GET /config/ignored-projects` unmodified (no per-row mapping).
- **ignore-project-fanout**: Marking a batch of projects ignored MUST issue
  one `POST /config/ignored-projects` request per project in its input
  array, concurrently rather than sequentially, and MUST reject as soon as
  any one of those requests rejects; the outcome of every other request
  already in flight at that point MUST NOT be awaited or reported.
- **unignore-project-id**: Un-ignoring a project MUST build its request path
  as `DELETE /config/ignored-projects/{id}`, where `{id}` is the URL-encoded
  string `${platform}|${projectName}`.

### Peer fleet client

- **peer-token-write-semantics**: a caller's partial update to a peer MUST be
  interpreted as: a string value for `token` sets or replaces the stored
  token; `null` clears it; omitting the `token` field from the update MUST
  leave the stored token unchanged, since a redacted token cannot be echoed
  back to distinguish "no change" from "clear."
- **peer-view-redaction**: A peer's returned view MUST NOT carry the raw
  token value; it MUST carry only `hasToken`, a boolean indicating whether a
  token is set.
- **peer-write-passthrough**: Creating and updating a peer MUST serialize the
  caller's body object directly, with no field allow-list step — unlike the
  monitoring-configuration client's group/site/endpoint operations, which
  rebuild an explicit fields object before serializing.
- **peer-crud-routes**: Listing, creating, updating, and deleting peers MUST
  call `GET`, `POST`, `PATCH`, and `DELETE` respectively against
  `/config/peers` (a specific peer by `/{id}` for update and delete).

## Appearance

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component.

## States

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component.

## Accessibility

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-api-001 | json-204-empty | A JSON request whose underlying response resolves as successful with status `204` | resolves to nothing; the body is never parsed |
| status-web-api-002 | json-ok-body | A JSON request whose underlying response resolves as successful with status `200` and body `{a: 1}` | resolves `{a: 1}` |
| status-web-api-003 | json-error-message, json-error-detail, site-crud | Update a site's name; the underlying response resolves as unsuccessful with status `404` and JSON body `{"error": "not found"}` | rejects with an error reading `PATCH /api/config/sites/x → 404 — not found` |
| status-web-api-004 | json-error-detail, peer-crud-routes | Create a peer; the underlying response resolves as unsuccessful with status `500` and a body that fails to parse as JSON | rejects with an error reading `POST /api/config/peers → 500` — no ` — ` suffix |
| status-web-api-005 | url-join | base path `/api`, path `/config/peers` | the joined URL is `/api/config/peers` |
| status-web-api-006 | event-stream-target | default client, path `/live/stream` | the open-event-stream operation opens a Server-Sent-Events connection at `/api/live/stream` |
| status-web-api-007 | (n/a — mapper passthrough, traced to the monitoring-configuration client's test file) | Group mapper given a row with an id, slug, name, and a 14-day retention | returns the same fields unchanged |
| status-web-api-008 | site-group-rename (traced to the monitoring-configuration client's test file) | Site mapper given a row whose group-identifier field is `"g1"` | the mapped view's `groupId` is `"g1"` |
| status-web-api-009 | endpoint-optional-field-defaults (traced to the monitoring-configuration client's test file) | Endpoint mapper given a row with `environment` absent | mapped `environment` is `null` |
| status-web-api-010 | endpoint-dns-defaults (traced to the monitoring-configuration client's test file) | Endpoint mapper given a row with all three DNS-check fields absent | all three default to `true` |
| status-web-api-011 | endpoint-dns-defaults (traced to the monitoring-configuration client's test file) | Endpoint mapper given a row with `dnsCheckCname: false` and the other two absent | `dnsCheckCname` stays `false`, `dnsCheckA` defaults to `true` |
| status-web-api-012 | peer-token-write-semantics, peer-write-passthrough | Update a peer's label only, without touching `token` | the serialized request body carries only the label field — no `token` key present at all |
| status-web-api-013 | peer-token-write-semantics | Update a peer with `token: null` | the serialized request body includes `"token": null` |
| status-web-api-014 | ignore-project-fanout | Mark two projects ignored in one call | exactly two `POST /config/ignored-projects` requests are issued, concurrently rather than sequentially |
| status-web-api-015 | unignore-project-id | Un-ignore a project identified by platform `vercel` and name `my/app` | request path is `DELETE /config/ignored-projects/vercel%7Cmy%2Fapp` |

## Edge Cases

- **Null and empty input**: The endpoint mapper MUST turn an absent
  `environment`, `platform`, `deployProject`, or `expectBody` into `null`,
  and an absent `ignoreProjectWarning` into `false`
  (endpoint-optional-field-defaults, endpoint-ignore-warning-default).
  Marking an empty batch of projects ignored MUST resolve immediately with
  no request issued. Listing endpoints by site, or un-ignoring a project,
  perform no client-side check that the site identifier/platform/project
  name is non-empty before URL-encoding it into the request; an empty
  string is sent to the backend as-is.
- **Boundary values**: none of `retentionDays`, `checkIntervalSeconds`, or
  `expectedStatus` is range-checked by this client before being sent;
  `environment` and `platform` are typed against a fixed set of allowed
  values but, like `kind` (see endpoint-kind-required), nothing in the
  monitoring-configuration client validates membership in either set before
  a request is sent.
- **Concurrent access**: no two calls into this client interleave against
  the same value in this component's own state; the client itself holds
  only its base path and a resolved network-request function, so multiple
  concurrent JSON-request/request/open-event-stream calls are independent,
  each with its own closure of state. The fan-out in ignore-project-fanout
  deliberately issues its N requests concurrently; when one rejects, the
  already-issued sibling requests continue running to completion in the
  background, but neither their results nor their errors are surfaced.
  (This assumes a single-threaded execution model; see Platform Notes for
  what a multi-threaded port needs.)
- **Error states**: a non-ok response from any of these operations MUST
  surface as the crafted error from json-error-message/json-error-detail. A
  network-level failure — the underlying request itself failing because it
  never reached a server (offline, DNS failure, a blocked cross-origin
  request) — is caught nowhere in this component; it propagates to the
  caller as whatever error the underlying network layer produces, which is
  a different shape than the `${method} ${url} → ${status}` message a
  non-ok response produces.
- **Offline or disconnected state**: the same uncaught-network-failure
  behavior above covers a request made while offline. For the
  open-event-stream operation, this component only opens the connection;
  reconnection after the connection drops is entirely the underlying
  Server-Sent-Events implementation's own behavior — none of these
  operations listens for or reacts to a stream error event, or re-opens the
  connection itself.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Base path | text | `/api` | Client-constructor/provider option; every relative path is joined onto this prefix by the url operation. |
| Network-request function | function | the platform's default | Client-constructor option; injected to install a test double or a polyfill, resolved fresh on every call (late-request-resolution). |
| Client | API client instance | none — the provider builds its own | Provider option; when given, the client accessor returns it verbatim instead of a provider-constructed client. |
| `body.environment` | one of: production, staging, testing | none — caller-supplied | endpoint create/update field; not validated against the allowed set by this client. |
| `body.platform` | one of: vercel, railway, cloudflare, crunchy | none — caller-supplied | endpoint create/update field; not validated against the allowed set by this client. |
| `body.kind` | one of: http, frontend, admin, health, custom, dns | none — caller-supplied, optional | omitted → server default `http`, per endpoint-kind-required. |
| `body.token` (peers) | text or none | omitted field = leave unchanged | see peer-token-write-semantics. |

## Deep Linking

Not applicable: this API client and its configuration-CRUD clients are not a navigable UI surface — none of them constructs or consumes a page route or deep link.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not an i18n key) | `${method} ${url} → ${status}` (plus an optional ` — ${text}` detail suffix) | The JSON-request operation throws this as a plain error message on every non-ok response (json-error-message, json-error-detail); it is English-only and never sourced from a localization resource. |

## Accessibility Options

Not applicable — this is a headless API client and configuration-CRUD module, not a visual component; none of it renders anything or reads a motion, contrast, or color-differentiation setting.

## Feature Flags

Not applicable: none of this component's operations reference a feature-flag key or gate; every exported operation always executes the same logic.

## Analytics

Not applicable: none of these operations call the package's telemetry client or any other analytics API.

## Privacy

- **Data collected**: the peer-fleet client's `token` field (a fleet shared
  secret) is the one sensitive value the given sources handle; the
  monitoring-configuration client and the API client carry only
  operational/infrastructure configuration (site, group, and endpoint
  records), never end-user personal data.
- **Storage**: none of these clients persists any value locally; every read
  returns a fresh network response, and nothing is cached or written to
  disk or local browser storage by this module.
- **Transmission**: the peer-fleet client sends `token` as a JSON
  request-body field (via create/update peer), never in a URL or query
  string. The transport scheme is whatever the base path resolves through —
  ordinarily a same-origin path, so secure transport is inherited from the
  hosting page rather than enforced by these clients themselves.
- **Retention**: none — a call's `token` value is not retained by these
  clients beyond the single outbound request; `hasToken` is the only signal
  a subsequent read returns, per peer-view-redaction.

## Logging

Not applicable: none of these clients calls a logging facility; the thrown error from the JSON-request operation is the only signal this component produces, and it propagates to the caller rather than being logged here.

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
- **React/Web**: the source. The API client is `StatusApiClient`, constructed
  via `createStatusApiClient` and consumed through
  `StatusApiProvider`/`useStatusApi` (React `Context`/`useMemo`/`useContext`);
  its `fetch`/`json`/`eventSource` operations wrap the browser's native
  `fetch` and `EventSource`, and `monitored-sites.ts`/`peers.ts` are plain
  `async`/`Promise`-returning functions with no framework dependency beyond
  the client type they're given. The concurrency assumptions in Edge Cases
  hold because this is single-threaded browser JavaScript — no two calls
  interleave on the same value — and `ignoreProjects`'s fan-out uses
  `Promise.all`. Tests are colocated (`monitored-sites.test.ts`) and run
  under Vitest.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/api/` |

## Design Decisions

**Decision**: `useStatusApi()` falls back to a single module-level
`defaultClient` singleton, built once at import time with no `basePath` or
`fetch` override, shared by every caller that has no ancestor
`StatusApiProvider`. (React/Web implementation.)
**Rationale**: matches the source directly — `const defaultClient =
createStatusApiClient();` is declared at module scope, and the doc comment on
`useStatusApi` states it returns "the same-origin default when no provider is
mounted."
**Approved**: pending.

**Decision**: mounting a bare `<StatusApiProvider>` with no `client` or
`basePath` prop builds a brand-new `StatusApiClient` (via `useMemo`) rather
than reusing the module's `defaultClient`; it behaves identically (same
default `basePath`, same global `fetch`) but is a distinct object reference.
(React/Web implementation.)
**Rationale**: `useMemo(() => client ?? createStatusApiClient({basePath}),
[client, basePath])` always calls `createStatusApiClient` when `client` is
falsy — it never falls back to the outer `defaultClient` constant, even
though the two clients are behaviorally interchangeable.
**Approved**: pending.

**Decision**: `EndpointWriteFields` is derived from `EndpointView`
(`Partial<Omit<EndpointView, "id" | "siteId">>`) instead of being hand-listed.
(React/Web implementation.)
**Rationale**: the inline comment states this directly: "Exactly EndpointView's
writable fields (derived — adding a column to EndpointView can't silently
drop it from create/update)." A new `EndpointView` field automatically
becomes writable through `createEndpoint`/`updateEndpoint` with no second
edit required.
**Approved**: pending.

**Decision**: `ignoreProjects` fans its per-project calls out with
`Promise.all` rather than a sequential loop or a concurrency-limited batch.
(React/Web implementation.)
**Rationale**: the doc comment states the unique `(platform, projectName)`
index makes a re-ignore idempotent, and that issuing the batch in parallel
makes ignoring a large batch cost one round-trip's latency rather than N; the
documented tradeoff is that one project's failure rejects the whole batch
immediately (`Promise.all` semantics) instead of reporting a per-project
partial result.
**Approved**: pending.

**Decision**: `peers.ts`'s `createPeer`/`updatePeer` serialize the caller's
object directly, while `monitored-sites.ts`'s group/site/endpoint functions
rebuild an explicit `fields` object before serializing. (React/Web
implementation.)
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
