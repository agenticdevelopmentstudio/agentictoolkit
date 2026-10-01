---
id: 80df89b9-a1d3-4fb5-b9e3-08bafd2720fb
title: Provider Type Facet
domain: agentictoolkit://cookbook/ai/providers/provider-type-facet
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
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
- provider-config
depends-on: []
related:
- agentictoolkit://cookbook/ai/plugins/plugin-descriptor
references: []
approved-by: ''
approved-date: ''
---

# Provider Type Facet

## Overview

The provider type facet answers "what do I need before this provider works": an account already paid for, a key that has to be fetched, a server running on this machine, or a hand-configured endpoint. The picker's Config Type column already shows this fact as descriptor copy (e.g. "OAuth Account", "API Key", "Local"); this concept buckets that same free-text copy into one of four facets so it can be filtered on. The concept performs no I/O. It defines: the facet itself, with cases `subscription`, `apiKey`, `local`, `custom`; two lookups, a title and a detail, supplying fixed display strings per case; a bucketing operation that classifies a descriptor's Config Type string by loose, case-insensitive substring matching; and one function answering whether a facet survives a filter selection. Its only production consumer is the provider picker: each row computes its facet from its Config Type string, the picker's filter logic calls the matching function, and the picker's Type filter button is built from the full set of facets and restored from a persisted selection.

## Behavioral Requirements

- **case-set**: The facet MUST define exactly four cases: `subscription`, `apiKey`, `local`, and `custom`.
- **raw-value-identity**: Each case's wire (string) value MUST equal its case name exactly (`"subscription"`, `"apiKey"`, `"local"`, `"custom"`).
- **all-cases-enumeration-order**: The facet MUST support enumerating all four cases, and that enumeration MUST list them in declaration order: `subscription`, `apiKey`, `local`, `custom`.
- **safe-to-share**: The facet MUST be safe to share across concurrent contexts with no synchronization; because it is a case-only value with a string wire form and no associated data, every instance is trivially shareable.
- **json-round-trip**: The facet MUST support encoding to and decoding from JSON via its wire value; encoding an instance MUST produce its wire-value string, and decoding MUST succeed only when the JSON string equals one of the four wire values.
- **value-equality-and-hashing**: The facet MUST support equality comparison and hashing derived from its case identity alone (it carries no associated data), since callers place instances into a set (the matching function's selection parameter and the picker's persisted type-filter selection).
- **wire-value-lookup**: The facet MUST provide a lookup from a wire-value string back to its case, returning the matching case for one of the four wire values and no result for any other string.
- **title-strings**: The title lookup MUST return `"Subscription"` for `subscription`, `"API key"` for `apiKey`, `"Local LLM"` for `local`, and `"Custom"` for `custom`.
- **detail-strings**: The detail lookup MUST return `"Uses an account you already have"` for `subscription`, `"Needs a key from the vendor"` for `apiKey`, `"Runs on this machine"` for `local`, and `"An endpoint you configure yourself"` for `custom`.
- **config-type-case-insensitive**: Bucketing a Config Type string MUST lowercase it before testing it against any rule, so bucketing is case-insensitive.
- **config-type-subscription-match**: Bucketing MUST resolve to `subscription` when the lowercased string contains `"oauth"`, `"subscription"`, or `"account"`.
- **config-type-local-match**: When the lowercased string does not satisfy the subscription rule, bucketing MUST resolve to `local` when it contains `"local"`.
- **config-type-apikey-match**: When the lowercased string satisfies neither the subscription nor the local rule, bucketing MUST resolve to `apiKey` when it contains `"key"` or `"token"`.
- **config-type-default-custom**: Bucketing MUST resolve to `custom` when the lowercased string satisfies none of the subscription, local, or key/token rules — including the empty string.
- **config-type-precedence-order**: When a string satisfies more than one rule (for example a string containing both `"account"` and `"token"`, or both `"local"` and `"key"`), bucketing MUST resolve to the first rule that matches in the fixed order subscription, then local, then apiKey, then custom; a later rule MUST NOT be evaluated once an earlier one has matched.
- **matches-empty-selection**: The matching function MUST return `true` for every facet when the selection is empty.
- **matches-membership**: The matching function MUST return whether the facet is a member of the selection when the selection is non-empty.

## Appearance

Not applicable — this is a bucketing concept, not a visual component.

