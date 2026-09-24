---
id: 80df89b9-a1d3-4fb5-b9e3-08bafd2720fb
title: Provider Type Facet
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-provider-type-facet
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Buckets a provider's Config Type display string into subscription, apiKey,
  local, or custom for the picker's Type filter.
platforms:
- swift
- macos
tags:
- ai-plugin
- value-type
- sendable
- foundation
- provider-config
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor
references: []
approved-by: ''
approved-date: ''
---

# Provider Type Facet

## Overview

`ProviderTypeFacet.swift` (`packages/apple/AgenticToolkit/AIPluginKit/ProviderTypeFacet.swift`) defines a four-case, `String`-raw-valued enum answering "what do I need before this provider works": an account already paid for, a key that has to be fetched, a server running on this machine, or a hand-configured endpoint. The picker's Config Type column already shows this fact as descriptor copy (`AIPluginDescriptor.ProviderTemplate.resolvedConfigType`, e.g. "OAuth Account", "API Key", "Local"); this file buckets that same free-text copy into one of the four facets so it can be filtered on, per the type's own doc comment. The file performs no I/O and has one dependency, `Foundation`. It defines: the `ProviderTypeFacet` enum itself with cases `subscription`, `apiKey`, `local`, `custom`; two computed properties, `title` and `detail`, supplying fixed display strings per case; a failable-free initializer, `init(configType:)`, that buckets a descriptor's Config Type string by loose, case-insensitive substring matching; and one static function, `matches(type:selected:)`, answering whether a facet survives a filter selection. Its only production consumer is `ProviderPickerViewController.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/`): `ProviderPickerRow.type` computes `ProviderTypeFacet(configType: configType)` per row, `ProviderPickerFilter.filter` calls `ProviderTypeFacet.matches(type:selected:)`, and the view controller's Type filter button is built from `ProviderTypeFacet.allCases` and restored via `ProviderTypeFacet.init(rawValue:)`.

## Behavioral Requirements

- **case-set**: `ProviderTypeFacet` MUST define exactly four cases: `subscription`, `apiKey`, `local`, and `custom`.
- **raw-value-identity**: Each case's raw `String` value MUST equal its Swift case name exactly (`"subscription"`, `"apiKey"`, `"local"`, `"custom"`), since no case declares an explicit raw-value literal and Swift synthesizes the raw value from the case name.
- **case-iterable-order**: `ProviderTypeFacet` MUST conform to `CaseIterable`, and `allCases` MUST enumerate the four cases in declaration order: `subscription`, `apiKey`, `local`, `custom`.
- **sendable-conformance**: `ProviderTypeFacet` MUST conform to `Sendable`; because it is a case-only enum with a `String` raw type and no associated values, every instance MUST be safe to share across concurrency domains with no synchronization.
- **codable-conformance**: `ProviderTypeFacet` MUST conform to `Codable`; because it is a `String`-backed `RawRepresentable` enum with no custom `init(from:)`/`encode(to:)`, encoding an instance MUST produce its raw-value string, and decoding MUST succeed only when the JSON string equals one of the four raw values.
- **equatable-hashable-conformance**: `ProviderTypeFacet` MUST be `Equatable` and `Hashable` via the compiler's automatic case-only synthesis (an enum with no associated values gets both with no explicit declaration), since callers place instances into `Set<ProviderTypeFacet>` (`matches(type:selected:)`'s `selected` parameter and the picker's persisted type-filter selection).
- **rawvalue-initializer**: `ProviderTypeFacet` MUST provide the compiler-synthesized `init?(rawValue:)` inherited from `RawRepresentable`, returning the matching case for one of the four raw-value strings and `nil` for any other string.
- **title-strings**: `title` MUST return `"Subscription"` for `.subscription`, `"API key"` for `.apiKey`, `"Local LLM"` for `.local`, and `"Custom"` for `.custom`.
- **detail-strings**: `detail` MUST return `"Uses an account you already have"` for `.subscription`, `"Needs a key from the vendor"` for `.apiKey`, `"Runs on this machine"` for `.local`, and `"An endpoint you configure yourself"` for `.custom`.
- **config-type-case-insensitive**: `init(configType:)` MUST lowercase the given string before testing it against any rule, so bucketing is case-insensitive.
- **config-type-subscription-match**: `init(configType:)` MUST bucket to `.subscription` when the lowercased string contains `"oauth"`, `"subscription"`, or `"account"`.
- **config-type-local-match**: When the lowercased string does not satisfy the subscription rule, `init(configType:)` MUST bucket to `.local` when it contains `"local"`.
- **config-type-apikey-match**: When the lowercased string satisfies neither the subscription nor the local rule, `init(configType:)` MUST bucket to `.apiKey` when it contains `"key"` or `"token"`.
- **config-type-default-custom**: `init(configType:)` MUST bucket to `.custom` when the lowercased string satisfies none of the subscription, local, or key/token rules — including the empty string.
- **config-type-precedence-order**: When a string satisfies more than one rule (for example a string containing both `"account"` and `"token"`, or both `"local"` and `"key"`), `init(configType:)` MUST resolve to the first rule that matches in the fixed order subscription, then local, then apiKey, then custom; the underlying if/else-if chain never evaluates a later rule once an earlier one has matched.
- **matches-empty-selection**: `matches(type:selected:)` MUST return `true` for every `type` when `selected` is empty.
- **matches-membership**: `matches(type:selected:)` MUST return `selected.contains(type)` when `selected` is non-empty.

