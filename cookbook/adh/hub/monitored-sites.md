---
id: a3e87176-5845-43ff-9041-af53437d605d
title: Monitored Sites
domain: agentictoolkit://cookbook/adh/hub/monitored-sites
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A data client for the Status Sites monitoring domain: generic-CRUD groups,
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

# Monitored Sites

## Overview

This is the client for the Status Sites monitoring domain: groups, sites, and endpoints, backed by
generic CRUD over `/api/monitoring/site-groups`, `/api/monitoring/sites`, and
`/api/monitoring/endpoints`. The model matches the database, not an earlier prototype: a site
belongs to exactly one group (`sites.site_group_id`, `NOT NULL`, FK `ON DELETE CASCADE`) and an
endpoint belongs to exactly one site (same cascade) — a strict 1:M chain, not the prototype's
many-to-many `groupIds[]`. The whole chain is owner-scoped server-side, with an optional
`workspace` parameter on every operation that re-pins it to a workspace's owning principal. This
logic holds the backend row and request-body shapes (a group row, a site row, an endpoint row, and
their create/put bodies), three mappers from row to caller-facing view, the caller-facing create
and update body shapes for each entity, the fixed set of valid endpoint kinds, and twelve
operations — list/create/update/delete for each of the three entities — each a thin request
builder over a shared authenticated request client. It is a headless **logic** module — no visual
surface — consumed today by the Dashboards (Site Monitoring) feature, so this recipe marks
Appearance, States, and Accessibility not applicable and carries the runtime contract entirely in
Behavioral Requirements, per the non-UI component guidance this recipe was authored under.

## Behavioral Requirements

**Mappers**

- **site-group-view-shape**: the group mapper MUST map a group row verbatim to a group view carrying
  `id`, `slug`, `name`, `retentionDays`, `createdAt`, and `updatedAt`, with no field renamed.
- **site-view-renames-group-id**: the site mapper MUST copy a site row's `siteGroupId` field into the
  site view's `groupId`; every other field (`id`, `slug`, `name`, `createdAt`, `updatedAt`) MUST be
  copied unchanged.
- **endpoint-view-shape**: the endpoint mapper MUST map an endpoint row verbatim to an endpoint view
  carrying `id`, `siteId`, `url`, `kind`, `expectedStatus`, `checkIntervalSeconds`, `isActive`,
  `createdAt`, and `updatedAt`, with no field renamed.

**Groups**

- **group-list-request**: the list-groups operation MUST send `GET /api/monitoring/site-groups` with
  the query string the shared workspace-query builder appends (empty when the `workspace` option is
  absent).
- **group-list-sorted-by-name**: the list-groups operation MUST return the mapped group views sorted by
  `name` via a locale-aware comparison, without mutating the array the request returned.
- **group-create-request**: the create-group operation MUST send `POST /api/monitoring/site-groups`
  (plus the workspace query) with a body built by the body-compaction helper from `{ name, slug,
  retentionDays }`, dropping `retentionDays` from the JSON payload when the caller omits it, and MUST
  return the mapped group view.
- **group-update-request**: the update-group operation MUST send `PUT
  /api/monitoring/site-groups/<encoded id>` (plus the workspace query) with a compacted patch of `{
  name, slug, retentionDays }`, and MUST return the mapped group view.
- **group-delete-request**: the delete-group operation MUST send `DELETE
  /api/monitoring/site-groups/<encoded id>` (plus the workspace query), discarding any response body,
  and MUST resolve with no value.
- **group-delete-cascades**: deleting a group MUST cascade at the database level (`FK ON DELETE
  CASCADE`) to remove every site in that group and every endpoint of those sites; this client issues
  one `DELETE` request and performs no separate cleanup call of its own.

**Sites**

- **site-belongs-to-exactly-one-group**: a site view MUST carry exactly one `groupId` as a required
  field — the single group this site belongs to (1:M; required) — and this client models no
  many-to-many group membership.
- **site-list-request**: the list-sites operation MUST send `GET /api/monitoring/sites` (plus the
  workspace query).
