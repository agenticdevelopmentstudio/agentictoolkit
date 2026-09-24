---
id: cef42b4b-e10e-4816-b1f8-0156699bec21
title: 'Hub Domain: Gamification'
domain: agentictoolkit://recipes/hub-domain-gamification
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Web data client (gamificationApi) and wire types for one ecosystem's realm
  gamification config, catalog, badges, levels, replay, and event types.
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
- agentictoolkit://recipes/hub-domain-ecosystem-config
references:
- packages/web/packages/data/src/gamification/gamification.ts (agentictoolkit)
- packages/web/packages/data/src/gamification/wire.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Gamification

## Overview

This component is `gamificationApi`, a twelve-method fetch client in `gamification.ts`, plus its wire types in `wire.ts` — the owner/admin-scoped data layer for ONE ecosystem's gamification "realm": its config (mode, skin, per-surface toggles, seasons, timezone), its effective catalog (platform-default badges and level rungs merged with the realm's own overrides), realm-owned badge CRUD, wholesale level-ladder replacement, a manual replay trigger, and realm custom event-type CRUD. The module's own comment states it backs "the per-product Gamification panes — the hub's single settings pane and the gamification site's four-topic rail alike," reaching the backend's `/gamification/realms/:ecosystemId/config` route family (and the sibling `/gamification/replay` route) through the host BFF's `/api/:path*` proxy. This is a **logic** component: `gamification.ts` and `wire.ts` render nothing — they are a plain fetch-based client and its type-only wire shapes, consumed by UI panes (`RealmSettingsPane.tsx`, `CatalogSection.tsx`, `LevelsSection.tsx`, `EventTypesSection.tsx` under `packages/web/packages/features/gamification/src/`) that are not part of this component's given sources.

## Behavioral Requirements

### Module-wide

- **wire-types-own-transcription**: every type `gamification.ts` imports and re-exports (`RealmConfig`, `RealmConfigInput`, `RealmConfigUpdate`, `RealmCatalog`, `CatalogBadge`, `CatalogLevel`, `RealmBadge`, `RealmBadgeInput`, `RealmLevelsInput`, `RealmLevelsUpdate`, `LevelRung`, `ReplayResult`, `RealmEventType`, `RealmEventTypeInput`, `Seasons`, `GamingMode`) MUST come from this module's own `./wire`, never from `@agentic-toolkit/adh-api-types`, per the module's own comment: "a generic data client does not take a dependency on adh's generated product vocabulary."
- **path-segment-encoding**: every dynamic path segment (`ecoId` in `configPath`/`catalogPath`/`badgesPath`/`badgePath`/`levelsPath`/`eventTypesPath`/`eventTypePath`, and `id` in `badgePath`/`eventTypePath`) MUST be passed through `enc` (`encodeURIComponent`) before being interpolated into the request path.
- **api-proxy-path-prefix**: every request path built by this module MUST begin with `/api/gamification/`, matching the host BFF's `/api/:path*` proxy that forwards to the backend's `/gamification/...` routes.
- **stateless-module**: `gamificationApi` MUST hold no instance- or module-level mutable state between calls; every method's request MUST be built solely from the arguments passed to that call.
- **no-response-caching**: none of the twelve `gamificationApi` methods MUST cache a prior response; every call MUST issue a fresh `authedJson` request.
- **error-propagation-unmodified**: none of the twelve `gamificationApi` methods MUST catch, transform, or discard a rejection from `authedJson`; every method's returned promise MUST reject with whatever error `authedJson` throws, unmodified — no method body contains a `try`/`catch`.

### Realm Config

