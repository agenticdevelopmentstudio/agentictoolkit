---
id: a3e87176-5845-43ff-9041-af53437d605d
title: Hub Domain Monitored Sites
domain: agentictoolkit://cookbook/data/monitored-sites
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Web data client for the Status Sites monitoring domain: generic-CRUD groups,
  sites, and endpoints over /api/monitoring/*, the 1:M group-to-site-to-endpoint model,
  owner/workspace scoping, and the field renames each mapper performs.'
platforms:
- typescript
- web
tags:
- hub
- monitoring
- site-groups
- sites
- endpoints
- workspace
- crud
- api
depends-on: []
related: []
references:
- packages/web/packages/data/src/monitored-sites/monitored-sites.ts (agentictoolkit)
- packages/web/packages/data/src/monitored-sites/wire.ts (agentictoolkit)
- packages/web/packages/data/src/monitored-sites/index.ts (agentictoolkit)
- packages/web/packages/data/src/monitored-sites/__tests__/monitored-sites.test.ts
  (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Monitored Sites

## Overview

`monitored-sites.ts` and `wire.ts`, re-exported by `index.ts` as `@agentic-toolkit/data/monitored-sites`,
are the client for the Status Sites monitoring domain: `site-groups`, `sites`, and `endpoints`, backed
by generic CRUD over `/api/monitoring/site-groups`, `/api/monitoring/sites`, and
`/api/monitoring/endpoints`. Per the module's own top-of-file comment, the model matches the database,
not an earlier prototype: a site belongs to exactly one group (`sites.site_group_id`, `NOT NULL`, FK
`ON DELETE CASCADE`) and an endpoint belongs to exactly one site (same cascade) — a strict 1:M chain,
not the prototype's many-to-many `groupIds[]`. The whole chain is owner-scoped server-side, with an
optional `workspace` parameter on every operation that re-pins it to a workspace's owning principal.
`wire.ts` holds the backend row and request-body shapes (`GroupRow`, `SiteRow`, `EndpointRow`, and their
create/put bodies); `monitored-sites.ts` exports the three `toGroup`/`toSite`/`toEndpoint` mappers, the
`CreateGroupBody`/`UpdateGroupBody`/`CreateSiteBody`/`UpdateSiteBody`/`CreateEndpointBody`/`UpdateEndpointBody`
caller-facing shapes, the `ENDPOINT_KINDS` constant, and twelve exported functions — list/create/update/delete
for each of the three entities — each a thin request builder over the shared `authedJson`/`authedRequest` helpers from
`@agentic-toolkit/auth/client` (re-exported through `./http`). It is a headless **logic** module — no
visual surface — consumed today by the Dashboards (Site Monitoring) feature
(`packages/web/packages/features/dashboards/src/*`), so this recipe marks Appearance, States, and
Accessibility not applicable and carries the runtime contract entirely in Behavioral Requirements, per
the non-UI component guidance this recipe was authored under.

## Behavioral Requirements

**Mappers (`toGroup`, `toSite`, `toEndpoint`)**

- **site-group-view-shape**: `toGroup` MUST map a `GroupRow` verbatim to a `SiteGroupView` carrying
  `id`, `slug`, `name`, `retentionDays`, `createdAt`, and `updatedAt`, with no field renamed.
- **site-view-renames-group-id**: `toSite` MUST copy a `SiteRow`'s `siteGroupId` field into
  `SiteView.groupId`; every other field (`id`, `slug`, `name`, `createdAt`, `updatedAt`) MUST be copied
  unchanged.
- **endpoint-view-shape**: `toEndpoint` MUST map an `EndpointRow` verbatim to an `EndpointView` carrying
  `id`, `siteId`, `url`, `kind`, `expectedStatus`, `checkIntervalSeconds`, `isActive`, `createdAt`, and
  `updatedAt`, with no field renamed.

**Groups (`listGroups`, `createGroup`, `updateGroup`, `deleteGroup`)**

- **group-list-request**: `listGroups` MUST send `GET /api/monitoring/site-groups` with the query string
  `workspaceQuery(opts)` appends (empty when `opts.workspace` is absent).
- **group-list-sorted-by-name**: `listGroups` MUST return the mapped `SiteGroupView[]` sorted by `name`
  via `sortByText`'s locale-aware `localeCompare`, without mutating the array `authedJson` returned.
- **group-create-request**: `createGroup` MUST send `POST /api/monitoring/site-groups` (plus
  `workspaceQuery`) with a body built by `compact()` from `{ name, slug, retentionDays }`, dropping
  `retentionDays` from the JSON payload when the caller omits it, and MUST return `toGroup(row)`.
- **group-update-request**: `updateGroup` MUST send `PUT /api/monitoring/site-groups/<enc(id)>` (plus
  `workspaceQuery`) with a `compact()` patch of `{ name, slug, retentionDays }`, and MUST return
  `toGroup(row)`.
- **group-delete-request**: `deleteGroup` MUST send `DELETE /api/monitoring/site-groups/<enc(id)>` (plus
  `workspaceQuery`) via `authedRequest`, discarding any response body, and MUST resolve with no value.
- **group-delete-cascades**: per the module's own comment on `deleteGroup`, deleting a group MUST cascade
  at the database level (`FK ON DELETE CASCADE`) to remove every site in that group and every endpoint of
  those sites; this client issues one `DELETE` request and performs no separate cleanup call of its own.

**Sites (`listSites`, `createSite`, `updateSite`, `deleteSite`)**

- **site-belongs-to-exactly-one-group**: a `SiteView` MUST carry exactly one `groupId` as a required
  field — the interface's own doc comment states "the single group this site belongs to (1:M;
  required)" — and this client models no many-to-many group membership.
- **site-list-request**: `listSites` MUST send `GET /api/monitoring/sites` (plus `workspaceQuery`).
- **site-list-sorted-by-name**: `listSites` MUST return `sortByText(rows.map(toSite), name)`.
- **site-list-single-request-only**: `listSites` MUST NOT issue a second request to the site-groups
  endpoint or perform any client-side intersection against group membership. Per the function's own
  comment, an earlier implementation did both — a second round-trip, plus a silent-hiding bug, since
  generic-CRUD lists cap at 500 rows and a workspace with more than 500 groups could drop sites whose
  group fell past that cap even though the server still monitors them; the current single-request form
  replaced it.
- **site-create-request**: `createSite` MUST send `POST /api/monitoring/sites` (plus `workspaceQuery`)
  with a body of exactly `{ name, slug, siteGroupId: body.groupId }`, renaming `groupId` to
  `siteGroupId`, sent without passing through `compact()` — all three fields are required by
  `CreateSiteBody`, so none can be `undefined`.
- **site-update-request**: `updateSite` MUST send `PUT /api/monitoring/sites/<enc(id)>` (plus
  `workspaceQuery`) with a `compact()` patch of `{ name, slug, siteGroupId: body.groupId }` built from
  the optional `UpdateSiteBody` fields.
- **site-delete-request**: `deleteSite` MUST send `DELETE /api/monitoring/sites/<enc(id)>` (plus
  `workspaceQuery`), discarding the body, and MUST resolve with no value.
- **site-delete-cascades**: per the module's own comment on `deleteSite`, deleting a site MUST cascade at
  the database level to remove every endpoint that belongs to it.

**Endpoints (`listEndpoints`, `createEndpoint`, `updateEndpoint`, `deleteEndpoint`)**

- **endpoint-list-request**: `listEndpoints` MUST send `GET /api/monitoring/endpoints` with a query
  string built from `URLSearchParams({ siteId })`, appending `workspace=<opts.workspace>` via `qs.set`
  only when `opts.workspace` is given — this is the one function in the file that builds its query string
  by hand instead of through the shared `workspaceQuery` helper every other function here uses.
- **endpoint-list-double-filtered**: `listEndpoints` MUST re-filter the mapped rows client-side to
  `e.siteId === siteId`, in addition to the server-side `siteId` equality filter the query string already
  applies. Per the function's own comment, this client filter is retained as defense-in-depth and is
  redundant once the server has already scoped the response.
- **endpoint-list-sorted-by-url**: `listEndpoints` MUST return the filtered rows sorted by `url` via
  `sortByText`.
- **endpoint-create-request**: `createEndpoint` MUST send `POST /api/monitoring/endpoints` (plus
  `workspaceQuery`) with a `compact()` body of `{ siteId, url, kind, expectedStatus,
  checkIntervalSeconds, isActive }`, where `siteId` comes from the function's own `siteId` parameter, not
  from `body`.
- **endpoint-update-request**: `updateEndpoint` MUST send `PUT /api/monitoring/endpoints/<enc(id)>`
  (plus `workspaceQuery`) with a `compact()` patch of `{ url, kind, expectedStatus,
  checkIntervalSeconds, isActive }`; `siteId` MUST NOT appear in this patch, so this operation cannot
  reparent an endpoint to a different site.
- **endpoint-delete-request**: `deleteEndpoint` MUST send `DELETE /api/monitoring/endpoints/<enc(id)>`
  (plus `workspaceQuery`), discarding the body, and MUST resolve with no value.
- **endpoint-kind-validation**: NEEDS REVIEW: Not implemented in source. `ENDPOINT_KINDS` declares the three valid endpoint kinds (`http`, `tcp`, `icmp`), but `CreateEndpointBody.kind`/`UpdateEndpointBody.kind` are typed as an unconstrained `string`, and neither `createEndpoint` nor `updateEndpoint` narrows the caller's value against `ENDPOINT_KINDS` (the `narrow` helper exported by `client-helpers.ts` exists for exactly this and is never called from this file) before sending it to the backend; a caller can create an endpoint with `kind: "ssh"` with no client-side signal that it will never be checked. Evidence that would settle it: whether `POST /api/monitoring/endpoints`/`PUT /api/monitoring/endpoints/:id` validates `kind` server-side, which is not present in this checkout.

**Cross-cutting**

- **every-write-url-encodes-identifiers**: every group, site, and endpoint `id` interpolated into a URL
  path segment MUST be percent-encoded via `enc` (`encodeURIComponent`, aliased in `client-helpers.ts`);
  every `workspace` value MUST likewise be percent-encoded, by `workspaceQuery` in every function except
  `listEndpoints`, which percent-encodes it via `URLSearchParams`/`qs.set` instead.
- **optional-fields-omitted-not-nulled**: `compact()` MUST drop only `undefined`-valued keys from a
  write body before it is serialized, preserving any explicit `null` a caller supplies — per `compact()`'s
  own doc comment, "`null` is preserved — it is an explicit 'clear this column'" — though no
  `CreateXBody`/`UpdateXBody` field in this module is typed to accept `null` itself, so this only matters
  if a caller bypasses the TypeScript types.
- **no-client-side-cache**: none of the twelve exported functions in `monitored-sites.ts` MUST cache or
  memoize a response; every call issues exactly one HTTP request (aside from the inherited `401`
  refresh-and-retry described below).
- **module-holds-no-mutable-state**: the only module-level values are the `GROUPS`/`SITES`/`ENDPOINTS`
  path-string constants and the `ENDPOINT_KINDS` tuple, all read-only; no shared mutable state exists for
  concurrent calls in this module to race on.

### Security

Monitored-sites configuration is not credential data, but every operation is owner/workspace-scoped, so
this recipe carries a dedicated security subsection per the cookbook's cross-cutting authorization
guidance.

- **owner-scoping-server-side**: per the module's own top-of-file comment, every operation MUST be
  owner-scoped server-side: `site_groups` by the caller's `user_id`; `sites` and `endpoints` inherit
  `user_id` and owner from their parent at create/reparent time.
- **workspace-param-repins-owner**: the optional `workspace` parameter, when supplied, MUST be sent as
  `?workspace=<slug>` on every operation (via `workspaceQuery`, or `listEndpoints`' equivalent
  `qs.set`), which per the comment pins the operation to the workspace's owning principal instead of the
  caller's own scope; list operations under a workspace MUST return only that principal's rows, and
  item update/delete under a workspace MUST resolve an org-owned row another member created.
- **auth-delegated-to-shared-client**: every network call in this module MUST go through `authedJson` or
  `authedRequest` (imported from `./http`, itself re-exporting `@agentic-toolkit/auth/client`); this
  module MUST NOT read, store, or attach a bearer token itself.
- **session-refresh-waterfall**: a `401` response to any call in this module MUST trigger exactly one
  token refresh and one retried request, inherited unconditionally from `authedFetch`; a second `401` on
  the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. This module defines
  no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`.
- **no-conflict-friendly-mapping**: no function in this module calls `rethrowConflict` (exported by
  `./http` for exactly this purpose elsewhere in the codebase) to translate a `409` "already exists"
  backend error into an entity-named friendly message; a duplicate group/site/endpoint slug MUST
  propagate as the raw `AuthHttpError` message the backend supplied.

## Appearance

Not applicable — this is a data-access client for the Status Sites monitoring domain, not a visual
component.

## States

Not applicable — this is a data-access client for the Status Sites monitoring domain, not a visual
component; any loading/error/empty visual state is owned by the presentation layer that consumes it.

## Accessibility

Not applicable — this is a data-access client for the Status Sites monitoring domain, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-monitored-sites-001 | site-view-renames-group-id | `toSite({ id:"s1", slug:"site", name:"Site", siteGroupId:"g1", createdAt:"c", updatedAt:"u" })` | Resolves to a `SiteView` with `groupId: "g1"` — `monitored-sites.test.ts` › "toSite renames siteGroupId→groupId" |
| hub-domain-monitored-sites-002 | site-group-view-shape | `toGroup({ id:"g1", slug:"grp", name:"Grp", retentionDays:30, createdAt:"c", updatedAt:"u" })` | Resolves to a `SiteGroupView` with `retentionDays: 30` — `monitored-sites.test.ts` › "toGroup carries the retention window through" |
| hub-domain-monitored-sites-003 | endpoint-view-shape | `toEndpoint({ id:"e1", siteId:"s1", url:"https://x", kind:"http", expectedStatus:200, checkIntervalSeconds:60, isActive:true, createdAt:"c", updatedAt:"u" })` | Resolves to an `EndpointView` with `expectedStatus: 200` and `isActive: true` — `monitored-sites.test.ts` › "toEndpoint preserves the check fields" |
| hub-domain-monitored-sites-004 | site-group-view-shape | Same input as 002 | `id`, `slug`, `name`, `createdAt`, `updatedAt` are all copied unchanged — derived directly from `toGroup`'s source, no dedicated assertion beyond `retentionDays` |
| hub-domain-monitored-sites-005 | group-list-request | `listGroups({ workspace: "acme" })` against a stub GET | Request URL is `/api/monitoring/site-groups?workspace=acme` — derived directly from `workspaceQuery`'s source, no dedicated test |
| hub-domain-monitored-sites-006 | group-list-sorted-by-name | Stub returns rows named `"Zebra"`, `"Apple"` | `listGroups` resolves in the order `["Apple", "Zebra"]` — derived directly from `sortByText`'s `localeCompare` sort, no dedicated test |
| hub-domain-monitored-sites-007 | group-create-request | `createGroup({ name: "Grp", slug: "grp" })` (no `retentionDays`) | `POST /api/monitoring/site-groups` body is `{"name":"Grp","slug":"grp"}` with no `retentionDays` key — derived directly from `compact()`'s `undefined`-key drop, no dedicated test |
| hub-domain-monitored-sites-008 | group-update-request | `updateGroup("g1", { retentionDays: 14 })` | `PUT /api/monitoring/site-groups/g1` body is `{"retentionDays":14}` only — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-009 | group-delete-request | `deleteGroup("g1")` | `DELETE /api/monitoring/site-groups/g1`; resolves to `undefined` — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-010 | site-list-single-request-only | `listSites({ workspace: "acme" })` | Exactly one HTTP request is issued, to `GET /api/monitoring/sites?workspace=acme`; no request to `/api/monitoring/site-groups` occurs — derived directly from the function's own comment and body, no dedicated test |
| hub-domain-monitored-sites-011 | site-create-request | `createSite({ name: "Site", slug: "site", groupId: "g1" })` | `POST /api/monitoring/sites` body is `{"name":"Site","slug":"site","siteGroupId":"g1"}` — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-012 | site-update-request | `updateSite("s1", { groupId: "g2" })` | `PUT /api/monitoring/sites/s1` body is `{"siteGroupId":"g2"}` only — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-013 | site-delete-request | `deleteSite("s1")` | `DELETE /api/monitoring/sites/s1`; resolves to `undefined` — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-014 | site-belongs-to-exactly-one-group | Compile-time: constructing `CreateSiteBody` without `groupId` | Fails to typecheck — `groupId` is a required, non-optional field — confirmed by the type declaration, no runtime test needed |
| hub-domain-monitored-sites-015 | endpoint-list-request | `listEndpoints("s1", { workspace: "acme" })` | Request URL is `/api/monitoring/endpoints?siteId=s1&workspace=acme` — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-016 | endpoint-list-double-filtered | Stub `GET /api/monitoring/endpoints?siteId=s1` returns one row with `siteId: "other"` (a stub bug or stale cache) | `listEndpoints("s1", ...)` resolves to an empty array — the client-side `.filter` drops it even though the server already applied its own `siteId` equality filter — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-017 | endpoint-list-sorted-by-url | Stub returns endpoints with `url` `"https://z"`, `"https://a"` | `listEndpoints` resolves in the order `["https://a", "https://z"]` — derived directly from `sortByText`, no dedicated test |
| hub-domain-monitored-sites-018 | endpoint-create-request | `createEndpoint("s1", { url: "https://x", kind: "http" })` | `POST /api/monitoring/endpoints` body is `{"siteId":"s1","url":"https://x","kind":"http"}` (no `expectedStatus`/`checkIntervalSeconds`/`isActive` keys) — derived directly from `compact()`, no dedicated test |
| hub-domain-monitored-sites-019 | endpoint-update-request | `updateEndpoint("e1", { isActive: false })` | `PUT /api/monitoring/endpoints/e1` body is `{"isActive":false}` only, and never includes a `siteId` key regardless of what the caller passes (the parameter type has none) — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-020 | endpoint-delete-request | `deleteEndpoint("e1")` | `DELETE /api/monitoring/endpoints/e1`; resolves to `undefined` — derived directly from source, no dedicated test |
| hub-domain-monitored-sites-021 | endpoint-kind-validation | `createEndpoint("s1", { url: "https://x", kind: "ssh" })` | The call resolves normally (the request is sent with `kind: "ssh"` verbatim); no client-side error is thrown despite `"ssh"` not being a member of `ENDPOINT_KINDS` — traces the open question on `endpoint-kind-validation`, no dedicated test |
| hub-domain-monitored-sites-022 | session-refresh-waterfall | Any function's first response is `401`; `refreshAccessToken()` resolves a new token | The request is retried once with the new token; a `401` on that retry throws `AuthHttpError` with `status: 401` — traced to `authedFetch` in `auth/src/client.ts`, exercised only indirectly through this module |
| hub-domain-monitored-sites-023 | errors-carry-status-and-code | Backend responds `409` to `createGroup` with body `{ error: { message: "slug already exists", code: "duplicate_slug" } }` | The thrown `AuthHttpError` has `status: 409` and `code: "duplicate_slug"`, with `rethrowConflict` never invoked, so the message is exactly the backend's — traced to `extractErrorCode`/`extractErrorMessage` in `auth/src/client.ts`, no `monitored-sites.ts` test |
| hub-domain-monitored-sites-024 | no-client-side-cache | Two sequential calls to `listGroups({ workspace: "acme" })` | Two separate HTTP requests are issued; the second call does not reuse the first response — derived directly from the absence of any cache/memo in source, no dedicated test |

## Edge Cases

- **Null and empty input — `workspace`**: not checked client-side in any of the twelve functions. `opts.workspace`
  is a typed `string | undefined`; an empty string is sent unchanged as `workspace=` (or, for
  `listEndpoints`, silently omitted, since `qs.set` is only called when `opts?.workspace` is truthy and an
  empty string is falsy). This is a MUST per the observed source; no validation exists.
- **Null and empty input — required create fields**: `createGroup`, `createSite`, and `createEndpoint`
  perform no client-side check that `name`/`slug`/`url` are non-empty; an empty string is sent to the
  backend unchanged, per `compact()`'s own scope (it drops only `undefined`, never filters an empty
  string). MUST behave this way per source.
- **Boundary values — `retentionDays`/`expectedStatus`/`checkIntervalSeconds`**: none of these numeric
  fields has a client-side minimum, maximum, or integer check; whatever number the caller supplies
  (including negative, zero, or non-integer) is sent to the backend unchanged via `compact()`. MUST
  behave this way per source — no declared closed set constrains these fields, unlike `kind`.
- **Boundary values — list size past the generic-CRUD 500-row cap**: per the module's own comment on
  `listSites`, "generic-CRUD lists cap at 500." `listGroups`, `listSites`, and `listEndpoints` accept no
  pagination, cursor, or limit parameter, and none of the three inspects the returned row count or signals
  truncation to the caller; a workspace with more than 500 groups, sites, or endpoints receives a silently
  incomplete list from any of the three. This is a fact traced directly to the source's own comment, not a
  gap invented by this recipe — see the `pagination-support` compliance finding below.
- **Concurrent access — module state**: this module holds no shared mutable state between calls (only the
  read-only `GROUPS`/`SITES`/`ENDPOINTS`/`ENDPOINT_KINDS` constants), so there is nothing for two
  concurrent calls to race on within the module itself.
- **Concurrent access — competing writes**: two concurrent `updateSite`/`updateGroup`/`updateEndpoint`
  calls for the same `id` follow ordinary `PUT` semantics — last response received wins, with no
  client-side sequencing, optimistic-lock check, or `updatedAt`-based conflict detection in this file.
- **Concurrent access — reparent then list**: calling `updateSite` to move a site to a new group and then
  immediately calling `listSites`/`listEndpoints` issues two independent requests with no client-side
  cache to invalidate; the second request's freshness depends entirely on the backend having committed
  the first, which this module does not wait on beyond the first request's own response.
- **Error states — non-2xx response**: every non-`401` failure and every unresolved `401` throws
  `AuthHttpError` carrying the HTTP status and optional code (`errors-carry-status-and-code`); nothing in
  this file catches or swallows that error.
- **Error states — `204` on a declared-void write**: `deleteGroup`, `deleteSite`, and `deleteEndpoint` call
  `authedRequest` (which discards the body and does not special-case `204`), so a `204` response resolves
  normally; this differs from `authedJson`, which throws on `204` — none of `monitored-sites.ts`'s create
  or update functions can receive a bodiless `204`, since `authedJson` treats that as an error regardless
  of caller intent.
- **Offline or disconnected state**: none of the twelve functions catches a network-level `fetch`
  rejection; a connectivity loss mid-call propagates as an unhandled promise rejection out of this module
  to the caller, with no retry, queuing, or offline-specific handling anywhere in this file.
- **No timeout**: no function sets a deadline or `AbortSignal`; a reachable-but-unresponsive backend leaves
  the call pending until the underlying `fetch` implementation's own limit, if any.
- **No cancellation**: no function accepts an `AbortSignal` parameter, so a caller cannot cancel an
  in-flight request through this module.
- **No retry beyond the `401` waterfall**: every call issues exactly one request (plus, on a `401`, the
  single inherited refresh-and-retry); nothing in this file retries a network failure or a non-`401`
  error status.
- **Stale module doc comment**: the module's own top-of-file comment states "the client-side narrowing in
  `listSites()`/`listEndpoints()` stays as defense-in-depth," but `listSites`'s implementation performs no
  such filter — it maps and sorts the response with no owner/workspace narrowing of its own; only
  `listEndpoints` retains a client-side filter (on `siteId`, per `endpoint-list-double-filtered`). This is
  recorded as an observed discrepancy between the source's comment and its code in Design Decisions, not
  smoothed over.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.workspace` (every function) | `string` (caller parameter, optional) | omitted → caller's own owner scope | Percent-encoded and appended as `?workspace=<slug>` (or `&workspace=<slug>` on `listEndpoints`); pins the operation to a workspace's owning principal instead of the caller's own scope. |
| `body` (`createGroup`) | `CreateGroupBody` (`{ name, slug, retentionDays? }`) | none — required except `retentionDays` | Sent through `compact()` as the `POST` body. |
| `body` (`updateGroup`) | `UpdateGroupBody` (all fields optional) | none — required argument, fields individually optional | Sent through `compact()` as the `PUT` body. |
| `body` (`createSite`) | `CreateSiteBody` (`{ name, slug, groupId }`, all required) | none — required | Sent verbatim (renamed to `siteGroupId`) as the `POST` body; not passed through `compact()`. |
| `body` (`updateSite`) | `UpdateSiteBody` (all fields optional) | none — required argument, fields individually optional | Sent through `compact()` (renamed to `siteGroupId`) as the `PUT` body. |
| `siteId` (`listEndpoints`, `createEndpoint`) | `string` (caller parameter, required) | none | Identifies the parent site; sent as a query parameter on `listEndpoints` and as a body field on `createEndpoint`. |
| `body` (`createEndpoint`) | `CreateEndpointBody` (`{ url, kind, expectedStatus?, checkIntervalSeconds?, isActive? }`) | none — `url`/`kind` required, rest optional | Sent through `compact()` as the `POST` body, with `siteId` added from the function's own parameter. |
| `body` (`updateEndpoint`) | `UpdateEndpointBody` (all fields optional) | none — required argument, fields individually optional | Sent through `compact()` as the `PUT` body; carries no `siteId` field. |
| `ENDPOINT_KINDS` | module constant, `readonly ["http","tcp","icmp"]` | fixed | The declared set of valid `kind` values; not consulted by `createEndpoint`/`updateEndpoint` (`endpoint-kind-validation`). |
| `GROUPS`/`SITES`/`ENDPOINTS` | module constants, fixed path strings | fixed | `/api/monitoring/site-groups`, `/api/monitoring/sites`, `/api/monitoring/endpoints`; not injectable or configurable. |

## Deep Linking

Not applicable: `monitored-sites.ts`/`wire.ts` register no URL scheme, route, or navigation target of
their own; they are a data client consumed by a separate presentation layer (the Dashboards feature) that
owns any deep-linking concern.

## Localization

Not applicable: `monitored-sites.ts`/`wire.ts` author no user-facing string of their own — the source
contains no `throw new Error(...)` with an English message anywhere in this file (unlike some sibling
clients' own validation errors). Every error message a caller can observe from this module originates in
the backend's response body and is extracted by `extractErrorMessage` in `auth/src/client.ts`, not
authored here.

## Accessibility Options

Not applicable: `monitored-sites.ts`/`wire.ts` render no UI and respond to none of Reduce Motion, Increase
Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the source contains no feature-flag or gating check of any kind; `ENDPOINT_KINDS` is a
fixed domain vocabulary (checker types), not a flag.

## Analytics

Not applicable: the source contains no analytics or event-emission call.

## Privacy

- **Data collected**: this module originates no data of its own; it reads and writes monitoring
  configuration records — group/site names and slugs, retention windows, and endpoint URLs, kinds, and
  check intervals. These are infrastructure-monitoring configuration records, not end-user PII.
- **Storage**: none. Every function is a stateless per-call request builder (`no-client-side-cache`,
  `module-holds-no-mutable-state`); nothing is held in memory or on disk beyond the lifetime of a single
  call.
- **Transmission**: yes. Every call carries a bearer credential attached by `@agentic-toolkit/auth/client`
  (`auth-delegated-to-shared-client`), not by this module; whatever transport security the deployment
  provides is outside the scope of these two files.
- **Retention**: none. Nothing this module handles is retained after the response it produced is returned
  to the caller.

## Logging

Not applicable: `monitored-sites.ts` and `wire.ts` contain no logging call of any kind.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/monitored-sites/monitored-sites.ts`
  and `wire.ts` hold the client, re-exported by `index.ts` as `@agentic-toolkit/data/monitored-sites`;
  every function is built on `authedJson`/`authedRequest` (from `../http`, re-exporting
  `@agentic-toolkit/auth/client`) and `compact`/`enc`/`sortByText`/`workspaceQuery` (from
  `../client-helpers`). The Dashboards feature (`packages/web/packages/features/dashboards/src/*`) is the
  one current consumer.
- **SwiftUI**: model `SiteGroupView`/`SiteView`/`EndpointView` (and the create/update body shapes) as
  `Codable, Hashable, Sendable` structs, mirroring the sibling Hub domain recipes' models pattern, and the
  twelve functions as `async throws` calls on an `actor` or `@MainActor final class`, with a dedicated
  error type carrying the HTTP status and optional machine code in place of `AuthHttpError`. `ENDPOINT_KINDS`
  becomes a `CaseIterable` `enum` — and, unlike the TypeScript source, a Swift port SHOULD use that enum as
  the `kind` parameter's type rather than a bare `String`, which would close the `endpoint-kind-validation`
  gap at compile time rather than reproducing it.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS Dashboards feature would
  consume the ported client through an injected data-source protocol, the same pattern other Hub domain
  recipes' data sources already use, rather than calling `URLSession` from the view layer.
- **Compose**: model the three wire rows and the six body shapes as Kotlin `data class`es annotated
  `@Serializable`, and the twelve functions as `suspend fun`s on a class built on Ktor or OkHttp, with a
  sealed error type carrying the HTTP status and optional code; model `ENDPOINT_KINDS` as a Kotlin `enum
  class`.
- **WinUI 3**: a .NET port would model `GroupRow`/`SiteRow`/`EndpointRow` and the six body shapes as
  `record`s attributed for `System.Text.Json`, and the twelve functions as `Task<T>`-returning methods on a
  class built on `HttpClient`, attaching `Authorization: Bearer <token>` the way this module's
  `authedFetch` does and refreshing on a `401` the same one-retry way, defining a `MonitoredSitesApiException`
  (status, code) parallel to `AuthHttpError`. Represent `ENDPOINT_KINDS` as a C# `enum EndpointKind { Http,
  Tcp, Icmp }` with a `[JsonConverter]` for the lowercase wire strings, and prefer exposing the endpoint
  list to a bound UI (e.g. a `DataGrid`/`ItemsRepeater`) through an `ObservableCollection<EndpointView>`
  populated after each `Task` completes, rather than a raw array, since WinUI 3's data-binding idiom
  expects change notification a plain `List<T>` does not provide — this is the platform with the least
  existing prior art in this repo for the refresh-and-retry contract, so the WinUI 3 port would need to
  build the equivalent of `authedFetch` itself, not only the twelve request builders.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/monitored-sites/` |

## Design Decisions

**Decision**: `createSite` builds its body as a plain object literal (`{ name, slug, siteGroupId:
body.groupId }`) rather than passing it through `compact()`, even though `createGroup` and
`createEndpoint` both do.
**Rationale**: `CreateSiteBody`'s three fields are all required (unlike `CreateGroupBody.retentionDays`
or `CreateEndpointBody`'s optional fields), so `compact()` would be a no-op here; the source omits the
call rather than applying it unconditionally for consistency.
**Approved**: pending

**Decision**: the module's own top-of-file comment states "the client-side narrowing in
`listSites()`/`listEndpoints()` stays as defense-in-depth," but `listSites`'s current implementation
performs no owner/workspace filter — only a `sortByText` by name.
**Rationale**: `listSites`'s own inline comment explains the server now owner-scopes `sites` identically
to `site_groups`, and the earlier client-side intersection (against the groups list) was removed
specifically because it round-tripped an extra request and hid rows past the 500-row cap; the top-of-file
comment appears to predate that refactor and was not updated to drop the `listSites()` half of its claim.
This recipe records the code as it actually behaves — no client-side owner narrowing in `listSites` — per
the source-fidelity guideline's requirement to describe the code as it is rather than as a stale comment
describes it.
**Approved**: pending

**Decision**: `listEndpoints` builds its query string with `URLSearchParams`/`qs.set` instead of the
shared `workspaceQuery` helper every other function in this file uses.
**Rationale**: `listEndpoints` already needs `URLSearchParams` to carry the required `siteId` parameter,
so appending `workspace` to that same object avoids constructing a second query-string fragment and
concatenating it; the resulting request is equivalent to what `workspaceQuery` would have produced, but
the code path is not shared.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | failed | Reliability |

`separation-of-concerns` passes: `monitored-sites.ts`/`wire.ts` contain zero UI or presentation code —
both files are the public data-domain surface consumed by the separate Dashboards presentation layer.
`unit-test-coverage` is `partial`: of the twelve exported functions plus three mappers,
`monitored-sites.test.ts` covers only the three mappers (`toGroup`, `toSite`, `toEndpoint`); none of
`listGroups`/`createGroup`/`updateGroup`/`deleteGroup`/`listSites`/`createSite`/`updateSite`/`deleteSite`/`listEndpoints`/`createEndpoint`/`updateEndpoint`/`deleteEndpoint`
has a dedicated test in this checkout. `explicit-error-handling` passes: nothing in this file swallows an
error — every failure either throws `AuthHttpError` (via the shared `authedFetch`) or propagates
unmodified. `server-side-authorization` passes: the module contains no client-side permission check of any
kind, per `owner-scoping-server-side`, deferring owner/workspace scoping entirely to the backend.
`error-response-handling` is `partial`: every call exposes a status and optional code for the caller to
branch on, but no function in this file offers per-code handling of its own (no `rethrowConflict`, no
`isNotFound`/`isConflict` branch) — every failure surfaces as the generic `AuthHttpError` propagation.
`pagination-support` fails: `listGroups`, `listSites`, and `listEndpoints` all return unpaginated
collections with no limit/cursor parameter, against a backend the source's own comment documents as
capping generic-CRUD lists at 500 rows, with no truncation signal to the caller. `graceful-degradation`
fails: unlike a sibling client's documented fallback constant, this module offers no fallback of any kind
when a call fails — every failure is an unhandled rejection with no degraded-but-functional path.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
