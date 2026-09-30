<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-provider-type-facet · source: ai-plugin-runtime-ai-plugin-kit-provider-type-facet.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-provider-type-facet#<slug>`):

- `case-set` MUST
- `raw-value-identity` MUST
- `case-iterable-order` MUST
- `sendable-conformance` MUST
- `codable-conformance` MUST
- `equatable-hashable-conformance` MUST
- `rawvalue-initializer` MUST
- `title-strings` MUST
- `detail-strings` MUST
- `config-type-case-insensitive` MUST
- `config-type-subscription-match` MUST
- `config-type-local-match` MUST
- `config-type-apikey-match` MUST
- `config-type-default-custom` MUST
- `config-type-precedence-order` MUST
- `matches-empty-selection` MUST
- `matches-membership` MUST
- `winui-3` MUST — a .NET port models the four cases as public enum ProviderTypeFacet { Subscription, ApiKey, Local, Custom } with a …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configType` | `String` | none (required) | Parameter to `init(configType:)` — the descriptor's Config Type display string (e.g. `AIPluginDescriptor.ProviderTemplate.resolvedConfigType`) to bucket into a facet. |
| `selected` | `Set<ProviderTypeFacet>` | none in this file (callers such as `ProviderPickerFilter.filter` default the equivalent parameter to `[]`) | Parameter to `matches(type:selected:)` — the set of facets currently checked in the picker's Type filter; an empty set matches every facet. |

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

## Platform Notes

- **SwiftUI**: not the source, but a straightforward consumer — a SwiftUI Type filter would read `ProviderTypeFacet.allCases` to populate a `Picker`/`Menu`, using `.title` as the label and `.detail` as a subtitle or tooltip, the same data `MultiChoiceFilterButton`'s AppKit consumer already reads at `ProviderPickerViewController.swift`. No `ObservableObject` wrapper is needed since the enum is `Sendable`, `Equatable`, and stateless.
- **Compose**: a Kotlin port models `ProviderTypeFacet` as an `enum class ProviderTypeFacet(val rawValue: String)` with the same four cases, plus a companion factory (e.g. `fromConfigType(configType: String): ProviderTypeFacet`) that reproduces the four-branch, lowercase, ordered `contains` chain exactly — subscription/oauth/account first, then local, then key/token, else custom. `matches` becomes a companion or top-level function over `Set<ProviderTypeFacet>`, and `CaseIterable.allCases` maps to `ProviderTypeFacet.entries`.
- **React/Web**: a TypeScript port models the four cases as a string-literal union (`type ProviderTypeFacet = "subscription" | "apiKey" | "local" | "custom"`); `title`/`detail` become `Record<ProviderTypeFacet, string>` lookup tables; `fromConfigType(configType: string)` reproduces the same lowercased, ordered `includes()` chain; `matches` becomes a plain function testing `selected.size === 0 || selected.has(type)` over a `Set`.
- **AppKit / UIKit**: this is the source, indirectly. `ProviderTypeFacet.swift` itself has no AppKit import, but its only production consumer is `ProviderPickerViewController.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/`): `ProviderPickerRow.type` computes the facet per row from `configType`, `ProviderPickerFilter.filter` narrows rows through `ProviderTypeFacet.matches`, the Type filter button's choices come from `ProviderTypeFacet.allCases.map { .init(id: $0.rawValue, title: $0.title, detail: $0.detail) }`, and a persisted selection is restored via `Set(typeFilter.selection.compactMap(ProviderTypeFacet.init(rawValue:)))`. No iOS/UIKit target exists for `AIPluginKit` today — `project.yml` declares the framework `platform: macOS` only.
- **WinUI 3**: a .NET port models the four cases as `public enum ProviderTypeFacet { Subscription, ApiKey, Local, Custom }` with a `JsonStringEnumConverter` (or an explicit string map) so the wire values stay the lowercase-first `"subscription"`/`"apiKey"`/`"local"`/`"custom"` strings this Swift enum's synthesized `Codable` produces. `Title`/`Detail` become an extension method or a `switch` expression over the enum returning the same eight literal strings. `FromConfigType(string configType)` reproduces the exact four-branch, lowercase-then-`Contains` chain in the same fixed order (config-type-precedence-order); because `string.Contains` is ordinal by default, the port MUST call `.ToLowerInvariant()` first (matching Swift's `.lowercased()`) or pass `StringComparison.OrdinalIgnoreCase` explicitly to reproduce config-type-case-insensitive. `Matches(type, selected)` becomes a static method over `IReadOnlySet<ProviderTypeFacet>`, and `Enum.GetValues<ProviderTypeFacet>()` feeds the `ItemsSource` of the `ComboBox`/toggle-button group standing in for `MultiChoiceFilterButton` in the settings XAML.

