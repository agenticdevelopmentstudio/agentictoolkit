<!-- leaf: implement-hub-domain-1/applications--part-4 · source: hub-domain-applications.md -->

# Hub Domain Applications — continued (part 4)

**Rules** (cite as `implement-hub-domain-1/applications--part-4#<slug>`):

- `disclosure-safeguard` MUST — ApplicationTokenCreated — the one type that carries a raw plaintext secret in its token field — declares no …

## Privacy

- **Data collected**: a plaintext bearer secret (`ApplicationTokenCreated.token`) is returned
  exactly once, in the response to a successful `createToken(applicationID:name:)` call.
- **Storage**: `ApplicationsTopic` never persists the secret; `revealedSecrets` is an in-memory
  `[String: String]` on the `@MainActor`-isolated topic instance, with no file, `UserDefaults`, or
  Keychain write anywhere in these three files.
- **Transmission**: this component never transmits the secret itself — it receives it once from
  `createToken`'s response and places it into a read-only form field for on-screen display; actual
  network transmission is the injected `ApplicationsDataSource`'s concern, out of scope of these
  files.
- **Retention**: bounded by two independent mechanisms — the reveal-once rule
  (`token-secret-expires-on-navigation`), which drops the secret from `revealedSecrets` the moment
  navigation moves away from that token's detail, and the `ApplicationsTopic` instance's own
  lifetime (the dictionary holds nothing once the instance is deallocated).
- **Disclosure safeguard**: `ApplicationTokenCreated` — the one type that carries a raw plaintext
  secret in its `token` field — declares no `CustomStringConvertible`/`CustomDebugStringConvertible`
  override, so its synthesized default description includes the secret in full.
  `ApplicationsTopic.swift` never logs or prints a `created` value; it stores only its `token` into
  `revealedSecrets`. A port MUST NOT log this value.

## Platform Notes

- **SwiftUI**: not applicable to these files directly — `ApplicationsTopic` returns
  `HTDVLevel`/`HTDVDetail`/`FormSpec` values consumed by the shared `FormViewController`/HTDV
  presentation layer; a SwiftUI-based presenter would consume the same values unchanged, since
  `ApplicationsTopic.swift` imports no SwiftUI and performs no rendering itself.
- **AppKit / UIKit**: this is the source. `ApplicationsDataSource.swift`, `ApplicationsModels.swift`,
  and `ApplicationsTopic.swift` live in the `Hub` module shared between the
  `AgenticToolkitHub-macOS` and `AgenticToolkitHub-iOS` targets (both declared in `project.yml`,
  one source set). None of the three files imports `AppKit` or `UIKit` directly — each is plain
  `Foundation` (`ApplicationsTopic.swift` also imports `AgenticToolkitHTDV`), with the
  platform-specific `NSViewController`/`UIViewController` split handled entirely inside
  `FormViewController`, one layer below where these types operate.
