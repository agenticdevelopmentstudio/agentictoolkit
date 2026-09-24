---
id: ef2a5ca9-04a4-46ab-8fef-3fdc6db2041d
title: Daemon Provider Resolver
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-daemon-provider-resolver
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Daemon-side, read-only lookup of the app's synced AI provider registry, the
  selected configuration, and a configuration's stored model, for headless daemon
  completions.
platforms:
- swift
- macos
tags:
- ai-plugin
- daemon
- configuration
- provider-resolver
depends-on:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/DaemonAIChatTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/AIProviderResolver.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Daemon Provider Resolver

## Overview

`DaemonProviderResolver` (`packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift`) is a case-less `public enum` — three static functions and no visual surface — that gives a headless host (the daemon) read-only access to the AI-provider-configuration registry the macOS app pushes over `AIProviderConfigSync`. Per its own doc comment it is "the daemon-side registry read API — the mirror of the app's AIProviderResolver," reading "the config-UUID-keyed layout a headless host receives via AIProviderConfigSync so it can resolve a configuration by id without the app." Hosts hand it a `ProviderSettingsReader` closure over whatever backs the synced values (per the doc comment, "stenographer: its SQLite settings table"), so `DaemonProviderResolver` and its caller `DaemonAIChat` never see the settings store itself. Its three functions answer: which configurations does the host currently mirror (`configurations`), which one is selected for one-shot completions (`selectedConfiguration`), and what model is stored for a given configuration (`model(config:_:)`). It performs no writes, no network access, and no logging of its own; every result is a pure function of what the supplied closure returns at the moment of the call.

## Behavioral Requirements

