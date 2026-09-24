---
id: 39a7192e-7e1e-4e93-b615-312a5ddf69b0
title: Hub Domain Access Client
domain: agentictoolkit://recipes/hub-domain-access
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'TypeScript client for the workspace roles & permissions /access API: feature
  areas, role CRUD, subject assignments, item restriction, and the effective-access
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

`access.ts` and `wire.ts`, re-exported by `index.ts`, are the public surface of the workspace roles
& permissions data domain — the client for the gated `/api/access` surface the source calls out in
its own top-of-file comment. Every operation names the workspace by slug (a personal workspace's
customer slug or an org slug); reads answer `404` to non-members, role definition is admin-only, and
assignment/restriction writes need the `M` (manage-access) verb at the target scope, all enforced by
the backend. `wire.ts` holds the wire shapes (`AccessFeatureRow`, `AccessGrantRow`, `AccessRoleRow`,
`AccessAssignmentRow`, `EffectiveAccessRow`); `access.ts` exports the `ACCESS_FEATURES` fallback
constant, the `AccessRoleInput`/`AccessAssignmentInput` write shapes, and the `accessApi` object of
ten methods, each a thin request builder over the shared `authedJson`/`authedRequest` helpers from
`@agentic-toolkit/auth/client` (re-exported through `./http`). It is a headless **logic** module — no
visual surface — so this recipe marks Appearance, States, and Accessibility not applicable and carries
the runtime contract entirely in Behavioral Requirements, per the non-UI component guidance this
recipe was authored under.

## Behavioral Requirements

**Feature areas (`listFeatures`, `ACCESS_FEATURES`)**

- **feature-list-scoped-by-workspace**: `listFeatures` MUST send `GET {BASE}/features` with a
  `workspace=<enc(workspace)>` query parameter, where `BASE` is the fixed constant `/api/access`.
- **feature-list-unwraps-envelope**: `listFeatures` MUST return the bare `features` array unwrapped
  from the `{ features }` response envelope, not the envelope itself.
- **feature-row-shape-validated**: `listFeatures` MUST throw a plain `Error` with the message
  `GET /access/features returned a malformed feature list` when `features` is not an array, or when
  any element is not an object whose `key` and `label` are both non-empty strings.
- **feature-order-preserved**: `listFeatures` MUST return rows in the order the backend sent them; it
  performs no client-side sort or reorder.
- **fallback-features-not-invoked-automatically**: `ACCESS_FEATURES` MUST NOT be substituted
  automatically by `listFeatures` on any failure — it is exported for a caller's own catch block, and
  no code path inside `listFeatures` reads or returns it.
- **fallback-features-fixed-set**: `ACCESS_FEATURES` MUST be exactly the two-entry, order-preserving
  array `[{key:"projects",label:"Projects"},{key:"personas",label:"Personas"}]`.

**Roles (`listRoles`, `createRole`, `updateRole`, `deleteRole`)**

- **role-list-scoped-by-workspace**: `listRoles` MUST send `GET {BASE}/roles?workspace=<enc(workspace)>`
  and return `body.roles` unwrapped and unvalidated — unlike `listFeatures`, no runtime shape check is
  applied to this response.
- **role-create-request-shape**: `createRole` MUST send `POST {BASE}/roles?workspace=<enc(workspace)>`
  with `AccessRoleInput` (`slug`, `name`, `description?`, `defaultFor?`, `grants`) JSON-serialized
  verbatim as the body, and MUST return `body.role`.
- **role-update-excludes-slug**: `updateRole`'s `patch` parameter is typed
  `Partial<Omit<AccessRoleInput,"slug">>`; a role's `slug` MUST NOT be changeable through this
  operation.
- **role-update-request-shape**: `updateRole` MUST send `PATCH {BASE}/roles/<enc(id)>?workspace=<enc(workspace)>`
  with the patch object JSON-serialized verbatim as the body, and MUST return `body.role`.
- **role-delete-request-shape**: `deleteRole` MUST send `DELETE {BASE}/roles/<enc(id)>?workspace=<enc(workspace)>`
  and MUST resolve with no value, discarding whatever body the response carries.

**Assignments (`listAssignments`, `putAssignment`, `deleteAssignment`)**

- **assignment-list-workspace-wide**: `listAssignments` called with no `scope` argument MUST send
  `GET {BASE}/assignments?workspace=<enc(workspace)>` with no `feature`/`itemId` query parameters, and
  MUST return the `{ assignments, restricted? }` body verbatim.
