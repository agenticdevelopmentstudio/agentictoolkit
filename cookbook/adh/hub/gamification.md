---
id: cef42b4b-e10e-4816-b1f8-0156699bec21
title: Gamification
domain: agentictoolkit://cookbook/adh/hub/gamification
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Owner/admin-scoped domain logic for one ecosystem's gamification realm
  — its configuration, effective catalog, badge and event-type management,
  level-ladder replacement, and replay.
platforms:
- typescript
- web
tags:
- hub
- gamification
- realm-config
- badges
- levels
- event-types
depends-on: []
related:
- agentictoolkit://cookbook/adh/hub/ecosystems/ecosystem-config
references:
- packages/web/packages/data/src/gamification/gamification.ts (agentictoolkit)
- packages/web/packages/data/src/gamification/wire.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Gamification

## Overview

This component is the gamification realm client: the owner/admin-scoped
data layer for ONE ecosystem's gamification "realm" — its configuration
(mode, skin, per-surface toggles, seasons, timezone), its effective catalog
(platform-default badges and level rungs merged with the realm's own
overrides), realm-owned badge management, wholesale level-ladder
replacement, a manual replay trigger, and realm custom event-type
management. This logic backs the per-product Gamification panes — a
single settings pane and a four-topic rail alike — reaching the backend's
realm-config route family (and a sibling replay route) through a host
proxy. This is a **logic** component: it renders nothing — it is a plain
request-based client and its wire shapes, consumed by separate UI panes
that are not part of this component's given sources.

## Behavioral Requirements

### Module-wide

- **wire-types-own-transcription**: every type this component imports and
  re-exports for the wire (the realm configuration record and its update
  input/result, the effective catalog and its badge/level entries, a realm
  badge record and its input, a level-ladder replacement input/result and
  level rung, a replay result, a realm event-type record and its input, a
  seasons window value, the gaming mode) MUST be this component's own
  transcription, never a dependency on a generated, product-specific
  vocabulary — a generic data client does not take a dependency on that
  vocabulary.
- **path-segment-encoding**: every dynamic path segment (an ecosystem id,
  or a badge/event-type id) MUST be URL-encoded before being interpolated
  into a request path.
- **api-proxy-path-prefix**: every request path this component builds
  MUST begin with the fixed `/api/gamification/` prefix, matching the
  host's generic API proxy that forwards to the backend's
  `/gamification/...` routes.
- **stateless-module**: this component MUST hold no instance- or
  module-level mutable state between calls; every operation's request
  MUST be built solely from the arguments passed to that call.
- **no-response-caching**: no operation MUST cache a prior response;
  every call MUST issue a fresh request.
- **error-propagation-unmodified**: no operation MUST catch, transform,
  or discard a failure from the underlying request; every operation's
  result MUST fail with whatever error the underlying request raised,
  unmodified — no operation itself attempts to handle that failure.

### Realm Config

- **realm-config-read**: reading a realm's configuration MUST issue a
  read to the realm-config route and resolve with the realm configuration
  record; this read is admin/owner-gated.
- **realm-config-partial-update-optionality**: updating a realm's
  configuration MUST issue a write to the realm-config route with the
  given update input as the body; every field of that input (`mode`,
  `skin`, `surfaces`, `seasons`, `timezone`) MUST be optional, so a caller
  may send any subset without the others.
- **realm-config-update-always-returns-config**: a configuration update's
  result MUST always carry the resulting realm configuration record,
  regardless of whether a replay occurred.
- **realm-config-mode-ordered-axis**: the gaming mode MUST be treated as
  one ordered axis, not a set of mutually exclusive alternatives —
  `'game'` INCLUDES everything `'gamification'` gives; it is a superset,
  not an alternative. A check for whether gaming is on at all MUST test
  the mode is not `'none'`; a check for a game-specific surface MUST test
  the mode equals `'game'`.
- **realm-config-surfaces-default-on**: each per-surface toggle MUST be
  treated as enabled unless that key is explicitly set to `false` — a
  surface is on unless set false.
