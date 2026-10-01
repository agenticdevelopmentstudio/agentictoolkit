---
id: 28581588-68f5-465d-8e8e-3aaaaef00560
title: Teams
domain: agentictoolkit://cookbook/adh/hub/teams
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Team domain logic: a generic-CRUD team client scoped to an ecosystem, and a
  hand-written team-membership client for members added by customer email or by a
  grant-gated persona key.'
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
- agentictoolkit://cookbook/adh/hub/ecosystems/ecosystems
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

# Teams

## Overview

This is the Teams domain: the non-UI logic for a *team* (a named group
owned by an ecosystem) and its membership. There is no separate
implementation for another platform — this is a single reference
implementation split across two clients that sit on two different kinds of
backend route:

- a **team client** — provides mapping and validation helpers plus CRUD.
  The team row itself is generic CRUD, so this client's whole job is
  translating between the backend's column names and the UI's vocabulary
  and scoping every request to the calling workspace's owning ecosystem.
- a **team-membership client** — membership is a hand-written backend
  route (`/api/team/members`, "off generic CRUD"), off the generated
  OpenAPI surface, because a member is one of two different kinds of
  thing — an existing customer added by email, or one of the caller's
  personas added by a grant-gated key — and no generic CRUD table models
  that choice.
- a **shared wire-shapes module** — the backend row and request-body
  shapes the team client's mapper and call sites read and write; type-only,
  and deliberately narrower than the hub's generated success/request-body
  wrappers so this client does not take on "adh product vocabulary a
  generic data client must not take on" (the source's own header comment).
- a **public surface** — re-exports both clients' exports.

Both clients share the transport and shaping conventions documented once
here: a shared authenticated-request helper (a Bearer-token client) throws
an error carrying the backend's message on failure, and every method here
lets that error propagate to the caller except the team client's
single-item fetch, which resolves to `null` instead. A shared
field-compaction helper drops only `undefined` keys from a PATCH/PUT body,
preserving an explicit `null`.

## Behavioral Requirements

### Team client

- **team-vocabulary-mapping**: Mapping a backend team row to its UI shape
  MUST map the row's `name` column to the UI's `displayName` field and
  `slug` to the UI's `identifier` field, passing `id`, `createdAt`, and
  `updatedAt` through unchanged.
- **team-identifier-is-reverse-domain**: A team's `identifier` MUST be a
  reverse-domain string, e.g. `com.example.platform`.
- **identifier-validation-empty-refused**: Validating a team identifier
  MUST return `"Identifier is required."` for an empty identifier, checked
  before the shape rule.
- **identifier-validation-shape**: Validating a team identifier MUST
  return `"Use reverse-domain form, e.g. com.example.platform."` for a
  non-empty identifier that fails the pattern one lowercase-alphanumeric
  label followed by one or more dot-separated lowercase-alphanumeric-or-
  hyphen labels, and MUST return `null` when the identifier passes.
- **team-list-scoped-to-ecosystem**: Listing teams for an ecosystem MUST
  send `GET /api/team/teams?ecosystemId=<encoded ecosystemId>`; the
  backend then returns ONLY that ecosystem's teams, enforced even for an
  admin caller.
- **team-list-sorted-by-display-name**: Listing teams MUST return teams
  sorted by `displayName` via a locale-aware text comparison, never in the
  backend's raw row order.
- **team-get-resolves-null-on-thrown-error**: Fetching a single team by id
  MUST resolve to `null` rather than rethrow when the underlying request
  throws — the backend responds 404 with a thrown error; the UI contract
  is null-for-missing.
- **team-get-swallows-any-error-as-not-found**: NEEDS REVIEW: Not
  implemented in source. Fetching a single team by id's catch block
  returns `null` for ANY thrown error, not only the backend's documented
  404, so a network failure or a server error is indistinguishable from a
  team that genuinely does not exist, and no signal (a rethrow, a log
  call) reaches the caller to tell the two apart; settled by narrowing the
  catch to a 404-status check and rethrowing everything else, or by an
  operator-visible log of the swallowed error.
- **team-create-no-pre-read-relies-on-backend-constraint**: Creating a
  team MUST NOT pre-read for a duplicate identifier before submitting the
  create — the backend's unique owner/slug constraint is the sole guard,
  because a pre-read can't see a soft-deleted row still holding the slug.
- **team-create-scopes-into-ecosystem**: Creating a team MUST send the
  create request to `/api/team/teams?ecosystemId=<encoded ecosystemId>`,
  stamping the new team into that ecosystem so it lands in — and is
  visible under — the workspace it was created in.