- **site-list-sorted-by-name**: the list-sites operation MUST return the mapped site views sorted by
  `name`.
- **site-list-single-request-only**: the list-sites operation MUST NOT issue a second request to the
  site-groups endpoint or perform any client-side intersection against group membership. An earlier
  implementation did both — a second round-trip, plus a silent-hiding bug, since generic-CRUD lists cap
  at 500 rows and a workspace with more than 500 groups could drop sites whose group fell past that cap
  even though the server still monitors them; the current single-request form replaced it.
- **site-create-request**: the create-site operation MUST send `POST /api/monitoring/sites` (plus the
  workspace query) with a body of exactly `{ name, slug, siteGroupId: <the given groupId> }`, renaming
  `groupId` to `siteGroupId`, sent without passing through the body-compaction helper — all three
  fields are required, so none can be absent.
- **site-update-request**: the update-site operation MUST send `PUT /api/monitoring/sites/<encoded
  id>` (plus the workspace query) with a compacted patch of `{ name, slug, siteGroupId: <the given
  groupId> }` built from the optional update fields.
- **site-delete-request**: the delete-site operation MUST send `DELETE /api/monitoring/sites/<encoded
  id>` (plus the workspace query), discarding the body, and MUST resolve with no value.
- **site-delete-cascades**: deleting a site MUST cascade at the database level to remove every endpoint
  that belongs to it.

**Endpoints**

- **endpoint-list-request**: the list-endpoints operation MUST send `GET /api/monitoring/endpoints`
  with a query string built from a `siteId` parameter, appending `workspace=<value>` only when the
  `workspace` option is given — this is the one operation that builds its query string separately from
  the shared workspace-query builder every other operation here uses.
- **endpoint-list-double-filtered**: the list-endpoints operation MUST re-filter the mapped rows
  client-side to `e.siteId === siteId`, in addition to the server-side `siteId` equality filter the
  query string already applies. This client filter is retained as defense-in-depth and is redundant
  once the server has already scoped the response.
- **endpoint-list-sorted-by-url**: the list-endpoints operation MUST return the filtered rows sorted by
  `url`.
- **endpoint-create-request**: the create-endpoint operation MUST send `POST
  /api/monitoring/endpoints` (plus the workspace query) with a compacted body of `{ siteId, url, kind,
  expectedStatus, checkIntervalSeconds, isActive }`, where `siteId` comes from the operation's own
  `siteId` parameter, not from the caller-supplied body.
- **endpoint-update-request**: the update-endpoint operation MUST send `PUT
  /api/monitoring/endpoints/<encoded id>` (plus the workspace query) with a compacted patch of `{ url,
  kind, expectedStatus, checkIntervalSeconds, isActive }`; `siteId` MUST NOT appear in this patch, so
  this operation cannot reparent an endpoint to a different site.
- **endpoint-delete-request**: the delete-endpoint operation MUST send `DELETE
  /api/monitoring/endpoints/<encoded id>` (plus the workspace query), discarding the body, and MUST
  resolve with no value.
- **endpoint-kind-validation**: NEEDS REVIEW: Not implemented in source. The fixed set of valid
  endpoint kinds declares the three valid endpoint kinds (`http`, `tcp`, `icmp`), but the create- and
  update-endpoint bodies' `kind` field is typed as an unconstrained string, and neither the
  create-endpoint nor the update-endpoint operation narrows the caller's value against that fixed set
  (a shared value-narrowing helper exists for exactly this and is never called here) before sending it
  to the backend; a caller can create an endpoint with `kind: "ssh"` with no client-side signal that it
  will never be checked. Evidence that would settle it: whether `POST
  /api/monitoring/endpoints`/`PUT /api/monitoring/endpoints/:id` validates `kind` server-side, which is
  not present in this checkout.

**Cross-cutting**

- **every-write-url-encodes-identifiers**: every group, site, and endpoint `id` interpolated into a URL
  path segment MUST be percent-encoded; every `workspace` value MUST likewise be percent-encoded, by
  the shared workspace-query builder in every operation except the list-endpoints operation, which
  percent-encodes it through its own query-string construction instead.
