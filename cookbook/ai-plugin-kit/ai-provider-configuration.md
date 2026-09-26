---
id: a8054368-9885-4b83-90cf-5029728ab397
title: AI Provider Configuration
domain: agentictoolkit://cookbook/ai-plugin-kit/ai-provider-configuration
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A user's named instance of a provider template - id, name, pluginIdentifier,
  templateId - plus the uniqueName(_:avoiding:) display-name helper.
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
- agentictoolkit://cookbook/ai-plugin-kit/ai-provider-config-keys
- agentictoolkit://cookbook/ai-plugin-kit/ai-plugin-descriptor
references:
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/AIPlugins/AIProviderConfigurationTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/AIProviderConfigKeysTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/AIProviderConfigStore.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/LLMProvidersListViewModel.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# AI Provider Configuration

## Overview

`AIProviderConfiguration.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift`) defines `AIProviderConfiguration`, a small `Codable`, `Sendable`, `Identifiable`, `Equatable`, `Hashable` value type that is, per its own doc comment, "a user's named instance of a provider template: which plugin serves it, which template it was created from, and a display name." It carries exactly four stored properties — `id: UUID`, `name: String`, `pluginIdentifier: String`, `templateId: String` — and nothing else. Per-configuration field values, the selected model, and secrets live in separate stores keyed by `id.uuidString` (see the sibling `AIProviderConfigKeys` component); only identity lives on this type, "so the ordered list is a small plain-Codable array shared by the app and the daemon." The file also defines one static helper, `uniqueName(_:avoiding:)`, that appends a numeric suffix to a candidate display name until the result is not in a caller-supplied set of names already taken. The type performs no I/O, no validation beyond what the Swift compiler enforces, and has no side effect of its own.

## Behavioral Requirements

- **identifier-assignment**: The initializer MUST assign `id` from its `id: UUID = UUID()` parameter, generating a fresh random UUID when the caller omits the argument.
- **identifier-immutability**: `id` MUST NOT change after initialization; it is declared `public let id: UUID`.
- **identifiable-conformance**: The type MUST satisfy `Identifiable` by exposing its `id: UUID` stored property directly as the protocol's `id` requirement, with no separate computed property or indirection.
- **display-name-mutability**: `name` MUST be assignable after initialization; it is declared `public var name: String`, so a caller MAY rename a configuration in place without constructing a new value and without changing `id`, `pluginIdentifier`, or `templateId`.
- **plugin-and-template-identity-immutability**: `pluginIdentifier` and `templateId` MUST NOT change after initialization; both are declared `public let`.
- **no-content-validation**: The initializer MUST accept any `String` value, including an empty string, for `name`, `pluginIdentifier`, and `templateId`; the source performs no format, length, or non-empty check on any of the three.
- **codable-conformance**: The type MUST conform to `Codable` via the compiler-synthesized `init(from:)`/`encode(to:)` over its four stored properties, so a value, or an array of values, encodes to and decodes from JSON with no custom coder.
- **sendable-conformance**: The type MUST conform to `Sendable`; every stored property (`UUID`, `String`, `String`, `String`) is itself `Sendable`, and the type performs no synchronization of its own, so an instance MAY cross an actor or `Task` boundary with no additional guard.
- **equatable-conformance**: The type MUST conform to `Equatable` via the compiler-synthesized memberwise comparison over `id`, `name`, `pluginIdentifier`, and `templateId`; two instances MUST compare unequal whenever any one of the four differs, including two otherwise-identical configurations that differ only in `id`.
- **hashable-conformance**: The type MUST conform to `Hashable` via the compiler-synthesized hash over the same four stored properties, consistent with `equatable-conformance`, so instances MAY be used as `Set` elements or `Dictionary` keys.
- **value-semantics**: The type MUST exhibit full Swift value semantics as a `struct` with no reference-type stored property; assigning or passing an instance MUST copy it, and mutating one copy's `name` MUST NOT affect any other copy or any previously encoded representation.
- **no-persistence**: The type MUST NOT read from or write to `UserDefaults`, the Keychain, a file, or a network endpoint itself; the source declares no such call, and per its own doc comment, a configuration's field values, model, and secrets are persisted elsewhere, keyed by `id.uuidString`.
- **no-registry-validation**: Construction, decoding, and comparison MUST NOT verify that `pluginIdentifier` or `templateId` refers to a currently installed, resolvable plugin or template; the type consults no plugin registry (see Design Decisions).
- **unique-name-unchanged-when-free**: `uniqueName(_:avoiding:)` MUST return `base` unchanged when `taken` does not contain `base`.
- **unique-name-suffix-on-collision**: `uniqueName(_:avoiding:)` MUST return `"\(base) 2"` when `taken` contains `base` but not `"\(base) 2"`.
- **unique-name-suffix-increments**: When `taken` also contains `"\(base) 2"`, `uniqueName(_:avoiding:)` MUST try successive suffixes `3`, `4`, … in order, returning the first candidate `"\(base) \(suffix)"` that `taken` does not contain.
- **unique-name-static-purity**: `uniqueName(_:avoiding:)` MUST be a `static` function with no side effect; it MUST NOT read or write `self`, any stored property, or any external store, deriving its result solely from its two arguments, and returning the identical result for the identical arguments on every call.