- **team-create-conflict-rethrown-friendly**: On a conflict response whose
  message matches "already exists" (case-insensitive), creating a team
  MUST rethrow via the shared conflict-translation helper as `A team with
  identifier "<identifier>" already exists.`; any other error MUST
  rethrow unchanged.
- **team-update-partial-via-compact**: Updating a team MUST send only the
  defined optional keys of `{name, slug}` through the shared
  field-compaction helper — an omitted (unset) field MUST be dropped from
  the update body.
- **team-update-conflict-rethrown-friendly**: Updating a team MUST
  rethrow a conflict response for a slug collision via the shared
  conflict-translation helper with the same friendly-message shape as
  creating a team, because a slug rename can collide with the unique
  owner/slug index.
- **team-delete-issues-delete**: Deleting a team MUST send `DELETE
  /api/team/teams/<encoded id>` and resolve with no value on success.
- **team-row-id-is-opaque**: A team's `id` MUST be treated as an opaque,
  server-generated identifier, never derived or parsed by this client.

### Team-membership client

- **member-kind-discriminates-customer-vs-persona**: A member's
  `memberKind` MUST be read as `"customer"` for any value other than the
  literal `"persona"` — present on every listing row; treat anything other
  than `"persona"` as a customer (robust to the field still being optional
  in the wire shape).
- **member-email-null-outside-ecosystem**: A member's `email` MUST be
  `null` when the member's customer row lies outside the caller's
  ecosystem, and MUST be non-null only when resolved from a customer row
  within it.
- **member-persona-fields-null-for-customers**: A member's `personaSlug`
  and `personaName` MUST be set only for a persona member and MUST be
  `null` for a customer member.
- **member-list-tolerates-missing-members-key**: Listing members MUST
  return an empty array when the response body carries no `members` key,
  rather than dereferencing an absent value — tolerating a body without
  `members` (the route always sends it, but a proxy/error page might not).
- **member-list-query-scoped-by-team**: Listing members for a team MUST
  send `GET /api/team/members?teamId=<encoded teamId>`.
- **member-counts-maps-team-to-count**: Fetching member counts MUST return
  a map keyed by team id to that team's member count within the caller's
  scope, built from `GET /api/team/members/counts`, and MUST default to an
  empty map when the response carries no `counts` array.
- **member-counts-is-unreferenced-but-retained**: Fetching member counts
  MUST remain in this client even though nothing in the fleet calls it
  now — the backend route it wraps is live, and this client mirrors the
  backend's surface, not the current callers'; it MUST be deleted only
  together with the route it wraps, never before.
- **member-add-by-email-resolves-existing-customer**: Adding a member by
  email MUST send a create request with `{teamId, email}` to
  `/api/team/members`, adding an EXISTING customer resolved by email
  within the caller's ecosystem — never creating a new customer; the
  backend responds 404 when none resolves.
- **member-add-persona-gated-by-may-act**: Adding a member by persona key
  MUST send a create request with `{teamId, personaKey}` to
  `/api/team/members/personas`, and the backend MUST refuse the call (403)
  unless the named persona has been granted the "team" action-permission.
- **member-remove-addresses-member-row**: Removing a member MUST send
  `DELETE /api/team/members/<encoded memberId>`, addressing the MEMBER
  row's own id — not the team id, nor the underlying user's or persona's
  id.
- **member-errors-propagate-with-backend-message**: Listing members,
  fetching counts, adding a member by email, adding a member by persona,
  and removing a member MUST NOT catch or transform a thrown error — the
  shared request helper throws an error carrying the backend's message
  verbatim, and every method here lets it propagate unchanged so callers
  surface that message inline.
- **member-add-duplicate-is-conflict**: Adding a member already on the
  team MUST surface as a thrown error from a backend conflict response —
  the backend guards duplicates; this client performs no client-side
  pre-check for this, unlike the team client's create/update
  friendly-message mapping.
- **member-types-hand-declared-off-openapi**: A member record and its
  request bodies MUST be maintained by hand in this client rather than
  generated, because the membership route is off the generated OpenAPI
  surface.

### Shared wire shapes

- **wire-types-mirror-call-sites-only**: The backend row and request-body
  shapes MUST carry exactly the fields the team client's mappers and call
  sites touch, replacing the hub's generated success/request-body
  wrappers so this client does not inherit "adh product vocabulary a
  generic data client must not take on."
