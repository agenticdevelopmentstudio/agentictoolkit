<!-- leaf: implement-hub-domain-1/games--part-3 · source: hub-domain-games.md -->

# Hub Domain: Games — continued (part 3)

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