- **provider-settings-reader-shape**: The `ProviderSettingsReader` closure type MUST be declared `@Sendable` and MUST have the signature `(_ key: String) -> String?`.
- **provider-settings-reader-absent-key**: A `ProviderSettingsReader` MUST return `nil` when the given key is absent from whatever store the closure wraps, per the type's own doc comment ("Returns nil when a key is absent").
- **settings-store-opacity**: `DaemonProviderResolver` MUST NOT access a settings store directly; every function MUST obtain data only by invoking the `settings` closure the caller supplies, per the type's own doc comment ("the resolver and `DaemonAIChat` never see the store itself").
- **configurations-empty-when-absent**: `configurations(_:)` MUST return `[]` when `settings(AIProviderConfigKeys.configurationsKey)` returns `nil`.
- **configurations-empty-when-blank**: `configurations(_:)` MUST return `[]` when `settings(AIProviderConfigKeys.configurationsKey)` returns `""`.
- **configurations-empty-when-malformed**: `configurations(_:)` MUST return `[]`, without throwing, when the stored value at `AIProviderConfigKeys.configurationsKey` is present and non-empty but is not valid JSON or does not decode as `[AIProviderConfiguration]`.
- **configurations-array-poisoning**: `configurations(_:)` MUST discard the entire decoded array — not just the offending element — when even one element of an otherwise well-formed JSON array fails to decode as `AIProviderConfiguration`; `JSONDecoder`'s array decoding fails atomically, and `try?` turns that single element failure into the same `[]` result as a fully malformed document.
- **configurations-decode-success**: `configurations(_:)` MUST decode the stored JSON string at `AIProviderConfigKeys.configurationsKey` into `[AIProviderConfiguration]` using `JSONDecoder` and MUST return it in the same element order when decoding succeeds.
- **decode-failure-diagnostics**: NEEDS REVIEW: Not implemented in source. When `settings(AIProviderConfigKeys.configurationsKey)` returns a non-empty string that fails to decode as `[AIProviderConfiguration]`, `configurations(_:)` swallows the `JSONDecoder` error via `try?` and returns `[]` with no log call, error return, or other diagnostic signal — indistinguishable from "zero configurations registered." What is missing: whether a corrupt-but-present registry is meant to be silently treated as empty (as a genuinely absent registry is), or whether daemon operators need a signal that the app's `AIProviderConfigSync` push produced, or synced to, an undecodable value. Evidence that would settle it: a daemon-side logging or telemetry call this repository does not show, or confirmation that a decode failure here is tracked elsewhere.
- **selected-configuration-absent**: `selectedConfiguration(_:)` MUST return `nil` when `settings(AIProviderConfigKeys.selectedConfigIdKey)` returns `nil` or `""`.
- **selected-configuration-malformed-id**: `selectedConfiguration(_:)` MUST return `nil` when the stored value at `AIProviderConfigKeys.selectedConfigIdKey` is not parseable by `UUID(uuidString:)`.
- **selected-configuration-lookup**: `selectedConfiguration(_:)` MUST return the first element of `configurations(settings)` whose `id` equals the parsed `UUID`, and MUST return `nil` when no element matches.
- **selected-configuration-duplicate-id-order**: When more than one element of the decoded registry shares the same `id`, `selectedConfiguration(_:)` MUST return the first such element in array order; `DaemonProviderResolver` enforces no uniqueness invariant of its own over the registry.
- **selected-configuration-fallback-signal**: A caller SHOULD treat a `nil` result from `selectedConfiguration(_:)` as "no configuration selected — use the zero-config path," not as an error condition, matching how `DaemonAIChat.complete` falls through to its CLI path when `selectedConfiguration` returns `nil`.
- **model-empty-when-unset**: `model(config:_:)` MUST return `""` when `settings(AIProviderConfigKeys.modelKey(config: id))` returns `nil`.
- **model-verbatim-value**: `model(config:_:)` MUST return the exact string stored at `AIProviderConfigKeys.modelKey(config: id)` when present, with no trimming, case-folding, or validation applied.
- **model-lookup-independent-of-registry**: `model(config:_:)` MUST look up the stored model by the given `id` alone; it MUST NOT check whether that `id` is present in `configurations(_:)` or matches the currently selected configuration.
- **stateless-namespace**: Every function in `DaemonProviderResolver` MUST be a pure function of its arguments and of what the supplied `settings` closure returns at the moment of the call; `DaemonProviderResolver` MUST hold no stored property of its own.
- **no-instantiation**: `DaemonProviderResolver` MUST NOT be instantiated; it is declared as a case-less `enum`, so every member MUST be accessed as a static/type member.
- **no-persistence**: `DaemonProviderResolver` MUST NOT write to the settings store, a file, or any other persistent medium; the source contains no such call.
- **no-side-effects**: `DaemonProviderResolver` MUST NOT perform network access, subprocess execution, or notification posting; the source contains no such call.
- **any-thread-invocation**: `DaemonProviderResolver`'s functions MUST be callable from any thread, actor, or `Task` with no `await` and no synchronization; the type declares no `actor` or `@MainActor` isolation and holds no shared mutable state.
- **no-caching**: `DaemonProviderResolver` MUST NOT cache a prior call's result; every call MUST re-invoke `settings` and, where applicable, re-run `JSONDecoder`, so a change to the underlying store between two calls MUST be visible on the next call.

## Appearance

Not applicable — this is a daemon-side registry read API, not a visual component.

## States

Not applicable — this is a daemon-side registry read API, not a visual component. It has no lifecycle of its own: every call is a one-shot, stateless read (see `stateless-namespace`).

## Accessibility

