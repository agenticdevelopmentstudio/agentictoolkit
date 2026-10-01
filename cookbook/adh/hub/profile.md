---
id: 70f5dcb1-9d00-445b-a691-0dc1e7dd7a67
title: Profile
domain: agentictoolkit://cookbook/adh/hub/profile
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A data client for a principal''s profile domain: owner-scoped social links
  and addresses, its privacy audience grants, and its metered usage summary.'
platforms:
- typescript
- web
tags:
- profile
- privacy
- usage
- workspace
- crud
- api
depends-on: []
related: []
references:
- packages/web/packages/data/src/profile/profile.ts (agentictoolkit)
- packages/web/packages/data/src/profile/usage.ts (agentictoolkit)
- packages/web/packages/data/src/profile/wire.ts (agentictoolkit)
- packages/web/packages/data/src/profile/index.ts (agentictoolkit)
- packages/web/packages/data/src/profile/__tests__/profile.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
- packages/web/packages/adh-api-types/src/data-profile-wire.test-d.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Profile

## Overview

This is the public surface of a principal's profile domain: social links and addresses
(owner-polymorphic rows a personal account or an organization can each hold), the per-row privacy
grant that decides who may see them, and the caller's metered usage summary. It is described in
its given implementation's source as "one entry for four endpoints because they answer about one
subject and are read together." A companion wire module holds the wire shapes (social link,
address, privacy grant, usage row/limits) and is measured against the backend's generated types by
a dedicated type-conformance check. It is a headless **logic** module — no visual surface — so
this recipe marks Appearance, States, and Accessibility not applicable and carries the runtime
contract entirely in Behavioral Requirements, per the non-UI component guidance this recipe was
authored under.

## Behavioral Requirements

**Social links**

- **social-links-list-request-shape**: the social-links list operation MUST send
  `GET /api/content/social-links`, appending `?workspace=<enc(workspace)>` only when a workspace
  option is given, and MUST return the parsed body as a list of social-link records with no
  transformation.
- **social-links-create-request-shape**: the social-links create operation MUST send
  `POST /api/content/social-links` (with the same optional `?workspace=` suffix) and a body that
  is the supplied create input JSON-serialized verbatim, and MUST return the parsed social-link
  record.
- **social-links-update-request-shape**: the social-links update operation MUST send
  `PUT /api/content/social-links/<enc(id)>` (with the same optional `?workspace=` suffix) and a
  body that is the supplied input JSON-serialized verbatim, and MUST return the parsed
  social-link record.
- **social-links-delete-request-shape**: the social-links delete operation MUST send
  `DELETE /api/content/social-links/<enc(id)>` (with the same optional `?workspace=` suffix) via
  the shared authenticated request client's no-body-parsing call, not its JSON-parsing call, and
  MUST resolve with no value, discarding whatever body the response carries.

**Addresses**

- **addresses-list-request-shape**: the addresses list operation MUST send
  `GET /api/content/addresses`, with the same optional `?workspace=` suffix as the social-links
  list operation, and MUST return the parsed body as a list of address records with no
  transformation.
- **addresses-create-request-shape**: the addresses create operation MUST send
  `POST /api/content/addresses` (with the optional `?workspace=` suffix) and a body that is the
  supplied create input JSON-serialized verbatim, and MUST return the parsed address record.
- **addresses-update-request-shape**: the addresses update operation MUST send
  `PUT /api/content/addresses/<enc(id)>` (with the optional `?workspace=` suffix) and a body that
  is the supplied input JSON-serialized verbatim, and MUST return the parsed address record.
- **addresses-delete-request-shape**: the addresses delete operation MUST send
  `DELETE /api/content/addresses/<enc(id)>` (with the optional `?workspace=` suffix) via the
  shared authenticated request client's no-body-parsing call, not its JSON-parsing call, and MUST
  resolve with no value.

**Workspace scoping**

- **workspace-query-omitted-when-absent**: the shared workspace-query builder MUST return the
  empty string when no workspace option is given or it is falsy, producing a request URL
  byte-identical to the personal (no-workspace) path.
