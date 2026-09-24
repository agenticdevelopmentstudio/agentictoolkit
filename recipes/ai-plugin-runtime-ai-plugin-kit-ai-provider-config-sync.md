---
id: 1d7812e7-28cb-4874-897f-43aab62fe009
title: AI Provider Config Sync
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-provider-config-sync
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The Codable app-to-daemon wire contract mirroring the whole AI provider registry
  (enabled flag, selection pointer, and every resolved configuration) in one payload.
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- sendable
- foundation
- provider-config
- wire-contract
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys
references:
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/AIProviderConfigSyncTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/DaemonAIChatTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/AIProviderConfigStore.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# AI Provider Config Sync

## Overview

`AIProviderConfigSync.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift`) declares two `public` value types that together form the app-to-daemon wire contract for AI provider configuration: `AIProviderConfigSync` (the envelope: whether AI summaries are enabled, which configuration is selected, and every configured provider) and `ResolvedProviderConfig` (one fully-resolved configuration's identity, model, and value bag). Per the file's own doc comment, this type "Replaces the old flattened `[String: Any]` push: carries the WHOLE set of configurations plus a pointer to the active one, so the daemon mirrors the full registry (keyed by configuration identity) rather than a single plugin-keyed slot." Both types conform to `Codable`, `Sendable`, and `Equatable`, and neither performs any I/O, validation beyond what the Swift compiler enforces, or any side effect — the file is the shape of the sync payload, not an implementation of sending, receiving, or applying it. `AIProviderConfigKeys.swift`'s own doc comment names the two ends of this contract: the app's `AIProviderConfigStore` (`UserDefaults` / app-Keychain) and "the daemon's registry (settings table / daemon-Keychain)"; `ResolvedProviderConfig`'s doc comment adds that the daemon "persists each under `AIProviderConfigKeys` keyed by `id`." No source file in this repository constructs an `AIProviderConfigSync` value outside of its own test target, and none decodes or applies one — see the `sync-application-unimplemented` requirement below.

## Behavioral Requirements

- **enabled-flag**: `AIProviderConfigSync` MUST carry a required `enabled: Bool` field recording whether AI summaries are enabled.
- **selected-config-id-optional**: `AIProviderConfigSync` MUST declare `selectedConfigId` as `UUID?`; per the source's doc comment, "nil / absent == zero-config path" — the configuration used for one-shot completions when a value is present, and the zero-config `claude -p` default (per `DaemonAIChat.complete`) when it is `nil`.
- **configs-collection**: `AIProviderConfigSync` MUST carry `configs: [ResolvedProviderConfig]`, described by the source as "Every configured provider, fully resolved (values + secrets)."
- **full-registry-snapshot**: `AIProviderConfigSync` MUST represent one complete, self-contained snapshot of the entire provider registry — every currently configured provider plus the current selection — because the type declares no delta, patch, or removed-ids shape; the source's own doc comment states this is the reason it exists, replacing "the old flattened `[String: Any]` push" so "the daemon mirrors the full registry ... rather than a single plugin-keyed slot."
- **resolved-config-identity-fields**: `ResolvedProviderConfig` MUST carry `id: UUID`, `name: String`, `pluginIdentifier: String`, and `templateId: String` — the same four identity fields `AIProviderConfiguration` carries — plus `model: String`, none of which has a default value in the initializer.
- **resolved-config-value-split**: `ResolvedProviderConfig` MUST carry a configuration's resolved value bag split into two same-shaped `[String: String]` dictionaries, `values` (non-secret fields) and `secrets` (secret fields), each keyed by the field's own key string — the same key a field would address via `AIProviderConfigKeys.fieldKey(config:field:)`.
- **empty-secret-clears-credential**: An empty string value under a key in `ResolvedProviderConfig.secrets` MUST be interpreted, per the source's own doc comment, as meaning "clear this credential" — i.e. a present-but-empty secret is a distinct, meaningful signal from that key being absent from `secrets` altogether.
- **codable-field-names**: `AIProviderConfigSync` and `ResolvedProviderConfig` MUST encode and decode using the compiler-synthesized `Codable` conformance with no custom `CodingKeys`, so the wire's JSON keys are exactly the Swift property names: `enabled`, `selectedConfigId`, `configs` for the envelope, and `id`, `name`, `pluginIdentifier`, `templateId`, `model`, `values`, `secrets` for each resolved configuration.
- **selected-config-id-omits-key-when-nil**: Encoding an `AIProviderConfigSync` whose `selectedConfigId` is `nil` MUST omit the `selectedConfigId` key from the JSON entirely rather than writing it as `null`, because the compiler-synthesized `Encodable` conformance calls `encodeIfPresent` for an `Optional`-typed stored property.
- **selected-config-id-decodes-missing-as-nil**: Decoding a JSON object that omits the `selectedConfigId` key MUST succeed and yield `selectedConfigId == nil`, traced to `AIProviderConfigSyncTests.testDecodesMissingSelectionAsNil`, which decodes `{"enabled":false,"configs":[]}` and asserts `decoded.selectedConfigId == nil`.
- **equatable-structural**: `AIProviderConfigSync` and `ResolvedProviderConfig` MUST conform to `Equatable`, comparing two instances equal if and only if every stored property is equal — the compiler-synthesized memberwise conformance — traced to `AIProviderConfigSyncTests.testRoundTrip`, which asserts a decoded value equals the original it was encoded from.
- **sendable-conformance**: `AIProviderConfigSync` and `ResolvedProviderConfig` MUST conform to `Sendable`; every stored property (`Bool`, `UUID?`, `String`, `[String: String]`, and arrays of these Sendable types) is itself `Sendable`, so the compiler accepts the conformance with no manual synchronization required to pass a value from the app's process into a daemon-facing call, or across any `Task`/actor boundary.
- **concurrency-isolation**: `AIProviderConfigSync` and `ResolvedProviderConfig` MUST be usable synchronously from any thread, actor, or `Task` with no `await`; the source declares neither type as an `actor` nor `@MainActor`-isolated, so every initializer and property access is `nonisolated` by default.
- **mutable-stored-properties**: Every stored property of `AIProviderConfigSync` (`enabled`, `selectedConfigId`, `configs`) and of `ResolvedProviderConfig` (`id`, `name`, `pluginIdentifier`, `templateId`, `model`, `values`, `secrets`) MUST be declared `var`, not `let`; unlike an immutable value type, an existing local instance MAY have any of these properties reassigned in place after construction.
- **memberwise-initializers**: `AIProviderConfigSync` and `ResolvedProviderConfig` MUST each expose a `public` memberwise initializer taking every stored property as a required parameter with no default value, so every field MUST be supplied explicitly at construction (including `selectedConfigId: nil` when there is no selection).
- **no-persistence**: `AIProviderConfigSync` and `ResolvedProviderConfig` MUST NOT read from or write to `UserDefaults`, the Keychain, a settings table, or a file themselves; the source declares only stored properties, a memberwise initializer, and the compiler-synthesized `Codable`/`Equatable` conformances.
- **no-side-effects**: Constructing, encoding, decoding, or reading any property of either type MUST NOT perform network access, subprocess execution, or notification posting; the source contains no such call.
- **no-error-domain**: Neither initializer MUST throw, and the file MUST NOT declare an `Error` type; construction always succeeds structurally for any argument values supplied, because the source performs no content validation (see Edge Cases).
- **sync-application-unimplemented**: NEEDS REVIEW: Not implemented in source. No function anywhere in this repository decodes an incoming `AIProviderConfigSync` payload and writes its contents into the `AIProviderConfigKeys`-addressed settings/Keychain layout that `DaemonProviderResolver` reads back (`configurationsKey`, `selectedConfigIdKey`, `enabledKey`, and the per-configuration `fieldKey`/`modelKey`/`secretFieldsKey`/`fieldsKey`), and no function constructs and transmits an `AIProviderConfigSync` from the app side either — the only place `AIProviderConfigSync(...)` is called anywhere under `packages/apple/AgenticToolkit` is `AIProviderConfigSyncTests.testRoundTrip`. What is missing: the app-side sender that builds this payload from `AIProviderConfigStore`, and the daemon-side receiver that decodes it and persists each `ResolvedProviderConfig` under `AIProviderConfigKeys` (honoring `empty-secret-clears-credential`). Evidence that would settle it: the daemon host implementation this file's doc comments attribute the receiving end to (e.g. the process `DaemonProviderResolver`'s doc comment calls "a headless host"), which is not present in this repository, or confirmation that this wiring has not yet been built.
- **configs-id-uniqueness-unenforced**: NEEDS REVIEW: Not implemented in source. `AIProviderConfigSync.configs` is a plain `[ResolvedProviderConfig]` with no check that every entry's `id` is unique, yet the type's own doc comment states its purpose is so "the daemon mirrors the full registry (keyed by configuration identity)" — a keyed mirror cannot hold two different values under one key, so two `configs` entries sharing an `id` would have one silently overwrite the other's `values`/`secrets`/`model` once persisted under `AIProviderConfigKeys`, with no error raised anywhere in this file. What is missing: a defined outcome for duplicate ids (reject at construction, reject at decode, or a documented "last one wins" rule). Evidence that would settle it: validation in whatever daemon-side receiver eventually decodes this payload (see `sync-application-unimplemented`), which does not exist in this repository today.