- **realm-config-read**: `getRealmConfig(ecoId)` MUST issue a GET to `configPath(ecoId)` via `authedJson` and resolve with a `RealmConfig`; per its own comment, this read is "admin/owner-gated."
- **realm-config-partial-update-optionality**: `updateRealmConfig(ecoId, input)` MUST issue a PUT to `configPath(ecoId)` with a body of `JSON.stringify(input)`; every field of `RealmConfigInput` (`mode`, `skin`, `surfaces`, `seasons`, `timezone`) MUST be optional, so a caller may send any subset without the others.
- **realm-config-update-always-returns-config**: `updateRealmConfig`'s resolved `RealmConfigUpdate` MUST always carry a `config: RealmConfig` field, regardless of whether a replay occurred.
- **realm-config-mode-ordered-axis**: `GamingMode` MUST be treated as one ordered axis, not a set of mutually exclusive alternatives — per its own comment, `'game'` "INCLUDES everything `'gamification'` gives... it is a superset, not an alternative." A check for whether gaming is on at all MUST test `mode !== "none"`; a check for a game-specific surface MUST test `mode === "game"`.
- **realm-config-surfaces-default-on**: each key of `RealmConfig.surfaces` MUST be treated as enabled unless that key is explicitly set to `false`, per its own comment: "a surface is ON unless set false."
- **realm-config-seasons-nullable-window**: `RealmConfig.seasons` and `RealmConfigInput.seasons` MUST accept `null` to mean seasons are off, and MUST accept an object of `{ anchor: string, lengthDays: number }` to mean an active season window, per `Seasons`'s own comment ("`null` ⇒ seasons off").
- **realm-config-replay-on-enable**: per the module's own comment, `RealmConfigUpdate.replayed` MUST be present only when the applied update raised `mode` from `'none'` to either `'gamification'` or `'game'`, triggering a retroactive replay; it MUST be absent for every other update.

### Catalog

- **catalog-effective-merge**: `getCatalog(ecoId)` MUST issue a GET to `catalogPath(ecoId)` and resolve with a `RealmCatalog` whose `badges` and `levels` arrays are the platform's defaults merged with the realm's own overrides, per `RealmCatalog`'s own comment describing it as "the EFFECTIVE catalog."
- **catalog-default-rows-read-only**: every entry of `RealmCatalog.badges`/`RealmCatalog.levels` MUST carry a `source` of `"default"` or `"realm"`; per `RealmCatalog`'s own comment, `source:'default'` rows MUST be treated as read-only and only `source:'realm'` rows are editable or deletable.

### Badges

- **badge-create**: `createRealmBadge(ecoId, input)` MUST issue a POST to `badgesPath(ecoId)` with a `RealmBadgeInput` JSON body and resolve with the created `RealmBadge`; per its own comment, an invalid body answers 400.
- **badge-input-required-field-set**: `RealmBadgeInput` MUST require `name`, `description`, `icon`, `statKey`, `comparator`, `threshold`, `badgeLine`, `tier`, `pointValue`, and `hidden` as non-optional values on every create or update call, per its own comment ("every field required by the schema") — even though the corresponding `RealmBadge` fields (`statKey`, `comparator`, `threshold`, `badgeLine`, `tier`) are optional and nullable on read.
- **badge-input-omits-read-only-fields**: `RealmBadgeInput` MUST NOT declare an `active`, `subjectType`, or `ecosystemId` property — all three are declared only on the read shape `RealmBadge` — so `createRealmBadge`/`updateRealmBadge` give a caller no way to set a badge's active flag, subject type, or ownership directly.
- **badge-tier-line-override-key**: per `createRealmBadge`'s own comment, a realm badge "overrides the same `(badgeLine, tier)` default" — the pair of `badgeLine` and `tier` is the override key against the platform's default catalog, not `id` or `name`.
- **badge-update-excludes-defaults**: `updateRealmBadge(ecoId, id, input)` MUST issue a PUT to `badgePath(ecoId, id)` with a `RealmBadgeInput` body and resolve with the updated `RealmBadge`; per its own comment, this call answers 404 for a platform-default badge (one whose `ecosystemId` is `null`).
- **badge-delete-clears-holdings-first**: `deleteRealmBadge(ecoId, id)` MUST issue a DELETE to `badgePath(ecoId, id)` and resolve with `{ deleted: string }`; per its own comment, deleting a realm-owned badge clears its holdings first, and MUST NOT succeed against a platform default (404).

### Levels

- **levels-replace-wholesale**: `putRealmLevels(ecoId, rungs)` MUST issue a PUT to `levelsPath(ecoId)` with a body of exactly `{ rungs }` (typed as `RealmLevelsInput` via the `satisfies` operator) and resolve with `RealmLevelsUpdate`; this call replaces the entire ladder, never a partial merge.
- **levels-ladder-shape-enforced-serverside**: `putRealmLevels`'s own comment states the sent `rungs` "must start at 0, strictly increasing. 400 otherwise," and `RealmLevelsInput`'s own comment repeats the same constraint; `putRealmLevels` performs no runtime check of that shape itself — enforcement is documented as the backend's, surfaced to the caller as a 400 via `error-propagation-unmodified`.
- **levels-update-replay-hint**: `RealmLevelsUpdate` MUST carry the replaced `levels: CatalogLevel[]` plus a `replayHint: string`, per its own comment ("the owner may POST /replay to backfill retroactively").