- **workspace-query-percent-encoded**: the shared workspace-query builder MUST return
  `?workspace=<percent-encoded workspace slug>` when a workspace option is given,
  percent-encoding the slug.

**Cache keys**

- **list-key-namespaced-by-owner**: the social-links, addresses, and usage-summary cache-key
  builders MUST each return a key ending `..., "org", <workspaceSlug>` when a workspace slug is
  given and `..., "self"` otherwise, differing at the same array segment so neither branch is a
  prefix of the other.
- **list-key-roots-not-exported**: the un-namespaced root keys behind the social-links,
  addresses, and usage-summary cache-key builders MUST NOT be exported; only their namespaced
  accessor functions are part of the module's public surface.
- **privacy-key-not-namespaced**: the privacy cache key MUST be exported directly as the fixed
  constant `["account", "privacy"]`, unlike the other three root keys, because privacy grants are
  not owner-scoped by workspace (see `privacy-grants-caller-scoped-only`).

**Privacy grants**

- **privacy-grants-list-unwraps-envelope**: the privacy-grants list operation MUST send
  `GET /api/account/privacy` and MUST return the bare `items` array unwrapped from the
  `{ items }` response envelope.
- **privacy-grants-caller-scoped-only**: the privacy-grants list and set operations MUST NOT
  accept or forward a `workspace` parameter; both operate only on the calling principal's own
  privacy grants.
- **privacy-grant-set-request-shape**: the privacy-grant set operation MUST send
  `PUT /api/account/privacy` with body `{ targetTable, targetId, audienceMask }`, where
  `audienceMask` is looked up from the requested privacy level via the fixed map
  `{"only-me": 0, public: 1, hub: 2}`, and MUST return the parsed privacy-grant record.
- **privacy-level-resolution-default**: resolving a privacy level MUST return `"only-me"` when no
  grant in the supplied array matches the given `(targetTable, targetId)` pair.
- **privacy-level-resolution-match**: resolving a privacy level MUST use the first grant in array
  order whose `targetTable` and `targetId` both match, ignoring any subsequent duplicate entries.
- **privacy-level-resolution-public-precedence**: resolving a privacy level MUST return
  `"public"` whenever the matched grant's `audienceMask` has bit 0 set (`audienceMask & 1`),
  regardless of whether bit 1 is also set.
- **privacy-level-resolution-hub**: resolving a privacy level MUST return `"hub"` when the matched
  grant's `audienceMask` has bit 1 set (`audienceMask & 2`) and bit 0 is not set.
- **privacy-level-resolution-unmatched-bits**: resolving a privacy level MUST return `"only-me"`
  when a grant matches but its `audienceMask` has neither bit 0 nor bit 1 set.

**Usage**

- **usage-summary-request-shape**: the usage-summary operation MUST send
  `GET /api/usage/summary`, appending `?workspace=<enc(workspace)>` only when a workspace option
  is given, and MUST return the bare `rows` array unwrapped from the `{ rows }` response envelope.
- **usage-summary-subject-list-server-derived**: the usage-summary operation MUST NOT send any
  parameter naming which principals' usage to return beyond `workspace` itself; the subject list
  is derived entirely on the backend.

**Wire shapes**

- **owner-scoped-row-shape**: a social-link record and an address record MUST both carry every
  field of the shared owner-scoped-row shape (`id`, `customerId`, `deletedAt`, `ecosystemId`,
  `ownerKind`, `ownerId`, `createdAt`, `updatedAt`, `syncVersion`, `syncStampedAt`, `syncTxid`) in
  addition to their own fields.
- **write-shapes-exclude-server-managed-fields**: a social-link create/update input and an
  address create/update input MUST include only the caller-writable fields
  (`platform`/`url`/`handle`/`sortOrder?` for the social-link input;
  `label`/`line1`/`line2`/`city`/`region`/`postalCode`/`country` for the address input) and MUST
  NOT include `id`, `customerId`, `ownerKind`, `ownerId`, the timestamps, or the sync fields,
  which the server manages.
- **social-link-sort-order-is-render-order**: a social-link record's `sortOrder` field MUST be the
  field the list route sorts by for the order the public user card renders these in; this module
  performs no client-side sort of its own.