- **realm-config-seasons-nullable-window**: a seasons value, whether read
  or written, MUST accept `null` to mean seasons are off, and MUST accept
  an object of `{ anchor: string, lengthDays: number }` to mean an active
  season window.
- **realm-config-replay-on-enable**: a configuration update's result MUST
  carry a `replayed` field only when the applied update raised the mode
  from `'none'` to either `'gamification'` or `'game'`, triggering a
  retroactive replay; that field MUST be absent for every other update.

### Catalog

- **catalog-effective-merge**: reading the effective catalog MUST issue a
  read to the catalog route and resolve with badge and level lists that
  are the platform's defaults merged with the realm's own overrides — the
  EFFECTIVE catalog, not the realm's overrides alone.
- **catalog-default-rows-read-only**: every catalog badge/level entry
  MUST carry a `source` of `"default"` or `"realm"`; a `source: "default"`
  row MUST be treated as read-only — only a `source: "realm"` row is
  editable or deletable.

### Badges

- **badge-create**: creating a realm badge MUST issue a create request to
  the badges route with the given input as the body and resolve with the
  created badge record; an invalid body answers a validation failure.
- **badge-input-required-field-set**: a badge create/update input MUST
  require `name`, `description`, `icon`, `statKey`, `comparator`,
  `threshold`, `badgeLine`, `tier`, `pointValue`, and `hidden` as
  non-optional values on every create or update — every field required
  by the schema — even though the corresponding fields on the read
  record (`statKey`, `comparator`, `threshold`, `badgeLine`, `tier`) are
  optional and nullable on read.
- **badge-input-omits-read-only-fields**: a badge create/update input
  MUST NOT declare an `active`, `subjectType`, or `ecosystemId` property
  — all three are declared only on the read record — so creating or
  updating a badge gives a caller no way to set a badge's active flag,
  subject type, or ownership directly.
- **badge-tier-line-override-key**: a realm badge overrides the same
  `(badgeLine, tier)` default — the pair of `badgeLine` and `tier` is the
  override key against the platform's default catalog, not an id or a
  name.
- **badge-update-excludes-defaults**: updating a realm badge MUST issue a
  write to the item's badge route with the given input as the body and
  resolve with the updated badge record; this call answers not-found for
  a platform-default badge (one whose `ecosystemId` is `null`).
- **badge-delete-clears-holdings-first**: deleting a realm badge MUST
  issue a delete request to the item's badge route and resolve with a
  `{ deleted: <id> }` result; deleting a realm-owned badge clears its
  holdings first, and MUST NOT succeed against a platform default
  (not-found).

### Levels

- **levels-replace-wholesale**: replacing a realm's level ladder MUST
  issue a write to the levels route with a body of exactly `{ rungs }`
  and resolve with a level-replacement result; this call replaces the
  entire ladder, never a partial merge.
- **levels-ladder-shape-enforced-serverside**: the sent rungs must start
  at 0 and be strictly increasing, else the request fails; the client
  performs no runtime check of that shape itself — enforcement is
  documented as the backend's, surfaced to the caller per
  **error-propagation-unmodified**.
- **levels-update-replay-hint**: a level-replacement result MUST carry
  the replaced level list plus a hint string that the owner may trigger a
  replay to backfill retroactively.

### Replay

- **replay-scoping-via-body**: triggering a replay MUST issue a create
  request to the fixed replay route (which takes no ecosystem-id segment)
  with a body of exactly `{ ecosystemId: <id> }`, and resolve with a
  replay result — the only one of this component's operations that
  carries its ecosystem scope in the body rather than the route.
- **replay-result-single-subject-fields**: a replay result's subject
  count MUST be `1` for a single-subject replay; its badge count MUST
  count newly-granted badges across the replayed subject(s); its
  points-gained field MUST be present only for a single-subject replay.

### Event Types

- **event-types-list-name-ordered**: listing a realm's event types MUST
  issue a read to the event-types route and resolve with a name-ordered
  list; this operation performs no sort of its own — ordering is
  produced server-side.
