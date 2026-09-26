---
id: 0f65ea61-3b0f-4a9b-842e-912555b7af62
title: AI Provider Config Keys
domain: agentictoolkit://cookbook/ai-plugin-kit/ai-provider-config-keys
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Deterministic per-configuration storage-key formatters and shared settings-key
  constants the app and daemon both use to address a provider configuration's fields,
  model, and Keychain ledgers.
platforms:
- swift
- macos
tags:
- ai-plugin
- storage-keys
- configuration
- keychain
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/AIProviderConfigKeysTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/AIProviderConfigStore.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/DaemonAIChatTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/DaemonAIChatGuardTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/AIModelChatConfig.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a storage-key namespace, not a visual component.

## States

Not applicable — this is a storage-key namespace, not a visual component. It has no lifecycle of its own: every call is a one-shot, stateless computation (see `pure-computation`).

## Accessibility

Not applicable — this is a storage-key namespace, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-config-keys-001 | field-key-format | `fieldKey(config: UUID("11111111-2222-3333-4444-555555555555")!, field: "apiKey")` | `"aiplugin.config.11111111-2222-3333-4444-555555555555.field.apiKey"` — `AIProviderConfigKeysTests.testFieldKeyFormat` |
| ai-provider-config-keys-002 | model-key-format | `modelKey(config: id)` (same `id` as above) | `"aiplugin.config.11111111-2222-3333-4444-555555555555.model"` — `AIProviderConfigKeysTests.testModelAndLedgerKeys` |
| ai-provider-config-keys-003 | secret-fields-key-format | `secretFieldsKey(config: id)` | `"aiplugin.config.11111111-2222-3333-4444-555555555555.secretfields"` — `AIProviderConfigKeysTests.testModelAndLedgerKeys` |
| ai-provider-config-keys-004 | fields-key-format | `fieldsKey(config: id)` | `"aiplugin.config.11111111-2222-3333-4444-555555555555.fields"` — `AIProviderConfigKeysTests.testModelAndLedgerKeys` |
| ai-provider-config-keys-005 | registry-keys-fixed | Read `selectedConfigIdKey`, `configurationsKey`, `enabledKey`, `legacyCleanedKey` | `"ai_selected_config_id"`, `"ai_configurations"`, `"ai_summaries_enabled"`, `"ai_legacy_cleaned"` respectively — `AIProviderConfigKeys.swift` |
| ai-provider-config-keys-006 | key-namespace-isolation | `fieldKey(config: idA, field: "apiKey")` vs. `fieldKey(config: idB, field: "apiKey")` for `idA != idB` | Two distinct strings, since `idA.uuidString != idB.uuidString` |
| ai-provider-config-keys-007 | fields-ledger-format | `DaemonAIChatTests.makeSettings` seeds `fieldsKey(config: id)` with `values.keys.joined(separator: "\n")`, then `DaemonAIChat.completeViaPlugin` reads it back via `fieldsLedger.split(separator: "\n")` | The recovered field-name set equals the original `values.keys` set — `DaemonAIChatTests.swift` and `DaemonAIChat.swift` |
| ai-provider-config-keys-008 | secret-fields-key-consumer (open question) | Grep `packages/apple/AgenticToolkit` for `secretFieldsKey` | Only `AIProviderConfigKeys.swift`'s declaration and `AIProviderConfigKeysTests.testModelAndLedgerKeys`'s format check appear; no production writer or reader exists |
| ai-provider-config-keys-009 | pure-computation, no-error-domain | Call `fieldKey(config: id, field: "apiKey")` twice in immediate succession | Both calls return the identical string; no error is thrown and no state changes between calls |
| ai-provider-config-keys-010 | concurrency-isolation | Call `AIProviderConfigKeys.modelKey(config:)` from several concurrent `Task`s with no `await` | The code compiles with no actor-isolation error, and every task observes the same result, because the type is `nonisolated` and holds no stored state |
| ai-provider-config-keys-011 | no-instantiation | Attempt `let x = AIProviderConfigKeys()` | Fails to compile: a case-less `enum` has no initializer |
| ai-provider-config-keys-012 | field-name-newline-safety (open question) | `fieldKey(config: id, field: "a\nb")`, whose value is later folded into a `fieldsKey` ledger and parsed with `split(separator: "\n")` | The ledger parses as two entries (`"a"` and `"b"`) instead of the intended single field key `"a\nb"`, corrupting the field lookup — demonstrates the unresolved gap; no test in the given suite exercises this because the source implements no guard against it |
| ai-provider-config-keys-013 | single-source-of-truth-usage (documented deviation) | Grep the codebase for the literal `"ai_summaries_enabled"` outside `AIProviderConfigKeys.swift` | `AIModelChatConfig.swift`'s `UserSettings.aiSummariesEnabled = UserSetting<Bool>("ai_summaries_enabled", default: false)` duplicates the literal independently rather than referencing `AIProviderConfigKeys.enabledKey` — the one known deviation from this SHOULD, documented in Design Decisions |