- **assignment-list-item-scoped**: `listAssignments` called with a `scope` argument MUST append
  `&feature=<enc(scope.feature)>&itemId=<enc(scope.itemId)>` to that same URL; unlike
  `AccessAssignmentInput`, `listAssignments`' `scope` type requires `feature` and `itemId` together —
  there is no way to supply only one.
- **assignment-put-upserts-one-per-scope**: `putAssignment` MUST send
  `PUT {BASE}/assignments?workspace=<enc(workspace)>` with `AccessAssignmentInput` JSON-serialized
  verbatim as the body, and MUST return `body.assignment`; per the source's own comment, this grants or
  replaces the one role a given subject holds at a given scope.
- **assignment-delete-request-shape**: `deleteAssignment` MUST send
  `DELETE {BASE}/assignments/<enc(id)>?workspace=<enc(workspace)>` and MUST resolve with no value.

**Item restriction (`restrictItem`, `restoreItem`)**

- **item-restrict-request-shape**: `restrictItem` MUST send
  `POST {BASE}/items/restrict?workspace=<enc(workspace)>` with a `{ feature, itemId }` JSON body.
- **item-restore-request-shape**: `restoreItem` MUST send
  `POST {BASE}/items/restore?workspace=<enc(workspace)>` with a `{ feature, itemId }` JSON body.
- **item-restrict-restore-parse-body**: `restrictItem` and `restoreItem` both call `authedJson`, not
  `authedRequest`, despite declaring `Promise<void>`; each MUST throw the same "unexpected empty
  response" `Error` that `authedJson` throws whenever the backend answers with HTTP 204, rather than
  resolving.

**Effective access (`effective`)**

- **effective-request-shape**: `effective` MUST send
  `GET {BASE}/effective?workspace=<enc(workspace)>&feature=<enc(q.feature)>&subjectKind=<q.subjectKind>&subjectId=<enc(q.subjectId)>`,
  appending `&itemId=<enc(q.itemId)>` only when `q.itemId` is given, and MUST omit that segment from
  the query string entirely (not send `itemId=`) when it is not.
- **effective-response-shape**: `effective` MUST return the parsed body verbatim as an
  `EffectiveAccessRow`, applying no transformation.
- **restricted-flag-shared-meaning**: `EffectiveAccessRow.restricted` and the optional `restricted` on
  `listAssignments`' item-scoped response both describe the same fact — whether the target item was
  marked restricted via `restrictItem` — but `listAssignments`' flag is present only for an item-scoped
  query while `effective`'s is always present.

**Cross-cutting**

- **every-call-url-encodes-identifiers**: every `accessApi` method MUST percent-encode `workspace` and
  any of `id`/`feature`/`itemId`/`subjectId` it places in a URL, via `enc` (`encodeURIComponent`
  aliased in `client-helpers.ts`); `subjectKind` on `effective` is interpolated unescaped because it is
  a closed string-literal union, never caller-supplied free text.
- **no-compact-on-write-bodies**: `createRole`, `updateRole`, and `putAssignment` MUST NOT call
  `compact()` from `client-helpers.ts` on their input before serializing it; they rely on
  `JSON.stringify`'s built-in omission of `undefined`-valued keys, which is sufficient for a plain
  object literal with optional fields.
- **no-client-side-cache**: `accessApi` MUST NOT cache or memoize any response; every call issues
  exactly one HTTP request.
- **stateless-module**: `accessApi` MUST hold no mutable module-level state across calls; the only
  module-level value besides the `BASE` string constant is `ACCESS_FEATURES`, a fixed, read-only array.

### Security

This is a security-relevant recipe: it is the client for a role/permission (authorization) surface.
It carries no secret of its own — the bearer credential lives in `@agentic-toolkit/auth/client`,
which this module composes rather than reimplements — and it performs no client-side authorization
check of its own, deferring entirely to the backend.

- **auth-delegated-to-shared-client**: every `accessApi` network call MUST go through `authedJson` or
  `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via `./http`), which attaches
  `Authorization: Bearer <token>` from `readAccessToken()`; this module MUST NOT read, store, or attach
  a token itself.
- **session-refresh-waterfall**: a `401` response to any `accessApi` call MUST trigger exactly one
  token refresh and one retried request, inherited unconditionally from `authedFetch`; a second `401`
  on the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. This module
  defines no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`.
