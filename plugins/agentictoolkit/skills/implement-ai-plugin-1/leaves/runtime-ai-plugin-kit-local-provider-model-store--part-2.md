<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-provider-model-store--part-2 · source: ai-plugin-runtime-ai-plugin-kit-local-provider-model-store.md -->

# LocalProviderModelStore — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseURL` (parameter to `isLocal`, `fetchModels`, `fetchSizes`, `fetchMetadata`, and the `cached*` reads) | `String` | none — required per call | The OpenAI-compatible base URL identifying the target server; used verbatim as the per-`baseURL` cache key and, after per-function trimming, as the network request target. |
| `model` (parameter to `fetchModelInfo`, `fetchMetadata`) | `String` | none — required per call | The model id to enrich or fetch metadata for; used verbatim as the global cache key for description/page-stats, and forwarded to each collaborator. |
| `viaOllamaPage` (parameter to `fetchModelInfo`) | `Bool` | none — required per call | Gates whether `OllamaModelPageStore.fetchInfo` (and therefore the returned/cached `stats`) is attempted at all. |
| `aiplugin.localModelCache` | settings key, `[String: [String]]` | `[:]` | Per-`baseURL` cache of the last successfully fetched model ids. |
| `aiplugin.localModelSizeCache` | settings key, `[String: [String: Int]]` | `[:]` | Per-`baseURL`, per-model cache of sizes in bytes from `/api/tags`. |
| `aiplugin.localModelMetadataCache` | settings key, `[String: [String: OllamaModelMetadata]]` | `[:]` | Per-`baseURL`, per-model cache of `/api/show` metadata. |
| `aiplugin.ollamaModelDescriptionCache` | settings key, `[String: String]` | `[:]` | Global (model-id-only) cache of the last resolved description. |
| `aiplugin.ollamaModelPageStatsCache` | settings key, `[String: LocalModelPageStats]` | `[:]` | Global (model-id-only) cache of the last resolved ollama.com page stats. |
| Request timeout (`fetchModels`, `fetchSizes`) | `TimeInterval` constant | `5` seconds | Hardcoded at each call site; not a parameter and not overridable from this file. |
| Loopback host set (`LocalModelServer`) | `Set<String>` constant | `{localhost, 127.0.0.1, 0.0.0.0, ::1, [::1]}` | Fixed in the collaborator type; not configurable from `LocalProviderModelStore`. |

## Privacy

- **Data collected**: No personal or account data. The store transmits a
  model id string to ollama.com's public model page (`fetchModelInfo` when
  `viaOllamaPage` is `true`, via `OllamaModelPageStore`) and to the
  caller-supplied `baseURL` (a user-configured local/loopback server) for
  the `/models`, `/api/tags`, and `/api/show` lookups. `fetchModelInfo` also
  triggers its collaborators `ModelCatalogStore` (openrouter.ai, models.dev,
  and the adh catalog endpoint) and `ArtificialAnalysisStore`
  (artificialanalysis.ai, which attaches any user-stored API key as an
  `x-api-key` header) — those requests originate inside those collaborator
  types, not this file, but are triggered by this file's call.
- **Storage**: Cached values (model ids, byte sizes, `OllamaModelMetadata`,
  free-text descriptions, page stats) persist on-device through the five
  `UserSetting`-backed keys listed under Configuration, via the default
  (non-secure) settings provider; none is marked `isSecure`.
- **Transmission**: Plain HTTP(S) `GET` requests to `{baseURL}/models`, the
  derived `.../api/tags`, and ollama.com's model page; one HTTP(S) `POST` to
  the derived `.../api/show` with a small JSON body (`{"model": <model>}`).
  No request in this file carries a credential or token.