- **event-type-create**: creating an event type MUST issue a create
  request to the event-types route with the given input as the body and
  resolve with the created record; a bad input answers a validation
  failure and a duplicate name answers a conflict.
- **event-type-update**: updating an event type MUST issue a write to
  the item's event-type route with the given input as the body and
  resolve with the updated record; a foreign realm's row answers
  not-found and a colliding rename answers a conflict.
- **event-type-delete**: deleting an event type MUST issue a delete
  request to the item's event-type route and resolve with a
  `{ deleted: <id> }` result; a foreign realm's row or an unknown id
  answers not-found.
- **event-type-input-length-precondition**: an event-type input's `name`
  and `statKey` MUST both be required and bounded to at most 64
  characters — a documented caller precondition that creating/updating
  an event type does not check itself, since a bad input's rejection is
  the backend's to raise.

## Appearance

Not applicable — this is a data client, not a visual component.

## States

Not applicable — this is a data client, not a visual component. The
gaming mode's three values (`'none'`, `'gamification'`, `'game'`)
describe realm-configuration data this client transports, not a runtime
state machine of the client itself; see **realm-config-mode-ordered-axis**
under Behavioral Requirements.

## Accessibility

Not applicable — this is a data client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| gamification-001 | wire-types-own-transcription | Read this component's own import list for its wire types | Every wire type comes from this component's own transcription; none is imported from a generated, product-specific vocabulary package |
| gamification-002 | path-segment-encoding, api-proxy-path-prefix | Build the realm-config route for ecosystem id `"eco/1"`, and the item badge route for ecosystem id `"eco 1"` and badge id `"b#1"` | `"/api/gamification/realms/eco%2F1/config"`; `"/api/gamification/realms/eco%201/badges/b%231"` |
| gamification-003 | stateless-module, no-response-caching | Read the same realm's configuration twice in a row, with the underlying request mocked to answer a different value each time | Two separate requests fire; the second resolved value differs from the first |
| gamification-004 | error-propagation-unmodified | The underlying request is mocked to fail with a conflict ("already exists") while creating an event type | The operation fails with that same error, unmodified |
| gamification-005 | realm-config-read | Read ecosystem `"org.acme.shop"`'s configuration, with the underlying request mocked to resolve a configuration record (mode `"none"`, skin `"plain"`, no surface overrides, no season, timezone `"UTC"`) | A read to the realm-config route for that ecosystem; resolves with that same record |
| gamification-006 | realm-config-partial-update-optionality, realm-config-update-always-returns-config | Update ecosystem `"eco-1"`'s configuration with only a timezone of `"America/New_York"` | A write to the realm-config route with a body containing only the timezone field; the resolved result's configuration field is present |
| gamification-007 | realm-config-mode-ordered-axis | Compare a configuration whose mode is `"game"` against one whose mode is `"gamification"` | Both report gaming is on; only the first reports the game-specific surface is on |
| gamification-008 | realm-config-surfaces-default-on | A configuration whose only surface override is `leaderboard: false` | An absent surface key (e.g. `badges`) reads as enabled; only `leaderboard` reads as off |
| gamification-009 | realm-config-seasons-nullable-window | Update `"eco-1"`'s configuration with a seasons value of `null`, then again with a seasons value of `{ anchor: "2026-01-01", lengthDays: 30 }` | The first write's body carries a null seasons value; the second carries that season-window object |
| gamification-010 | realm-config-replay-on-enable | Update `"eco-1"`'s configuration to mode `"gamification"`, with the underlying request mocked to resolve a configuration plus a replay summary (1 subject, 2 badges, 50 points) | The resolved result's replay field equals that summary |
| gamification-011 | catalog-effective-merge, catalog-default-rows-read-only | Read ecosystem `"eco-1"`'s effective catalog, with the underlying request mocked to resolve badge/level rows tagged `"default"` and `"realm"` | The resolved catalog preserves each row's source tag unchanged |
| gamification-012 | badge-create, badge-input-required-field-set | Create a badge for `"eco-1"` with name `"Streaker"`, description `"7-day streak"`, icon `"fire"`, statKey `"streak_days"`, comparator `">="`, threshold `7`, badgeLine `"streak"`, tier `"bronze"`, pointValue `50`, hidden `false` | A create request to the badges route with a body containing exactly those ten fields |
| gamification-013 | badge-input-omits-read-only-fields | Inspect the badge create/update input's field set | No `active`, `subjectType`, or `ecosystemId` field, though the read record declares all three |
| gamification-014 | badge-tier-line-override-key | The documented override contract for creating a realm badge | A realm badge overrides the same (badgeLine, tier) default |
| gamification-015 | badge-update-excludes-defaults, badge-delete-clears-holdings-first | The documented behavior for updating and for deleting a realm badge | Updating answers not-found for a platform default; deleting clears its holdings first and likewise answers not-found for a default |
| gamification-016 | levels-replace-wholesale | Replace `"eco-1"`'s level ladder with two rungs: `{ name: "Novice", minPoints: 0 }`, `{ name: "Pro", minPoints: 500 }` | A write to the levels route with a body of exactly `{ rungs: [those two entries] }` |
| gamification-017 | levels-ladder-shape-enforced-serverside | The documented shape constraint on the rungs a level-replacement sends | Rungs must start at 0 and be strictly increasing; no runtime check of the array happens client-side |
| gamification-018 | levels-update-replay-hint | The underlying request is mocked to resolve a level list plus the hint string `"trigger a replay to backfill"` for a level replacement | The resolved result's hint field equals that string |
| gamification-019 | replay-scoping-via-body | Trigger a replay for `"eco-1"` | A create request to the fixed replay route (no `"eco-1"` in the route) with a body of exactly `{ ecosystemId: "eco-1" }` |
| gamification-020 | replay-result-single-subject-fields | The underlying request is mocked to resolve `{ subjects: 1, badges: 3, xpGained: 120 }` for a replay | The resolved replay result carries all three fields |
| gamification-021 | event-types-list-name-ordered | List `"eco-1"`'s event types, with the underlying request mocked to resolve a name-ordered list | Resolves with that same list, in the same order; no sort is performed client-side |
| gamification-022 | event-type-create, event-type-input-length-precondition | Create an event type for `"eco-1"` with name `"level_up"`, statKey `"levels_gained"` | A create request to the event-types route with that body; no client-side length/presence check performed |
| gamification-023 | event-type-update | Update event type `"et-1"` for `"eco-1"` with name `"level_up_v2"`, statKey `"levels_gained"` | A write to that item's event-type route with that body |
| gamification-024 | event-type-delete | Delete event type `"et-1"` for `"eco-1"` | A delete request to that item's event-type route, resolving `{ deleted: "et-1" }` |

