---
id: 39a7192e-7e1e-4e93-b615-312a5ddf69b0
title: Hub Domain Access Client
domain: agentictoolkit://cookbook/adh/hub/access
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Client for the workspace roles & permissions access API: feature areas,
  role CRUD, subject assignments, item restriction, and the effective-access
  explainer.'
platforms:
- typescript
- web
tags:
- access-control
- permissions
- roles
- workspace
- api
depends-on: []
related: []
references:
- packages/web/packages/data/src/access/access.ts (agentictoolkit)
- packages/web/packages/data/src/access/wire.ts (agentictoolkit)
- packages/web/packages/data/src/access/index.ts (agentictoolkit)
- packages/web/packages/data/src/access/__tests__/access.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Access Client

## Overview

This is the client for the gated workspace roles & permissions access surface: feature
areas, role CRUD, subject assignments, item restriction, and an effective-access explainer.
Every operation names the workspace by slug (a personal workspace's customer slug or an org
slug); reads answer with a not-found response to non-members, role definition is admin-only,
and assignment/restriction writes need the manage-access verb at the target scope, all
enforced by the backend. The client exposes a set of wire row shapes (for feature areas,
grants, roles, assignments, and effective-access results), a fallback feature-areas list,
write input shapes for role and assignment writes, and ten operations, each a thin request
builder over a shared authenticated-request helper. It is a headless **logic** module — no
visual surface — so this recipe marks Appearance, States, and Accessibility not applicable
and carries the runtime contract entirely in Behavioral Requirements, per the non-UI
component guidance this recipe was authored under.

## Behavioral Requirements

**Feature areas**

- **feature-list-scoped-by-workspace**: the list-features operation MUST send a request to
  the features route with a `workspace` query parameter carrying the percent-encoded
  workspace slug.
- **feature-list-unwraps-envelope**: the list-features operation MUST return the bare list of
  feature-area rows unwrapped from the `{ features }` response envelope, not the envelope
  itself.
- **feature-row-shape-validated**: the list-features operation MUST throw a plain error with
  the message `GET /access/features returned a malformed feature list` when the response's
  `features` value is not an array, or when any element is not an object whose `key` and
  `label` are both non-empty strings.
- **feature-order-preserved**: the list-features operation MUST return rows in the order the
  backend sent them; it performs no client-side sort or reorder.
- **fallback-features-not-invoked-automatically**: the fallback feature list MUST NOT be
  substituted automatically by the list-features operation on any failure — it is exported
  for a caller's own catch block, and no path inside the list-features operation reads or
  returns it.
- **fallback-features-fixed-set**: the fallback feature list MUST be exactly the two-entry,
  order-preserving list `[{key:"projects",label:"Projects"},{key:"personas",label:"Personas"}]`.

**Roles**

- **role-list-scoped-by-workspace**: the list-roles operation MUST send a request to the
  roles route scoped by workspace and return the role list unwrapped and unvalidated —
  unlike the list-features operation, no runtime shape check is applied to this response.
- **role-create-request-shape**: the create-role operation MUST send a create request to the
  roles route scoped by workspace, with the role write input (`slug`, `name`, `description?`,
  `defaultFor?`, `grants`) serialized verbatim as the body, and MUST return the created role.
- **role-update-excludes-slug**: the update-role operation's patch input excludes `slug`; a
  role's `slug` MUST NOT be changeable through this operation.
- **role-update-request-shape**: the update-role operation MUST send an update request to a
  specific role's route scoped by workspace, with the patch object serialized verbatim as the
  body, and MUST return the updated role.
- **role-delete-request-shape**: the delete-role operation MUST send a delete request to a
  specific role's route scoped by workspace, and MUST resolve with no value, discarding
  whatever body the response carries.

**Assignments**

- **assignment-list-workspace-wide**: the list-assignments operation called with no scope
  argument MUST send a request to the assignments route scoped only by workspace, with no
  feature/item query parameters, and MUST return the `{ assignments, restricted? }` body
  verbatim.
