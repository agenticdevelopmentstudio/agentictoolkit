---
id: 1d7812e7-28cb-4874-897f-43aab62fe009
title: Provider Configuration Synchronization
domain: agentictoolkit://cookbook/ai/providers/provider-config-sync
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The serializable app-to-daemon wire contract mirroring the whole AI provider
  registry (enabled flag, selection pointer, and every resolved configuration) in
  one payload.
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- provider-config
- wire-contract
depends-on: []
related:
- agentictoolkit://cookbook/ai/providers/provider-config-keys
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

# Provider Configuration Synchronization

## Overview

This component declares two value types that together form the
app-to-daemon wire contract for AI provider configuration: the sync
envelope (whether AI summaries are enabled, which configuration is
selected, and every configured provider) and the resolved provider
configuration record (one fully-resolved configuration's identity, model,
and value bag). Per its own documented contract, this component "Replaces
the old flattened push: carries the WHOLE set of configurations plus a
pointer to the active one, so the daemon mirrors the full registry (keyed
by configuration identity) rather than a single plugin-keyed slot." Both
types are serializable and safe to share across concurrency domains, and
neither performs any I/O, validation beyond basic structural typing, or
any side effect — this component is the shape of the sync payload, not an
implementation of sending, receiving, or applying it. The
provider-configuration-keys component's own documented contract names the
two ends of this contract: the app's provider-configuration store and "the
daemon's registry (settings table / secure daemon-side store)"; the
resolved-configuration record's documented contract adds that the daemon
"persists each under the storage-key namespace keyed by id." No source in
this repository constructs a sync-envelope value outside of its own test
target, and none decodes or applies one — see the
`sync-application-unimplemented` requirement below.

## Behavioral Requirements

- **enabled-flag**: The sync envelope MUST carry a required boolean field,
  `enabled`, recording whether AI summaries are enabled.
- **selected-config-id-optional**: The sync envelope MUST declare
  `selectedConfigId` as an optional identifier; per this component's own
  documented contract, "nil / absent == zero-config path" — the
  configuration used for one-shot completions when a value is present, and
  the zero-config command-line default (per the daemon's chat-completion
  path) when it is absent.
- **configs-collection**: The sync envelope MUST carry `configs`, a list
  of resolved provider configuration records, described by this component
  as "Every configured provider, fully resolved (values + secrets)."
- **full-registry-snapshot**: The sync envelope MUST represent one
  complete, self-contained snapshot of the entire provider registry —
  every currently configured provider plus the current selection — because
  the type declares no delta, patch, or removed-ids shape; this
  component's own documented contract states this is the reason it
  exists, replacing "the old flattened push" so "the daemon mirrors the
  full registry ... rather than a single plugin-keyed slot."
- **resolved-config-identity-fields**: The resolved-configuration record
  MUST carry `id`, `name`, `pluginIdentifier`, and `templateId` — the same
  four identity fields a provider configuration carries — plus `model`,
  none of which has a default value in the constructor.
- **resolved-config-value-split**: The resolved-configuration record MUST
  carry a configuration's resolved value bag split into two same-shaped
  text-to-text maps, `values` (non-secret fields) and `secrets` (secret
  fields), each keyed by the field's own key string — the same key a field
  would address via the provider-configuration-keys component's field-key
  operation.
- **empty-secret-clears-credential**: An empty string value under a key in
  the resolved-configuration record's `secrets` map MUST be interpreted,
  per this component's own documented contract, as meaning "clear this
  credential" — i.e. a present-but-empty secret is a distinct, meaningful
  signal from that key being absent from `secrets` altogether.
- **serialized-field-names**: The sync envelope and resolved-configuration
  record MUST serialize and deserialize using their default field-by-field
  encoding with no custom key mapping, so the wire's JSON keys are exactly
  the type's own field names: `enabled`, `selectedConfigId`, `configs` for
  the envelope, and `id`, `name`, `pluginIdentifier`, `templateId`,
  `model`, `values`, `secrets` for each resolved configuration.