- **privacy-target-table-widened**: a privacy target-table value MUST be a plain string, not a
  closed set of known target tables, so this client cannot refuse a target table the backend
  later adds.
- **usage-limits-enforced-flag**: a usage-limits record's `enforced` flag MUST reflect the global
  kill switch already ANDed into the per-key enforcement decision; when `false`, the quota fields
  are recorded against but never refused (observe-then-enforce).
- **usage-row-kind-application-admin-only**: a usage row with `kind: "application"` MUST only
  appear in the platform-admin ecosystem view — an application belongs to its ecosystem and to no
  workspace, so neither the personal nor the workspace-scoped view can produce one.

**Cross-cutting**

- **every-write-call-serializes-verbatim**: the social-links create/update, addresses
  create/update, and privacy-grant set operations MUST JSON-serialize their body argument with no
  field renaming, omission, or added field beyond what that argument already carries.
- **module-holds-no-mutable-state**: this domain's operations MUST NOT cache, memoize, or retain
  any response across calls; every network operation issues exactly one HTTP request per call,
  and privacy-level resolution, workspace-query building, and the cache-key builders perform a
  pure computation with no I/O.
- **no-runtime-response-validation**: the social-links list, addresses list, privacy-grants list,
  and usage-summary operations MUST return whatever the shared authenticated request client's
  typed result produces, applying no runtime shape check of their own to the response body —
  unlike this cookbook's sibling Access recipe's list-features operation.

### Security

This module carries address rows (physical mailing addresses), the privacy audience settings that
decide who may see a principal's social links and addresses, and metered usage/cost figures (a
usage row's `costMicros` field) — all principal-identifying or financially sensitive data — but it
authenticates and authorizes none of it itself.

- **auth-delegated-to-shared-client**: every network call in this domain MUST go through the
  shared authenticated request client's JSON-parsing or no-body-parsing call (backed by the
  platform's shared auth client), which attaches the bearer credential; this module MUST NOT
  read, store, or attach a token itself.
- **no-client-side-storage-of-sensitive-fields**: this domain MUST NOT persist any address,
  social link, privacy grant, or usage row to any client-side store; every value is held only for
  the duration of the call that produced it.
- **audience-visibility-enforced-server-side**: the privacy-grant set operation MUST NOT perform
  any client-side check of who may currently see a target's content before or after the write;
  this module's role is limited to translating a privacy level to an audience bitmask and sending
  it — enforcement of who is shown what based on the resulting mask happens entirely outside this
  domain.
- **violation-handling-inherited**: a non-2xx response to any call in this domain MUST propagate
  as whatever error the shared authenticated request client throws; this module defines no
  security-violation handling of its own.

## Appearance

Not applicable — this is a data client for a principal's profile domain, not a visual component.

## States

Not applicable — this is a data client for a principal's profile domain, not a visual component.

## Accessibility