- **assignment-list-item-scoped**: the list-assignments operation called with a scope
  argument MUST add feature and item identifiers to that same request; unlike the assignment
  write input, the list-assignments operation's scope argument requires feature and item
  together — there is no way to supply only one.
- **assignment-put-upserts-one-per-scope**: the assignment-upsert operation MUST send an
  upsert request to the assignments route scoped by workspace, with the assignment write
  input serialized verbatim as the body, and MUST return the resulting assignment; per the
  source's own comment, this grants or replaces the one role a given subject holds at a
  given scope.
- **assignment-delete-request-shape**: the delete-assignment operation MUST send a delete
  request to a specific assignment's route scoped by workspace, and MUST resolve with no
  value.

**Item restriction**

- **item-restrict-request-shape**: the restrict-item operation MUST send a restrict request
  to the item-restriction route scoped by workspace, with a `{ feature, itemId }` body.
- **item-restore-request-shape**: the restore-item operation MUST send a restore request to
  the item-restoration route scoped by workspace, with a `{ feature, itemId }` body.
- **item-restrict-restore-parse-body**: the restrict-item and restore-item operations both
  parse the response body, despite being declared to resolve with no value; each MUST throw
  the same "unexpected empty response" error that the shared response-parsing helper throws
  whenever the backend answers with an empty (no-content) response, rather than resolving.

**Effective access**

- **effective-request-shape**: the effective-access query MUST send a request to the
  effective-access route with workspace, feature, subject-kind, and subject-id query
  parameters, adding an item identifier only when one is given, and MUST omit that parameter
  from the query entirely (not send it empty) when it is not.
- **effective-response-shape**: the effective-access query MUST return the parsed body
  verbatim as an effective-access row, applying no transformation.
- **restricted-flag-shared-meaning**: the effective-access row's `restricted` flag and the
  optional `restricted` flag on the list-assignments operation's item-scoped response both
  describe the same fact — whether the target item was marked restricted via the
  restrict-item operation — but the list-assignments operation's flag is present only for an
  item-scoped query while the effective-access query's is always present.

**Cross-cutting**

- **every-call-url-encodes-identifiers**: every operation MUST percent-encode the workspace
  identifier and any of the id/feature/item/subject identifiers it places in a URL; the
  subject-kind value on the effective-access query is placed unescaped because it is a
  closed set of literal values, never caller-supplied free text.
- **no-compact-on-write-bodies**: the create-role, update-role, and assignment-upsert
  operations MUST NOT strip unset fields from their input before serializing it; they rely
  on the serialization format's own omission of unset keys, which is sufficient for a plain
  object with optional fields.
- **no-client-side-cache**: the client MUST NOT cache or memoize any response; every call
  issues exactly one request.
- **stateless-module**: the client MUST hold no mutable state across calls; the only
  persistent value is the fallback feature list, a fixed, read-only list.

### Security

This is a security-relevant recipe: it is the client for a role/permission (authorization)
surface. It carries no secret of its own — the bearer credential lives in the shared
authentication client, which this module composes rather than reimplements — and it performs
no client-side authorization check of its own, deferring entirely to the backend.

- **auth-delegated-to-shared-client**: every call MUST go through the shared
  authenticated-request helper, which attaches a bearer credential read from the shared
  token store; this module MUST NOT read, store, or attach a token itself.
- **session-refresh-waterfall**: a `401` response to any call MUST trigger exactly one token
  refresh and one retried request, inherited unconditionally from the shared
  authenticated-fetch layer; a second `401` on the retried request MUST propagate as a
  thrown HTTP error with `status: 401`. This module defines no refresh or retry logic of its
  own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST
  cause the call to throw an HTTP error, carrying the response's HTTP status and, when the
  body supplies one, a machine-readable `code`.
- **feature-validation-error-is-plain**: the error `feature-row-shape-validated` throws
  carries no `status`, so the shared status-extraction helper returns `undefined` for it,
  distinguishing "the backend answered but the body was malformed" from any HTTP-level
  failure.
