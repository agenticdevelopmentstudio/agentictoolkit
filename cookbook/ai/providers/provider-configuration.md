---
id: a8054368-9885-4b83-90cf-5029728ab397
title: Provider Configuration
domain: agentictoolkit://cookbook/ai/providers/provider-configuration
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A user's named instance of a provider template — its identifier, display
  name, plugin identifier, and template identifier — plus a helper that derives
  a unique display name.
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- provider-config
depends-on: []
related:
- agentictoolkit://cookbook/ai/providers/provider-config-keys
- agentictoolkit://cookbook/ai/plugins/plugin-descriptor
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

# Provider Configuration

## Overview

The provider configuration record is "a user's named instance of a provider template: which plugin serves it, which template it was created from, and a display name." It carries exactly four fields — `id`, `name`, `pluginIdentifier`, `templateId` — and nothing else. Per-configuration field values, the selected model, and secrets live in separate stores keyed by `id` (see the sibling provider config keys concept); only identity lives on this record, so the ordered list of configurations stays a small, plainly-serializable collection shared by the app and any background process. The concept also defines one helper, deriving a unique display name, that appends a numeric suffix to a candidate name until the result is not in a caller-supplied set of names already taken. The record performs no I/O, no validation beyond basic type-shape, and has no side effect of its own.

## Behavioral Requirements

- **identifier-assignment**: Constructing a configuration MUST assign `id` from an optional argument, generating a fresh random identifier when the caller omits it.
- **identifier-immutability**: `id` MUST NOT change after construction.
- **stable-identity**: The configuration MUST expose `id` directly as its primary identity, with no separate computed value or indirection, so it can be used as the key when rendering a list of configurations.
- **display-name-mutability**: `name` MUST be assignable after construction, so a caller MAY rename a configuration in place without constructing a new value and without changing `id`, `pluginIdentifier`, or `templateId`.
- **plugin-and-template-identity-immutability**: `pluginIdentifier` and `templateId` MUST NOT change after construction.
- **no-content-validation**: Construction MUST accept any string value, including an empty string, for `name`, `pluginIdentifier`, and `templateId`; no format, length, or non-empty check is performed on any of the three.
- **json-round-trip**: A configuration, or an array of configurations, MUST encode to and decode from JSON using its four fields (`id`, `name`, `pluginIdentifier`, `templateId`) directly, with no custom coding logic.
- **concurrency-safe**: A configuration value MUST be safe to share across threads or concurrent tasks with no additional guard; every field it stores is itself safe to share this way, and the configuration performs no synchronization of its own.
- **value-equality**: Two configurations MUST compare equal only when `id`, `name`, `pluginIdentifier`, and `templateId` all match; two otherwise-identical configurations that differ only in `id` MUST compare unequal.
- **value-hashing**: Two configurations that compare equal (per value-equality) MUST hash identically, so configurations MAY be used as set elements or map keys.
- **value-semantics**: A configuration MUST behave as a copied value, not a shared reference: assigning or passing one MUST copy it, and mutating one copy's `name` MUST NOT affect any other copy or any previously encoded representation.
- **no-persistence**: A configuration MUST NOT read from or write to any settings store, secure storage, a file, or a network endpoint itself; a configuration's field values, selected model, and secrets are persisted elsewhere, keyed by `id`.
- **no-registry-validation**: Construction, decoding, and comparison MUST NOT verify that `pluginIdentifier` or `templateId` refers to a currently installed, resolvable plugin or template; the configuration consults no plugin registry (see Design Decisions).
- **unique-name-unchanged-when-free**: Deriving a unique name from a candidate MUST return the candidate unchanged when the taken set does not contain it.
- **unique-name-suffix-on-collision**: Deriving a unique name MUST return `"<candidate> 2"` when the taken set contains the candidate but not `"<candidate> 2"`.
- **unique-name-suffix-increments**: When the taken set also contains `"<candidate> 2"`, deriving a unique name MUST try successive suffixes 3, 4, … in order, returning the first candidate `"<candidate> <suffix>"` that the taken set does not contain.
- **unique-name-static-purity**: Deriving a unique name MUST have no side effect; it MUST derive its result solely from the candidate name and the taken set, returning the identical result for the identical arguments on every call, with no dependency on any configuration instance or external store.

## Appearance

Not applicable — this is a data record, not a visual component.

## States

Not applicable — this is a data record, not a visual component; it defines no runtime state machine of its own.

## Accessibility