Not applicable — this is a data client for a principal's profile domain, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-profile-001 | social-links-list-request-shape | The social-links list operation, called with no options | Request URL is `/api/content/social-links` with no query — `profile.test.ts` › "lists personal social links with no query when no workspace" |
| hub-domain-profile-002 | social-links-list-request-shape, workspace-query-percent-encoded | The social-links list operation, called with `{ workspace: "acme" }` | Request URL is `/api/content/social-links?workspace=acme` — `profile.test.ts` › "lists org social links with ?workspace= when a slug is given" |
| hub-domain-profile-003 | addresses-list-request-shape, workspace-query-percent-encoded | The addresses list operation, called with `{ workspace: "a/b" }` | Request URL is `/api/content/addresses?workspace=a%2Fb` — `profile.test.ts` › "encodes the workspace slug" |
| hub-domain-profile-004 | workspace-query-omitted-when-absent | The addresses list operation, called with no options | Request URL is `/api/content/addresses` with no `?workspace=` segment — derived directly from the workspace-query-building branch; no dedicated test beyond vector 001's equivalent on social links |
| hub-domain-profile-005 | social-links-create-request-shape, every-write-call-serializes-verbatim | The social-links create operation, called with `{ platform: "github", url: "https://x", handle: "" }` and `{ workspace: "acme" }` | `POST /api/content/social-links?workspace=acme` with body `{"platform":"github","url":"https://x","handle":""}` JSON-serialized verbatim; resolves to the parsed social-link record — `profile.test.ts` › "posts a create with the workspace query" |
| hub-domain-profile-006 | social-links-update-request-shape | The social-links update operation, called with id `"id1"`, `{ platform: "github", url: "https://x", handle: "" }`, and `{ workspace: "acme" }` | `PUT /api/content/social-links/id1?workspace=acme` with that body verbatim — `profile.test.ts` › "puts an update with id + workspace query" |
| hub-domain-profile-007 | social-links-delete-request-shape | The social-links delete operation, called with id `"id1"` and `{ workspace: "acme" }` | Sends `DELETE /api/content/social-links/id1?workspace=acme` via the no-body-parsing call; resolves with no value — `profile.test.ts` › "deletes with id + workspace query via authedRequest" |
| hub-domain-profile-008 | addresses-create-request-shape | The addresses create operation, called with `{ label: "Home", line1: "1 Main St", line2: "", city: "Springfield", region: "IL", postalCode: "62701", country: "US" }` and `{ workspace: "acme" }` | `POST /api/content/addresses?workspace=acme` with that body verbatim — no dedicated test; derived directly from source, mirroring vector 005 |
| hub-domain-profile-009 | addresses-update-request-shape | The addresses update operation, called with id `"addr1"`, the same address input, and `{ workspace: "acme" }` | `PUT /api/content/addresses/addr1?workspace=acme` with that body verbatim — no dedicated test; mirrors vector 006 |
| hub-domain-profile-010 | addresses-delete-request-shape | The addresses delete operation, called with id `"addr1"` and `{ workspace: "acme" }` | Sends `DELETE /api/content/addresses/addr1?workspace=acme` via the no-body-parsing call; resolves with no value — no dedicated test; mirrors vector 007 |
| hub-domain-profile-011 | list-key-namespaced-by-owner | The social-links cache-key builder, called with no workspace and separately with `"acme"` | Resolve to `["profile","social-links","self"]` and `["profile","social-links","org","acme"]` respectively — neither array is a prefix of the other — no dedicated test; derived directly from source |
| hub-domain-profile-012 | list-key-namespaced-by-owner | The usage-summary cache-key builder, called with `"acme"` | Resolves to `["usage","summary","org","acme"]` — no dedicated test; same contract as vector 011 |
| hub-domain-profile-013 | list-key-roots-not-exported, privacy-key-not-namespaced | Inspect the module's exported bindings | The un-namespaced root keys behind the social-links, addresses, and usage-summary cache-key builders are absent from the export list; the privacy cache key is present and equals `["account","privacy"]` — confirmed by reading the `export` statements, no test needed |
| hub-domain-profile-014 | privacy-grants-list-unwraps-envelope | The privacy-grants list operation, against a stub response `{ items: [{ targetTable: "addresses", targetId: "a1", audienceMask: 1 }] }` | Resolves to the bare array `[{ targetTable: "addresses", targetId: "a1", audienceMask: 1 }]` — no dedicated test; derived directly from source |
| hub-domain-profile-015 | privacy-grants-caller-scoped-only | Inspect the privacy-grants list and set operations' signatures | Neither accepts a `workspace` parameter — confirmed by the function signatures, no test needed |
| hub-domain-profile-016 | privacy-grant-set-request-shape | The privacy-grant set operation, called with `"addresses"`, `"a1"`, and `"public"` | `PUT /api/account/privacy` with body `{ targetTable: "addresses", targetId: "a1", audienceMask: 1 }` — no dedicated test; derived from the fixed audience-mask map |
| hub-domain-profile-017 | privacy-level-resolution-default | Resolving a privacy level given an empty grant list, `"addresses"`, `"a1"` | Returns `"only-me"` — no dedicated test; derived directly from source |
| hub-domain-profile-018 | privacy-level-resolution-match | Resolving a privacy level given two grants for the same target, the first with `audienceMask: 2` and the second with `audienceMask: 1` | Returns `"hub"` (the first match), not `"public"` — no dedicated test; derived from first-match array-lookup semantics |
| hub-domain-profile-019 | privacy-level-resolution-public-precedence | Resolving a privacy level given one grant with `audienceMask: 3` | Returns `"public"` — both bits set, public wins per the function's own doc comment — no dedicated test; derived directly from source |
| hub-domain-profile-020 | privacy-level-resolution-hub | Resolving a privacy level given one grant with `audienceMask: 2` | Returns `"hub"` — no dedicated test; derived directly from source |
| hub-domain-profile-021 | privacy-level-resolution-unmatched-bits | Resolving a privacy level given one grant with `audienceMask: 4` | Returns `"only-me"` — a matched grant whose mask sets neither bit 0 nor bit 1 falls through both checks — no dedicated test; derived directly from source |
| hub-domain-profile-022 | usage-summary-request-shape | The usage-summary operation, called with `{ workspace: "acme" }`, against a stub response `{ rows: [] }` | `GET /api/usage/summary?workspace=acme`; resolves to `[]` — no dedicated test; derived directly from source |
| hub-domain-profile-023 | usage-summary-request-shape, workspace-query-omitted-when-absent | The usage-summary operation, called with no options | `GET /api/usage/summary` with no `?workspace=` segment — no dedicated test; mirrors vector 004 |
| hub-domain-profile-024 | usage-summary-subject-list-server-derived | Inspect the usage-summary operation's parameter type | The only accepted option is an optional workspace slug; no per-principal filter can be requested by the caller — confirmed by the function signature, no test needed |
| hub-domain-profile-025 | owner-scoped-row-shape, write-shapes-exclude-server-managed-fields | A social-link record value missing the `syncTxid` field; a social-link create/update input that also sets `id` | Both are rejected as ill-shaped by the type system — confirmed by the interface declarations; a companion wire-conformance test pins the `id`-on-write-input case directly with a type-level expectation of failure |
| hub-domain-profile-026 | social-link-sort-order-is-render-order | Read a social-link record's `sortOrder` field's doc comment | States it is "the order the PUBLIC user card renders these in" and that the list route sorts by it — confirmed directly from the source comment |
| hub-domain-profile-027 | privacy-target-table-widened | Passing a target-table value the client has never declared (e.g. a table the backend adds after this client was written) | Accepted without client-side rejection — the target-table type is unconstrained by design, pinned as a permanent equality against the backend's generated type by a companion wire-conformance test |
| hub-domain-profile-028 | usage-limits-enforced-flag | Read a usage-limits record's `enforced` field's doc comment | States "When false the limits are RECORDED against but never refused (observe-then-enforce)" — confirmed directly from the source comment |
| hub-domain-profile-029 | usage-row-kind-application-admin-only | Read the usage-row kind field's doc comment | States `application` rows are platform-admin-only, since an application belongs to no workspace — confirmed directly from the source comment |
| hub-domain-profile-030 | module-holds-no-mutable-state, no-runtime-response-validation | Read every operation this domain exports | None declares or closes over a mutable module-level variable beyond the fixed constants; the social-links list, addresses list, privacy-grants list, and usage-summary operations each return the shared request client's result directly with no shape check — confirmed by reading the function bodies, no test needed |
| hub-domain-profile-031 | auth-delegated-to-shared-client | Inspect the module's imports | The shared authenticated request client's two calls are imported from the domain's shared HTTP helper; no other network primitive appears anywhere in this domain's source — confirmed by reading the `import` statements, no test needed |
| hub-domain-profile-032 | violation-handling-inherited | Any call in this domain whose backend response is a non-2xx status | The call rejects with whatever error the shared authenticated request client throws, with no local error-interception logic in this domain — confirmed by reading the function bodies, no test needed |
| hub-domain-profile-033 | audience-visibility-enforced-server-side | Read the privacy-grant set operation's implementation | Contains no conditional branching on caller identity or current audience before sending the write — confirmed by reading the function body, no test needed |
| hub-domain-profile-034 | no-client-side-storage-of-sensitive-fields | Search this domain's source for any client-side storage call | Zero matches across this domain's source — confirmed by direct search, no test needed |