- **team-put-body-is-fully-partial**: The update-request body's `name` and
  `slug` MUST both be optional, matching the generic-CRUD backend's
  partial-schema PUT contract.

## Appearance

Not applicable — this is domain logic (two typed API clients and their wire
types), not a visual component.

## States

Not applicable — this is domain logic, not a visual component. Its only
observable "states" are the ordinary async-operation states a caller
already handles generically: pending (an awaited call), succeeded, and
failed (a thrown error carrying the backend's message).

## Accessibility

Not applicable — this is domain logic, not a visual component. The two
hardcoded strings this component defines (the identifier-validation
operation's error messages) are plain text handed to a separate rendering
layer, which owns accessibility presentation.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-teams-001 | identifier-validation-shape | Validating the identifier `"com.acme.platform"`. | `null` — accepts reverse-domain identifiers, verified by an existing test in the source. |
| hub-domain-teams-002 | identifier-validation-empty-refused | Validating the empty identifier `""`. | Matches `/required/i` — rejects an empty identifier, verified by an existing test in the source. |
| hub-domain-teams-003 | identifier-validation-shape | Validating the identifier `"platform"`. | Matches `/reverse-domain/i` — rejects a single-label identifier, verified by an existing test in the source. |
| hub-domain-teams-004 | team-vocabulary-mapping | Mapping the backend row `{id:"1", name:"Platform", slug:"com.acme.platform", createdAt:"c", updatedAt:"u"}` to its UI shape. | `displayName === "Platform"`, `identifier === "com.acme.platform"` — renames name→displayName and slug→identifier, verified by an existing test in the source. |
| hub-domain-teams-005 | team-update-partial-via-compact | Updating team `"1"` with `{displayName: "Renamed", identifier: undefined}`. | The update body is `{"name":"Renamed"}` — the `slug` key is absent, not sent as `undefined`. |
| hub-domain-teams-006 | team-create-conflict-rethrown-friendly | Creating a team `{displayName:"X", identifier:"com.acme.x"}` in ecosystem `"eco1"` when the backend throws an error matching "... already exists". | Rethrown as `A team with identifier "com.acme.x" already exists.` |
| hub-domain-teams-007 | team-list-scoped-to-ecosystem, team-list-sorted-by-display-name | Listing teams for ecosystem `"eco1"` over backend rows named `["Beta","Alpha"]`. | `GET /api/team/teams?ecosystemId=eco1`; result names `["Alpha","Beta"]`. |
| hub-domain-teams-008 | team-get-resolves-null-on-thrown-error | Fetching team `"missing"` when the request throws. | Resolves to `null`, does not rethrow. |
| hub-domain-teams-009 | team-delete-issues-delete | Deleting team `"t/1"`. | `DELETE /api/team/teams/t%2F1` (percent-encoded). |
| hub-domain-teams-010 | member-list-tolerates-missing-members-key | Listing members of team `"t1"` when the response body is `{}`. | Resolves to `[]`, no thrown error. |
| hub-domain-teams-011 | member-list-query-scoped-by-team | Listing members of team `"t1"`. | `GET /api/team/members?teamId=t1`. |
| hub-domain-teams-012 | member-counts-maps-team-to-count | Fetching member counts over `{counts:[{teamId:"t1",count:3}]}`. | A map with `get("t1") === 3`. |
| hub-domain-teams-013 | member-add-by-email-resolves-existing-customer | Adding member `"a@b.com"` to team `"t1"` by email. | `POST /api/team/members` with body `{"teamId":"t1","email":"a@b.com"}`. |
| hub-domain-teams-014 | member-add-persona-gated-by-may-act | Adding persona `"sales-bot"` to team `"t1"`. | `POST /api/team/members/personas` with body `{"teamId":"t1","personaKey":"sales-bot"}`. |
| hub-domain-teams-015 | member-remove-addresses-member-row | Removing member `"m/1"`. | `DELETE /api/team/members/m%2F1` (percent-encoded). |
| hub-domain-teams-016 | member-kind-discriminates-customer-vs-persona | A listing row with `memberKind: "elevated"` (an unrecognized value). | Per the field's own documented contract, a consumer MUST treat it as `"customer"`, never as `"persona"`. |

## Edge Cases

- **Null/empty input**: An empty `identifier` MUST be refused with
  `"Identifier is required."` (MUST, `identifier-validation-empty-refused`).
  Neither adding a member by email's `email` nor adding a member by
  persona key's `personaKey` is validated client-side; an empty value is
  sent to the backend unchanged, and whatever the backend does with it (a
  404 or 400) is this client's behavior too — an absent client-side
  check, not a swallowed error (no documented contract promises one).
- **Boundary/malformed values**: Validating a team identifier MUST accept
  the minimal two-label form (`"a.b"`) and MUST reject a single label
  (`"platform"`, confirmed by Conformance Test Vector 003) — the pattern
  requires at least one dot-separated segment after the first label.
- **Concurrent access**: Two closely-timed create/update calls for the
  same owner/slug MUST leave exactly one team row and MUST present the
  second caller with the friendly "already exists" error via the shared
  conflict-translation helper (`team-create-conflict-rethrown-friendly`,
  `team-update-conflict-rethrown-friendly`). Two closely-timed add-member
  calls adding the same customer to the same team MUST leave exactly one
  member row, but — unlike the team client — the second caller sees the
  backend's RAW conflict message, with no friendly-message mapping
  applied by this client (`member-add-duplicate-is-conflict`).
- **Error states**: Fetching a single team by id resolves ANY thrown error
  to `null`, not only a 404 (see `team-get-swallows-any-error-as-not-found`
  in Behavioral Requirements). Every other method on both clients (listing/
  create/update/delete for teams, all of the team-membership client) lets
  a thrown error propagate unchanged to the caller
  (`member-errors-propagate-with-backend-message`).
- **Offline/disconnected state**: Neither client implements a timeout,
  retry, backoff, or offline queue; a network failure mid-request surfaces
  identically to any other thrown error — an error with no status —
  through the shared request helper, with no built-in recovery in this
  domain's own files (an absent feature, not a swallowed signal, since no
  documented contract in this domain promises retry behavior).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ecosystemId` (listing/creating a team) | `string` | required, no default | Scopes the op to that ecosystem's own teams via `?ecosystemId=` |
| `id` (fetching/updating/deleting a team) | `string` | required, no default | The team row's opaque server-generated id |
| `input.displayName`/`input.identifier` (creating a team) | `string`/`string` | required, no default | Sent as backend `name`/`slug` |
| `input` (updating a team) | partial team-input object | `{}` (all fields optional) | Only defined keys are sent, via the shared field-compaction helper |
| `teamId` (listing/adding members) | `string` | required, no default | The team a member list is read from or added to |
| `email` (adding a member by email) | `string` | required, no default | Resolved to an existing customer within the caller's ecosystem |
| `personaKey` (adding a member by persona) | `string` | required, no default | One of the caller's own personas; gated on its "team" action-permission grant |
| `memberId` (removing a member) | `string` | required, no default | The membership row's own id |

## Deep Linking

Not applicable — this component owns no URL scheme, Android intent filter,
or platform deep-link registration; the `/api/team/*` routes it calls are
HTTP API routes, not front-end deep links.

## Localization

- **Hardcoded English strings**: the identifier-validation operation's two
  messages — `"Identifier is required."` and `"Use reverse-domain form,
  e.g. com.example.platform."` — and the team client's create/update
  conflict-translation message, `A team with identifier "<identifier>"
  already exists.`, are fixed English literals in this domain's source.

No file in this domain defines an i18n key, a lookup table, or a locale
parameter — every user-facing string above is plain, fixed English. This is
a plain, honestly-reported fact about the current source, not a hidden gap
(see Compliance).

## Accessibility Options

Not applicable — this component renders no UI and defines no
reduced-motion, increased-contrast, or color-differentiation behavior.

## Feature Flags

Not applicable — no file in this domain defines or reads a feature-flag
key; every conditional path (customer vs. persona membership, the
grant-gated persona-add refusal) is derived from a caller-supplied
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
  live round trip through the shared request helper. Whatever caching a
  consumer layers on top is outside this domain's files.
- **Transmission**: Every call travels through the shared
  authenticated-request helper (a Bearer-token client); this domain itself
  attaches no credential and reads no cookie.
- **Retention**: This domain retains nothing between calls; it is a
  stateless set of functions over the network. A removed member or a
  deleted team leaves no trace in this client — retention of the
  underlying rows is a backend concern this domain's files do not
  describe.

## Logging

No file in this domain calls a logger or any platform logging API. Every
failure this component detects is either resolved to a documented
fallback (fetching a single team's `null`) or surfaced to the caller as a
thrown error; logging that failure is the responsibility of the caller or
host application, not of this domain component.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe: the Teams domain — team CRUD scoped to an ecosystem, and membership by customer email or grant-gated persona key. |