## Edge Cases

- **Empty ecosystem-id string**: URL-encoding an empty string yields an
  empty string, producing a request path with a doubled slash (e.g. the
  realm-config route with no id segment); none of this component's
  operations reject an empty ecosystem id before building that path.
  MUST.
- **Empty badge/event-type id string**: the same doubling occurs in the
  item routes' second segment; neither updating/deleting a badge nor
  updating/deleting an event type rejects an empty id before building the
  path. MUST.
- **Fully-omitted update body**: updating a realm's configuration with an
  empty input sends a write with an empty-object body; every
  configuration-input field being optional means an all-omitted input is
  not rejected client-side. MUST.
- **Empty rungs list**: replacing a realm's level ladder with an empty
  list sends a body of `{ rungs: [] }`, which violates the documented
  "must start at 0" shape; the client performs no check for this and
  relies entirely on the backend's rejection. MUST.
- **Boundary season length (1 and 366 days)**: a season window's length
  is documented as bounded to `1..366` days; the client passes whatever
  numeric value the caller supplies with no client-side range check.
  MUST.
- **Boundary event-type field length (64 characters)**: an event-type
  input's `name`/`statKey` fields are documented as bounded to at most
  64 characters; same, unchecked client-side. MUST.
- **Concurrent calls**: this component holds no shared state between
  calls (**stateless-module**), so two concurrent calls — even to the
  same operation and ecosystem id — MUST NOT be serialized,
  deduplicated, or coalesced by this component; each fires its own
  independent request whose relative completion order depends on the
  network, not this component. MUST.