## Edge Cases

- **Null and empty input — the workspace option**: MUST take the same no-query branch whether the
  options are entirely omitted or the workspace option is the empty string `""`, since an empty
  string is falsy and the workspace-query builder's check is a plain truthiness test.
- **Null and empty input — a social-link input's `handle`/`sortOrder`**: `handle` MUST be sent as
  the empty string unchanged when the caller supplies one (per the client's own test fixture,
  `handle: ""`); `sortOrder` MUST be omitted from the serialized body entirely when the caller does
  not supply it, since serializing to JSON drops an absent key.
- **Null and empty input — resolving an empty grant list**: MUST return `"only-me"`, per
  `privacy-level-resolution-default`.
- **Boundary values — `audienceMask` bit combinations**: resolving a privacy level MUST test only
  bits 0 and 1; a mask with only higher bits set (e.g. `4`) MUST fall through to `"only-me"`, and a
  mask with bit 0 set together with any higher bits (e.g. `5`) MUST still resolve to `"public"`,
  since the bit-0 check runs first and unconditionally.
- **Concurrent access**: this domain holds no shared mutable state beyond its fixed constants
  (`module-holds-no-mutable-state`), so two calls made together cannot race on anything inside this
  domain itself. Two concurrent privacy-grant-set or social-link/address-create calls for the same
  target SHOULD be expected by a caller to follow ordinary HTTP write semantics with no
  client-side sequencing — the last response the caller applies wins; no ordering guarantee is
  implemented anywhere in this domain, so this is a fact about caller responsibility, not a
  behavior this module enforces.
