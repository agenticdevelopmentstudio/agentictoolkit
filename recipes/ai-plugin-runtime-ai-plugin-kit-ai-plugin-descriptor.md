---
id: 39de0dff-2b26-4d3d-97a3-ebdbdb38846a
title: AI Plugin Descriptor
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The host-side model of a plugin''s descriptor.json: identity, models, settings
  fields, and provider templates AIPluginManager reads at discovery time.'
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- sendable
- foundation
- provider-config
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-chat-context
references: []
approved-by: ''
approved-date: ''
---

# AI Plugin Descriptor

## Overview

`AIPluginDescriptor.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIPluginDescriptor.swift`) defines the host-side model of a plugin's `descriptor.json`: its identity, the models it offers, and the settings fields the host should render and persist. A plugin ships this as a plain JSON resource inside its `.aiplugin` bundle. `AIPluginManager` reads it at plugin *discovery* time — before, and without ever, loading the plugin's compiled binary — so a host UI can list and configure a provider from data alone. All presentation and configuration metadata lives here as data; the plugin's compiled `AIPlugin` contributes only request-building and response-decoding (per `AIPlugin.swift`'s doc comment). The file defines four `Codable`, `Sendable`, `Equatable` value types: `AIPluginDescriptor` itself, `Field` (one configurable value), `ModelDetail` (optional per-model metadata), and `ProviderTemplate` (a named provider preset). None of the four performs I/O; the file's only "operations" are pure resolution helpers (`resolvedDefaultModel`, `resolvedTemplates`, `fields(for:)`, `modelDetail(for:)`) over already-decoded data.

## Behavioral Requirements