- **optional-fields-omitted-not-nulled**: the body-compaction helper MUST drop only absent-valued keys
  from a write body before it is serialized, preserving any explicit `null` a caller supplies — `null`
  is preserved, as an explicit "clear this column" — though no create/update body field in this module
  accepts `null` itself, so this only matters if a caller bypasses the declared shapes.
- **no-client-side-cache**: none of the twelve operations MUST cache or memoize a response; every call
  issues exactly one HTTP request (aside from the inherited `401` refresh-and-retry described below).
- **module-holds-no-mutable-state**: the only persistent values this logic holds are the three
  fixed path-string constants and the fixed set of valid endpoint kinds, all read-only; no shared
  mutable state exists for concurrent calls to race on.

### Security

Monitored-sites configuration is not credential data, but every operation is owner/workspace-scoped, so
this recipe carries a dedicated security subsection per the cookbook's cross-cutting authorization
guidance.

- **owner-scoping-server-side**: every operation MUST be owner-scoped server-side: groups by the
  caller's user id; sites and endpoints inherit the user id and owner from their parent at
  create/reparent time.
- **workspace-param-repins-owner**: the optional `workspace` parameter, when supplied, MUST be sent as
  `?workspace=<slug>` on every operation, which pins the operation to the workspace's owning principal
  instead of the caller's own scope; list operations under a workspace MUST return only that
  principal's rows, and item update/delete under a workspace MUST resolve an org-owned row another
  member created.
- **auth-delegated-to-shared-client**: every network call in this module MUST go through the shared
  authenticated request client; this module MUST NOT read, store, or attach a bearer token itself.
- **session-refresh-waterfall**: a `401` response to any call in this module MUST trigger exactly one
  token refresh and one retried request, inherited unconditionally from that shared client; a second
  `401` on the retried request MUST propagate as a thrown typed HTTP error with `status: 401`. This
  module defines no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw a typed HTTP error, carrying the response's HTTP status and, when the body supplies
  one, a machine-readable `code`.