- **selected-config-id-omits-key-when-nil**: Encoding a sync envelope
  whose `selectedConfigId` is absent MUST omit the `selectedConfigId` key
  from the JSON entirely rather than writing it as a null value, because
  the default encoding calls the presence-aware encoding path for an
  optional-typed stored field.
- **selected-config-id-decodes-missing-as-nil**: Decoding a JSON object
  that omits the `selectedConfigId` key MUST succeed and yield an absent
  `selectedConfigId`, demonstrated by decoding `{"enabled":false,"configs":[]}`
  and observing the decoded value's `selectedConfigId` is absent.
- **structural-equality**: The sync envelope and resolved-configuration
  record MUST support equality comparison, comparing two instances equal
  if and only if every stored field is equal — a structural, field-by-field
  comparison — demonstrated by asserting a decoded value equals the
  original it was encoded from.
- **concurrent-share-safety**: The sync envelope and resolved-configuration
  record MUST be safe to share across concurrency domains; every stored
  field (boolean, optional identifier, text, text-to-text maps, and lists
  of these safe-to-share types) is itself safe to share, so no manual
  synchronization is required to pass a value from the app's process into
  a daemon-facing call, or across any concurrent-execution-context
  boundary.
- **concurrency-isolation**: The sync envelope and resolved-configuration
  record MUST be usable synchronously from any concurrency domain with no
  suspension; neither type declares confinement to a single execution
  context, so every constructor and field access is unconfined by
  default.
- **mutable-stored-properties**: Every stored field of the sync envelope
  (`enabled`, `selectedConfigId`, `configs`) and of the
  resolved-configuration record (`id`, `name`, `pluginIdentifier`,
  `templateId`, `model`, `values`, `secrets`) MUST be mutable, not fixed
  at construction; unlike an immutable value type, an existing local
  instance MAY have any of these fields reassigned in place after
  construction.
- **memberwise-initializers**: The sync envelope and resolved-configuration
  record MUST each expose a constructor taking every stored field as a
  required parameter with no default value, so every field MUST be
  supplied explicitly at construction (including an explicitly-absent
  `selectedConfigId` when there is no selection).
- **no-persistence**: The sync envelope and resolved-configuration record
  MUST NOT read from or write to a settings store, a secure credential
  store, or a file themselves; this component declares only stored
  fields, a constructor, and its serialization/equality behavior.
- **no-side-effects**: Constructing, encoding, decoding, or reading any
  field of either type MUST NOT perform network access, subprocess
  execution, or notification posting; the source contains no such call.
- **no-error-domain**: Neither constructor MUST fail, and this component
  MUST NOT declare an error type; construction always succeeds
  structurally for any argument values supplied, because the source
  performs no content validation (see Edge Cases).
- **sync-application-unimplemented**: NEEDS REVIEW: Not implemented in
  source. No function anywhere in this repository decodes an incoming
  sync-envelope payload and writes its contents into the
  storage-key-addressed settings/secure-store layout the daemon provider
  resolver reads back (the configurations key, selected-configuration-id
  key, enabled key, and the per-configuration field/model/secret-fields/fields
  keys), and no function constructs and transmits a sync envelope from the
  app side either — the only place a sync envelope is constructed anywhere
  in the given sources is this component's own round-trip test. What is
  missing: the app-side sender that builds this payload from the app's
  provider-configuration store, and the daemon-side receiver that decodes
  it and persists each resolved-configuration record under the
  provider-configuration-keys component's key namespace (honoring
  `empty-secret-clears-credential`). Evidence that would settle it: the
  daemon host implementation this component's documented contract
  attributes the receiving end to (e.g. the daemon provider resolver's
  documented contract calls it "a headless host"), which is not present in
  this repository, or confirmation that this wiring has not yet been
  built.