- **schema-version-field**: `AIPluginDescriptor` MUST include a `schemaVersion: Int` field identifying the descriptor schema the plugin bundle was authored against; this type imposes no minimum or maximum on the value, and any `Int` decodes successfully.
- **current-schema-version-constant**: `AIPluginDescriptor` MUST expose `public static let currentSchemaVersion = 3` naming the newest schema version the host understands; this constant is not itself an enforcement mechanism (see Design Decisions).
- **identity-fields-required**: `AIPluginDescriptor` MUST require `identifier: String`, `displayName: String`, and `version: String`, each with no default value; this type performs no format or non-empty validation on any of the three.
- **models-list**: `AIPluginDescriptor` MUST expose `models: [String]`, the model identifiers a host renders as a popup, defaulting to `[]` in the memberwise initializer.
- **default-model-optional**: `AIPluginDescriptor` MUST allow `defaultModel: String?` to be `nil`, defaulting to `nil` in the memberwise initializer.
- **resolved-default-model**: `AIPluginDescriptor.resolvedDefaultModel` MUST return `defaultModel` when it is non-nil, else `models.first`, else `""`.
- **fields-list**: `AIPluginDescriptor` MUST expose `fields: [Field]`, the settings the host renders as a form and persists per plugin, defaulting to `[]` in the memberwise initializer.
- **templates-optional**: `AIPluginDescriptor` MUST allow `templates: [ProviderTemplate]?` to be `nil` (a v2 descriptor with no explicit templates) or a non-nil array, defaulting to `nil` in the memberwise initializer.
- **resolved-templates-explicit**: `resolvedTemplates` MUST return `templates` unchanged when it is non-nil and contains at least one element.
- **resolved-templates-implicit-synthesis**: When `templates` is `nil` or an empty array, `resolvedTemplates` MUST return exactly one synthesized `ProviderTemplate` with `id: "default"`, `displayName` equal to the descriptor's `displayName`, empty `defaultValues`, `models`/`defaultModel` copied from the descriptor, `secretRequired: true`, and `fields` equal to the descriptor's own `fields`.
- **fields-for-template**: `fields(for:)` MUST return the given `ProviderTemplate`'s own `fields` when non-nil, else the descriptor's `fields`.
- **field-identity**: `Field` MUST require `key: String`, `label: String`, and `kind: Kind`, and MUST allow `placeholder: String?` to default to `nil`.
- **field-kind-values**: `Field.Kind` MUST be exactly one of `secret` or `text`, a `String`-raw-valued enum whose raw value equals the case name.
- **field-kind-storage-contract**: Per this file's own doc comments on `Field.Kind`, a `Field` whose `kind` is `.secret` MUST be understood by config-persistence consumers as a masked entry requiring Keychain storage (API keys, tokens), and a `Field` whose `kind` is `.text` MUST be understood as a plain entry requiring non-Keychain storage (e.g. user defaults, base URLs); `AIPluginDescriptor.swift` itself performs no storage — the contract is honored by `PluginConfigStore.swift` and `AIProviderConfigStore.swift`, both of which route `field.isSecret` into `UserSetting(..., isSecure:)`.
- **field-is-secret**: `Field.isSecret` MUST return `true` if and only if `kind == .secret`.
- **model-detail-identity**: `ModelDetail` MUST require `id: String`, and MUST allow `description: String?`, `tools: Bool?`, and `goodFor: String?` to each independently default to `nil`.
- **model-detail-lookup**: `ProviderTemplate.modelDetail(for:)` MUST return the first element of `modelDetails` whose `id` equals the given model id, or `nil` when `modelDetails` is `nil` or contains no matching `id`.
- **provider-template-identity**: `ProviderTemplate` MUST require `id: String` and `displayName: String`, and MUST default `defaultValues` to `[:]`, `models` to `[]`, `defaultModel` to `nil`, `secretRequired` to `true`, and `fields`, `provider`, `llm`, `configType`, `providerDescription`, `llmDescription`, and `modelDetails` each to `nil`.
- **provider-template-resolved-default-model**: `ProviderTemplate.resolvedDefaultModel` MUST return `defaultModel` when non-nil, else `models.first`, else `""` — the identical rule as `AIPluginDescriptor.resolvedDefaultModel`.
- **provider-template-resolved-provider**: `resolvedProvider` MUST return `provider` when non-nil, else `displayName`.
- **provider-template-resolved-llm**: `resolvedLLM` MUST return `llm` when non-nil, else `""`.
- **provider-template-resolved-config-type**: `resolvedConfigType` MUST return `configType` when it is non-nil; when `configType` is `nil`, it MUST return the literal string `"API Key"` if `secretRequired` is `true`, and the literal string `"Local"` otherwise.
- **json-decoding-required-keys**: Because none of `AIPluginDescriptor`, `Field`, `ProviderTemplate`, or `ModelDetail` declares a custom `init(from:)` or `CodingKeys`, the compiler-synthesized `Decodable` conformance MUST require every non-Optional stored property's JSON key to be present at decode time — for `AIPluginDescriptor`: `schemaVersion`, `identifier`, `displayName`, `version`, `models`, `fields`; for `Field`: `key`, `label`, `kind`; for `ProviderTemplate`: `id`, `displayName`, `defaultValues`, `models`, `secretRequired`; for `ModelDetail`: `id`. Decoding MUST throw `DecodingError.keyNotFound` if any of these is absent, even though the corresponding Swift initializer parameter has a default value for programmatic construction.
- **json-decoding-optional-keys**: Every Optional-typed stored property (`defaultModel`, `templates` on `AIPluginDescriptor`; `placeholder` on `Field`; `defaultModel`, `fields`, `provider`, `llm`, `configType`, `providerDescription`, `llmDescription`, `modelDetails` on `ProviderTemplate`; `description`, `tools`, `goodFor` on `ModelDetail`) MUST decode successfully to `nil` when its JSON key is absent or explicitly `null`.
- **codable-conformance**: `AIPluginDescriptor`, `Field`, `ModelDetail`, and `ProviderTemplate` MUST conform to `Codable` so a plugin's `descriptor.json` resource decodes directly via `JSONDecoder`.
- **equatable-conformance**: `AIPluginDescriptor`, `Field`, `ModelDetail`, and `ProviderTemplate` MUST conform to `Equatable`.
- **sendable-and-immutability**: `AIPluginDescriptor`, `Field`, `ModelDetail`, and `ProviderTemplate` MUST conform to `Sendable`, and every stored property across all four types MUST be declared `let`, so an instance is fully immutable after initialization and may cross an actor/concurrency-domain boundary with no synchronization.
- **decoding-error-propagation**: This file MUST NOT catch, transform, or swallow a decode failure; the compiler-synthesized `init(from:)` MUST propagate whatever `DecodingError` `JSONDecoder` produces to the caller, since the file declares no custom `init(from:)`, no validation logic, and no `Error` type of its own.

## Appearance

Not applicable — this is a host-side data model decoded from a plugin's `descriptor.json`, not a visual component.

## States

