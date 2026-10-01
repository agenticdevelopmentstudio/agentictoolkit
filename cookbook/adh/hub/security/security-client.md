---
id: 19839612-1fd1-44c5-8659-674c264240be
title: Security Client
domain: agentictoolkit://cookbook/adh/hub/security/security-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The client-side contract for the personal API token surface (`/api/auth/tokens`) and the
  bucket access-list surface (`/api/bucket/access-groups`): mint/list/revoke tokens, and
  access-group/member/grant CRUD.'
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
- agentictoolkit://cookbook/adh/hub/security/authentication-client
- agentictoolkit://cookbook/adh/hub/access
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

# Security Client

## Overview

Two independent, unrelated-at-runtime clients that happen to share one surface because both guard
access to backend resources: a **personal API tokens client** mints, lists, and revokes the caller's
own personal API tokens against `/api/auth/tokens`. A **bucket access lists client** is, per its own
documentation, "wired to the real backend access-group routes": CRUD for bucket-scoped access lists (a
named group of principals plus CRUD grants per target), their members, and their grants, against
`/api/bucket/access-groups` and `/api/bucket/buckets/{bucketId}/access-groups`. A shared wire-shapes
module holds the wire shapes for both; per its own header comment it is a local mirror of the backend's
OpenAPI-generated shapes (for `/auth/tokens` and `/bucket/{access-groups,buckets}/*`), carrying full
backend-schema fidelity so this component stays decoupled from the backend's generated types. Both
clients are thin request builders over shared authenticated-request helpers, plus shared
encoding/compaction helpers. Neither client is a visual surface — this is a headless **logic** module,
so this recipe marks Appearance, States, and Accessibility not applicable and carries the runtime
contract entirely in Behavioral Requirements, per the non-UI component guidance this recipe was
authored under.

## Behavioral Requirements

**Personal API tokens**

- **token-list-request-shape**: Listing tokens MUST send `GET /api/auth/tokens` and MUST return the
  parsed token list verbatim, applying no transformation.
- **token-scopes-unwraps-envelope**: Fetching the scope catalogue MUST send `GET
  /api/auth/tokens/scopes` and MUST return the bare `prefixes` array unwrapped from the `{ prefixes }`
  response envelope, not the envelope itself.
- **token-mint-request-shape**: Minting a token MUST send `POST /api/auth/tokens` with the caller's
  mint body (`name`, `expiresAt?`, `scope?`) JSON-serialized verbatim as the body, with no compaction or
  other transformation applied first, and MUST return the parsed created-token response.
- **token-revoke-request-shape**: Revoking a token MUST send `DELETE /api/auth/tokens/{id}`, with `id`
  percent-encoded, and MUST resolve with no value, discarding whatever body the response carries.
- **token-created-secret-returned-once**: A minted token's secret field is documented as "the raw token
  value — shown exactly once"; minting MUST return that field to the caller unmodified as part of the
  resolved created-token response, and MUST NOT retain, log, or resend it itself.
- **token-metadata-never-carries-secret**: Every other tokens operation (listing, fetching scopes,
  revoking) MUST operate only on the non-secret token record, whose fields are `id`, `name`, `prefix`
  (documented as "non-secret leading chars, for display"), `createdAt`, `expiresAt`, `lastUsedAt`, and
  an optional `scope`; none of these three operations MUST ever receive or return the raw secret.

**Bucket access lists**

- **access-list-all-groups-cross-bucket**: Listing all access groups MUST send `GET
  /api/bucket/access-groups`, unscoped to any single bucket, and MUST return the group array unwrapped
  from the `{ accessGroups }` envelope; per the source's own documentation, this is the one cross-bucket
  call for the Access pane, in place of a per-bucket listing fan-out, and the caller — not this
  component — MUST join bucket names locally and filter to the ecosystem it is displaying.
