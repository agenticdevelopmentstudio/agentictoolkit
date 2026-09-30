<!-- leaf: implement-hub-domain-1/gamification · source: hub-domain-gamification.md -->

**Rules** (cite as `implement-hub-domain-1/gamification#<slug>`):

- `wire-types-own-transcription` MUST
- `path-segment-encoding` MUST
- `api-proxy-path-prefix` MUST
- `stateless-module` MUST
- `no-response-caching` MUST
- `error-propagation-unmodified` MUST
- `realm-config-read` MUST
- `realm-config-partial-update-optionality` MUST
- `realm-config-update-always-returns-config` MUST
- `realm-config-mode-ordered-axis` MUST
- `realm-config-surfaces-default-on` MUST
- `realm-config-seasons-nullable-window` MUST
- `realm-config-replay-on-enable` MUST
- `catalog-effective-merge` MUST
- `catalog-default-rows-read-only` MUST
- `badge-create` MUST
- `badge-input-required-field-set` MUST
- `badge-input-omits-read-only-fields` MUST
- `badge-update-excludes-defaults` MUST
- `badge-delete-clears-holdings-first` MUST
- `levels-replace-wholesale` MUST
- `levels-update-replay-hint` MUST
- `replay-scoping-via-body` MUST
- `replay-result-single-subject-fields` MUST
- `event-types-list-name-ordered` MUST
- `event-type-create` MUST
- `event-type-update` MUST
- `event-type-delete` MUST

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