- **no-conflict-friendly-mapping**: no operation in this module calls the shared conflict-friendly-error
  helper to translate a `409` "already exists" backend error into an entity-named friendly message; a
  duplicate group/site/endpoint slug MUST propagate as the raw error message the backend supplied.

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
| hub-domain-monitored-sites-001 | site-view-renames-group-id | The site mapper applied to a site row `{ id:"s1", slug:"site", name:"Site", siteGroupId:"g1", createdAt:"c", updatedAt:"u" }` | Resolves to a site view with `groupId: "g1"` |
| hub-domain-monitored-sites-002 | site-group-view-shape | The group mapper applied to a group row `{ id:"g1", slug:"grp", name:"Grp", retentionDays:30, createdAt:"c", updatedAt:"u" }` | Resolves to a group view with `retentionDays: 30` |
| hub-domain-monitored-sites-003 | endpoint-view-shape | The endpoint mapper applied to an endpoint row `{ id:"e1", siteId:"s1", url:"https://x", kind:"http", expectedStatus:200, checkIntervalSeconds:60, isActive:true, createdAt:"c", updatedAt:"u" }` | Resolves to an endpoint view with `expectedStatus: 200` and `isActive: true` |
| hub-domain-monitored-sites-004 | site-group-view-shape | Same input as 002 | `id`, `slug`, `name`, `createdAt`, `updatedAt` are all copied unchanged |
| hub-domain-monitored-sites-005 | group-list-request | The list-groups operation called with `{ workspace: "acme" }` against a stub GET | Request URL is `/api/monitoring/site-groups?workspace=acme` |
| hub-domain-monitored-sites-006 | group-list-sorted-by-name | Stub returns rows named `"Zebra"`, `"Apple"` | The list-groups operation resolves in the order `["Apple", "Zebra"]` |
| hub-domain-monitored-sites-007 | group-create-request | The create-group operation called with `{ name: "Grp", slug: "grp" }` (no `retentionDays`) | `POST /api/monitoring/site-groups` body is `{"name":"Grp","slug":"grp"}` with no `retentionDays` key |
| hub-domain-monitored-sites-008 | group-update-request | The update-group operation called with id `"g1"` and `{ retentionDays: 14 }` | `PUT /api/monitoring/site-groups/g1` body is `{"retentionDays":14}` only |
| hub-domain-monitored-sites-009 | group-delete-request | The delete-group operation called with id `"g1"` | `DELETE /api/monitoring/site-groups/g1`; resolves to no value |
| hub-domain-monitored-sites-010 | site-list-single-request-only | The list-sites operation called with `{ workspace: "acme" }` | Exactly one HTTP request is issued, to `GET /api/monitoring/sites?workspace=acme`; no request to `/api/monitoring/site-groups` occurs |
| hub-domain-monitored-sites-011 | site-create-request | The create-site operation called with `{ name: "Site", slug: "site", groupId: "g1" }` | `POST /api/monitoring/sites` body is `{"name":"Site","slug":"site","siteGroupId":"g1"}` |
| hub-domain-monitored-sites-012 | site-update-request | The update-site operation called with id `"s1"` and `{ groupId: "g2" }` | `PUT /api/monitoring/sites/s1` body is `{"siteGroupId":"g2"}` only |
| hub-domain-monitored-sites-013 | site-delete-request | The delete-site operation called with id `"s1"` | `DELETE /api/monitoring/sites/s1`; resolves to no value |
| hub-domain-monitored-sites-014 | site-belongs-to-exactly-one-group | Attempting to build a create-site request without `groupId` | MUST be rejected before any request is sent — `groupId` is a required field |
| hub-domain-monitored-sites-015 | endpoint-list-request | The list-endpoints operation called with site id `"s1"` and `{ workspace: "acme" }` | Request URL is `/api/monitoring/endpoints?siteId=s1&workspace=acme` |
| hub-domain-monitored-sites-016 | endpoint-list-double-filtered | Stub `GET /api/monitoring/endpoints?siteId=s1` returns one row with `siteId: "other"` (a stub bug or stale cache) | The list-endpoints operation resolves to an empty array — the client-side filter drops it even though the server already applied its own `siteId` equality filter |
| hub-domain-monitored-sites-017 | endpoint-list-sorted-by-url | Stub returns endpoints with `url` `"https://z"`, `"https://a"` | The list-endpoints operation resolves in the order `["https://a", "https://z"]` |
| hub-domain-monitored-sites-018 | endpoint-create-request | The create-endpoint operation called with site id `"s1"` and `{ url: "https://x", kind: "http" }` | `POST /api/monitoring/endpoints` body is `{"siteId":"s1","url":"https://x","kind":"http"}` (no `expectedStatus`/`checkIntervalSeconds`/`isActive` keys) |
| hub-domain-monitored-sites-019 | endpoint-update-request | The update-endpoint operation called with id `"e1"` and `{ isActive: false }` | `PUT /api/monitoring/endpoints/e1` body is `{"isActive":false}` only, and never includes a `siteId` key regardless of what the caller passes |
| hub-domain-monitored-sites-020 | endpoint-delete-request | The delete-endpoint operation called with id `"e1"` | `DELETE /api/monitoring/endpoints/e1`; resolves to no value |
| hub-domain-monitored-sites-021 | endpoint-kind-validation | The create-endpoint operation called with site id `"s1"` and `{ url: "https://x", kind: "ssh" }` | The call resolves normally (the request is sent with `kind: "ssh"` verbatim); no client-side error is thrown despite `"ssh"` not being one of the valid kinds |
| hub-domain-monitored-sites-022 | session-refresh-waterfall | Any operation's first response is `401`; the token-refresh step resolves a new token | The request is retried once with the new token; a `401` on that retry throws a typed HTTP error with `status: 401` |
| hub-domain-monitored-sites-023 | errors-carry-status-and-code | Backend responds `409` to the create-group operation with body `{ error: { message: "slug already exists", code: "duplicate_slug" } }` | The thrown error has `status: 409` and `code: "duplicate_slug"`, with the conflict-friendly-error helper never invoked, so the message is exactly the backend's |
| hub-domain-monitored-sites-024 | no-client-side-cache | Two sequential calls to the list-groups operation with `{ workspace: "acme" }` | Two separate HTTP requests are issued; the second call does not reuse the first response |