## Appearance

Not applicable — this is a bucketing enum, not a visual component.

## States

Not applicable — this is a bucketing enum, not a visual component.

## Accessibility

Not applicable — this is a bucketing enum, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| provider-type-facet-001 | config-type-subscription-match, config-type-local-match, config-type-apikey-match | `ProviderTypeFacet(configType:)` on `"OAuth Account"`, `"Subscription"`, `"API Key"`, `"Local"`, `"Local Server"` (traced to `ProviderTypeFacetTests.realConfigTypes`) | Returns `.subscription`, `.subscription`, `.apiKey`, `.local`, `.local` respectively |
| provider-type-facet-002 | config-type-case-insensitive, config-type-subscription-match, config-type-apikey-match, config-type-default-custom | `ProviderTypeFacet(configType:)` on `"oauth 2 account"`, `"Access Token"`, `""`, `"Bring your own endpoint"` (traced to `ProviderTypeFacetTests.looseMatching`) | Returns `.subscription`, `.apiKey`, `.custom`, `.custom` respectively |
| provider-type-facet-003 | config-type-precedence-order, config-type-subscription-match | `ProviderTypeFacet(configType: "Subscription Token")` (traced to `ProviderTypeFacetTests.subscriptionWinsOverKey`) | Returns `.subscription`, not `.apiKey`, even though the string also contains `"token"` |
| provider-type-facet-004 | matches-empty-selection, matches-membership | `ProviderTypeFacet.matches(type: .apiKey, selected: [])`; `matches(type: .apiKey, selected: [.apiKey, .local])`; `matches(type: .subscription, selected: [.apiKey, .local])` (traced to `ProviderTypeFacetTests.matches`) | Returns `true`, `true`, `false` respectively |
| provider-type-facet-005 | title-strings, detail-strings | For every facet in `ProviderTypeFacet.allCases` (traced to `ProviderTypeFacetTests.labels`) | `facet.title.isEmpty == false` and `facet.detail.isEmpty == false` for all four cases |
| provider-type-facet-006 | case-iterable-order, case-set | `ProviderTypeFacet.allCases` (traced to the case declaration order in `ProviderTypeFacet.swift`; no test enumerates order directly) | Returns `[.subscription, .apiKey, .local, .custom]`, in that order |
| provider-type-facet-007 | rawvalue-initializer, raw-value-identity | `ProviderTypeFacet(rawValue: "apiKey")`; `ProviderTypeFacet(rawValue: "bogus")` (traced to the compiler-synthesized `RawRepresentable` initializer that `ProviderPickerViewController.swift` line 647 calls via `compactMap(ProviderTypeFacet.init(rawValue:))`) | Returns `.apiKey` for `"apiKey"`; returns `nil` for `"bogus"` |
| provider-type-facet-008 | config-type-precedence-order, config-type-local-match, config-type-apikey-match | `ProviderTypeFacet(configType: "Local API Key")` (derived directly from the if/else-if order in `ProviderTypeFacet.swift`; not exercised by an existing test) | Returns `.local` — the local rule is checked and matches before the key/token rule is ever reached |

## Edge Cases

