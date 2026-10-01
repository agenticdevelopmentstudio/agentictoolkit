---
id: 0f65ea61-3b0f-4a9b-842e-912555b7af62
title: Provider Configuration Keys
domain: agentictoolkit://cookbook/ai/providers/provider-config-keys
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Deterministic per-configuration storage-key formatters and shared settings-key
  constants the app and daemon both use to address a provider configuration's fields,
  model, and secret-credential ledgers.
platforms:
- swift
- macos
tags:
- ai-plugin
- storage-keys
- configuration
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

# Provider Configuration Keys

## Overview

The provider-configuration-keys component is a stateless namespace — never
instantiated — that is, per its own documented contract, "the single source
of truth for the per-configuration storage-key namespace" shared by the
app's provider-configuration store and the daemon's registry (reached
through the daemon provider resolver and the daemon's chat-completion
path). Four operations (field key, model key, secret-fields key, fields
key) format an identifier-scoped key string for one provider
configuration's field values, selected model, and secret-ledger
bookkeeping; four fixed constants (selected-configuration-id key,
configurations key, enabled key, legacy-cleaned key) name registry-wide
settings that are not scoped to any one configuration. Because both the app
and the daemon compute keys through this one component rather than
duplicating the format, a configuration identifier maps to the same key
strings on both sides and the two layouts cannot drift. It is a **logic**
component with no visual surface: every operation is a deterministic,
side-effect-free computation (or a fixed literal), it performs no I/O, and
it never fails.

## Behavioral Requirements

- **field-key-format**: The field-key operation MUST return the string
  `aiplugin.config.<id>.field.<field>`, where `<id>` is the configuration
  identifier's canonical uppercase, hyphenated string form and `<field>` is
  the given field name, both interpolated verbatim and unescaped.
- **model-key-format**: The model-key operation MUST return the string
  `aiplugin.config.<id>.model`.
- **secret-fields-key-format**: The secret-fields-key operation MUST
  return the string `aiplugin.config.<id>.secretfields`.
- **fields-key-format**: The fields-key operation MUST return the string
  `aiplugin.config.<id>.fields`.
- **registry-keys-fixed**: The selected-configuration-id key, configurations
  key, enabled key, and legacy-cleaned key MUST each equal one fixed
  literal string — `"ai_selected_config_id"`, `"ai_configurations"`,
  `"ai_summaries_enabled"`, and `"ai_legacy_cleaned"` respectively — the
  same for every configuration and every call, never parameterized by a
  configuration identifier.
- **key-namespace-isolation**: The field-key, model-key, secret-fields-key,
  and fields-key operations MUST embed the configuration identifier as a
  distinct path segment (`aiplugin.config.<id>.…`), so calling any one of
  them with two different configuration identifiers and the same remaining
  arguments MUST produce two different key strings.
- **fields-ledger-format**: the value a caller stores under the key the
  fields-key operation returns MUST be a newline (`\n`)-separated list of
  the configuration's currently-stored non-secret field keys — the shape
  this component's own documented contract declares ("Newline-joined …
  value keys stored for the configuration"), and the shape the daemon's
  chat-completion path actually parses by splitting on `\n` after its own
  test double seeds it with the field names joined by `\n`.