- **configs-id-uniqueness-unenforced**: NEEDS REVIEW: Not implemented in
  source. The sync envelope's `configs` field is a plain list with no
  check that every entry's identifier is unique, yet this component's own
  documented contract states its purpose is so "the daemon mirrors the
  full registry (keyed by configuration identity)" — a keyed mirror cannot
  hold two different values under one key, so two `configs` entries
  sharing an identifier would have one silently overwrite the other's
  values/secrets/model once persisted under the provider-configuration-keys
  component's namespace, with no error raised anywhere in this component.
  What is missing: a defined outcome for duplicate identifiers (reject at
  construction, reject at decode, or a documented "last one wins" rule).
  Evidence that would settle it: validation in whatever daemon-side
  receiver eventually decodes this payload (see
  `sync-application-unimplemented`), which does not exist in this
  repository today.

## Appearance

Not applicable — this is a serializable wire-contract value type, not a visual component.

## States

Not applicable — this is a serializable wire-contract value type with no lifecycle of its own; it has no running/loading/failed states, only the mutable field values described in `mutable-stored-properties`.

## Accessibility

Not applicable — this is a serializable wire-contract value type, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-config-sync-001 | serialized-field-names, structural-equality | Construct a sync envelope with `enabled: true`, a selected configuration id, and one resolved-configuration record (identity fields "Groq" / "com.x.openai-compatible" / "custom", model "llama-3.3-70b", values `{"baseURL": "https://api.groq.com/openai/v1"}`, secrets `{"apiKey": "sk-abc"}`); encode then decode | Decoded value equals the original exactly |
| ai-provider-config-sync-002 | selected-config-id-decodes-missing-as-nil | Decode `{"enabled":false,"configs":[]}` | Decoded `selectedConfigId` is absent, `enabled` is false, `configs` is empty |
| ai-provider-config-sync-003 | selected-config-id-omits-key-when-nil | Encode a sync envelope with `enabled: false`, no selected configuration, and an empty `configs` list | The resulting JSON object has no `selectedConfigId` key at all (not a null value) |
| ai-provider-config-sync-004 | configs-collection | Encode a sync envelope with `enabled: true`, no selected configuration, and an empty `configs` list | The resulting JSON's `configs` key is present as an empty array |
| ai-provider-config-sync-005 | empty-secret-clears-credential | Round-trip a resolved-configuration record whose `secrets` map is `{"apiKey": ""}` through encode/decode | Decoded `secrets["apiKey"]` is the empty string — it survives the wire unchanged (not stripped or converted to a missing key), preserving the "clear this credential" signal |
| ai-provider-config-sync-006 | structural-equality | Two resolved-configuration records built with identical identity fields, model, values, and secrets, versus a third differing only in model | The first two compare equal; the third compares unequal to either |
| ai-provider-config-sync-007 | structural-equality | Two sync envelopes with identical enabled/selected-configuration/configs fields, versus a third differing only in enabled | The first two compare equal; the third compares unequal to either |
| ai-provider-config-sync-008 | serialized-field-names | Encode a resolved-configuration record whose identifier is `11111111-2222-3333-4444-555555555555` | The JSON `id` field is the string `"11111111-2222-3333-4444-555555555555"` (the canonical uppercase, hyphenated form) |
| ai-provider-config-sync-009 | concurrent-share-safety, concurrency-isolation | Capture a constructed sync-envelope value in a closure passed to a new concurrent execution context with no suspension and no confinement hop | Runs with no concurrency-safety diagnostic, because every stored field is itself safe to share across concurrency domains |

## Edge Cases

- **Empty `configs` list**: MUST NOT be rejected at construction; the
  source has no non-empty check, and this is exactly the shape the
  missing-selection test decodes.
- **`selectedConfigId` is absent**: MUST be accepted as the documented
  zero-config path (see `selected-config-id-optional`); this is not an
  error state.
