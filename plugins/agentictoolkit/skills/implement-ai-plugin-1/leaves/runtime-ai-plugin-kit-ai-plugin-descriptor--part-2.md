<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor.md -->

# AI Plugin Descriptor — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor--part-2#<slug>`):

- `winui-3` MUST — a .NET port would model the four types as records deserialized with System.Text.Json — e.g. public sealed record …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `schemaVersion` | `Int` | `AIPluginDescriptor.currentSchemaVersion` (`3`) | `AIPluginDescriptor`'s descriptor-schema version; unvalidated by this type (see Edge Cases). |
| `identifier` | `String` | none (required) | `AIPluginDescriptor`'s unique plugin id. |
| `displayName` | `String` | none (required) | `AIPluginDescriptor`'s human-readable name; also the implicit template's `displayName`. |
| `version` | `String` | none (required) | `AIPluginDescriptor`'s plugin version string, unvalidated. |
| `models` | `[String]` | `[]` | `AIPluginDescriptor`'s model identifiers, rendered as a popup. |
| `defaultModel` | `String?` | `nil` | `AIPluginDescriptor`'s preselected model; falls back to `models.first` via `resolvedDefaultModel`. |
| `fields` | `[Field]` | `[]` | `AIPluginDescriptor`'s settings fields the host renders and persists. |
| `templates` | `[ProviderTemplate]?` | `nil` | `AIPluginDescriptor`'s explicit provider presets; `nil`/empty synthesizes one implicit template. |
| `key` | `String` | none (required) | `Field`'s config-bag lookup key and persisted-setting suffix. |
| `label` | `String` | none (required) | `Field`'s host-rendered label. |
| `kind` | `Field.Kind` | none (required) | `Field`'s `.secret` or `.text` storage classification. |
| `placeholder` | `String?` | `nil` | `Field`'s optional placeholder text. |
| `id` | `String` | none (required) | `ModelDetail`'s model-id key. |
| `description` | `String?` | `nil` | `ModelDetail`'s one-line model description. |
| `tools` | `Bool?` | `nil` | `ModelDetail`'s tool/function-calling support flag. |
| `goodFor` | `String?` | `nil` | `ModelDetail`'s "well-suited for" blurb. |
| `id` | `String` | none (required) | `ProviderTemplate`'s preset id. |
| `displayName` | `String` | none (required) | `ProviderTemplate`'s preset display name. |
| `defaultValues` | `[String: String]` | `[:]` | `ProviderTemplate`'s seeded config values injected before `buildRequest`. |
| `models` | `[String]` | `[]` | `ProviderTemplate`'s model list. |
| `defaultModel` | `String?` | `nil` | `ProviderTemplate`'s preselected model. |
| `secretRequired` | `Bool` | `true` | `ProviderTemplate`'s flag for whether a secret field must be filled. |
| `fields` | `[Field]?` | `nil` | `ProviderTemplate`'s field overrides; `nil` inherits the descriptor's `fields`. |
| `provider` | `String?` | `nil` | `ProviderTemplate`'s vendor name; falls back to `displayName` via `resolvedProvider`. |
| `llm` | `String?` | `nil` | `ProviderTemplate`'s model-brand label; falls back to `""` via `resolvedLLM`. |
| `configType` | `String?` | `nil` | `ProviderTemplate`'s auth-method label; falls back to `"API Key"`/`"Local"` via `resolvedConfigType`. |
| `providerDescription` | `String?` | `nil` | `ProviderTemplate`'s vendor blurb for the details pane. |
| `llmDescription` | `String?` | `nil` | `ProviderTemplate`'s model-family blurb for the details pane. |
| `modelDetails` | `[ModelDetail]?` | `nil` | `ProviderTemplate`'s per-model descriptive metadata. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (inline Swift literal, no lookup key) | "API Key" | `ProviderTemplate.resolvedConfigType`'s fallback when `configType` is `nil` and `secretRequired == true`; shown in the provider picker's Config Type column. |
| — (inline Swift literal, no lookup key) | "Local" | `ProviderTemplate.resolvedConfigType`'s fallback when `configType` is `nil` and `secretRequired == false`. |

Both strings are hardcoded English literals with no localization mechanism (no `NSLocalizedString`/`String(localized:)`/string-catalog lookup) anywhere in this file. Every other user-facing string on a descriptor (`displayName`, `label`, `placeholder`, `providerDescription`, `llmDescription`, etc.) is plugin-authored data passed through unchanged, not a string this file itself defines.

## Privacy