## Edge Cases

- **Empty `field` string**: `fieldKey(config:field:)` MUST NOT reject `field: ""`; it returns `"aiplugin.config.<id>.field."` with a trailing separator and no error, because the source performs no content check on `field`.
- **Whitespace-only or `.`-containing `field`**: `fieldKey(config:field:)` MUST NOT reject or alter such input; the string is interpolated verbatim (see `field-character-permissiveness`).
- **`field` containing `\n`**: See the open question in `field-name-newline-safety`. The key itself is still produced without error, but a caller that also maintains the `fieldsKey`/`secretFieldsKey` ledger for that configuration will corrupt the ledger's newline-delimited parsing.
- **Two different configuration ids, same `field`**: MUST produce two different keys for every one of `fieldKey`, `modelKey`, `secretFieldsKey`, and `fieldsKey` (see `key-namespace-isolation`); `UUID.uuidString` never coincides for two distinct `UUID` values, so no collision is possible.
- **Repeated calls with identical arguments**: MUST return the identical string every time (see `pure-computation`); there is no cache to invalidate and no counter or clock involved.
- **Concurrent calls**: applicable and safe by construction — `AIProviderConfigKeys` holds no stored or shared mutable state, so calls from the app's main actor and the daemon's own concurrency domain MUST NOT require any lock, queue hop, or `await` (see `concurrency-isolation`).
- **Boundary values on `id`**: none apply beyond what `UUID` itself enforces; every `UUID` value (including `UUID()`'s randomly generated form and a fixed literal like the test fixture's `11111111-2222-3333-4444-555555555555`) produces a well-formed 36-character `uuidString`, so there is no minimum/maximum or malformed-`id` case to handle — the type system rules it out before this code runs.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) that could fail; it never touches a store, only names one.
- **Offline or disconnected state**: Not applicable — `AIProviderConfigKeys.swift` performs no network access of its own; whether the daemon or app can currently be reached is a concern of whatever `ProviderSettingsReader`/`SecretStoring`/Keychain call site uses the returned key, not of this file.
- **Cancellation and timeouts**: Not applicable — every member is a synchronous, non-async, non-throwing computation; there is nothing to cancel and no operation that can time out.
- **Missing file or unreachable server**: Not applicable — this file opens no file and makes no server call; a missing settings row or an unreadable Keychain entry at the key this file returns is the caller's failure mode, not this file's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | `UUID` | none (required) | The configuration identifier passed to `fieldKey`, `modelKey`, `secretFieldsKey`, and `fieldsKey`; embedded verbatim via `id.uuidString` in every per-configuration key. |
| `field` | `String` | none (required) | The descriptor field's key (e.g. `"apiKey"`, `"baseURL"`), passed to `fieldKey(config:field:)`; caller-supplied and unvalidated (see Edge Cases). |
| `selectedConfigIdKey` | `String` (constant) | `"ai_selected_config_id"` | Fixed settings key holding the id of the configuration used for AI summaries; an empty stored value means the daemon's zero-config Claude-CLI path. |
| `configurationsKey` | `String` (constant) | `"ai_configurations"` | Fixed settings key for the daemon's registry index: a JSON-encoded `[AIProviderConfiguration]`. |
| `enabledKey` | `String` (constant) | `"ai_summaries_enabled"` | Fixed settings key for the AI-summaries-enabled flag. |
| `legacyCleanedKey` | `String` (constant) | `"ai_legacy_cleaned"` | Fixed one-time-guard key marking that legacy plugin-keyed AI settings have already been cleaned up. |

