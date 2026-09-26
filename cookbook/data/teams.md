---
id: 28581588-68f5-465d-8e8e-3aaaaef00560
title: 'Hub Domain: Teams'
domain: agentictoolkit://cookbook/data/teams
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Teams domain logic: the web teamsApi (generic-CRUD Team, scoped to an ecosystem)
  and teamMembersApi (hand-written membership by customer email or persona key) clients.'
platforms:
- typescript
- web
tags:
- hub
- teams
- team-members
- access-control
- slug
depends-on: []
related:
- agentictoolkit://cookbook/data/ecosystems
references:
- packages/web/packages/data/src/teams/team-members.ts (agentictoolkit)
- packages/web/packages/data/src/teams/teams.ts (agentictoolkit)
- packages/web/packages/data/src/teams/wire.ts (agentictoolkit)
- packages/web/packages/data/src/teams/index.ts (agentictoolkit)
- packages/web/packages/data/src/teams/__tests__/teams.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Teams

## Overview

`hub-domain-teams` is the Teams domain of the hub: the non-UI web logic for
a *team* (a named group owned by an ecosystem) and its membership. There is
no Apple counterpart — this is a single, web-only reference implementation
(`packages/web/packages/data/src/teams/`, TypeScript), split across two
clients that sit on two different kinds of backend route:

- **`teams.ts`** — `teamsApi`, `toTeam`, and `validateTeamIdentifier`. The
  `Team` row itself is generic CRUD (`team.teams`), so this file's whole job
  is translating between the backend's column names and the UI's vocabulary
  and scoping every request to the calling workspace's owning ecosystem.
- **`team-members.ts`** — `teamMembersApi`. Membership is a hand-written
  backend route (`/api/team/members`, "OFF generic CRUD"), off the generated
  OpenAPI surface, because a member is one of two different kinds of thing —
  an existing customer added by email, or one of the caller's personas added
  by a grant-gated key — and no generic CRUD table models that choice.
- **`wire.ts`** — the backend row (`TeamRow`) and request-body
  (`TeamCreateBody`, `TeamPutBody`) shapes `teams.ts`'s mapper and call sites
  read and write; type-only, and deliberately narrower than the hub's
  generated `SuccessBody<...>`/`RequestBody<...>` wrappers so this client
  does not take on "adh product vocabulary a generic data client must not
  take on" (file header).
- **`index.ts`** — the public surface: both clients' exports.