Not applicable — this is a host-side data model decoded from a plugin's `descriptor.json`, not a visual component. Any runtime lifecycle (plugin discovered, loaded, or failed to load) belongs to `AIPluginManager`, not to this type.

## Accessibility

Not applicable — this is a host-side data model decoded from a plugin's `descriptor.json`, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-descriptor-001 | identity-fields-required, field-identity, resolved-default-model | JSON `{schemaVersion:2, identifier:"com.example.provider", displayName:"Example", version:"1.2.3", models:["fast","smart"], defaultModel:"smart", fields:[{key:"apiKey",label:"API Key",kind:"secret"},{key:"baseURL",label:"Base URL",kind:"text",placeholder:"https://…"}]}` decoded via `JSONDecoder` (traced to `AIPluginDescriptorTests.decodesFromJSON`) | `identifier == "com.example.provider"`; `models == ["fast","smart"]`; `resolvedDefaultModel == "smart"`; `fields.count == 2`; `fields[0].isSecret == true`; `fields[1].kind == .text`; `fields[1].placeholder == "https://…"` |
| ai-plugin-descriptor-002 | resolved-default-model | `AIPluginDescriptor(identifier: "a", displayName: "A", version: "1", models: ["one", "two"])` (traced to `AIPluginDescriptorTests.defaultModelFallback`) | `resolvedDefaultModel == "one"` |
| ai-plugin-descriptor-003 | resolved-default-model | `AIPluginDescriptor(identifier: "b", displayName: "B", version: "1")` (no `models`, no `defaultModel`; same test) | `resolvedDefaultModel == ""` |
| ai-plugin-descriptor-004 | resolved-templates-explicit, provider-template-identity, fields-for-template | JSON `{schemaVersion:3, ..., templates:[{id:"a",displayName:"A",defaultValues:{baseURL:"https://a/v1"},models:["m1","m2"],defaultModel:"m1",secretRequired:true}]}` (traced to `AIPluginDescriptorTemplateTests.decodesTemplates`) | `descriptor.templates?.count == 1`; `resolvedTemplates.first!.id == "a"`; `defaultValues["baseURL"] == "https://a/v1"`; `template.resolvedDefaultModel == "m1"`; `fields(for: template).map(\.key) == ["apiKey"]` |
| ai-plugin-descriptor-005 | resolved-templates-implicit-synthesis, fields-for-template | `AIPluginDescriptor(identifier: "com.example.legacy", displayName: "Legacy", version: "1.0", models: ["only"], defaultModel: "only", fields: [.init(key: "apiKey", label: "API Key", kind: .secret)])` with `templates` omitted (traced to `AIPluginDescriptorTemplateTests.implicitTemplate`) | `templates == nil`; `resolvedTemplates.count == 1`; `resolvedTemplates[0].displayName == "Legacy"`; `resolvedTemplates[0].resolvedDefaultModel == "only"`; `fields(for: resolvedTemplates[0]).map(\.key) == ["apiKey"]` |
| ai-plugin-descriptor-006 | fields-for-template | A `ProviderTemplate` with its own `fields: [.init(key: "apiKey", label: "Session Token", kind: .secret)]`, on a descriptor whose own `fields` has `apiKey` labeled `"API Key"` (traced to `AIPluginDescriptorTemplateTests.templateFieldOverride`) | `fields(for: template).first?.label == "Session Token"` |
| ai-plugin-descriptor-007 | field-identity, field-is-secret | `Field(key: "k", label: "L", kind: .text)` with `placeholder` omitted | `isSecret == false`; `placeholder == nil` |
| ai-plugin-descriptor-008 | provider-template-resolved-config-type | `ProviderTemplate(id: "t", displayName: "T", secretRequired: false)` with `configType` omitted | `resolvedConfigType == "Local"` |
| ai-plugin-descriptor-009 | provider-template-resolved-provider, provider-template-resolved-llm | `ProviderTemplate(id: "t", displayName: "X")` with `provider` and `llm` both omitted | `resolvedProvider == "X"`; `resolvedLLM == ""` |
| ai-plugin-descriptor-010 | model-detail-lookup | A `ProviderTemplate` with `modelDetails: [ModelDetail(id: "a")]`; call `modelDetail(for: "b")` | Returns `nil` |
| ai-plugin-descriptor-011 | json-decoding-required-keys | The JSON from vector 001 with the `"models"` key removed entirely | `JSONDecoder().decode(AIPluginDescriptor.self, from:)` throws `DecodingError.keyNotFound` |