## Appearance

Not applicable — this is a Sendable value type (a provider-configuration identity record), not a visual component.

## States

Not applicable — this is a Sendable value type (a provider-configuration identity record), not a visual component; it defines no runtime state machine of its own.

## Accessibility

Not applicable — this is a Sendable value type (a provider-configuration identity record), not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-configuration-001 | identifier-assignment | `AIProviderConfiguration(name: "X", pluginIdentifier: "p", templateId: "t")` (no `id` argument), constructed twice | Each call produces a non-nil `UUID` `id`; the two calls' `id` values differ — traced to `init(id: UUID = UUID(), ...)` and `AIProviderConfigurationTests.settingsPersist`'s identical call shape |
| ai-provider-configuration-002 | identifier-immutability | Attempt `cfg.id = UUID()` on an existing `var cfg: AIProviderConfiguration` | Fails to compile: `id` is declared `let` |
| ai-provider-configuration-003 | identifiable-conformance | Bind `cfg` to a context requiring `some Identifiable`, then read `cfg.id` | Compiles with no adapter, and the value equals the stored `id` property directly |
| ai-provider-configuration-004 | display-name-mutability | `var cfg = AIProviderConfiguration(name: "X", pluginIdentifier: "p", templateId: "t"); let before = (cfg.id, cfg.pluginIdentifier, cfg.templateId); cfg.name = "Y"` | `cfg.name == "Y"`; `(cfg.id, cfg.pluginIdentifier, cfg.templateId) == before` |
| ai-provider-configuration-005 | plugin-and-template-identity-immutability | Attempt `cfg.pluginIdentifier = "other"` or `cfg.templateId = "other"` | Fails to compile: both are declared `let` |
| ai-provider-configuration-006 | no-content-validation | `AIProviderConfiguration(name: "", pluginIdentifier: "", templateId: "")` | Construction succeeds with no error or throw; `.name == ""`, `.pluginIdentifier == ""`, `.templateId == ""` |
| ai-provider-configuration-007 | codable-conformance | `let original = AIProviderConfiguration(id: UUID(), name: "My Groq", pluginIdentifier: "com.x.openai-compatible", templateId: "groq"); let data = try JSONEncoder().encode([original]); let decoded = try JSONDecoder().decode([AIProviderConfiguration].self, from: data)` | `decoded == [original]` — `AIProviderConfigurationTests.codableRoundTrip` |
| ai-provider-configuration-008 | sendable-conformance | Capture an `AIProviderConfiguration` value in a `@Sendable` closure passed to `Task { ... }` under `SWIFT_STRICT_CONCURRENCY: complete` | Compiles with no Sendable-conformance diagnostic |
| ai-provider-configuration-009 | equatable-conformance | Two values built with identical `name`, `pluginIdentifier`, `templateId` but distinct `id` (two separate `AIProviderConfiguration(name: "X", pluginIdentifier: "p", templateId: "t")` calls, each with its own default `id`) | The two values compare `!=`, because the synthesized `Equatable` includes `id` |
| ai-provider-configuration-010 | hashable-conformance | Insert two values that are `==` (copied from one instance, so `id`, `name`, `pluginIdentifier`, `templateId` all match) into a `Set<AIProviderConfiguration>` | `set.count == 1` |
| ai-provider-configuration-011 | value-semantics | `var a = AIProviderConfiguration(name: "X", pluginIdentifier: "p", templateId: "t"); let b = a; a.name = "Y"` | `b.name == "X"` (unchanged); `a.name == "Y"` |
| ai-provider-configuration-012 | no-persistence | Grep `AIProviderConfiguration.swift` for `UserDefaults`, `Keychain`, `FileManager`, `URLSession`, or any settings/network API | No match — the file imports only `Foundation` and calls no persistence or networking API |
| ai-provider-configuration-013 | no-registry-validation | `AIProviderConfiguration(name: "X", pluginIdentifier: "com.does.not.exist", templateId: "no-such-template")`, with no matching `AIPluginDescriptor` installed anywhere | Construction succeeds with no error, warning, or lookup performed |
| ai-provider-configuration-014 | unique-name-unchanged-when-free | `AIProviderConfiguration.uniqueName("Groq", avoiding: [])` | `"Groq"` — `AIProviderConfigKeysTests.testUniqueNameAppendsSuffix` |
| ai-provider-configuration-015 | unique-name-suffix-on-collision | `AIProviderConfiguration.uniqueName("Groq", avoiding: ["Groq"])` | `"Groq 2"` — `AIProviderConfigKeysTests.testUniqueNameAppendsSuffix` |
| ai-provider-configuration-016 | unique-name-suffix-increments | `AIProviderConfiguration.uniqueName("Groq", avoiding: ["Groq", "Groq 2"])` | `"Groq 3"` — a direct consequence of the `while taken.contains("\(base) \(suffix)") { suffix += 1 }` loop; not spelled out by name in the given test file, but forced by its control flow |
| ai-provider-configuration-017 | unique-name-static-purity | Call `AIProviderConfiguration.uniqueName("Groq", avoiding: ["Groq"])` twice in immediate succession | Both calls return `"Groq 2"`; no state changes between calls, and no instance of `AIProviderConfiguration` is required to call it |
| ai-provider-configuration-018 | codable-conformance, equatable-conformance (external-store evidence) | `let cfg = AIProviderConfiguration(name: "X", pluginIdentifier: "p", templateId: "t"); UserSettings.aiProviderConfigurations.value = [cfg]; UserSettings.selectedAIProviderConfigurationId.value = cfg.id.uuidString` | `UserSettings.aiProviderConfigurations.value == [cfg]` and `UserSettings.selectedAIProviderConfigurationId.value == cfg.id.uuidString` — `AIProviderConfigurationTests.settingsPersist`; this round-trips through an external store, not through this file's own logic |