- **authorization-enforced-server-side**: the client MUST NOT perform any client-side
  permission check before sending a request. Per the module's own top-of-file comment,
  workspace membership, the admin-only gate on role definition, and the manage-access-verb
  requirement on assignment and restriction writes are enforced entirely by the backend,
  which answers a non-member's read with `404` rather than `403` — so a non-member cannot
  distinguish "this workspace has no such resource" from "you may not see it."
- **no-escalation-is-a-server-guarantee**: the source's own comment states that the server
  enforces no-escalation on assignment and restriction writes; this file contains no code
  that checks or blocks a self-escalating grant — the guarantee is external to it, not
  implemented here.

## Appearance

Not applicable — this is the workspace roles & permissions data-access client, not a visual
component.

## States

Not applicable — this is the workspace roles & permissions data-access client, not a visual
component; any loading/error/empty visual state is owned by the presentation layer that
consumes it.

## Accessibility

Not applicable — this is the workspace roles & permissions data-access client, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-access-001 | feature-list-scoped-by-workspace | List feature areas for workspace `acme` | Request URL contains `/api/access/features` and `workspace=acme` — `access.test.ts` › "GETs the workspace-scoped features route" |
| hub-domain-access-002 | every-call-url-encodes-identifiers | List feature areas for workspace `a b/c` | Request URL contains `workspace=` followed by the percent-encoded slug — `access.test.ts` › "encodes a workspace slug that needs escaping" |
| hub-domain-access-003 | feature-list-unwraps-envelope | Response body `{ features: [{ key: "projects", label: "Projects" }] }` | The list-features operation resolves to `[{ key: "projects", label: "Projects" }]` — `access.test.ts` › "unwraps the { features } envelope to the bare array" |
| hub-domain-access-004 | feature-order-preserved | Response body with three rows in order `projects`, `personas`, `audiences` | The list-features operation resolves in that exact order — `access.test.ts` › "preserves registration order across multiple rows" |
| hub-domain-access-005 | feature-row-shape-validated | Response body `{ features: "abc" }` | The list-features operation rejects (throws) — `access.test.ts` › "rejects when features is a string, not an array" |
| hub-domain-access-006 | feature-row-shape-validated | Response body `{ features: [{ key: "", label: "Projects" }] }` | Rejects — `access.test.ts` › "rejects a row whose key is the empty string" |
| hub-domain-access-007 | feature-row-shape-validated | Response body `{}` (no `features` key) | Rejects — `access.test.ts` › "rejects when the features key is absent entirely" |
| hub-domain-access-008 | fallback-features-fixed-set | Read the fallback feature list | Deep-equals `[{ key: "projects", label: "Projects" }, { key: "personas", label: "Personas" }]` — no dedicated test; derived directly from the source literal |
| hub-domain-access-009 | fallback-features-not-invoked-automatically | List feature areas for workspace `acme` against a response that trips feature-row-shape-validated | The rejection propagates to the caller unchanged; the fallback feature list is never referenced inside the list-features operation's source — no test exercises this by design, since it asserts an absence |
| hub-domain-access-010 | role-list-scoped-by-workspace | List roles for workspace `acme` against a stub returning `{ roles: [{ id: "r1", slug: "editor", ... }] }` | Resolves to that exact array, unwrapped and unvalidated — no dedicated test; derived directly from source |
| hub-domain-access-011 | role-create-request-shape | Create a role for workspace `acme` with `{ slug: "editor", name: "Editor", grants: [] }` | `POST /api/access/roles?workspace=acme` with that body verbatim; resolves to the created role — no dedicated test; derived directly from source |
| hub-domain-access-012 | role-update-excludes-slug | Attempt to include `slug` in the update-role patch input | Rejected by the patch input's own shape, which has no `slug` field — confirmed by the input's declared contract, no runtime test needed |
| hub-domain-access-013 | role-delete-request-shape | Delete role `role-1` in workspace `acme` | `DELETE /api/access/roles/role-1?workspace=acme`; resolves to no value — no dedicated test; derived directly from source |
| hub-domain-access-014 | assignment-list-workspace-wide | List assignments for workspace `acme` with no scope | `GET /api/access/assignments?workspace=acme` with no `feature`/`itemId` query parameters — no dedicated test; derived directly from source |
| hub-domain-access-015 | assignment-list-item-scoped | List assignments for workspace `acme` scoped to feature `projects`, item `p1` | Request URL also contains `&feature=projects&itemId=p1` — no dedicated test; derived directly from source |
| hub-domain-access-016 | assignment-put-upserts-one-per-scope | Upsert an assignment for workspace `acme` with `{ subjectKind: "customer", subjectId: "c1", roleId: "r1" }` | `PUT /api/access/assignments?workspace=acme` with that body verbatim; resolves to the resulting assignment — no dedicated test; derived directly from source |
| hub-domain-access-017 | assignment-delete-request-shape | Delete assignment `a1` in workspace `acme` | `DELETE /api/access/assignments/a1?workspace=acme`; resolves to no value — no dedicated test; derived directly from source |
| hub-domain-access-018 | item-restrict-request-shape | Restrict item `p1` in feature `projects` for workspace `acme` | `POST /api/access/items/restrict?workspace=acme` with body `{ feature: "projects", itemId: "p1" }` — no dedicated test; derived directly from source |
| hub-domain-access-019 | item-restrict-restore-parse-body | Restrict item `p1` in feature `projects` for workspace `acme` against a stub response with `status: 204` | Throws the "Unexpected empty response (204 No Content); use authedRequest for endpoints with no body" error, traced to the shared response-parsing helper's own check; not caught anywhere in the restrict-item operation |
| hub-domain-access-020 | effective-request-shape | Query effective access for workspace `acme` with `{ feature: "projects", subjectKind: "customer", subjectId: "c1" }` and no item | Request URL has no `itemId=` segment at all — no dedicated test; derived directly from source |
| hub-domain-access-021 | effective-request-shape | Same query with item `p1` added | Request URL includes `&itemId=p1` — no dedicated test; derived directly from source |
| hub-domain-access-022 | session-refresh-waterfall | Any call's first response is `401`; refreshing the token resolves a new one | The request is retried once with the new token; a `401` on that retry throws an HTTP error with `status: 401` — traced to the shared authenticated-fetch layer, exercised only indirectly through this client |
| hub-domain-access-023 | errors-carry-status-and-code | Backend responds `403` with body `{ error: { message: "forbidden", code: "no_manage_verb" } }` | The thrown HTTP error has `status: 403` and `code: "no_manage_verb"` — no dedicated test in this file; traced to the shared authentication client's error-extraction helpers |
| hub-domain-access-024 | authorization-enforced-server-side | Backend responds `404` to a list-roles/list-assignments/effective-access call made by a non-member | The call rejects with an HTTP error `status: 404`; the client performs no membership pre-check of its own — no source branch inspects caller identity before sending the request |

