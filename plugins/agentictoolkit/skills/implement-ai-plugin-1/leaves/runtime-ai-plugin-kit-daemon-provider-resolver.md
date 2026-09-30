<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-provider-resolver · source: ai-plugin-runtime-ai-plugin-kit-daemon-provider-resolver.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-provider-resolver#<slug>`):

- `provider-settings-reader-shape` MUST
- `provider-settings-reader-absent-key` MUST
- `settings-store-opacity` MUST
- `configurations-empty-when-absent` MUST
- `configurations-empty-when-blank` MUST
- `configurations-empty-when-malformed` MUST
- `configurations-array-poisoning` MUST
- `configurations-decode-success` MUST
- `selected-configuration-absent` MUST
- `selected-configuration-malformed-id` MUST
- `selected-configuration-lookup` MUST
- `selected-configuration-duplicate-id-order` MUST
- `selected-configuration-fallback-signal` SHOULD
- `model-empty-when-unset` MUST
- `model-verbatim-value` MUST
- `model-lookup-independent-of-registry` MUST
- `stateless-namespace` MUST
- `no-instantiation` MUST
- `no-persistence` MUST
- `no-side-effects` MUST
- `any-thread-invocation` MUST
- `no-caching` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `settings` | `ProviderSettingsReader` (`@Sendable (String) -> String?`) | none (required) | Injected by the caller on every call; the sole source of registry, selection, and model data. |
| `id` | `UUID` | none (required for `model(config:_:)`) | The configuration identifier whose stored model is being looked up. |
| `AIProviderConfigKeys.configurationsKey` | `String` (constant, `"ai_configurations"`) | n/a | Settings key `configurations(_:)` reads for the JSON-encoded `[AIProviderConfiguration]` registry. |
| `AIProviderConfigKeys.selectedConfigIdKey` | `String` (constant, `"ai_selected_config_id"`) | n/a | Settings key `selectedConfiguration(_:)` reads for the selected configuration's UUID string. |
| `AIProviderConfigKeys.modelKey(config:)` | `String` (per-configuration, `"aiplugin.config.<id>.model"`) | n/a | Settings key `model(config:_:)` reads for that configuration's stored model. |

## Privacy

- **Data collected**: `DaemonProviderResolver` collects no data itself; it reads configuration identity (`id`, `name`, `pluginIdentifier`, `templateId`) and a stored model string from whatever the caller's `ProviderSettingsReader` returns. No credential or secret value ever passes through this type — secret values are addressed by `AIProviderConfigKeys.fieldKey`/`secretFieldsKey` and moved by `AIProviderConfigSync`/`SecretStoring`, neither of which `DaemonProviderResolver` calls.
- **Storage**: `DaemonProviderResolver` performs no storage of its own; it only reads, through the caller-supplied closure, whatever backing store the caller wraps (per the doc comment, the daemon's settings table).
- **Transmission**: this file performs no network transmission of its own; it only reads local, already-synced values.
- **Retention**: this file defines no retention policy; a value's lifetime is entirely the responsibility of the store behind the caller's `settings` closure.

