---
id: 5d44b127-7701-4d3f-8d34-fe50084e52b7
title: 'Hub Domain: Games'
domain: agentictoolkit://recipes/hub-domain-games
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Games catalog domain logic: the web gamesApi/gameDefinitionsApi/gameEffectsApi/gameMappingsApi
  CRUD clients over four tables of the game schema.'
platforms:
- typescript
- web
tags:
- games
- crud
- ecosystems
- jsonb
- web
depends-on:
- agentictoolkit://recipes/auth-client
related:
- agentictoolkit://recipes/hub-domain-ecosystems
references:
- packages/web/packages/data/src/games/games.ts (agentictoolkit)
- packages/web/packages/data/src/games/index.ts (agentictoolkit)
- packages/web/packages/data/src/games/__tests__/games.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Games

## Overview

`hub-domain-games` is the Games catalog domain logic: the web client for the
four OPERATOR-WRITABLE tables of the `game` schema (`game.games`,
`game.definitions`, `game.effects`, `game.mappings`), built over adh's
generic CRUD routes. One source of truth, `packages/web/packages/data/src/games/games.ts`,
exports `gamesApi` (the catalog record itself) and three same-shaped child
clients, `gameDefinitionsApi`, `gameEffectsApi`, and `gameMappingsApi`,
produced by one shared factory, `childApi`. The module's own header comment
states the boundary this recipe holds to deliberately: the `game` schema has
eight other tables that hold PLAYER state, none of which have an operator
read path, and this client never reaches them.

Two structural facts run through every operation this recipe documents.
First, a SCOPING asymmetry: the parent id (`ecosystemId` for a game,
`gameId` for a child row) is a query-string filter on LIST and a BODY field
on CREATE, because the generic LIST route reads query params and the
generic POST route reads none — the two spellings are not interchangeable,
and using the wrong one either misfiles a row under the caller's own
ecosystem or fails a `NOT NULL` constraint. Second, a WIRE crossing: four
columns (`games.description`, `definitions.description`, both nullable
`text`; `games.engine_config`, `definitions.data`, both `jsonb`) are `string`
on this client's types but are not strings on the wire, and `gameFromWire`/
`gameToWire`/`definitionFromWire`/`definitionToWire` hold both crossings in
one place rather than scattering the translation across call sites.

## Behavioral Requirements

### Closed-set types

- **game-character-names-values**: `GameCharacterNames` MUST be one of
  `"off"`, `"optional"`, `"required"` — `game.games.character_names`, a
  closed set enforced by a database `check`, with `"off"` as the default
  (`games.ts`).
- **game-status-values**: `GameStatus` MUST be one of `"active"`,
  `"hidden"`, `"retired"` — `game.games.status`, defaulting to `"active"`;
  `"hidden"` is delisted but still startable by anyone holding a link or a
  save, and `"retired"` is neither (`games.ts`).
- **game-event-log-values**: `GameEventLog` MUST be one of `"debug"`,
  `"authoritative"` — `game.games.event_log`, a closed set enforced by a
  database `check`, defaulting to `"debug"`; `"authoritative"` means the
  event log is the truth and is never swept regardless of the retention
  window (`games.ts`).
- **game-definition-status-values**: `GameDefinitionStatus` MUST be one of
  `"active"`, `"retired"` — narrower than `GameStatus`'s three values,
  because a definition is either offered or it is not; nothing about it is
  "startable" (`games.ts`).
- **game-effect-trigger-values**: `GameEffectTrigger` MUST be one of
  `"on_use"`, `"on_equip"`, `"on_hold"`, `"on_enter"`, `"on_acquire"` —
  `game.effects.trigger`, a closed set enforced by a database `check`
  (`games.ts`).
- **game-effect-operation-values**: `GameEffectOperation` MUST be one of
  `"add"`, `"multiply"`, `"set"` — `game.effects.operation`, also a closed
  set enforced by a database `check` (`games.ts`).

### Row shapes and invariants

- **game-shape**: `Game` MUST carry `id`, `slug`, `name`, `description`
  (`string`), `engine`, `engineConfig` (`string`), `characterNames`,
  `status`, `eventLog`, `eventRetentionDays` (`number`), `createdAt`,
  `updatedAt` (`games.ts`).
- **game-id-is-opaque**: `Game.id` MUST be treated as an opaque,
  server-generated UUID with no address of its own — `game.games` is NOT
  rdid-addressed, and a game is reached as "the game of ecosystem X"
  through its product's ecosystem rdid rather than by an id-based address
  (`games.ts` header comment).
- **game-event-retention-semantics**: `Game.eventRetentionDays` MUST be
  read as the day window the `"debug"` sweep applies, and MUST be treated
  as meaningless when `eventLog` is `"authoritative"`, per the field's own
  doc comment (`games.ts`).
- **game-input-shape**: `GameInput` MUST carry exactly `slug`, `name`,
  `description`, `engine`, `engineConfig`, `characterNames`, `status`,
  `eventLog`, `eventRetentionDays` — no `id`, `createdAt`, or `updatedAt`
  (`games.ts`).