Not applicable — this is a daemon-side registry read API, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| daemon-provider-resolver-001 | selected-configuration-lookup, configurations-decode-success | `settings` built like `DaemonAIChatTests.makeSettings(selected: configId)` (registry has one config with `id == configId`, `pluginIdentifier == pluginId`) → `DaemonProviderResolver.selectedConfiguration(settings)` | Returns a non-nil `AIProviderConfiguration` with `.id == configId` and `.pluginIdentifier == pluginId` — `DaemonAIChatTests.resolverSelectsConfiguration` |
| daemon-provider-resolver-002 | provider-settings-reader-absent-key, configurations-empty-when-absent, selected-configuration-absent | `settings = emptySettings` (`{ _ in nil }`) → `selectedConfiguration(settings)` and `configurations(settings)` | `selectedConfiguration` returns `nil`; `configurations` returns `[]` — `DaemonAIChatTests.resolverToleratesAbsentOrMalformedRegistry` |
| daemon-provider-resolver-003 | configurations-empty-when-malformed | `settings` returns `"not json"` for `AIProviderConfigKeys.configurationsKey` and `nil` for every other key → `configurations(settings)` | Returns `[]`, no error thrown — `DaemonAIChatTests.resolverToleratesAbsentOrMalformedRegistry` |
| daemon-provider-resolver-004 | provider-settings-reader-absent-key, model-empty-when-unset | `settings = emptySettings`, arbitrary `configId` → `model(config: configId, emptySettings)` | Returns `""` — `DaemonAIChatTests.resolverReadsStoredModel` |
| daemon-provider-resolver-005 | model-verbatim-value, model-lookup-independent-of-registry | `settings` built like `makeSettings(selected: configId, model: "fake-large")` → `model(config: configId, settings)` | Returns `"fake-large"` exactly — `DaemonAIChatTests.resolverReadsStoredModel` |
| daemon-provider-resolver-006 | selected-configuration-malformed-id | `settings` returns `"not-a-uuid"` for `AIProviderConfigKeys.selectedConfigIdKey` and a valid registry JSON for `configurationsKey` → `selectedConfiguration(settings)` | Returns `nil` — traced to the `guard !id.isEmpty, let uuid = UUID(uuidString: id) else { return nil }` line in `DaemonProviderResolver.swift`; no dedicated test exists in the given sources, but the outcome follows directly from that guard |
| daemon-provider-resolver-007 | selected-configuration-duplicate-id-order | Registry JSON holds two `AIProviderConfiguration` entries `[A, B]` sharing the same `id` but different `name`s; `selectedConfigIdKey` set to that shared id → `selectedConfiguration(settings)` | Returns the entry equal to `A` — traced to `configurations(settings).first { $0.id == uuid }`, which returns the first array match |
| daemon-provider-resolver-008 | configurations-decode-success | Registry JSON `[config1, config2]` (two distinct, well-formed configurations) → `configurations(settings)` | Returns `[config1, config2]` in the same order, fully decoded — traced to `try? JSONDecoder().decode([AIProviderConfiguration].self, ...)` and `AIProviderConfiguration`'s `Codable` conformance |
| daemon-provider-resolver-009 | selected-configuration-fallback-signal | `selectedConfiguration(settings)` returns `nil` inside `DaemonAIChat.complete` | `DaemonAIChat.complete` takes the `completeViaCLI` branch (the zero-config `claude -p` path) and never calls `completeViaPlugin` — traced to `DaemonAIChat.swift`'s `if let config = DaemonProviderResolver.selectedConfiguration(settings) { … }` followed by `return try await completeViaCLI(...)` |
| daemon-provider-resolver-010 | no-caching, stateless-namespace | Call `configurations(settings)` once; mutate the dictionary the `settings` closure closes over to add a new configuration; call `configurations(settings)` again | The second call's result includes the newly added configuration; no result is cached from the first call |
| daemon-provider-resolver-011 | no-instantiation | Attempt `let x = DaemonProviderResolver()` | Fails to compile: a case-less `enum` has no initializer |
| daemon-provider-resolver-012 | no-persistence, no-side-effects | Inspect `DaemonProviderResolver.swift` for `FileManager`, `URLSession`, `Process`, or any settings-write call | No such call exists; every effect happens inside the caller-supplied `settings` closure, not in this type |
| daemon-provider-resolver-013 | provider-settings-reader-shape, settings-store-opacity | Inspect `ProviderSettingsReader`'s declaration and every call site in `DaemonProviderResolver.swift` | The typealias is `@Sendable (_ key: String) -> String?`; every function accesses data only by calling the passed-in `settings` closure, never a concrete store type |
| daemon-provider-resolver-014 | any-thread-invocation | Call `DaemonProviderResolver.configurations`, `.selectedConfiguration`, and `.model` from several concurrent `Task`s with no `await` and no actor hop | Code compiles with no actor-isolation error, and each task observes a result consistent with what its own `settings` closure returns — traced to the absence of any `actor`/`@MainActor` annotation on the enum |
| daemon-provider-resolver-015 | configurations-empty-when-blank | `settings` returns `""` for `AIProviderConfigKeys.configurationsKey` → `configurations(settings)` | Returns `[]` — traced to the `guard !json.isEmpty, ...` line, which treats an empty string the same as `nil` |
| daemon-provider-resolver-016 | configurations-array-poisoning | Registry JSON is a well-formed array where one element is missing a required field (e.g. `id`) → `configurations(settings)` | Returns `[]`, not a partial list of the well-formed elements — `JSONDecoder`'s decode of `[AIProviderConfiguration]` fails as a whole when any element fails, and `try?` converts that failure to `[]` |
| daemon-provider-resolver-017 | decode-failure-diagnostics (open question) | Search `DaemonProviderResolver.swift` and its call sites for a `Logger`, `os_log`, or error-reporting call reached when the `try?` in `configurations(_:)` fails | No such call exists anywhere in the given sources — demonstrates the open question; no test in the given suite exercises a decode-failure diagnostic because the source implements none |
| daemon-provider-resolver-018 | model-lookup-independent-of-registry | `settings` returns `[]` (empty JSON array) for `configurationsKey` but a value for `AIProviderConfigKeys.modelKey(config: someId)` where `someId` is not — and never was — present in that registry → `model(config: someId, settings)` | Returns the stored model string unchanged; `model(config:_:)` never consults `configurations(_:)` |