- **Compose**: a Kotlin port would model `Application`/`ApplicationCreate`/`ApplicationUpdate`/
  `ApplicationToken`/`ApplicationTokenCreated` as immutable `data class`es, `ConsumerKind` as a
  Kotlin `enum class` with a custom deserializer mirroring the `.developer` fallback,
  `CrudPermissions`/`TableGrant`/`SchemaGrant` as plain (non-`@Serializable`) domain classes kept
  out of the wire-decoding path on purpose, and `ApplicationsTopic` as a class exposing a
  `suspend fun child(...)` returning a sealed `HtdvChild`; `revealedSecrets` becomes a
  `MutableMap<String, String>` confined to a single `Dispatchers.Main`-bound coroutine scope,
  mirroring `@MainActor`.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  runtime narrowing function for `ConsumerKind` (mirroring the `.developer` fallback instead of
  `zod`'s default throw-on-mismatch behavior), plain objects (not classes) for
  `CrudPermissions`/`TableGrant`/`SchemaGrant` kept out of any `JSON.stringify` path that reaches
  the network, and `async` functions returning `Promise<HtdvChild>` for `child(...)`; the
  reveal-once mechanic needs an explicit teardown (a router's route-leave hook keyed by the
  outgoing path's token id) to reproduce `expireRevealedSecret(unless:)`'s "same detail re-renders,
  anything else expires" rule — JavaScript's single-threaded event loop already gives the map
  mutation itself the safety `@MainActor` provides in Swift, so no extra confinement primitive is
  needed for that part.
- **WinUI 3**: a .NET port would model `Application`, `ApplicationCreate`, `ApplicationUpdate`,
  `ApplicationToken`, and `ApplicationTokenCreated` as `record`s (free structural equality,
  mirroring the Swift `Hashable` conformances), `ConsumerKind` as an `enum` with a custom
  `JsonConverter` that narrows an unrecognized `System.Text.Json` string to `Developer` instead of
  throwing, and `CrudPermissions`/`TableGrant`/`SchemaGrant` as plain classes with no
  `[JsonPropertyName]`/serialization attributes at all — kept deliberately unreachable from
  `System.Text.Json.JsonSerializer` the same way the Swift types are kept off `Codable`.
  `IApplicationsDataSource` would expose `Task<Application[]> ListAsync(string ecosystemId)`,
  `Task<ApplicationTokenCreated> CreateTokenAsync(string applicationId, string name)`, etc., backed
  by `HttpClient` + `System.Text.Json`. `ApplicationsTopic`'s equivalent would be a view-model class
  with `async Task<HtdvChild> ChildAsync(...)`; `revealedSecrets` becomes a
  `Dictionary<string, string>` field on a view model instantiated per-window/per-`ContentDialog`,
  with the one-shot expiry implemented in the page's `OnNavigatedFrom` override (or the view
  model's `Dispose`) rather than a `@MainActor`-checked property, and UI-bound lists
  (`ObservableCollection<T>`) rebuilt wholesale on every re-fetch rather than incrementally patched,
  mirroring the whole-list-rewrite pattern in `schema-save-rewrites-whole-list`.

## Design Decisions

**Decision**: `settingsDetail`'s save action re-homes an application's schema grants by writing
them to the new identifier BEFORE clearing them from the old one, rather than clearing first or
writing both in one call.
**Rationale**: per the source's own comment, there is no compensating write if the second call
fails; ordering the writes this way means a transient failure on the second (clearing) call merely
leaves a harmless duplicate of the grants under the now-stale old id, whereas the reverse order
would let a transient failure on the second (writing) call lose the grants outright.
**Approved**: pending

**Decision**: a token's plaintext secret is retained in `revealedSecrets` only until navigation
departs from the detail screen currently showing it, enforced by calling
`expireRevealedSecret(unless:)` at the top of every `child(...)` call rather than on a timer or a
view-disappear callback.
**Rationale**: per the source's own comment, retaining the secret for the whole session "made the
notice a lie" — `ApplicationsTopic.revealMessage` promises the secret disappears once the reader
has navigated away. Tying the check to the navigation path itself, rather than a lifecycle event a
presentation layer would have to remember to call, means the guarantee holds regardless of which
presentation layer drives it.
**Approved**: pending

**Decision**: `CrudPermissions`, `TableGrant`, and `SchemaGrant` are kept out of `Codable`
entirely, with the wire shape's translation left to an adapter outside these three files.
**Rationale**: per their own doc comments, this makes it impossible to serialize these domain
types onto the API by accident — a caller reaching for `JSONEncoder` on a `SchemaGrant` fails to
compile rather than silently producing the wrong wire shape (`{schemaId, crud, tables:
[{tableId, crud}]}` is not what the struct's stored properties would naively encode to).
**Approved**: pending

**Decision**: a table's permissions are rejected outright (not clamped or silently ignored) when
they exceed the schema grant's own ceiling, and selecting `"row"` as the permission level is
rejected outright rather than silently treated as `"table"`.
**Rationale**: both are explicit `HubError.validation` throws with user-facing messages
(`table-grant-ceiling-enforcement`, `table-grant-row-level-rejected`) rather than a quiet
downgrade, so the caller always knows why a save did not take effect instead of discovering a
narrower grant than requested only by inspecting it afterward.
**Approved**: pending

**Decision**: schema and table grant edits are persisted by rewriting the application's entire
`[SchemaGrant]` array on every save (`rewriteGrant`), rather than a per-field or per-grant PATCH.
**Rationale**: this keeps `ApplicationsTopic`'s write path uniform — one shape of call
(`setSchemaGrants(applicationID:_:)`) handles add, edit, and remove for both schema- and
table-level grants — at the cost of the concurrency exposure covered by the open question on
grants-write-concurrency; the source does not indicate whether this tradeoff was made knowingly or
because the backend has historically been treated as single-writer-per-application.
**Approved**: pending