- **access-group-detail-request-shape**: Fetching a group's detail MUST send `GET
  /api/bucket/access-groups/{groupId}` (percent-encoded) and MUST return the parsed group detail
  verbatim, including its nested `members` and `grants` arrays.
- **access-group-create-scoped-to-bucket**: Creating a group MUST send `POST
  /api/bucket/buckets/{bucketId}/access-groups` (percent-encoded) with a body of `{ name, description?
  }`, where `name` is the trimmed input name and `description` is included only when the input
  description is truthy.
- **access-group-create-conflict-friendly**: On a caught error whose message matches an "already
  exists" pattern, creating a group MUST rethrow a plain error with the message `An access list named
  "<trimmed name>" already exists.`; any other caught error MUST be rethrown unchanged.
- **access-group-update-request-shape**: Updating a group MUST send `PATCH
  /api/bucket/access-groups/{groupId}` with a body built key-by-key: `name` is included, trimmed, only
  when the caller supplies it, and `description` is included, unmodified, only when the caller supplies
  it.
- **access-group-update-conflict-friendly**: On a caught error matching the same "already exists"
  pattern, updating a group MUST rethrow a plain error with the message `An access list named "<trimmed
  name, or empty string if none was supplied>" already exists.`; any other caught error MUST be
  rethrown unchanged.
- **access-group-delete-request-shape**: Deleting a group MUST send `DELETE
  /api/bucket/access-groups/{groupId}` and MUST resolve with no value; unlike creating/updating a group,
  it applies no error translation of its own, so any error the backend returns — including the conflict
  the seeded "everyone" group's delete always answers with — propagates to the caller unchanged and
  un-translated.
- **access-member-add-request-shape**: Adding a member MUST send `POST
  /api/bucket/access-groups/{groupId}/members` with a body of exactly `{ memberType, memberId }`.
- **access-member-add-conflict-friendly**: On a caught error matching the same "already exists"
  pattern, adding a member MUST rethrow a plain error with the message `That member is already in this
  access list.`; any other caught error MUST be rethrown unchanged.
- **access-member-remove-request-shape**: Removing a member MUST send `DELETE
  /api/bucket/access-groups/{groupId}/members/{memberRowId}` and MUST resolve with no value; per the
  source's own documentation, the member-row id is the membership row's own id, never the principal's
  own id — the backend delete matches on the row id.
- **access-grant-upsert-request-shape**: Upserting a grant MUST send `PUT
  /api/bucket/access-groups/{groupId}/grants` with a body of exactly `{ targetType, targetId, crud }`
  and MUST return the parsed grant; like deleting a group, it applies no error translation, so any
  backend error propagates unchanged.
- **access-grant-delete-request-shape**: Deleting a grant MUST send `DELETE
  /api/bucket/access-groups/{groupId}/grants/{grantId}` and MUST resolve with no value.
- **access-crud-string-passthrough**: Upserting a grant MUST send whatever `crud` string the caller
  supplies (documented as "comma-separated CRUD subset, e.g. `'C,R,U,D'` or `''` (none)") verbatim, with
  no client-side charset, ordering, or length check.
- **access-metadata-not-writable**: Neither the create-group nor update-group request body MUST
  include a `metadata` field; neither operation can set the `metadata` an access group record carries,
  even though fetching a group or listing all groups MUST return whatever `metadata` the backend
  supplies.

**Cross-cutting**

- **every-bucket-access-call-url-encodes-identifiers**: Every bucket access-list operation MUST
  percent-encode the bucket id, group id, member-row id, and grant id before placing them in a URL.