- **`selectedConfigId` does not match any `id` in `configs`**: MUST NOT be
  rejected at construction; this component enforces no referential
  relationship between the two fields. Downstream, the daemon provider
  resolver's selected-configuration lookup already tolerates exactly this
  case gracefully — returning none when no entry matches — and the
  daemon's chat-completion path falls through to the zero-config
  command-line default — so a dangling selection is a defined,
  non-crashing outcome once the payload reaches that resolver, even though
  this component itself does not validate it.
- **Duplicate identifier values across `configs` entries**: See
  `configs-id-uniqueness-unenforced` — this component accepts duplicates
  with no error, and what happens once such a payload is persisted is
  undefined in source.
- **Empty string identity or model fields** (name, plugin identifier,
  template identifier, model all empty strings): MUST NOT be rejected; the
  source performs no content validation on any text field.
- **Empty `values` or `secrets` maps**: MUST NOT be rejected; both are
  plain text-to-text maps with no minimum-count requirement.
- **The same field key present in both `values` and `secrets`**: this
  component enforces no disjointness between the two maps; nothing in
  this component resolves which one a receiver should prefer if both
  contain the same key.
- **Very large `configs` list**: MUST NOT be rejected; this component
  declares no upper bound on the number of configurations a sync payload
  may carry.
- **Concurrent access**: applicable, and safe by construction for reads —
  the sync envelope and resolved-configuration record are safe to share
  across concurrency domains, so an already-constructed, unshared copy
  MAY be read from multiple concurrent execution contexts with no
  synchronization. Because every stored field is mutable (see
  `mutable-stored-properties`), a single instance held in shared mutable
  storage still needs the caller's own synchronization (a confinement
  mechanism, a lock, or a serial queue) to avoid a data race on that
  shared variable — being safe to share guarantees a value is safe to
  *transfer*, not that a shared mutable binding to it is automatically
  synchronized.
- **Error states from a dependency**: Not applicable — this component has
  no dependency (no network, database, or file-system call) of its own
  that could fail; whatever eventually sends or receives this payload over
  the app-daemon boundary is a different, currently-unimplemented
  component (see `sync-application-unimplemented`), not this component.
- **Offline or disconnected state**: Not applicable — this component
  performs no network access itself; it only defines the shape of a
  payload some other, unimplemented transport would carry.
- **Cancellation and timeouts**: Not applicable — every operation in this
  component (construction, encoding, decoding, equality) is synchronous
  and non-suspending; there is nothing to cancel and no operation that can
  time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | none (required) | The sync envelope's flag for whether AI summaries are enabled. |
| `selectedConfigId` | optional identifier | none (required; pass absent for no selection) | The sync envelope's pointer to the configuration used for summaries; absent is the documented zero-config path. |
| `configs` | list of resolved-configuration records | none (required) | The sync envelope's full set of configured providers, fully resolved. |
| `id` | identifier | none (required) | The resolved-configuration record's identity, matching the app-side configuration's own identifier that it mirrors. |
| `name` | text | none (required) | The resolved-configuration record's display name. |
| `pluginIdentifier` | text | none (required) | The resolved-configuration record's plugin-bundle identifier. |
| `templateId` | text | none (required) | The resolved-configuration record's provider-template identifier. |
| `model` | text | none (required) | The resolved-configuration record's resolved model string. |
| `values` | text-to-text map | none (required) | The resolved-configuration record's non-secret resolved field values, keyed by field key. |
| `secrets` | text-to-text map | none (required) | The resolved-configuration record's secret resolved field values, keyed by field key; an empty value means "clear this credential." |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable
destination — it is a wire-payload shape with no navigation surface of
its own.

## Localization

Not applicable: the source contains no user-facing string literal;
`name`, `pluginIdentifier`, `templateId`, `model`, and every key/value in
`values`/`secrets` are caller-supplied data, never text this file displays
or hardcodes.

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

- **Data collected**: the resolved-configuration record's `secrets` field
  carries a provider credential (e.g. an API key) for every configuration
  that has one, alongside `values`' non-secret fields (e.g. a base URL).
  The sync envelope bundles every configuration's `secrets` together with
  `enabled` and `selectedConfigId` into one payload — this component's
  stated purpose is to move the app's full, already-resolved credential
  set to the daemon in one shot.