## Edge Cases

- **Null/empty input**: `settings` returning `nil` for every key (e.g. a fresh install with no configuration ever synced) MUST cause `configurations` to return `[]`, `selectedConfiguration` to return `nil`, and `model` to return `""` — never crash or throw (MUST).
- **Null/empty input**: `settings` returning `""` for `AIProviderConfigKeys.configurationsKey` MUST be treated identically to `nil` (both fail the `!json.isEmpty` guard), yielding `[]` (MUST).
- **Null/empty input**: `settings` returning `""` for `AIProviderConfigKeys.selectedConfigIdKey` MUST be treated identically to `nil` (both fail `!id.isEmpty`), yielding `nil` from `selectedConfiguration` (MUST).
- **Boundary values**: a registry value of `"[]"` (a valid, well-formed empty JSON array) at `configurationsKey` MUST decode to `[]` via the success path, not the malformed-input path — a successful decode of zero elements, distinct from an absent or malformed value that also yields `[]` (MUST).
- **Boundary values**: a registry with exactly one configuration whose `id` matches `selectedConfigIdKey` is the minimum non-empty case for `selectedConfiguration` to succeed; it MUST return that configuration (MUST).
- **Boundary values**: `model(config:_:)` places no length or character constraint on the returned string; whatever value is stored at `AIProviderConfigKeys.modelKey(config:)` — including a very long string, one containing non-ASCII characters, or one that names no model the plugin actually recognizes — MUST be returned verbatim (MUST).
- **Concurrent access**: applicable. `DaemonProviderResolver` holds no stored or shared mutable state and declares no actor isolation, so calls from multiple threads, actors, or `Task`s MUST NOT require a lock, queue hop, or `await`, and MUST NOT race, because each call only reads through the caller-supplied, `@Sendable` `settings` closure (MUST).
- **Concurrent access**: `selectedConfiguration` performs two independent reads through `settings` — once directly for `selectedConfigIdKey`, once indirectly via `configurations` for `configurationsKey`. If the underlying store is mutated between those two reads by a concurrent writer, the two values are not read as one atomic snapshot; a transient `nil` result MAY occur and MUST be tolerated as equivalent to "not currently resolvable," never treated as an error (MUST).
- **Error states**: the only dependency is the caller-supplied `settings` closure. `DaemonProviderResolver` MUST treat any `nil` return from `settings` as "key absent" and MUST NOT distinguish "key never set" from "underlying store unavailable" — both surface identically, because `ProviderSettingsReader`'s signature carries no error case (MUST).
- **Error states**: a `configurationsKey` value that is present, non-empty, and syntactically valid JSON but decodes to the wrong shape (e.g. a JSON object instead of an array) MUST be swallowed by the `try?` and yield `[]`, identically to syntactically invalid JSON (MUST).
- **Offline or disconnected state**: Not applicable — `DaemonProviderResolver` makes no network call and has no notion of connectivity; whether the app-daemon sync (`AIProviderConfigSync`) that originally populated the settings store is currently reachable is a concern of that separate component, not of this read-only lookup.
- **Cancellation and timeouts**: Not applicable — every function is synchronous and non-`async`; there is no operation to cancel and nothing that can time out.
- **Missing file or unreachable server**: Not applicable — `DaemonProviderResolver` opens no file and calls no server; it only invokes the passed-in closure, whose own failure modes are outside this type's contract.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `settings` | `ProviderSettingsReader` (`@Sendable (String) -> String?`) | none (required) | Injected by the caller on every call; the sole source of registry, selection, and model data. |
| `id` | `UUID` | none (required for `model(config:_:)`) | The configuration identifier whose stored model is being looked up. |
| `AIProviderConfigKeys.configurationsKey` | `String` (constant, `"ai_configurations"`) | n/a | Settings key `configurations(_:)` reads for the JSON-encoded `[AIProviderConfiguration]` registry. |
| `AIProviderConfigKeys.selectedConfigIdKey` | `String` (constant, `"ai_selected_config_id"`) | n/a | Settings key `selectedConfiguration(_:)` reads for the selected configuration's UUID string. |
| `AIProviderConfigKeys.modelKey(config:)` | `String` (per-configuration, `"aiplugin.config.<id>.model"`) | n/a | Settings key `model(config:_:)` reads for that configuration's stored model. |