## Edge Cases

- **Null and empty input — `workspace`**: not checked client-side in any of the twelve operations. The
  `workspace` option is optional and may be absent; an empty string is sent unchanged as `workspace=`
  (or, for the list-endpoints operation, silently omitted, since it is only appended when the option is
  truthy and an empty string is falsy). This is a MUST per the observed source; no validation exists.
- **Null and empty input — required create fields**: the create-group, create-site, and create-endpoint
  operations perform no client-side check that `name`/`slug`/`url` are non-empty; an empty string is
  sent to the backend unchanged, since the body-compaction helper only drops absent values, never an
  empty string. MUST behave this way per source.
- **Boundary values — `retentionDays`/`expectedStatus`/`checkIntervalSeconds`**: none of these numeric
  fields has a client-side minimum, maximum, or integer check; whatever number the caller supplies
  (including negative, zero, or non-integer) is sent to the backend unchanged. MUST behave this way per
  source — no declared closed set constrains these fields, unlike `kind`.
- **Boundary values — list size past the generic-CRUD 500-row cap**: generic-CRUD lists cap at 500 rows.
  The list-groups, list-sites, and list-endpoints operations accept no pagination, cursor, or limit
  parameter, and none of the three inspects the returned row count or signals truncation to the caller;
  a workspace with more than 500 groups, sites, or endpoints receives a silently incomplete list from
  any of the three. This is a fact traced directly to the source, not a gap invented by this recipe —
  see the `pagination-support` compliance finding below.
- **Concurrent access — module state**: this module holds no shared mutable state between calls (only
  the three read-only path constants and the fixed set of valid endpoint kinds), so there is nothing for
  two concurrent calls to race on within the module itself.
- **Concurrent access — competing writes**: two concurrent update-site/update-group/update-endpoint calls
  for the same `id` follow ordinary `PUT` semantics — last response received wins, with no client-side
  sequencing, optimistic-lock check, or `updatedAt`-based conflict detection in this recipe.
- **Concurrent access — reparent then list**: calling the update-site operation to move a site to a new
  group and then immediately calling the list-sites/list-endpoints operations issues two independent
  requests with no client-side cache to invalidate; the second request's freshness depends entirely on
  the backend having committed the first, which this module does not wait on beyond the first request's
  own response.
- **Error states — non-2xx response**: every non-`401` failure and every unresolved `401` throws a
  typed HTTP error carrying the HTTP status and optional code (`errors-carry-status-and-code`); nothing
  in this recipe catches or swallows that error.
- **Error states — `204` on a declared-void write**: the delete-group, delete-site, and delete-endpoint
  operations discard the response body and do not special-case `204`, so a `204` response resolves
  normally; this differs from operations that decode a JSON body, which treat `204` as an error — none
  of the create or update operations can receive a bodiless `204`, since decoding a response treats that
  as an error regardless of caller intent.
- **Offline or disconnected state**: none of the twelve operations catches a network-level connection
  failure; a connectivity loss mid-call propagates as an unhandled asynchronous rejection out of this
  module to the caller, with no retry, queuing, or offline-specific handling anywhere in this recipe.
- **No timeout**: no operation sets a deadline or cancellation signal; a reachable-but-unresponsive
  backend leaves the call pending until the underlying transport's own limit, if any.
- **No cancellation**: no operation accepts a cancellation-signal parameter, so a caller cannot cancel
  an in-flight request through this module.
- **No retry beyond the `401` waterfall**: every call issues exactly one request (plus, on a `401`, the
  single inherited refresh-and-retry); nothing in this recipe retries a network failure or a non-`401`
  error status.