### Replay

- **replay-scoping-via-body**: `replayRealm(ecoId)` MUST issue a POST to the fixed `replayPath()` (`/api/gamification/replay`, which takes no `ecoId` segment) with a JSON body of exactly `{ ecosystemId: ecoId }`, and resolve with a `ReplayResult` — the only one of the twelve operations that carries its ecosystem scope in the body rather than the URL path.
- **replay-result-single-subject-fields**: `ReplayResult.subjects` MUST be `1` for a single-subject replay per its own comment; `badges` MUST count newly-granted badges across the replayed subject(s); `xpGained` MUST be present only for a single-subject replay, per its own comment ("Points granted — single-subject replay only").

### Event Types

- **event-types-list-name-ordered**: `listEventTypes(ecoId)` MUST issue a GET to `eventTypesPath(ecoId)` and resolve with a `RealmEventType[]`; per its own comment the result is "name-ordered" and `listEventTypes` performs no sort of its own — ordering is produced server-side.
- **event-type-create**: `createEventType(ecoId, input)` MUST issue a POST to `eventTypesPath(ecoId)` with a `RealmEventTypeInput` body and resolve with the created `RealmEventType`; per its own comment, a bad input answers 400 and a duplicate name answers 409.
- **event-type-update**: `updateEventType(ecoId, id, input)` MUST issue a PUT to `eventTypePath(ecoId, id)` with a `RealmEventTypeInput` body and resolve with the updated `RealmEventType`; per its own comment, a foreign realm's row answers 404 and a colliding rename answers 409.
- **event-type-delete**: `deleteEventType(ecoId, id)` MUST issue a DELETE to `eventTypePath(ecoId, id)` and resolve with `{ deleted: string }`; per its own comment, a foreign realm's row or an unknown id answers 404.
- **event-type-input-length-precondition**: `RealmEventTypeInput`'s own comment bounds `name` and `statKey` to "both fields required, ≤64 chars" — a documented caller precondition that `createEventType`/`updateEventType` do not check themselves, per `event-type-create`'s own comment assigning a bad input's rejection (400) to the backend.

## Appearance

Not applicable — this is a data client, not a visual component.

## States

Not applicable — this is a data client, not a visual component. `GamingMode`'s three values (`'none'`, `'gamification'`, `'game'`) describe realm-configuration data this client transports, not a runtime state machine of the client itself; see `realm-config-mode-ordered-axis` under Behavioral Requirements.

## Accessibility

