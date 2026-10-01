---
id: 39de0dff-2b26-4d3d-97a3-ebdbdb38846a
title: Plugin Descriptor
domain: agentictoolkit://cookbook/ai/plugins/plugin-descriptor
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The host-side model of a plugin''s descriptor.json: identity, models, settings
  fields, and provider templates the host reads at discovery time.'
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- provider-config
depends-on: []
related:
- agentictoolkit://cookbook/ai/chat/chat-context
references: []
approved-by: ''
approved-date: ''
---

# Plugin Descriptor

## Overview

A plugin descriptor is the host-side model of a plugin's `descriptor.json`:
its identity, the models it offers, and the settings fields the host should
render and persist. A plugin ships this as a plain JSON resource inside its
plugin bundle. The host reads it at plugin *discovery* time — before, and
without ever, loading the plugin's compiled code — so a host UI can list and
configure a provider from data alone. All presentation and configuration
metadata lives here as data; the plugin's own compiled contract contributes
only request-building and response-decoding. The descriptor defines four
value types: the descriptor itself, a field (one configurable value),
per-model detail (optional per-model metadata), and a provider template (a
named provider preset). None of the four performs I/O; the descriptor's only
"operations" are pure resolution helpers (resolving a default model,
resolving templates, resolving fields for a template, looking up per-model
detail) over already-decoded data.

## Behavioral Requirements

- **schema-version-field**: A plugin descriptor MUST include a
  `schemaVersion` integer field identifying the descriptor schema the
  plugin bundle was authored against; this concept imposes no minimum or
  maximum on the value, and any integer decodes successfully.
- **current-schema-version-constant**: The descriptor concept MUST expose a
  shared constant, `currentSchemaVersion = 3`, naming the newest schema
  version the host understands; this constant is not itself an enforcement
  mechanism (see Design Decisions).
- **identity-fields-required**: A plugin descriptor MUST require
  `identifier`, `displayName`, and `version` string fields, each with no
  default value; this concept performs no format or non-empty validation on
  any of the three.
- **models-list**: A plugin descriptor MUST expose a `models` list of
  strings, the model identifiers a host renders as a popup, defaulting to
  an empty list when constructed directly.
- **default-model-optional**: A plugin descriptor MUST allow `defaultModel`
  to be absent, defaulting to absent when constructed directly.
- **resolved-default-model**: Resolving a descriptor's default model MUST
  return `defaultModel` when it is present, else the first entry of
  `models`, else the empty string.
- **fields-list**: A plugin descriptor MUST expose a `fields` list, the
  settings the host renders as a form and persists per plugin, defaulting
  to an empty list when constructed directly.
- **templates-optional**: A plugin descriptor MUST allow `templates` to be
  absent (a v2 descriptor with no explicit templates) or a present list,
  defaulting to absent when constructed directly.
- **resolved-templates-explicit**: Resolving a descriptor's templates MUST
  return `templates` unchanged when it is present and contains at least one
  element.
- **resolved-templates-implicit-synthesis**: When `templates` is absent or
  an empty list, resolving a descriptor's templates MUST return exactly one
  synthesized provider template with `id: "default"`, `displayName` equal
  to the descriptor's `displayName`, empty `defaultValues`,
  `models`/`defaultModel` copied from the descriptor, `secretRequired:
  true`, and `fields` equal to the descriptor's own `fields`.
- **fields-for-template**: Resolving the fields for a template MUST return
  the given provider template's own `fields` when present, else the
  descriptor's `fields`.
- **field-identity**: A field MUST require `key`, `label`, and `kind`
  values, and MUST allow `placeholder` to default to absent.
- **field-kind-values**: A field's `kind` MUST be exactly one of `secret`
  or `text`, whose wire identifier equals its own case name.
- **field-kind-storage-contract**: A field whose `kind` is `secret` MUST be
  understood by config-persistence consumers as a masked entry requiring
  secure (e.g. keychain) storage (API keys, tokens), and a field whose
  `kind` is `text` MUST be understood as a plain entry requiring
  non-secure storage (e.g. user defaults, base URLs); the descriptor
  concept itself performs no storage — the contract is honored by sibling
  config-store components.
- **field-is-secret**: A field's `isSecret` value MUST be true if and only
  if its `kind` is `secret`.
