---
id: 19839612-1fd1-44c5-8659-674c264240be
title: Hub Domain Security Client
domain: agentictoolkit://cookbook/data/security
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'TypeScript client for the /api/auth/tokens personal-API-token surface and
  the /api/bucket/access-groups bucket access-list surface: mint/list/revoke tokens,
  and access-group/member/grant CRUD.'
platforms:
- typescript
- web
tags:
- security
- api-tokens
- access-control
- hub
- buckets
depends-on: []
related:
- agentictoolkit://cookbook/hub/features/authentication
- agentictoolkit://cookbook/data/access
references:
- packages/web/packages/data/src/security/tokens.ts (agentictoolkit)
- packages/web/packages/data/src/security/bucket-access.ts (agentictoolkit)
- packages/web/packages/data/src/security/wire.ts (agentictoolkit)
- packages/web/packages/data/src/security/index.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
- packages/web/packages/adh-api-types/src/schema.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Security Client

## Overview

`tokens.ts` and `bucket-access.ts`, re-exported by `index.ts`, are the public surface of the security
data domain: two independent, unrelated-at-runtime clients that happen to share one folder because
both guard access to backend resources. `tokensApi` (`tokens.ts`) mints, lists, and revokes the
caller's own personal API tokens against `/api/auth/tokens`. `bucketAccessApi` (`bucket-access.ts`)
is, per its own top-of-file comment, "wired to the real backend access-group routes
(`websites/backend/src/routes/bucketGroups.ts`)": CRUD for bucket-scoped access lists (a named group
of principals plus CRUD grants per target), their members, and their grants, against
`/api/bucket/access-groups` and `/api/bucket/buckets/{bucketId}/access-groups`. `wire.ts` holds the
wire shapes for both; its own header comment states it is a package-local mirror of the
OpenAPI-generated shapes the hub previously imported from `@agentic-toolkit/adh-api-types` (for
`/auth/tokens` and `/bucket/{access-groups,buckets}/*`), carrying full backend-schema fidelity so the
toolkit stays decoupled from the hub's generated types. Both clients are thin request builders over
the shared `authedJson`/`authedRequest` helpers from `@agentic-toolkit/auth/client` (re-exported
through `./http`), plus `enc`/`compact` from `./client-helpers`. Neither client is a visual surface —
this is a headless **logic** module, so this recipe marks Appearance, States, and Accessibility not
applicable and carries the runtime contract entirely in Behavioral Requirements, per the non-UI
component guidance this recipe was authored under.

## Behavioral Requirements

**Personal API tokens (`tokensApi`)**

- **token-list-request-shape**: `list` MUST send `GET {BASE}` (`BASE` = the fixed constant
  `/api/auth/tokens`) and MUST return the parsed `ApiToken[]` body verbatim, applying no
  transformation.
- **token-scopes-unwraps-envelope**: `scopes` MUST send `GET {BASE}/scopes` and MUST return the bare
  `prefixes` array unwrapped from the `{ prefixes }` response envelope, not the envelope itself.
- **token-mint-request-shape**: `mint` MUST send `POST {BASE}` with the caller's `MintTokenBody`
  (`name`, `expiresAt?`, `scope?`) JSON-serialized verbatim as the body, with no `compact()` or other
  transformation applied first, and MUST return the parsed `ApiTokenCreated` body.
- **token-revoke-request-shape**: `revoke` MUST send `DELETE {BASE}/{id}`, with `id` percent-encoded
  via the global `encodeURIComponent` (not the `enc` alias `bucket-access.ts` uses for the same
  purpose), and MUST resolve with no value, discarding whatever body the response carries.
- **token-created-secret-returned-once**: `ApiTokenCreatedRow`'s own doc comment states its `token`
  field is "the raw token value — shown exactly once"; `mint` MUST return that field to the caller
  unmodified as part of the resolved `ApiTokenCreated`, and MUST NOT retain, log, or resend it itself.
- **token-metadata-never-carries-secret**: every other `tokensApi` operation (`list`, `scopes`,
  `revoke`) MUST operate only on `ApiTokenRow`, whose fields are `id`, `name`, `prefix` (documented as
  "non-secret leading chars, for display"), `createdAt`, `expiresAt`, `lastUsedAt`, and an optional
  `scope`; none of these three operations MUST ever receive or return the raw secret.

**Bucket access lists (`bucketAccessApi`)**