## Appearance

Not applicable — this is a Codable wire-contract value type, not a visual component.

## States

Not applicable — this is a Codable wire-contract value type with no lifecycle of its own; it has no running/loading/failed states, only the mutable field values described in `mutable-stored-properties`.

## Accessibility

Not applicable — this is a Codable wire-contract value type, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-config-sync-001 | codable-field-names, equatable-structural | Construct `AIProviderConfigSync(enabled: true, selectedConfigId: id, configs: [ResolvedProviderConfig(id: id, name: "Groq", pluginIdentifier: "com.x.openai-compatible", templateId: "custom", model: "llama-3.3-70b", values: ["baseURL": "https://api.groq.com/openai/v1"], secrets: ["apiKey": "sk-abc"])])`, encode with `JSONEncoder`, decode with `JSONDecoder` | Decoded value `== ` the original — `AIProviderConfigSyncTests.testRoundTrip` |
| ai-provider-config-sync-002 | selected-config-id-decodes-missing-as-nil | Decode `{"enabled":false,"configs":[]}` | `decoded.selectedConfigId == nil`, `decoded.enabled == false`, `decoded.configs.isEmpty == true` — `AIProviderConfigSyncTests.testDecodesMissingSelectionAsNil` |
| ai-provider-config-sync-003 | selected-config-id-omits-key-when-nil | Encode `AIProviderConfigSync(enabled: false, selectedConfigId: nil, configs: [])` with `JSONEncoder` | The resulting JSON object has no `selectedConfigId` key at all (not a `null` value) |
| ai-provider-config-sync-004 | configs-collection | Encode `AIProviderConfigSync(enabled: true, selectedConfigId: nil, configs: [])` | The resulting JSON's `configs` key is present as `[]` |
| ai-provider-config-sync-005 | empty-secret-clears-credential | Round-trip a `ResolvedProviderConfig` whose `secrets` is `["apiKey": ""]` through `JSONEncoder`/`JSONDecoder` | Decoded `secrets["apiKey"] == ""` — the empty string survives the wire unchanged (not stripped or converted to a missing key), preserving the "clear this credential" signal |
| ai-provider-config-sync-006 | equatable-structural | Two `ResolvedProviderConfig` values built with identical `id`, `name`, `pluginIdentifier`, `templateId`, `model`, `values`, `secrets`, versus a third differing only in `model` | The first two compare `==`; the third compares `!=` to either |
| ai-provider-config-sync-007 | equatable-structural | Two `AIProviderConfigSync` values with identical `enabled`/`selectedConfigId`/`configs`, versus a third differing only in `enabled` | The first two compare `==`; the third compares `!=` to either |
| ai-provider-config-sync-008 | codable-field-names | Encode `ResolvedProviderConfig(id: UUID("11111111-2222-3333-4444-555555555555")!, ...)` | The JSON `id` field is the string `"11111111-2222-3333-4444-555555555555"` (Foundation's canonical uppercase, hyphenated `uuidString` form) |
| ai-provider-config-sync-009 | sendable-conformance, concurrency-isolation | Capture a constructed `AIProviderConfigSync` value in a closure passed to a new `Task` with no `await` and no actor hop | Compiles with no `Sendable`-conformance diagnostic, because every stored property is itself `Sendable` |

## Edge Cases

- **Empty `configs` array**: `AIProviderConfigSync.init` MUST NOT reject `configs: []`; the source has no non-empty check, and this is exactly the shape `AIProviderConfigSyncTests.testDecodesMissingSelectionAsNil` decodes.
- **`selectedConfigId` is `nil`**: MUST be accepted as the documented zero-config path (see `selected-config-id-optional`); this is not an error state.
- **`selectedConfigId` does not match any `id` in `configs`**: `AIProviderConfigSync.init` MUST NOT reject this combination; the type enforces no referential relationship between the two fields. Downstream, `DaemonProviderResolver.selectedConfiguration` already tolerates exactly this case gracefully — `configurations(settings).first { $0.id == uuid }` returns `nil` when no entry matches, and `DaemonAIChat.complete` falls through to the zero-config CLI default — so a dangling selection is a defined, non-crashing outcome once the payload reaches that resolver, even though this file itself does not validate it.
- **Duplicate `id` values across `configs` entries**: See `configs-id-uniqueness-unenforced` — the type accepts duplicates with no error, and what happens once such a payload is persisted is undefined in source.
- **Empty string identity or model fields** (`name: ""`, `pluginIdentifier: ""`, `templateId: ""`, `model: ""`): `ResolvedProviderConfig.init` MUST NOT reject any of these; the source performs no content validation on any `String` field.
- **Empty `values` or `secrets` dictionaries**: `ResolvedProviderConfig.init` MUST NOT reject `values: [:]` or `secrets: [:]`; both are plain `[String: String]` with no minimum-count requirement.
- **The same field key present in both `values` and `secrets`**: the source enforces no disjointness between the two dictionaries; nothing in this file resolves which one a receiver should prefer if both contain the same key.
- **Very large `configs` array**: `AIProviderConfigSync.init` MUST NOT reject any array length; the source declares no upper bound on the number of configurations a sync payload may carry.
- **Concurrent access**: applicable, and safe by construction for reads — `AIProviderConfigSync` and `ResolvedProviderConfig` are `Sendable`, so an already-constructed, unshared copy MAY be read from multiple tasks concurrently with no synchronization. Because every stored property is `var` (see `mutable-stored-properties`), a single instance held in shared mutable storage (e.g. a `var` captured by multiple concurrent tasks) still needs the caller's own synchronization (an actor, a lock, or a serial queue) to avoid a data race on that shared variable — `Sendable` guarantees a value is safe to *transfer*, not that a shared mutable binding to it is automatically synchronized.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) of its own that could fail; whatever eventually sends or receives this payload over the app-daemon boundary is a different, currently-unimplemented component (see `sync-application-unimplemented`), not this file.
- **Offline or disconnected state**: Not applicable — `AIProviderConfigSync.swift` performs no network access itself; it only defines the shape of a payload some other, unimplemented transport would carry.
- **Cancellation and timeouts**: Not applicable — every operation in this file (construction, encoding, decoding, equality) is synchronous and non-`async`; there is nothing to cancel and no operation that can time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `Bool` | none (required) | `AIProviderConfigSync`'s flag for whether AI summaries are enabled. |
| `selectedConfigId` | `UUID?` | none (required; pass `nil` for no selection) | `AIProviderConfigSync`'s pointer to the configuration used for summaries; `nil` is the documented zero-config path. |
| `configs` | `[ResolvedProviderConfig]` | none (required) | `AIProviderConfigSync`'s full set of configured providers, fully resolved. |
| `id` | `UUID` | none (required) | `ResolvedProviderConfig`'s identity, matching the app-side `AIProviderConfiguration.id` it mirrors. |
| `name` | `String` | none (required) | `ResolvedProviderConfig`'s display name. |
| `pluginIdentifier` | `String` | none (required) | `ResolvedProviderConfig`'s `.aiplugin` bundle identifier. |
| `templateId` | `String` | none (required) | `ResolvedProviderConfig`'s provider-template identifier. |
| `model` | `String` | none (required) | `ResolvedProviderConfig`'s resolved model string. |
| `values` | `[String: String]` | none (required) | `ResolvedProviderConfig`'s non-secret resolved field values, keyed by field key. |
| `secrets` | `[String: String]` | none (required) | `ResolvedProviderConfig`'s secret resolved field values, keyed by field key; an empty value means "clear this credential." |

## Deep Linking

Not applicable: `AIProviderConfigSync.swift` defines no URL, route, or navigable destination — it is a wire-payload shape with no navigation surface of its own.

## Localization

Not applicable: the source contains no user-facing string literal; `name`, `pluginIdentifier`, `templateId`, `model`, and every key/value in `values`/`secrets` are caller-supplied data, never text this file displays or hardcodes.

## Accessibility Options

Not applicable: `AIProviderConfigSync.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `ResolvedProviderConfig.secrets` carries a provider credential (e.g. an API key) for every configuration that has one, alongside `values`' non-secret fields (e.g. `baseURL`). `AIProviderConfigSync` bundles every configuration's `secrets` together with `enabled` and `selectedConfigId` into one payload — the type's stated purpose is to move the app's full, already-resolved credential set to the daemon in one shot.
- **Storage**: `AIProviderConfigSync.swift` performs no storage of its own (see `no-persistence`); per its doc comment, the receiving side is expected to persist each configuration "under `AIProviderConfigKeys` keyed by `id`" — plain settings keys for `values`, and a secure store (Keychain, per `AIProviderConfigKeys`'s doc comment) for `secrets` — but no such receiver exists in this repository (see `sync-application-unimplemented`), so today nothing in this codebase actually stores a value carried by this type.
- **Transmission**: this file defines the payload's shape but performs no transmission itself; it is documented as crossing the app-to-daemon boundary (a process boundary, and per `AIProviderConfigKeys`'s doc comment, potentially between the app's storage and "the daemon's registry"), but no sender exists in this repository either (see `sync-application-unimplemented`).
- **Retention**: `AIProviderConfigSync` and `ResolvedProviderConfig` define no retention policy or expiry of their own; a constructed instance is a transient in-memory value with no cache. Any retention of the credentials it carries is entirely the responsibility of whatever (currently unimplemented) receiver persists them.
- **Disclosure safeguard**: Neither `AIProviderConfigSync` nor `ResolvedProviderConfig` overrides `CustomStringConvertible`/`CustomDebugStringConvertible`, so the compiler-synthesized default description of either type prints the entire `secrets` dictionary — including any credential — verbatim; the types apply no redaction of their own. No caller in `packages/apple/AgenticToolkit` logs or prints an `AIProviderConfigSync`/`ResolvedProviderConfig` value today, so this has no live effect in this repository, but nothing in the type would stop a future caller from doing so.

## Logging

Not applicable: `AIProviderConfigSync.swift` contains no `Logger`, `os_log`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIProviderConfigSync.swift` imports only `Foundation`, with no SwiftUI dependency; a SwiftUI-based settings screen would construct and encode this type unchanged before handing it to whatever transport eventually sends it to the daemon.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It is plain Foundation with no AppKit import; the app-side `AIProviderConfigStore.swift` (`macOS/Features/AIPlugins/`, `@MainActor`-isolated) is the natural source of the field values this type would carry, and the daemon-side `DaemonProviderResolver`/`DaemonAIChat` are the natural consumers of what it would deliver, though neither side currently constructs or decodes one (see `sync-application-unimplemented`).
- **Compose**: model `AIProviderConfigSync` and `ResolvedProviderConfig` as `@Serializable` Kotlin `data class`es (`kotlinx.serialization`) with `var` properties to match the source's mutability, and `UUID` as `java.util.UUID` serialized to its string form. Note the same cross-platform case-sensitivity issue documented on the sibling `AIProviderConfigKeys` recipe: `UUID.toString()` on the JVM is lowercase, while Foundation's `uuidString` is uppercase — an Android daemon and an Apple app sharing this payload over the same wire MUST agree on one case (or compare case-insensitively) for `id`/`selectedConfigId` to match correctly.
- **React/Web**: model as a plain TypeScript interface — `interface AIProviderConfigSync { enabled: boolean; selectedConfigId?: string; configs: ResolvedProviderConfig[] }` — with `id`s as `string` (JavaScript has no native `UUID` type). Replicating `selected-config-id-omits-key-when-nil` needs care: `JSON.stringify` omits a key whose value is `undefined` but keeps one whose value is `null`, so the field must be typed/constructed as `selectedConfigId?: string` (and left `undefined`, never set to `null`) to match Swift's "omit the key entirely" behavior exactly.
- **WinUI 3**: model as C# `record`s using `System.Text.Json` — e.g. `public sealed record AIProviderConfigSync(bool Enabled, Guid? SelectedConfigId, IReadOnlyList<ResolvedProviderConfig> Configs);` and `public sealed record ResolvedProviderConfig(Guid Id, string Name, string PluginIdentifier, string TemplateId, string Model, IReadOnlyDictionary<string, string> Values, IReadOnlyDictionary<string, string> Secrets);`. Apply `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]` (or an equivalent serializer option) to `SelectedConfigId` to reproduce `selected-config-id-omits-key-when-nil` — `System.Text.Json` writes `null` by default for a `null` nullable property, unlike Swift's key-omitting `encodeIfPresent`. Normalize `Guid.ToString()` (default `"D"` format, lowercase) to uppercase with `.ToUpperInvariant()` — or normalize consistently on read — so `id`/`selectedConfigId` values match byte-for-byte against Foundation's uppercase `uuidString` on the Apple side of the wire. `IReadOnlyDictionary<string, string>`/`Dictionary<string, string>` replace `[String: String]` for `Values`/`Secrets`; preserve `empty-secret-clears-credential` by treating a present key with an empty string the same as the Swift side does, not as equivalent to the key's absence.

## Design Decisions

**Decision**: `AIProviderConfigSync` carries the entire provider registry (every `ResolvedProviderConfig` plus the current selection) in one payload, rather than an incremental add/remove/update delta.
**Rationale**: per the type's own doc comment, this is a deliberate replacement for "the old flattened `[String: Any]` push," chosen so "the daemon mirrors the full registry ... rather than a single plugin-keyed slot" — a full-snapshot payload cannot drift from partial updates arriving out of order, at the cost of resending every configuration's `values`/`secrets` on every sync, even for configurations that did not change.
**Approved**: pending

**Decision**: `ResolvedProviderConfig` splits a configuration's resolved values into two parallel `[String: String]` dictionaries (`values`, `secrets`) rather than one dictionary of a richer value type that carries its own secret/non-secret flag.
**Rationale**: this mirrors the split `AIProviderConfigKeys` and `DaemonAIChat.completeViaPlugin` already make between plain settings storage and Keychain-backed secret storage — a receiver can route each dictionary to its corresponding store directly, without inspecting per-field metadata to decide where a value belongs.
**Approved**: pending

**Decision**: every stored property of `AIProviderConfigSync` and `ResolvedProviderConfig` is declared `var`, not `let` — unlike the sibling `AIChatContext.swift` types, whose stored properties are all immutable `let`s.
**Rationale**: not explained in source; recorded here as an observed divergence from the sibling immutability convention rather than corrected, since neither `Sendable` nor `Equatable` requires immutability and the source gives no indication of an in-place-mutation call site that would justify it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | Privacy and Data |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | failed | Security |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |

`separation-of-concerns` passes because `AIProviderConfigSync.swift` performs no storage, no transport, and no business logic of its own; it is only the data shape shared between an app-side sender and a daemon-side receiver, neither of which lives in this file. `idempotent-operations` passes because encoding, decoding, and equality are all deterministic computations of a value's stored properties, with no shared state that could make repeated calls diverge (see `codable-field-names`, `equatable-structural`). `data-minimization` is `partial`: `ResolvedProviderConfig` carries a configuration's *entire* resolved value and secret bag in one undifferentiated pair of dictionaries, with no narrower, credential-free view for a caller that only needs identity or model, and no redaction on the type's default description, which prints `secrets` verbatim if ever logged or printed (see `Disclosure safeguard` in Privacy). `input-sanitization` fails because neither `configs`' `id` uniqueness nor `selectedConfigId`'s reference into `configs` is validated at construction or decode time (see `configs-id-uniqueness-unenforced`). `secure-storage` is `partial`: the `values`/`secrets` split gives a future receiver a clean signal for which fields need a secure store, but nothing in this file enforces that a receiver actually routes `secrets` there — that enforcement, like the receiver itself, does not yet exist in this repository (see `sync-application-unimplemented`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited NEEDS REVIEW markers against the marker rules; kept markers are one-line named bullets. |