- **model-detail-identity**: Per-model detail MUST require an `id`, and
  MUST allow `description`, `tools`, and `goodFor` to each independently
  default to absent.
- **model-detail-lookup**: Looking up a template's per-model detail MUST
  return the first element of `modelDetails` whose `id` equals the given
  model id, or no result when `modelDetails` is absent or contains no
  matching `id`.
- **provider-template-identity**: A provider template MUST require `id`
  and `displayName`, and MUST default `defaultValues` to an empty map,
  `models` to an empty list, `defaultModel` to absent, `secretRequired` to
  true, and `fields`, `provider`, `llm`, `configType`,
  `providerDescription`, `llmDescription`, and `modelDetails` each to
  absent.
- **provider-template-resolved-default-model**: Resolving a template's
  default model MUST return `defaultModel` when present, else the first
  entry of `models`, else the empty string — the identical rule as
  resolving a descriptor's default model.
- **provider-template-resolved-provider**: Resolving a template's provider
  name MUST return `provider` when present, else `displayName`.
- **provider-template-resolved-llm**: Resolving a template's model-brand
  label MUST return `llm` when present, else the empty string.
- **provider-template-resolved-config-type**: Resolving a template's
  config type MUST return `configType` when it is present; when
  `configType` is absent, it MUST return the literal string `"API Key"` if
  `secretRequired` is `true`, and the literal string `"Local"` otherwise.
- **json-decoding-required-keys**: Because the descriptor concept declares
  no custom decoding logic, decoding from JSON MUST require every
  non-optional field's JSON key to be present at decode time — for the
  descriptor: `schemaVersion`, `identifier`, `displayName`, `version`,
  `models`, `fields`; for a field: `key`, `label`, `kind`; for a provider
  template: `id`, `displayName`, `defaultValues`, `models`,
  `secretRequired`; for per-model detail: `id`. Decoding MUST fail with a
  key-not-found error if any of these is absent, even though the
  corresponding direct-construction initializer has a default value for
  programmatic construction.
- **json-decoding-optional-keys**: Every optional field (`defaultModel`,
  `templates` on the descriptor; `placeholder` on a field; `defaultModel`,
  `fields`, `provider`, `llm`, `configType`, `providerDescription`,
  `llmDescription`, `modelDetails` on a provider template; `description`,
  `tools`, `goodFor` on per-model detail) MUST decode successfully to
  absent when its JSON key is absent or explicitly `null`.
- **codable-conformance**: A descriptor, a field, per-model detail, and a
  provider template MUST each be serializable to and deserializable from
  JSON directly, so a plugin's `descriptor.json` resource decodes without a
  custom parsing step.
- **equatable-conformance**: A descriptor, a field, per-model detail, and a
  provider template MUST each support equality comparison.
- **sendable-and-immutability**: A descriptor, a field, per-model detail,
  and a provider template MUST each be immutable value types with no
  mutable state after construction, so an instance is fully immutable and
  may cross a concurrency-domain boundary with no synchronization.
- **decoding-error-propagation**: The descriptor concept MUST NOT catch,
  transform, or swallow a decode failure; decoding MUST propagate whatever
  error the underlying JSON decoder produces to the caller, since the
  descriptor declares no custom decoding logic, no validation logic, and no
  error type of its own.

## Appearance

Not applicable — this is a host-side data model decoded from a plugin's `descriptor.json`, not a visual component.

## States

Not applicable — this is a host-side data model decoded from a plugin's `descriptor.json`, not a visual component. Any runtime lifecycle (plugin discovered, loaded, or failed to load) belongs to the host's plugin manager, not to this concept.

## Accessibility