- **Network unreachable**: a request failure (e.g. no connectivity)
  fails before any response exists; per
  **error-propagation-unmodified**, the calling operation's result fails
  with that same underlying error, uncaught. MUST.
- **Non-2xx response**: a non-ok response is converted to a typed error
  carrying the response's status and an extracted message by the shared
  authenticated-request layer (outside these given sources, but read to
  resolve this contract); exactly one authorization failure triggers one
  token-refresh-and-retry before this conversion — one refresh and one
  retry only. MUST.
- **Offline or disconnected mid-request**: none of this component's
  operations register a retry, timeout, or a cancellation of their own; a
  request that never settles (e.g. a dropped connection) leaves the
  returned result pending for as long as the underlying request takes to
  settle. MUST.
- **Malformed or unexpected response body**: the shared request helper
  parses the response body unconditionally on an ok, non-empty response;
  a body that is not valid data rejects with that parse call's own
  error, likewise unwrapped and uncaught by any operation here. MUST.
- **Empty-body (no-content) response**: per the shared request helper's
  own guard, a no-content status throws a fixed error indicating a
  different helper should be used for endpoints with no body, rather
  than attempting to parse a body — none of the documented gamification
  routes are expected to return no content, so this path is unexercised
  by any operation here but remains reachable if the backend ever
  answered one of them that way. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| ecosystem id | string | none (required) | Passed to every operation; URL-encoded into the request path for every operation except triggering a replay, which places it in the create request's body instead. |
| item id | string | none (required for badge/event-type item operations) | A badge id or an event-type id; URL-encoded into the item route. |
| configuration update input | object | none (required) | Partial-update body for updating a realm's configuration; every field optional. |
| badge create/update input | object | none (required) | Full create/update body for creating/updating a realm badge; every field required. |
| level rungs | list | none (required) | Full replacement ladder for replacing a realm's levels. |
| event-type create/update input | object | none (required) | Create/update body for creating/updating an event type; both fields required. |
| access token | implicit environment dependency | none | Attached to every request by the shared authenticated-request layer; not a parameter of any operation here. |
| request base path | implicit environment dependency | `/api/gamification/...` (relative) | Every path is relative, resolved against the current page origin through the host's generic API proxy; no base-URL environment value appears in this component. |

## Deep Linking

Not applicable: this component defines no URL scheme, route table, or
navigation handler. Every path it builds is an outbound request path, not
an inbound deep link.

## Localization

Not applicable: this component contains no user-facing string literal —
no error message text, no display text, and no i18n library call. The
only string literals here are enum/union values (`"rpg"`, `"plain"`,
`"none"`, `"gamification"`, `"game"`, `"default"`, `"realm"`,
`"none"`/`"bronze"`/`"silver"`/`"gold"`/`"platinum"`,
`">="`/`">"`/`"="`) and path templates built from encoded arguments —
data values and request shapes, not display copy.

## Accessibility Options

Not applicable: this component renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color, screen-reader state).

## Feature Flags

Not applicable in the build-time/runtime-toggle sense this section
means: this component's own behavior is not gated behind a feature flag.
The per-surface toggle data it transports is itself gamification-surface
data for other apps to read — the component's subject matter, documented
under **realm-config-surfaces-default-on** — not a toggle over this
component's own code paths.

## Analytics

Not applicable: this component calls no analytics or event-emission API
of any kind.

## Privacy

- **Data collected**: this component collects no analytics of its own.
  It transports realm configuration and gamification-catalog data (a
  realm configuration record, its effective catalog, a badge record, an
  event-type record, and their create/update bodies) — none of which is
  end-user personal data. This component reads, stores, or transmits no
  token or credential directly; the access token attached to every
  request is handled entirely by the shared authenticated-request layer,
  outside this component's own logic.
- **Storage**: not applicable — this component persists nothing itself;
  every operation is a stateless request.
- **Transmission**: every request travels over whatever transport the
  shared request layer uses; this component configures no
  transport-level behavior itself.