## States

Not applicable — this is a bucketing concept, not a visual component.

## Accessibility

Not applicable — this is a bucketing concept, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| provider-type-facet-001 | config-type-subscription-match, config-type-local-match, config-type-apikey-match | Bucket the Config Type strings `"OAuth Account"`, `"Subscription"`, `"API Key"`, `"Local"`, `"Local Server"` | Returns `subscription`, `subscription`, `apiKey`, `local`, `local` respectively |
| provider-type-facet-002 | config-type-case-insensitive, config-type-subscription-match, config-type-apikey-match, config-type-default-custom | Bucket the Config Type strings `"oauth 2 account"`, `"Access Token"`, `""`, `"Bring your own endpoint"` | Returns `subscription`, `apiKey`, `custom`, `custom` respectively |
| provider-type-facet-003 | config-type-precedence-order, config-type-subscription-match | Bucket the Config Type string `"Subscription Token"` | Returns `subscription`, not `apiKey`, even though the string also contains `"token"` |
| provider-type-facet-004 | matches-empty-selection, matches-membership | Match `apiKey` against an empty selection; match `apiKey` against `{apiKey, local}`; match `subscription` against `{apiKey, local}` | Returns `true`, `true`, `false` respectively |
| provider-type-facet-005 | title-strings, detail-strings | For every facet in the full set of cases | Its title is non-empty and its detail is non-empty, for all four cases |
| provider-type-facet-006 | all-cases-enumeration-order, case-set | Enumerate all cases | Returns `[subscription, apiKey, local, custom]`, in that order |
| provider-type-facet-007 | wire-value-lookup, raw-value-identity | Look up the wire value `"apiKey"`; look up the wire value `"bogus"` | Returns `apiKey` for `"apiKey"`; returns no result for `"bogus"` |
| provider-type-facet-008 | config-type-precedence-order, config-type-local-match, config-type-apikey-match | Bucket the Config Type string `"Local API Key"` | Returns `local` — the local rule is checked and matches before the key/token rule is ever reached |

## Edge Cases

