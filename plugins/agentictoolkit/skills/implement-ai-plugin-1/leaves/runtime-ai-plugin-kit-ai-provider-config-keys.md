<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys#<slug>`):

- `field-key-format` MUST
- `model-key-format` MUST
- `secret-fields-key-format` MUST
- `fields-key-format` MUST
- `registry-keys-fixed` MUST
- `key-namespace-isolation` MUST
- `fields-ledger-format` MUST
- `secret-fields-ledger-format` MUST
- `pure-computation` MUST
- `no-persistence` MUST
- `no-side-effects` MUST
- `no-error-domain` MUST
- `no-instantiation` MUST
- `concurrency-isolation` MUST
- `single-source-of-truth-usage` MUST
- `field-character-permissiveness` MAY

# AI Provider Config Keys

## Overview

`AIProviderConfigKeys` (`packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift`) is a case-less `public enum` — a static namespace, never instantiated — that is, per its own doc comment, "the single source of truth for the per-configuration storage-key namespace" shared by the macOS app's `AIProviderConfigStore` (UserDefaults / app-Keychain) and the daemon's registry (a settings table / daemon-Keychain, reached through `DaemonProviderResolver` and `DaemonAIChat`). Four static functions (`fieldKey`, `modelKey`, `secretFieldsKey`, `fieldsKey`) format a `UUID`-scoped key string for one `AIProviderConfiguration`'s field values, selected model, and Keychain-enumeration ledgers; four static constants (`selectedConfigIdKey`, `configurationsKey`, `enabledKey`, `legacyCleanedKey`) name registry-wide settings that are not scoped to any one configuration. Because both the app and the daemon compute keys through this one type rather than duplicating the format, a configuration id maps to the same key strings on both sides and the two layouts cannot drift. It is a **logic** component with no visual surface: every member is a deterministic, side-effect-free computation (or a fixed literal), it performs no I/O, and it never throws.

## Behavioral Requirements