## Edge Cases

- **Null and empty input — `workspace`**: Not checked client-side. `workspace` is a plain
  string the caller supplies; an empty slug is sent to the server unchanged as `workspace=`.
  A non-empty customer or org slug is a caller precondition, per the module's top-of-file
  comment.
- **Null and empty input — assignment scope pairing**: see `assignment-scope-pairing-validation`
  below.
- **Empty `grants` array**: the create-role and update-role operations MUST send an empty
  `grants: []` unchanged when the caller supplies one; no client-side check requires at
  least one grant — a role with zero grants is a valid, unvalidated request as far as this
  module is concerned.
- **Boundary values — grant verb strings**: grant rows' item-verb and subitem-verb fields are
  strings with a documented expected character set (a comma-letter subset of `C,R,U,D,M` and
  `C,R,U,D` respectively), but the create-role and update-role operations send whatever
  string the caller provides with no client-side charset or length check. This is a fact,
  not a gap: the sibling fallback-feature-list documentation notes that "every submitted
  grant is refined against it server-side," establishing that this client's job is to pass
  the value through, not police its shape.
- **Concurrent access — module state**: the client holds no shared mutable state between
  calls (the only persistent value is the read-only fallback feature list), so there is
  nothing for two concurrent calls to race on within this module.
- **Concurrent access — competing writes**: two concurrent assignment-upsert calls for the
  same subject and scope follow ordinary upsert semantics — last response received wins,
  with no client-side sequencing or optimistic-lock check in this file.