## Edge Cases

- **Empty `name`, `pluginIdentifier`, or `templateId`**: MUST be accepted without error (see `no-content-validation`); an empty `name` displays as a blank label to whatever UI renders it, but this type performs no rejection.
- **`taken` is empty**: `uniqueName(_:avoiding:)` MUST return `base` unchanged (see `unique-name-unchanged-when-free`) — an empty `Set<String>` is a valid, ordinary input, not a special case in the source.
- **`base` already ends in a numeric suffix**: `uniqueName("Groq 2", avoiding: ["Groq 2"])` MUST return `"Groq 2 2"`, because the source concatenates `"\(base) \(suffix)"` unconditionally with no check for whether `base` already looks like a suffixed name; this is a documented quirk of the naming scheme, not a bug the type guards against.
- **Extremely large `taken` sets**: the suffix loop in `uniqueName(_:avoiding:)` has no iteration cap; for any finite `Set<String>` — the only kind constructible by a caller — the loop MUST terminate at the first untaken `"\(base) \(suffix)"`. The source places no overflow guard on the `Int` suffix counter, but reaching `Int.max` iterations would require a caller to have first supplied that many already-taken names, which is not a realistic input for a list of a user's own configurations.
- **Concurrent access**: this type declares no shared mutable state — it is a `Sendable` `struct`, and each variable holding a copy is independent memory (see `value-semantics`); two threads or tasks each holding their own copy MUST NOT be able to race on this type's own storage. Concurrent mutation of a shared collection of configurations (e.g. an array in `UserSettings` read and written from two threads at once) is the concern of that collection's own synchronization, not of this type.
- **Error states from a dependency**: Not applicable — the type has no dependency (no network, database, or file-system call) that could fail; per `no-persistence`, it never touches a store.
- **Offline or disconnected state**: Not applicable — `AIProviderConfiguration.swift` performs no network access of its own.
- **Cancellation and timeouts**: Not applicable — every member is a synchronous, non-`async`, non-throwing computation; there is nothing to cancel and no operation that can time out.
- **Missing file or unreachable server**: Not applicable — this file opens no file and makes no server call.
- **Orphaned `pluginIdentifier`/`templateId`**: a configuration whose plugin has since been uninstalled, or whose template id no longer resolves in that plugin's descriptor, MUST still decode, compare, and hash normally; this type performs no liveness check against the current plugin registry (see `no-registry-validation` and Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | `UUID` | `UUID()` (freshly generated) | Stable identity for a configuration instance, passed to `init(id:name:pluginIdentifier:templateId:)`. |
| `name` | `String` | none (required) | Caller-supplied display name; mutable after construction; no validation. |
| `pluginIdentifier` | `String` | none (required) | Identifies which plugin (an `AIPluginDescriptor.identifier`) serves this configuration; not checked against any registry by this type. |
| `templateId` | `String` | none (required) | Identifies which provider template (a `ProviderTemplate.id`) this configuration was created from; not checked against any registry by this type. |
| `base` (`uniqueName(_:avoiding:)`) | `String` | none (required) | Candidate display name the caller wants made unique. |
| `taken` (`uniqueName(_:avoiding:)`) | `Set<String>` | none (required) | Names already in use that the returned name MUST avoid. |