Not applicable — this is a host-side data model decoded from a plugin's `descriptor.json`, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-descriptor-001 | identity-fields-required, field-identity, resolved-default-model | Decode the JSON `{schemaVersion:2, identifier:"com.example.provider", displayName:"Example", version:"1.2.3", models:["fast","smart"], defaultModel:"smart", fields:[{key:"apiKey",label:"API Key",kind:"secret"},{key:"baseURL",label:"Base URL",kind:"text",placeholder:"https://…"}]}` | `identifier == "com.example.provider"`; `models == ["fast","smart"]`; resolved default model `== "smart"`; `fields.count == 2`; first field's `isSecret == true`; second field's `kind == text`; second field's `placeholder == "https://…"` |
| ai-plugin-descriptor-002 | resolved-default-model | Construct a descriptor directly with `identifier: "a"`, `displayName: "A"`, `version: "1"`, `models: ["one", "two"]` | Resolved default model `== "one"` |
| ai-plugin-descriptor-003 | resolved-default-model | Construct a descriptor directly with `identifier: "b"`, `displayName: "B"`, `version: "1"` (no `models`, no `defaultModel`) | Resolved default model `== ""` |
| ai-plugin-descriptor-004 | resolved-templates-explicit, provider-template-identity, fields-for-template | Decode the JSON `{schemaVersion:3, ..., templates:[{id:"a",displayName:"A",defaultValues:{baseURL:"https://a/v1"},models:["m1","m2"],defaultModel:"m1",secretRequired:true}]}` | The descriptor's `templates` count is `1`; the first resolved template's `id == "a"`; its `defaultValues["baseURL"] == "https://a/v1"`; its resolved default model `== "m1"`; resolving fields for that template yields keys `["apiKey"]` |
| ai-plugin-descriptor-005 | resolved-templates-implicit-synthesis, fields-for-template | Construct a descriptor directly with `identifier: "com.example.legacy"`, `displayName: "Legacy"`, `version: "1.0"`, `models: ["only"]`, `defaultModel: "only"`, one field with `key: "apiKey"`, `label: "API Key"`, `kind: secret`, and `templates` omitted | `templates` is absent; resolving templates yields exactly one; its `displayName == "Legacy"`; its resolved default model `== "only"`; resolving fields for it yields keys `["apiKey"]` |
| ai-plugin-descriptor-006 | fields-for-template | A provider template with its own field `key: "apiKey"`, `label: "Session Token"`, `kind: secret`, on a descriptor whose own `fields` has `apiKey` labeled `"API Key"` | Resolving fields for that template returns a first field with `label == "Session Token"` |
| ai-plugin-descriptor-007 | field-identity, field-is-secret | A field with `key: "k"`, `label: "L"`, `kind: text`, `placeholder` omitted | `isSecret == false`; `placeholder` is absent |
| ai-plugin-descriptor-008 | provider-template-resolved-config-type | A provider template with `id: "t"`, `displayName: "T"`, `secretRequired: false`, `configType` omitted | Resolved config type `== "Local"` |
| ai-plugin-descriptor-009 | provider-template-resolved-provider, provider-template-resolved-llm | A provider template with `id: "t"`, `displayName: "X"`, `provider` and `llm` both omitted | Resolved provider `== "X"`; resolved LLM label `== ""` |
| ai-plugin-descriptor-010 | model-detail-lookup | A provider template with per-model detail `[{id: "a"}]`; look up detail for `"b"` | Returns no result |
| ai-plugin-descriptor-011 | json-decoding-required-keys | The JSON from vector 001 with the `"models"` key removed entirely | Decoding fails with a key-not-found error |

## Edge Cases

