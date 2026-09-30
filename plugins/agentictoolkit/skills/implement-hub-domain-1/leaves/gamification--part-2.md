<!-- leaf: implement-hub-domain-1/gamification--part-2 · source: hub-domain-gamification.md -->

# Hub Domain: Gamification — continued (part 2)

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

## Privacy

- **Data collected**: this component collects no analytics of its own. It transports realm configuration and gamification-catalog data (`RealmConfig`, `RealmCatalog`, `RealmBadge`, `RealmEventType`, and their create/update bodies) — none of which is end-user personal data. Neither given file reads, stores, or transmits a token or credential directly; the bearer access token attached to every request is handled entirely inside `authedJson`/`authedFetch` in `@agentic-toolkit/auth/client.ts`, outside these two given sources.
- **Storage**: not applicable — `gamification.ts`/`wire.ts` persist nothing themselves; every method is a stateless fetch call.
- **Transmission**: every request travels over whatever transport `authedJson` uses (outside these given sources); this component configures no TLS or transport-level behavior itself.
- **Retention**: not applicable — this component defines no retention policy of its own; retention of realm configuration, badges, levels, and event types is entirely the backend's concern.

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
**Rationale**: the source does not explain why. This is a notable divergence from the sibling component Hub Domain: Ecosystem Config, whose `signin-apps.ts` and `feature-flags.ts` call `rethrowConflict` to turn a backend 409 into a friendly, entity-named message before it reaches a caller. This recipe records the observed divergence rather than inventing a motive the source does not state.
**Approved**: pending