Not applicable — this is a data record, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-configuration-001 | identifier-assignment | Construct two configurations with matching `name`, `pluginIdentifier`, `templateId` and no `id` argument supplied | Each construction produces a non-empty `id`; the two `id` values differ |
| ai-provider-configuration-002 | identifier-immutability | Attempt to assign a new value to an existing configuration's `id` after construction | Not permitted — `id` has no setter |
| ai-provider-configuration-003 | stable-identity | Bind a configuration to a context that renders a list keyed by identity, then read its `id` | Works with no adapter; the value used for identity equals `id` directly |
| ai-provider-configuration-004 | display-name-mutability | Construct a configuration, capture its `(id, pluginIdentifier, templateId)`, then reassign only `name` | `name` updates to the new value; `(id, pluginIdentifier, templateId)` are unchanged |
| ai-provider-configuration-005 | plugin-and-template-identity-immutability | Attempt to assign a new value to an existing configuration's `pluginIdentifier` or `templateId` | Not permitted — neither has a setter |
| ai-provider-configuration-006 | no-content-validation | Construct a configuration with `name`, `pluginIdentifier`, and `templateId` all set to an empty string | Construction succeeds with no error; all three fields read back as empty strings |
| ai-provider-configuration-007 | json-round-trip | Encode an array containing one configuration (random `id`, non-empty `name`/`pluginIdentifier`/`templateId`) to JSON, then decode it back | The decoded array equals the original |
| ai-provider-configuration-008 | concurrency-safe | Capture a configuration value in a closure or task handed off to run concurrently, under strict concurrency checking | No safety diagnostic is raised |
| ai-provider-configuration-009 | value-equality | Construct two configurations with identical `name`, `pluginIdentifier`, `templateId` but each given its own freshly generated `id` | The two values compare unequal, because equality includes `id` |
| ai-provider-configuration-010 | value-hashing | Insert two configurations that compare equal (copied from one instance, so all four fields match) into a set | The set contains one entry |
| ai-provider-configuration-011 | value-semantics | Construct a configuration `a`, copy it to `b`, then reassign `a`'s `name` | `b.name` is unchanged; `a.name` reflects the new value |
| ai-provider-configuration-012 | no-persistence | Inspect the record's own logic for any settings-store, secure-storage, file, or network call | None is present; the record touches no persistence or networking API of its own |
| ai-provider-configuration-013 | no-registry-validation | Construct a configuration with a `pluginIdentifier` and `templateId` that match no installed plugin or template | Construction succeeds with no error, warning, or lookup performed |
| ai-provider-configuration-014 | unique-name-unchanged-when-free | Derive a unique name for candidate "Groq" against an empty taken set | "Groq" |
| ai-provider-configuration-015 | unique-name-suffix-on-collision | Derive a unique name for candidate "Groq" against a taken set containing "Groq" | "Groq 2" |
| ai-provider-configuration-016 | unique-name-suffix-increments | Derive a unique name for candidate "Groq" against a taken set containing "Groq" and "Groq 2" | "Groq 3" — a direct consequence of trying successive suffixes until one is free |
| ai-provider-configuration-017 | unique-name-static-purity | Derive a unique name for candidate "Groq" against a taken set containing "Groq", twice in immediate succession, with no configuration instance involved | Both calls return "Groq 2"; no state changes between calls |
| ai-provider-configuration-018 | json-round-trip, value-equality (external-store evidence) | Construct a configuration, store it as the sole entry of the app's configuration list, and record its `id` as the selected configuration | The stored list contains exactly that configuration, and the selected-configuration record equals its `id`; this round-trips through an external store, not through the record's own logic |

## Edge Cases

