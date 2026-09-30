<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-sync · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-sync.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-sync#<slug>`):

- `enabled-flag` MUST
- `selected-config-id-optional` MUST
- `configs-collection` MUST
- `full-registry-snapshot` MUST
- `resolved-config-identity-fields` MUST
- `resolved-config-value-split` MUST
- `empty-secret-clears-credential` MUST
- `codable-field-names` MUST
- `selected-config-id-omits-key-when-nil` MUST
- `selected-config-id-decodes-missing-as-nil` MUST
- `equatable-structural` MUST
- `sendable-conformance` MUST
- `concurrency-isolation` MUST
- `mutable-stored-properties` MUST
- `memberwise-initializers` MUST
- `no-persistence` MUST
- `no-side-effects` MUST
- `no-error-domain` MUST

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

