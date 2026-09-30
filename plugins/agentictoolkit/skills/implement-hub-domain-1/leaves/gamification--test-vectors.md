<!-- leaf: implement-hub-domain-1/gamification--test-vectors · source: hub-domain-gamification.md -->

# Hub Domain: Gamification

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