## Edge Cases

- **Empty `models`/`fields` arrays present in JSON**: `models: []` and `fields: []` MUST decode successfully; `resolvedDefaultModel` MUST then fall back to `""` when `defaultModel` is also absent (vector 003).
- **Missing `models` or `fields` key** (as opposed to present-but-empty): decoding MUST throw `DecodingError.keyNotFound`, since both are non-Optional stored properties with no Codable-level default (json-decoding-required-keys, vector 011).
- **Empty `identifier`, `displayName`, or `version` strings**: decoding and construction MUST NOT reject an empty string; this type performs no non-empty validation on any of the three.
- **`defaultModel` absent, explicit `null`, or naming a model not present in `models`**: `defaultModel` MUST decode to `nil` when absent or `null`; `resolvedDefaultModel` performs no membership check against `models`, so a `defaultModel` naming a model absent from `models` MUST still be returned unchanged.
- **`templates` absent, explicit `null`, or an empty array**: all three MUST route to the same implicit-template branch of `resolvedTemplates`, since the guard is `if let templates, !templates.isEmpty` — only a non-nil, non-empty array bypasses synthesis.
- **`schemaVersion` at or beyond its documented boundary** (`0`, negative, `currentSchemaVersion`, or above): this type imposes no minimum or maximum; every `Int` value decodes successfully. Range acceptance (`2...currentSchemaVersion`) is validated by `AIPluginManager.discoverPlugins()`, not by this type (see Design Decisions).
- **Malformed `kind` string** (e.g. `"masked"` instead of `"secret"`/`"text"`): decoding a `Field` MUST throw `DecodingError.dataCorrupted`, since `Field.Kind` is a `String`-backed `RawRepresentable` enum whose synthesized `init(from:)` has no unknown-case fallback.
- **Identifier, field-key, and template-id uniqueness**: NEEDS REVIEW: Not implemented in source. Neither `AIPluginDescriptor.identifier`, nor `Field.key` values within one descriptor's `fields` array, nor `ProviderTemplate.id` values within one descriptor's `templates` array are checked for uniqueness by this type on decode or construction. Downstream, `AIPluginManager.template(pluginIdentifier:templateId:)` resolves a `templateId` via `first(where:)`, silently returning only the first match with no signal that a collision occurred. What is missing: whether duplicate keys/ids should be rejected at decode time, or are intentionally permissive with first-match-wins left entirely to callers. Evidence that would settle it: a decision from whoever owns `AIPluginKit` on where, if anywhere, that validation belongs.
- **Concurrent access**: Because every stored property across all four types is `let` and every type is `Sendable`, a single constructed value MAY be read concurrently from multiple tasks or actors (e.g. simultaneously by a SwiftUI view and an AppKit controller) with no synchronization; no operation defined in this file mutates shared state.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) of its own to fail; locating and reading `descriptor.json` from a bundle is `AIPluginManager.readDescriptor(from:)`'s responsibility, not this type's.
- **Offline or disconnected state**: Not applicable — this file performs no network access of its own; the descriptor is decoded from a local resource shipped inside the `.aiplugin` bundle, per the type's own doc comment ("A plugin ships this as a plain JSON resource inside its `.aiplugin` bundle").
- **Cancellation and timeouts**: Not applicable — this file exposes no asynchronous or long-running operation; every member is a synchronous stored or computed property, or a pure synchronous function.

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

## Deep Linking

Not applicable: `AIPluginDescriptor.swift` defines no URL routing, navigation, or scheme handling — it is a decoded data shape consumed by settings UI (e.g. `LLMProvidersView.swift`, `LLMPickerView.swift`), unrelated to app navigation.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (inline Swift literal, no lookup key) | "API Key" | `ProviderTemplate.resolvedConfigType`'s fallback when `configType` is `nil` and `secretRequired == true`; shown in the provider picker's Config Type column. |
| — (inline Swift literal, no lookup key) | "Local" | `ProviderTemplate.resolvedConfigType`'s fallback when `configType` is `nil` and `secretRequired == false`. |

Both strings are hardcoded English literals with no localization mechanism (no `NSLocalizedString`/`String(localized:)`/string-catalog lookup) anywhere in this file. Every other user-facing string on a descriptor (`displayName`, `label`, `placeholder`, `providerDescription`, `llmDescription`, etc.) is plugin-authored data passed through unchanged, not a string this file itself defines.