- **Empty Config Type string**: Bucketing `""` MUST resolve to `custom`, since the lowercased empty string satisfies none of the six matched substrings (provider-type-facet-002).
- **Multiple rules satisfied at once (boundary of the matching rules)**: A Config Type string satisfying more than one rule's substring test MUST resolve via the fixed evaluation order subscription, then local, then apiKey, then custom; no input can reach a later rule once an earlier one has matched (provider-type-facet-003, provider-type-facet-008).
- **Unrecognized wire value**: A wire-value lookup given a string that is not one of the four case names MUST return no result rather than crash or default to a case (provider-type-facet-007).
- **Malformed JSON during decode**: Decoding a JSON string that is not `"subscription"`, `"apiKey"`, `"local"`, or `"custom"` MUST fail with a decoding error, since decoding is implemented in terms of the wire-value lookup and fails whenever that lookup returns no result.
- **Concurrent access**: Because the facet is a case-only value with no stored mutable state, calling the matching function or the bucketing operation concurrently from multiple threads or execution contexts MUST be safe with no synchronization, since neither function reads or writes shared state.
- **Error states from a dependency**: Not applicable — this concept has no dependency (no network, database, or file-system call) of its own to fail; bucketing is a pure string transform over a value already resolved by the descriptor's Config Type display logic.
- **Offline or disconnected state**: Not applicable — this concept performs no network access of its own.
- **Cancellation and timeouts**: Not applicable — every operation is synchronous and non-throwing; there is no asynchronous or long-running operation to cancel or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configType` | string | none (required) | Parameter to the bucketing operation — the descriptor's Config Type display string to bucket into a facet. |
| `selected` | set of facets | none in this concept (callers default the equivalent parameter to an empty set) | Parameter to the matching function — the set of facets currently checked in the picker's Type filter; an empty set matches every facet. |

## Deep Linking

Not applicable: this concept defines no URL routing, navigation, or scheme handling.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (inline literal, no lookup key) | Subscription | Title for `subscription`; the Type filter's choice label. |
| — (inline literal, no lookup key) | API key | Title for `apiKey`. |
| — (inline literal, no lookup key) | Local LLM | Title for `local`. |
| — (inline literal, no lookup key) | Custom | Title for `custom`. |
| — (inline literal, no lookup key) | Uses an account you already have | Detail for `subscription`; shown as the choice's tooltip/detail text. |
| — (inline literal, no lookup key) | Needs a key from the vendor | Detail for `apiKey`. |
| — (inline literal, no lookup key) | Runs on this machine | Detail for `local`. |
| — (inline literal, no lookup key) | An endpoint you configure yourself | Detail for `custom`. |

All eight strings are hardcoded English literals with no localization lookup mechanism (no string-table, localized-bundle, or string-catalog lookup) anywhere in this concept.

## Accessibility Options

Not applicable: this is a data-only value with no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this concept declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: this concept contains no analytics or event-emission call.

## Privacy

Not applicable: this concept carries no credential or personal data. It buckets a display string (a descriptor's Config Type copy) that is already non-secret vendor-authored metadata; the actual secret value behind an `apiKey`-bucketed provider lives elsewhere, not in this concept.

## Logging

Not applicable: this concept contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not the source, but a straightforward consumer — a SwiftUI Type filter would read `ProviderTypeFacet.allCases` to populate a `Picker`/`Menu`, using `.title` as the label and `.detail` as a subtitle or tooltip, the same data `MultiChoiceFilterButton`'s AppKit consumer already reads at `ProviderPickerViewController.swift`. No `ObservableObject` wrapper is needed since the enum is `Sendable`, `Equatable`, and stateless.
- **Compose**: a Kotlin port models `ProviderTypeFacet` as an `enum class ProviderTypeFacet(val rawValue: String)` with the same four cases, plus a companion factory (e.g. `fromConfigType(configType: String): ProviderTypeFacet`) that reproduces the four-branch, lowercase, ordered `contains` chain exactly — subscription/oauth/account first, then local, then key/token, else custom. `matches` becomes a companion or top-level function over `Set<ProviderTypeFacet>`, and `CaseIterable.allCases` maps to `ProviderTypeFacet.entries`.
- **React/Web**: a TypeScript port models the four cases as a string-literal union (`type ProviderTypeFacet = "subscription" | "apiKey" | "local" | "custom"`); `title`/`detail` become `Record<ProviderTypeFacet, string>` lookup tables; `fromConfigType(configType: string)` reproduces the same lowercased, ordered `includes()` chain; `matches` becomes a plain function testing `selected.size === 0 || selected.has(type)` over a `Set`.
- **AppKit / UIKit**: this is the source, indirectly. `ProviderTypeFacet.swift` itself has no AppKit import, but its only production consumer is `ProviderPickerViewController.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/`): `ProviderPickerRow.type` computes the facet per row from `configType`, `ProviderPickerFilter.filter` narrows rows through `ProviderTypeFacet.matches`, the Type filter button's choices come from `ProviderTypeFacet.allCases.map { .init(id: $0.rawValue, title: $0.title, detail: $0.detail) }`, and a persisted selection is restored via `Set(typeFilter.selection.compactMap(ProviderTypeFacet.init(rawValue:)))`. No iOS/UIKit target exists for `AIPluginKit` today — `project.yml` declares the framework `platform: macOS` only.
- **WinUI 3**: a .NET port models the four cases as `public enum ProviderTypeFacet { Subscription, ApiKey, Local, Custom }` with a `JsonStringEnumConverter` (or an explicit string map) so the wire values stay the lowercase-first `"subscription"`/`"apiKey"`/`"local"`/`"custom"` strings this Swift enum's synthesized `Codable` produces. `Title`/`Detail` become an extension method or a `switch` expression over the enum returning the same eight literal strings. `FromConfigType(string configType)` reproduces the exact four-branch, lowercase-then-`Contains` chain in the same fixed order (config-type-precedence-order); because `string.Contains` is ordinal by default, the port MUST call `.ToLowerInvariant()` first (matching Swift's `.lowercased()`) or pass `StringComparison.OrdinalIgnoreCase` explicitly to reproduce config-type-case-insensitive. `Matches(type, selected)` becomes a static method over `IReadOnlySet<ProviderTypeFacet>`, and `Enum.GetValues<ProviderTypeFacet>()` feeds the `ItemsSource` of the `ComboBox`/toggle-button group standing in for `MultiChoiceFilterButton` in the settings XAML.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/ProviderTypeFacet.swift` |

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
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/providers/. |