- **feature-validation-error-is-plain**: the `Error` `feature-row-shape-validated` throws carries no
  `status`, so `httpStatus()` (the duck-typed helper in `http.ts`) returns `undefined` for it,
  distinguishing "the backend answered but the body was malformed" from any HTTP-level failure.
- **authorization-enforced-server-side**: `accessApi` MUST NOT perform any client-side permission
  check before sending a request. Per the module's own top-of-file comment, workspace membership, the
  admin-only gate on role definition, and the `M`-verb requirement on assignment and restriction writes
  are enforced entirely by the backend, which answers a non-member's read with `404` rather than `403`
  — so a non-member cannot distinguish "this workspace has no such resource" from "you may not see it."
- **no-escalation-is-a-server-guarantee**: the source's own comment states that the server enforces
  no-escalation on assignment and restriction writes; this file contains no code that checks or blocks
  a self-escalating grant — the guarantee is external to it, not implemented here.

## Appearance

Not applicable — this is the workspace roles & permissions data-access client, not a visual component.

## States

Not applicable — this is the workspace roles & permissions data-access client, not a visual component;
any loading/error/empty visual state is owned by the presentation layer that consumes `accessApi`.

## Accessibility

Not applicable — this is the workspace roles & permissions data-access client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-access-001 | feature-list-scoped-by-workspace | `listFeatures("acme")` | Request URL contains `/api/access/features` and `workspace=acme` — `access.test.ts` › "GETs the workspace-scoped features route" |
| hub-domain-access-002 | every-call-url-encodes-identifiers | `listFeatures("a b/c")` | Request URL contains `workspace=` followed by `encodeURIComponent("a b/c")` — `access.test.ts` › "encodes a workspace slug that needs escaping" |
| hub-domain-access-003 | feature-list-unwraps-envelope | Response body `{ features: [{ key: "projects", label: "Projects" }] }` | `listFeatures` resolves to `[{ key: "projects", label: "Projects" }]` — `access.test.ts` › "unwraps the { features } envelope to the bare array" |
| hub-domain-access-004 | feature-order-preserved | Response body with three rows in order `projects`, `personas`, `audiences` | `listFeatures` resolves in that exact order — `access.test.ts` › "preserves registration order across multiple rows" |
| hub-domain-access-005 | feature-row-shape-validated | Response body `{ features: "abc" }` | `listFeatures` rejects (throws) — `access.test.ts` › "rejects when features is a string, not an array" |
| hub-domain-access-006 | feature-row-shape-validated | Response body `{ features: [{ key: "", label: "Projects" }] }` | `listFeatures` rejects — `access.test.ts` › "rejects a row whose key is the empty string" |
| hub-domain-access-007 | feature-row-shape-validated | Response body `{}` (no `features` key) | `listFeatures` rejects — `access.test.ts` › "rejects when the features key is absent entirely" |
| hub-domain-access-008 | fallback-features-fixed-set | Read the exported `ACCESS_FEATURES` constant | Deep-equals `[{ key: "projects", label: "Projects" }, { key: "personas", label: "Personas" }]` — no dedicated test; derived directly from the source literal |
| hub-domain-access-009 | fallback-features-not-invoked-automatically | `listFeatures("acme")` against a response that trips `feature-row-shape-validated` | The rejection propagates to the caller unchanged; `ACCESS_FEATURES` is never referenced inside `listFeatures`'s source — no test exercises this by design, since it asserts an absence |
| hub-domain-access-010 | role-list-scoped-by-workspace | `listRoles("acme")` against a stub returning `{ roles: [{ id: "r1", slug: "editor", ... }] }` | Resolves to that exact array, unwrapped and unvalidated — no dedicated test; derived directly from source |
| hub-domain-access-011 | role-create-request-shape | `createRole("acme", { slug: "editor", name: "Editor", grants: [] })` | `POST /api/access/roles?workspace=acme` with that body verbatim; resolves to `body.role` — no dedicated test; derived directly from source |
| hub-domain-access-012 | role-update-excludes-slug | Compile-time: constructing `{ slug: "x", name: "y" }` as `updateRole`'s `patch` argument | Fails to typecheck against `Partial<Omit<AccessRoleInput,"slug">>` — confirmed by the type declaration, no runtime test needed |
| hub-domain-access-013 | role-delete-request-shape | `deleteRole("acme", "role-1")` | `DELETE /api/access/roles/role-1?workspace=acme`; resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-access-014 | assignment-list-workspace-wide | `listAssignments("acme")` | `GET /api/access/assignments?workspace=acme` with no `feature`/`itemId` query parameters — no dedicated test; derived directly from source |
| hub-domain-access-015 | assignment-list-item-scoped | `listAssignments("acme", { feature: "projects", itemId: "p1" })` | Request URL also contains `&feature=projects&itemId=p1` — no dedicated test; derived directly from source |
| hub-domain-access-016 | assignment-put-upserts-one-per-scope | `putAssignment("acme", { subjectKind: "customer", subjectId: "c1", roleId: "r1" })` | `PUT /api/access/assignments?workspace=acme` with that body verbatim; resolves to `body.assignment` — no dedicated test; derived directly from source |
| hub-domain-access-017 | assignment-delete-request-shape | `deleteAssignment("acme", "a1")` | `DELETE /api/access/assignments/a1?workspace=acme`; resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-access-018 | item-restrict-request-shape | `restrictItem("acme", "projects", "p1")` | `POST /api/access/items/restrict?workspace=acme` with body `{ feature: "projects", itemId: "p1" }` — no dedicated test; derived directly from source |
| hub-domain-access-019 | item-restrict-restore-parse-body | `restrictItem("acme", "projects", "p1")` against a stub response with `status: 204` | Throws the "Unexpected empty response (204 No Content); use authedRequest for endpoints with no body" `Error`, traced to `authedJson`'s own check; not caught anywhere in `restrictItem` |
| hub-domain-access-020 | effective-request-shape | `effective("acme", { feature: "projects", subjectKind: "customer", subjectId: "c1" })` (no `itemId`) | Request URL has no `itemId=` segment at all — no dedicated test; derived directly from source |
| hub-domain-access-021 | effective-request-shape | Same call with `itemId: "p1"` added | Request URL includes `&itemId=p1` — no dedicated test; derived directly from source |
| hub-domain-access-022 | session-refresh-waterfall | Any `accessApi` call's first response is `401`; `refreshAccessToken()` resolves a new token | The request is retried once with the new token; a `401` on that retry throws `AuthHttpError` with `status: 401` — traced to `authedFetch` in `auth/src/client.ts`, exercised only indirectly through `accessApi` |
| hub-domain-access-023 | errors-carry-status-and-code | Backend responds `403` with body `{ error: { message: "forbidden", code: "no_manage_verb" } }` | The thrown `AuthHttpError` has `status: 403` and `code: "no_manage_verb"` — no dedicated `access.ts` test; traced to `extractErrorCode`/`extractErrorMessage` in `auth/src/client.ts` |
| hub-domain-access-024 | authorization-enforced-server-side | Backend responds `404` to `listRoles`/`listAssignments`/`effective` called by a non-member | The call rejects with `AuthHttpError` `status: 404`; `accessApi` performs no membership pre-check of its own — no source branch inspects caller identity before sending the request |