- **secret-fields-ledger-format**: the value a caller stores under the key
  the secret-fields-key operation returns MUST be a newline (`\n`)-separated
  list of the descriptor field keys whose secrets are currently stored for
  that configuration — the shape this component's own documented contract
  declares ("Newline-joined descriptor field keys whose *secrets* are
  currently stored for the configuration").
- **pure-computation**: every operation MUST be a deterministic function of
  its arguments alone: calling it any number of times with the same
  arguments MUST return the same string every time.
- **no-persistence**: this component MUST NOT read from or write to a
  settings store, a secure credential store, or any file itself; it holds
  no stored state and calls no persistence operation of its own — it only
  formats and returns key strings for callers to use against their own
  store.
- **no-side-effects**: calling any operation MUST NOT perform network
  access, file I/O, subprocess execution, or notification posting; the
  source contains no such call.
- **no-error-domain**: no operation MUST fail, and none MUST signal
  failure through an optional or empty result; every operation always
  succeeds structurally regardless of its input, because none of them
  validates its argument in a way that could reject it.
- **no-instantiation**: this component MUST NOT be instantiated; it is a
  namespace of operations with no case or instance, so every member MUST
  be accessed as a type-level member.
- **concurrency-isolation**: this component MUST be callable synchronously,
  with no suspension and no synchronization, from any concurrency domain;
  it declares no confinement to a single execution context and holds no
  shared mutable state a concurrent caller could race on.
- **single-source-of-truth-usage**: a caller that needs one of these
  storage keys SHOULD obtain it from this component rather than
  duplicating the literal string, so the app and daemon layouts cannot
  drift, per this component's own documented contract; any deviation MUST
  be documented — see Design Decisions for the one known deviation (a
  separate settings-configuration component's independent
  `"ai_summaries_enabled"` literal).
- **field-character-permissiveness**: a caller MAY pass a field name
  containing any character other than `\n` (including `.`, whitespace, or
  an empty string) to the field-key operation; this component places no
  other restriction on the character set, so a plugin author choosing a
  field-key spelling MAY use any identifier that avoids embedding a
  newline (see field-name-newline-safety, below).
- **field-name-newline-safety**: NEEDS REVIEW: Not implemented in source.
  Neither the field-key operation nor the per-field names recorded in the
  fields-key/secret-fields-key ledgers are validated to exclude the `\n`
  character, yet those ledgers' documented and observed shape is a
  newline-joined list of exactly those field names (see
  fields-ledger-format); a field key containing `\n` would split into two
  entries when the daemon's chat-completion path parses the ledger by
  splitting on `\n`, silently corrupting the field lookup for that
  configuration. What is missing: a defined restriction on a field name's
  character set (or an escaping scheme) for the ledger-based keys.
  Evidence that would settle it: the character constraints a plugin's
  field-descriptor key is meant to honor (not defined in the given
  sources), or a validating constructor added to this component.
- **secret-fields-key-consumer**: NEEDS REVIEW: Not implemented in source.
  The secret-fields-key operation's documented contract declares it exists
  to "clear exactly those entries when the configuration is removed," but
  no call site anywhere in the given sources writes or reads the key it
  returns; the app-side configuration store clears a removed
  configuration's secrets by iterating the caller-supplied field-descriptor
  list directly, not via this ledger. What is missing: confirmation of who
  populates and consumes this ledger, and when. Evidence that would settle
  it: the daemon-side removal implementation the documented contract
  attributes this key to ("(Daemon-side.)"), which is not present in this
  repository, or confirmation that the ledger is currently dead code.

## Appearance

Not applicable — this is a storage-key namespace, not a visual component.

## States

Not applicable — this is a storage-key namespace, not a visual component. It has no lifecycle of its own: every call is a one-shot, stateless computation (see `pure-computation`).

## Accessibility

Not applicable — this is a storage-key namespace, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-config-keys-001 | field-key-format | Configuration identifier `11111111-2222-3333-4444-555555555555`, field name `"apiKey"`; call the field-key operation | `"aiplugin.config.11111111-2222-3333-4444-555555555555.field.apiKey"` |
| ai-provider-config-keys-002 | model-key-format | Same configuration identifier as above; call the model-key operation | `"aiplugin.config.11111111-2222-3333-4444-555555555555.model"` |
| ai-provider-config-keys-003 | secret-fields-key-format | Same configuration identifier; call the secret-fields-key operation | `"aiplugin.config.11111111-2222-3333-4444-555555555555.secretfields"` |
| ai-provider-config-keys-004 | fields-key-format | Same configuration identifier; call the fields-key operation | `"aiplugin.config.11111111-2222-3333-4444-555555555555.fields"` |
| ai-provider-config-keys-005 | registry-keys-fixed | Read the selected-configuration-id key, configurations key, enabled key, and legacy-cleaned key | `"ai_selected_config_id"`, `"ai_configurations"`, `"ai_summaries_enabled"`, `"ai_legacy_cleaned"` respectively |
| ai-provider-config-keys-006 | key-namespace-isolation | Call the field-key operation with two different configuration identifiers and the same field name | Two distinct strings, since two distinct configuration identifiers never share the same canonical string form |
| ai-provider-config-keys-007 | fields-ledger-format | A test double seeds the fields-key ledger with a set of field names joined by `\n`, then the daemon's chat-completion path reads it back by splitting on `\n` | The recovered field-name set equals the original set exactly |
| ai-provider-config-keys-008 | secret-fields-key-consumer (open question) | Search the given sources for every reference to the secret-fields-key operation | Only its declaration and a format-only check appear; no production writer or reader exists |
| ai-provider-config-keys-009 | pure-computation, no-error-domain | Call the field-key operation twice in immediate succession with the same arguments | Both calls return the identical string; no error is raised and no state changes between calls |
| ai-provider-config-keys-010 | concurrency-isolation | Call the model-key operation from several concurrent execution contexts with no suspension | Every call observes the same result, with no concurrency-safety diagnostic, because the component holds no stored state |
| ai-provider-config-keys-011 | no-instantiation | Attempt to construct an instance of this component | Fails: the component is a namespace with no instance to construct |
| ai-provider-config-keys-012 | field-name-newline-safety (open question) | Call the field-key operation with a field name containing `\n`, whose returned key's value is later folded into a fields-key ledger and parsed by splitting on `\n` | The ledger parses as two entries instead of the intended single field key, corrupting the field lookup — demonstrates the unresolved gap; no test in the given suite exercises this because the source implements no guard against it |
| ai-provider-config-keys-013 | single-source-of-truth-usage (documented deviation) | Search the codebase for the literal `"ai_summaries_enabled"` outside this component | A separate settings-configuration component duplicates the literal independently rather than referencing this component's enabled key — the one known deviation from this SHOULD, documented in Design Decisions |

## Edge Cases

- **Empty field name**: the field-key operation MUST NOT reject an empty
  field name; it returns `"aiplugin.config.<id>.field."` with a trailing
  separator and no error, because this component performs no content check
  on the field name.
- **Whitespace-only or `.`-containing field name**: the field-key
  operation MUST NOT reject or alter such input; the string is interpolated
  verbatim (see `field-character-permissiveness`).
- **Field name containing `\n`**: See the open question in
  `field-name-newline-safety`. The key itself is still produced without
  error, but a caller that also maintains the fields-key/secret-fields-key
  ledger for that configuration will corrupt the ledger's newline-delimited
  parsing.
- **Two different configuration identifiers, same field name**: MUST
  produce two different keys for every one of the field-key, model-key,
  secret-fields-key, and fields-key operations (see
  `key-namespace-isolation`); two distinct configuration identifiers never
  share the same canonical string form, so no collision is possible.
- **Repeated calls with identical arguments**: MUST return the identical
  string every time (see `pure-computation`); there is no cache to
  invalidate and no counter or clock involved.
- **Concurrent calls**: applicable and safe by construction — this
  component holds no stored or shared mutable state, so calls from the
  app's main execution context and the daemon's own concurrency domain MUST
  NOT require any lock, queue hop, or suspension (see
  `concurrency-isolation`).
- **Boundary values on the configuration identifier**: none apply beyond
  what the identifier type itself enforces; every valid identifier value
  (including a randomly generated one and a fixed literal like the test
  fixture's) produces a well-formed 36-character canonical string, so there
  is no minimum/maximum or malformed-identifier case to handle — the type
  system rules it out before this code runs.
- **Error states from a dependency**: Not applicable — this component has
  no dependency (no network, database, or file-system call) that could
  fail; it never touches a store, only names one.
- **Offline or disconnected state**: Not applicable — this component
  performs no network access of its own; whether the daemon or app can
  currently be reached is a concern of whatever settings-reader/secret-store
  call site uses the returned key, not of this component.
- **Cancellation and timeouts**: Not applicable — every operation is
  synchronous, non-suspending, and infallible; there is nothing to cancel
  and no operation that can time out.
- **Missing file or unreachable server**: Not applicable — this component
  opens no file and makes no server call; a missing settings row or an
  unreadable credential-store entry at the key this component returns is
  the caller's failure mode, not this component's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Configuration identifier | identifier | none (required) | The configuration identifier passed to the field-key, model-key, secret-fields-key, and fields-key operations; embedded verbatim in its canonical string form in every per-configuration key. |
| Field name | text | none (required) | The descriptor field's key (e.g. `"apiKey"`, `"baseURL"`), passed to the field-key operation; caller-supplied and unvalidated (see Edge Cases). |
| Selected-configuration-id key | text (constant) | `"ai_selected_config_id"` | Fixed settings key holding the id of the configuration used for AI summaries; an empty stored value means the daemon's zero-config path. |
| Configurations key | text (constant) | `"ai_configurations"` | Fixed settings key for the daemon's registry index: a JSON-encoded list of provider configurations. |
| Enabled key | text (constant) | `"ai_summaries_enabled"` | Fixed settings key for the AI-summaries-enabled flag. |
| Legacy-cleaned key | text (constant) | `"ai_legacy_cleaned"` | Fixed one-time-guard key marking that legacy plugin-keyed AI settings have already been cleaned up. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable
destination — it is a key-naming namespace with no navigation surface of
its own.

## Localization

Not applicable: the source contains no user-facing string literal; every
string it produces or names is an internal storage-key identifier (e.g.
`"aiplugin.config.<id>.field.<key>"`, `"ai_summaries_enabled"`), never text
displayed to a user.

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no
conditional feature-gating logic; every member is always available.

## Analytics

Not applicable: the source contains no analytics or event-emission call of
any kind.

## Privacy

- **Data collected**: this component collects no data itself; it computes
  the *names* (storage keys) under which a configuration's field values —
  including a provider credential when a descriptor field is marked secret
  (e.g. an API key) — are looked up. The credential value itself never
  passes through this component.
- **Storage**: this component performs no storage of its own. The key it
  returns for a secret field is used as-is by the caller's secure backing
  store on the app side, or by the secret-storing component on the daemon
  side. Non-secret fields and the four registry-level constants are stored
  by whatever settings store the caller passes as its settings-reader.
- **Transmission**: this component performs no network transmission.
  Whether a secret crosses the app-daemon boundary at all is determined by
  the provider-configuration sync component, a different component; this
  component only supplies the address both sides use to store the resolved
  value locally.
- **Retention**: this component defines no retention policy or expiry; a
  key's value persists for as long as the caller's backing store keeps it.
  Removal is the caller's responsibility — the app-side configuration store
  resets non-secret fields and the model to an empty string (clearing the
  effective secure-store entry when the field is marked secure); whether
  the daemon-side secret-fields-key/fields-key ledgers drive an equivalent
  removal is the open `secret-fields-key-consumer` question above.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIProviderConfigKeys.swift` imports only `Foundation`, with no SwiftUI dependency; a SwiftUI-based settings screen calls the same static functions unchanged.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It declares `AIProviderConfigKeys` as a case-less `public enum` — the Swift idiom for a namespace — with four static functions, `fieldKey(config:field:)`, `modelKey(config:)`, `secretFieldsKey(config:)`, and `fieldsKey(config:)`, each taking a `UUID` and interpolating `id.uuidString` (Foundation's canonical uppercase, hyphenated 36-character form) into the returned `String`, plus four `static let` constants (`selectedConfigIdKey`, `configurationsKey`, `enabledKey`, `legacyCleanedKey`). It declares no `actor`, `@MainActor`, or `Sendable` annotation, so every static member is `nonisolated` by default. It is consumed by the AppKit-facing, `@MainActor`-isolated `AIProviderConfigStore.swift` (`macOS/Features/AIPlugins/`) and by the daemon-side `DaemonProviderResolver`/`DaemonAIChat`, both plain Foundation with no AppKit import of their own. The one documented deviation from `single-source-of-truth-usage` — `AIModelChatConfig.swift`'s independent `UserSettings.aiSummariesEnabled = UserSetting<Bool>("ai_summaries_enabled", default: false)` literal — is a Swift-specific `UserSetting` property wrapper duplicating `enabledKey`'s string by hand.
- **Compose**: model as a Kotlin top-level `object AIProviderConfigKeys` — the direct analog of a case-less Swift `enum` used as a namespace — with functions taking a `java.util.UUID`. Note that `UUID.toString()` on the JVM returns *lowercase* hex, unlike Foundation's uppercase `uuidString`; an Android daemon and an Apple app sharing this key format over the same settings store MUST agree on one case (or do a case-insensitive lookup), or otherwise-identical configuration ids will produce non-matching keys.
- **React/Web**: model as a module of plain exported functions (e.g. `fieldKey(id: string, field: string): string`) over a UUID already serialized as a string, since JavaScript has no native `UUID` type. The same cross-platform case-sensitivity note applies: `crypto.randomUUID()` produces a lowercase string, so a web client sharing this key format with the Apple app/daemon needs the same case-normalization decision noted for Compose.
- **WinUI 3**: model `AIProviderConfigKeys` as a `static class` with `static string` methods and `const string` fields, e.g. `public static string FieldKey(Guid configId, string field) => $"aiplugin.config.{configId}.field.{field}";`, `public static string ModelKey(Guid configId) => $"aiplugin.config.{configId}.model";`, `public static string SecretFieldsKey(Guid configId) => $"aiplugin.config.{configId}.secretfields";`, `public static string FieldsKey(Guid configId) => $"aiplugin.config.{configId}.fields";`, and `public const string SelectedConfigIdKey = "ai_selected_config_id";` (plus `ConfigurationsKey`, `EnabledKey`, `LegacyCleanedKey` as further `const string` fields). Critically, `Guid.ToString()`'s default `"D"` format is *lowercase*, unlike Foundation's uppercase `UUID.uuidString` — call `configId.ToString("D").ToUpperInvariant()` (or normalize consistently on read) so a WinUI 3 client and an Apple app/daemon sharing one settings store produce byte-identical keys for the same configuration id. Persist the ledger values (`FieldsKey`/`SecretFieldsKey`) as a `\n`-joined `string` (e.g. `string.Join("\n", fieldNames)`) to match the Swift side's `split(separator: "\n")` parsing exactly, including the same unresolved risk if a field name itself contains `\n` (see `field-name-newline-safety`).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift` |

## Design Decisions

**Decision**: The same field-key string addresses both a plain (non-secret) settings entry and a secure-store-backed secret entry for the same field, distinguished only by the caller's own routing (whether the field is marked secret, which store the caller chooses), never by any structural difference in the key itself.
**Rationale**: per the component's own documented contract, the goal is that "a configuration id maps to the same key strings on both sides" of the app/daemon boundary; encoding a "secure" marker into the key string would create two parallel namespaces for what is otherwise one field, duplicating the distinction a field descriptor's secret flag already drives at the call site.
**Approved**: pending

**Decision**: The enabled key and legacy-cleaned key are declared as fixed constants but have no call site anywhere in the given sources that reads or writes them by name; the enabled key's literal value (`"ai_summaries_enabled"`) is independently duplicated as a hardcoded string in a separate settings-configuration component, rather than referencing this component's enabled key.
**Rationale**: this is recorded here as an observed fact rather than corrected, because routing that other component through this component's enabled key would change a file outside this component's own contract; nothing today ties the two literals together, so a future rename of either would silently break the pairing with no compiler error. (Apple platform implementation.)
**Approved**: pending

**Decision**: The secret-fields-key operation and its newline-joined ledger shape are documented on this component but never populated or consulted anywhere in this repository.
**Rationale**: the documented contract attributes the ledger to daemon-side removal logic ("(Daemon-side.)"), which may live outside this repository; rather than assume that consumer exists and behaves correctly, or invent one, this is flagged as the open `secret-fields-key-consumer` question in Behavioral Requirements. (Apple platform implementation.)
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/providers/. |