- **Error states — dependency failure**: this domain catches no rejection from the shared
  authenticated request client; a non-2xx backend response, a network failure, or a malformed
  response body all MUST propagate unmodified to the caller, per `violation-handling-inherited`.
- **Offline or disconnected state**: no call in this domain guards against a network-level
  rejection; a connectivity loss mid-call MUST propagate as an unhandled rejection out of every
  exported operation, with no retry, queuing, or offline-specific handling.
- **No timeout**: no call sets a deadline or cancellation signal; a reachable-but-unresponsive
  backend MUST leave the call pending indefinitely as far as this domain is concerned.
- **No cancellation**: no exported operation accepts a cancellation signal, so a caller MUST NOT
  be able to cancel an in-flight request through this domain.
- **No retry beyond the inherited 401 waterfall**: every call issues exactly one request (plus,
  on a `401`, whatever single refresh-and-retry the shared authenticated request client itself
  performs, outside this domain); nothing in this domain MUST retry a network failure or a
  non-401 error status.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| The workspace option (every list/create/update/delete/usage operation) | optional string | omitted → the caller's own principal | Workspace slug scoping the call to an organization's profile instead of the caller's own; percent-encoded when present. |
| The create/update input (social links) | an object | none — required | `{ platform, url, handle, sortOrder? }`, sent verbatim as the request body. |
| The create/update input (addresses) | an object | none — required | `{ label, line1, line2, city, region, postalCode, country }`, sent verbatim as the request body. |
| Target table / target id / level (privacy-grant set) | string, string, a privacy-level value | none — required | The level is mapped through the fixed audience-mask map to an integer bitmask before sending. |
| Grants (privacy-level resolution) | a list of privacy-grant records | none — required, caller supplies the already-loaded list | Pure lookup; issues no network call of its own. |
| The fixed audience-mask map | a module constant | fixed `{"only-me": 0, public: 1, hub: 2}` | Not injectable or configurable. |
| The four cache-key roots | module constants | fixed | Not injectable; the privacy cache key alone is exported directly, per `privacy-key-not-namespaced`. |

## Deep Linking

Not applicable: this domain registers no URL scheme, route, or navigation target of its own; it is
a data client consumed by a separate presentation layer that owns any deep-linking concern.

## Localization

Not applicable: no part of this domain authors a user-facing string of any kind — every thrown
error originates from the shared authenticated request client (owned by the shared auth client),
and every value these operations return either passes a backend response through unchanged or is
a non-string type. This differs from this cookbook's sibling Access recipe, whose list-features
operation does author one hardcoded English validation message; this component has no equivalent
code path.