Not applicable — this is a data client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| gamification-001 | wire-types-own-transcription | Read the import statement at the top of `gamification.ts` | Imports only from `./wire`; no import from `@agentic-toolkit/adh-api-types` |
| gamification-002 | path-segment-encoding, api-proxy-path-prefix | `configPath("eco/1")`, `badgePath("eco 1", "b#1")` | `"/api/gamification/realms/eco%2F1/config"`; `"/api/gamification/realms/eco%201/badges/b%231"` |
| gamification-003 | stateless-module, no-response-caching | Call `gamificationApi.getRealmConfig("eco-1")` twice with `authedJson` mocked to return a different value each time | Two separate `authedJson` calls fire; the second resolved value differs from the first |
| gamification-004 | error-propagation-unmodified | `authedJson` mocked to reject with an `AuthHttpError(409, "already exists")` for `createEventType` | The returned promise rejects with that same error, unmodified |
| gamification-005 | realm-config-read | `getRealmConfig("org.acme.shop")` with `authedJson` mocked to resolve `{ ecosystemId: "org.acme.shop", mode: "none", skin: "plain", surfaces: {}, seasons: null, timezone: "UTC" }` | GET to `"/api/gamification/realms/org.acme.shop/config"`; resolves with that object |
| gamification-006 | realm-config-partial-update-optionality, realm-config-update-always-returns-config | `updateRealmConfig("eco-1", { timezone: "America/New_York" })` | PUT to `"/api/gamification/realms/eco-1/config"` with body `{"timezone":"America/New_York"}` only; resolved `RealmConfigUpdate.config` is present |
| gamification-007 | realm-config-mode-ordered-axis | `RealmConfig.mode === "game"` vs. `"gamification"` | `mode !== "none"` is true for both; `mode === "game"` is true only for the first |
| gamification-008 | realm-config-surfaces-default-on | `surfaces = { leaderboard: false }` | Reading `surfaces.badges` (an absent key) is treated as enabled; only `surfaces.leaderboard` is off |
| gamification-009 | realm-config-seasons-nullable-window | `updateRealmConfig("eco-1", { seasons: null })`, then `updateRealmConfig("eco-1", { seasons: { anchor: "2026-01-01", lengthDays: 30 } })` | Bodies `{"seasons":null}` then `{"seasons":{"anchor":"2026-01-01","lengthDays":30}}` |
| gamification-010 | realm-config-replay-on-enable | `updateRealmConfig("eco-1", { mode: "gamification" })` with `authedJson` mocked to resolve `{ config: {...}, replayed: { subjects: 1, badges: 2, xpGained: 50 } }` | Resolved value's `replayed` field equals that object |
| gamification-011 | catalog-effective-merge, catalog-default-rows-read-only | `getCatalog("eco-1")` with `authedJson` mocked to resolve badges/levels tagged `source: "default"` and `source: "realm"` | Resolved `RealmCatalog` preserves each row's `source` tag unchanged |
| gamification-012 | badge-create, badge-input-required-field-set | `createRealmBadge("eco-1", { name: "Streaker", description: "7-day streak", icon: "fire", statKey: "streak_days", comparator: ">=", threshold: 7, badgeLine: "streak", tier: "bronze", pointValue: 50, hidden: false })` | POST to `"/api/gamification/realms/eco-1/badges"` with a body containing exactly those ten keys |
| gamification-013 | badge-input-omits-read-only-fields | Read the `RealmBadgeInput` interface in `wire.ts` | No `active`, `subjectType`, or `ecosystemId` property, though `RealmBadge` declares all three |
| gamification-014 | badge-tier-line-override-key | Read `createRealmBadge`'s own comment | States a realm badge "overrides the same (badgeLine, tier) default" |
| gamification-015 | badge-update-excludes-defaults, badge-delete-clears-holdings-first | Read `updateRealmBadge`'s and `deleteRealmBadge`'s own comments | "404 for a platform default" and "clears its holdings first; 404 for a default" respectively |
| gamification-016 | levels-replace-wholesale | `putRealmLevels("eco-1", [{ name: "Novice", minPoints: 0 }, { name: "Pro", minPoints: 500 }])` | PUT to `"/api/gamification/realms/eco-1/levels"` with body `{"rungs":[{"name":"Novice","minPoints":0},{"name":"Pro","minPoints":500}]}` |
| gamification-017 | levels-ladder-shape-enforced-serverside | Read `putRealmLevels`'s and `RealmLevelsInput`'s own comments | Both state rungs must start at 0 and be strictly increasing; `putRealmLevels` contains no runtime check of the array |
| gamification-018 | levels-update-replay-hint | `authedJson` mocked to resolve `{ levels: [...], replayHint: "POST /gamification/replay to backfill" }` for `putRealmLevels` | Resolved `RealmLevelsUpdate.replayHint` equals that string |
| gamification-019 | replay-scoping-via-body | `replayRealm("eco-1")` | POST to the fixed path `"/api/gamification/replay"` (no `"eco-1"` in the URL) with body `{"ecosystemId":"eco-1"}` |
| gamification-020 | replay-result-single-subject-fields | `authedJson` mocked to resolve `{ subjects: 1, badges: 3, xpGained: 120 }` for `replayRealm` | Resolved `ReplayResult` carries all three fields |
| gamification-021 | event-types-list-name-ordered | `listEventTypes("eco-1")` with `authedJson` mocked to resolve a name-ordered array | Resolves with that same array, in the same order; no `.sort()` call in `listEventTypes` |
| gamification-022 | event-type-create, event-type-input-length-precondition | `createEventType("eco-1", { name: "level_up", statKey: "levels_gained" })` | POST to `"/api/gamification/realms/eco-1/event-types"` with body `{"name":"level_up","statKey":"levels_gained"}`; no client-side length/presence check performed |
| gamification-023 | event-type-update | `updateEventType("eco-1", "et-1", { name: "level_up_v2", statKey: "levels_gained" })` | PUT to `"/api/gamification/realms/eco-1/event-types/et-1"` with that body |
| gamification-024 | event-type-delete | `deleteEventType("eco-1", "et-1")` | DELETE to `"/api/gamification/realms/eco-1/event-types/et-1"`, resolving `{ deleted: "et-1" }` |