## Accessibility Options

Not applicable: this is a data-only value type with no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `AIPluginDescriptor.swift` declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: `AIPluginDescriptor.swift` contains no analytics or event-emission call; any instrumentation around plugin discovery or loading (the `logger.info`/`logger.warning` calls) lives in `AIPluginManager`, not this file.

## Privacy

- **Data collected**: This type carries the metadata a plugin declares about its own settings, including which of those settings the plugin considers a credential. Per this file's own doc comments on `Field.Kind`, `.secret` marks a "masked entry, persisted to the Keychain (API keys, tokens)"; `.text` marks a "plain text entry, persisted to user defaults (base URLs, etc.)." The type itself collects nothing beyond decoding whatever `descriptor.json` and the host's own field values provide.
- **Storage**: `AIPluginDescriptor.swift` performs no storage of its own. The `.secret`/`.text` distinction is a contract honored by `PluginConfigStore.swift` and `AIProviderConfigStore.swift`, both of which route `field.isSecret` into `UserSetting(..., isSecure:)` to store secret values in the Keychain and non-secret values elsewhere (e.g. user defaults).
- **Transmission**: Not applicable at this layer — `AIPluginDescriptor.swift` contains no networking code; per this file's own doc comment, "the plugin's compiled `AIPlugin` contributes only request-building and response-decoding," so any transmission of a resolved secret happens in a different file.
- **Retention**: Not applicable at this layer — this type has no retention policy of its own; how long a Keychain- or user-defaults-stored value survives is governed entirely by whatever store implements the contract this type only labels.

## Logging

Not applicable: `AIPluginDescriptor.swift` contains no `os_log`, `Logger`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not the source, but a real consumer — `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMProvidersView.swift` imports `SwiftUI` and `AIPluginKit` directly. `AIPluginDescriptor.swift` itself has no SwiftUI dependency; a SwiftUI view binds to instances returned by `AIPluginManager.descriptors`/`resolvedTemplates` as plain `Equatable` values inside `@State`/view-model properties — no `ObservableObject` wrapper is needed since every type here is immutable and `Sendable`.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIPluginDescriptor.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). The AppKit consumer `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMPickerView.swift` reads `resolvedTemplates`/`fields(for:)` directly to populate its `NSPopUpButton`/list UI with no bridging layer, since the model is Foundation-only (`Codable`, `Sendable`, `Equatable`) and equally usable from AppKit or SwiftUI.
- **Compose**: a Kotlin port would model `AiPluginDescriptor`, `Field`, `ModelDetail`, and `ProviderTemplate` as `@Serializable` (`kotlinx.serialization`) immutable `data class`es with `val` properties; `Field.Kind` as a `kotlinx.serialization`-backed enum with `secret`/`text` values. Because `kotlinx.serialization.json.Json` by default also requires a non-nullable, non-`@EncodeDefault` property's key to be present (mirroring json-decoding-required-keys), the same required/optional-key split from Behavioral Requirements carries over directly. Compose UI would read `resolvedTemplates()` into a `remember { mutableStateOf(...) }` or a `StateFlow` on a view model, not mutate the data class itself.
- **React/Web**: a TypeScript port models the same shape as plain `interface`s (`interface AIPluginDescriptor { schemaVersion: number; identifier: string; ... }`), decoded from JSON with a runtime validator (e.g. `zod`) rather than a bare `JSON.parse` cast, since `JSON.parse` alone would silently accept a `models`-less object where Swift's synthesized `Decodable` throws — the validator schema must mark `models`/`fields`/`schemaVersion`/etc. as required to reproduce that behavior. `resolvedDefaultModel`, `resolvedTemplates`, `fields(for:)`, and `modelDetail(for:)` become plain exported functions operating on the interface, since TypeScript has no struct-method equivalent tied to the data shape itself.
- **WinUI 3**: a .NET port would model the four types as `record`s deserialized with `System.Text.Json` — e.g. `public sealed record AiPluginDescriptor(int SchemaVersion, string Identifier, string DisplayName, string Version, IReadOnlyList<string> Models, string? DefaultModel, IReadOnlyList<AiPluginField> Fields, IReadOnlyList<AiPluginProviderTemplate>? Templates);` — with `Field.Kind` as an `enum Kind { Secret, Text }` decorated with a `JsonStringEnumConverter`/`JsonConverter` so the wire values stay the lowercase `"secret"`/`"text"` strings Swift's `RawRepresentable<String>` enum produces. Because `System.Text.Json`'s default behavior treats a missing property as its type's default (`null`/`0`/empty) rather than throwing — unlike Swift's synthesized `Decodable` — the port MUST mark `SchemaVersion`, `Identifier`, `DisplayName`, `Version`, `Models`, and `Fields` as C# 11 `required` record properties (or apply `[JsonRequired]`) to reproduce the json-decoding-required-keys behavioral requirement; otherwise a `descriptor.json` missing `"models"` would silently decode to an empty list instead of failing fast, as it does on Apple. `ResolvedDefaultModel`, `ResolvedTemplates`, `Fields(template)`, and `ModelDetail(for:)` become computed properties/methods on the record (records support member methods, so no separate service class is needed). Expose the resolved templates to XAML via an `ObservableCollection<AiPluginProviderTemplate>` on the hosting view model feeding a `ComboBox`/`ListView` `ItemsSource`, since the record itself needs no `INotifyPropertyChanged` — it mirrors the Swift `let`-only immutability from sendable-and-immutability.