- **Stale module doc comment**: this module's own top-of-file comment states "the client-side narrowing
  in the list-sites/list-endpoints operations stays as defense-in-depth," but the list-sites operation's
  implementation performs no such filter — it maps and sorts the response with no owner/workspace
  narrowing of its own; only the list-endpoints operation retains a client-side filter (on `siteId`, per
  `endpoint-list-double-filtered`). This is recorded as an observed discrepancy between the source's
  comment and its code in Design Decisions, not smoothed over.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` (every operation) | string (caller parameter, optional) | omitted → caller's own owner scope | Percent-encoded and appended as `?workspace=<slug>` (or `&workspace=<slug>` on the list-endpoints operation); pins the operation to a workspace's owning principal instead of the caller's own scope. |
| body (create-group) | `{ name, slug, retentionDays? }` | none — required except `retentionDays` | Sent through the body-compaction helper as the `POST` body. |
| body (update-group) | all fields optional | none — required argument, fields individually optional | Sent through the body-compaction helper as the `PUT` body. |
| body (create-site) | `{ name, slug, groupId }`, all required | none — required | Sent verbatim (renamed to `siteGroupId`) as the `POST` body; not passed through the body-compaction helper. |
| body (update-site) | all fields optional | none — required argument, fields individually optional | Sent through the body-compaction helper (renamed to `siteGroupId`) as the `PUT` body. |
| `siteId` (list-endpoints, create-endpoint) | string (caller parameter, required) | none | Identifies the parent site; sent as a query parameter on the list-endpoints operation and as a body field on the create-endpoint operation. |
| body (create-endpoint) | `{ url, kind, expectedStatus?, checkIntervalSeconds?, isActive? }` | none — `url`/`kind` required, rest optional | Sent through the body-compaction helper as the `POST` body, with `siteId` added from the operation's own parameter. |
| body (update-endpoint) | all fields optional | none — required argument, fields individually optional | Sent through the body-compaction helper as the `PUT` body; carries no `siteId` field. |
| valid endpoint kinds | fixed set (`"http"`, `"tcp"`, `"icmp"`) | fixed | The declared set of valid `kind` values; not consulted by the create-endpoint/update-endpoint operations (`endpoint-kind-validation`). |
| the three route paths | fixed path strings | fixed | `/api/monitoring/site-groups`, `/api/monitoring/sites`, `/api/monitoring/endpoints`; not injectable or configurable. |

## Deep Linking

Not applicable: this logic registers no URL scheme, route, or navigation target of its own; it is a
data client consumed by a separate presentation layer (the Dashboards feature) that owns any
deep-linking concern.

## Localization

Not applicable: this logic authors no user-facing string of its own — the source contains no thrown
error with an English message anywhere in this recipe (unlike some sibling clients' own validation
errors). Every error message a caller can observe from this module originates in the backend's response
body and is extracted by the shared authenticated request client, not authored here.

## Accessibility Options

Not applicable: this logic renders no UI and responds to none of Reduce Motion, Increase Contrast, or
Differentiate Without Color.

## Feature Flags

Not applicable: the source contains no feature-flag or gating check of any kind; the fixed set of valid
endpoint kinds is a fixed domain vocabulary, not a flag.

## Analytics

Not applicable: the source contains no analytics or event-emission call.

## Privacy

- **Data collected**: this module originates no data of its own; it reads and writes monitoring
  configuration records — group/site names and slugs, retention windows, and endpoint URLs, kinds, and
  check intervals. These are infrastructure-monitoring configuration records, not end-user PII.
- **Storage**: none. Every operation is a stateless per-call request builder (`no-client-side-cache`,
  `module-holds-no-mutable-state`); nothing is held in memory or on disk beyond the lifetime of a single
  call.
- **Transmission**: yes. Every call carries a bearer credential attached by the shared authenticated
  request client, not by this module; whatever transport security the deployment provides is outside
  the scope of this recipe.
- **Retention**: none. Nothing this module handles is retained after the response it produced is
  returned to the caller.

## Logging

Not applicable: this logic contains no logging call of any kind.

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
**Applies to**: Web — this is a detail of this platform's own implementation of the body-compaction
helper, not a behavior a port needs to reproduce beyond the observable request body.
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
**Applies to**: Web — `URLSearchParams` and the shared `workspaceQuery` helper are both artifacts of
this platform's implementation; a port only needs to reproduce the resulting query string.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