## Edge Cases

- **Null and empty input — `workspace`**: Not checked client-side. `workspace` is a typed `string` the caller supplies; an empty slug is sent to the server unchanged as `workspace=`. A non-empty customer or org slug is a caller precondition, per the module's top-of-file comment.
- **Null and empty input — assignment scope pairing**: `assignment-scope-pairing-validation` below.
- **Empty `grants` array**: `createRole`/`updateRole` MUST send an empty `grants: []` unchanged when the
  caller supplies one; no client-side check requires at least one grant — a role with zero grants is a
  valid, unvalidated request as far as this module is concerned.
- **Boundary values — grant verb strings**: `AccessGrantRow.itemVerbs`/`.subitemVerbs` are typed
  `string` with a doc-commented expected character set (a comma-letter subset of `C,R,U,D,M` and
  `C,R,U,D` respectively), but `createRole`/`updateRole` send whatever string the caller provides with
  no client-side charset or length check. This is a fact, not a gap: the sibling `ACCESS_FEATURES`
  comment documents that "every submitted grant is refined against it server-side," establishing that
  this client's job is to pass the value through, not police its shape.
- **Concurrent access — module state**: `accessApi` holds no shared mutable state between calls (the
  only module-level value besides the `BASE` constant is the read-only `ACCESS_FEATURES` array), so
  there is nothing for two concurrent calls to race on within this module.
- **Concurrent access — competing writes**: two concurrent `putAssignment` calls for the same subject
  and scope follow ordinary `PUT` semantics — last response received wins, with no client-side
  sequencing or optimistic-lock check in this file.
