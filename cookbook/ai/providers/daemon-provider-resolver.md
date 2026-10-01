---
id: ef2a5ca9-04a4-46ab-8fef-3fdc6db2041d
title: Daemon Provider Resolver
domain: agentictoolkit://cookbook/ai/providers/daemon-provider-resolver
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/ai/providers/provider-config-keys
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

The daemon provider resolver is a stateless namespace — three operations
and no visual surface — that gives a headless host (the daemon) read-only
access to the AI-provider-configuration registry the main app pushes over
the provider-configuration sync component. Per its own documented contract
it is "the daemon-side registry read API — the mirror of the app's provider
resolver," reading "the config-identifier-keyed layout a headless host
receives via the provider-configuration sync so it can resolve a
configuration by id without the app." Hosts hand it a settings-reader
function over whatever backs the synced values (per the documented
contract, "a settings table"), so the resolver and its caller (the
daemon's chat-completion path) never see the settings store itself. Its
three operations answer: which configurations does the host currently
mirror (configurations), which one is selected for one-shot completions
(selected configuration), and what model is stored for a given
configuration (model lookup). It performs no writes, no network access, and
no logging of its own; every result is a pure function of what the supplied
function returns at the moment of the call.

## Behavioral Requirements

- **provider-settings-reader-shape**: The settings-reader function type
  MUST be safe to call from any concurrency domain and MUST have the shape:
  given a key (text), return an optional text value.
- **provider-settings-reader-absent-key**: A settings-reader function MUST
  return none when the given key is absent from whatever store the
  function wraps, per the type's own documented contract ("Returns nil
  when a key is absent").
- **settings-store-opacity**: The resolver MUST NOT access a settings
  store directly; every operation MUST obtain data only by invoking the
  settings function the caller supplies, per the documented contract ("the
  resolver and its caller never see the store itself").
- **configurations-empty-when-absent**: The configurations lookup MUST
  return an empty list when the settings function returns none for the
  configurations key.
- **configurations-empty-when-blank**: The configurations lookup MUST
  return an empty list when the settings function returns an empty string
  for the configurations key.
- **configurations-empty-when-malformed**: The configurations lookup MUST
  return an empty list, without raising an error, when the stored value at
  the configurations key is present and non-empty but is not valid JSON or
  does not decode as a list of provider configurations.
- **configurations-array-poisoning**: The configurations lookup MUST
  discard the entire decoded list — not just the offending element — when
  even one element of an otherwise well-formed JSON array fails to decode
  as a provider configuration; the decoder's array decoding fails
  atomically, and the failure-swallowing path turns that single-element
  failure into the same empty-list result as a fully malformed document.
- **configurations-decode-success**: The configurations lookup MUST decode
  the stored JSON string at the configurations key into a list of provider
  configurations and MUST return it in the same element order when
  decoding succeeds.
- **decode-failure-diagnostics**: NEEDS REVIEW: Not implemented in source.
  When the settings function returns a non-empty string that fails to
  decode as a list of provider configurations, the configurations lookup
  swallows the decode error and returns an empty list with no log call,
  error return, or other diagnostic signal — indistinguishable from "zero
  configurations registered." What is missing: whether a corrupt-but-present
  registry is meant to be silently treated as empty (as a genuinely absent
  registry is), or whether daemon operators need a signal that the app's
  provider-configuration sync produced, or synced to, an undecodable value.
  Evidence that would settle it: a daemon-side logging or telemetry call
  this repository does not show, or confirmation that a decode failure here
  is tracked elsewhere.
- **selected-configuration-absent**: The selected-configuration lookup MUST
  return none when the settings function returns none or an empty string
  for the selected-configuration-id key.
- **selected-configuration-malformed-id**: The selected-configuration
  lookup MUST return none when the stored value at the
  selected-configuration-id key is not parseable as a configuration
  identifier.
- **selected-configuration-lookup**: The selected-configuration lookup
  MUST return the first element of the configurations list whose
  identifier equals the parsed identifier, and MUST return none when no
  element matches.
- **selected-configuration-duplicate-id-order**: When more than one
  element of the decoded registry shares the same identifier, the
  selected-configuration lookup MUST return the first such element in list
  order; the resolver enforces no uniqueness invariant of its own over the
  registry.
- **selected-configuration-fallback-signal**: A caller SHOULD treat a none
  result from the selected-configuration lookup as "no configuration
  selected — use the zero-config path," not as an error condition,
  matching how the daemon's chat-completion operation falls through to its
  command-line path when the selected-configuration lookup returns none.
- **model-empty-when-unset**: The model lookup MUST return an empty string
  when the settings function returns none for that configuration's model
  key.
- **model-verbatim-value**: The model lookup MUST return the exact string
  stored at that configuration's model key when present, with no trimming,
  case-folding, or validation applied.
- **model-lookup-independent-of-registry**: The model lookup MUST look up
  the stored model by the given identifier alone; it MUST NOT check
  whether that identifier is present in the configurations list or matches
  the currently selected configuration.
- **stateless-namespace**: Every operation in the resolver MUST be a pure
  function of its arguments and of what the supplied settings function
  returns at the moment of the call; the resolver MUST hold no stored
  property of its own.
- **no-instantiation**: The resolver MUST NOT be instantiated; it is a
  namespace of operations with no case or instance, so every member MUST
  be accessed as a type-level member.
- **no-persistence**: The resolver MUST NOT write to the settings store, a
  file, or any other persistent medium; the source contains no such call.
- **no-side-effects**: The resolver MUST NOT perform network access,
  subprocess execution, or notification posting; the source contains no
  such call.
- **any-thread-invocation**: The resolver's operations MUST be callable
  from any concurrency domain with no suspension and no synchronization;
  the type declares no confinement to a single execution context and holds
  no shared mutable state.
- **no-caching**: The resolver MUST NOT cache a prior call's result; every
  call MUST re-invoke the settings function and, where applicable, re-run
  the decoder, so a change to the underlying store between two calls MUST
  be visible on the next call.

## Appearance

Not applicable — this is a daemon-side registry read API, not a visual component.

## States

Not applicable — this is a daemon-side registry read API, not a visual component. It has no lifecycle of its own: every call is a one-shot, stateless read (see `stateless-namespace`).

## Accessibility

Not applicable — this is a daemon-side registry read API, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| daemon-provider-resolver-001 | selected-configuration-lookup, configurations-decode-success | A settings function representing a registry holding one configuration whose identifier and plugin identifier are known values, with that identifier set as selected; call the selected-configuration lookup | Returns a non-none configuration whose identifier and plugin identifier match the known values |
| daemon-provider-resolver-002 | provider-settings-reader-absent-key, configurations-empty-when-absent, selected-configuration-absent | A settings function that returns none for every key; call the selected-configuration lookup and the configurations lookup | selected-configuration lookup returns none; configurations lookup returns an empty list |
| daemon-provider-resolver-003 | configurations-empty-when-malformed | A settings function that returns "not json" for the configurations key and none for every other key; call the configurations lookup | Returns an empty list, no error raised |
| daemon-provider-resolver-004 | provider-settings-reader-absent-key, model-empty-when-unset | A settings function that returns none for every key, with an arbitrary configuration identifier; call the model lookup for that identifier | Returns an empty string |
| daemon-provider-resolver-005 | model-verbatim-value, model-lookup-independent-of-registry | A settings function representing a registry with a selected configuration whose stored model is "fake-large"; call the model lookup for that configuration's identifier | Returns "fake-large" exactly |
| daemon-provider-resolver-006 | selected-configuration-malformed-id | A settings function that returns "not-a-uuid" for the selected-configuration-id key and a valid registry for the configurations key; call the selected-configuration lookup | Returns none |
| daemon-provider-resolver-007 | selected-configuration-duplicate-id-order | A registry holding two configuration entries sharing the same identifier but different names, with the selected-configuration-id key set to that shared identifier; call the selected-configuration lookup | Returns the first of the two entries in list order |
| daemon-provider-resolver-008 | configurations-decode-success | A registry holding two distinct, well-formed configurations; call the configurations lookup | Returns both configurations in the same order, fully decoded |
| daemon-provider-resolver-009 | selected-configuration-fallback-signal | The selected-configuration lookup returns none inside the daemon's chat-completion operation | The chat-completion operation takes its command-line fallback path (the zero-config path) and never attempts the plugin-based path |
| daemon-provider-resolver-010 | no-caching, stateless-namespace | Call the configurations lookup once; mutate the underlying store the settings function reads from to add a new configuration; call the configurations lookup again | The second call's result includes the newly added configuration; no result is cached from the first call |
| daemon-provider-resolver-011 | no-instantiation | Attempt to construct an instance of the resolver | Fails: the resolver is a namespace with no instance to construct |
| daemon-provider-resolver-012 | no-persistence, no-side-effects | Inspect the resolver for any file-system, network, subprocess, or settings-write call | No such call exists; every effect happens inside the caller-supplied settings function, not in this component |
| daemon-provider-resolver-013 | provider-settings-reader-shape, settings-store-opacity | Inspect the settings-reader function type's declared shape and every call site inside the resolver | The shape is a function safe to call from any concurrency domain, from a key (text) to an optional text value; every operation accesses data only by calling the passed-in settings function, never a concrete store type |
| daemon-provider-resolver-014 | any-thread-invocation | Call the resolver's three operations from several concurrent execution contexts with no suspension and no synchronization | Runs with no concurrency-safety diagnostic, and each call observes a result consistent with what its own settings function returns |
| daemon-provider-resolver-015 | configurations-empty-when-blank | A settings function that returns an empty string for the configurations key; call the configurations lookup | Returns an empty list — an empty string is treated the same as none |
| daemon-provider-resolver-016 | configurations-array-poisoning | A registry that is a well-formed array where one element is missing a required field (e.g. its identifier); call the configurations lookup | Returns an empty list, not a partial list of the well-formed elements |
| daemon-provider-resolver-017 | decode-failure-diagnostics (open question) | Search the resolver and its call sites for a logging or error-reporting call reached when the configurations lookup's decode fails | No such call exists anywhere in the given sources — demonstrates the open question; no test in the given suite exercises a decode-failure diagnostic because the source implements none |
| daemon-provider-resolver-018 | model-lookup-independent-of-registry | A settings function that returns an empty list for the configurations key but a value for some identifier's model key, where that identifier is not — and never was — present in that registry; call the model lookup for that identifier | Returns the stored model string unchanged; the model lookup never consults the configurations list |

## Edge Cases

- **Null/empty input**: settings returning none for every key (e.g. a
  fresh install with no configuration ever synced) MUST cause the
  configurations lookup to return an empty list, the selected-configuration
  lookup to return none, and the model lookup to return an empty string —
  never crash or raise an error (MUST).
- **Null/empty input**: settings returning an empty string for the
  configurations key MUST be treated identically to none (both fail the
  non-empty check), yielding an empty list (MUST).
- **Null/empty input**: settings returning an empty string for the
  selected-configuration-id key MUST be treated identically to none (both
  fail the non-empty check), yielding none from the selected-configuration
  lookup (MUST).
- **Boundary values**: a registry value of "[]" (a valid, well-formed
  empty JSON array) at the configurations key MUST decode to an empty list
  via the success path, not the malformed-input path — a successful decode
  of zero elements, distinct from an absent or malformed value that also
  yields an empty list (MUST).
- **Boundary values**: a registry with exactly one configuration whose
  identifier matches the selected-configuration-id key is the minimum
  non-empty case for the selected-configuration lookup to succeed; it MUST
  return that configuration (MUST).
- **Boundary values**: the model lookup places no length or character
  constraint on the returned string; whatever value is stored at a
  configuration's model key — including a very long string, one containing
  non-ASCII characters, or one that names no model the plugin actually
  recognizes — MUST be returned verbatim (MUST).
- **Concurrent access**: applicable. The resolver holds no stored or
  shared mutable state and declares no confinement to a single execution
  context, so calls from multiple concurrent execution contexts MUST NOT
  require a lock, queue hop, or suspension, and MUST NOT race, because each
  call only reads through the caller-supplied, concurrency-safe settings
  function (MUST).
- **Concurrent access**: the selected-configuration lookup performs two
  independent reads through the settings function — once directly for the
  selected-configuration-id key, once indirectly via the configurations
  lookup for the configurations key. If the underlying store is mutated
  between those two reads by a concurrent writer, the two values are not
  read as one atomic snapshot; a transient none result MAY occur and MUST
  be tolerated as equivalent to "not currently resolvable," never treated
  as an error (MUST).
- **Error states**: the only dependency is the caller-supplied settings
  function. The resolver MUST treat any none return from settings as "key
  absent" and MUST NOT distinguish "key never set" from "underlying store
  unavailable" — both surface identically, because the settings-reader's
  shape carries no error case (MUST).
- **Error states**: a configurations-key value that is present, non-empty,
  and syntactically valid JSON but decodes to the wrong shape (e.g. a JSON
  object instead of an array) MUST be swallowed and yield an empty list,
  identically to syntactically invalid JSON (MUST).
- **Offline or disconnected state**: Not applicable — the resolver makes
  no network call and has no notion of connectivity; whether the
  app-daemon sync that originally populated the settings store is
  currently reachable is a concern of that separate component, not of this
  read-only lookup.
- **Cancellation and timeouts**: Not applicable — every operation is
  synchronous and non-suspending; there is no operation to cancel and
  nothing that can time out.
- **Missing file or unreachable server**: Not applicable — the resolver
  opens no file and calls no server; it only invokes the passed-in
  function, whose own failure modes are outside this component's contract.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| settings | settings-reader function (concurrency-safe, key → optional text) | none (required) | Injected by the caller on every call; the sole source of registry, selection, and model data. |
| id | configuration identifier | none (required for model lookup) | The configuration identifier whose stored model is being looked up. |
| Configurations key | text (constant, `"ai_configurations"`) | n/a | Settings key the configurations lookup reads for the JSON-encoded configuration-list registry. |
| Selected-configuration-id key | text (constant, `"ai_selected_config_id"`) | n/a | Settings key the selected-configuration lookup reads for the selected configuration's identifier string. |
| Model key (per configuration) | text (per-configuration, `"aiplugin.config.<id>.model"`) | n/a | Settings key the model lookup reads for that configuration's stored model. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable
destination — it is a registry-lookup API with no navigation surface of
its own.

## Localization

Not applicable: the source produces no user-facing string. Its return
values are either domain data (configuration instances, a model identifier
string) or storage-key lookups performed via the provider-configuration
keys component; none of these are text displayed to a user.

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

- **Data collected**: the resolver collects no data itself; it reads
  configuration identity (identifier, name, plugin identifier, template
  identifier) and a stored model string from whatever the caller's
  settings-reader function returns. No credential or secret value ever
  passes through this component — secret values are addressed by the
  provider-configuration-keys component and moved by the
  provider-configuration-sync and secret-store components, neither of
  which the resolver calls.
- **Storage**: the resolver performs no storage of its own; it only reads,
  through the caller-supplied function, whatever backing store the caller
  wraps (per the documented contract, a settings table).
- **Transmission**: this component performs no network transmission of
  its own; it only reads local, already-synced values.
- **Retention**: this component defines no retention policy; a value's
  lifetime is entirely the responsibility of the store behind the caller's
  settings function.

## Logging

Not applicable: the resolver contains no logging call. See
decode-failure-diagnostics for the one place this absence is a genuine
open question rather than a settled fact.

## Platform Notes

- **SwiftUI**: not applicable to this file — `DaemonProviderResolver.swift` imports only `Foundation`, with no SwiftUI dependency; any SwiftUI-based daemon-status surface would call these same static functions unchanged.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift` is part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It has no AppKit or UIKit import and is consumed by `DaemonAIChat` (same framework, also plain Foundation) from the daemon process, not from any app UI layer. The app-side mirror, `AIProviderResolver` (`macOS/Features/AIPlugins/AIProviderResolver.swift`), is `@MainActor`-isolated because it touches the AppKit-adjacent `AIPluginManager`; `DaemonProviderResolver` declares no such isolation because it touches nothing but the passed-in closure. Concretely, `DaemonProviderResolver` is a case-less `public enum` exposing three static functions — `configurations(_:)`, `selectedConfiguration(_:)`, and `model(config:_:)` — over a `ProviderSettingsReader` typealias declared `@Sendable (_ key: String) -> String?`. `configurations(_:)` decodes with `try? JSONDecoder().decode([AIProviderConfiguration].self, from: Data(json.utf8))`, so any decode failure collapses via `try?` to `nil`, which the function turns into `[]`; `selectedConfiguration(_:)` parses the selected-id string with `UUID(uuidString:)`, returning `nil` on failure, and otherwise calls `configurations(settings).first { $0.id == uuid }`; `model(config:_:)` reads `settings(AIProviderConfigKeys.modelKey(config: id)) ?? ""` directly. The requirement names above (configurations-empty-when-*, selected-configuration-malformed-id, model-*) each trace to one of these three function bodies.
- **Compose**: model as a Kotlin top-level `object DaemonProviderResolver` with `fun configurations(settings: (String) -> String?): List<AIProviderConfiguration>`, `fun selectedConfiguration(settings: (String) -> String?): AIProviderConfiguration?`, and `fun model(configId: UUID, settings: (String) -> String?): String`, using `kotlinx.serialization.json.Json.decodeFromString` wrapped in `runCatching { }.getOrNull()` in place of Swift's `try?`, to match the same fail-to-empty/fail-to-null contract. `UUID.toString()` on the JVM is lowercase, unlike Foundation's uppercase `uuidString`; a shared registry with an Apple host needs the same case-normalization decision the sibling `AIProviderConfigKeys` recipe calls out.
- **React/Web**: model as a module of plain exported functions over a UUID already serialized as a string — `configurations(settings: (key: string) => string | null): AIProviderConfiguration[]`, etc. — using `JSON.parse` wrapped in `try { } catch { return [] }` to match the swallow-to-empty contract. JavaScript has no native `UUID` type, so the id-equality check in `selectedConfiguration` becomes a plain string comparison.
- **WinUI 3**: model `DaemonProviderResolver` as a `static class` with `static` methods over a `Func<string, string?>` in place of `ProviderSettingsReader` (a pure, side-effect-free delegate preserves the same any-thread-safety property `@Sendable` gives the Swift closure): `public static List<AIProviderConfiguration> Configurations(Func<string, string?> settings)`, decoding with `System.Text.Json.JsonSerializer.Deserialize<List<AIProviderConfiguration>>(json)` inside a `try`/`catch (JsonException)` that returns an empty `List<AIProviderConfiguration>` to match the Swift `try?`-to-`[]` contract; `public static AIProviderConfiguration? SelectedConfiguration(Func<string, string?> settings)` using `Guid.TryParse` in place of `UUID(uuidString:)` (returning `null` on `false`, matching the Swift guard); and `public static string Model(Guid configId, Func<string, string?> settings) => settings(AIProviderConfigKeys.ModelKey(configId)) ?? "";`. Because `Guid.ToString("D")` is lowercase while Foundation's `uuidString` is uppercase, a WinUI 3 daemon sharing a settings store with the Apple app/daemon MUST normalize case exactly as the `AIProviderConfigKeys` recipe's WinUI 3 note requires, or `Guid`-keyed lookups against Apple-written keys will silently miss. No `ObservableCollection`/`INotifyPropertyChanged` applies — like the Swift source, this is a stateless, one-shot read API, not an observable data source.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/DaemonProviderResolver.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/providers/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, including the open question about swallowed registry-decode diagnostics |