- **Empty `name`, `pluginIdentifier`, or `templateId`**: MUST be accepted without error (see `no-content-validation`); an empty `name` displays as a blank label wherever it is shown, but the record performs no rejection.
- **Taken set is empty**: deriving a unique name MUST return the candidate unchanged (see `unique-name-unchanged-when-free`) — an empty set is a valid, ordinary input, not a special case.
- **Candidate already ends in a numeric suffix**: deriving a unique name for "Groq 2" against a taken set containing "Groq 2" MUST return "Groq 2 2", because the suffix is appended unconditionally with no check for whether the candidate already looks like a suffixed name; this is a documented quirk of the naming scheme, not a bug the concept guards against.
- **Extremely large taken sets**: the suffix search has no iteration cap; for any finite taken set — the only kind a caller can construct — the search MUST terminate at the first untaken `"<candidate> <suffix>"`. There is no overflow guard on the suffix counter, but exhausting it would require a caller to have first supplied an unrealistic number of already-taken names for a list of a user's own configurations.
- **Concurrent access**: the record declares no shared mutable state of its own (see `value-semantics`); two threads or tasks each holding their own copy MUST NOT be able to race on the record's own storage. Concurrent mutation of a shared collection of configurations (e.g. a list read and written from two threads at once) is the concern of that collection's own synchronization, not of this record.
- **Error states from a dependency**: Not applicable — the record has no dependency (no network, database, or file-system call) that could fail; per `no-persistence`, it never touches a store.
- **Offline or disconnected state**: Not applicable — the record performs no network access of its own.
- **Cancellation and timeouts**: Not applicable — every operation is synchronous and non-throwing; there is nothing to cancel and no operation that can time out.
- **Missing file or unreachable server**: Not applicable — the record opens no file and makes no server call.
- **Orphaned `pluginIdentifier`/`templateId`**: a configuration whose plugin has since been uninstalled, or whose template id no longer resolves in that plugin's descriptor, MUST still decode, compare, and hash normally; the record performs no liveness check against the current plugin registry (see `no-registry-validation` and Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | identifier | freshly generated | Stable identity for a configuration instance. |
| `name` | string | none (required) | Caller-supplied display name; mutable after construction; no validation. |
| `pluginIdentifier` | string | none (required) | Identifies which plugin serves this configuration; not checked against any registry by this record. |
| `templateId` | string | none (required) | Identifies which provider template this configuration was created from; not checked against any registry by this record. |
| `base` (deriving a unique name) | string | none (required) | Candidate display name the caller wants made unique. |
| `taken` (deriving a unique name) | set of strings | none (required) | Names already in use that the returned name MUST avoid. |

## Deep Linking

Not applicable: the record defines no URL, route, or navigable destination — it is an identity data record with no navigation surface of its own.

## Localization

Not applicable: the record contains no user-facing string literal; `name` is caller-supplied data rather than a hardcoded UI string, and the numeric suffix appended when deriving a unique name is formatting, not natural-language text.

## Accessibility Options

Not applicable: the record renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the record declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: the record contains no analytics or event-emission call of any kind.

## Privacy

Not applicable: the record never stores, reads, or transmits a token or credential value itself — a configuration's secrets are persisted separately, keyed by `id` (see the sibling provider config keys concept for how those keys and their credential-bearing values are handled).

## Logging

Not applicable: the record contains no logging call of any kind.

## Platform Notes