## Deep Linking

Not applicable: `DaemonProviderResolver.swift` defines no URL, route, or navigable destination — it is a registry-lookup API with no navigation surface of its own.

## Localization

Not applicable: the source produces no user-facing string. Its return values are either domain data (`AIProviderConfiguration` instances, a model identifier string) or storage-key lookups performed via `AIProviderConfigKeys`; none of these are text displayed to a user.

## Accessibility Options

Not applicable: `DaemonProviderResolver.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `DaemonProviderResolver` collects no data itself; it reads configuration identity (`id`, `name`, `pluginIdentifier`, `templateId`) and a stored model string from whatever the caller's `ProviderSettingsReader` returns. No credential or secret value ever passes through this type — secret values are addressed by `AIProviderConfigKeys.fieldKey`/`secretFieldsKey` and moved by `AIProviderConfigSync`/`SecretStoring`, neither of which `DaemonProviderResolver` calls.
- **Storage**: `DaemonProviderResolver` performs no storage of its own; it only reads, through the caller-supplied closure, whatever backing store the caller wraps (per the doc comment, the daemon's settings table).
- **Transmission**: this file performs no network transmission of its own; it only reads local, already-synced values.
- **Retention**: this file defines no retention policy; a value's lifetime is entirely the responsibility of the store behind the caller's `settings` closure.

## Logging

Not applicable: `DaemonProviderResolver.swift` contains no `Logger`, `os_log`, `print`, or other logging call. See `decode-failure-diagnostics` for the one place this absence is a genuine open question rather than a settled fact.

## Platform Notes

- **SwiftUI**: not applicable to this file — `DaemonProviderResolver.swift` imports only `Foundation`, with no SwiftUI dependency; any SwiftUI-based daemon-status surface would call these same static functions unchanged.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift` is part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It has no AppKit or UIKit import and is consumed by `DaemonAIChat` (same framework, also plain Foundation) from the daemon process, not from any app UI layer. The app-side mirror, `AIProviderResolver` (`macOS/Features/AIPlugins/AIProviderResolver.swift`), is `@MainActor`-isolated because it touches the AppKit-adjacent `AIPluginManager`; `DaemonProviderResolver` declares no such isolation because it touches nothing but the passed-in closure.
- **Compose**: model as a Kotlin top-level `object DaemonProviderResolver` with `fun configurations(settings: (String) -> String?): List<AIProviderConfiguration>`, `fun selectedConfiguration(settings: (String) -> String?): AIProviderConfiguration?`, and `fun model(configId: UUID, settings: (String) -> String?): String`, using `kotlinx.serialization.json.Json.decodeFromString` wrapped in `runCatching { }.getOrNull()` in place of Swift's `try?`, to match the same fail-to-empty/fail-to-null contract. `UUID.toString()` on the JVM is lowercase, unlike Foundation's uppercase `uuidString`; a shared registry with an Apple host needs the same case-normalization decision the sibling `AIProviderConfigKeys` recipe calls out.
- **React/Web**: model as a module of plain exported functions over a UUID already serialized as a string — `configurations(settings: (key: string) => string | null): AIProviderConfiguration[]`, etc. — using `JSON.parse` wrapped in `try { } catch { return [] }` to match the swallow-to-empty contract. JavaScript has no native `UUID` type, so the id-equality check in `selectedConfiguration` becomes a plain string comparison.
- **WinUI 3**: model `DaemonProviderResolver` as a `static class` with `static` methods over a `Func<string, string?>` in place of `ProviderSettingsReader` (a pure, side-effect-free delegate preserves the same any-thread-safety property `@Sendable` gives the Swift closure): `public static List<AIProviderConfiguration> Configurations(Func<string, string?> settings)`, decoding with `System.Text.Json.JsonSerializer.Deserialize<List<AIProviderConfiguration>>(json)` inside a `try`/`catch (JsonException)` that returns an empty `List<AIProviderConfiguration>` to match the Swift `try?`-to-`[]` contract; `public static AIProviderConfiguration? SelectedConfiguration(Func<string, string?> settings)` using `Guid.TryParse` in place of `UUID(uuidString:)` (returning `null` on `false`, matching the Swift guard); and `public static string Model(Guid configId, Func<string, string?> settings) => settings(AIProviderConfigKeys.ModelKey(configId)) ?? "";`. Because `Guid.ToString("D")` is lowercase while Foundation's `uuidString` is uppercase, a WinUI 3 daemon sharing a settings store with the Apple app/daemon MUST normalize case exactly as the `AIProviderConfigKeys` recipe's WinUI 3 note requires, or `Guid`-keyed lookups against Apple-written keys will silently miss. No `ObservableCollection`/`INotifyPropertyChanged` applies — like the Swift source, this is a stateless, one-shot read API, not an observable data source.