- **Error states — validation failure vs. HTTP failure**: the error `feature-row-shape-validated`
  throws and an HTTP error are distinguishable only via the shared status-extraction
  helper's status check.
- **Error states — 204 on a declared-void write**: see `item-restrict-restore-parse-body`
  above; this is the one place in the file where an operation declared to resolve with no
  value can throw on success-shaped input, depending on what the backend actually returns.
- **Offline or disconnected state**: none of the ten operations catches a network-level
  failure; a connectivity loss mid-call propagates unhandled out of the client to the
  caller, with no retry, queuing, or offline-specific handling anywhere in this file.
- **No timeout**: no call sets a deadline or cancellation signal; a reachable-but-unresponsive
  backend leaves the call pending until the underlying transport's own limit, if any.
- **No cancellation**: no operation accepts a cancellation-signal parameter, so a caller
  cannot cancel an in-flight request through this module.
- **No retry beyond the 401 waterfall**: every call issues exactly one request (plus, on a
  `401`, the single inherited refresh-and-retry); nothing in this file retries a network
  failure or a non-401 error status.
- **assignment-scope-pairing-validation**: NEEDS REVIEW: Not implemented in source. The
  assignment write input's `feature`/`itemId` fields are independently optional, but the
  field's own doc comment declares they must be provided together to scope a grant to one
  item and omitted together for a workspace-wide grant; the assignment-upsert operation
  sends whatever partial combination the caller passes with no client-side check enforcing
  that pairing. Evidence that would settle it: the backend's handling of a
  `feature`-without-`itemId` (or the reverse) assignment write, which is not present in this
  checkout.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` | string (caller parameter) | none — required on every call | The workspace slug (personal customer slug or org slug) every call is scoped to; percent-encoded before being placed in the URL. |
| `scope` (list-assignments) | object with `feature` and `itemId` (optional) | omitted → workspace-wide listing | When given, narrows the assignments list to one item; omitted, lists workspace-wide assignments. |
| `input` (create-role) | role write input | none — required | `{ slug, name, description?, defaultFor?, grants }`, sent verbatim as the create-request body. |
| `patch` (update-role) | partial role write input, excluding `slug` | none — required | Any subset of `name`/`description`/`defaultFor`/`grants`; `slug` cannot be supplied. |
| `input` (assignment-upsert) | assignment write input | none — required | `{ subjectKind, subjectId, feature?, itemId?, roleId }`, sent verbatim as the upsert-request body. |
| `q` (effective-access query) | `{ feature, subjectKind, subjectId, itemId? }` | none — required | `itemId` is appended to the query only when provided. |
| base route | fixed constant, `/api/access` | fixed | Not injectable or configurable; every request path is built from it. |
| fallback feature list | fixed, read-only list of feature-area rows | fixed two-entry list | The fallback a caller may use when listing feature areas fails against a backend that predates the features route; not applied automatically by this client. |

## Deep Linking

Not applicable: this client registers no URL scheme, route, or navigation target of its own;
it is a data client consumed by a separate presentation layer that owns any deep-linking
concern.

## Localization

Listing feature areas is the one place this module authors its own English string, rather
than relaying one from the backend:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `GET /access/features returned a malformed feature list` | Thrown when the response fails `feature-row-shape-validated`'s runtime shape check |

There is no localization mechanism in this module (no catalog, no key, no i18n call) — the
string above is a hardcoded literal, stated as fact per the non-UI component guidance rather
than as a gap. Every other error message a caller can observe from this client originates in
the backend's response body and is extracted by the shared authentication client, not
authored here.

## Accessibility Options

Not applicable: this client renders no UI and responds to none of Reduce Motion, Increase
Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the feature-listing operation and its fallback list name feature *areas* the
roles matrix edits (`projects`, `personas`) — a data-domain concept — not a feature-flag key;
the file contains no feature-flag or gating check of any kind.

## Analytics

Not applicable: the source contains no analytics or event-emission call.

## Privacy

- **Data collected**: this module originates no data of its own; it reads and writes role,
  grant, and assignment records identifying which subjects (`customer`/`persona`/`team`)
  hold which roles at which scopes. These are access-control records, not end-user PII.
- **Storage**: none. The client is a stateless per-call request builder; it holds nothing in
  memory or on disk beyond the lifetime of a single call, per `no-client-side-cache` and
  `stateless-module`.
- **Transmission**: yes. Every call carries a bearer credential attached by the shared
  authentication client (`auth-delegated-to-shared-client`), not by this module; whatever
  transport security the deployment provides is outside the scope of these two files.
- **Retention**: none. Nothing this module handles is retained after the response it
  produced is returned to the caller.

## Logging

Not applicable: this client contains no logging call of any kind.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/access/access.ts` and
  `wire.ts` hold the client; `accessApi` is built entirely on `authedJson`/`authedRequest`
  from `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc`
  (`encodeURIComponent`) from `./client-helpers`; `index.ts` re-exports both files as the
  package's public surface for the rest of the web app. The wire row types are
  `AccessFeatureRow`, `AccessGrantRow`, `AccessRoleRow`, `AccessAssignmentRow`,
  `EffectiveAccessRow`; the write input types are `AccessRoleInput` and
  `AccessAssignmentInput`; the fallback feature list is exported as `ACCESS_FEATURES`. The
  ten operations are named `listFeatures`, `listRoles`, `createRole`, `updateRole`,
  `deleteRole`, `listAssignments`, `putAssignment`, `deleteAssignment`, `restrictItem`,
  `restoreItem`, and `effective`. `updateRole`'s patch parameter is typed
  `Partial<Omit<AccessRoleInput,"slug">>`, which is where "slug is excluded" is enforced, at
  compile time, in this implementation. Errors are thrown as `AuthHttpError` (status +
  optional code), extracted via `extractErrorCode`/`extractErrorMessage` in
  `auth/src/client.ts`; the one-retry-on-401 refresh waterfall and token attachment live in
  `authedFetch`/`readAccessToken`/`refreshAccessToken` in that same file. The duck-typed
  status-extraction helper is `httpStatus()` in `http.ts`; write bodies rely on
  `JSON.stringify`'s omission of `undefined` keys rather than calling the `compact()` helper
  also in `client-helpers.ts`.
