---
id: 98d7c94e-4db9-42c9-b36e-1a2a59409fda
title: 'Hub Domain: Organizations'
domain: agentictoolkit://recipes/hub-domain-organizations
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: TypeScript client for organization records (list, resolve, create, rename,
  archive, restore) and an organization workspace's member roster.
platforms:
- typescript
- web
tags:
- hub
- organizations
- workspace
- roster
- api
depends-on: []
related:
- agentictoolkit://recipes/auth-client
references:
- packages/web/packages/data/src/organizations/organizations.ts (agentictoolkit)
- packages/web/packages/data/src/organizations/members.ts (agentictoolkit)
- packages/web/packages/data/src/organizations/wire.ts (agentictoolkit)
- packages/web/packages/data/src/organizations/index.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Organizations

## Overview

`hub-domain-organizations` is the Organizations domain of the hub: the non-UI logic that lists,
resolves, creates, renames, archives, and restores an *organization* — a workspace-owned record
whose creation provisions an ownership chain (a namespace, an admin team, and a default ecosystem)
and mints a reverse-domain identifier (rdid) — plus a companion client for an organization
workspace's member roster. Both live in
`packages/web/packages/data/src/organizations/`: `organizations.ts` (`organizationsApi` — six
methods, plus the `ORGANIZATIONS_QUERY_KEY` react-query cache-key prefix), `members.ts`
(`workspaceMembersApi.list`), and `wire.ts` (the backend row and request-body shapes both clients
read and send, transcribed from the backend's own OpenAPI-documented component schemas).
`index.ts` re-exports both files as `@agentic-toolkit/data/organizations`'s public surface.

The module's own top-of-file comment frames its central fact: creating an organization is a
hand-written backend operation, *not* generic CRUD — it provisions state beyond the organization
row itself — and its authorization is split two ways that this recipe documents precisely:
`create` is gated by the *workspace kind* the caller creates from (open in a personal workspace,
admin-of-the-org required from an org workspace), while `rename` is gated by *which field* is
being changed (name/description need org-team-admin; a slug change needs site-admin, because it
re-mints the organization's global rdid tree). `organizationsApi.list` is deliberately
workspace-scoped rather than a pure membership listing, for the same reason the sibling Ecosystems
domain's list is workspace-scoped: an unscoped "the caller's organizations" list answered a
membership question that stayed identical no matter which workspace was open, silently misplacing
an organization inside the wrong workspace's own rail.

## Behavioral Requirements

### Types (`wire.ts`)

- **organization-shape**: `Organization` MUST carry `id`, `slug`, `name`, `description?: string |
  null`, and `rdid?: string`.
- **organization-rdid-presence**: `Organization.rdid` MUST be present only on the response to a
  POST create; a plain GET (`resolve`) or PATCH (`rename`) response MUST omit it, per the type's
  own doc comment.
- **organization-list-row-omits-owner**: `OrganizationListRow` MUST carry only `id`, `slug`,
  `name`, `description?` — it MUST NOT carry an `ownerKind`/`ownerId` pair. `wire.ts`'s own doc
  comment records that this pair was removed because nothing read it: which workspace was asked is
  already the answer to "why is this org in the list."
- **organization-create-input-shape**: `OrganizationCreateInput` MUST carry exactly `slug` and
  `name` — every other organization property is provisioned server-side, per the type's own doc
  comment ("Only slug + name").
- **organization-provisioned-shape**: `OrganizationProvisioned` MUST carry `organization`,
  `namespace` (`id`, `ownerKind`, `ownerId`, `slug`, `name`, `rdid`), `teamId`, and `ecosystem`
  (`id`, `slug`, `rdid`).
- **organization-rename-input-shape**: `OrganizationRenameInput` MUST make `name`, `slug`, and
  `description` independently optional; the type's own doc comment declares that a caller MUST
  supply at least one of the three.
- **organization-renamed-alias-unused**: `OrganizationRenamed` MUST be exported (re-exported by
  `organizations.ts`) as a type alias of `Organization`, but `organizationsApi.rename`'s declared
  return type MUST remain `Organization`, never `OrganizationRenamed`.
- **organization-restored-shape**: `OrganizationRestored` MUST carry exactly one field,
  `organization`.
- **workspace-member-shape**: `WorkspaceMember` MUST carry `userId`, `email?: string | null`,
  `displayName?: string | null`, `isAdmin`, and `addedAt`.
- **workspace-member-nullable-fields**: `WorkspaceMember.email` and `.displayName` MUST be `null`
  (not merely absent) for a member outside the caller's ecosystem, per the type's own doc comment
  describing this as an RLS-bounded read, the same pattern team rosters use.
- **workspace-member-is-admin-definition**: `WorkspaceMember.isAdmin` MUST represent admin of ANY
  of the organization's teams — the roster's strongest role — per the type's own doc comment.
- **workspace-member-added-at-definition**: `WorkspaceMember.addedAt` MUST represent the EARLIEST
  membership timestamp across the organization's teams, per the type's own doc comment.

### Listing and resolution (`organizationsApi.list`, `.resolve`)

- **organization-list-workspace-required**: `organizationsApi.list` MUST take `workspaceSlug` as a
  required parameter; no workspace-less listing exists.
- **organization-list-request-shape**: `list` MUST send `GET /api/organization/organizations` with
  a `workspace=<enc(workspaceSlug)>` query parameter, and MUST return the response body unwrapped
  as `OrganizationListRow[]`.
- **organization-list-semantics-by-workspace-kind**: the set of rows `list` returns MUST depend on
  the named workspace's kind, per the function's own doc comment: a personal workspace's rows MUST
  be the organizations the caller owns plus the organizations the caller belongs to; an
  organization workspace's rows MUST be only the organizations that organization owns.
- **organization-resolve-request-shape**: `resolve(key)` MUST send `GET
  /api/organization/organizations/<enc(key)>` and MUST return the parsed body verbatim as an
  `Organization`.
- **organization-resolve-key-polymorphic**: `resolve` MUST pass `key` through unmodified — per the
  function's own doc comment, `key` MAY be a UUID, a slug, or a reverse-domain rdid, and `resolve`
  MUST NOT attempt to detect which before sending the request.
- **organization-resolve-no-404-mapping**: `resolve` MUST NOT catch or remap a 404 response; a
  not-found `key` MUST propagate as a thrown `AuthHttpError` with `status: 404`, unchanged.

### Creation (`organizationsApi.create`)

- **organization-create-request-shape**: `create(input, workspaceSlug)` MUST send `POST
  /api/organization/organizations` with a `workspace=<enc(workspaceSlug)>` query parameter, a
  `Content-Type: application/json` header, and `input` JSON-serialized verbatim as the body (no
  `compact`), and MUST resolve to the parsed `OrganizationProvisioned` body on success.
- **organization-create-workspace-required**: `create` MUST take `workspaceSlug` as a required
  parameter, naming both the workspace the organization is created FROM and the workspace that
  WILL OWN it.
- **organization-create-conflict-mapping**: a conflict thrown by the create request MUST be
  remapped, via `rethrowConflict`, to `An organization with that slug already exists.`; any other
  error MUST propagate unchanged.

### Rename (`organizationsApi.rename`)

- **organization-rename-request-shape**: `rename(id, input)` MUST send `PATCH
  /api/organization/organizations/<enc(id)>` with a `Content-Type: application/json` header and
  `compact(input)` JSON-serialized as the body, and MUST resolve to the parsed `Organization` body
  on success.
- **organization-rename-conflict-mapping**: a conflict thrown by the rename request MUST be
  remapped, via `rethrowConflict`, to `That organization slug is already taken.`; any other error
  MUST propagate unchanged.

### Archive and restore (`organizationsApi.archive`, `.restore`)

- **organization-archive-request-shape**: `archive(id)` MUST send `DELETE
  /api/organization/organizations/<enc(id)>` via `authedRequest` (not `authedJson`) and MUST
  resolve to `void`, since a 204 response has no body to parse.
- **organization-restore-request-shape**: `restore(id)` MUST send `POST
  /api/organization/organizations/<enc(id)>/restore`, MUST parse the response as
  `OrganizationRestored` via `authedJson`, and MUST resolve to `body.organization`, never the
  envelope.
- **organization-restore-conflict-status-based**: a 409 response to `restore` MUST be detected via
  `isConflict` (status-based), not `rethrowConflict` (message-based), and remapped to `That
  organization's handle has been taken, so it can't be restored.`; any other error MUST propagate
  unchanged.

### Query caching contract (`ORGANIZATIONS_QUERY_KEY`)

- **organizations-query-key-is-prefix-only**: `ORGANIZATIONS_QUERY_KEY` MUST be the fixed
  one-element tuple `["organizations"]` — a PREFIX a caller MUST append a workspace slug to
  (`[...ORGANIZATIONS_QUERY_KEY, slug]`) to form one workspace's complete cache key.
- **organizations-query-key-distinct-from-workspaces-key**: `ORGANIZATIONS_QUERY_KEY` MUST remain
  a constant distinct from any workspace-membership query key a caller separately maintains, per
  the export's own doc comment, since the two keys cache the answers to two different questions
  over two different endpoints.

### Workspace member roster (`workspaceMembersApi.list`)

- **roster-request-shape**: `workspaceMembersApi.list(slug)` MUST send `GET
  /api/workspaces/<enc(slug)>/members` via `authedJson` and MUST resolve to the parsed body
  verbatim as a `WorkspaceMembersResponse` (not unwrapped to a bare array, unlike
  `organizationsApi.list`).
- **roster-distinct-customers**: the resolved `WorkspaceMembersResponse.members` MUST be the
  distinct customers across the organization's org-owned teams, per the function's own doc comment
  ("the distinct customers across the org's org-owned teams"); a customer belonging to more than
  one of the organization's teams MUST appear exactly once.
- **roster-not-found-semantics**: `list` MUST propagate a 404 unchanged both for a slug naming no
  organization workspace and for an organization workspace the caller is not a member of, per the
  function's own doc comment; it performs no client-side membership check of its own.

### Cross-cutting

- **every-call-url-encodes-identifiers**: every `organizationsApi` and `workspaceMembersApi` method
  MUST percent-encode every caller-supplied identifier it places in a URL (`workspaceSlug`, `key`,
  `id`, roster `slug`) via `enc` (`encodeURIComponent` aliased in `client-helpers.ts`).
- **no-client-side-cache**: `organizationsApi` and `workspaceMembersApi` MUST NOT cache or memoize
  any response themselves; every call issues exactly one HTTP request.
- **module-holds-no-mutable-state**: neither module MUST hold mutable module-level state across
  calls; the only module-level value besides the URL templates each method builds inline is the
  read-only `ORGANIZATIONS_QUERY_KEY` constant. Unlike the sibling `ecosystemsApi`/`accessApi`
  clients, no `BASE` route constant is extracted in either file.

### Security

This is a security-relevant recipe: `create`, `rename`, `archive`, and the roster read are all
gated by organization- and workspace-level authorization roles. It carries no secret of its own —
the bearer credential lives in `@agentic-toolkit/auth/client`, which this module composes rather
than reimplements.

- **auth-delegated-to-shared-client**: every network call in both modules MUST go through
  `authedJson` or `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via `./http`),
  which attaches `Authorization: Bearer <token>` from `readAccessToken()`; neither module MUST
  read, store, or attach a token itself.
- **session-refresh-waterfall**: a 401 response to any call MUST trigger exactly one token refresh
  and one retried request, inherited unconditionally from `authedFetch`; a second 401 on the
  retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved 401 MUST cause
  the call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body
  supplies one, a machine-readable `code`.
- **authorization-enforced-server-side**: neither module MUST perform any client-side permission
  check before sending a request. Per `organizations.ts`'s own comments: `create`'s split (open in
  a personal workspace, admin-of-the-organization required from an organization workspace),
  `rename`'s split (name/description need org-team-admin, slug needs site-admin), `archive`'s
  allowed roles (organization creator, org-team admin, or site-admin), and the roster's membership
  gate are all enforced entirely by the backend — a violation surfaces as a 403 (or, for the
  roster, a 404) that this client does not distinguish or pre-check.

## Appearance

Not applicable — this is a data-access client (two API modules and their wire types), not a visual
component.

## States

Not applicable — this is a data-access client, not a visual component. Its observable "states" are
the ordinary async-operation states a caller already handles generically: in-flight (an awaited
`Promise`), succeeded, and failed (a thrown `AuthHttpError` or plain `Error`).

## Accessibility

Not applicable — this is a data-access client, not a visual component. Every string this component
defines (the three hand-authored conflict messages) is plain text handed to whatever presentation
layer a caller builds around it.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-organizations-001 | organization-shape, organization-rdid-presence | Decode two `Organization`-shaped payloads: one from a GET/PATCH response (no `rdid`) and one from a POST create response (`rdid` present) | The GET/PATCH-shaped value has `rdid === undefined`; the POST-shaped value has `rdid` equal to the sent string — derived directly from `wire.ts`'s own doc comment on `Organization.rdid`; no dedicated test in this checkout |
| hub-domain-organizations-002 | organization-list-row-omits-owner | Construct an `OrganizationListRow` literal | The type accepts only `id`, `slug`, `name`, `description?` — an `ownerKind`/`ownerId` pair is a compile-time excess-property error — compile-time fact from `wire.ts`; no runtime test |
| hub-domain-organizations-003 | organization-create-input-shape | Construct an `OrganizationCreateInput` literal with `slug`/`name` only | Compiles; a third field is a compile-time error — compile-time fact from `wire.ts`; no runtime test |
| hub-domain-organizations-004 | organization-rename-input-shape | Construct an `OrganizationRenameInput` literal with only `slug` set | Compiles — `name`/`description` are independently optional — compile-time fact from `wire.ts`; no runtime test |
| hub-domain-organizations-005 | organization-provisioned-shape, organization-create-request-shape, organization-create-workspace-required | `organizationsApi.create({slug:"acme",name:"Acme"}, "personal")` against a stub 201 response `{organization, namespace, teamId, ecosystem}` | Resolves to that object verbatim; request is `POST /api/organization/organizations?workspace=personal` with body `{"slug":"acme","name":"Acme"}` — no dedicated test; derived directly from source |
| hub-domain-organizations-006 | organization-restored-shape, organization-restore-request-shape | `organizationsApi.restore("org-1")` against a stub 200 response `{"organization":{"id":"org-1","slug":"acme","name":"Acme"}}` | Resolves to `{"id":"org-1","slug":"acme","name":"Acme"}`, the unwrapped `organization`, not the envelope — no dedicated test; derived directly from source |
| hub-domain-organizations-007 | organization-renamed-alias-unused | Inspect `organizationsApi.rename`'s declared return type against the exported `OrganizationRenamed` alias | `rename` is typed `Promise<Organization>`, never `Promise<OrganizationRenamed>`, even though `OrganizationRenamed` is re-exported from this module — compile-time fact from `organizations.ts`/`wire.ts`; no runtime test |
| hub-domain-organizations-008 | workspace-member-shape, workspace-member-nullable-fields | Decode a `WorkspaceMember` row for a member outside the caller's ecosystem: `{"userId":"u1","email":null,"displayName":null,"isAdmin":false,"addedAt":"2026-01-01"}` | Resolves with `email === null` and `displayName === null`, not `undefined` or omitted — derived directly from `wire.ts`'s doc comment; no dedicated test |
| hub-domain-organizations-009 | workspace-member-is-admin-definition | A customer who is a plain member of one of the org's teams and an admin of another of the org's teams | The roster row for that customer has `isAdmin === true` — derived directly from `wire.ts`'s doc comment ("Admin of any of the org's teams"); no dedicated test |
| hub-domain-organizations-010 | workspace-member-added-at-definition | A customer who joined Team A on `2026-01-01` and Team B (same org) on `2026-03-01` | The roster row for that customer has `addedAt === "2026-01-01"` — derived directly from `wire.ts`'s doc comment ("Earliest membership across the org's teams"); no dedicated test |
| hub-domain-organizations-011 | organization-list-workspace-required, organization-list-request-shape | `organizationsApi.list("acme")` | Request URL is `/api/organization/organizations?workspace=acme`; resolves to the parsed body verbatim as `OrganizationListRow[]` — no dedicated test; derived directly from source |
| hub-domain-organizations-012 | every-call-url-encodes-identifiers | `organizationsApi.list("a b/c")`, and separately `workspaceMembersApi.list("a b/c")` | Both request URLs contain the slug percent-encoded via `encodeURIComponent("a b/c")`, not the raw string — no dedicated test; derived directly from `enc`'s use in both files |
| hub-domain-organizations-013 | organization-list-semantics-by-workspace-kind | `organizationsApi.list` called with a personal-workspace slug, and separately with an organization-workspace slug | The row set differs per the function's own doc comment (personal → owned-plus-member organizations; organization workspace → only that organization's owned rows) — this is server-side behavior the client cannot assert on its own; recorded as fact per the source comment, not exercised by a test in this checkout |
| hub-domain-organizations-014 | organization-resolve-request-shape, organization-resolve-key-polymorphic | `organizationsApi.resolve("org.acme")`, `.resolve("11111111-1111-1111-1111-111111111111")`, and `.resolve("acme")` | All three send `GET /api/organization/organizations/<key>` with the key passed through unmodified — no dedicated test; derived directly from source |
| hub-domain-organizations-015 | organization-resolve-no-404-mapping | `organizationsApi.resolve("missing")` against a backend 404 | Rejects with `AuthHttpError`, `status: 404`; `resolve` contains no catch clause of its own — no dedicated test; derived directly from the absence of a catch block in source |
| hub-domain-organizations-016 | organization-create-conflict-mapping | The create request's backend response is a 409 whose message matches the pattern "already exists" | `create` rejects with `Error("An organization with that slug already exists.")`, not the raw backend message — derived directly from `rethrowConflict`'s pattern match in `http.ts`; no dedicated test |
| hub-domain-organizations-017 | organization-rename-request-shape | `organizationsApi.rename("org-1", {slug:"acme2", description: undefined})` | `PATCH /api/organization/organizations/org-1` with body `{"slug":"acme2"}` — `description` is omitted, not sent as an explicit `undefined`, because `compact` strips it — no dedicated test; derived directly from source |
| hub-domain-organizations-018 | organization-rename-conflict-mapping | The rename request's backend response is a 409 whose message matches the pattern "already exists" | `rename` rejects with `Error("That organization slug is already taken.")` — no dedicated test; derived directly from source |
| hub-domain-organizations-019 | organization-archive-request-shape | `organizationsApi.archive("org-1")` against a 204 response | Sends `DELETE /api/organization/organizations/org-1` via `authedRequest`; resolves to `undefined` with no parse attempted — no dedicated test; derived directly from source |
| hub-domain-organizations-020 | organization-restore-conflict-status-based | `organizationsApi.restore("org-1")` against a 409 response whose body message reads "that organization handle has been taken" (does not match the "already exists" pattern) | `restore` rejects with `Error("That organization's handle has been taken, so it can't be restored.")`, produced via the status-based `isConflict` check, not `rethrowConflict` — derived directly from the source's own inline comment explaining this asymmetry; no dedicated test |
| hub-domain-organizations-021 | organizations-query-key-is-prefix-only, organizations-query-key-distinct-from-workspaces-key | Read the exported `ORGANIZATIONS_QUERY_KEY` constant | Deep-equals the one-element tuple `["organizations"]`; the export's own doc comment states it is deliberately distinct from a workspace-membership key — no dedicated test; derived directly from source |
| hub-domain-organizations-022 | roster-request-shape | `workspaceMembersApi.list("acme")` against a stub response `{"members":[{"userId":"u1","email":"a@b.com","displayName":"A","isAdmin":true,"addedAt":"2026-01-01"}]}` | `GET /api/workspaces/acme/members`; resolves to the parsed body verbatim (the `{members}` envelope, not unwrapped to a bare array) — no dedicated test; derived directly from source |
| hub-domain-organizations-023 | roster-distinct-customers | A backend roster response for an organization whose one customer belongs to two of the organization's teams | The resolved `members` array contains exactly one row for that customer — a backend guarantee stated in the function's own doc comment; recorded as fact, not exercised by a client-side test in this checkout |
| hub-domain-organizations-024 | roster-not-found-semantics | `workspaceMembersApi.list` called with a slug naming no organization workspace, and separately with a slug naming a real organization workspace the caller is not a member of | Both reject with `AuthHttpError`, `status: 404`, indistinguishable from each other by this client — derived directly from the function's own doc comment; no dedicated test |
| hub-domain-organizations-025 | session-refresh-waterfall | Any `organizationsApi`/`workspaceMembersApi` call's first response is 401; `refreshAccessToken()` resolves a new token | The request is retried once with the new token; a 401 on that retry throws `AuthHttpError`, `status: 401` — traced to `authedFetch` in `auth/src/client.ts`; exercised only indirectly through these two modules |
| hub-domain-organizations-026 | authorization-enforced-server-side | Backend responds 403 to `create` called from an organization workspace by a non-admin, and separately 403 to `rename`'s slug field patched by an org-team-admin who is not site-admin | Both calls reject with `AuthHttpError` carrying the response status; neither module contains a branch that inspects caller role before sending the request — derived directly from `organizations.ts`'s own comments; no dedicated test |
| hub-domain-organizations-027 | no-client-side-cache, module-holds-no-mutable-state | Call `organizationsApi.list("acme")` twice in succession against a fetch mock that counts invocations | The mock records exactly two HTTP requests, one per call — no shared cache or memoized result short-circuits the second call — no dedicated test; derived directly from the absence of any cache/state field in either module |
| hub-domain-organizations-028 | auth-delegated-to-shared-client | Inspect every exported method's implementation | Every one calls `authedJson` or `authedRequest`; neither module attaches an `Authorization` header or reads a token itself — derived directly from source; no dedicated test |
| hub-domain-organizations-029 | errors-carry-status-and-code | Backend responds 403 to `archive` with body `{"error":{"message":"forbidden","code":"not_site_admin"}}` | The thrown `AuthHttpError` has `status: 403` and `code: "not_site_admin"` — traced to `extractErrorCode`/`extractErrorMessage` in `auth/src/client.ts`; no dedicated test in this checkout |

## Edge Cases

- **Null and empty input — identifiers**: Not checked client-side. `workspaceSlug`, `key`, `id`,
  and the roster `slug` are typed `string`; an empty string is sent to the server unchanged (e.g.
  `workspace=`). A non-empty, valid slug/id/key is a caller precondition per each function's own
  doc comment, not something this client validates.
- **rename-empty-patch-validation**: supplying at least one of `name`/`slug`/`description` is a caller precondition stated by `OrganizationRenameInput`'s doc comment; `rename` does not check it, so `rename(id, {})` sends `compact({})`, an empty JSON object, as the PATCH body, and the backend's response surfaces unchanged.
- **Boundary/malformed values**: No length, character-set, or format constraint is enforced
  client-side on `slug`, `name`, or `description` anywhere in `organizations.ts` — unlike the
  sibling Apple `Ecosystem` client's pattern/length checks, this client imposes no boundary of its
  own on any field; per the module's own "hand-written on the backend" framing, the backend's own
  validation is the sole authority.
- **Concurrent access — competing creates**: Two closely-timed `create` calls for the same slug
  race the backend's unique-slug constraint; the loser's request is rejected with a 409 that
  `create` maps to `"An organization with that slug already exists."` via `rethrowConflict` — this
  client makes no pre-check of its own, so both requests are always sent.
- **Concurrent access — competing restores**: Two closely-timed `restore` calls for handles that
  both resolve to the same freed slug race the same way; per `organization-restore-conflict-status-based`,
  the loser gets the distinct, status-based `"That organization's handle has been taken, so it
  can't be restored."` message rather than the create/rename wording.
- **Error states — validation vs. HTTP failure**: every error this component's callers can observe
  is a thrown `AuthHttpError` (via `authedFetch`) or one of the two hand-authored friendly `Error`s
  (`create`/`rename`'s `rethrowConflict` remap, `restore`'s `isConflict` remap); no path in either
  file swallows an error or resolves a value on failure.
- **Error states — 404 ambiguity**: per `organization-resolve-no-404-mapping` and
  `roster-not-found-semantics`, `resolve`'s 404 (key not found) and the roster's 404 (non-org slug,
  or a non-member of a real org) are both plain, unremapped `AuthHttpError`s with `status: 404` —
  this client gives the caller no way to distinguish "does not exist" from "exists but you can't
  see it" beyond the status code itself.
- **Offline or disconnected state**: none of the seven exported methods catches a network-level
  `fetch` rejection; a connectivity loss mid-call propagates as an unhandled promise rejection to
  the caller, with no retry, queuing, or offline-specific handling anywhere in either file.
- **No timeout / no cancellation**: no method sets a deadline or accepts an abort signal from the
  caller; a reachable-but-unresponsive backend leaves the call pending indefinitely.
- **No retry beyond the 401 waterfall**: every call issues exactly one request (plus, on a 401, the
  single inherited refresh-and-retry); nothing in either file retries a network failure or a
  non-401/non-409 error status.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspaceSlug` (`organizationsApi.list`, `.create`) | `string` | none — required | Names the workspace whose organizations are listed, or the workspace an organization is created FROM (and will OWN). |
| `key` (`organizationsApi.resolve`) | `string` | none — required | A UUID, slug, or reverse-domain rdid identifying the organization; passed through unmodified. |
| `id` (`organizationsApi.rename`, `.archive`, `.restore`) | `string` | none — required | The organization's stored handle (`Organization.id`), percent-encoded into the URL path. |
| `input` (`organizationsApi.create`) | `OrganizationCreateInput` | none — required | `{ slug, name }`, sent verbatim as the `POST` body. |
| `input` (`organizationsApi.rename`) | `OrganizationRenameInput` | none — required | Any subset of `{ name, slug, description }`; sent through `compact` so unset fields are omitted. |
| `slug` (`workspaceMembersApi.list`) | `string` | none — required | The organization workspace slug whose member roster is requested. |
| `/api/organization/organizations` | route literal, no exported constant | fixed | Base path every `organizationsApi` method inlines per call; unlike the sibling `ecosystemsApi`/`accessApi` clients, no `BASE` module constant is extracted. |
| `/api/workspaces/<slug>/members` | route literal | fixed | Roster route `workspaceMembersApi.list` inlines per call. |

## Deep Linking

Not applicable: `organizations.ts`/`members.ts`/`wire.ts` register no URL scheme, route, or
navigation target of their own; they are a data client consumed by a separate presentation layer
that owns any deep-linking concern.

## Localization

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | An organization with that slug already exists. | Thrown by `create` when the backend reports a slug conflict |
| — | That organization slug is already taken. | Thrown by `rename` when the backend reports a slug conflict |
| — | That organization's handle has been taken, so it can't be restored. | Thrown by `restore` when the backend reports a 409 |

There is no localization mechanism in either file (no catalog, no key, no `i18n` call) — the three
strings above are fixed English literals, stated as fact per the non-UI component guidance rather
than as a hidden gap (see Compliance). Every other error message a caller can observe from either
module originates in the backend's response body and is extracted by `extractErrorMessage` in
`auth/src/client.ts`, not authored here.

## Accessibility Options

Not applicable: `organizations.ts`/`members.ts`/`wire.ts` render no UI and respond to none of
Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: no file in either module defines or reads a feature-flag key.

## Analytics

Not applicable: no file in either module emits a client-side analytics or telemetry event.

## Privacy

- **Data collected**: organization administrative metadata (`id`, `slug`, `name`, `description`,
  `rdid`, and the provisioned `namespace`/`teamId`/`ecosystem` ids), plus, via
  `workspaceMembersApi.list`, roster rows naming a member's `userId`, `email`, `displayName`,
  `isAdmin` status, and `addedAt` timestamp. Unlike the organization fields, the roster's `email`
  and `displayName` ARE personal data about a real person.
- **Storage**: neither module holds a cache of its own; every call is a live round-trip, per
  `no-client-side-cache`. Whatever a caller does with the resolved data (for example, a react-query
  cache keyed via `ORGANIZATIONS_QUERY_KEY`) is outside these two files.
- **Transmission**: every call travels through `authedJson`/`authedRequest`, per
  `auth-delegated-to-shared-client`; neither module attaches its own credentials or reads cookies.
- **Retention**: none within these files. `email`/`displayName`'s exposure is already narrowed
  server-side to members within the caller's ecosystem, per `workspace-member-nullable-fields` —
  this client neither widens nor persists that exposure.

## Logging

Not applicable: no file in either module calls a logger, `console.log`, `console.warn`,
`console.error`, or any platform logging API. Every failure this component detects is surfaced to
its caller as a thrown `AuthHttpError` or plain `Error`; any logging of that failure is the
responsibility of the caller or host application.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/organizations/organizations.ts`,
  `members.ts`, and `wire.ts` hold the client; every method is a plain async function over
  `authedJson`/`authedRequest` (`@agentic-toolkit/auth/client`, re-exported through `./http`) and
  `enc`/`compact` from `./client-helpers`; `index.ts` re-exports both files as the package's public
  surface (`@agentic-toolkit/data/organizations`).
- **SwiftUI**: a Swift port would model `Organization`/`OrganizationListRow`/
  `OrganizationCreateInput`/`OrganizationProvisioned`/`OrganizationRenameInput`/
  `OrganizationRestored`/`WorkspaceMember`/`WorkspaceMembersResponse` as `Codable, Hashable,
  Sendable` structs, mirroring the pattern the sibling Hub Ecosystems/Access recipes' Apple models
  already use, and `organizationsApi`/`workspaceMembersApi` as an `actor` or `@MainActor final
  class` exposing `async throws` functions built on `URLSession`, with a dedicated error type
  carrying the HTTP status and an optional machine code in place of `AuthHttpError`.
- **AppKit / UIKit**: no direct UI dependency exists in either module; a macOS/iOS Hub feature
  would consume the ported client through an injected data-source protocol — the same pattern the
  sibling `EcosystemsDataSource` already uses — rather than calling `URLSession` from the view
  layer.
- **Compose**: model the eight wire shapes as Kotlin `data class`es annotated `@Serializable`, and
  `organizationsApi`/`workspaceMembersApi` as classes exposing `suspend fun` equivalents built on
  Ktor or OkHttp, with a sealed error type carrying the HTTP status and optional code.
- **WinUI 3**: `HttpClient` with `System.Text.Json` replaces `fetch`/`URLSession` for every
  organizations/roster request this recipe documents. A `ContentDialog` hosting
  `Microsoft.UI.Xaml.Controls` (`TextBox` for `slug`/`name`, a multi-line `TextBox` for
  `description`) is the equivalent of a create/rename form, and a second `ContentDialog` with a
  destructive-styled primary button is the equivalent of an archive-confirmation flow a host would
  build around `archive(id)`. `Task`/`async`-`await` replaces every `Promise` call; a custom
  `AccessApiException`-equivalent exception (status, code) should carry the same conflict-versus-
  not-found distinctions this recipe's error-mapping requirements rely on — and, per
  `organization-restore-conflict-status-based`, a WinUI port MUST keep `restore`'s conflict
  detection status-code-based rather than message-text-based, since the backend's 409 wording
  differs between the create/rename routes and the restore route.

## Design Decisions

**Decision**: `organizationsApi.list` requires `workspaceSlug` and scopes its rows by that
workspace's kind (owned-plus-member for a personal workspace, owned-only for an organization
workspace), rather than answering a plain, workspace-independent "the caller's organizations"
question.
**Rationale**: per the module's own top-of-file comment, an earlier arrangement read
`workspacesApi.list()` and filtered `kind === "organization"` — a pure membership question,
identical under every workspace, so the workspace you had open silently appeared inside its own
organizations rail. Organizations now carry an owning workspace (`owner_kind`/`owner_id`), and this
endpoint reads it; `workspacesApi.list()` remains correct for the workspace SWITCHER, which
genuinely is asking the membership question.
**Approved**: pending

**Decision**: `create` sends `input` verbatim (no `compact`), while `rename` applies
`compact(input)` to a structurally similar patch object.
**Rationale**: `create`'s body is a fixed two-field shape (`slug` + `name`) always fully supplied
by the caller — there is nothing optional to omit. `rename`'s body has three independently optional
fields, and an untouched field must not travel as an explicit `undefined` key on the wire; `compact`
is needed only where partial updates exist.
**Approved**: pending

**Decision**: `restore`'s 409 handling is status-based (`isConflict`), while `create`/`rename`'s is
message-based (`rethrowConflict`).
**Rationale**: the source's own inline comment states the restore route's 409 message ("that
organization handle has been taken") does not match `rethrowConflict`'s "already exists" pattern
match — reusing `rethrowConflict` here would fail to produce the friendly message and let the raw
backend wording leak through. Status-based detection avoids depending on exact wording that this
one route doesn't share with the other two.
**Approved**: pending

**Decision**: `resolve` does not intercept a 404 into `null`.
**Rationale**: no comment in the source explains this choice, and no other 404-to-null pattern
exists elsewhere in these two files to compare it against (unlike the sibling Ecosystems client's
`get(id)`, which does map 404 to `null`). This is recorded as an observed fact of the current
source, not smoothed into a more convenient shape — a port SHOULD preserve it unless a future
change to the source deliberately revisits it.
**Approved**: pending

**Decision**: `create`'s authorization splits on WORKSPACE KIND (open in a personal workspace,
admin-of-the-organization required from an organization workspace), while `rename`'s splits on
WHICH FIELD is being changed (name/description need org-team-admin; slug needs site-admin).
**Rationale**: both splits are stated directly in the source's own per-method comments. `create`'s
split exists because creating from an organization workspace is a governance act — the organization
that owns the workspace ends up owning the result. `rename`'s split exists because a slug change
re-mints the organization's global rdid tree, a wider-blast-radius operation than editing a label.
**Approved**: pending

**Decision**: `ORGANIZATIONS_QUERY_KEY` is deliberately a bare prefix, not a complete cache key, and
deliberately distinct from any workspace-membership query key.
**Rationale**: directly from the export's own doc comment — a caller appends the workspace slug so
each workspace caches its own answer and switching workspaces cannot serve the previous one's rows;
invalidating the bare prefix clears every workspace at once, which is what `create`/`rename` need.
Sharing one key over the organizations question and the membership question is what made the two
lists impossible to tell apart before this endpoint existed.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | failed | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` **passed**: `organizations.ts`/`members.ts` contain zero UI or
presentation code, `wire.ts` is a type-only file, and `index.ts`'s own comment describes the module
as the public surface of a data domain, consumed by a separate presentation layer.
`explicit-error-handling` **passed**: nothing in either file swallows an error — every failure
either throws `AuthHttpError` (via the shared `authedFetch`) or one of the two hand-authored
friendly `Error`s this recipe documents. `unit-test-coverage` **failed**: no `__tests__` directory
or `*.test.ts` file exists next to `organizations.ts`/`members.ts` in this checkout, and the
consumer feature tests found elsewhere in the repository (`NewOrganizationModal.test.tsx`,
`orgRenameSavePath.test.tsx`) mock `@agentic-toolkit/data/organizations` wholesale rather than
exercising this module's own request-building or error-mapping logic — none of the requirements
above is exercised by a dedicated test in this checkout. `server-side-authorization` **passed**:
neither module performs a client-side permission check of any kind, per
`authorization-enforced-server-side`, deferring the workspace-kind and field-level authorization
splits, the archive role set, and the roster membership gate entirely to the backend.
`input-sanitization` **partial**: no file client-side validates `slug`/`name`/`description`
character set or length before sending; the backend's own uniqueness constraint and validation are
the sole authority this client deliberately relies on rather than duplicating (see Edge Cases).
`error-response-handling` **passed**: `rethrowConflict`/`isConflict` and the plain `AuthHttpError`
propagation consistently distinguish a slug conflict (`create`/`rename`), a handle-taken conflict
(`restore`), and every other failure, on every method. `retry-with-backoff` **failed**: no file
retries a failed organizations/roster request beyond the inherited 401-refresh-and-retry-once,
which is a different, cross-cutting auth concern (see `auth-client`), not a retry of this domain's
own operations. `offline-behavior` **failed**: neither module defines an offline-cache-first read
path or a queued-write-when-offline behavior; every operation is a live round-trip that fails
outright when the network is unavailable. `idempotent-operations` **partial**: `rename`'s PATCH is
a plain field update with no stated idempotency guarantee of its own (unlike the sibling Ecosystems
client's documented locked-value diff), and `create`/`restore` have no idempotency key on the
client side — a client-level retry of either (were one ever added) could not safely be
distinguished from a genuine duplicate request. `data-minimization` **passed**: every organization
field this component reads or writes is administrative metadata, and the roster's personal fields
(`email`, `displayName`) are already nulled server-side outside the caller's own ecosystem before
this client ever sees them. `no-hardcoded-strings` **failed**: the three hand-authored conflict
messages this recipe documents are fixed English with no lookup table or locale parameter in either
file (see Localization) — a plain, honestly-reported gap, not a hidden one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial recipe: `organizationsApi` (list/resolve/create/rename/archive/restore), `workspaceMembersApi.list`, and the wire model contract. |