- **Empty `configType` string**: `init(configType:)` given `""` MUST bucket to `.custom`, since the lowercased empty string satisfies none of the six matched substrings (provider-type-facet-002).
- **Multiple rules satisfied at once (boundary of the matching rules)**: A `configType` string satisfying more than one rule's substring test MUST resolve via the fixed evaluation order subscription, then local, then apiKey, then custom; no input can reach a later rule once an earlier one has matched (provider-type-facet-003, provider-type-facet-008).
- **Unrecognized `rawValue`**: `init?(rawValue:)` given a string that is not one of the four case names MUST return `nil` rather than crash or default to a case (provider-type-facet-007); this is the compiler-provided `RawRepresentable` behavior, not custom logic in this file.
- **Malformed JSON during `Codable` decode**: Because `Codable` is synthesized for a `String`-`RawRepresentable` enum, `JSONDecoder` decoding a JSON string that is not `"subscription"`, `"apiKey"`, `"local"`, or `"custom"` MUST throw `DecodingError.dataCorrupted`, since the synthesized `init(from:)` calls `init?(rawValue:)` and throws when it returns `nil`.
- **Concurrent access**: Because `ProviderTypeFacet` is a case-only `Sendable` enum with no stored mutable state, calling `matches(type:selected:)` or `init(configType:)` concurrently from multiple threads or actors MUST be safe with no synchronization, since neither function reads or writes shared state.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) of its own to fail; `init(configType:)` is a pure string transform over a value already resolved by `AIPluginDescriptor.ProviderTemplate.resolvedConfigType`.
- **Offline or disconnected state**: Not applicable — this file performs no network access of its own.
- **Cancellation and timeouts**: Not applicable — every member is a synchronous, non-throwing function or computed property; there is no asynchronous or long-running operation to cancel or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configType` | `String` | none (required) | Parameter to `init(configType:)` — the descriptor's Config Type display string (e.g. `AIPluginDescriptor.ProviderTemplate.resolvedConfigType`) to bucket into a facet. |
| `selected` | `Set<ProviderTypeFacet>` | none in this file (callers such as `ProviderPickerFilter.filter` default the equivalent parameter to `[]`) | Parameter to `matches(type:selected:)` — the set of facets currently checked in the picker's Type filter; an empty set matches every facet. |

## Deep Linking

Not applicable: `ProviderTypeFacet.swift` defines no URL routing, navigation, or scheme handling.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (inline Swift literal, no lookup key) | Subscription | `title` for `.subscription`; the Type filter's choice label. |
| — (inline Swift literal, no lookup key) | API key | `title` for `.apiKey`. |
| — (inline Swift literal, no lookup key) | Local LLM | `title` for `.local`. |
| — (inline Swift literal, no lookup key) | Custom | `title` for `.custom`. |
| — (inline Swift literal, no lookup key) | Uses an account you already have | `detail` for `.subscription`; shown as the choice's tooltip/detail text. |
| — (inline Swift literal, no lookup key) | Needs a key from the vendor | `detail` for `.apiKey`. |
| — (inline Swift literal, no lookup key) | Runs on this machine | `detail` for `.local`. |
| — (inline Swift literal, no lookup key) | An endpoint you configure yourself | `detail` for `.custom`. |

All eight strings are hardcoded English literals with no localization mechanism (no `NSLocalizedString`/`String(localized:)`/string-catalog lookup) anywhere in this file.

## Accessibility Options

Not applicable: this is a data-only value type with no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `ProviderTypeFacet.swift` declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: `ProviderTypeFacet.swift` contains no analytics or event-emission call.

## Privacy

Not applicable: `ProviderTypeFacet.swift` carries no credential or personal data. It buckets a display string (a descriptor's Config Type copy, e.g. `AIPluginDescriptor.ProviderTemplate.resolvedConfigType`) that is already non-secret vendor-authored metadata; the actual secret value behind an `.apiKey`-bucketed provider lives in `Field`/`PluginConfigStore`, not in this file.

## Logging

Not applicable: `ProviderTypeFacet.swift` contains no `os_log`, `Logger`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not the source, but a straightforward consumer — a SwiftUI Type filter would read `ProviderTypeFacet.allCases` to populate a `Picker`/`Menu`, using `.title` as the label and `.detail` as a subtitle or tooltip, the same data `MultiChoiceFilterButton`'s AppKit consumer already reads at `ProviderPickerViewController.swift` line 108. No `ObservableObject` wrapper is needed since the enum is `Sendable`, `Equatable`, and stateless.
- **Compose**: a Kotlin port models `ProviderTypeFacet` as an `enum class ProviderTypeFacet(val rawValue: String)` with the same four cases, plus a companion factory (e.g. `fromConfigType(configType: String): ProviderTypeFacet`) that reproduces the four-branch, lowercase, ordered `contains` chain exactly — subscription/oauth/account first, then local, then key/token, else custom. `matches` becomes a companion or top-level function over `Set<ProviderTypeFacet>`, and `CaseIterable.allCases` maps to `ProviderTypeFacet.entries`.
- **React/Web**: a TypeScript port models the four cases as a string-literal union (`type ProviderTypeFacet = "subscription" | "apiKey" | "local" | "custom"`); `title`/`detail` become `Record<ProviderTypeFacet, string>` lookup tables; `fromConfigType(configType: string)` reproduces the same lowercased, ordered `includes()` chain; `matches` becomes a plain function testing `selected.size === 0 || selected.has(type)` over a `Set`.
- **AppKit / UIKit**: this is the source, indirectly. `ProviderTypeFacet.swift` itself has no AppKit import, but its only production consumer is `ProviderPickerViewController.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/`): `ProviderPickerRow.type` computes the facet per row from `configType`, `ProviderPickerFilter.filter` narrows rows through `ProviderTypeFacet.matches`, the Type filter button's choices come from `ProviderTypeFacet.allCases.map { .init(id: $0.rawValue, title: $0.title, detail: $0.detail) }` at line 108, and a persisted selection is restored via `Set(typeFilter.selection.compactMap(ProviderTypeFacet.init(rawValue:)))` at line 647. No iOS/UIKit target exists for `AIPluginKit` today — `project.yml` declares the framework `platform: macOS` only.
- **WinUI 3**: a .NET port models the four cases as `public enum ProviderTypeFacet { Subscription, ApiKey, Local, Custom }` with a `JsonStringEnumConverter` (or an explicit string map) so the wire values stay the lowercase-first `"subscription"`/`"apiKey"`/`"local"`/`"custom"` strings this Swift enum's synthesized `Codable` produces. `Title`/`Detail` become an extension method or a `switch` expression over the enum returning the same eight literal strings. `FromConfigType(string configType)` reproduces the exact four-branch, lowercase-then-`Contains` chain in the same fixed order (config-type-precedence-order); because `string.Contains` is ordinal by default, the port MUST call `.ToLowerInvariant()` first (matching Swift's `.lowercased()`) or pass `StringComparison.OrdinalIgnoreCase` explicitly to reproduce config-type-case-insensitive. `Matches(type, selected)` becomes a static method over `IReadOnlySet<ProviderTypeFacet>`, and `Enum.GetValues<ProviderTypeFacet>()` feeds the `ItemsSource` of the `ComboBox`/toggle-button group standing in for `MultiChoiceFilterButton` in the settings XAML.

## Design Decisions

**Decision**: `init(configType:)` matches loosely, by lowercased substring (`contains`), rather than by an exact match against a fixed dictionary of known Config Type strings.
**Rationale**: per the type's own doc comment, `configType` is descriptor copy meant to be read by a person (e.g. "OAuth Account", "Subscription Token"), and a vendor adding new but similar wording tomorrow (e.g. "OAuth 2 Account") should land in the same bucket rather than silently becoming an unbucketed fourth kind of thing. `ProviderTypeFacetTests.looseMatching` exercises exactly this: `"oauth 2 account"` still resolves to `.subscription`.
**Approved**: pending

**Decision**: the subscription/oauth/account rule is checked before the key/token rule, so a string naming both (e.g. `"Subscription Token"`) resolves to `.subscription`, not `.apiKey`.
**Rationale**: per `ProviderTypeFacetTests.subscriptionWinsOverKey`'s own comment, "OAuth Account" style strings sometimes also say "token", and the account is the thing the user actually needs to have ready, so it takes precedence over the token wording. The same fixed-order reasoning extends to the local rule being checked before the key/token rule (config-type-precedence-order, provider-type-facet-008), though no existing test exercises that specific combination.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | passed | Best Practices |

`separation-of-concerns` passes because `ProviderTypeFacet.swift` performs no file I/O, network access, or persistence of its own — it is a pure enum plus two pure functions over already-resolved data. `no-hardcoded-strings` fails: `title` and `detail` return literal, non-localized English strings (see Localization) that the picker's Type filter displays directly. `idempotent-operations` passes: `init(configType:)` and `matches(type:selected:)` are pure and deterministic — calling either repeatedly with the same input always returns the same result with no side effect. `test-pyramid` passes: every behavior in this file (bucketing, precedence, matching, labels) is covered by `ProviderTypeFacetTests.swift`'s unit-level `@Test` cases, and no integration or end-to-end layer is applicable since the file has no I/O to integrate.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