- **Error states — validation failure vs. HTTP failure**: `feature-row-shape-validated`'s thrown
  `Error` and an `AuthHttpError` are distinguishable only via `httpStatus()`'s duck-typed `.status`
  check (`http.ts`); the former has none, per `feature-validation-error-is-plain`.
- **Error states — 204 on a declared-void write**: `item-restrict-restore-parse-body` above; this is
  the one place in the file where a declared `Promise<void>` operation can throw on success-shaped
  input, depending on what the backend actually returns.
- **Offline or disconnected state**: none of the ten `accessApi` methods catches a network-level
  `fetch` rejection; a connectivity loss mid-call propagates as an unhandled promise rejection out of
  `accessApi` to the caller, with no retry, queuing, or offline-specific handling anywhere in this
  file.
- **No timeout**: no `accessApi` call sets a deadline or `AbortSignal`; a reachable-but-unresponsive
  backend leaves the call pending until the underlying `fetch` implementation's own limit, if any.
- **No cancellation**: no `accessApi` method accepts an `AbortSignal` parameter, so a caller cannot
  cancel an in-flight request through this module.
- **No retry beyond the 401 waterfall**: every `accessApi` call issues exactly one request (plus, on a
  `401`, the single inherited refresh-and-retry); nothing in this file retries a network failure or a
  non-401 error status.
- **assignment-scope-pairing-validation**: NEEDS REVIEW: Not implemented in source. `AccessAssignmentInput.feature`/`.itemId` are independently optional, but the field's own doc comment declares they must be provided together to scope a grant to one item and omitted together for a workspace-wide grant; `putAssignment` sends whatever partial combination the caller passes with no client-side check enforcing that pairing. Evidence that would settle it: the backend's handling of a `feature`-without-`itemId` (or the reverse) assignment write, which is not present in this checkout.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` | `string` (caller parameter) | none — required on every call | The workspace slug (personal customer slug or org slug) every `accessApi` call is scoped to; percent-encoded via `enc` before being placed in the URL. |
| `scope` (`listAssignments`) | `{ feature: string; itemId: string }` (optional) | omitted → workspace-wide listing | When given, narrows the assignments list to one item; omitted, lists workspace-wide assignments. |
| `input` (`createRole`) | `AccessRoleInput` | none — required | `{ slug, name, description?, defaultFor?, grants }`, sent verbatim as the `POST` body. |
| `patch` (`updateRole`) | `Partial<Omit<AccessRoleInput,"slug">>` | none — required | Any subset of `name`/`description`/`defaultFor`/`grants`; `slug` is excluded from the type. |
| `input` (`putAssignment`) | `AccessAssignmentInput` | none — required | `{ subjectKind, subjectId, feature?, itemId?, roleId }`, sent verbatim as the `PUT` body. |
| `q` (`effective`) | `{ feature, subjectKind, subjectId, itemId? }` | none — required | `itemId` is appended to the query string only when provided. |
| `BASE` | module constant, `"/api/access"` | fixed | Not injectable or configurable; every request path is built as `${BASE}/...`. |
| `ACCESS_FEATURES` | module constant, `ReadonlyArray<AccessFeatureRow>` | fixed two-entry array | The fallback a caller may use when `listFeatures` fails against a backend that predates `/access/features`; not applied automatically by this module. |

## Deep Linking

Not applicable: `access.ts`/`wire.ts` register no URL scheme, route, or navigation target of their
own; they are a data client consumed by a separate presentation layer that owns any deep-linking
concern.

## Localization

`listFeatures` is the one place this module authors its own English string, rather than relaying one
from the backend:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `GET /access/features returned a malformed feature list` | Thrown by `listFeatures` when the response fails `feature-row-shape-validated`'s runtime shape check |

There is no localization mechanism in this module (no catalog, no key, no `i18n` call) — the string
above is a hardcoded literal, stated as fact per the non-UI component guidance rather than as a gap.
Every other error message a caller can observe from `accessApi` originates in the backend's response
body and is extracted by `extractErrorMessage` in `auth/src/client.ts`, not authored here.

## Accessibility Options

Not applicable: `access.ts`/`wire.ts` render no UI and respond to none of Reduce Motion, Increase
Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: `listFeatures`/`ACCESS_FEATURES` name feature *areas* the roles matrix edits
(`projects`, `personas`) — a data-domain concept — not a feature-flag key; the file contains no
feature-flag or gating check of any kind.

## Analytics

Not applicable: the source contains no analytics or event-emission call.

## Privacy

- **Data collected**: this module originates no data of its own; it reads and writes role, grant, and
  assignment records identifying which subjects (`customer`/`persona`/`team`) hold which roles at which
  scopes. These are access-control records, not end-user PII.
- **Storage**: none. `accessApi` is a stateless per-call request builder; it holds nothing in memory or
  on disk beyond the lifetime of a single call, per `no-client-side-cache` and `stateless-module`.
- **Transmission**: yes. Every call carries a bearer credential attached by `@agentic-toolkit/auth/client`
  (`auth-delegated-to-shared-client`), not by this module; whatever transport security the deployment
  provides is outside the scope of these two files.
- **Retention**: none. Nothing this module handles is retained after the response it produced is
  returned to the caller.

## Logging

Not applicable: `access.ts` and `wire.ts` contain no logging call of any kind.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/access/access.ts` and `wire.ts`
  hold the client; `accessApi` is built entirely on `authedJson`/`authedRequest` from
  `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc` (`encodeURIComponent`) from
  `./client-helpers`; `index.ts` re-exports both files as the package's public surface for the rest of
  the web app.