- **game-definition-shape**: `GameDefinition` MUST carry `id`, `gameId`,
  `authorCustomerId`, `kind`, `key`, `name`, `description` (`string`),
  `status`, `sortOrder`, `data` (`string`), `createdAt`, `updatedAt`
  (`games.ts`).
- **game-definition-key-scope**: `GameDefinition.key` MUST be read as the
  stable handle an engine refers to, unique WITHIN `kind` rather than
  across the whole game (`games.ts`).
- **game-definition-input-excludes-author**: `GameDefinitionInput` MUST
  carry `kind`, `key`, `name`, `description`, `status`, `sortOrder`, `data`
  and MUST NOT carry `authorCustomerId` — that column is ROUTE-MANAGED,
  stamped from the caller by the backend's `POST /game/terms`, and masked
  out of the generic CRUD body, so a client that sent it would have the
  value silently stripped rather than refused (`games.ts` header comment).
- **game-effect-shape**: `GameEffect` MUST carry `id`, `gameId`,
  `definitionId`, `key`, `trigger`, `target`, `operation`, `value`
  (`number`), `duration` (`number | null`), `sortOrder`, `createdAt`,
  `updatedAt` (`games.ts`).
- **game-effect-duration-semantics**: `GameEffect.duration` of `null` MUST
  be read as "for as long as it is held," never as "no duration," and MUST
  NOT be confused with `0`, which means the effect expires immediately
  (`games.ts`).
- **game-effect-sort-order-is-load-bearing**: `GameEffect.sortOrder` MUST
  be treated as load-bearing for correctness — applying an `"add"` effect
  before a `"multiply"` effect produces a different result than the
  reverse order (`games.ts`).
- **game-effect-input-allows-blank-selection**: `GameEffectInput.trigger`
  and `GameEffectInput.operation` MUST accept `""` in addition to their
  respective closed sets, representing a draft that has not yet chosen a
  value; neither closed set has a default, so a blank draft carries no
  trigger or operation until one is picked (`games.ts`).
- **game-mapping-shape**: `GameMapping` MUST carry `id`, `gameId`, `kind`
  (an unconstrained, game-defined string with no database `check`),
  `fromId`, `toId`, `amount` (`number`), `sortOrder`, `createdAt`,
  `updatedAt` (`games.ts`).
- **game-mapping-input-shape**: `GameMappingInput` MUST carry `kind`,
  `fromId`, `toId`, `amount`, `sortOrder` (`games.ts`).

### The two column crossings (wire mapping)

- **nullable-text-read**: `gameFromWire` and `definitionFromWire` MUST map
  a `description` of `null` on the wire to `""` on the client type
  (`games.ts`; pinned by "reads a null description as an empty field" and
  "applies the same reading rule to a definition" in `games.test.ts`).