- **access-list-all-groups-cross-bucket**: `listAllGroups` MUST send `GET {GROUPS}` (`GROUPS` = the
  fixed constant `/api/bucket/access-groups`, unscoped to any single bucket) and MUST return the
  `accessGroups` array unwrapped from the `{ accessGroups }` envelope; per the source's own comment,
  this is the one cross-bucket call for the Access pane, in place of a per-bucket `listGroups`
  fan-out, and the caller — not this module — MUST join bucket names locally and filter to the
  ecosystem it is displaying.
- **access-group-detail-request-shape**: `getGroup` MUST send `GET {GROUPS}/{enc(groupId)}` and MUST
  return the parsed `AccessGroupDetail` verbatim, including its nested `members` and `grants` arrays.
- **access-group-create-scoped-to-bucket**: `createGroup` MUST send
  `POST {BUCKETS}/{enc(bucketId)}/access-groups` (`BUCKETS` = the fixed constant
  `/api/bucket/buckets`) with a body of `{ name, description? }`, where `name` is `input.name.trim()`
  and `description` is included only when `input.description` is truthy.
- **access-group-create-conflict-friendly**: on a caught error whose message matches `/already
  exists/i`, `createGroup` MUST rethrow a plain `Error` with the message `An access list named
  "<trimmed name>" already exists.`; any other caught error MUST be rethrown unchanged.
- **access-group-update-request-shape**: `updateGroup` MUST send `PATCH {GROUPS}/{enc(groupId)}` with
  a body built key-by-key: `name` is included, trimmed, only when `patch.name !== undefined`, and
  `description` is included, unmodified, only when `patch.description !== undefined`.
- **access-group-update-conflict-friendly**: on a caught error whose message matches `/already
  exists/i`, `updateGroup` MUST rethrow a plain `Error` with the message `An access list named
  "<trimmed patch.name, or empty string if patch.name is undefined>" already exists.`; any other
  caught error MUST be rethrown unchanged.
- **access-group-delete-request-shape**: `deleteGroup` MUST send `DELETE {GROUPS}/{enc(groupId)}` and
  MUST resolve with no value; unlike `createGroup`/`updateGroup`, it wraps the call in no `try`/`catch`
  of its own, so any error the backend returns — including the `409` the source's top comment says
  the seeded "everyone" group's delete always answers with — propagates to the caller unchanged and
  un-translated.
- **access-member-add-request-shape**: `addMember` MUST send
  `POST {GROUPS}/{enc(groupId)}/members` with a body of exactly `{ memberType, memberId }`.
- **access-member-add-conflict-friendly**: on a caught error whose message matches `/already
  exists/i`, `addMember` MUST rethrow a plain `Error` with the message `That member is already in
  this access list.`; any other caught error MUST be rethrown unchanged.
- **access-member-remove-request-shape**: `removeMember` MUST send
  `DELETE {GROUPS}/{enc(groupId)}/members/{enc(memberRowId)}` and MUST resolve with no value; per the
  source's own comment, `memberRowId` is the membership row's `id` (`AccessGroupMember.id`), never the
  principal's own id — the backend `DELETE` matches on the row id.
- **access-grant-upsert-request-shape**: `upsertGrant` MUST send `PUT {GROUPS}/{enc(groupId)}/grants`
  with a body of exactly `{ targetType, targetId, crud }` and MUST return the parsed `AccessGrant`;
  like `deleteGroup`, it wraps the call in no `try`/`catch`, so any backend error propagates
  unchanged.
- **access-grant-delete-request-shape**: `deleteGrant` MUST send
  `DELETE {GROUPS}/{enc(groupId)}/grants/{enc(grantId)}` and MUST resolve with no value.