## Deep Linking

Not applicable: `AIProviderConfigKeys.swift` defines no URL, route, or navigable destination — it is a key-naming namespace with no navigation surface of its own.

## Localization

Not applicable: the source contains no user-facing string literal; every string it produces or names is an internal storage-key identifier (e.g. `"aiplugin.config.<id>.field.<key>"`, `"ai_summaries_enabled"`), never text displayed to a user.

## Accessibility Options

Not applicable: `AIProviderConfigKeys.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `AIProviderConfigKeys` collects no data itself; it computes the *names* (storage keys) under which a configuration's field values — including a provider credential when a descriptor field's `isSecret` is `true` (e.g. an API key) — are looked up. The credential value itself never passes through this type.
- **Storage**: `AIProviderConfigKeys` performs no storage of its own. The key it returns for a secret field is used as-is by the caller's secure backing store — `UserSetting(isSecure: true)` on the app side (`AIProviderConfigStore.fieldSetting`) or `SecretStoring` on the daemon side (`DaemonAIChat.completeViaPlugin`). Non-secret fields and the four registry-level constants are stored by whatever settings store the caller passes as its `ProviderSettingsReader` / `UserDefaults`.
- **Transmission**: this file performs no network transmission. Whether a secret crosses the app-daemon boundary at all is determined by `AIProviderConfigSync`/`ResolvedProviderConfig.secrets`, a different type; `AIProviderConfigKeys` only supplies the address both sides use to store the resolved value locally.
- **Retention**: this file defines no retention policy or expiry; a key's value persists for as long as the caller's backing store keeps it. Removal is the caller's responsibility — `AIProviderConfigStore.clearStoredValues` resets non-secret fields and the model to `""` (clearing the effective Keychain entry when the field `isSecure`); whether the daemon-side `secretFieldsKey`/`fieldsKey` ledgers drive an equivalent removal is the open `secret-fields-key-consumer` question above.

## Logging

Not applicable: `AIProviderConfigKeys.swift` contains no `Logger`, `os_log`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIProviderConfigKeys.swift` imports only `Foundation`, with no SwiftUI dependency; a SwiftUI-based settings screen calls the same static functions unchanged.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It is consumed by the AppKit-facing, `@MainActor`-isolated `AIProviderConfigStore.swift` (`macOS/Features/AIPlugins/`) and by the daemon-side `DaemonProviderResolver`/`DaemonAIChat`, both plain Foundation with no AppKit import of their own.
- **Compose**: model as a Kotlin top-level `object AIProviderConfigKeys` — the direct analog of a case-less Swift `enum` used as a namespace — with functions taking a `java.util.UUID`. Note that `UUID.toString()` on the JVM returns *lowercase* hex, unlike Foundation's uppercase `uuidString`; an Android daemon and an Apple app sharing this key format over the same settings store MUST agree on one case (or do a case-insensitive lookup), or otherwise-identical configuration ids will produce non-matching keys.
- **React/Web**: model as a module of plain exported functions (e.g. `fieldKey(id: string, field: string): string`) over a UUID already serialized as a string, since JavaScript has no native `UUID` type. The same cross-platform case-sensitivity note applies: `crypto.randomUUID()` produces a lowercase string, so a web client sharing this key format with the Apple app/daemon needs the same case-normalization decision noted for Compose.
- **WinUI 3**: model `AIProviderConfigKeys` as a `static class` with `static string` methods and `const string` fields, e.g. `public static string FieldKey(Guid configId, string field) => $"aiplugin.config.{configId}.field.{field}";`, `public static string ModelKey(Guid configId) => $"aiplugin.config.{configId}.model";`, `public static string SecretFieldsKey(Guid configId) => $"aiplugin.config.{configId}.secretfields";`, `public static string FieldsKey(Guid configId) => $"aiplugin.config.{configId}.fields";`, and `public const string SelectedConfigIdKey = "ai_selected_config_id";` (plus `ConfigurationsKey`, `EnabledKey`, `LegacyCleanedKey` as further `const string` fields). Critically, `Guid.ToString()`'s default `"D"` format is *lowercase*, unlike Foundation's uppercase `UUID.uuidString` — call `configId.ToString("D").ToUpperInvariant()` (or normalize consistently on read) so a WinUI 3 client and an Apple app/daemon sharing one settings store produce byte-identical keys for the same configuration id. Persist the ledger values (`FieldsKey`/`SecretFieldsKey`) as a `\n`-joined `string` (e.g. `string.Join("\n", fieldNames)`) to match the Swift side's `split(separator: "\n")` parsing exactly, including the same unresolved risk if a field name itself contains `\n` (see `field-name-newline-safety`).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift` |