## Edge Cases

- **Empty `ecoId` string**: `enc("")` encodes to `""`, producing a request path with a doubled slash (e.g. `"/api/gamification/realms//config"`); none of the twelve methods reject an empty `ecoId` before building that path. MUST.
- **Empty `id` string (badge or event type)**: the same doubling occurs in `badgePath`/`eventTypePath`'s second segment; neither `updateRealmBadge`/`deleteRealmBadge` nor `updateEventType`/`deleteEventType` reject an empty `id` before building the path. MUST.
- **Fully-omitted update body**: `updateRealmConfig("eco-1", {})` sends a PUT with body `"{}"`; every `RealmConfigInput` field being optional means an all-omitted input is not rejected client-side. MUST.
- **Empty `rungs` array**: `putRealmLevels("eco-1", [])` sends body `{"rungs":[]}`, which violates the documented "must start at 0" shape; the client performs no check for this and relies entirely on the backend's 400. MUST.
- **Boundary `lengthDays` (1 and 366)**: `RealmConfigInput.seasons`'s own comment bounds `lengthDays` to `1..366`; the client passes whatever numeric value the caller supplies with no client-side range check. MUST.
- **Boundary event-type field length (64 chars)**: `RealmEventTypeInput`'s own comment bounds `name`/`statKey` to `≤64` chars; same, unchecked client-side. MUST.
- **Concurrent calls**: `gamificationApi` holds no shared state between calls (`stateless-module`), so two concurrent calls — even to the same operation and `ecoId` — MUST NOT be serialized, deduplicated, or coalesced by this module; each fires its own independent request whose relative completion order depends on the network, not this file. MUST.
- **Network unreachable**: a `fetch` failure (e.g. no connectivity) rejects before any `Response` exists; per `error-propagation-unmodified`, the calling `gamificationApi` method's promise rejects with that same underlying error, uncaught. MUST.
- **Non-2xx response**: per `authedFetch` (in `@agentic-toolkit/auth/client.ts`, outside these two given files but read to resolve this contract), a non-ok response is converted to `AuthHttpError` carrying the response's status and an extracted message; exactly one `401` triggers one token-refresh-and-retry before this conversion, per `authedFetch`'s own comment ("One refresh + one retry only"). MUST.
- **Offline or disconnected mid-request**: none of the twelve methods register a retry, timeout, or an abort signal of their own; a request that never settles (e.g. a dropped connection) leaves the returned promise pending for as long as the underlying `fetch` call takes to settle. MUST.
- **Malformed or unexpected response body**: `authedJson` calls `res.json()` unconditionally on an ok, non-204 response; a body that is not valid JSON rejects with that parse call's own error, likewise unwrapped and uncaught by any `gamificationApi` method. MUST.
- **204 No Content response**: per `authedJson`'s own guard, a `204` status throws a fixed `"Unexpected empty response (204 No Content); use authedRequest for endpoints with no body"` error rather than attempting to parse a body — none of the twelve documented gamification routes are expected to return `204`, so this path is unexercised by any method here but remains reachable if the backend ever answered one of them that way. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ecoId` | `string` | none (required) | Ecosystem id passed to every method; URL-encoded via `enc()` into the request path for every operation except `replayRealm`, which places it in the POST body's `ecosystemId` field instead. |
| `id` | `string` | none (required for badge/event-type item operations) | Badge id (`updateRealmBadge`, `deleteRealmBadge`) or event-type id (`updateEventType`, `deleteEventType`); URL-encoded via `enc()`. |
| `input` (`RealmConfigInput`) | object | none (required) | Partial-update body for `updateRealmConfig`; every field optional. |
| `input` (`RealmBadgeInput`) | object | none (required) | Full create/update body for `createRealmBadge`/`updateRealmBadge`; every field required. |
| `rungs` (`LevelRung[]`) | array | none (required) | Full replacement ladder for `putRealmLevels`. |
| `input` (`RealmEventTypeInput`) | object | none (required) | Create/update body for `createEventType`/`updateEventType`; both fields required. |
| Bearer access token | implicit environment dependency | none | Attached to every request by `authedJson`/`authedFetch` (in `@agentic-toolkit/auth/client.ts`, outside these two given files) via `readAccessToken()`; not a parameter of any `gamificationApi` method. |
| Request base path | implicit environment dependency | `/api/gamification/...` (relative) | Every path is relative, resolved against the current page origin through the host's `/api/:path*` BFF proxy; no base-URL environment variable appears in `gamification.ts`. |