- **Retention**: Cached values are retained indefinitely — this file
  provides no explicit clear, remove, or expiry operation for any of its
  five caches. A value is only ever replaced by a later successful fetch for
  the same key, or removed if the underlying settings store is cleared
  externally.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/LocalProviderModelStore.swift`,
  which `import AgenticToolkitCore`s its collaborators
  `LocalModelServer.swift` (same target) and, from Core,
  `ModelCatalogStore.swift`, `ArtificialAnalysisStore.swift`,
  `OllamaModelPageStore.swift`, `OllamaModelMetadata.swift` (which also
  defines `LocalModelMetadataStore`), and the `UserSetting`/`UserSettings`/
  `StorableSetting`/`SettingsStore` settings-storage stack. It has no
  SwiftUI dependency at all — its current consumers,
  `ModelChooserViewController.swift`/`ModelChooserContent.swift`, are
  AppKit, not SwiftUI. Concurrency comes from `@MainActor`, persistence from
  `UserSetting` (UserDefaults-backed by default), networking from
  `URLSession.shared`, and parsing from `JSONDecoder`.
- **Compose**: A Kotlin port has no direct `@MainActor` equivalent; use a
  plain singleton `object` whose mutating functions are confined to
  `Dispatchers.Main.immediate` (or guarded by a `Mutex`) to reproduce the
  same non-interleaved read-modify-write guarantee. Replace the five
  `UserSetting`s with `DataStore<Preferences>` (or a small Room table) keyed
  by the same string names, `kotlinx.serialization.json` in place of
  `JSONDecoder`/`JSONSerialization`, and `OkHttp`/Ktor `HttpClient` with a
  5-second timeout for the two direct GET/POST calls this file makes.
- **React/Web**: A module of plain async functions plus a module-level
  cache object (or `localStorage`/`IndexedDB` for persistence across
  reloads), each cache entry `JSON.stringify`d the way `Codable` serializes
  here. Use `fetch` with `AbortSignal.timeout(5000)` for the two 5-second
  bounds, and preserve `fetchModelInfo`'s ordering with `await catalog();
  await rank(); await (viaOllamaPage ? page() : null);` rather than
  `Promise.all`, since the source deliberately awaits sequentially, not
  concurrently.
- **AppKit / UIKit**: Identical to the SwiftUI note — this type is
  UI-framework-agnostic, and is in fact consumed today from AppKit
  (`ModelChooserViewController`), not SwiftUI. Nothing in the contract
  changes under UIKit.
- **WinUI 3**: Model `LocalProviderModelStore` as a plain static class (or a
  singleton service registered in DI) mirroring the enum-of-statics shape.
  Replace each `UserSetting<T>` with a JSON-serialized string stored in
  `Windows.Storage.ApplicationData.Current.LocalSettings` (its
  `ApplicationDataCompositeValue` does not natively hold nested
  dictionaries, so serialize each cache's value with `System.Text.Json`
  before storing, matching `Codable`'s round-trip here) — never the secure/
  credential-locker equivalent, matching `cache-non-secure-storage`. Use
  `HttpClient` with `Timeout = TimeSpan.FromSeconds(5)` for the `/models`
  and `/api/tags` `GET`s and a `POST` with `JsonContent.Create` for
  `/api/show`. Represent `LocalModelPageStats` as a
  `record struct LocalModelPageStats(string? Downloads, string? Updated)`.
  Reproduce `mainactor-atomic-cache-update` by performing each cache's
  read-modify-write inside a `SemaphoreSlim(1, 1)` (or by marshaling onto a
  single `DispatcherQueue`), and reproduce `model-info-sequential-order` with
  `await catalogTask; await rankTask; await pageTask;` — never
  `Task.WhenAll` — so the port preserves the source's deliberate ordering
  rather than parallelizing it.

## Design Decisions

**Decision**: `fetchModels` strips at most one trailing `/` from `baseURL`
before appending `/models`, while `LocalModelServer.nativeTagsURL(baseURL:)`
(used by `fetchSizes`) strips every trailing slash and a trailing `/v1` in a
loop.
**Rationale**: Not stated in a source comment; this is a design fact rather
than a documented rationale. The practical effect is that a `baseURL` with
more than one trailing slash produces a well-formed native tags URL via
`fetchSizes` but a request with an embedded double slash via `fetchModels`,
which typically 404s and folds into the ordinary failure path rather than
crashing.
**Approved**: pending

**Decision**: `fetchModelInfo` awaits the catalog description, the rank, and
(conditionally) the ollama.com page strictly in sequence, never concurrently.
**Rationale**: Per the doc comment, "The catalog and rank awaits come FIRST
so a chooser's N per-model tasks all join the same live round of each before
fanning out to N page fetches" — the sequencing exists to line up with
`ModelCatalogStore.catalog()`'s and `ArtificialAnalysisStore`'s own
in-flight-task coalescing (see their respective sources), not to slow this
call down; the page fetch runs last because it has no such coalescing and is
the one call unique to each model.
**Approved**: pending

**Decision**: The description and page-stats caches are keyed by model id
alone (global), while the models, sizes, and metadata caches are keyed by
`baseURL` (or `baseURL` plus model id).
**Rationale**: Per the doc comment on `descriptionCache`, "Remote models
only ever get catalog text... Keyed by model name alone, not by server" — a
model's prose description and community popularity are properties of the
model itself, not of which server happens to be hosting it, so two servers
exposing the same model id intentionally share one cached description and
one cached stats entry.
**Approved**: pending

**Decision**: `fetchModels`/`fetchSizes`/`fetchMetadata` provide no locality
guard of their own — nothing stops a caller from invoking them with a
non-loopback `baseURL`.
**Rationale**: `isLocal(baseURL:)` exists specifically as the caller-facing
decision point (as `ModelChooserViewController` uses it before choosing
between this store and the remote descriptor catalog); `fetchModels` in
particular is a generic OpenAI-compatible `/models` listing with no
inherent local-only assumption, so baking a loopback check into it would
narrow a function that is otherwise reusable.
**Approved**: pending