- **Storage**: this component performs no storage of its own (see
  `no-persistence`); per its documented contract, the receiving side is
  expected to persist each configuration "under the provider-configuration-keys
  component's namespace keyed by id" — plain settings keys for values, and
  a secure store for secrets — but no such receiver exists in this
  repository (see `sync-application-unimplemented`), so today nothing in
  this codebase actually stores a value carried by this type.
- **Transmission**: this component defines the payload's shape but
  performs no transmission itself; it is documented as crossing the
  app-to-daemon boundary (a process boundary, and per the
  provider-configuration-keys component's documented contract, potentially
  between the app's storage and "the daemon's registry"), but no sender
  exists in this repository either (see `sync-application-unimplemented`).
- **Retention**: the sync envelope and resolved-configuration record
  define no retention policy or expiry of their own; a constructed
  instance is a transient in-memory value with no cache. Any retention of
  the credentials it carries is entirely the responsibility of whatever
  (currently unimplemented) receiver persists them.
- **Disclosure safeguard**: Neither type overrides its default
  textual/debug description, so the compiler-synthesized default
  description of either type prints the entire `secrets` map — including
  any credential — verbatim; the types apply no redaction of their own.
  No caller in the given sources logs or prints a sync-envelope or
  resolved-configuration-record value today, so this has no live effect in
  this repository, but nothing in the type would stop a future caller from
  doing so.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIProviderConfigSync.swift` imports only `Foundation`, with no SwiftUI dependency; a SwiftUI-based settings screen would construct and encode this type unchanged before handing it to whatever transport eventually sends it to the daemon.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It declares two `public` value types, `AIProviderConfigSync` (the sync envelope) and `ResolvedProviderConfig` (the resolved-configuration record), each conforming to `Codable`, `Sendable`, and `Equatable` via the compiler-synthesized conformances, with every stored property declared `var` rather than `let` and a `public` memberwise initializer taking every property as a required parameter. `selectedConfigId: UUID?` relies on the compiler-synthesized `Encodable` conformance's `encodeIfPresent` call to omit the JSON key when `nil`, matching `selected-config-id-omits-key-when-nil`. It is plain Foundation with no AppKit import; the app-side `AIProviderConfigStore.swift` (`macOS/Features/AIPlugins/`, `@MainActor`-isolated) is the natural source of the field values this type would carry, and the daemon-side `DaemonProviderResolver`/`DaemonAIChat` are the natural consumers of what it would deliver, though neither side currently constructs or decodes one (see `sync-application-unimplemented`).
- **Compose**: model `AIProviderConfigSync` and `ResolvedProviderConfig` as `@Serializable` Kotlin `data class`es (`kotlinx.serialization`) with `var` properties to match the source's mutability, and `UUID` as `java.util.UUID` serialized to its string form. Note the same cross-platform case-sensitivity issue documented on the sibling provider-configuration-keys recipe: `UUID.toString()` on the JVM is lowercase, while Foundation's `uuidString` is uppercase — an Android daemon and an Apple app sharing this payload over the same wire MUST agree on one case (or compare case-insensitively) for `id`/`selectedConfigId` to match correctly.
- **React/Web**: model as a plain TypeScript interface — `interface AIProviderConfigSync { enabled: boolean; selectedConfigId?: string; configs: ResolvedProviderConfig[] }` — with `id`s as `string` (JavaScript has no native `UUID` type). Replicating `selected-config-id-omits-key-when-nil` needs care: `JSON.stringify` omits a key whose value is `undefined` but keeps one whose value is `null`, so the field must be typed/constructed as `selectedConfigId?: string` (and left `undefined`, never set to `null`) to match Swift's "omit the key entirely" behavior exactly.
- **WinUI 3**: model as C# `record`s using `System.Text.Json` — e.g. `public sealed record AIProviderConfigSync(bool Enabled, Guid? SelectedConfigId, IReadOnlyList<ResolvedProviderConfig> Configs);` and `public sealed record ResolvedProviderConfig(Guid Id, string Name, string PluginIdentifier, string TemplateId, string Model, IReadOnlyDictionary<string, string> Values, IReadOnlyDictionary<string, string> Secrets);`. Apply `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]` (or an equivalent serializer option) to `SelectedConfigId` to reproduce `selected-config-id-omits-key-when-nil` — `System.Text.Json` writes `null` by default for a `null` nullable property, unlike Swift's key-omitting `encodeIfPresent`. Normalize `Guid.ToString()` (default `"D"` format, lowercase) to uppercase with `.ToUpperInvariant()` — or normalize consistently on read — so `id`/`selectedConfigId` values match byte-for-byte against Foundation's uppercase `uuidString` on the Apple side of the wire. `IReadOnlyDictionary<string, string>`/`Dictionary<string, string>` replace `[String: String]` for `Values`/`Secrets`; preserve `empty-secret-clears-credential` by treating a present key with an empty string the same as the Swift side does, not as equivalent to the key's absence.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigSync.swift` |

