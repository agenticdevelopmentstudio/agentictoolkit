<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor.md -->

# AI Plugin Descriptor

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor--edge-cases#<slug>`):

- `empty-models-fields-arrays-present-in-json` MUST — models: [] and fields: [] MUST decode successfully; resolvedDefaultModel MUST then fall back to "" when defaultModel is …
- `missing-models-or-fields-key` MUST (as opposed to present-but-empty) — decoding MUST throw DecodingError.keyNotFound, since both are non-Optional stored properties with no Codable-level …
- `empty-identifier-displayname-or-version-strings` MUST — decoding and construction MUST NOT reject an empty string; this type performs no non-empty validation on any of the …
- `defaultmodel-absent-explicit-null-or-naming-a-model-not-present-in-models` MUST — defaultModel MUST decode to nil when absent or null; resolvedDefaultModel performs no membership check against models, …
- `templates-absent-explicit-null-or-an-empty-array` MUST — all three MUST route to the same implicit-template branch of resolvedTemplates, since the guard is if let templates, …
- `malformed-kind-string` MUST (e.g. `"masked"` instead of `"secret"`/`"text"`) — decoding a Field MUST throw DecodingError.dataCorrupted, since Field.Kind is a String-backed RawRepresentable enum …
- `concurrent-access` MAY — Because every stored property across all four types is let and every type is Sendable, a single constructed value MAY …

## Edge Cases

- **Empty `models`/`fields` arrays present in JSON**: `models: []` and `fields: []` MUST decode successfully; `resolvedDefaultModel` MUST then fall back to `""` when `defaultModel` is also absent (vector 003).
- **Missing `models` or `fields` key** (as opposed to present-but-empty): decoding MUST throw `DecodingError.keyNotFound`, since both are non-Optional stored properties with no Codable-level default (json-decoding-required-keys, vector 011).
- **Empty `identifier`, `displayName`, or `version` strings**: decoding and construction MUST NOT reject an empty string; this type performs no non-empty validation on any of the three.
- **`defaultModel` absent, explicit `null`, or naming a model not present in `models`**: `defaultModel` MUST decode to `nil` when absent or `null`; `resolvedDefaultModel` performs no membership check against `models`, so a `defaultModel` naming a model absent from `models` MUST still be returned unchanged.
- **`templates` absent, explicit `null`, or an empty array**: all three MUST route to the same implicit-template branch of `resolvedTemplates`, since the guard is `if let templates, !templates.isEmpty` — only a non-nil, non-empty array bypasses synthesis.
- **`schemaVersion` at or beyond its documented boundary** (`0`, negative, `currentSchemaVersion`, or above): this type imposes no minimum or maximum; every `Int` value decodes successfully. Range acceptance (`2...currentSchemaVersion`) is validated by `AIPluginManager.discoverPlugins()`, not by this type (see Design Decisions).
- **Malformed `kind` string** (e.g. `"masked"` instead of `"secret"`/`"text"`): decoding a `Field` MUST throw `DecodingError.dataCorrupted`, since `Field.Kind` is a `String`-backed `RawRepresentable` enum whose synthesized `init(from:)` has no unknown-case fallback.
- **Identifier, field-key, and template-id uniqueness**: Neither `AIPluginDescriptor.identifier`, nor `Field.key` values within one descriptor's `fields` array, nor `ProviderTemplate.id` values within one descriptor's `templates` array are checked for uniqueness by this type on decode or construction; duplicates decode and construct successfully. Downstream, `AIPluginManager.template(pluginIdentifier:templateId:)` resolves a `templateId` via `resolvedTemplates.first { $0.id == templateId }`, so a duplicate `id` silently returns only the first match, with no error or signal that a collision occurred.
- **Concurrent access**: Because every stored property across all four types is `let` and every type is `Sendable`, a single constructed value MAY be read concurrently from multiple tasks or actors (e.g. simultaneously by a SwiftUI view and an AppKit controller) with no synchronization; no operation defined in this file mutates shared state.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) of its own to fail; locating and reading `descriptor.json` from a bundle is `AIPluginManager.readDescriptor(from:)`'s responsibility, not this type's.
- **Offline or disconnected state**: Not applicable — this file performs no network access of its own; the descriptor is decoded from a local resource shipped inside the `.aiplugin` bundle, per the type's own doc comment ("A plugin ships this as a plain JSON resource inside its `.aiplugin` bundle").
- **Cancellation and timeouts**: Not applicable — this file exposes no asynchronous or long-running operation; every member is a synchronous stored or computed property, or a pure synchronous function.