- **SwiftUI**: a Swift port would model `AccessFeatureRow`/`AccessGrantRow`/`AccessRoleRow`/
  `AccessAssignmentRow`/`EffectiveAccessRow` as `Codable, Hashable, Sendable` structs, mirroring the
  pattern the sibling Hub authentication recipe's `AuthenticationModels.swift` already uses, and
  `accessApi` as an `actor` or `@MainActor final class` exposing `async throws` functions built on
  `URLSession`, with a dedicated error type carrying the HTTP status and an optional machine code in
  place of `AuthHttpError`.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS Hub feature would
  consume the ported client through an injected data-source protocol — the same pattern
  `ApiTokensRail`/`AccessListsTopic` already use for their own data sources — rather than calling
  `URLSession` from the view layer.
- **Compose**: model the five wire rows as Kotlin `data class`es annotated `@Serializable`, and
  `accessApi` as a class exposing `suspend fun` equivalents built on Ktor or OkHttp, with a sealed
  error type carrying the HTTP status and optional code.
- **WinUI 3**: a .NET port would model the wire rows as `record`s attributed for `System.Text.Json`,
  and `accessApi` as a class exposing `Task<T>`-returning methods built on `HttpClient`, attaching
  `Authorization: Bearer <token>` the way this module's `authedFetch` does, refreshing on a `401` the
  same one-retry way, and defining an `AccessApiException` (status, code) parallel to `AuthHttpError`
  — this is the platform with the least existing prior art in this repo for that refresh-and-retry
  contract, so the WinUI 3 port would need to build the equivalent of `authedFetch` itself, not only
  `accessApi`.

## Design Decisions

**Decision**: `ACCESS_FEATURES` is exported as a plain constant but never consulted from inside
`listFeatures` itself.
**Rationale**: the source's own comment frames it as a degraded path for "a backend that predates
`/access/features`," and the authoritative registry is per-deployment and server-refined — so
`listFeatures` staying strict (throw on anything it can't validate) and leaving the fallback decision
to the caller keeps this module from silently masking a real backend/response mismatch as an old-backend
case.
**Approved**: pending

**Decision**: `restrictItem`/`restoreItem` call `authedJson` rather than `authedRequest`, even though
both are declared `Promise<void>`.
**Rationale**: this is recorded as observed source behavior, not smoothed into the declared type — a
204 response from either endpoint throws today, per `item-restrict-restore-parse-body`; a port MUST
preserve this exact behavior rather than "fixing" it to `authedRequest`'s discard-the-body semantics,
since the current backend's actual response shape for these two routes is not available in this
checkout to confirm which is correct.
**Approved**: pending

**Decision**: only `listFeatures` validates its response shape at runtime; `listRoles`, `listAssignments`,
and `effective` trust the generic `authedJson<T>` cast.
**Rationale**: the source's own `isAccessFeatureRow` comment explains this guard was added after a
bare cast on `/access/features` let a malformed response reach every consumer looking like real data;
no equivalent comment or fix exists for the other reads, so this recipe records the current asymmetry
as a fact of the source rather than projecting the same guard onto endpoints that don't have it.
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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
