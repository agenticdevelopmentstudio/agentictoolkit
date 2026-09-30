<!-- leaf: implement-hub-domain-1/games--part-2 · source: hub-domain-games.md -->

# Hub Domain: Games — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/games--part-2#<slug>`):

- `games-list-scoped-by-ecosystem-query` MUST
- `games-list-sorted-by-name` MUST
- `games-for-ecosystem-single-result` MUST
- `games-create-ecosystem-in-body` MUST
- `games-create-conflict-mapping` MUST
- `games-update-omits-ecosystem` MUST
- `games-update-conflict-mapping` MUST
- `games-delete-no-body` MUST
- `id-percent-encoded-in-path` MUST
- `child-api-shared-factory` MUST
- `child-list-scoped-by-game-query` MUST
- `child-list-unsorted` MUST
- `child-create-parent-in-body` MUST
- `child-update-full-put` MUST
- `child-delete-no-body` MUST
- `child-create-update-no-conflict-mapping` MUST
- `definitions-use-real-codec` MUST
- `effects-mappings-use-identity-codec` MUST
- `fixed-route-bases` MUST
- `api-prefix-is-a-rewrite` MUST

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

## Localization

- **Hardcoded English strings**: `rethrowConflict`'s friendly message,
  `A game with slug "<slug>" already exists.` (both `gamesApi.create` and
  `gamesApi.update`), and `textToJson`'s two refusal messages, `Engine
  config must be valid JSON.` and `Data must be valid JSON.`, are fixed
  English with no lookup table, i18n key, or locale parameter anywhere in
  this module.

This is a plain, honestly-reported fact about the current source, not a
hidden gap (see Compliance).

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