## Deep Linking

Not applicable: neither `gamification.ts` nor `wire.ts` defines a URL scheme, route table, or navigation handler. Every path this module builds is an outbound API request path, not an inbound deep link.

## Localization

Not applicable: `gamification.ts` and `wire.ts` contain no user-facing string literal — no `throw new Error("...")`, no display text, and no i18n library call. The only string literals in either file are enum/union values (`"rpg"`, `"plain"`, `"none"`, `"gamification"`, `"game"`, `"default"`, `"realm"`, `"none"`/`"bronze"`/`"silver"`/`"gold"`/`"platinum"`, `">="`/`">"`/`"="`) and path templates built from `enc()`-encoded arguments — data values and request shapes, not display copy.

## Accessibility Options

Not applicable: these files render nothing and read no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color, VoiceOver).

## Feature Flags

Not applicable in the build-time/runtime-toggle sense this section means: no given source gates its own behavior behind a feature flag. `RealmConfig.surfaces` is itself gamification-surface toggle data this client transports for other apps to read — the component's subject matter, documented under `realm-config-surfaces-default-on` — not a toggle over this file's own code paths.

## Analytics

Not applicable: no given source calls an analytics or event-emission API of any kind.

## Privacy

- **Data collected**: this component collects no analytics of its own. It transports realm configuration and gamification-catalog data (`RealmConfig`, `RealmCatalog`, `RealmBadge`, `RealmEventType`, and their create/update bodies) — none of which is end-user personal data. Neither given file reads, stores, or transmits a token or credential directly; the bearer access token attached to every request is handled entirely inside `authedJson`/`authedFetch` in `@agentic-toolkit/auth/client.ts`, outside these two given sources.
- **Storage**: not applicable — `gamification.ts`/`wire.ts` persist nothing themselves; every method is a stateless fetch call.
- **Transmission**: every request travels over whatever transport `authedJson` uses (outside these given sources); this component configures no TLS or transport-level behavior itself.
- **Retention**: not applicable — this component defines no retention policy of its own; retention of realm configuration, badges, levels, and event types is entirely the backend's concern.

## Logging

Not applicable: neither `gamification.ts` nor `wire.ts` calls `console.log`, `Logger`, or any other logging API.

## Platform Notes

