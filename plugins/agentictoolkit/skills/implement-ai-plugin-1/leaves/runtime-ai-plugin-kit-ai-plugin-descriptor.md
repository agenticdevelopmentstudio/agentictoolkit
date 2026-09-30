<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor#<slug>`):

- `schema-version-field` MUST
- `current-schema-version-constant` MUST
- `identity-fields-required` MUST
- `models-list` MUST
- `default-model-optional` MUST
- `resolved-default-model` MUST
- `fields-list` MUST
- `templates-optional` MUST
- `resolved-templates-explicit` MUST
- `resolved-templates-implicit-synthesis` MUST
- `fields-for-template` MUST
- `field-identity` MUST
- `field-kind-values` MUST
- `field-kind-storage-contract` MUST
- `field-is-secret` MUST
- `model-detail-identity` MUST
- `model-detail-lookup` MUST
- `provider-template-identity` MUST
- `provider-template-resolved-default-model` MUST
- `provider-template-resolved-provider` MUST
- `provider-template-resolved-llm` MUST
- `provider-template-resolved-config-type` MUST
- `json-decoding-required-keys` MUST
- `json-decoding-optional-keys` MUST
- `codable-conformance` MUST
- `equatable-conformance` MUST
- `sendable-and-immutability` MUST
- `decoding-error-propagation` MUST

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