- **SwiftUI**: a Swift port would model `AccessFeatureRow`/`AccessGrantRow`/`AccessRoleRow`/
  `AccessAssignmentRow`/`EffectiveAccessRow` as `Codable, Hashable, Sendable` structs,
  mirroring the pattern the sibling Hub authentication recipe's `AuthenticationModels.swift`
  already uses, and `accessApi` as an `actor` or `@MainActor final class` exposing `async
  throws` functions built on `URLSession`, with a dedicated error type carrying the HTTP
  status and an optional machine code in place of `AuthHttpError`.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS Hub feature
  would consume the ported client through an injected data-source protocol — the same
  pattern `ApiTokensRail`/`AccessListsTopic` already use for their own data sources — rather
  than calling `URLSession` from the view layer.
- **Compose**: model the five wire rows as Kotlin `data class`es annotated `@Serializable`,
  and `accessApi` as a class exposing `suspend fun` equivalents built on Ktor or OkHttp, with
  a sealed error type carrying the HTTP status and optional code.
- **WinUI 3**: a .NET port would model the wire rows as `record`s attributed for
  `System.Text.Json`, and `accessApi` as a class exposing `Task<T>`-returning methods built
  on `HttpClient`, attaching `Authorization: Bearer <token>` the way this module's
  `authedFetch` does, refreshing on a `401` the same one-retry way, and defining an
  `AccessApiException` (status, code) parallel to `AuthHttpError` — this is the platform
  with the least existing prior art in this repo for that refresh-and-retry contract, so the
  WinUI 3 port would need to build the equivalent of `authedFetch` itself, not only
  `accessApi`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/access/` |

## Design Decisions

**Decision**: `ACCESS_FEATURES` is exported as a plain constant but never consulted from
inside `listFeatures` itself.
**Platform**: React/Web.
**Rationale**: the source's own comment frames it as a degraded path for "a backend that
predates `/access/features`," and the authoritative registry is per-deployment and
server-refined — so `listFeatures` staying strict (throw on anything it can't validate) and
leaving the fallback decision to the caller keeps this module from silently masking a real
backend/response mismatch as an old-backend case.
**Approved**: pending

**Decision**: `restrictItem`/`restoreItem` call `authedJson` rather than `authedRequest`,
even though both are declared `Promise<void>`.
**Platform**: React/Web.
**Rationale**: this is recorded as observed source behavior, not smoothed into the declared
type — a 204 response from either endpoint throws today, per `item-restrict-restore-parse-body`;
a port MUST preserve this exact behavior rather than "fixing" it to `authedRequest`'s
discard-the-body semantics, since the current backend's actual response shape for these two
routes is not available in this checkout to confirm which is correct.
**Approved**: pending

**Decision**: only `listFeatures` validates its response shape at runtime; `listRoles`,
`listAssignments`, and `effective` trust the generic `authedJson<T>` cast.
**Platform**: React/Web.
**Rationale**: the source's own `isAccessFeatureRow` comment explains this guard was added
after a bare cast on `/access/features` let a malformed response reach every consumer
looking like real data; no equivalent comment or fix exists for the other reads, so this
recipe records the current asymmetry as a fact of the source rather than projecting the same
guard onto endpoints that don't have it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | Reliability |

`separation-of-concerns` passes: `access.ts`/`wire.ts` contain zero UI or presentation code — both the
module's own top comment and `index.ts`'s comment describe it as the public surface of a data domain,
consumed by a separate presentation layer. `unit-test-coverage` is `partial`: of `accessApi`'s ten
methods, only `listFeatures` has dedicated unit tests (`access.test.ts`'s comment says as much
explicitly — every other consumer test mocks this package wholesale); `listRoles`, `createRole`,
`updateRole`, `deleteRole`, `listAssignments`, `putAssignment`, `deleteAssignment`, `restrictItem`,
`restoreItem`, and `effective` have none in this checkout. `explicit-error-handling` passes: nothing
in this file swallows an error — every failure either throws `AuthHttpError` (via the shared
`authedFetch`) or the plain validation `Error` `listFeatures` raises itself. `server-side-authorization`
passes: the module contains no client-side permission check of any kind, per `authorization-enforced-server-side`,
deferring membership, admin-only role edits, and the manage-access verb requirement entirely to the
backend. `error-response-handling` is `partial`: every call exposes a status and optional code for the
caller to branch on, but only `listFeatures`'s doc comment describes a specific, documented fallback
contract for one status (a `404` meaning "this backend predates the route") — and even that fallback
is implemented by the caller, not by this module; the other nine methods offer no per-code handling
beyond the generic `AuthHttpError` propagation. `graceful-degradation` is `partial`: `ACCESS_FEATURES`
exists as an explicit, documented escape hatch for exactly this situation, but `listFeatures` does not
apply it itself — degradation is opt-in by the caller, not automatic within this component, and no
other method offers a fallback of any kind.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