- **SwiftUI**: not applicable to these sources directly — this is a web-only component with no Apple counterpart given. A Swift port's networking/model layer (see AppKit/UIKit below) is the same regardless of whether the consuming UI is SwiftUI or AppKit; SwiftUI itself adds nothing beyond that shared layer.
- **AppKit / UIKit**: model `gamificationApi` as a small `struct`/`enum` namespace of `async throws` functions built on `URLSession`, mirroring each of the twelve methods 1:1; model the `wire.ts` interfaces as `Codable, Hashable` structs (mirroring the sibling `hub-domain-ecosystem-config` recipe's `sendable-models` convention) with a custom `CodingKeys`-free mapping since every wire field is already camelCase; represent `Seasons`'s `{...} | null` as `Seasons?` and `RealmConfigInput`'s per-field optionality as `Optional` properties encoded through a body builder that omits `nil` keys (mirroring `compact()` in `client-helpers.ts`) rather than emitting `null` for every absent field.
- **React / Web**: this is the source platform. `gamification.ts` (the twelve `gamificationApi` methods and their path builders) and `wire.ts` (the wire types, marked "Type-only file" in its own header comment) live under `packages/web/packages/data/src/gamification/`; TypeScript's structural typing means none of `wire.ts`'s literal-union or numeric-range constraints (`tier`, `comparator`, `lengthDays` `1..366`, `≤64`-char fields) are checked at runtime by this module — only by the compiler at call sites and by the backend at request time.
- **Compose**: model each of the twelve operations as a `suspend fun` on a `GamificationApi` interface returning the Kotlin equivalent data class (`kotlinx.serialization.Serializable`); model `GamingMode`/`skin`/`tier`/`comparator` as `@Serializable` sealed classes or enums with an explicit `@SerialName` per value to match the exact wire strings; model `Seasons` as a nullable data class and `RealmConfigInput`'s per-field optionality with `@EncodeDefault(NEVER)`-annotated nullable properties so an absent field is omitted rather than serialized as `null`, matching `RealmConfigInput`'s partial-PUT contract.
- **WinUI 3**: model `gamificationApi` as a C# class whose twelve methods return `Task<T>` over `HttpClient`, using `System.Text.Json` with `JsonNamingPolicy.CamelCase` for the wire records; model `GamingMode`, `skin`, `tier`, and `comparator` as C# enums decorated with `JsonStringEnumConverter` so the serialized values match the TypeScript string literals exactly; model `Seasons` as a nullable record (`Seasons?`). The distinctive porting problem this recipe exists to flag: TypeScript's `field?: T` (omit-if-absent) versus `field: T | null` (explicit clear) distinction — used by `RealmConfigInput.seasons` to mean three different things (omitted, `null`, or an object) — has no direct C#/`System.Text.Json` equivalent, since a plain nullable property cannot distinguish "not provided" from "explicitly null." A WinUI 3 port needs either a wrapper type (e.g. an `Optional<T>` that tracks "was set") or a hand-built `JsonSerializerOptions`/`JsonConverter` pair that only emits a property when the C# caller explicitly assigned it, mirroring `compact()`'s undefined-key-dropping behavior in `client-helpers.ts` on the TypeScript side.

## Design Decisions

**Decision**: `gamification.ts` transcribes its own wire types into `wire.ts` rather than importing generated types from `@agentic-toolkit/adh-api-types`.
**Rationale**: the module's own comment states this directly — "a generic data client does not take a dependency on adh's generated product vocabulary," following the same pattern the comment cites for `ecosystems/wire.ts`. This keeps the `packages/data` layer product-agnostic at the cost of a second, hand-maintained copy of the backend's `Gamification*` schemas that must be kept in sync by hand.
**Approved**: pending

**Decision**: none of the twelve `gamificationApi` methods intercept a documented 400/404/409 response into a friendlier, entity-named message — every rejection propagates from `authedJson` unmodified (`error-propagation-unmodified`).
**Rationale**: the source does not explain why. This is a notable divergence from the sibling component [Hub Domain: Ecosystem Config](agentictoolkit://recipes/hub-domain-ecosystem-config), whose `signin-apps.ts` and `feature-flags.ts` call `rethrowConflict` to turn a backend 409 into a friendly, entity-named message before it reaches a caller. This recipe records the observed divergence rather than inventing a motive the source does not state.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |

`separation-of-concerns` passes: `gamification.ts`/`wire.ts` contain no UI-rendering import and no business logic beyond building a path, choosing an HTTP verb, and shaping a body — a clean, single-purpose data-access layer consumed by a separate features package. `unit-test-coverage` fails: no test file exists anywhere in the repository adjacent to `gamification.ts` or `wire.ts` (confirmed by search), unlike this package's sibling `hub-domain-ecosystem-config` client, whose Apple counterpart has a dedicated test file even though its web clients are likewise untested. `explicit-error-handling` passes: every method lets `authedJson`'s rejection propagate untouched — there is no `catch` anywhere in either file to silently swallow, so nothing is ever discarded. `input-sanitization` is partial: `enc()` (`encodeURIComponent`) sanitizes every dynamic URL segment against path injection, but no field-level validation (comparator/tier enum membership, `lengthDays` 1..366, event-type field length ≤64 chars, or the level ladder's "start at 0, strictly increasing" shape) happens in this module — every one of those documented constraints is enforced only by the TypeScript compiler at the call site or by the backend's 400 response, per `levels-ladder-shape-enforced-serverside` and `event-type-input-length-precondition`. `error-response-handling` is partial: every operation's documented status codes (400/404/409) are recorded in this file's own comments, but the client does not translate any of them into a caller-facing message of its own — see the `error-propagation-unmodified` Design Decision above; a caller must read the raw `AuthHttpError` itself to act on a specific status.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