- **Data collected**: This type carries the metadata a plugin declares about its own settings, including which of those settings the plugin considers a credential. Per this file's own doc comments on `Field.Kind`, `.secret` marks a "masked entry, persisted to the Keychain (API keys, tokens)"; `.text` marks a "plain text entry, persisted to user defaults (base URLs, etc.)." The type itself collects nothing beyond decoding whatever `descriptor.json` and the host's own field values provide.
- **Storage**: `AIPluginDescriptor.swift` performs no storage of its own. The `.secret`/`.text` distinction is a contract honored by `PluginConfigStore.swift` and `AIProviderConfigStore.swift`, both of which route `field.isSecret` into `UserSetting(..., isSecure:)` to store secret values in the Keychain and non-secret values elsewhere (e.g. user defaults).
- **Transmission**: Not applicable at this layer — `AIPluginDescriptor.swift` contains no networking code; per this file's own doc comment, "the plugin's compiled `AIPlugin` contributes only request-building and response-decoding," so any transmission of a resolved secret happens in a different file.
- **Retention**: Not applicable at this layer — this type has no retention policy of its own; how long a Keychain- or user-defaults-stored value survives is governed entirely by whatever store implements the contract this type only labels.

## Platform Notes

- **SwiftUI**: not the source, but a real consumer — `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMProvidersView.swift` imports `SwiftUI` and `AIPluginKit` directly. `AIPluginDescriptor.swift` itself has no SwiftUI dependency; a SwiftUI view binds to instances returned by `AIPluginManager.descriptors`/`resolvedTemplates` as plain `Equatable` values inside `@State`/view-model properties — no `ObservableObject` wrapper is needed since every type here is immutable and `Sendable`.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIPluginDescriptor.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). The AppKit consumer `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMPickerView.swift` reads `resolvedTemplates`/`fields(for:)` directly to populate its `NSPopUpButton`/list UI with no bridging layer, since the model is Foundation-only (`Codable`, `Sendable`, `Equatable`) and equally usable from AppKit or SwiftUI.
- **Compose**: a Kotlin port would model `AiPluginDescriptor`, `Field`, `ModelDetail`, and `ProviderTemplate` as `@Serializable` (`kotlinx.serialization`) immutable `data class`es with `val` properties; `Field.Kind` as a `kotlinx.serialization`-backed enum with `secret`/`text` values. Because `kotlinx.serialization.json.Json` by default also requires a non-nullable, non-`@EncodeDefault` property's key to be present (mirroring json-decoding-required-keys), the same required/optional-key split from Behavioral Requirements carries over directly. Compose UI would read `resolvedTemplates()` into a `remember { mutableStateOf(...) }` or a `StateFlow` on a view model, not mutate the data class itself.
- **React/Web**: a TypeScript port models the same shape as plain `interface`s (`interface AIPluginDescriptor { schemaVersion: number; identifier: string; ... }`), decoded from JSON with a runtime validator (e.g. `zod`) rather than a bare `JSON.parse` cast, since `JSON.parse` alone would silently accept a `models`-less object where Swift's synthesized `Decodable` throws — the validator schema must mark `models`/`fields`/`schemaVersion`/etc. as required to reproduce that behavior. `resolvedDefaultModel`, `resolvedTemplates`, `fields(for:)`, and `modelDetail(for:)` become plain exported functions operating on the interface, since TypeScript has no struct-method equivalent tied to the data shape itself.
- **WinUI 3**: a .NET port would model the four types as `record`s deserialized with `System.Text.Json` — e.g. `public sealed record AiPluginDescriptor(int SchemaVersion, string Identifier, string DisplayName, string Version, IReadOnlyList<string> Models, string? DefaultModel, IReadOnlyList<AiPluginField> Fields, IReadOnlyList<AiPluginProviderTemplate>? Templates);` — with `Field.Kind` as an `enum Kind { Secret, Text }` decorated with a `JsonStringEnumConverter`/`JsonConverter` so the wire values stay the lowercase `"secret"`/`"text"` strings Swift's `RawRepresentable<String>` enum produces. Because `System.Text.Json`'s default behavior treats a missing property as its type's default (`null`/`0`/empty) rather than throwing — unlike Swift's synthesized `Decodable` — the port MUST mark `SchemaVersion`, `Identifier`, `DisplayName`, `Version`, `Models`, and `Fields` as C# 11 `required` record properties (or apply `[JsonRequired]`) to reproduce the json-decoding-required-keys behavioral requirement; otherwise a `descriptor.json` missing `"models"` would silently decode to an empty list instead of failing fast, as it does on Apple. `ResolvedDefaultModel`, `ResolvedTemplates`, `Fields(template)`, and `ModelDetail(for:)` become computed properties/methods on the record (records support member methods, so no separate service class is needed). Expose the resolved templates to XAML via an `ObservableCollection<AiPluginProviderTemplate>` on the hosting view model feeding a `ComboBox`/`ListView` `ItemsSource`, since the record itself needs no `INotifyPropertyChanged` — it mirrors the Swift `let`-only immutability from sendable-and-immutability.