## Design Decisions

**Decision**: `configurations(_:)` and `selectedConfiguration(_:)` treat every failure mode — an absent key, an empty string, malformed JSON, a JSON value of the wrong shape, or a non-UUID selected-id string — identically: return `[]` or `nil` with no distinction and no thrown error.
**Rationale**: `ProviderSettingsReader`'s signature (`String?`, non-throwing) cannot carry an error, and the type's own doc comment states it "Returns nil / "" when the id isn't known" — the resolver fails closed rather than propagate a decode failure the daemon has no user-facing surface to report. `DaemonAIChat.complete` relies on exactly this fail-closed `nil` to fall through to its zero-config CLI path instead of erroring when the registry is empty or corrupt.
**Approved**: pending

**Decision**: `selectedConfiguration(_:)` reads `selectedConfigIdKey` and `configurationsKey` as two separate, unsynchronized calls to `settings`, rather than one combined read.
**Rationale**: `ProviderSettingsReader` exposes only single-key reads, so any transactional read across two keys would have to be implemented by the caller's backing store, not by this type; the resolver accepts the resulting non-atomicity (see Edge Cases) because a transient mismatch resolves to the same safe `nil` outcome as "no configuration selected."
**Approved**: pending

**Decision**: `selectedConfiguration(_:)` returns the first array element matching the selected id and enforces no uniqueness invariant of its own over the decoded registry.
**Rationale**: configuration-id uniqueness is established when a configuration is created (`AIProviderConfiguration.init(id: UUID = UUID(), …)` and the app-side store's add/rename flow), not re-verified by the daemon-side reader. `DaemonProviderResolver` trusts the registry it is handed, per its role as the mirror of the app's resolver, and duplicating that validation here would be redundant work with no daemon-observable benefit.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |

`separation-of-concerns` passes because the file's only responsibility is resolving registry/selection/model reads through a caller-supplied closure; it performs no storage, no secret handling, and no plugin-loading logic of its own (that lives in `DaemonAIChat`). `idempotent-operations` passes because every function is a deterministic read of its arguments and the current closure state (see `stateless-namespace`, `no-caching`). `data-minimization` passes because the file collects, stores, or transmits no data itself (see Privacy). `input-sanitization` passes because every malformed or absent input this type can receive — a missing key, an empty string, invalid JSON, a JSON value of the wrong shape, or a non-UUID id string — is handled by failing closed to `[]`/`nil`/`""` rather than throwing, crashing, or producing a corrupted result (see `configurations-empty-when-malformed`, `selected-configuration-malformed-id`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, including the open question about swallowed registry-decode diagnostics |