Both clients share the transport and shaping conventions documented once
here: `authedJson`/`authedRequest` (`http.ts`, itself a re-export of
`@agentic-toolkit/auth/client`'s Bearer-token client) throw an `Error`
carrying the backend's message on failure, and every method here lets that
error propagate to the caller except `teamsApi.get`, which resolves to
`null` instead. `compact()` (`client-helpers.ts`) drops only `undefined`
keys from a PATCH/PUT body, preserving an explicit `null`.

## Behavioral Requirements

### teams.ts — `teamsApi`

- **team-vocabulary-mapping**: `toTeam` MUST map the backend row's `name`
  column to `Team.displayName` and `slug` to `Team.identifier`, passing
  `id`, `createdAt`, and `updatedAt` through unchanged (`toTeam`; file
  header mapping table: "UI displayName <-> backend name", "UI identifier
  <-> backend slug").
- **team-identifier-is-reverse-domain**: `Team.identifier` MUST be a
  reverse-domain string, e.g. `com.example.platform` (`Team.identifier` doc
  comment).
- **identifier-validation-empty-refused**: `validateTeamIdentifier` MUST
  return `"Identifier is required."` for an empty identifier, checked
  before the shape rule (`validateTeamIdentifier`, confirmed by
  `hub-domain-teams-002`).
- **identifier-validation-shape**: `validateTeamIdentifier` MUST return
  `"Use reverse-domain form, e.g. com.example.platform."` for a non-empty
  identifier that fails the pattern one lowercase-alphanumeric label
  followed by one or more dot-separated lowercase-alphanumeric-or-hyphen
  labels, and MUST return `null` when the identifier passes
  (`validateTeamIdentifier`, confirmed by `hub-domain-teams-001`/`003`).
- **team-list-scoped-to-ecosystem**: `teamsApi.list(ecosystemId)` MUST GET
  `/api/team/teams?ecosystemId=<encoded ecosystemId>`; the backend then
  returns ONLY that ecosystem's teams, enforced even for an admin caller
  (file header: "`?ecosystemId=` ... list then returns ONLY that
  ecosystem's teams (enforced for admins too)").
- **team-list-sorted-by-display-name**: `teamsApi.list` MUST return teams
  sorted by `displayName` via `sortByText` (locale-aware `localeCompare`),
  never in the backend's raw row order (`teamsApi.list`).
- **team-get-resolves-null-on-thrown-error**: `teamsApi.get(id)` MUST
  resolve to `null` rather than rethrow when the underlying request throws
  — "the backend 404s with a thrown error; the UI contract is
  null-for-missing" (`teamsApi.get`).
- **team-get-swallows-any-error-as-not-found**: NEEDS REVIEW: Not implemented in source. `teamsApi.get`'s catch block returns `null` for ANY thrown error, not only the backend's documented 404, so a network failure or a 500 is indistinguishable from a team that genuinely does not exist, and no signal (a rethrow, a log call) reaches the caller to tell the two apart; settled by narrowing the catch to `httpStatus(err) === 404` (`http.ts`) and rethrowing everything else, or by an operator-visible log of the swallowed error.
- **team-create-no-pre-read-relies-on-backend-constraint**: `teamsApi.create`
  MUST NOT pre-read for a duplicate identifier before POSTing — the
  backend's unique `(owner, slug)` constraint is the sole guard, because a
  pre-read "can't see a soft-deleted row still holding the slug"
  (`teamsApi.create` inline comment).
- **team-create-scopes-into-ecosystem**: `teamsApi.create(input,
  ecosystemId)` MUST POST to `/api/team/teams?ecosystemId=<encoded
  ecosystemId>`, stamping the new team into that ecosystem so it lands in —
  and is visible under — the workspace it was created in (`teamsApi.create`
  inline comment).
- **team-create-conflict-rethrown-friendly**: On a 409 whose message
  matches "already exists" (case-insensitive), `teamsApi.create` MUST
  rethrow via `rethrowConflict` as `A team with identifier "<identifier>"
  already exists.`; any other error MUST rethrow unchanged
  (`rethrowConflict`, `teamsApi.create` catch block, confirmed by
  `hub-domain-teams-004`).
- **team-update-partial-via-compact**: `teamsApi.update(id, input)` MUST
  send only the defined optional keys of `{name, slug}` through `compact` —
  an omitted (`undefined`) field MUST be dropped from the PUT body
  (`teamsApi.update`, confirmed by `hub-domain-teams-005`).
- **team-update-conflict-rethrown-friendly**: `teamsApi.update` MUST
  rethrow a 409 slug collision via `rethrowConflict` with the same
  friendly-message shape as `create`, because "a slug rename can collide
  with the unique `(owner, slug)` index" (`teamsApi.update` inline comment).
- **team-delete-issues-delete**: `teamsApi.delete(id)` MUST issue `DELETE
  /api/team/teams/<encoded id>` and resolve to `void` on success
  (`teamsApi.delete`).
- **team-row-id-is-opaque**: `Team.id` MUST be treated as an opaque,
  server-generated identifier, never derived or parsed by this client (file
  header: "UI id <-> backend id (opaque server-generated UUID)").

### team-members.ts — `teamMembersApi`

- **member-kind-discriminates-customer-vs-persona**: `TeamMember.memberKind`
  MUST be read as `"customer"` for any value other than the literal
  `"persona"` — "present on every GET row; treat anything other than
  'persona' as a customer (robust to the api-types field still being
  optional)" (`TeamMember.memberKind` doc comment).
- **member-email-null-outside-ecosystem**: `TeamMember.email` MUST be
  `null` when the member's customer row lies outside the caller's
  ecosystem, and MUST be non-null only when resolved from a customer row
  within it (`TeamMember.email` doc comment: "resolved from the member's
  customer row; null if outside the caller's ecosystem").
- **member-persona-fields-null-for-customers**: `TeamMember.personaSlug`
  and `TeamMember.personaName` MUST be set only for a persona member and
  MUST be `null` for a customer member (`TeamMember.personaSlug`/
  `personaName` doc comments: "set only for persona members (null for
  customers)").
- **member-list-tolerates-missing-members-key**: `teamMembersApi.list`
  MUST return an empty array when the response body carries no `members`
  key, rather than dereferencing `undefined.length` — "tolerate a body
  without `members` (the route always sends it, but a proxy/error page
  might not)" (`teamMembersApi.list`).
- **member-list-query-scoped-by-team**: `teamMembersApi.list(teamId)` MUST
  GET `/api/team/members?teamId=<encoded teamId>` (`teamMembersApi.list`).
- **member-counts-maps-team-to-count**: `teamMembersApi.counts()` MUST
  return a `Map` keyed by `teamId` to that team's member count within the
  caller's scope, built from `GET /api/team/members/counts`, and MUST
  default to an empty `Map` when the response carries no `counts` array
  (`teamMembersApi.counts`).
- **member-counts-is-unreferenced-but-retained**: `teamMembersApi.counts`
  MUST remain in this client even though "nothing in the fleet calls it
  now" — the backend route it wraps is live, and this client mirrors "the
  backend's surface, not the current callers'"; it MUST be deleted only
  together with the route it wraps, never before (`teamMembersApi.counts`
  doc comment).
- **member-add-by-email-resolves-existing-customer**: `add(teamId, email)`
  MUST POST `{teamId, email}` to `/api/team/members`, adding an EXISTING
  customer resolved by email within the caller's ecosystem — never
  creating a new customer; the backend 404s when none resolves (file
  header: "added by EMAIL, resolved to a customer in the ecosystem — 404 if
  none").
- **member-add-persona-gated-by-may-act**: `addPersona(teamId, personaKey)`
  MUST POST `{teamId, personaKey}` to `/api/team/members/personas`, and the
  backend MUST refuse the call (403) unless the named persona has been
  granted `may_act` `'team'` (file header: "gated on the persona's may_act
  'team' grant").
- **member-remove-addresses-member-row**: `remove(memberId)` MUST issue
  `DELETE /api/team/members/<encoded memberId>`, addressing the MEMBER
  row's own id — not the team id, nor the underlying user's or persona's id
  (`teamMembersApi.remove`).
- **member-errors-propagate-with-backend-message**: `list`, `counts`,
  `add`, `addPersona`, and `remove` MUST NOT catch or transform a thrown
  error — `authedJson`/`authedRequest` throw an `Error` carrying the
  backend's message verbatim, and every method here lets it propagate
  unchanged so "callers surface `e.message` inline" (file header).
- **member-add-duplicate-is-conflict**: Adding a member already on the
  team MUST surface as a thrown error from a backend 409 — "the backend
  ... guards duplicates (409)" (file header); `teamMembersApi` performs no
  client-side pre-check for this, unlike `teamsApi.create`/`update`'s
  `rethrowConflict` friendly-message mapping.
- **member-types-hand-declared-off-openapi**: `TeamMember` and its request
  bodies MUST be maintained by hand in `team-members.ts` rather than
  generated, because `/api/team/members` "is off the generated OpenAPI
  surface" (file header).

### wire.ts

- **wire-types-mirror-call-sites-only**: `TeamRow`/`TeamCreateBody`/
  `TeamPutBody` MUST carry exactly the fields `teams.ts`'s mappers and call
  sites touch, replacing the hub's generated `SuccessBody<...>`/
  `RequestBody<...>` wrappers so this client does not inherit "adh product
  vocabulary a generic data client must not take on" (file header).
- **team-put-body-is-fully-partial**: `TeamPutBody`'s `name` and `slug`
  MUST both be optional, matching the generic-CRUD backend's
  `createInsertSchema().partial()` PUT contract (`TeamPutBody` comment,
  `teamsApi.update`).

## Appearance

Not applicable — this is domain logic (two typed API clients and their wire
types), not a visual component.

## States

Not applicable — this is domain logic, not a visual component. Its only
observable "states" are the ordinary async-operation states a caller
already handles generically: pending (an awaited call), succeeded, and
failed (a thrown `Error` carrying the backend's message, per the file
headers of both clients).

## Accessibility

Not applicable — this is domain logic, not a visual component. The two
hardcoded strings this component defines (`validateTeamIdentifier`'s error
messages) are plain text handed to a separate rendering layer, which owns
accessibility presentation.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-teams-001 | identifier-validation-shape | `validateTeamIdentifier("com.acme.platform")` | `null` (`teams.test.ts`: "accepts reverse-domain identifiers") |
| hub-domain-teams-002 | identifier-validation-empty-refused | `validateTeamIdentifier("")` | Matches `/required/i` (`teams.test.ts`: "rejects an empty identifier") |
| hub-domain-teams-003 | identifier-validation-shape | `validateTeamIdentifier("platform")` | Matches `/reverse-domain/i` (`teams.test.ts`: "rejects a single-label identifier") |
| hub-domain-teams-004 | team-vocabulary-mapping | `toTeam({id:"1", name:"Platform", slug:"com.acme.platform", createdAt:"c", updatedAt:"u"})` | `t.displayName === "Platform"`, `t.identifier === "com.acme.platform"` (`teams.test.ts`: "renames name→displayName and slug→identifier") |
| hub-domain-teams-005 | team-update-partial-via-compact | `teamsApi.update("1", {displayName: "Renamed", identifier: undefined})` | PUT body `{"name":"Renamed"}` — `slug` key absent, not sent as `undefined` (`teamsApi.update`, `compact`) |
| hub-domain-teams-006 | team-create-conflict-rethrown-friendly | `teamsApi.create({displayName:"X", identifier:"com.acme.x"}, "eco1")` when the backend throws `Error("... already exists")` | Rethrown `Error('A team with identifier "com.acme.x" already exists.')` (`rethrowConflict`) |
| hub-domain-teams-007 | team-list-scoped-to-ecosystem, team-list-sorted-by-display-name | `teamsApi.list("eco1")` over backend rows named `["Beta","Alpha"]` | GET `/api/team/teams?ecosystemId=eco1`; result names `["Alpha","Beta"]` (`teamsApi.list`, `sortByText`) |
| hub-domain-teams-008 | team-get-resolves-null-on-thrown-error | `teamsApi.get("missing")` when the request throws | Resolves to `null`, does not rethrow (`teamsApi.get`) |
| hub-domain-teams-009 | team-delete-issues-delete | `teamsApi.delete("t/1")` | `DELETE /api/team/teams/t%2F1` (`teamsApi.delete`, `enc`) |
| hub-domain-teams-010 | member-list-tolerates-missing-members-key | `teamMembersApi.list("t1")` when the response body is `{}` | Resolves to `[]`, no thrown error (`teamMembersApi.list`) |
| hub-domain-teams-011 | member-list-query-scoped-by-team | `teamMembersApi.list("t1")` | GET `/api/team/members?teamId=t1` (`teamMembersApi.list`) |
| hub-domain-teams-012 | member-counts-maps-team-to-count | `teamMembersApi.counts()` over `{counts:[{teamId:"t1",count:3}]}` | `Map` with `get("t1") === 3` (`teamMembersApi.counts`) |
| hub-domain-teams-013 | member-add-by-email-resolves-existing-customer | `teamMembersApi.add("t1", "a@b.com")` | POST `/api/team/members` with body `{"teamId":"t1","email":"a@b.com"}` (`teamMembersApi.add`) |
| hub-domain-teams-014 | member-add-persona-gated-by-may-act | `teamMembersApi.addPersona("t1", "sales-bot")` | POST `/api/team/members/personas` with body `{"teamId":"t1","personaKey":"sales-bot"}` (`teamMembersApi.addPersona`) |
| hub-domain-teams-015 | member-remove-addresses-member-row | `teamMembersApi.remove("m/1")` | `DELETE /api/team/members/m%2F1` (`teamMembersApi.remove`, `enc`) |
| hub-domain-teams-016 | member-kind-discriminates-customer-vs-persona | A GET row with `memberKind: "elevated"` (an unrecognized value) | Per the type's own doc comment, a consumer MUST treat it as `"customer"`, never as `"persona"` (`TeamMember.memberKind` doc comment) |

## Edge Cases

- **Null/empty input**: An empty `identifier` to `validateTeamIdentifier`
  MUST be refused with `"Identifier is required."` (SHOULD/MUST per
  `identifier-validation-empty-refused`). Neither `add`'s `email` nor
  `addPersona`'s `personaKey` is validated client-side; an empty value is
  sent to the backend unchanged, and whatever the backend does with it (a
  404 or 400) is this client's behavior too — an absent client-side check,
  not a swallowed error (no doc comment or type signature promises one).
- **Boundary/malformed values**: `validateTeamIdentifier` MUST accept the
  minimal two-label form (`"a.b"`) and MUST reject a single label
  (`"platform"`, confirmed by `hub-domain-teams-003`) — the pattern
  requires at least one dot-separated segment after the first label.
- **Concurrent access**: Two closely-timed `teamsApi.create`/`update` calls
  for the same `(owner, slug)` MUST leave exactly one team row and MUST
  present the second caller with the friendly `"already exists"` error via
  `rethrowConflict` (team-create-conflict-rethrown-friendly,
  team-update-conflict-rethrown-friendly). Two closely-timed
  `teamMembersApi.add` calls adding the same customer to the same team MUST
  leave exactly one member row, but — unlike `teamsApi` — the second caller
  sees the backend's RAW 409 message, with no friendly-message mapping
  applied by this client (member-add-duplicate-is-conflict).
- **Error states**: `teamsApi.get` resolves ANY thrown error to `null`,
  not only a 404 (see team-get-swallows-any-error-as-not-found in
  Behavioral Requirements). Every other method on both clients
  (`teamsApi.list`/`create`/`update`/`delete`, all of `teamMembersApi`)
  lets a thrown error propagate unchanged to the caller
  (member-errors-propagate-with-backend-message).
- **Offline/disconnected state**: Neither client implements a timeout,
  retry, backoff, or offline queue; a network failure mid-request surfaces
  identically to any other thrown error — an `Error` with no `.status` —
  through `authedJson`/`authedRequest`, with no built-in recovery in this
  domain's own files (an absent feature, not a swallowed signal, since no
  doc comment or type in this domain promises retry behavior).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ecosystemId` (`teamsApi.list`/`create`) | `string` | required, no default | Scopes the op to that ecosystem's own teams via `?ecosystemId=` |
| `id` (`teamsApi.get`/`update`/`delete`) | `string` | required, no default | The team row's opaque server-generated id |
| `input.displayName`/`input.identifier` (`teamsApi.create`) | `string`/`string` | required, no default | Sent as backend `name`/`slug` |
| `input` (`teamsApi.update`) | `Partial<TeamInput>` | `{}` (all fields optional) | Only defined keys are sent, via `compact` |
| `teamId` (`teamMembersApi.list`/`add`/`addPersona`) | `string` | required, no default | The team a member list is read from or added to |
| `email` (`teamMembersApi.add`) | `string` | required, no default | Resolved to an existing customer within the caller's ecosystem |
| `personaKey` (`teamMembersApi.addPersona`) | `string` | required, no default | One of the caller's own personas; gated on its `may_act` `'team'` grant |
| `memberId` (`teamMembersApi.remove`) | `string` | required, no default | The membership row's own id |

## Deep Linking

Not applicable — this component owns no URL scheme, Android intent filter,
or platform deep-link registration; the `/api/team/*` routes it calls are
HTTP API routes, not front-end deep links.

## Localization

- **Hardcoded English strings**: `validateTeamIdentifier`'s two messages —
  `"Identifier is required."` and `"Use reverse-domain form, e.g.
  com.example.platform."` — and `teamsApi.create`/`update`'s
  `rethrowConflict` message, `A team with identifier "<identifier>" already
  exists.`, are fixed English literals in `teams.ts`.

No file in this domain defines an i18n key, a lookup table, or a locale
parameter — every user-facing string above is plain, fixed English. This is
a plain, honestly-reported fact about the current source, not a hidden gap
(see Compliance).

## Accessibility Options

Not applicable — this component renders no UI and defines no Reduce
Motion, Increase Contrast, or Differentiate-Without-Color behavior.

## Feature Flags

Not applicable — no file in this domain defines or reads a feature-flag
key; every conditional path (customer vs. persona membership, the
may_act-gated `addPersona` refusal) is derived from a caller-supplied
argument or a server-enforced grant, never from a flag this component owns.

## Analytics

Not applicable — no file in this domain emits a client-side analytics or
telemetry event.

## Privacy

- **Data collected**: Team administrative metadata (`displayName`,
  `identifier`) and per-member data — a member's `role`, `addedAt`, and,
  for a customer member, `email`/`displayName` resolved from that
  customer's own row; for a persona member, `personaSlug`/`personaName`.
  `email` is the one field here that directly identifies a person outside
  the platform's own naming.
- **Storage**: This client holds no cache of its own — every call is a
  live round trip through `authedJson`/`authedRequest`. Whatever caching a
  consumer layers on top is outside this domain's files.
- **Transmission**: Every call travels through `authedJson`/
  `authedRequest` (`http.ts`, re-exporting `@agentic-toolkit/auth/client`'s
  Bearer-token client); this domain itself attaches no credential and reads
  no cookie.
- **Retention**: This domain retains nothing between calls; it is a
  stateless set of functions over the network. A removed member
  (`teamMembersApi.remove`) or a deleted team (`teamsApi.delete`) leaves no
  trace in this client — retention of the underlying rows is a backend
  concern this domain's files do not describe.

## Logging

No file in this domain calls a logger, `console.log`, `console.warn`,
`console.error`, or any platform logging API. Every failure this component
detects is either resolved to a documented fallback (`teamsApi.get`'s
`null`) or surfaced to the caller as a thrown `Error`; logging that failure
is the responsibility of the caller or host application, not of this
domain component.

## Platform Notes

- **SwiftUI / AppKit / UIKit**: Not applicable — no Swift declaration
  exists in this domain; there is no Apple-side Teams implementation to
  note concurrency behavior for.
- **React/Web**: This is the sole reference implementation. Both clients
  (`teamsApi`, `teamMembersApi`) are plain objects of `async` functions
  over `fetch` (via `authedJson`/`authedRequest`); neither exports a React
  hook, unlike `hub-domain-ecosystems`'s
  `use-workspace-default-ecosystem.ts` — every export here is
  framework-agnostic and usable from a plain script or a test.
- **Windows / WinUI 3**: No WinUI 3 implementation exists in this domain. A
  port would model `Team`/`TeamMember` as plain records (or `record`
  types), route every call through a shared `HttpClient` with a Bearer
  token attached (the equivalent of `authedJson`/`authedRequest`), use
  `System.Text.Json` for the request/response bodies (mirroring
  `compact`'s undefined-vs-null distinction by only serializing properties
  actually set, e.g. via `JsonIgnoreCondition.WhenWritingNull` combined with
  nullable value types rather than omission), and reproduce
  `teamsApi.get`'s null-on-404 contract with an explicit
  `HttpStatusCode.NotFound` check rather than a bare `catch` — closing the
  gap this recipe flags in the web source
  (team-get-swallows-any-error-as-not-found). `async`/`Task` maps directly
  from this domain's `Promise`-returning methods; no `ObservableCollection`
  or `INotifyPropertyChanged` is needed, since nothing here is observed
  state — every call returns a fresh value.
- **Android**: No Android implementation exists in this domain. A Kotlin
  port would face the identical 404-vs-any-error distinction as WinUI 3
  above (checking the HTTP response code explicitly, e.g. via Retrofit/
  OkHttp, rather than catching every `IOException` alike), and would model
  `compact`'s undefined-vs-null distinction with a `Map<String, Any?>` (or
  a sealed "patch" type) rather than a Kotlin `data class`'s all-or-nothing
  field set, since a `data class` cannot distinguish "not set" from "set to
  null" the way this domain's `Partial<TeamInput>` does.
- **Python**: No Python implementation exists in this domain. A port would
  route calls through a shared `httpx`/`requests` session carrying the
  Bearer token, model `Team`/`TeamMember` as `dataclass`es or Pydantic
  models, and reproduce `compact` with a helper that drops keys whose value
  is a sentinel "unset" (not Python's own `None`, which — as in the
  TypeScript source — must remain sendable as an explicit clear).

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/teams/` |

## Design Decisions

**Decision**: Membership by an existing customer (`add`, by email) and
membership by one of the caller's own personas (`addPersona`, by key) are
two separate methods on two separate routes, rather than one method
branching on a `kind` argument.
**Rationale**: The two paths differ in both lookup (an email resolved
against the caller's ecosystem vs. a key resolved against the caller's own
personas) and authorization (an ordinary team-scope check vs. the
persona's own `may_act` `'team'` grant); collapsing them into one signature
would hide which check applies to a given call (file header: "added by
EMAIL, resolved to a customer in the ecosystem — 404 if none... or one of
the caller's personas (added by key, gated on the persona's may_act 'team'
grant)").
**Approved**: pending

**Decision**: `teams.ts` (generic CRUD) maps through a `wire.ts` row type
and a `toTeam` mapper; `team-members.ts` (a hand-written route) declares
`TeamMember` directly, with no separate wire row or mapper.
**Rationale**: The generic-CRUD backend's column names (`name`, `slug`)
differ from the UI's vocabulary (`displayName`, `identifier`), so `teams.ts`
needs a translation layer. The hand-written `/api/team/members` route "is
off the generated OpenAPI surface" and was written to match the UI's
vocabulary directly, so there is no generated row to diverge from and
nothing to translate (file headers of both files).
**Approved**: pending

**Decision**: `teamsApi.create`/`update` perform no pre-read for a
duplicate identifier before writing; the backend's unique `(owner, slug)`
constraint is the only guard, translated to a friendly message via
`rethrowConflict` only after the backend rejects the write.
**Rationale**: A pre-read is racy under concurrent writers and "can't see a
soft-deleted row still holding the slug" — the database constraint is the
one place that can answer "is this slug free" correctly (`teamsApi.create`
inline comment).
**Approved**: pending

**Decision**: `ecosystemId` is a required argument on `teamsApi.list`/
`create`, resolved by the caller (via `hub-domain-ecosystems`'s
`ecosystemIdForSlug`), rather than looked up inside this domain.
**Rationale**: A team's owning ecosystem is "the workspace's ecosystem",
and the slug-to-id resolution is `hub-domain-ecosystems`'s own concern; had
`teams.ts` performed that lookup itself, it would take on a dependency on
another domain's data shape instead of accepting the id its caller already
has (file header: "The caller resolves the id with
`ecosystemsApi.ecosystemIdForSlug(slug)`").
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [api-design-conventions](agenticdevelopercookbook://compliance/access-patterns#api-design-conventions) | partial | access-patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | failed | reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | passed | security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | security |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | security |

Every logic component in this cookbook is held to at least
`separation-of-concerns` and `unit-test-coverage`. **`separation-of-concerns`**
passes: `teams.ts` owns the `Team` route stem, `team-members.ts` owns the
membership route stem, and `wire.ts` is a type-only file the other two read
— no file reaches into another's internals. **`unit-test-coverage`** is
`partial`: `teams.test.ts` exercises `toTeam` and `validateTeamIdentifier`
directly (the vectors above traced to its three assertions), but no test
file exists for `team-members.ts` at all — every `teamMembersApi` behavior
in this recipe is traced to the source code and its doc comments, not to a
test assertion. **`api-design-conventions`** is `partial`: the domain does
not follow one uniform client shape end to end — `teamsApi` maps through a
`wire.ts` row and a `toX` mapper and translates a 409 to a friendly message
on write, while `teamMembersApi` declares its type directly with no mapper
and no friendly-message translation on a duplicate-member 409 (see Design
Decisions for why the divergence is deliberate; the asymmetry itself is
real, not invented). **`idempotent-operations`** is `failed`, honestly:
neither `teamsApi.create`/`update` nor `teamMembersApi.add`/`addPersona` is
idempotent — a retry of a write that already succeeded server-side (e.g.
after a dropped response) hits a 409 conflict rather than transparently
returning the existing row, unlike the idempotent-per-triple pattern the
sibling `hub-domain-projects` recipe documents for `artifacts.link`.
**`error-recovery`** is `partial`: `teamsApi.get`'s 404 recovers to a
documented `null`, but (a) that recovery is over-broad — see
team-get-swallows-any-error-as-not-found — and (b) no method on either
client retries or backs off a transient failure. **`no-hardcoded-strings`**
is `failed`: `validateTeamIdentifier`'s two messages and the
`rethrowConflict` friendly-conflict message are fixed English literals with
no i18n key anywhere in these files (see Localization). **`secure-transport`**
passes: every call goes through `authedJson`/`authedRequest`'s Bearer-token
client, and this domain attaches no credential or cookie of its own.
**`secure-log-output`** passes because there is no logging at all in this
domain (see Logging). **`server-side-authorization`** passes: this domain
never attempts its own authorization check — team owner/admin scope and
the persona `may_act` `'team'` grant are both enforced entirely by the
backend, and this client only surfaces the resulting 403/404 (file headers
of both `teams.ts` and `team-members.ts`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe: the Teams domain — team CRUD scoped to an ecosystem, and membership by customer email or grant-gated persona key. |
