<!-- leaf: implement-hub-domain-1/games · source: hub-domain-games.md -->

**Rules** (cite as `implement-hub-domain-1/games#<slug>`):

- `game-character-names-values` MUST
- `game-status-values` MUST
- `game-event-log-values` MUST
- `game-definition-status-values` MUST
- `game-effect-trigger-values` MUST
- `game-effect-operation-values` MUST
- `game-shape` MUST
- `game-id-is-opaque` MUST
- `game-event-retention-semantics` MUST
- `game-input-shape` MUST
- `game-definition-shape` MUST
- `game-definition-key-scope` MUST
- `game-definition-input-excludes-author` MUST
- `game-effect-shape` MUST
- `game-effect-duration-semantics` MUST
- `game-effect-sort-order-is-load-bearing` MUST
- `game-effect-input-allows-blank-selection` MUST
- `game-mapping-shape` MUST
- `game-mapping-input-shape` MUST
- `nullable-text-read` MUST
- `nullable-text-write` MUST
- `jsonb-read-as-indented-text` MUST
- `jsonb-write-as-parsed-value` MUST
- `jsonb-empty-value-differs-by-column` MUST
- `jsonb-read-null-as-empty-text` MUST
- `jsonb-write-refuses-unparseable-text` MUST
- `jsonb-serialization-collapse-is-defensive` MUST

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