- **Empty `models`/`fields` arrays present in JSON**: `models: []` and `fields: []` MUST decode successfully; resolving the default model MUST then fall back to `""` when `defaultModel` is also absent (vector 003).
- **Missing `models` or `fields` key** (as opposed to present-but-empty): decoding MUST fail with a key-not-found error, since both are non-optional fields with no wire-level default (json-decoding-required-keys, vector 011).
- **Empty `identifier`, `displayName`, or `version` strings**: decoding and construction MUST NOT reject an empty string; this concept performs no non-empty validation on any of the three.
- **`defaultModel` absent, explicit `null`, or naming a model not present in `models`**: `defaultModel` MUST decode to absent when absent or `null`; resolving the default model performs no membership check against `models`, so a `defaultModel` naming a model absent from `models` MUST still be returned unchanged.
- **`templates` absent, explicit `null`, or an empty array**: all three MUST route to the same implicit-template branch of resolving templates, since only a present, non-empty list bypasses synthesis.
- **`schemaVersion` at or beyond its documented boundary** (`0`, negative, `currentSchemaVersion`, or above): this concept imposes no minimum or maximum; every integer value decodes successfully. Range acceptance (`2...currentSchemaVersion`) is validated by the host's plugin-discovery process, not by this concept (see Design Decisions).
- **Malformed `kind` string** (e.g. `"masked"` instead of `"secret"`/`"text"`): decoding a field MUST fail with a data-corrupted error, since a field's `kind` recognizes only the fixed `secret`/`text` values and has no unknown-value fallback.
- **Identifier, field-key, and template-id uniqueness**: Neither the descriptor's `identifier`, nor `Field.key` values within one descriptor's `fields` list, nor a provider template's `id` values within one descriptor's `templates` list are checked for uniqueness by this concept on decode or construction; duplicates decode and construct successfully. Downstream, the host's template lookup resolves a template id by taking the first resolved template with a matching `id`, so a duplicate `id` silently returns only the first match, with no error or signal that a collision occurred.
- **Concurrent access**: Because every one of the four value types is immutable, a single constructed value MAY be read concurrently from multiple threads or tasks (e.g. simultaneously by two different UI layers) with no synchronization; no operation defined by this concept mutates shared state.
- **Error states from a dependency**: Not applicable — this concept has no dependency (no network, database, or file-system call) of its own to fail; locating and reading `descriptor.json` from a bundle is the host's responsibility, not this concept's.
- **Offline or disconnected state**: Not applicable — this concept performs no network access of its own; the descriptor is decoded from a local resource shipped inside the plugin bundle.
- **Cancellation and timeouts**: Not applicable — this concept exposes no asynchronous or long-running operation; every member is a synchronous stored or computed value, or a pure synchronous function.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `schemaVersion` | integer | `currentSchemaVersion` (`3`) | The descriptor's descriptor-schema version; unvalidated by this concept (see Edge Cases). |
| `identifier` | string | none (required) | The descriptor's unique plugin id. |
| `displayName` | string | none (required) | The descriptor's human-readable name; also the implicit template's `displayName`. |
| `version` | string | none (required) | The descriptor's plugin version string, unvalidated. |
| `models` | list of strings | `[]` | The descriptor's model identifiers, rendered as a popup. |
| `defaultModel` | string, optional | absent | The descriptor's preselected model; falls back to the first entry of `models` when resolved. |
| `fields` | list of fields | `[]` | The descriptor's settings fields the host renders and persists. |
| `templates` | list of provider templates, optional | absent | The descriptor's explicit provider presets; absent/empty synthesizes one implicit template. |
| `key` | string | none (required) | A field's config-bag lookup key and persisted-setting suffix. |
| `label` | string | none (required) | A field's host-rendered label. |
| `kind` | field kind (`secret` or `text`) | none (required) | A field's storage classification. |
| `placeholder` | string, optional | absent | A field's optional placeholder text. |
| `id` | string | none (required) | Per-model detail's model-id key. |
| `description` | string, optional | absent | Per-model detail's one-line model description. |
| `tools` | boolean, optional | absent | Per-model detail's tool/function-calling support flag. |
| `goodFor` | string, optional | absent | Per-model detail's "well-suited for" blurb. |
| `id` | string | none (required) | A provider template's preset id. |
| `displayName` | string | none (required) | A provider template's preset display name. |
| `defaultValues` | map of string to string | `{}` | A provider template's seeded config values injected before request-building. |
| `models` | list of strings | `[]` | A provider template's model list. |
| `defaultModel` | string, optional | absent | A provider template's preselected model. |
| `secretRequired` | boolean | `true` | A provider template's flag for whether a secret field must be filled. |
| `fields` | list of fields, optional | absent | A provider template's field overrides; absent inherits the descriptor's `fields`. |
| `provider` | string, optional | absent | A provider template's vendor name; falls back to `displayName` when resolved. |
| `llm` | string, optional | absent | A provider template's model-brand label; falls back to the empty string when resolved. |
| `configType` | string, optional | absent | A provider template's auth-method label; falls back to `"API Key"`/`"Local"` when resolved. |
| `providerDescription` | string, optional | absent | A provider template's vendor blurb for the details pane. |
| `llmDescription` | string, optional | absent | A provider template's model-family blurb for the details pane. |
| `modelDetails` | list of per-model detail, optional | absent | A provider template's per-model descriptive metadata. |

## Deep Linking