## Accessibility Options

Not applicable: this domain renders no UI and responds to none of Reduce Motion, Increase
Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the source contains no feature-flag or gating check of any kind in this domain.

## Analytics

Not applicable: the source contains no analytics or event-emission call in this domain.

## Privacy

- **Data collected**: address rows (`label`, `line1`, `line2`, `city`, `region`, `postalCode`,
  `country`), social link rows (`platform`, `url`, `handle`), the caller's own privacy audience
  setting per target row (`targetTable`/`targetId`/`audienceMask`), and metered usage/cost figures
  (`requests`/`bytes`/`tokens`/`costMicros`) for the caller's own principals or, with `?workspace=`,
  a workspace's. The privacy-grant record is itself the mechanism that decides who else may see
  the address and social-link rows above.
- **Storage**: none client-side — per `module-holds-no-mutable-state` and
  `no-client-side-storage-of-sensitive-fields`, nothing in this domain is retained beyond the
  lifetime of a single call. Server-side storage is outside the scope of this domain.
- **Transmission**: yes. Every call carries a bearer credential attached by the shared auth client
  (`auth-delegated-to-shared-client`), not by this module; whatever transport security the
  deployment provides is outside the scope of this domain.
- **Retention**: none within this module; nothing this module handles is retained after the
  response it produced is returned to the caller.

## Logging

Not applicable: this domain contains no logging call of any kind.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/profile/profile.ts`,
  `usage.ts`, and `wire.ts` hold the client, re-exported as the package's public surface by
  `index.ts`; every network operation is built on `authedJson`/`authedRequest` from
  `@agentic-toolkit/auth/client` (re-exported through `./http`), and the four cache-key functions
  are plain string-array builders with no framework dependency of their own — a consumer wires them
  into whatever cache layer (e.g. react-query) it uses.
- **SwiftUI**: model `SocialLink`/`SocialLinkWrite`/`Address`/`AddressWrite`/`PrivacyGrant`/
  `UsageRow`/`UsageLimits` as `Codable, Hashable, Sendable` structs, `PrivacyLevel`/`UsageScope`/
  `UsageRowKind` as Swift `enum`s, and the client as an `actor` or `@MainActor final class` exposing
  `async throws` functions built on `URLSession`, mirroring the pattern the sibling
  `hub-domain-access` recipe's Swift port note already describes for this repo's Hub Apple targets.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS feature would
  consume the ported client through an injected data-source protocol rather than calling
  `URLSession` from the view layer, and the `opts.workspace` parameter becomes a constructor/init
  argument on that protocol rather than a per-call option.
- **Compose**: model the wire rows as Kotlin `data class`es annotated `@Serializable`, `PrivacyLevel`
  as a Kotlin `enum class`, and the client as a class exposing `suspend fun` equivalents built on
  Ktor or OkHttp; the cache-key arrays become a small `data class` or sealed key type rather than a
  plain list, since Kotlin has no equivalent to comparing array prefixes at the call site.
- **WinUI 3**: model `SocialLink`/`SocialLinkWrite`/`Address`/`AddressWrite`/`PrivacyGrant`/
  `UsageRow`/`UsageLimits` as `record`s attributed for `System.Text.Json`, `PrivacyLevel` as a C#
  `enum` with a `Dictionary<PrivacyLevel,int>` in place of `AUDIENCE_MASK`, and the client as a class
  exposing `Task<T>`-returning methods built on `HttpClient`, attaching `Authorization: Bearer
  <token>` and the same one-retry-on-401 refresh waterfall `authedFetch` performs. Back the two list
  surfaces (social links, addresses) with `ObservableCollection<T>` for a Settings-page editor, with
  each row implementing `INotifyPropertyChanged` for two-way binding in the address/social-link edit
  forms. The `socialLinksKey`/`addressesKey`/`usageSummaryKey` namespacing has no direct WinUI 3
  analog, since there is no react-query-style cache — a port would instead key any local cache
  `Dictionary` by the same `(ownerKind, ownerId)` tuple to preserve the same non-aliasing guarantee.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/profile/` |