- **Swift/Foundation**: implemented as a `Codable`, `Sendable`, `Identifiable`, `Equatable`, `Hashable` `struct` with `public let id: UUID = UUID()`, `public var name: String`, `public let pluginIdentifier: String`, `public let templateId: String`. Immutability of `id`, `pluginIdentifier`, and `templateId` is enforced by declaring them `let`, so an assignment attempt fails to compile. `Codable`, `Equatable`, and `Hashable` conformance are compiler-synthesized over the four stored properties with no custom coder. `Sendable` conformance needs no additional guard because every stored property is itself `Sendable` and the type is a value type with no reference-type storage. Deriving a unique name is implemented as a `static func uniqueName(_ base: String, avoiding taken: Set<String>) -> String`, using a `while taken.contains("\(base) \(suffix)") { suffix += 1 }` loop starting at `suffix = 2`.
- **SwiftUI**: this is the source's primary consumer pattern. `LLMProvidersListViewModel` (`macOS/Features/AIPlugins/Settings/LLMProvidersListViewModel.swift`), an `@MainActor ObservableObject`, holds `@Published var configurations: [AIProviderConfiguration]` and feeds it straight to SwiftUI list views via the type's own `Identifiable` conformance — no separate `id:` closure is needed in a `ForEach`/`List`. Renaming a row calls `configurations[index].name = uniqueName(trimmed, avoiding: takenNames)`, relying on `display-name-mutability` and `value-semantics` so only that one array element's copy changes.
- **AppKit / UIKit**: `AIPluginKit` (the framework target, `project.yml`) targets `platform: macOS` only — there is no iOS target for it today. The AppKit layer never touches `AIProviderConfiguration` directly; it hosts the SwiftUI settings screen and receives `onRequestAddProvider`/`onRequestChat` callbacks from the view model (because "SwiftUI can't present the AppKit sheet" or "reach the window manager itself," per that file's own comments) rather than reading or writing this type's properties.
- **Compose**: model as a Kotlin `data class AIProviderConfiguration(val id: UUID = UUID.randomUUID(), var name: String, val pluginIdentifier: String, val templateId: String)`. A Kotlin `data class` synthesizes `equals`/`hashCode`/`copy` the same way Swift's compiler synthesizes `Equatable`/`Hashable` here, including `id` in the comparison; a `LazyColumn`'s `items(configurations, key = { it.id })` is the analog of the SwiftUI `Identifiable`-driven `ForEach`. Port `uniqueName(_:avoiding:)` as a companion-object function with the same `while` loop.
- **React/Web**: model as a plain TypeScript type, `interface AIProviderConfiguration { id: string; name: string; pluginIdentifier: string; templateId: string }`, with `id` generated via `crypto.randomUUID()`. JavaScript objects have no synthesized structural equality, so port `value-equality`/`value-hashing` as an explicit `equalConfigs(a, b)` helper (or a library like a deep-equal check) comparing all four fields — omitting this is the most likely spot a web port silently diverges from `identifier-immutability`'s "different `id` means different configuration" rule. Port `uniqueName(base, taken)` as a pure exported function mirroring the same suffix loop.
- **WinUI 3**: model as a `sealed class AIProviderConfiguration` (not a `record`, so `Name` can remain independently settable while `Id`, `PluginIdentifier`, and `TemplateId` stay `{ get; }`-only) implementing `IEquatable<AIProviderConfiguration>` by comparing all four properties, matching `value-equality`'s inclusion of `Id`: `public Guid Id { get; }`, `public string Name { get; set; }`, `public string PluginIdentifier { get; }`, `public string TemplateId { get; }`, with a constructor defaulting `Id` to `Guid.NewGuid()` the way the Swift initializer defaults to `UUID()`. Use `System.Text.Json`'s `JsonSerializer.Serialize`/`Deserialize<List<AIProviderConfiguration>>` for `json-round-trip`'s JSON round-trip. If the port binds a list of these to a WinUI 3 `ListView`/`ItemsRepeater` through an `ObservableCollection<AIProviderConfiguration>`, note the divergence from the source: mutating `Name` on a class instance already in the collection does **not** raise `CollectionChanged`, and WinUI's binding will not refresh that row unless `AIProviderConfiguration` also implements `INotifyPropertyChanged` for `Name` — the Swift source needs no such mechanism because `@Published var configurations: [AIProviderConfiguration]` re-publishes the whole array by value on every mutation (see `value-semantics`). Port `uniqueName(_:avoiding:)` as `public static string UniqueName(string @base, ISet<string> taken)` with the identical `while (taken.Contains($"{@base} {suffix}")) { suffix++; }` loop.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift` |

## Design Decisions

**Decision**: `AIProviderConfiguration` stores only identity (`id`, `name`, `pluginIdentifier`, `templateId`); resolved field values, secrets, and the selected model for that configuration live in separate stores keyed by `id.uuidString`, not on this type.
**Rationale**: per the type's own doc comment, this keeps "the ordered list ... a small plain-Codable array shared by the app and the daemon" — a `[AIProviderConfiguration]` can be persisted, diffed, and mirrored to the daemon's registry (`AIProviderConfigKeys.configurationsKey`) cheaply and without ever carrying secret material through that channel; secrets and values are instead addressed per-configuration via `AIProviderConfigKeys` and resolved on demand by `AIProviderConfigStore`, a sibling file. (Swift)
**Approved**: pending

**Decision**: Neither `pluginIdentifier` nor `templateId` is validated against any plugin registry at construction, decode, or comparison time.
**Rationale**: `AIProviderConfigStore.clearStoredValues`'s own doc comment explicitly anticipates a configuration whose "template no longer resolves (plugin uninstalled or template renamed)" and still clears its stored values by id alone, so an orphaned `pluginIdentifier`/`templateId` is a known, caller-handled condition rather than a gap in this type; resolving those identifiers against the currently installed plugins is `AIPluginManager`'s and its descriptor's responsibility, not this type's.
**Approved**: pending

**Decision**: `uniqueName(_:avoiding:)` disambiguates by appending `" 2"`, `" 3"`, … to `base`, and the type's `Equatable`/`Hashable` conformance compares all four stored properties, including `id` — so two configurations with identical `name`, `pluginIdentifier`, and `templateId` but different `id` values are distinct, unequal configurations, not duplicates.
**Rationale**: `id` is the type's real identity (see `stable-identity`); `name` is a caller-facing label a user MAY set to anything, including a value another configuration already uses. `uniqueName` exists only to make a freshly *proposed* default name friendlier, not to enforce name uniqueness as an invariant of the type itself.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/providers/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