- **no-compact-on-write-bodies**: None of minting, creating a group, updating a group, adding a member,
  or upserting a grant MUST apply a general-purpose field-compaction transform to its body before
  serializing it; each builds its own conditional object shape (or, for minting, serializes the
  caller's object directly), and the standard omission of `undefined`-valued keys during serialization
  is what actually drops absent optionals.
- **no-client-side-cache**: Neither client MUST cache or memoize any response; every call issues
  exactly one HTTP request.
- **stateless-module**: Neither client MUST hold mutable state across calls; the only persistent values
  are the fixed path constants for the tokens base path, the groups base path, and the buckets base
  path.

### Security

This is a security-relevant recipe: the personal API tokens client issues and revokes the caller's own
bearer-style API credentials, and the bucket access lists client is the client for a resource-level
authorization surface (who may read/write which buckets, bucket types, or rows). Neither client carries
the caller's own *session* credential — that lives in a shared authenticated-request helper, which both
clients compose rather than reimplement.

- **auth-delegated-to-shared-client**: Every token/access-list network call MUST go through the shared
  authenticated-request helpers, which attach a bearer token read from the stored access token; neither
  client MUST read, store, or attach a session token itself.
- **session-refresh-waterfall**: A `401` response to any call from either client MUST trigger exactly
  one token refresh and one retried request, inherited unconditionally from the shared request helper;
  a second `401` on the retried request MUST propagate as a thrown error carrying `status: 401`.
  Neither client defines any refresh or retry logic of its own.
- **errors-carry-status-and-code**: Any non-2xx response other than an unresolved `401` MUST cause the
  call to throw an error carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`, per the shared request helper's implementation.
- **token-scope-passthrough-unvalidated**: Minting's `scope` parameter (documented as "REST path
  prefixes this token may reach ... optional `:read` suffix, `*` = all") MUST be sent exactly as the
  caller supplies it, with no client-side check that a prefix is well-formed or that `expiresAt` is a
  valid future date; both are backend-validated concerns per this component's own lack of any such
  check.
- **token-can-be-a-grant-principal**: The member-type vocabulary (`"user" | "organization" | "persona"
  | "app" | "token"`) includes `"token"`; adding a member MUST accept a member id that names an API
  token as a bucket access-group member exactly as it would a user or organization, with no distinct
  handling for that case.
- **server-side-grant-and-ceiling-validation**: Per this component's own documentation, the backend
  enforces "grant-target validity and the bucket ≥ type ≥ row ceiling" for every grant an upsert sends;
  this component performs no client-side check of a grant's target hierarchy before sending it.
- **server-side-seeded-group-protection**: Per the same documentation, the seeded `"everyone"` access
  group is undeletable server-side — "delete → 409" — and deleting a group contains no client-side
  check of the group's kind before sending the request; the protection is enforced entirely by the
  backend and surfaced to the caller as an untranslated conflict response, per
  `access-group-delete-request-shape`.

## Appearance

Not applicable — this is the personal API token and bucket access-list data-access client, not a
visual component.

## States

Not applicable — this is the personal API token and bucket access-list data-access client, not a
visual component; any loading/error/empty visual state is owned by the presentation layer that
consumes either client.

## Accessibility

Not applicable — this is the personal API token and bucket access-list data-access client, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-security-001 | token-list-request-shape | Listing tokens | `GET /api/auth/tokens`; resolves to the parsed token list verbatim — no dedicated test in this checkout; derived directly from source |
| hub-domain-security-002 | token-scopes-unwraps-envelope | Fetching the scope catalogue against a stub returning `{ prefixes: ["/content/markdown"] }` | Resolves to `["/content/markdown"]`, not the envelope — no dedicated test; derived directly from source |
| hub-domain-security-003 | token-mint-request-shape | Minting a token with `{ name: "ci", scope: ["/content/markdown:read"] }` | `POST /api/auth/tokens` with that object JSON-serialized verbatim; resolves to the created-token response — no dedicated test; derived directly from source |
| hub-domain-security-004 | token-created-secret-returned-once | Response body `{ id: "t1", name: "ci", prefix: "abcd", createdAt: "...", expiresAt: null, lastUsedAt: null, token: "secret-raw-value" }` from minting | The resolved response's `token` field equals `"secret-raw-value"`, unmodified — no dedicated test; derived directly from the wire shape and the pass-through return |
| hub-domain-security-005 | token-revoke-request-shape | Revoking token id `"tok 1"` | `DELETE /api/auth/tokens/tok%201` (percent-encoded); resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-security-006 | access-list-all-groups-cross-bucket | Listing all groups against a stub returning `{ accessGroups: [{ id: "g1", bucketId: "b1", ... }] }` | Resolves to `[{ id: "g1", bucketId: "b1", ... }]`, unwrapped — no dedicated test; derived directly from source |
| hub-domain-security-007 | access-group-detail-request-shape | Fetching group `"g1"`'s detail | `GET /api/bucket/access-groups/g1`; resolves to the group detail verbatim, including `members`/`grants` — no dedicated test; derived directly from source |
| hub-domain-security-008 | access-group-create-scoped-to-bucket | Creating a group in bucket `"b1"` with name `"  Editors  "` | `POST /api/bucket/buckets/b1/access-groups` with body `{ name: "Editors" }` (no `description` key) — no dedicated test; derived directly from source |
| hub-domain-security-009 | access-group-create-conflict-friendly | Creating a group named `"Editors"` in bucket `"b1"` against a stub whose error message is `"Access group with that name already exists"` | Rejects with a plain error whose message is exactly `An access list named "Editors" already exists.` — no dedicated test; derived directly from the conflict-translation pattern and the create action's own catch |
| hub-domain-security-010 | access-group-update-request-shape | Updating group `"g1"` with `{ description: "new" }` | `PATCH /api/bucket/access-groups/g1` with body `{ description: "new" }` only (`name` omitted since it wasn't supplied) — no dedicated test; derived directly from source |
| hub-domain-security-011 | access-group-update-conflict-friendly | Updating group `"g1"` with `{}` against a stub error message matching the "already exists" pattern | Rejects with message `An access list named "" already exists.` (no name was supplied, so the trimmed value is `""`) — no dedicated test; derived directly from source |
| hub-domain-security-012 | access-group-delete-request-shape | Deleting group `"everyone-group-id"` against a stub returning HTTP `409` with body `{ error: "cannot delete the everyone group" }` | Rejects with an error carrying `status: 409` and that exact backend message, unmodified — no dedicated test; derived directly from the absence of error translation on this path |
| hub-domain-security-013 | access-member-add-request-shape | Adding member `{ memberType: "persona", memberId: "p1" }` to group `"g1"` | `POST /api/bucket/access-groups/g1/members` with body `{ memberType: "persona", memberId: "p1" }` — no dedicated test; derived directly from source |
| hub-domain-security-014 | access-member-add-conflict-friendly | Adding member `{ memberType: "user", memberId: "u1" }` against a stub error message matching the "already exists" pattern | Rejects with message exactly `That member is already in this access list.` — no dedicated test; derived directly from source |
| hub-domain-security-015 | access-member-remove-request-shape | Removing member row `"row-42"` from group `"g1"` | `DELETE /api/bucket/access-groups/g1/members/row-42`; resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-security-016 | access-grant-upsert-request-shape | Upserting grant `{ targetType: "bucket_type", targetId: "bt1", crud: "C,R" }` for group `"g1"` | `PUT /api/bucket/access-groups/g1/grants` with body `{ targetType: "bucket_type", targetId: "bt1", crud: "C,R" }`; resolves to the parsed grant — no dedicated test; derived directly from source |
| hub-domain-security-017 | access-grant-upsert-request-shape | Same call against a stub returning HTTP `404` (e.g. `targetId` does not exist) | Rejects with an error carrying `status: 404`, propagated unchanged — no dedicated test; derived directly from the absence of error translation on this path |
| hub-domain-security-018 | access-grant-delete-request-shape | Deleting grant `"grant-1"` from group `"g1"` | `DELETE /api/bucket/access-groups/g1/grants/grant-1`; resolves to `undefined` — no dedicated test; derived directly from source |
| hub-domain-security-019 | access-crud-string-passthrough | Upserting grant `{ targetType: "row", targetId: "r1", crud: "" }` for group `"g1"` | The request body's `crud` is the empty string, sent unchanged — no dedicated test; derived directly from source |
| hub-domain-security-020 | every-bucket-access-call-url-encodes-identifiers | Fetching group detail for id `"a b/c"` | The request URL contains the percent-encoded form of `"a b/c"` in place of the raw id — no dedicated test; derived directly from the shared percent-encoding helper's definition |
| hub-domain-security-021 | token-revoke-request-shape | Revoking token `"a/b"` compared against deleting group `"a/b"` | Both requests carry the identical percent-encoded segment `a%2Fb`, even though the two call sites reach percent-encoding through different code paths (see Design Decisions) — the two are behaviorally identical despite that naming divergence |
| hub-domain-security-022 | session-refresh-waterfall | Any call's first response is `401`; the token refresh call resolves a new token | The request is retried once with the new token; a `401` on that retry throws an error carrying `status: 401` — traced to the shared request helper, exercised only indirectly through either client |
| hub-domain-security-023 | errors-carry-status-and-code | Backend responds `403` to a grant upsert with body `{ error: { message: "forbidden", code: "no_manage_verb" } }` | The thrown error has `status: 403` and `code: "no_manage_verb"` — traced to the shared error-extraction helpers |
| hub-domain-security-024 | no-client-side-cache | Two sequential calls to list tokens | Two distinct HTTP requests are issued; the second call's result is never served from a value cached by the first — no dedicated test; derived directly from the absence of any cache/memoization in the source |

## Edge Cases

- **Null and empty input — group name (create/update)**: trimming an empty or all-whitespace group
  name produces `""`, which is sent to the backend unchanged; neither creating nor updating a group
  rejects it client-side.
- **Null and empty input — add-member/upsert-grant identifiers**: `memberId`, `targetId`, and `crud:
  ""` are all accepted as empty strings and sent verbatim; only `crud: ""` has documented meaning
  ("none"), per `access-crud-string-passthrough`.
- **Null and empty input — path-segment identifiers**: percent-encoding an empty group id, member-row
  id, grant id, bucket id, or token id produces an empty URL segment (e.g. `.../members/`); the
  resulting malformed request is still sent, with no client-side guard against it.
- **Boundary values — mint scope/expiry**: minting accepts any string array for `scope` and any string
  (or `null`) for `expiresAt` with no length, format, or range check; a caller-supplied malformed date
  string or an unbounded `scope` array is sent to the backend as-is.
- **Boundary values — `crud` grant string**: no minimum or maximum length, no de-duplication of
  repeated letters, and no validation that only `C`/`R`/`U`/`D` characters appear; upserting a grant
  sends whatever string the caller provides.
- **Concurrent access — module state**: neither client holds shared mutable state between calls
  (`stateless-module`), so there is nothing for two concurrent calls to race on within this component.
- **Concurrent access — competing name/member conflicts**: two concurrent group-create calls with the
  same trimmed name in the same bucket, or two concurrent add-member calls with the same member id, are
  resolved by the backend's uniqueness constraint; the loser's request receives the conflict that
  `access-group-create-conflict-friendly`/`access-member-add-conflict-friendly` translate to a friendly
  message — there is no client-side pre-check, only this post-hoc translation.
- **Concurrent access — competing grant/group writes**: two concurrent grant-upsert calls for the same
  group/target, or a group-delete racing a group-update for the same group, follow ordinary HTTP
  semantics — last response received wins, with no client-side sequencing, version check, or optimistic
  lock anywhere in either client.
- **Error states — validation failure vs. HTTP failure**: every error either client can throw carries
  an HTTP status and code (via the shared request helper) or, for the three conflict-translation sites,
  a plain error carrying only a friendly message and no status; a shared status-detection helper
  distinguishes the two by duck-typing the `.status` property.
- **Error states — dependency unavailable**: neither client catches a network-level rejection anywhere
  outside the `401` waterfall the shared request helper already provides; a DNS failure, connection
  refusal, or TLS error propagates as an unhandled promise rejection out of whichever operation was
  called.
- **Offline or disconnected state**: none of the twelve operations detects or reacts to a loss of
  connectivity mid-call; a connection dropped after the request was sent but before a response arrived
  surfaces only as the underlying network-level rejection described above.
- **No timeout**: no operation in either client sets a deadline or abort signal; a reachable-but-
  unresponsive backend leaves the call pending until the underlying transport's own limit, if any.
- **No cancellation**: no operation accepts a cancellation signal, so a caller cannot cancel an
  in-flight request through either client.
- **No retry beyond the 401 waterfall**: every call issues exactly one request (plus, on a `401`, the
  single inherited refresh-and-retry); nothing in either client retries a network failure or a non-401
  error status.
- **token-mint-retry-duplication**: minting sends a plain request with no idempotency key,
  client-generated request id, or de-duplication; a caller that retries minting after an ambiguous
  failure (a timeout or dropped connection after the first request reached the backend) sends a second
  request, which can mint a second, independently-secreted token. Unlike group-create/add-member, whose
  retries collide on a uniqueness constraint and surface a conflict, nothing in this component gives a
  retried mint an equivalent signal; any de-duplication belongs to the backend's mint route.
- **token-member-revocation-orphan**: the member-type vocabulary allows an API token to be a bucket
  access-group member (`memberType: "token"`), but the two clients never coordinate: revoking a token
  sends only the revoke request and touches no access-group-member row. Whether rows naming the revoked
  token are removed is decided by the backend's revocation handler, not by either client.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Tokens base path | fixed string constant, `"/api/auth/tokens"` | fixed | Not injectable; every token request path is built from this base. |
| Groups base path | fixed string constant, `"/api/bucket/access-groups"` | fixed | Not injectable; the base path for group/member/grant operations by group id. |
| Buckets base path | fixed string constant, `"/api/bucket/buckets"` | fixed | Not injectable; used only by group-create's `{bucketsBase}/{bucketId}/access-groups` path. |
| Mint body | `{ name, expiresAt?, scope? }` | none — required | Sent verbatim as the request body; `expiresAt`/`scope` are omitted from the wire body entirely when left absent. |
| Token id (revoke) | string (caller parameter) | none — required | The token's id; percent-encoded before being placed in the URL. |
| Bucket id (group-create) | string (caller parameter) | none — required | The owning bucket; percent-encoded. |
| Group id (most bucket access-list operations) | string (caller parameter) | none — required | The access group's id; percent-encoded. |
| Group-create input | `{ name: string; description?: string }` | none — required | `name` is trimmed before send; `description` is sent only when truthy. |
| Group-update patch | `{ name?: string; description?: string }` | none — required | Each key is sent only when the caller supplies it (checked for presence, not truthiness). |
| Add-member input | `{ memberType; memberId: string }` | none — required | Sent verbatim as the request body. |
| Member-row id (remove-member) | string (caller parameter) | none — required | The membership row's own id, not the principal's id. |
| Upsert-grant input | `{ targetType; targetId: string; crud: string }` | none — required | Sent verbatim as the request body; `crud` is not validated client-side. |
| Grant id (delete-grant) | string (caller parameter) | none — required | The grant's id; percent-encoded. |

## Deep Linking

Not applicable: this component registers no URL scheme, route, or navigation target of its own; it is
a data client consumed by a separate presentation layer that owns any deep-linking concern.

## Localization

The bucket access lists client is the one place in this domain that authors its own English strings,
rather than relaying one from the backend:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `An access list named "<name>" already exists.` | Thrown when creating a group hits a name conflict, via the shared conflict-translation helper |
| — | `An access list named "<name>" already exists.` | Thrown when updating a group hits a name conflict, via the shared conflict-translation helper |
| — | `That member is already in this access list.` | Thrown when adding a member hits a uniqueness conflict, via the shared conflict-translation helper |

There is no localization mechanism in this domain (no catalog, no key, no localization-lookup call) —
the three strings above are hardcoded literals, stated as fact per the non-UI component guidance rather
than as a gap. Every other error message a caller can observe from either client originates in the
backend's response body and is extracted by a shared error-message helper, not authored in this
component.

## Accessibility Options

Not applicable: this component renders no UI and responds to none of reduced motion, increased
contrast, or color differentiation.

## Feature Flags

Not applicable: the source contains no feature-flag key, gate, or conditional check of any kind.

## Analytics

Not applicable: the source contains no analytics or event-emission call.

## Privacy

- **Data collected**: the personal API tokens client originates and returns personal API token
  records — `id`, `name`, `prefix` ("non-secret leading chars, for display"), `createdAt`,
  `expiresAt`, `lastUsedAt`, `scope` — and, on minting only, the raw secret `token` value, documented as
  "shown exactly once." The bucket access lists client reads and writes access-group, member, and grant
  records identifying which principals (`user`/`organization`/`persona`/`app`/`token`) hold which CRUD
  grants at which targets. The token secret is credential material; the access-group records are
  access-control records, not end-user PII.
- **Storage**: none within this component. Both clients are stateless per-call request builders (per
  `stateless-module`); neither holds the minted secret, a session token, or any access-control record
  in memory or on disk beyond the lifetime of a single call.
- **Transmission**: yes. Every call carries a bearer session credential attached by the shared
  authenticated-request helper (`auth-delegated-to-shared-client`), not by these clients; minting
  additionally receives a freshly issued raw secret token in its response body. Whatever transport
  security the deployment provides is outside the scope of this component.
- **Retention**: none within this component. Whatever the backend retains — token metadata rows,
  access group/member/grant rows — is outside the scope of these clients.

## Logging

Not applicable: no logging or other diagnostic call of any kind appears in this component.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/security/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
