<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-model-catalog--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-model-catalog.md -->

# AIModelCatalog — continued (part 2)

## Platform Notes

- **SwiftUI**: The source (`packages/apple/AgenticToolkit/AIPluginKit/AIModelCatalog.swift`,
  bundled resource `model-catalog.json`, generator
  `packages/apple/AIPlugins/tools/generate_model_catalog.py`, tests
  `Tests/AIPluginKitTests/AIModelCatalogTests.swift`) has no SwiftUI
  dependency of its own — it is plain Swift, framework-agnostic. It is
  consumed today by AppKit view controllers under
  `macOS/Features/AIPlugins/Settings/` (`ModelPickerItem`,
  `ModelChooserViewController`, `ProviderPickerViewController`) purely as
  data; a SwiftUI consumer would call the same `resolve`/`model(named:)` API
  with no changes to this type.
- **Compose**: Model as Kotlin `data class`es — `data class Model(val id:
  String, val aliases: List<String> = emptyList(), val description:
  String? = null, val capabilities: List<String> = emptyList())` and a
  matching `Offering`/`ResolvedModel`, giving structural equality for free
  (matching Swift's `Equatable`). `kotlinx.serialization` with `@Serializable`
  and default values on the constructor reproduces `decodeIfPresent(...) ??
  []`. Replace `byName`/`byCanonicalID` with two `Map<String, Model>` built in
  an `init {}` block, and load `model-catalog.json` as an Android asset via
  `context.assets.open(...)` wrapped in a `runCatching { }.getOrNull()` to
  mirror `load(from:)`'s total (never-throwing) contract.
- **React/Web**: `interface Model { id: string; aliases: string[]; description?:
  string; capabilities: string[] }` plus matching `Offering`/`ResolvedModel`
  interfaces. Parse with a runtime validator (e.g. zod) instead of Swift's
  throwing `Codable` initializer, applying the same empty-array/`undefined`
  defaults explicitly since `JSON.parse` performs no schema coercion. Build
  `byName`/`byCanonicalID` as two `Map<string, Model>` at module load, and
  memoize the parsed catalog in a module-level `let shared: AIModelCatalog |
  null` (lazily computed on first access) as the equivalent of Swift's
  `static let shared`.
- **AppKit / UIKit**: No AppKit- or UIKit-specific API appears in this file;
  it is genuinely UI-framework-agnostic and only consumed by the AppKit view
  controllers named above. Nothing in this type needs to change to run under
  UIKit — only the consuming views differ.
- **WinUI 3**: This is the platform this recipe exists to steer. Model
  `Model`/`Offering`/`ResolvedModel` as C# `sealed record` types — e.g.
  `public sealed record Model(string Id, IReadOnlyList<string> Aliases,
  string? Description, IReadOnlyList<string> Capabilities)` — which give
  value semantics and structural equality matching Swift's `Equatable`.
  Decode with `System.Text.Json`'s `JsonSerializer.Deserialize<AIModelCatalog>`,
  using nullable properties with constructor defaults (or a custom
  `JsonConverter`) to reproduce `decodeIfPresent(...) ?? []`. Build
  `byName`/`byCanonicalID` as two `Dictionary<string, Model>` populated once
  in the record's constructor, exactly mirroring the Swift index-build loop
  (including last-writer-wins on a colliding key). Ship `model-catalog.json`
  as Content in the app package and load it via
  `Windows.ApplicationModel.Package.Current.InstalledLocation` (or an
  embedded-resource stream) instead of `Bundle.url(forResource:)`. Expose the
  loaded value through a `Lazy<AIModelCatalog>` (the `Lazy<T>` equivalent of
  Swift's `static let shared`), wrapping the file read and
  `JsonSerializer.Deserialize` call in a `try`/`catch` that falls back to an
  empty `AIModelCatalog` on any exception, matching `load(from:)`'s
  never-throw, empty-on-failure contract. `async`/`Task`-based file I/O is
  optional here since the resource is local and small; a synchronous read at
  startup is the direct port of the Swift `Bundle`/`Data(contentsOf:)` call.

## Design Decisions

- **Decision**: Split shared, per-model facts (`Model`: description,
  capabilities) from per-offering, per-gateway terms (`Offering`: context
  window, output limit, prices), keyed by `templateId` and the gateway's own
  spelling of the model.
  **Rationale**: The same model (e.g. `gpt-oss-120b`) is served by many
  gateways; describing it inside every provider's descriptor would copy one
  blurb dozens of times and let the copies drift, while a model's context
  window and token prices genuinely differ per gateway (one number would be
  wrong nearly everywhere) — both facts are stated directly in the source's
  top-of-file documentation comment.
  **Approved**: pending
- **Decision**: `AIModelCatalog.shared` never fails to exist — a missing,
  unreadable, or malformed `model-catalog.json` yields an empty catalog
  rather than a crash or a thrown error surfacing to the caller.
  **Rationale**: per the source comment on `shared`, "a stale or absent
  catalog costs descriptions, and must never take the provider UI down with
  it" — losing model descriptions is an acceptable degradation; losing the
  entire provider picker is not.
  **Approved**: pending
- **Decision**: Curated `ModelDetail` overrides only the descriptive fields
  (`description`, `tools`, `goodFor`) in `resolve(...)`, never the numeric
  `Offering` terms.
  **Rationale**: per the source comment on `resolve`, curated fields are
  "hand-written for the few flagship models where the generated blurb isn't
  good enough, and a regeneration must never silently overwrite that
  judgement" — but a gateway's context window and prices are facts the
  gateway itself reports, which curated prose has no authority to change.
  **Approved**: pending
- **Decision**: `canonicalID(_:)` strips only a fixed, explicit set of
  quantization/precision suffixes (checked longest-first), and leaves every
  other trailing token — `-turbo`, `-latest`, `-fast`, `-thinking` — alone.
  **Rationale**: `generate_model_catalog.py`'s sibling `canonical_model_id`
  (which this Swift function must mirror per its own doc comment) states
  these suffixes are "the same weights served at lower precision" and safe to
  fold onto the base model, while `-turbo`/`-fast`/`-latest`/`-thinking`
  "name genuinely different models or aliases" and must never be folded.
  **Approved**: pending
- **Decision**: `AIModelCatalog.schemaVersion` is carried on the wire and
  stored, but — unlike `AIPluginDescriptor.schemaVersion` — is never gated
  against a known-compatible range before the catalog is used.
  **Rationale**: no comment in `AIModelCatalog.swift`,
  `generate_model_catalog.py`, or the shipped catalog explains this
  asymmetry; the recipe records the behavior as it is
  (`schema-version-not-gated`): the framework ships and regenerates its own
  catalog, so there is no foreign payload to guard against today.
  **Approved**: pending