- **field-key-format**: `fieldKey(config:field:)` MUST return the string `aiplugin.config.<id>.field.<field>`, where `<id>` is `id.uuidString` (Foundation's canonical uppercase, hyphenated 36-character form) and `<field>` is the given `field` argument, both interpolated verbatim and unescaped.
- **model-key-format**: `modelKey(config:)` MUST return the string `aiplugin.config.<id>.model`.
- **secret-fields-key-format**: `secretFieldsKey(config:)` MUST return the string `aiplugin.config.<id>.secretfields`.
- **fields-key-format**: `fieldsKey(config:)` MUST return the string `aiplugin.config.<id>.fields`.
- **registry-keys-fixed**: `selectedConfigIdKey`, `configurationsKey`, `enabledKey`, and `legacyCleanedKey` MUST each equal one fixed literal string — `"ai_selected_config_id"`, `"ai_configurations"`, `"ai_summaries_enabled"`, and `"ai_legacy_cleaned"` respectively — the same for every configuration and every call, never parameterized by a configuration id.
- **key-namespace-isolation**: `fieldKey`, `modelKey`, `secretFieldsKey`, and `fieldsKey` MUST embed `id.uuidString` as a distinct path segment (`aiplugin.config.<id>.…`), so calling any one of them with two different configuration ids and the same remaining arguments MUST produce two different key strings.
- **fields-ledger-format**: the value a caller stores under the key returned by `fieldsKey(config:)` MUST be a newline (`\n`)-separated list of the configuration's currently-stored non-secret field keys — the shape the type's own doc comment declares ("Newline-joined … value keys stored for `id`"), and the shape `DaemonAIChat.completeViaPlugin` actually parses via `fieldsLedger.split(separator: "\n")` after `DaemonAIChatTests.makeSettings` seeds it with `values.keys.joined(separator: "\n")`.
- **secret-fields-ledger-format**: the value a caller stores under the key returned by `secretFieldsKey(config:)` MUST be a newline (`\n`)-separated list of the descriptor field keys whose secrets are currently stored for that configuration — the shape the type's own doc comment declares ("Newline-joined descriptor field keys whose *secrets* are currently stored for `id`").
- **pure-computation**: every function in `AIProviderConfigKeys` MUST be a deterministic function of its arguments alone: calling it any number of times with the same arguments MUST return the same string every time.
- **no-persistence**: `AIProviderConfigKeys` MUST NOT read from or write to `UserDefaults`, the Keychain, a settings table, or any file itself; the source declares no stored property and calls no persistence API — it only formats and returns key strings for callers to use against their own store.
- **no-side-effects**: calling any member of `AIProviderConfigKeys` MUST NOT perform network access, file I/O, subprocess execution, or notification posting; the source contains no such call.
- **no-error-domain**: no function in `AIProviderConfigKeys` MUST throw, and none MUST return an optional to signal failure; every member always succeeds structurally regardless of its input, because the source performs no validation that could reject an argument.
- **no-instantiation**: `AIProviderConfigKeys` MUST NOT be instantiated; it is declared as a case-less `enum` — the Swift idiom for a namespace — so the compiler prevents constructing a value of the type, and every member MUST be accessed as a static/type member.
- **concurrency-isolation**: `AIProviderConfigKeys` MUST be callable synchronously, without `await` or any synchronization, from any thread, actor, or `Task`; the type declares no `actor`, `@MainActor`, or `Sendable` annotation and holds no stored property, so every static member is `nonisolated` by default and touches no shared mutable state a concurrent caller could race on.
- **single-source-of-truth-usage**: a caller that needs one of these storage keys SHOULD obtain it by calling `AIProviderConfigKeys` rather than duplicating the literal string, so the app and daemon layouts cannot drift, per the type's own doc comment; any deviation MUST be documented — see Design Decisions for the one known deviation (`AIModelChatConfig.swift`'s independent `"ai_summaries_enabled"` literal).
- **field-character-permissiveness**: a caller MAY pass a `field` value containing any character other than `\n` (including `.`, whitespace, or an empty string) to `fieldKey(config:field:)`; the type places no other restriction on the character set, so a plugin author choosing a field-key spelling MAY use any identifier that avoids embedding a newline (see `field-name-newline-safety`, below).
- **field-name-newline-safety**: NEEDS REVIEW: Not implemented in source. Neither `fieldKey(config:field:)` nor the per-field names recorded in the `fieldsKey`/`secretFieldsKey` ledgers are validated to exclude the `\n` character, yet those ledgers' documented and observed shape is a newline-joined list of exactly those field names (see `fields-ledger-format`); a field key containing `\n` would split into two entries when `DaemonAIChat.completeViaPlugin` parses the ledger with `fieldsLedger.split(separator: "\n")`, silently corrupting the field lookup for that configuration. What is missing: a defined restriction on `field`'s character set (or an escaping scheme) for the ledger-based keys. Evidence that would settle it: the character constraints `AIPluginDescriptor.Field.key` is meant to honor (not defined in the given sources), or a validating initializer added to `AIProviderConfigKeys`.
- **secret-fields-key-consumer**: NEEDS REVIEW: Not implemented in source. `secretFieldsKey(config:)`'s doc comment declares it exists to "clear exactly those entries when the configuration is removed," but no call site anywhere in `packages/apple/AgenticToolkit` writes or reads the key it returns; `AIProviderConfigStore.clearStoredValues` clears a removed configuration's secrets by iterating the caller-supplied `fields: [AIPluginDescriptor.Field]` list directly, not via this ledger. What is missing: confirmation of who populates and consumes this ledger, and when. Evidence that would settle it: the daemon-side removal implementation the doc comment attributes this key to ("(Daemon-side.)"), which is not present in this repository, or confirmation that the ledger is currently dead code.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | `UUID` | none (required) | The configuration identifier passed to `fieldKey`, `modelKey`, `secretFieldsKey`, and `fieldsKey`; embedded verbatim via `id.uuidString` in every per-configuration key. |
| `field` | `String` | none (required) | The descriptor field's key (e.g. `"apiKey"`, `"baseURL"`), passed to `fieldKey(config:field:)`; caller-supplied and unvalidated (see Edge Cases). |
| `selectedConfigIdKey` | `String` (constant) | `"ai_selected_config_id"` | Fixed settings key holding the id of the configuration used for AI summaries; an empty stored value means the daemon's zero-config Claude-CLI path. |
| `configurationsKey` | `String` (constant) | `"ai_configurations"` | Fixed settings key for the daemon's registry index: a JSON-encoded `[AIProviderConfiguration]`. |
| `enabledKey` | `String` (constant) | `"ai_summaries_enabled"` | Fixed settings key for the AI-summaries-enabled flag. |
| `legacyCleanedKey` | `String` (constant) | `"ai_legacy_cleaned"` | Fixed one-time-guard key marking that legacy plugin-keyed AI settings have already been cleaned up. |

## Privacy

- **Data collected**: `AIProviderConfigKeys` collects no data itself; it computes the *names* (storage keys) under which a configuration's field values — including a provider credential when a descriptor field's `isSecret` is `true` (e.g. an API key) — are looked up. The credential value itself never passes through this type.
- **Storage**: `AIProviderConfigKeys` performs no storage of its own. The key it returns for a secret field is used as-is by the caller's secure backing store — `UserSetting(isSecure: true)` on the app side (`AIProviderConfigStore.fieldSetting`) or `SecretStoring` on the daemon side (`DaemonAIChat.completeViaPlugin`). Non-secret fields and the four registry-level constants are stored by whatever settings store the caller passes as its `ProviderSettingsReader` / `UserDefaults`.
- **Transmission**: this file performs no network transmission. Whether a secret crosses the app-daemon boundary at all is determined by `AIProviderConfigSync`/`ResolvedProviderConfig.secrets`, a different type; `AIProviderConfigKeys` only supplies the address both sides use to store the resolved value locally.
- **Retention**: this file defines no retention policy or expiry; a key's value persists for as long as the caller's backing store keeps it. Removal is the caller's responsibility — `AIProviderConfigStore.clearStoredValues` resets non-secret fields and the model to `""` (clearing the effective Keychain entry when the field `isSecure`); whether the daemon-side `secretFieldsKey`/`fieldsKey` ledgers drive an equivalent removal is the open `secret-fields-key-consumer` question above.