## Deep Linking

Not applicable: the source defines no URL, route, or navigable destination — it is an identity data record with no navigation surface of its own.

## Localization

Not applicable: the source contains no user-facing string literal; `name` is caller-supplied data rather than a hardcoded UI string, and `uniqueName`'s `" \(suffix)"` numeric suffix is formatting, not natural-language text.

## Accessibility Options

Not applicable: `AIProviderConfiguration.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

Not applicable: `AIProviderConfiguration.swift` never stores, reads, or transmits a token or credential value itself — per its own doc comment, a configuration's secrets are persisted separately, keyed by `id.uuidString` (see the `ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys` recipe for how those keys and their credential-bearing values are handled).

## Logging

Not applicable: the source contains no `Logger`, `os_log`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: this is the source's primary consumer pattern. `LLMProvidersListViewModel` (`macOS/Features/AIPlugins/Settings/LLMProvidersListViewModel.swift`), an `@MainActor ObservableObject`, holds `@Published var configurations: [AIProviderConfiguration]` and feeds it straight to SwiftUI list views via the type's own `Identifiable` conformance — no separate `id:` closure is needed in a `ForEach`/`List`. Renaming a row calls `configurations[index].name = uniqueName(trimmed, excluding: id)`, relying on `display-name-mutability` and `value-semantics` so only that one array element's copy changes.
- **AppKit / UIKit**: `AIPluginKit` (the framework target, `project.yml`) targets `platform: macOS` only — there is no iOS target for it today. The AppKit layer never touches `AIProviderConfiguration` directly; it hosts the SwiftUI settings screen and receives `onRequestAddProvider`/`onRequestChat` callbacks from the view model (because "SwiftUI can't present the AppKit sheet" or "reach the window manager itself," per that file's own comments) rather than reading or writing this type's properties.
- **Compose**: model as a Kotlin `data class AIProviderConfiguration(val id: UUID = UUID.randomUUID(), var name: String, val pluginIdentifier: String, val templateId: String)`. A Kotlin `data class` synthesizes `equals`/`hashCode`/`copy` the same way Swift's compiler synthesizes `Equatable`/`Hashable` here, including `id` in the comparison; a `LazyColumn`'s `items(configurations, key = { it.id })` is the analog of the SwiftUI `Identifiable`-driven `ForEach`. Port `uniqueName(_:avoiding:)` as a companion-object function with the same `while` loop.
- **React/Web**: model as a plain TypeScript type, `interface AIProviderConfiguration { id: string; name: string; pluginIdentifier: string; templateId: string }`, with `id` generated via `crypto.randomUUID()`. JavaScript objects have no synthesized structural equality, so port `equatable-conformance`/`hashable-conformance` as an explicit `equalConfigs(a, b)` helper (or a library like a deep-equal check) comparing all four fields — omitting this is the most likely spot a web port silently diverges from `identifier-immutability`'s "different `id` means different configuration" rule. Port `uniqueName(base, taken)` as a pure exported function mirroring the same suffix loop.
- **WinUI 3**: model as a `sealed class AIProviderConfiguration` (not a `record`, so `Name` can remain independently settable while `Id`, `PluginIdentifier`, and `TemplateId` stay `{ get; }`-only) implementing `IEquatable<AIProviderConfiguration>` by comparing all four properties, matching `equatable-conformance`'s inclusion of `Id`: `public Guid Id { get; }`, `public string Name { get; set; }`, `public string PluginIdentifier { get; }`, `public string TemplateId { get; }`, with a constructor defaulting `Id` to `Guid.NewGuid()` the way the Swift initializer defaults to `UUID()`. Use `System.Text.Json`'s `JsonSerializer.Serialize`/`Deserialize<List<AIProviderConfiguration>>` for `codable-conformance`'s JSON round-trip. If the port binds a list of these to a WinUI 3 `ListView`/`ItemsRepeater` through an `ObservableCollection<AIProviderConfiguration>`, note the divergence from the source: mutating `Name` on a class instance already in the collection does **not** raise `CollectionChanged`, and WinUI's binding will not refresh that row unless `AIProviderConfiguration` also implements `INotifyPropertyChanged` for `Name` — the Swift source needs no such mechanism because `@Published var configurations: [AIProviderConfiguration]` re-publishes the whole array by value on every mutation (see `value-semantics`). Port `uniqueName(_:avoiding:)` as `public static string UniqueName(string @base, ISet<string> taken)` with the identical `while (taken.Contains($"{@base} {suffix}")) { suffix++; }` loop.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift` |