## Design Decisions

**Decision**: The same `fieldKey(config:field:)` string addresses both a plain (non-secret) settings entry and a Keychain-backed secret entry for the same field, distinguished only by the caller's own routing (`field.isSecret`, `UserSetting(isSecure:)`, `SecretStoring`), never by any structural difference in the key itself.
**Rationale**: per the file's own doc comment, the goal is that "a configuration id maps to the same key strings on both sides" of the app/daemon boundary; encoding a "secure" marker into the key string would create two parallel namespaces for what is otherwise one field, duplicating the distinction `AIPluginDescriptor.Field.isSecret` already drives at the call site (`AIProviderConfigStore.fieldSetting`, `DaemonAIChat.completeViaPlugin`).
**Approved**: pending

**Decision**: `enabledKey` and `legacyCleanedKey` are declared as fixed constants but have no call site anywhere in `packages/apple/AgenticToolkit` that reads or writes them by name; `enabledKey`'s literal value (`"ai_summaries_enabled"`) is independently duplicated as a hardcoded string in `AIModelChatConfig.swift`'s `UserSettings.aiSummariesEnabled`, rather than referencing `AIProviderConfigKeys.enabledKey`.
**Rationale**: this is recorded here as an observed fact rather than corrected, because routing `UserSettings.aiSummariesEnabled` through `AIProviderConfigKeys.enabledKey` would change `AIModelChatConfig.swift`, a file outside this component's own contract; nothing today ties the two literals together, so a future rename of either would silently break the pairing with no compiler error.
**Approved**: pending

**Decision**: `secretFieldsKey(config:)` and its newline-joined ledger shape are documented on the type but never populated or consulted anywhere in this repository.
**Rationale**: the doc comment attributes the ledger to daemon-side removal logic ("(Daemon-side.)"), which may live outside this repository; rather than assume that consumer exists and behaves correctly, or invent one, this is flagged as the open `secret-fields-key-consumer` question in Behavioral Requirements.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | failed | Security |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |

`separation-of-concerns` passes because the file's only responsibility is formatting and naming storage keys; it performs no storage, no secret handling, and no business logic of its own. `idempotent-operations` passes because every function is a deterministic, side-effect-free computation of its arguments (see `pure-computation`). `data-minimization` passes because the file collects, stores, or transmits no data itself (see Privacy). `input-sanitization` fails because `field` — and the field names recorded in the newline-joined ledgers — are accepted with no character restriction, so a field key containing `\n` corrupts the ledger format the type itself documents (see `field-name-newline-safety`). `secure-storage` is partial: the key format gives every field one address shared by the app and daemon, but nothing in this file enforces that a secret field is actually routed to a secure store — that enforcement lives entirely in each caller, so a future caller could store a secret field's value in a non-secure store under the exact same key with no safeguard from this type.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