Not applicable: this concept defines no URL routing, navigation, or scheme handling — it is a decoded data shape consumed by settings UI, unrelated to app navigation.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (inline literal, no lookup key) | "API Key" | A provider template's resolved config type fallback when `configType` is absent and `secretRequired == true`; shown in the provider picker's Config Type column. |
| — (inline literal, no lookup key) | "Local" | A provider template's resolved config type fallback when `configType` is absent and `secretRequired == false`. |

Both strings are hardcoded English literals with no localization-lookup mechanism (a string catalog, a localized-string table) anywhere in this concept. Every other user-facing string on a descriptor (`displayName`, `label`, `placeholder`, `providerDescription`, `llmDescription`, etc.) is plugin-authored data passed through unchanged, not a string this concept itself defines.

## Accessibility Options

Not applicable: this is a data-only value type with no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this concept declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: this concept contains no analytics or event-emission call; any instrumentation around plugin discovery or loading lives in the host's plugin manager, not this concept.

## Privacy

- **Data collected**: This concept carries the metadata a plugin declares about its own settings, including which of those settings the plugin considers a credential. A field whose `kind` is `secret` marks a "masked entry, persisted to secure storage (API keys, tokens)"; a field whose `kind` is `text` marks a "plain text entry, persisted to non-secure storage (base URLs, etc.)." The concept itself collects nothing beyond decoding whatever `descriptor.json` and the host's own field values provide.
- **Storage**: This concept performs no storage of its own. The `secret`/`text` distinction is a contract honored by sibling config-store components, which route a field's `isSecret` value into secure or non-secure storage accordingly.
- **Transmission**: Not applicable at this layer — this concept contains no networking code; the plugin's own compiled contract contributes only request-building and response-decoding, so any transmission of a resolved secret happens elsewhere.
- **Retention**: Not applicable at this layer — this concept has no retention policy of its own; how long a securely- or non-securely-stored value survives is governed entirely by whatever store implements the contract this concept only labels.

## Logging

Not applicable: this concept contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not the source, but a real consumer — `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMProvidersView.swift` imports `SwiftUI` and `AIPluginKit` directly. `AIPluginDescriptor.swift` itself has no SwiftUI dependency; a SwiftUI view binds to instances returned by `AIPluginManager.descriptors`/`resolvedTemplates` as plain `Equatable` values inside `@State`/view-model properties — no `ObservableObject` wrapper is needed since every type here is immutable and `Sendable`.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIPluginDescriptor.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). The AppKit consumer `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMPickerView.swift` reads `resolvedTemplates`/`fields(for:)` directly to populate its `NSPopUpButton`/list UI with no bridging layer, since the model is Foundation-only (`Codable`, `Sendable`, `Equatable`) and equally usable from AppKit or SwiftUI.
- **Compose**: a Kotlin port would model `AiPluginDescriptor`, `Field`, `ModelDetail`, and `ProviderTemplate` as `@Serializable` (`kotlinx.serialization`) immutable `data class`es with `val` properties; `Field.Kind` as a `kotlinx.serialization`-backed enum with `secret`/`text` values. Because `kotlinx.serialization.json.Json` by default also requires a non-nullable, non-`@EncodeDefault` property's key to be present (mirroring json-decoding-required-keys), the same required/optional-key split from Behavioral Requirements carries over directly. Compose UI would read `resolvedTemplates()` into a `remember { mutableStateOf(...) }` or a `StateFlow` on a view model, not mutate the data class itself.
- **React/Web**: a TypeScript port models the same shape as plain `interface`s (`interface AIPluginDescriptor { schemaVersion: number; identifier: string; ... }`), decoded from JSON with a runtime validator (e.g. `zod`) rather than a bare `JSON.parse` cast, since `JSON.parse` alone would silently accept a `models`-less object where Swift's synthesized `Decodable` throws — the validator schema must mark `models`/`fields`/`schemaVersion`/etc. as required to reproduce that behavior. `resolvedDefaultModel`, `resolvedTemplates`, `fields(for:)`, and `modelDetail(for:)` become plain exported functions operating on the interface, since TypeScript has no struct-method equivalent tied to the data shape itself.
- **WinUI 3**: a .NET port would model the four types as `record`s deserialized with `System.Text.Json` — e.g. `public sealed record AiPluginDescriptor(int SchemaVersion, string Identifier, string DisplayName, string Version, IReadOnlyList<string> Models, string? DefaultModel, IReadOnlyList<AiPluginField> Fields, IReadOnlyList<AiPluginProviderTemplate>? Templates);` — with `Field.Kind` as an `enum Kind { Secret, Text }` decorated with a `JsonStringEnumConverter`/`JsonConverter` so the wire values stay the lowercase `"secret"`/`"text"` strings Swift's `RawRepresentable<String>` enum produces. Because `System.Text.Json`'s default behavior treats a missing property as its type's default (`null`/`0`/empty) rather than throwing — unlike Swift's synthesized `Decodable` — the port MUST mark `SchemaVersion`, `Identifier`, `DisplayName`, `Version`, `Models`, and `Fields` as C# 11 `required` record properties (or apply `[JsonRequired]`) to reproduce the json-decoding-required-keys behavioral requirement; otherwise a `descriptor.json` missing `"models"` would silently decode to an empty list instead of failing fast, as it does on Apple. `ResolvedDefaultModel`, `ResolvedTemplates`, `Fields(template)`, and `ModelDetail(for:)` become computed properties/methods on the record (records support member methods, so no separate service class is needed). Expose the resolved templates to XAML via an `ObservableCollection<AiPluginProviderTemplate>` on the hosting view model feeding a `ComboBox`/`ListView` `ItemsSource`, since the record itself needs no `INotifyPropertyChanged` — it mirrors the Swift `let`-only immutability from sendable-and-immutability.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIPluginDescriptor.swift` |