## Design Decisions

**Decision**: `AIPluginDescriptor.currentSchemaVersion`'s doc comment states "Bundles whose `schemaVersion` differs are skipped at discovery," but `AIPluginManager.discoverPlugins()` actually accepts the range `2...currentSchemaVersion`, not only an exact match against `currentSchemaVersion`.
**Rationale**: accepting a range lets the host stay compatible with an older still-supported schema version (v2) while treating pre-descriptor v1 plugins (which ship no `descriptor.json` at all, so there is nothing to decode) as absent rather than as a decode failure. The doc comment's "differs" wording is imprecise relative to the actual range check, but the two files agree on the outcome that matters: v1 plugins and any `schemaVersion` outside `2...3` are both skipped.
**Approved**: pending

**Decision**: `AIPluginDescriptor`, `Field`, `ProviderTemplate`, and `ModelDetail` rely entirely on the compiler-synthesized `Codable` conformance rather than a custom `init(from:)`.
**Rationale**: this keeps the file free of hand-written decoding logic, but it means the Swift-side default parameter values on `models`, `fields`, `secretRequired`, `defaultValues`, etc. — convenient for programmatic construction and for `AIPluginManager.registerForTesting` — do not apply during JSON decoding; every non-Optional property's key MUST be present in `descriptor.json` or decoding throws (json-decoding-required-keys). A plugin author who assumed the Swift default meant `"fields": []` could be omitted from their JSON would see their plugin silently skipped by `AIPluginManager.readDescriptor(from:)`'s `try?`.
**Approved**: pending

**Decision**: `resolvedTemplates` synthesizes one implicit `ProviderTemplate` (id `"default"`) from the descriptor's own fields whenever `templates` is `nil` or empty, rather than requiring every plugin to declare at least one explicit template.
**Rationale**: per the type's own doc comment, this keeps pre-v3 ("v2") plugins — which predate the `templates` field — working as a single provider without requiring every existing `descriptor.json` to be rewritten. `resolvedProvider`/`resolvedLLM`/`resolvedConfigType`'s own fallbacks (to `displayName`, `""`, and `"API Key"`/`"Local"` respectively) exist for the same reason, so an implicit template still renders sensibly in the provider picker's Provider/LLM/Config Type columns.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |

`separation-of-concerns` passes because `AIPluginDescriptor.swift` performs no file I/O, network access, or persistence of its own — bundle discovery lives in `AIPluginManager`, and credential/setting storage lives in `PluginConfigStore`/`AIProviderConfigStore`; this file is only the decoded shape and its pure resolution helpers. `no-hardcoded-strings` fails: `resolvedConfigType` returns the literal, non-localized English strings `"API Key"` and `"Local"`, which the provider picker's Config Type column displays directly (see Localization). `data-integrity` is `partial`: `identifier`, `Field.key`, and `ProviderTemplate.id` carry no uniqueness or non-empty validation in this type (see the open question in Edge Cases). `secure-storage` is `partial`: `Field.Kind.secret` correctly signals which values downstream consumers MUST route to the Keychain (confirmed in `PluginConfigStore.swift`/`AIProviderConfigStore.swift`), but this type performs no storage or enforcement of its own — a consumer that ignored `isSecret` would not be caught by anything in this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