## Design Decisions

**Decision**: `PrivacyTargetTable` is typed as a plain `string` rather than a closed union of known
target tables.
**Rationale**: `wire.ts`'s own comment states that a client that hard-coded the members would
refuse a target table the backend later adds; `data-profile-wire.test-d.ts` pins this as a
permanent, deliberate asymmetry against the generated backend type, not a placeholder meant to be
narrowed later.
**Applies to**: Web
**Approved**: pending

**Decision**: `SOCIAL_LINKS_KEY`, `ADDRESSES_KEY`, and `USAGE_SUMMARY_KEY` are not exported; only
their namespaced accessor functions are.
**Rationale**: `profile.ts`'s own comment explains that using a bare root as a cache key would alias
one owner's list onto another's under prefix-based cache invalidation. Exporting only the accessor
keeps every consumer going through the one function that produces the owner-namespaced shape,
rather than risking a second, independently-derived key that silently desyncs from it.
**Applies to**: Web
**Approved**: pending

**Decision**: none of `listSocialLinks`, `listAddresses`, `getPrivacyGrants`, or `getUsageSummary`
runtime-validates its response shape, unlike this cookbook's sibling `hub-domain-access` recipe's
`listFeatures`.
**Rationale**: recorded as observed source behavior, not smoothed over — no comment in `profile.ts`
or `usage.ts` documents an equivalent guard or a reason one was omitted. A port MUST preserve this
same trust-the-cast behavior rather than adding validation these two files don't have, since nothing
in the given sources establishes that the omission was a deliberate choice versus simply not yet
needed.
**Approved**: pending

**Decision**: `OwnerScopedRow.customerId` is documented as the denormalized creator of a row, not
its owner.
**Rationale**: `wire.ts`'s own comment warns "do not read it as 'whose row this is'" — a directly
relevant trap for a port that might otherwise assume `customerId` identifies the row's owning
principal, when the `ownerKind`/`ownerId` pair is the actual owner.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | failed | Access Patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | failed | Access Patterns |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`separation-of-concerns` passes: `profile.ts`/`usage.ts`/`wire.ts` contain zero UI or presentation
code — all three files are, per `index.ts`'s own comment, the public surface of a data domain
consumed by a separate presentation layer (the Settings > Profile editor and the public UserCard).
`unit-test-coverage` is `partial`: `profile.test.ts` exercises `listSocialLinks`, `listAddresses`
(list and encoding only), `createSocialLink`, `updateSocialLink`, and `deleteSocialLink` with six
assertions, but `createAddress`, `updateAddress`, `deleteAddress`, `getPrivacyGrants`,
`setPrivacyGrant`, `resolvePrivacyLevel`, and every export in `usage.ts` have no dedicated test
anywhere in this checkout. `explicit-error-handling` passes: nothing in these three files swallows
an error — every failure either propagates from `authedJson`/`authedRequest` unmodified or is a
compile-time-only constraint (the wire types); per `violation-handling-inherited`, no `try`/`catch`
anywhere in `profile.ts`/`usage.ts` intercepts a rejection. `secure-storage` passes: this module
persists nothing of what it handles to any client-side store, per `no-client-side-storage-of-
sensitive-fields` — there is no insecure (or secure) storage of these fields to evaluate, only their
complete absence from any store. `error-response-handling` is `failed`: no function in
`profile.ts`/`usage.ts` maps any HTTP status to a friendlier error or a documented fallback (no
`isNotFound`/`isConflict`/`rethrowConflict` call anywhere in these two files); every failure surfaces
as the generic error `authedJson`/`authedRequest` throws, with zero per-status branching. 
`pagination-support` is `failed`: `listSocialLinks`, `listAddresses`, and `getUsageSummary` all
return unpaginated collections with no limit or cursor parameter and no truncation signal to the
caller. `data-minimization` passes: every write body carries exactly the caller-writable fields
`write-shapes-exclude-server-managed-fields` names, with the server managing identity, tenancy,
ownership, and sync fields; no extra field is collected or appended by this module. `no-pii-in-logs`
passes trivially: none of the three given sources contains a single logging call, so no PII can
leak through logging here.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