## Design Decisions

**Decision**: `AIProviderConfiguration` stores only identity (`id`, `name`, `pluginIdentifier`, `templateId`); resolved field values, secrets, and the selected model for that configuration live in separate stores keyed by `id.uuidString`, not on this type.
**Rationale**: per the type's own doc comment, this keeps "the ordered list ... a small plain-Codable array shared by the app and the daemon" — a `[AIProviderConfiguration]` can be persisted, diffed, and mirrored to the daemon's registry (`AIProviderConfigKeys.configurationsKey`) cheaply and without ever carrying secret material through that channel; secrets and values are instead addressed per-configuration via `AIProviderConfigKeys` and resolved on demand by `AIProviderConfigStore`, a sibling file.
**Approved**: pending

**Decision**: Neither `pluginIdentifier` nor `templateId` is validated against any plugin registry at construction, decode, or comparison time.
**Rationale**: `AIProviderConfigStore.clearStoredValues`'s own doc comment explicitly anticipates a configuration whose "template no longer resolves (plugin uninstalled or template renamed)" and still clears its stored values by id alone, so an orphaned `pluginIdentifier`/`templateId` is a known, caller-handled condition rather than a gap in this type; resolving those identifiers against the currently installed plugins is `AIPluginManager`'s and its descriptor's responsibility, not this type's.
**Approved**: pending

**Decision**: `uniqueName(_:avoiding:)` disambiguates by appending `" 2"`, `" 3"`, … to `base`, and the type's `Equatable`/`Hashable` conformance compares all four stored properties, including `id` — so two configurations with identical `name`, `pluginIdentifier`, and `templateId` but different `id` values are distinct, unequal configurations, not duplicates.
**Rationale**: `id` is the type's real identity (see `identifiable-conformance`); `name` is a caller-facing label a user MAY set to anything, including a value another configuration already uses. `uniqueName` exists only to make a freshly *proposed* default name friendlier, not to enforce name uniqueness as an invariant of the type itself.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

`separation-of-concerns` passes because the type carries only identity, leaving field values, model, and secrets to `AIProviderConfigKeys`-addressed stores (see Design Decisions). `idempotent-operations` passes because `uniqueName(_:avoiding:)` and the synthesized `Equatable`/`Hashable` conformances are deterministic, side-effect-free functions of their inputs (see `unique-name-static-purity`). `data-integrity` passes because the type's value semantics (see `value-semantics`) prevent one copy's mutation from silently corrupting another. `data-minimization` passes because the type collects, stores, or transmits no secret material itself (see Privacy). `input-sanitization` is partial: `name`, `pluginIdentifier`, and `templateId` accept any string content with no format or non-empty check (see `no-content-validation`); this is not itself an injection risk within this file, since it parses none of those strings, but a caller that feeds an unvalidated value into a downstream format (e.g. a settings key or a ledger, as `AIProviderConfigKeys` does) inherits whatever risk that downstream format carries.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