- **access-crud-string-passthrough**: `upsertGrant` MUST send whatever `crud` string the caller
  supplies (documented on `AccessGrantPutBody`/`AccessGrantRow` as "comma-separated CRUD subset, e.g.
  `'C,R,U,D'` or `''` (none)") verbatim, with no client-side charset, ordering, or length check.
- **access-metadata-not-writable**: `AccessGroupCreateBody` and `AccessGroupPatchBody` MUST NOT
  include a `metadata` field; neither `createGroup` nor `updateGroup` can set the `metadata` a
  `BucketAccessGroup` row carries, even though `getGroup`/`listAllGroups` MUST return whatever
  `metadata` the backend supplies.

**Cross-cutting**

- **every-bucket-access-call-url-encodes-identifiers**: every `bucketAccessApi` method MUST
  percent-encode `bucketId`, `groupId`, `memberRowId`, and `grantId` via `enc` (`encodeURIComponent`
  aliased in `client-helpers.ts`) before placing them in a URL.
- **no-compact-on-write-bodies**: neither `mint`, `createGroup`, `updateGroup`, `addMember`, nor
  `upsertGrant` MUST call `compact()` from `client-helpers.ts` on its body before serializing it; each
  builds its own conditional object literal (or, for `mint`, serializes the caller's object directly),
  and `JSON.stringify`'s built-in omission of `undefined`-valued keys is what actually drops absent
  optionals.
- **no-client-side-cache**: neither `tokensApi` nor `bucketAccessApi` MUST cache or memoize any
  response; every call issues exactly one HTTP request.
- **stateless-module**: neither client MUST hold mutable module-level state across calls; the only
  module-level values are the fixed path constants `BASE`, `GROUPS`, and `BUCKETS`.

### Security

This is a security-relevant recipe: `tokensApi` issues and revokes the caller's own bearer-style API
credentials, and `bucketAccessApi` is the client for a resource-level authorization surface (who may
read/write which buckets, bucket types, or rows). Neither client carries the caller's own *session*
credential — that lives in `@agentic-toolkit/auth/client`, which both modules compose rather than
reimplement.

- **auth-delegated-to-shared-client**: every `tokensApi`/`bucketAccessApi` network call MUST go
  through `authedJson` or `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via
  `./http`), which attaches `Authorization: Bearer <token>` from `readAccessToken()`; neither module
  MUST read, store, or attach a session token itself.
- **session-refresh-waterfall**: a `401` response to any call from either client MUST trigger exactly
  one token refresh and one retried request, inherited unconditionally from `authedFetch`; a second
  `401` on the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. Neither
  file defines any refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one,
  a machine-readable `code`, per `authedFetch`'s shared implementation.
- **token-scope-passthrough-unvalidated**: `mint`'s `scope` parameter (documented on `ApiTokenRow` as
  "REST path prefixes this token may reach ... optional `:read` suffix, `*` = all") MUST be sent
  exactly as the caller supplies it, with no client-side check that a prefix is well-formed or that
  `expiresAt` is a valid future date; both are backend-validated concerns per this module's own lack
  of any such check.
- **token-can-be-a-grant-principal**: `MemberType` (`"user" | "organization" | "persona" | "app" |
  "token"`) includes `"token"`; `addMember` MUST accept a `memberId` that names an API token as a
  bucket access-group member exactly as it would a user or organization, with no distinct handling
  for that case.
- **server-side-grant-and-ceiling-validation**: per `bucket-access.ts`'s own top comment, the backend
  enforces "grant-target validity and the bucket ≥ type ≥ row ceiling" for every grant `upsertGrant`
  sends; this module performs no client-side check of a grant's target hierarchy before sending it.
- **server-side-seeded-group-protection**: per the same comment, the seeded `"everyone"` access group
  (`AccessGroupRow.kind === "everyone"`) is undeletable server-side — "delete → 409" — and
  `deleteGroup` contains no client-side check of `kind` before sending the request; the protection is
  enforced entirely by the backend and surfaced to the caller as an untranslated `409`, per
  `access-group-delete-request-shape`.

## Appearance

Not applicable — this is the personal API token and bucket access-list data-access client, not a
visual component.

## States

Not applicable — this is the personal API token and bucket access-list data-access client, not a
visual component; any loading/error/empty visual state is owned by the presentation layer that
consumes `tokensApi`/`bucketAccessApi`.

## Accessibility

Not applicable — this is the personal API token and bucket access-list data-access client, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-security-001 | token-list-request-shape | `tokensApi.list()` | `GET /api/auth/tokens`; resolves to the parsed `ApiToken[]` body verbatim — no dedicated test in this checkout; derived directly from source |
| hub-domain-security-002 | token-scopes-unwraps-envelope | `tokensApi.scopes()` against a stub returning `{ prefixes: ["/content/markdown"] }` | Resolves to `["/content/markdown"]`, not the envelope — no dedicated test; derived directly from source |
| hub-domain-security-003 | token-mint-request-shape | `tokensApi.mint({ name: "ci", scope: ["/content/markdown:read"] })` | `POST /api/auth/tokens` with that object JSON-serialized verbatim; resolves to `ApiTokenCreated` — no dedicated test; derived directly from source |
| hub-domain-security-004 | token-created-secret-returned-once | Response body `{ id: "t1", name: "ci", prefix: "abcd", createdAt: "...", expiresAt: null, lastUsedAt: null, token: "secret-raw-value" }` from `mint` | Resolved `ApiTokenCreated.token` equals `"secret-raw-value"`, unmodified — no dedicated test; derived directly from the `ApiTokenCreatedRow` type and `mint`'s pass-through return |
| hub-domain-security-005 | token-revoke-request-shape | `tokensApi.revoke("tok 1")` | `DELETE /api/auth/tokens/tok%201` (`encodeURIComponent("tok 1")`); resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-security-006 | access-list-all-groups-cross-bucket | `bucketAccessApi.listAllGroups()` against a stub returning `{ accessGroups: [{ id: "g1", bucketId: "b1", ... }] }` | Resolves to `[{ id: "g1", bucketId: "b1", ... }]`, unwrapped — no dedicated test; derived directly from source |
| hub-domain-security-007 | access-group-detail-request-shape | `bucketAccessApi.getGroup("g1")` | `GET /api/bucket/access-groups/g1`; resolves to the `AccessGroupDetail` verbatim, including `members`/`grants` — no dedicated test; derived directly from source |
| hub-domain-security-008 | access-group-create-scoped-to-bucket | `bucketAccessApi.createGroup("b1", { name: "  Editors  " })` | `POST /api/bucket/buckets/b1/access-groups` with body `{ name: "Editors" }` (no `description` key) — no dedicated test; derived directly from source |
| hub-domain-security-009 | access-group-create-conflict-friendly | `createGroup("b1", { name: "Editors" })` against a stub whose error message is `"Access group with that name already exists"` | Rejects with a plain `Error` whose message is exactly `An access list named "Editors" already exists.` — no dedicated test; derived directly from `rethrowConflict`'s regex and `createGroup`'s catch |
| hub-domain-security-010 | access-group-update-request-shape | `bucketAccessApi.updateGroup("g1", { description: "new" })` | `PATCH /api/bucket/access-groups/g1` with body `{ description: "new" }` only (`name` omitted since `patch.name` is `undefined`) — no dedicated test; derived directly from source |
| hub-domain-security-011 | access-group-update-conflict-friendly | `updateGroup("g1", {})` against a stub error message matching `/already exists/i` | Rejects with message `An access list named "" already exists.` (`patch.name` is `undefined`, so `(patch.name ?? "").trim()` is `""`) — no dedicated test; derived directly from source |
| hub-domain-security-012 | access-group-delete-request-shape | `bucketAccessApi.deleteGroup("everyone-group-id")` against a stub returning HTTP `409` with body `{ error: "cannot delete the everyone group" }` | Rejects with `AuthHttpError` `status: 409` and that exact backend message, unmodified — no dedicated test; derived directly from the absence of a `try`/`catch` in `deleteGroup` |
| hub-domain-security-013 | access-member-add-request-shape | `bucketAccessApi.addMember("g1", { memberType: "persona", memberId: "p1" })` | `POST /api/bucket/access-groups/g1/members` with body `{ memberType: "persona", memberId: "p1" }` — no dedicated test; derived directly from source |
| hub-domain-security-014 | access-member-add-conflict-friendly | `addMember("g1", { memberType: "user", memberId: "u1" })` against a stub error message matching `/already exists/i` | Rejects with message exactly `That member is already in this access list.` — no dedicated test; derived directly from source |
| hub-domain-security-015 | access-member-remove-request-shape | `bucketAccessApi.removeMember("g1", "row-42")` | `DELETE /api/bucket/access-groups/g1/members/row-42`; resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-security-016 | access-grant-upsert-request-shape | `bucketAccessApi.upsertGrant("g1", { targetType: "bucket_type", targetId: "bt1", crud: "C,R" })` | `PUT /api/bucket/access-groups/g1/grants` with body `{ targetType: "bucket_type", targetId: "bt1", crud: "C,R" }`; resolves to the parsed `AccessGrant` — no dedicated test; derived directly from source |
| hub-domain-security-017 | access-grant-upsert-request-shape | Same call against a stub returning HTTP `404` (e.g. `targetId` does not exist) | Rejects with `AuthHttpError` `status: 404`, propagated unchanged — no dedicated test; derived directly from the absence of a `try`/`catch` in `upsertGrant` |
| hub-domain-security-018 | access-grant-delete-request-shape | `bucketAccessApi.deleteGrant("g1", "grant-1")` | `DELETE /api/bucket/access-groups/g1/grants/grant-1`; resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-security-019 | access-crud-string-passthrough | `upsertGrant("g1", { targetType: "row", targetId: "r1", crud: "" })` | Request body's `crud` is the empty string, sent unchanged — no dedicated test; derived directly from source |
| hub-domain-security-020 | every-bucket-access-call-url-encodes-identifiers | `bucketAccessApi.getGroup("a b/c")` | Request URL contains `encodeURIComponent("a b/c")` in place of the raw id — no dedicated test; derived directly from `enc`'s definition as `encodeURIComponent` |
| hub-domain-security-021 | token-revoke-request-shape | `tokensApi.revoke("a/b")` compared against `bucketAccessApi.deleteGroup("a/b")` | Both requests carry the identical percent-encoded segment `a%2Fb`, even though `revoke` uses the global `encodeURIComponent` and `deleteGroup` uses the `enc` alias — both are the same function, so the two call sites are behaviorally identical despite the naming divergence |
| hub-domain-security-022 | session-refresh-waterfall | Any `tokensApi`/`bucketAccessApi` call's first response is `401`; `refreshAccessToken()` resolves a new token | The request is retried once with the new token; a `401` on that retry throws `AuthHttpError` with `status: 401` — traced to `authedFetch` in `auth/src/client.ts`, exercised only indirectly through either client |
| hub-domain-security-023 | errors-carry-status-and-code | Backend responds `403` to `upsertGrant` with body `{ error: { message: "forbidden", code: "no_manage_verb" } }` | The thrown `AuthHttpError` has `status: 403` and `code: "no_manage_verb"` — traced to `extractErrorCode`/`extractErrorMessage` in `auth/src/client.ts` |
| hub-domain-security-024 | no-client-side-cache | Two sequential `tokensApi.list()` calls | Two distinct HTTP requests are issued; the second call's result is never served from a value cached by the first — no dedicated test; derived directly from the absence of any cache/memoization in the source |

## Edge Cases

- **Null and empty input — `createGroup`/`updateGroup` name**: `input.name.trim()` on an empty or
  all-whitespace string produces `""`, which is sent to the backend unchanged; neither method rejects
  it client-side.
- **Null and empty input — `addMember`/`upsertGrant` identifiers**: `memberId`, `targetId`, and
  `crud: ""` are all accepted as empty strings and sent verbatim; only `crud: ""` has documented
  meaning ("none"), per `access-crud-string-passthrough`.
- **Null and empty input — path-segment identifiers**: `enc("")`/`encodeURIComponent("")` on an empty
  `groupId`, `memberRowId`, `grantId`, `bucketId`, or token `id` produces an empty URL segment (e.g.
  `.../members/`); the resulting malformed request is still sent, with no client-side guard against
  it.
- **Boundary values — `mint` scope/expiry**: MUST — `mint` accepts any string array for `scope` and
  any string (or `null`) for `expiresAt` with no length, format, or range check; a caller-supplied
  malformed date string or an unbounded `scope` array is sent to the backend as-is.
- **Boundary values — `crud` grant string**: no minimum or maximum length, no de-duplication of
  repeated letters, and no validation that only `C`/`R`/`U`/`D` characters appear; `upsertGrant` sends
  whatever string the caller provides.
- **Concurrent access — module state**: neither `tokensApi` nor `bucketAccessApi` holds shared mutable
  state between calls (`stateless-module`), so there is nothing for two concurrent calls to race on
  within these files.
- **Concurrent access — competing name/member conflicts**: two concurrent `createGroup` calls with the
  same trimmed `name` in the same bucket, or two concurrent `addMember` calls with the same
  `memberId`, are resolved by the backend's uniqueness constraint; the loser's request receives the
  `409` that `access-group-create-conflict-friendly`/`access-member-add-conflict-friendly` translate to
  a friendly message — there is no client-side pre-check, only this post-hoc translation.
- **Concurrent access — competing grant/group writes**: two concurrent `upsertGrant` calls for the
  same `groupId`/`targetType`/`targetId`, or a `deleteGroup` racing an `updateGroup` for the same
  `groupId`, follow ordinary HTTP semantics — last response received wins, with no client-side
  sequencing, version check, or optimistic lock anywhere in either file.
- **Error states — validation failure vs. HTTP failure**: every error either client can throw is an
  `AuthHttpError` (via `authedFetch`) or, for the three `rethrowConflict` sites, a plain `Error`
  carrying only a friendly message and no `status`; `httpStatus()` (`http.ts`) distinguishes the two by
  duck-typing the `.status` property.
- **Error states — dependency unavailable**: neither client catches a `fetch`-level network rejection
  anywhere outside the `401` waterfall `authedFetch` already provides; a DNS failure, connection
  refusal, or TLS error propagates as an unhandled promise rejection out of whichever method was
  called.
- **Offline or disconnected state**: none of the twelve `tokensApi`/`bucketAccessApi` methods detects
  or reacts to a loss of connectivity mid-call; a connection dropped after the request was sent but
  before a response arrived surfaces only as the underlying `fetch` rejection described above.
- **No timeout**: no method in either file sets a deadline or `AbortSignal`; a reachable-but-
  unresponsive backend leaves the call pending until the underlying `fetch` implementation's own
  limit, if any.
- **No cancellation**: no method accepts an `AbortSignal` parameter, so a caller cannot cancel an
  in-flight request through either client.
- **No retry beyond the 401 waterfall**: every call issues exactly one request (plus, on a `401`, the
  single inherited refresh-and-retry); nothing in either file retries a network failure or a non-401
  error status.
- **token-mint-retry-duplication**: `mint` sends a plain `POST` with no idempotency key, client-generated request id, or de-duplication; a caller that retries `mint` after an ambiguous failure (a timeout or dropped connection after the first `POST` reached the backend) sends a second request, which can mint a second, independently-secreted token. Unlike `createGroup`/`addMember`, whose retries collide on a uniqueness constraint and surface a `409`, nothing in `tokens.ts` gives a retried `mint` an equivalent signal; any de-duplication belongs to the backend's `POST /api/auth/tokens` route.
- **token-member-revocation-orphan**: `MemberType` allows an API token to be a bucket access-group member (`memberType: "token"`), but `tokens.ts` and `bucket-access.ts` never coordinate: `tokensApi.revoke` sends only the revoke request and touches no `AccessGroupMember` row. Whether rows naming the revoked token are removed is decided by the backend's revocation handler, not by either client.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `BASE` (`tokensApi`) | module constant, `"/api/auth/tokens"` | fixed | Not injectable; every `tokensApi` request path is built as `${BASE}/...`. |
| `GROUPS` (`bucketAccessApi`) | module constant, `"/api/bucket/access-groups"` | fixed | Not injectable; the base path for group/member/grant operations by `groupId`. |
| `BUCKETS` (`bucketAccessApi`) | module constant, `"/api/bucket/buckets"` | fixed | Not injectable; used only by `createGroup`'s `${BUCKETS}/{bucketId}/access-groups` path. |
| `body` (`mint`) | `MintTokenBody` (`{ name, expiresAt?, scope? }`) | none — required | Sent verbatim as the `POST` body; `expiresAt`/`scope` are omitted from the wire body entirely when left `undefined` by `JSON.stringify`. |
| `id` (`revoke`) | `string` (caller parameter) | none — required | The token's `id`; percent-encoded via the global `encodeURIComponent` before being placed in the URL. |
| `bucketId` (`createGroup`) | `string` (caller parameter) | none — required | The owning bucket; percent-encoded via `enc`. |
| `groupId` (most `bucketAccessApi` methods) | `string` (caller parameter) | none — required | The access group's `id`; percent-encoded via `enc`. |
| `input` (`createGroup`) | `{ name: string; description?: string }` | none — required | `name` is trimmed before send; `description` is sent only when truthy. |
| `patch` (`updateGroup`) | `{ name?: string; description?: string }` | none — required | Each key is sent only when the caller supplies it (checked via `!== undefined`, not truthiness). |
| `input` (`addMember`) | `{ memberType: MemberType; memberId: string }` | none — required | Sent verbatim as the `POST` body. |
| `memberRowId` (`removeMember`) | `string` (caller parameter) | none — required | The `AccessGroupMember.id` of the membership row, not the principal's id. |
| `input` (`upsertGrant`) | `{ targetType: GrantTargetType; targetId: string; crud: string }` | none — required | Sent verbatim as the `PUT` body; `crud` is not validated client-side. |
| `grantId` (`deleteGrant`) | `string` (caller parameter) | none — required | The grant's `id`; percent-encoded via `enc`. |

## Deep Linking

Not applicable: `tokens.ts`, `bucket-access.ts`, and `wire.ts` register no URL scheme, route, or
navigation target of their own; they are data clients consumed by a separate presentation layer that
owns any deep-linking concern.

## Localization

`bucket-access.ts` is the one place in this domain that authors its own English strings, rather than
relaying one from the backend:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `An access list named "<name>" already exists.` | Thrown by `createGroup` on a name conflict, via `rethrowConflict` |
| — | `An access list named "<name>" already exists.` | Thrown by `updateGroup` on a name conflict, via `rethrowConflict` |
| — | `That member is already in this access list.` | Thrown by `addMember` on a member-uniqueness conflict, via `rethrowConflict` |

There is no localization mechanism in this domain (no catalog, no key, no `i18n` call) — the three
strings above are hardcoded literals, stated as fact per the non-UI component guidance rather than as
a gap. Every other error message a caller can observe from `tokensApi` or `bucketAccessApi` originates
in the backend's response body and is extracted by `extractErrorMessage` in `auth/src/client.ts`, not
authored in these two files.

## Accessibility Options

Not applicable: `tokens.ts`, `bucket-access.ts`, and `wire.ts` render no UI and respond to none of
Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the source contains no feature-flag key, gate, or conditional check of any kind.

## Analytics

Not applicable: the source contains no analytics or event-emission call.

## Privacy

- **Data collected**: `tokensApi` originates and returns personal API token records — `id`, `name`,
  `prefix` ("non-secret leading chars, for display"), `createdAt`, `expiresAt`, `lastUsedAt`, `scope`
  — and, on `mint` only, the raw secret `token` value, documented as "shown exactly once."
  `bucketAccessApi` reads and writes access-group, member, and grant records identifying which
  principals (`user`/`organization`/`persona`/`app`/`token`) hold which CRUD grants at which targets.
  The token secret is credential material; the access-group records are access-control records, not
  end-user PII.
- **Storage**: none within these files. Both clients are stateless per-call request builders (per
  `stateless-module`); neither holds the minted secret, a session token, or any access-control record
  in memory or on disk beyond the lifetime of a single call.
- **Transmission**: yes. Every call carries a bearer session credential attached by
  `@agentic-toolkit/auth/client` (`auth-delegated-to-shared-client`), not by these modules; `mint`
  additionally receives a freshly issued raw secret token in its response body. Whatever transport
  security the deployment provides is outside the scope of these files.
- **Retention**: none within these files. Whatever the backend retains — token metadata rows, access
  group/member/grant rows — is outside the scope of `tokens.ts`, `bucket-access.ts`, and `wire.ts`.

## Logging

Not applicable: no `console`, logger, or other diagnostic call of any kind appears in `tokens.ts`,
`bucket-access.ts`, or `wire.ts`.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/security/tokens.ts` and
  `bucket-access.ts` hold the two clients; `wire.ts` holds their shared wire shapes; `index.ts`
  re-exports all three as the package's public surface. Both clients are built entirely on
  `authedJson`/`authedRequest` from `@agentic-toolkit/auth/client` (re-exported through `./http`) and
  `enc` (`encodeURIComponent`) from `./client-helpers`; `tokens.ts` alone calls the global
  `encodeURIComponent` directly rather than the `enc` alias, per `token-revoke-request-shape`.
- **SwiftUI**: a Swift port already exists for this exact backend surface —
  `packages/apple/AgenticToolkit/Hub/Features/Authentication/ApiTokensRail.swift` and
  `AccessListsTopic.swift` (documented in the sibling `auth-client-authentication` recipe) — and models
  the wire rows as `Codable, Sendable` structs and each client as an `@MainActor final class` exposing
  `async throws` methods over an injected data-source protocol, with a `HubError` in place of
  `AuthHttpError`. A fresh port of these two TypeScript files specifically should follow that existing
  pattern rather than introduce a second one.
- **AppKit / UIKit**: no direct UI dependency exists in either TypeScript file; consuming code reaches
  the ported client through an injected data-source protocol (`ApiTokensDataSource`,
  `BucketAccessDataSource` in the existing Swift port), never by calling `URLSession` from the view
  layer directly.
- **Compose**: model the six wire rows (`ApiToken`, `ApiTokenCreated`, `AccessGroup`,
  `AccessGroupMember`, `AccessGrant`, `AccessGroupDetail`) as Kotlin `data class`es annotated
  `@Serializable`, and each client as a class exposing `suspend fun` equivalents built on Ktor or
  OkHttp, with a sealed error type carrying the HTTP status and optional code in place of
  `AuthHttpError`.
- **WinUI 3**: a .NET port would model the wire rows as `record`s attributed for
  `System.Text.Json`, and `TokensApi`/`BucketAccessApi` as classes exposing `Task<T>`-returning methods
  built on `HttpClient`, attaching `Authorization: Bearer <token>` the way `authedFetch` does and
  refreshing on a `401` the same one-retry way, with an `ApiException` (status, code) parallel to
  `AuthHttpError`. This is the platform with the least existing prior art in this repo for that
  refresh-and-retry contract — as with the sibling `hub-domain-access` recipe's `accessApi`, a WinUI 3
  port would need to build the equivalent of `authedFetch` itself before either client can be ported,
  including its own single-refresh-then-retry-on-401 waterfall.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/security/` |

## Design Decisions

**Decision**: `deleteGroup` and `upsertGrant` wrap their call in no `try`/`catch`, while
`createGroup`, `updateGroup`, and `addMember` each catch and pass the error through `rethrowConflict`.
**Rationale**: `rethrowConflict` rewrites an error only when its message matches `/already exists/i`
— a naming or uniqueness collision the caller caused by picking a value that collided with an
existing row. `deleteGroup`'s `409` (the seeded "everyone" group refusing deletion) and any `upsertGrant`
failure are not naming collisions, so wrapping either in `rethrowConflict` would be a no-op even if
added: the regex would never match, and the original error would pass through unchanged regardless.
**Approved**: pending

**Decision**: `tokens.ts`'s `revoke` percent-encodes its path segment with the global
`encodeURIComponent`, while every `bucket-access.ts` method uses the `enc` alias
(`client-helpers.ts`'s re-export of the identical function) for the same purpose.
**Rationale**: not explained in either source file; recorded here as an observed naming inconsistency
between two sibling files in the same domain folder, not a functional difference — both names resolve
to the same built-in function, so `hub-domain-security-021`'s behavior is identical either way. A port
to another platform should use one consistent name for this operation rather than carrying the
inconsistency forward.
**Approved**: pending

**Decision**: `wire.ts`'s types are declared as a package-local mirror of the OpenAPI-generated shapes
in `@agentic-toolkit/adh-api-types`, rather than importing them directly.
**Rationale**: per `wire.ts`'s own header comment, this keeps the toolkit decoupled from the hub's
generated types "without narrowing what a caller can rely on" — the mirrored interfaces carry full
backend-schema fidelity (every field the backend's OpenAPI schema declares), not only the subset
`tokens.ts`/`bucket-access.ts` happen to read or write today.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | partial | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |

`separation-of-concerns` passes: `tokens.ts`, `bucket-access.ts`, and `wire.ts` contain zero UI or
presentation code — both the module's own comments and `index.ts` describe it as the public surface
of a data domain, consumed by a separate presentation layer. `unit-test-coverage` fails: this checkout
has no `__tests__` directory, and no test file of any kind, under
`packages/web/packages/data/src/security/` — none of `tokensApi`'s four methods or
`bucketAccessApi`'s eight methods has a dedicated unit test, unlike the sibling `access.ts`, which has
at least one tested method. `explicit-error-handling` passes: nothing in either file swallows an
error — every failure either throws `AuthHttpError` (via the shared `authedFetch`) or, at the three
`rethrowConflict` sites, a plain translated `Error`; nothing is caught and discarded.
`server-side-authorization` passes: neither client performs a client-side permission check of any
kind, per `server-side-grant-and-ceiling-validation` and `server-side-seeded-group-protection` —
grant-target validity, the bucket ≥ type ≥ row ceiling, and the seeded group's delete protection are
all enforced entirely by the backend. `token-lifecycle` is `partial`: `mint`/`revoke` support an
optional expiry and on-demand revocation, but this client enforces no minimum or maximum token
lifetime and performs no rotation of its own — a deliberate difference from a short-lived session
access token (these are long-lived personal API tokens by design, per `ApiTokenRow`'s `expiresAt:
string | null` allowing "never expires"), but the check's stated bar ("short-lived (5-15 min) with
refresh token rotation") is not met by this token model, and this recipe records that gap rather than
mark the check inapplicable to a security-relevant credential-issuing surface. `error-response-handling`
is `partial`: `createGroup`, `updateGroup`, and `addMember` translate their one documented conflict
code into a friendly message, but `deleteGroup`, `upsertGrant`, `deleteGrant`, `mint`, and `revoke`
offer no per-status handling beyond the generic `AuthHttpError` propagation every non-2xx response
already gets. `idempotent-operations` is `partial`: `upsertGrant` is a true upsert via `PUT` and is
idempotent by construction; `createGroup` and `addMember` are not idempotent themselves but turn a
retried duplicate into a detectable `409` via the backend's uniqueness constraint; `mint` has neither
property — per `token-mint-retry-duplication`, a retried `mint` can silently issue a second, live
credential with no way for the caller to detect or reconcile it from this module alone.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