- **Retention**: not applicable — this component defines no retention
  policy of its own; retention of realm configuration, badges, levels,
  and event types is entirely the backend's concern.

## Logging

Not applicable: this component calls no logger or other logging API.

## Platform Notes

- **SwiftUI**: not applicable to these sources directly — this is a
  web-only component with no Apple counterpart given. A Swift port's
  networking/model layer (see AppKit/UIKit below) is the same regardless
  of whether the consuming UI is SwiftUI or AppKit; SwiftUI itself adds
  nothing beyond that shared layer.
- **AppKit / UIKit**: model `gamificationApi` as a small `struct`/`enum`
  namespace of `async throws` functions built on `URLSession`, mirroring
  each of the twelve methods 1:1; model the `wire.ts` interfaces as
  `Codable, Hashable` structs (mirroring the sibling
  `hub-domain-ecosystem-config` recipe's `sendable-models` convention)
  with a custom `CodingKeys`-free mapping since every wire field is
  already camelCase; represent `Seasons`'s `{...} | null` as `Seasons?`
  and `RealmConfigInput`'s per-field optionality as `Optional` properties
  encoded through a body builder that omits `nil` keys (mirroring
  `compact()` in `client-helpers.ts`) rather than emitting `null` for
  every absent field.
- **React / Web**: this is the source platform, and the only reference
  implementation given. `gamification.ts` (the twelve `gamificationApi`
  methods and their path builders — **realm-config-read**/
  **-partial-update-optionality**/**-update-always-returns-config**,
  **catalog-effective-merge**, **badge-create**/**-update-excludes-defaults**/
  **-delete-clears-holdings-first**, **levels-replace-wholesale**,
  **replay-scoping-via-body**, **event-types-list-name-ordered**/
  **event-type-create**/**-update**/**-delete**) and `wire.ts` (the wire
  types — `RealmConfig`, `RealmConfigInput`, `RealmConfigUpdate`,
  `RealmCatalog`, `CatalogBadge`, `CatalogLevel`, `RealmBadge`,
  `RealmBadgeInput`, `RealmLevelsInput`, `RealmLevelsUpdate`,
  `LevelRung`, `ReplayResult`, `RealmEventType`, `RealmEventTypeInput`,
  `Seasons`, `GamingMode`; marked "Type-only file" in its own header
  comment) live under `packages/web/packages/data/src/gamification/`.
  Every dynamic path segment is passed through `enc`
  (`encodeURIComponent`) before interpolation
  (**path-segment-encoding**); every write body is built with
  `JSON.stringify`, and `putRealmLevels`'s body is typed as an exact
  `{ rungs }` shape via the `satisfies` operator
  (**levels-replace-wholesale**). Every method issues its request
  through `authedJson` and never wraps it in a `try`/`catch`
  (**error-propagation-unmodified**, **no-response-caching**);
  `authedJson`/`authedFetch` (in `@agentic-toolkit/auth/client.ts`,
  outside these two given files) attach the bearer access token, convert
  a non-ok response to `AuthHttpError`, and perform the
  one-refresh-and-retry described in Edge Cases. `listEventTypes`
  performs no `.sort()` of its own — ordering is server-side
  (**event-types-list-name-ordered**). TypeScript's structural typing
  means none of `wire.ts`'s literal-union or numeric-range constraints
  (`tier`, `comparator`, `lengthDays` `1..366`, `≤64`-char fields) are
  checked at runtime by this module — only by the compiler at call sites
  and by the backend at request time.
- **Compose**: model each of the twelve operations as a `suspend fun` on
  a `GamificationApi` interface returning the Kotlin equivalent data
  class (`kotlinx.serialization.Serializable`); model
  `GamingMode`/`skin`/`tier`/`comparator` as `@Serializable` sealed
  classes or enums with an explicit `@SerialName` per value to match the
  exact wire strings; model `Seasons` as a nullable data class and
  `RealmConfigInput`'s per-field optionality with
  `@EncodeDefault(NEVER)`-annotated nullable properties so an absent
  field is omitted rather than serialized as `null`, matching
  `RealmConfigInput`'s partial-PUT contract.
- **WinUI 3**: model `gamificationApi` as a C# class whose twelve
  methods return `Task<T>` over `HttpClient`, using `System.Text.Json`
  with `JsonNamingPolicy.CamelCase` for the wire records; model
  `GamingMode`, `skin`, `tier`, and `comparator` as C# enums decorated
  with `JsonStringEnumConverter` so the serialized values match the
  TypeScript string literals exactly; model `Seasons` as a nullable
  record (`Seasons?`). The distinctive porting problem this recipe
  exists to flag: TypeScript's `field?: T` (omit-if-absent) versus
  `field: T | null` (explicit clear) distinction — used by
  `RealmConfigInput.seasons` to mean three different things (omitted,
  `null`, or an object) — has no direct C#/`System.Text.Json`
  equivalent, since a plain nullable property cannot distinguish "not
  provided" from "explicitly null." A WinUI 3 port needs either a
  wrapper type (e.g. an `Optional<T>` that tracks "was set") or a
  hand-built `JsonSerializerOptions`/`JsonConverter` pair that only
  emits a property when the C# caller explicitly assigned it, mirroring
  `compact()`'s undefined-key-dropping behavior in `client-helpers.ts`
  on the TypeScript side.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/gamification/` |

## Design Decisions

**Decision**: `gamification.ts` transcribes its own wire types into
`wire.ts` rather than importing generated types from
`@agentic-toolkit/adh-api-types`.
**Rationale**: the module's own comment states this directly — "a
generic data client does not take a dependency on adh's generated
product vocabulary," following the same pattern the comment cites for
`ecosystems/wire.ts`. This keeps the `packages/data` layer
product-agnostic at the cost of a second, hand-maintained copy of the
backend's `Gamification*` schemas that must be kept in sync by hand.
**Approved**: pending

**Decision**: none of the twelve `gamificationApi` methods intercept a
documented 400/404/409 response into a friendlier, entity-named message
— every rejection propagates from `authedJson` unmodified
(`error-propagation-unmodified`).
**Rationale**: the source does not explain why. This is a notable
divergence from the sibling component
[Hub Domain: Ecosystem Config](agentictoolkit://cookbook/adh/hub/ecosystems/ecosystem-config),
whose `signin-apps.ts` and `feature-flags.ts` call `rethrowConflict` to
turn a backend 409 into a friendly, entity-named message before it
reaches a caller. This recipe records the observed divergence rather
than inventing a motive the source does not state.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |

`separation-of-concerns` passes: `gamification.ts`/`wire.ts` contain no
UI-rendering import and no business logic beyond building a path,
choosing an HTTP verb, and shaping a body — a clean, single-purpose
data-access layer consumed by a separate features package.
`unit-test-coverage` fails: no test file exists anywhere in the
repository adjacent to `gamification.ts` or `wire.ts` (confirmed by
search), unlike this package's sibling `hub-domain-ecosystem-config`
client, whose Apple counterpart has a dedicated test file even though its
web clients are likewise untested. `explicit-error-handling` passes:
every method lets `authedJson`'s rejection propagate untouched — there is
no `catch` anywhere in either file to silently swallow, so nothing is
ever discarded. `input-sanitization` is partial: `enc()`
(`encodeURIComponent`) sanitizes every dynamic URL segment against path
injection, but no field-level validation (comparator/tier enum
membership, `lengthDays` 1..366, event-type field length ≤64 chars, or
the level ladder's "start at 0, strictly increasing" shape) happens in
this module — every one of those documented constraints is enforced
only by the TypeScript compiler at the call site or by the backend's 400
response, per `levels-ladder-shape-enforced-serverside` and
`event-type-input-length-precondition`. `error-response-handling` is
partial: every operation's documented status codes (400/404/409) are
recorded in this file's own comments, but the client does not translate
any of them into a caller-facing message of its own — see the
`error-propagation-unmodified` Design Decision above; a caller must read
the raw `AuthHttpError` itself to act on a specific status.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