## Design Decisions

**Decision**: The sync envelope carries the entire provider registry (every resolved-configuration record plus the current selection) in one payload, rather than an incremental add/remove/update delta.
**Rationale**: per this component's own documented contract, this is a deliberate replacement for "the old flattened push," chosen so "the daemon mirrors the full registry ... rather than a single plugin-keyed slot" — a full-snapshot payload cannot drift from partial updates arriving out of order, at the cost of resending every configuration's `values`/`secrets` on every sync, even for configurations that did not change.
**Approved**: pending

**Decision**: The resolved-configuration record splits a configuration's resolved values into two parallel text-to-text maps (`values`, `secrets`) rather than one map of a richer value type that carries its own secret/non-secret flag.
**Rationale**: this mirrors the split the provider-configuration-keys component and the daemon's chat-completion path already make between plain settings storage and secure-store-backed secret storage — a receiver can route each map to its corresponding store directly, without inspecting per-field metadata to decide where a value belongs. (Apple platform implementation.)
**Approved**: pending

**Decision**: every stored field of the sync envelope and resolved-configuration record is declared mutable, not fixed at construction — unlike the sibling chat-context types, whose stored fields are all immutable.
**Rationale**: not explained in source; recorded here as an observed divergence from the sibling immutability convention rather than corrected, since neither the concurrent-share-safety nor the structural-equality requirement demands immutability and the source gives no indication of an in-place-mutation call site that would justify it. (Apple platform implementation.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | Privacy and Data |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | failed | Security |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |

`separation-of-concerns` passes because this component performs no storage, no transport, and no business logic of its own; it is only the data shape shared between an app-side sender and a daemon-side receiver, neither of which lives in this file. `idempotent-operations` passes because encoding, decoding, and equality are all deterministic computations of a value's stored properties, with no shared state that could make repeated calls diverge (see `serialized-field-names`, `structural-equality`). `data-minimization` is `partial`: the resolved-configuration record carries a configuration's *entire* resolved value and secret bag in one undifferentiated pair of maps, with no narrower, credential-free view for a caller that only needs identity or model, and no redaction on the type's default description, which prints `secrets` verbatim if ever logged or printed (see `Disclosure safeguard` in Privacy). `input-sanitization` fails because neither `configs`' identifier uniqueness nor `selectedConfigId`'s reference into `configs` is validated at construction or decode time (see `configs-id-uniqueness-unenforced`). `secure-storage` is `partial`: the `values`/`secrets` split gives a future receiver a clean signal for which fields need a secure store, but nothing in this file enforces that a receiver actually routes `secrets` there — that enforcement, like the receiver itself, does not yet exist in this repository (see `sync-application-unimplemented`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/providers/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