- **nullable-text-write**: `gameToWire` and `definitionToWire` MUST map a
  `description` that is empty or all-whitespace, after trimming, to `null`
  on the wire — an empty box means the COLUMN is empty, never an empty
  string stored in it — via the shared `emptyToNull` helper (`games.ts`;
  pinned by "writes an empty box as an empty COLUMN, not an empty string
  in one" in `games.test.ts`).
- **jsonb-read-as-indented-text**: `gameFromWire`/`definitionFromWire`
  MUST render a parsed `engineConfig`/`data` JSON value as the two-space
  indented text produced by `JSON.stringify(value, null, 2)`, via the
  shared `jsonToText` helper (`games.ts`; pinned by "reads a config OBJECT
  as the JSON text the operator edits" in `games.test.ts`).
- **jsonb-write-as-parsed-value**: `gameToWire`/`definitionToWire` MUST
  parse the operator's JSON text back into a JSON value before sending it,
  via the shared `textToJson` helper, never sending the raw text string
  (`games.ts`; pinned by "parses the operator's text into a JSON VALUE on
  the way out" in `games.test.ts`).
- **jsonb-empty-value-differs-by-column**: `jsonToText`/`textToJson` MUST
  use `{}` (the empty JSON object) as `engineConfig`'s empty value, because
  `games.engine_config` is `NOT NULL` with a `{}` default, and MUST use
  `null` as `data`'s empty value, because `definitions.data` is nullable
  (`games.ts`; pinned by "crosses an empty engine config as the empty
  OBJECT, both ways" and "crosses an empty definition payload as NULL,
  both ways" in `games.test.ts`).
- **jsonb-read-null-as-empty-text**: `jsonToText` MUST return `""` when the
  wire value is `null` or `undefined`, whatever the client's own type
  claims about that column's nullability (`games.ts`; pinned by "reads a
  null engine config as an empty field, whatever the type says" in
  `games.test.ts`).
- **jsonb-write-refuses-unparseable-text**: `textToJson` MUST throw a
  `clientRefusal` (an `Error` with a `status` of `400`) carrying the
  message `"<label> must be valid JSON."` when the trimmed text fails
  `JSON.parse`, where `<label>` is `"Engine config"` for `gameToWire` and
  `"Data"` for `definitionToWire` (`games.ts`; pinned by "refuses
  unparseable JSON with a 4xx the shared reporter drops" in
  `games.test.ts`).
- **jsonb-serialization-collapse-is-defensive**: `jsonToText` MUST return
  `""` (never `"undefined"`) if `JSON.stringify` itself answers
  `undefined`, a branch the source's own comment states nothing a `jsonb`
  column can hold reaches, kept only because the function is a cast over
  whatever the route returns (`games.ts`).

### `gamesApi`

- **games-list-scoped-by-ecosystem-query**: `gamesApi.list(ecosystemId?)`
  MUST request `GET /api/game/games?ecosystemId=<encoded ecosystemId>`
  when given an id, and MUST request the bare `/api/game/games` URL when
  omitted (`games.ts`; pinned by "filters the catalog by ecosystem in the
  QUERY" and "asks for the whole catalog when no ecosystem is named" in
  `games.test.ts`).
- **games-list-sorted-by-name**: `gamesApi.list` MUST sort the mapped rows
  by `name` via the locale-aware `sortByText` helper, because the generic
  list route applies no `ORDER BY` of its own and returns rows in whatever
  order the query planner produces (`games.ts`).
- **games-for-ecosystem-single-result**: `gamesApi.forEcosystem(ecosystemId)`
  MUST call `gamesApi.list(ecosystemId)` and return its first row, or
  `null` when the list is empty; this is safe because a partial unique
  index (`uq_games_ecosystem` on `(ecosystem_id) WHERE deleted_at IS NULL`)
  guarantees at most one live game per ecosystem (`games.ts`; pinned by
  "resolves the one game of an ecosystem" and "answers null for an
  ecosystem with no game" in `games.test.ts`).
- **games-create-ecosystem-in-body**: `gamesApi.create(input, ecosystemId)`
  MUST send `ecosystemId` as a field of the POST BODY (alongside
  `gameToWire(input)`), never as a query parameter, because the generic
  POST route reads no query params at all (`games.ts`; pinned by "stamps a
  created game into its ecosystem through the BODY, not the query" in
  `games.test.ts`).
- **games-create-conflict-mapping**: `gamesApi.create` MUST catch any error
  from the POST and pass it to `rethrowConflict` with the friendly message
  `A game with slug "<input.slug>" already exists.`, which rethrows that
  friendly message only when the caught error's own message matches
  `/already exists/i`, and otherwise rethrows the caught error unchanged
  (`games.ts`, `http.ts`; pinned by "names the entity, not the constraint,
  when a slug is taken" in `games.test.ts`).
- **games-update-omits-ecosystem**: `gamesApi.update(id, input)` MUST PUT
  to `/api/game/games/<encoded id>` with a body built from `gameToWire(input)`
  alone, and MUST NOT resend an ecosystem id in any form — a game does not
  move between ecosystems, and this PUT is the only route that could try
  (`games.ts`; pinned by "does not resend the ecosystem on update" in
  `games.test.ts`).
- **games-update-conflict-mapping**: `gamesApi.update` MUST map a caught
  error through `rethrowConflict` with the same friendly-message rule as
  `games-create-conflict-mapping`, using `input.slug` in the message
  (`games.ts`).
- **games-delete-no-body**: `gamesApi.delete(id)` MUST send `DELETE
  /api/game/games/<encoded id>` with no request body and resolve to `void`
  (`games.ts`).
- **id-percent-encoded-in-path**: every path segment built from a caller
  id (`gamesApi.update`/`delete`, and every `childApi` `update`/`delete`)
  MUST be percent-encoded via the shared `enc` helper (`encodeURIComponent`)
  before being interpolated into the URL (`games.ts`, `client-helpers.ts`;
  pinned by "percent-encodes the id in the path" in `games.test.ts`).

### Child collection factory (`gameDefinitionsApi` / `gameEffectsApi` / `gameMappingsApi`)

- **child-api-shared-factory**: `gameDefinitionsApi`, `gameEffectsApi`, and
  `gameMappingsApi` MUST each be produced by the one `childApi` factory
  function, parameterized by a base route and a `{fromWire, toWire}` codec,
  rather than three independent implementations (`games.ts`).
- **child-list-scoped-by-game-query**: `childApi(...).list(gameId)` MUST
  request `GET <base>?gameId=<encoded gameId>` and map every row through
  the codec's `fromWire` (`games.ts`; pinned by "filters each child
  collection by game in the QUERY" in `games.test.ts`).
- **child-list-unsorted**: `childApi(...).list` MUST NOT apply any sort of
  its own to the rows it returns — unlike `gamesApi.list`, it returns the
  mapped rows in the order the generic list route's query planner produced
  them (`games.ts`).
- **child-create-parent-in-body**: `childApi(...).create(gameId, input)`
  MUST send `gameId` as a field of the POST BODY (alongside
  `codec.toWire(input)`), never as a query parameter, for the same reason
  as `games-create-ecosystem-in-body` (`games.ts`; pinned by "parents a
  created definition/effect/mapping through the BODY, not the query" in
  `games.test.ts`).
- **child-update-full-put**: `childApi(...).update(id, input)` MUST PUT to
  `<base>/<encoded id>` with a body built from `codec.toWire(input)` alone
  (`games.ts`).
- **child-delete-no-body**: `childApi(...).delete(id)` MUST send `DELETE
  <base>/<encoded id>` with no request body and resolve to `void`
  (`games.ts`).
- **child-create-update-no-conflict-mapping**: `childApi(...).create` and
  `childApi(...).update` MUST propagate any error from the request
  unchanged — neither wraps its call in a `try`/`catch`, unlike
  `gamesApi.create`/`update`, so a 409 conflict on a definition, effect, or
  mapping surfaces as whatever raw message the generic CRUD route returned,
  never a `gamesApi`-style friendly, entity-named message (`games.ts`).
- **definitions-use-real-codec**: `gameDefinitionsApi` MUST be built with
  `{ fromWire: definitionFromWire, toWire: definitionToWire }`, applying
  the nullable-text and jsonb crossings on every read and write
  (`games.ts`).
- **effects-mappings-use-identity-codec**: `gameEffectsApi` and
  `gameMappingsApi` MUST be built with the shared `identityCodec`, whose
  `fromWire` returns the row unchanged and whose `toWire` spreads the
  input into a plain object — because neither `GameEffect` nor
  `GameMapping` has a nullable-text or jsonb column requiring translation
  (`GameEffect.duration` is already typed `number | null` with no crossing
  needed) (`games.ts`).

### Routing

- **fixed-route-bases**: the module MUST address exactly four fixed base
  routes — `/api/game/games`, `/api/game/definitions`, `/api/game/effects`,
  `/api/game/mappings` — as module-level constants, never built or
  discovered at runtime (`games.ts`).
- **api-prefix-is-a-rewrite**: the `/api` prefix on every route MUST be
  understood as a frontend rewrite (mapping `/api/:path*` onto the
  backend's own prefix-less routes) rather than a literal backend path
  segment, the same shape `/api/team/teams` and `/api/bucket/buckets` use
  elsewhere in the app (`games.ts` header comment).

## Appearance

Not applicable — this is domain logic, not a visual component.

## States

Not applicable — this is domain logic, not a visual component.

## Accessibility

Not applicable — this is domain logic, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-games-001 | games-list-scoped-by-ecosystem-query | `gamesApi.list("ecosystem.acme")` | Request URL `/api/game/games?ecosystemId=ecosystem.acme` ("filters the catalog by ecosystem in the QUERY", `games.test.ts`) |
| hub-domain-games-002 | games-list-scoped-by-ecosystem-query | `gamesApi.list()` (no argument) | Request URL `/api/game/games` with no query string ("asks for the whole catalog when no ecosystem is named", `games.test.ts`) |
| hub-domain-games-003 | games-for-ecosystem-single-result | `gamesApi.forEcosystem("ecosystem.acme")` where the list response has one matching row | Resolves to that `Game`; request URL `/api/game/games?ecosystemId=ecosystem.acme` ("resolves the one game of an ecosystem", `games.test.ts`) |
| hub-domain-games-004 | games-for-ecosystem-single-result | `gamesApi.forEcosystem("ecosystem.acme")` where the list response is `[]` | Resolves to `null` ("answers null for an ecosystem with no game", `games.test.ts`) |
| hub-domain-games-005 | games-create-ecosystem-in-body | `gamesApi.create(gameInput, "ecosystem.acme")` | Request URL has no `ecosystemId=` query param; request body's `ecosystemId` field equals `"ecosystem.acme"` ("stamps a created game into its ecosystem through the BODY, not the query", `games.test.ts`) |
| hub-domain-games-006 | games-update-omits-ecosystem | `gamesApi.update("8f2b1c40-...", gameInput)` | Request URL `/api/game/games/8f2b1c40-...`; request body has no `ecosystemId` property ("does not resend the ecosystem on update", `games.test.ts`) |
| hub-domain-games-007 | id-percent-encoded-in-path | `gamesApi.delete("a b")` | Request URL `/api/game/games/a%20b` ("percent-encodes the id in the path", `games.test.ts`) |
| hub-domain-games-008 | child-list-scoped-by-game-query | `gameDefinitionsApi.list("8f2b1c40-...")`, `gameEffectsApi.list("8f2b1c40-...")`, `gameMappingsApi.list("8f2b1c40-...")` | Request URLs `/api/game/definitions?gameId=8f2b1c40-...`, `/api/game/effects?gameId=8f2b1c40-...`, `/api/game/mappings?gameId=8f2b1c40-...` respectively ("filters each child collection by game in the QUERY", `games.test.ts`) |
| hub-domain-games-009 | child-create-parent-in-body | `gameDefinitionsApi.create("8f2b1c40-...", definitionInput)` | Request URL `/api/game/definitions`; request body's `gameId` field equals `"8f2b1c40-..."` ("parents a created definition through the BODY, not the query", `games.test.ts`) |
| hub-domain-games-010 | child-create-parent-in-body | `gameEffectsApi.create("8f2b1c40-...", effectInput)` | Request URL `/api/game/effects`; request body's `gameId` field equals `"8f2b1c40-..."` ("parents a created effect through the BODY, not the query", `games.test.ts`) |
| hub-domain-games-011 | child-create-parent-in-body | `gameMappingsApi.create("8f2b1c40-...", mappingInput)` | Request URL `/api/game/mappings`; request body's `gameId` field equals `"8f2b1c40-..."` ("parents a created mapping through the BODY, not the query", `games.test.ts`) |
| hub-domain-games-012 | game-definition-input-excludes-author | `gameDefinitionsApi.create("8f2b1c40-...", definitionInput)` | Request body has no `authorCustomerId` property ("never sends a definition's author, which the route owns", `games.test.ts`) |
| hub-domain-games-013 | games-create-conflict-mapping | `gamesApi.create(gameInput, "ecosystem.acme")` where the POST responds `409` with a body message containing `"already exists"` | Rejects with `Error("A game with slug \"cavern\" already exists.")` ("names the entity, not the constraint, when a slug is taken", `games.test.ts`) |
| hub-domain-games-014 | nullable-text-read | `gameFromWire({ ...gameRow, description: null })` | `.description === ""`; every other field (e.g. `.slug`, `.eventRetentionDays`) unchanged from the wire row ("reads a null description as an empty field", `games.test.ts`) |
| hub-domain-games-015 | nullable-text-read | `gameFromWire(gameRow)` where `gameRow.description === "Cold."` | `.description === "Cold."` ("keeps a description that is actually there", `games.test.ts`) |
| hub-domain-games-016 | nullable-text-write | `gameToWire({ ...gameInput, description: "" })` and `gameToWire({ ...gameInput, description: "   " })`; same two cases through `definitionToWire` | `.description === null` in all four cases ("writes an empty box as an empty COLUMN, not an empty string in one", `games.test.ts`) |
| hub-domain-games-017 | nullable-text-read | `definitionFromWire({ ...definitionRow, description: null })` | `.description === ""`; `.authorCustomerId === ""` unchanged ("applies the same reading rule to a definition", `games.test.ts`) |
| hub-domain-games-018 | jsonb-read-as-indented-text | `gameFromWire({ ...gameRow, engineConfig: { seed: 7 } })` | `.engineConfig === '{\n  "seed": 7\n}'`, typed `string` ("reads a config OBJECT as the JSON text the operator edits", `games.test.ts`) |
| hub-domain-games-019 | jsonb-write-as-parsed-value | `gameToWire({ ...gameInput, engineConfig: '{"seed":7}' })` | `.engineConfig` deep-equals `{ seed: 7 }`, not the original string ("parses the operator's text into a JSON VALUE on the way out", `games.test.ts`) |
| hub-domain-games-020 | jsonb-empty-value-differs-by-column | `gameFromWire(gameRow)` where `engineConfig === {}`; `gameToWire({ ...gameInput, engineConfig: "" })` and with `"   "` | Read: `.engineConfig === ""`. Write: `.engineConfig` deep-equals `{}` (never `null`) in both whitespace cases ("crosses an empty engine config as the empty OBJECT, both ways", `games.test.ts`) |
| hub-domain-games-021 | jsonb-read-null-as-empty-text | `gameFromWire({ ...gameRow, engineConfig: null })` | `.engineConfig === ""` ("reads a null engine config as an empty field, whatever the type says", `games.test.ts`) |
| hub-domain-games-022 | jsonb-empty-value-differs-by-column | `definitionFromWire(definitionRow)` where `data === null`; `definitionToWire({ ...definitionInput, data: "" })` | Read: `.data === ""`. Write: `.data === null` (never `{}`) ("crosses an empty definition payload as NULL, both ways", `games.test.ts`) |
| hub-domain-games-023 | jsonb-write-as-parsed-value, jsonb-read-as-indented-text | `definitionToWire({ ...definitionInput, data: '{"prose":"a hall"}' })`, then `definitionFromWire({ ...definitionRow, data: <that written value> })` | Write: `.data` deep-equals `{ prose: "a hall" }`. Read-back: `.data === '{\n  "prose": "a hall"\n}'` ("round-trips a real payload through both directions of the crossing", `games.test.ts`) |
| hub-domain-games-024 | jsonb-write-refuses-unparseable-text | `gameToWire({ ...gameInput, engineConfig: "{oops" })` and `definitionToWire({ ...definitionInput, data: "{oops" })` | Both throw an `Error` whose `.status === 400` and `.message` is `"Engine config must be valid JSON."` / `"Data must be valid JSON."` respectively ("refuses unparseable JSON with a 4xx the shared reporter drops", `games.test.ts`) |

## Edge Cases

- **Null/empty input**: An empty or whitespace-only `description` MUST
  write as the empty COLUMN (`null`), never an empty string in the column
  (nullable-text-write, hub-domain-games-016). An empty or whitespace-only
  `engineConfig`/`data` MUST write as that column's own empty JSON value —
  `{}` for `engineConfig`, `null` for `data` — never as the other column's
  empty value (jsonb-empty-value-differs-by-column, hub-domain-games-020,
  -022). An empty catalog LIST resolves to `[]` for `gamesApi.list`/
  `childApi.list`, which `forEcosystem` further reduces to `null`
  (games-for-ecosystem-single-result, hub-domain-games-004).
- **Boundary/malformed values**: JSON text that fails `JSON.parse` MUST be
  refused with a 4xx `clientRefusal` rather than stored as a JSON string
  (jsonb-write-refuses-unparseable-text, hub-domain-games-024).
  `GameEffectInput.trigger`/`operation` of `""` (a caller precondition the
  type signature itself documents as a valid, if incomplete, draft state —
  see `game-effect-input-allows-blank-selection`) and a caller-supplied
  `eventRetentionDays` outside the schema's `> 0` check are both sent to
  the backend exactly as given; this client applies no client-side range
  or closed-set validation of its own to either field, relying entirely on
  the database `check` constraints the source's own comments document for
  `character_names`, `status`, `event_log`, `trigger`, `operation`, and
  `event_retention_days`.
- **Concurrent access**: This module is plain single-threaded JavaScript
  with no actor, lock, or queue of its own — every exported function is an
  independent `async` call, and nothing here serializes two calls made at
  once. Two closely-timed `gamesApi.create` calls for the same
  `(ecosystemId, slug)` are not deduplicated client-side; the backend's own
  unique constraint (the one `games-create-conflict-mapping` maps to a
  friendly message) is the actual guard. The same race against a
  definition/effect/mapping's uniqueness constraint (if the backend has
  one) is NOT given a friendly mapping at all, per
  `child-create-update-no-conflict-mapping` — it would surface as the raw
  backend message.
- **Error states**: Every request this module makes can reject with
  whatever `authedJson`/`authedRequest` (`@agentic-toolkit/auth`'s client)
  throws — an `AuthHttpError` carrying an HTTP status and a backend-derived
  message for a non-2xx response, or a plain rejected `Promise` for a
  network-level failure that never reached the server. `gamesApi.create`/
  `update` narrow exactly one case of that (a message matching
  `/already exists/i`) into a friendly, entity-named error and rethrow
  every other error unchanged; no other function in this module inspects
  or transforms a caught error at all — `gamesApi.list`/`forEcosystem`/
  `delete` and every `childApi` method let any rejection propagate
  untouched.
- **Offline/disconnected state**: This module has no offline cache, no
  queued-write mechanism, and no reconnection logic; every operation is a
  single live round trip that rejects outright when the network is
  unavailable, with no retry attempted by this module (the underlying
  `authedFetch`'s one-refresh-and-retry applies only to a `401`, an
  authentication concern documented in `auth-client`, not a network-outage
  retry of this domain's own operations).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ecosystemId` | `string \| undefined` (`gamesApi.list`/`forEcosystem`) | `undefined` | Column-filters the catalog to one ecosystem; omitted, the call returns every game the caller can see |
| `gameId` | `string` (`childApi(...).list`/`create`) | none — required | The parent game every child-collection call is scoped to; sent as a query filter on `list`, a body field on `create` |
| `GAMES` (`/api/game/games`) | internal constant | fixed | Base route for every generic-CRUD `gamesApi` call |
| `DEFINITIONS` (`/api/game/definitions`) | internal constant | fixed | Base route for `gameDefinitionsApi` |
| `EFFECTS` (`/api/game/effects`) | internal constant | fixed | Base route for `gameEffectsApi` |
| `MAPPINGS` (`/api/game/mappings`) | internal constant | fixed | Base route for `gameMappingsApi` |
| `ENGINE_CONFIG_EMPTY` (`{}`) | internal constant | fixed | The JSON value `engineConfig`'s empty box crosses to/from, matching `games.engine_config`'s `NOT NULL DEFAULT '{}'` |
| `DEFINITION_DATA_EMPTY` (`null`) | internal constant | fixed | The JSON value `data`'s empty box crosses to/from, matching `definitions.data`'s nullable column |

## Deep Linking

Not applicable: `games.ts` owns no URL scheme, route registration, or deep
link of its own — it is an HTTP API client whose four fixed base routes
(`GAMES`, `DEFINITIONS`, `EFFECTS`, `MAPPINGS`) are backend endpoints, not
front-end navigable links.

## Localization

- **Hardcoded English strings**: `rethrowConflict`'s friendly message,
  `A game with slug "<slug>" already exists.` (both `gamesApi.create` and
  `gamesApi.update`), and `textToJson`'s two refusal messages, `Engine
  config must be valid JSON.` and `Data must be valid JSON.`, are fixed
  English with no lookup table, i18n key, or locale parameter anywhere in
  this module.

This is a plain, honestly-reported fact about the current source, not a
hidden gap (see Compliance).

## Accessibility Options

Not applicable — this is domain logic, not a visual component; it defines
no Reduce Motion, Increase Contrast, or Differentiate-Without-Color
behavior of its own.

## Feature Flags

Not applicable: the module's own header comment states the omission is
deliberate — the four tables this client writes "sit behind no roles-layer
feature gate at all," because a game is ECOSYSTEM-level configuration
rather than a workspace-owned artifact, and no file in `games.ts` reads or
defines a feature-flag key.

## Analytics

Not applicable: no file in this module emits a client-side analytics or
telemetry event.

## Privacy

- **Data collected**: Game/definition/effect/mapping catalog metadata only
  — slugs, names, descriptions, engine identifiers and configuration,
  status/character-name/event-log settings, effect triggers and deltas,
  and mapping edges. The module's own header comment states this
  deliberately excludes the `game` schema's eight other, player-state
  tables, which have no operator read path through this client.
- **Storage**: This module holds no cache of its own; every call is a live
  round trip through `authedJson`/`authedRequest`.
- **Transmission**: Every request travels through the injected
  `@agentic-toolkit/auth` Bearer-token client (`authedJson`/
  `authedRequest`, re-exported via `./http`); this module itself attaches
  no credentials and reads no cookies (see `auth-client`).
- **Retention**: Not applicable — this module retains nothing between
  calls; it has no cache with a lifetime to document.

## Logging

Not applicable: no file in this module calls `console.log`,
`console.warn`, `console.error`, or any platform logging API. Every
failure this module detects is either remapped and rethrown
(`games-create-conflict-mapping`, `jsonb-write-refuses-unparseable-text`)
or propagated unchanged; logging that failure is the caller's
responsibility.

## Platform Notes

- **React/Web**: This is the reference implementation —
  `packages/web/packages/data/src/games/games.ts`. `gamesApi` and the
  `childApi(base, codec)` factory are plain `async` functions over
  `authedJson`/`authedRequest` (themselves over `fetch`); the two wire
  crossings are centralized in `gameFromWire`/`gameToWire`/
  `definitionFromWire`/`definitionToWire`, and `games.test.ts` (Vitest,
  with a stubbed global `fetch`) pins every route/body/crossing
  requirement documented above.
- **SwiftUI / AppKit / UIKit**: No Apple implementation of this domain
  exists yet. A port would model `Game`/`GameDefinition`/`GameEffect`/
  `GameMapping` as `Codable, Hashable, Sendable` structs (the closed-set
  fields as Swift `enum`s with a `String` raw value and a lenient
  `init(from:)` for an unrecognized wire value, mirroring the fallback
  behavior `narrow` gives the web client elsewhere in this package); the
  two wire crossings would live in each type's `Codable` `init(from:)`/
  `encode(to:)` rather than in free functions, and every network call
  would be an `async throws` `URLSession` request analogous to
  `EcosystemsDataSource`'s pattern in `hub-domain-ecosystems`.
- **Compose / Android**: A `data class` per row type (with a `sealed
  interface` or `enum class` for each closed set) plus `Retrofit`/`Ktor`
  service interfaces mirroring `gamesApi`/`childApi`'s four fixed base
  routes is the idiomatic equivalent; the two wire crossings would live in
  a `Moshi`/`kotlinx.serialization` custom adapter for the affected fields,
  and a `ViewModel` exposing `StateFlow` would replace the bare `Promise`
  return values.
- **WinUI 3**: `HttpClient` replaces `fetch`/`authedJson` for every
  `/api/game/*` request this recipe documents, with the Bearer token
  attached the same way `auth-client`'s access-token/refresh waterfall
  does today. `System.Text.Json` (`JsonSerializer`/`JsonNode`) replaces the
  `JSON.parse`/`JSON.stringify` pair in `jsonToText`/`textToJson` — a
  `JsonNode`'s `ToJsonString(new JsonSerializerOptions { WriteIndented =
  true })` reproduces the two-space indented text `jsonToText` produces,
  and `JsonNode.Parse` reproduces `textToJson`'s parse, with a caught
  `JsonException` translated into the same "<label> must be valid JSON."
  refusal. Each closed-set type (`GameCharacterNames`, `GameStatus`,
  `GameEventLog`, `GameDefinitionStatus`, `GameEffectTrigger`,
  `GameEffectOperation`) is naturally a C# `enum` with a
  `JsonStringEnumConverter`, though the web client's lenient behavior of
  falling back on an unrecognized backend string (via `narrow`, used
  elsewhere in this package) has no automatic .NET equivalent and would
  need an explicit converter that catches the enum-parse failure. A record
  type per row (`Game`, `GameDefinition`, `GameEffect`, `GameMapping`) with
  `Task`-returning methods on a small set of typed service classes — one
  per base route, or one generic class parameterized the way `childApi` is
  — reproduces the module's shape; `Uri.EscapeDataString` replaces `enc`
  for every id interpolated into a path.

## Design Decisions

**Decision**: The parent id (`ecosystemId` for a game, `gameId` for a
child row) travels as a query parameter on LIST but as a BODY field on
CREATE, rather than using one spelling for both.
**Rationale**: The generic CRUD backend's LIST route reads query
parameters as column filters, while its POST route reads no query
parameters at all — a create that named its parent in the query string
would either insert a row with no parent (a `NOT NULL` violation surfacing
as an opaque backend fault) or, for the ecosystem case specifically,
silently default to the caller's own ecosystem instead of the one they
asked for. Using one consistent spelling would be simpler to read but
would misfile data.
**Approved**: pending

**Decision**: `gamesApi.forEcosystem` is implemented as `list(ecosystemId)[0]
?? null` rather than as a dedicated single-row backend endpoint.
**Rationale**: `game.games` is guarded by a partial unique index,
`uq_games_ecosystem` on `(ecosystem_id) WHERE deleted_at IS NULL`, so a
column-filtered list for one ecosystem can never return more than one live
row. Reusing the existing LIST route and taking the first result costs one
fewer backend endpoint to build and maintain, and the safety of doing so
follows directly from a database constraint rather than a client-side
assumption.
**Approved**: pending

**Decision**: `engineConfig`'s empty JSON value is `{}` while `data`'s
empty JSON value is `null`, and `jsonToText`/`textToJson` take that value
as an explicit `emptyValue` parameter rather than hardcoding one shared
empty representation.
**Rationale**: `games.engine_config` is `NOT NULL` with a `{}` default, so
its empty state IS the empty object; `definitions.data` is nullable, so
its empty state IS the null column. Posting `null` to the first would 500
at the column; posting `{}` to the second would show the operator two
characters they never typed. The two columns' empties are a schema fact,
not a preference, so the helper is parameterized rather than picking one
answer for both.
**Approved**: pending

**Decision**: `gamesApi.create`/`update` catch and remap a conflict to a
friendly, entity-named message; the three `childApi`-built clients
(`gameDefinitionsApi`, `gameEffectsApi`, `gameMappingsApi`) catch nothing
at all.
**Rationale**: This is a genuine, current asymmetry, not an oversight this
recipe is inventing a justification for: `gamesApi.create`'s own
`rethrowConflict` call names the one conflict a game's create/update path
is known to hit (a duplicate `(ecosystem, slug)`), while the shared
`childApi` factory was written generically across three row types with no
single friendly message that fits all three. A future friendly-message
addition for a child collection should follow `rethrowConflict`'s existing
message-sniffing pattern rather than inventing a new one.
**Approved**: pending

**Decision**: `rethrowConflict` (in `http.ts`) decides whether to remap an
error by testing the caught error's `.message` against `/already
exists/i`, not by checking its HTTP status code.
**Rationale**: Per `http.ts`'s own doc comment, generic CRUD answers a
duplicate row or identifier with an HTTP 409 whose message contains
"already exists" — but a 409 can also mean a different kind of conflict
with a different message. Matching on the message content, rather than on
the status code alone, keeps `rethrowConflict` from friendly-ifying a 409
that means something else; the cost is that a genuine duplicate whose
backend message happens not to contain that exact phrase would pass
through unmapped, which is the behavior `games-create-conflict-mapping`
and `games-update-conflict-mapping` document as-is rather than as an
idealized "always maps a 409."
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | failed | Access Patterns |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | failed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` **passed**: the wire types (`GameWire`,
`GameDefinitionWire`) are kept distinct from the client-facing `Game`/
`GameDefinition` types, and both column crossings are held in one set of
functions (`gameFromWire`/`gameToWire`/`definitionFromWire`/
`definitionToWire`) rather than repeated at each call site; the generic
`childApi` factory keeps transport shape separate from the three row
types it serves. `explicit-error-handling` **passed**: no path in this
module silently drops a failure — every error either matches a specific
remap (`rethrowConflict`'s message test, `textToJson`'s `clientRefusal`)
or propagates unchanged; nothing is caught and discarded.
`unit-test-coverage` **partial**: `games.test.ts` exercises `gamesApi`'s
full surface (list scoping, `forEcosystem`, create/update body-vs-query
scoping, conflict mapping, delete's id-encoding) and both column crossings
exhaustively, but never exercises `childApi`'s `update` or `delete` for
any of the three child collections, and never exercises
`child-create-update-no-conflict-mapping`'s no-remap behavior directly.
`error-response-handling` **partial**: the module distinguishes a
"duplicate slug" conflict from every other error by message content in
exactly two functions (`gamesApi.create`/`update`); it never distinguishes
a `404` from any other status anywhere (there is no `isNotFound`-style
branch in this file, unlike `hub-domain-ecosystems`'s `ecosystemsApi.get`),
and the three `childApi` clients distinguish nothing at all.
`retry-with-backoff` **failed**: no file in this module retries a failed
request; the underlying `authedFetch`'s one-refresh-then-retry is a
401-specific auth waterfall (see `auth-client`), not a retry of this
domain's own operations. `offline-behavior` **failed**: this module
defines no offline-cache-first read path and no queued-write-when-offline
behavior; every call is a live round trip that fails outright when the
network is unavailable. `timeout-handling` **failed**: no call in this
module sets a timeout or passes an `AbortSignal`; a hung request hangs
until the underlying `fetch` itself resolves or rejects.
`idempotent-operations` **partial**: every `update`/PUT in this module
sends the full replacement state, which is naturally idempotent to repeat;
no `create`/POST carries an idempotency key, so a client-level retry of a
create (were one ever added) could not distinguish a genuine duplicate
request from a second, different create — the module currently avoids the
question entirely by never retrying. `input-sanitization` **partial**:
`textToJson` enforces JSON-parseability before a `jsonb` write and
`emptyToNull` trims text before the null crossing, but every closed-set
field this module sends (`characterNames`, `status`, `eventLog`,
`trigger`, `operation`) is passed through with no client-side check
against its own closed set, relying entirely on the backend's database
`check` constraints. `data-minimization` **passed**: every field this
module reads or writes is game/definition/effect/mapping catalog
metadata; its own header comment states the deliberate exclusion of the
schema's player-state tables. `no-hardcoded-strings` **failed**: every
user-facing string this module produces (the conflict message, the two
JSON-refusal messages) is fixed English with no lookup table or locale
parameter (see Localization) — a plain, honestly-reported gap, not a
hidden one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe: the web `gamesApi`/`gameDefinitionsApi`/`gameEffectsApi`/`gameMappingsApi` contract over the `game` schema's four operator-writable tables. |