## Design Decisions

**Decision**: `AIPluginDescriptor.currentSchemaVersion`'s doc comment states "Bundles whose `schemaVersion` differs are skipped at discovery," but `AIPluginManager.discoverPlugins()` actually accepts the range `2...currentSchemaVersion`, not only an exact match against `currentSchemaVersion`.
**Rationale**: accepting a range lets the host stay compatible with an older still-supported schema version (v2) while treating pre-descriptor v1 plugins (which ship no `descriptor.json` at all, so there is nothing to decode) as absent rather than as a decode failure. The doc comment's "differs" wording is imprecise relative to the actual range check, but the two files agree on the outcome that matters: v1 plugins and any `schemaVersion` outside `2...3` are both skipped.
**Approved**: pending

**Decision**: In the Swift implementation, `AIPluginDescriptor`, `Field`, `ProviderTemplate`, and `ModelDetail` rely entirely on the compiler-synthesized `Codable` conformance rather than a custom `init(from:)`.
**Rationale**: this keeps the file free of hand-written decoding logic, but it means the Swift-side default parameter values on `models`, `fields`, `secretRequired`, `defaultValues`, etc. — convenient for programmatic construction and for `AIPluginManager.registerForTesting` — do not apply during JSON decoding; every non-Optional property's key MUST be present in `descriptor.json` or decoding throws (json-decoding-required-keys). A plugin author who assumed the Swift default meant `"fields": []` could be omitted from their JSON would see their plugin silently skipped by `AIPluginManager.readDescriptor(from:)`'s `try?`. A port on another platform that relies on its own serializer's default-generation MUST make the same "required key" choice explicit, per json-decoding-required-keys.
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

`separation-of-concerns` passes because `AIPluginDescriptor.swift` performs no file I/O, network access, or persistence of its own — bundle discovery lives in `AIPluginManager`, and credential/setting storage lives in `PluginConfigStore`/`AIProviderConfigStore`; this file is only the decoded shape and its pure resolution helpers. `no-hardcoded-strings` fails: `resolvedConfigType` returns the literal, non-localized English strings `"API Key"` and `"Local"`, which the provider picker's Config Type column displays directly (see Localization). `data-integrity` is `partial`: `identifier`, `Field.key`, and `ProviderTemplate.id` carry no uniqueness or non-empty validation in this type — duplicates decode and construct successfully, and `AIPluginManager.template(pluginIdentifier:templateId:)` silently resolves to the first match on a colliding `id` (see Edge Cases). `secure-storage` is `partial`: `Field.Kind.secret` correctly signals which values downstream consumers MUST route to the Keychain (confirmed in `PluginConfigStore.swift`/`AIProviderConfigStore.swift`), but this type performs no storage or enforcement of its own — a consumer that ignored `isSecret` would not be caught by anything in this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
