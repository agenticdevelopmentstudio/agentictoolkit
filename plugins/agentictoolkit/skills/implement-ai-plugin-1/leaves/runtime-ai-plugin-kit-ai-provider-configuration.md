<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-configuration · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-configuration.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-configuration#<slug>`):

- `identifier-assignment` MUST
- `identifier-immutability` MUST
- `identifiable-conformance` MUST
- `display-name-mutability` MUST
- `plugin-and-template-identity-immutability` MUST
- `no-content-validation` MUST
- `codable-conformance` MUST
- `sendable-conformance` MUST
- `equatable-conformance` MUST
- `hashable-conformance` MUST
- `value-semantics` MUST
- `no-persistence` MUST
- `no-registry-validation` MUST
- `unique-name-unchanged-when-free` MUST
- `unique-name-suffix-on-collision` MUST
- `unique-name-suffix-increments` MUST
- `unique-name-static-purity` MUST

# AI Provider Configuration

## Overview

`AIProviderConfiguration.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfiguration.swift`) defines `AIProviderConfiguration`, a small `Codable`, `Sendable`, `Identifiable`, `Equatable`, `Hashable` value type that is, per its own doc comment, "a user's named instance of a provider template: which plugin serves it, which template it was created from, and a display name." It carries exactly four stored properties — `id: UUID`, `name: String`, `pluginIdentifier: String`, `templateId: String` — and nothing else. Per-configuration field values, the selected model, and secrets live in separate stores keyed by `id.uuidString` (see the sibling `AIProviderConfigKeys` component); only identity lives on this type, "so the ordered list is a small plain-Codable array shared by the app and the daemon." The file also defines one static helper, `uniqueName(_:avoiding:)`, that appends a numeric suffix to a candidate display name until the result is not in a caller-supplied set of names already taken. The type performs no I/O, no validation beyond what the Swift compiler enforces, and has no side effect of its own.

## Behavioral Requirements

- **identifier-assignment**: The initializer MUST assign `id` from its `id: UUID = UUID()` parameter, generating a fresh random UUID when the caller omits the argument.
- **identifier-immutability**: `id` MUST NOT change after initialization; it is declared `public let id: UUID`.
- **identifiable-conformance**: The type MUST satisfy `Identifiable` by exposing its `id: UUID` stored property directly as the protocol's `id` requirement, with no separate computed property or indirection.
- **display-name-mutability**: `name` MUST be assignable after initialization; it is declared `public var name: String`, so a caller MAY rename a configuration in place without constructing a new value and without changing `id`, `pluginIdentifier`, or `templateId`.
- **plugin-and-template-identity-immutability**: `pluginIdentifier` and `templateId` MUST NOT change after initialization; both are declared `public let`.
- **no-content-validation**: The initializer MUST accept any `String` value, including an empty string, for `name`, `pluginIdentifier`, and `templateId`; the source performs no format, length, or non-empty check on any of the three.
- **codable-conformance**: The type MUST conform to `Codable` via the compiler-synthesized `init(from:)`/`encode(to:)` over its four stored properties, so a value, or an array of values, encodes to and decodes from JSON with no custom coder.
- **sendable-conformance**: The type MUST conform to `Sendable`; every stored property (`UUID`, `String`, `String`, `String`) is itself `Sendable`, and the type performs no synchronization of its own, so an instance MAY cross an actor or `Task` boundary with no additional guard.
- **equatable-conformance**: The type MUST conform to `Equatable` via the compiler-synthesized memberwise comparison over `id`, `name`, `pluginIdentifier`, and `templateId`; two instances MUST compare unequal whenever any one of the four differs, including two otherwise-identical configurations that differ only in `id`.
- **hashable-conformance**: The type MUST conform to `Hashable` via the compiler-synthesized hash over the same four stored properties, consistent with `equatable-conformance`, so instances MAY be used as `Set` elements or `Dictionary` keys.
- **value-semantics**: The type MUST exhibit full Swift value semantics as a `struct` with no reference-type stored property; assigning or passing an instance MUST copy it, and mutating one copy's `name` MUST NOT affect any other copy or any previously encoded representation.
- **no-persistence**: The type MUST NOT read from or write to `UserDefaults`, the Keychain, a file, or a network endpoint itself; the source declares no such call, and per its own doc comment, a configuration's field values, model, and secrets are persisted elsewhere, keyed by `id.uuidString`.
- **no-registry-validation**: Construction, decoding, and comparison MUST NOT verify that `pluginIdentifier` or `templateId` refers to a currently installed, resolvable plugin or template; the type consults no plugin registry (see Design Decisions).
- **unique-name-unchanged-when-free**: `uniqueName(_:avoiding:)` MUST return `base` unchanged when `taken` does not contain `base`.
- **unique-name-suffix-on-collision**: `uniqueName(_:avoiding:)` MUST return `"\(base) 2"` when `taken` contains `base` but not `"\(base) 2"`.
- **unique-name-suffix-increments**: When `taken` also contains `"\(base) 2"`, `uniqueName(_:avoiding:)` MUST try successive suffixes `3`, `4`, … in order, returning the first candidate `"\(base) \(suffix)"` that `taken` does not contain.
- **unique-name-static-purity**: `uniqueName(_:avoiding:)` MUST be a `static` function with no side effect; it MUST NOT read or write `self`, any stored property, or any external store, deriving its result solely from its two arguments, and returning the identical result for the identical arguments on every call.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | `UUID` | `UUID()` (freshly generated) | Stable identity for a configuration instance, passed to `init(id:name:pluginIdentifier:templateId:)`. |
| `name` | `String` | none (required) | Caller-supplied display name; mutable after construction; no validation. |
| `pluginIdentifier` | `String` | none (required) | Identifies which plugin (an `AIPluginDescriptor.identifier`) serves this configuration; not checked against any registry by this type. |
| `templateId` | `String` | none (required) | Identifies which provider template (a `ProviderTemplate.id`) this configuration was created from; not checked against any registry by this type. |
| `base` (`uniqueName(_:avoiding:)`) | `String` | none (required) | Candidate display name the caller wants made unique. |
| `taken` (`uniqueName(_:avoiding:)`) | `Set<String>` | none (required) | Names already in use that the returned name MUST avoid. |

## Platform Notes

- **SwiftUI**: this is the source's primary consumer pattern. `LLMProvidersListViewModel` (`macOS/Features/AIPlugins/Settings/LLMProvidersListViewModel.swift`), an `@MainActor ObservableObject`, holds `@Published var configurations: [AIProviderConfiguration]` and feeds it straight to SwiftUI list views via the type's own `Identifiable` conformance — no separate `id:` closure is needed in a `ForEach`/`List`. Renaming a row calls `configurations[index].name = uniqueName(trimmed, excluding: id)`, relying on `display-name-mutability` and `value-semantics` so only that one array element's copy changes.
- **AppKit / UIKit**: `AIPluginKit` (the framework target, `project.yml`) targets `platform: macOS` only — there is no iOS target for it today. The AppKit layer never touches `AIProviderConfiguration` directly; it hosts the SwiftUI settings screen and receives `onRequestAddProvider`/`onRequestChat` callbacks from the view model (because "SwiftUI can't present the AppKit sheet" or "reach the window manager itself," per that file's own comments) rather than reading or writing this type's properties.
- **Compose**: model as a Kotlin `data class AIProviderConfiguration(val id: UUID = UUID.randomUUID(), var name: String, val pluginIdentifier: String, val templateId: String)`. A Kotlin `data class` synthesizes `equals`/`hashCode`/`copy` the same way Swift's compiler synthesizes `Equatable`/`Hashable` here, including `id` in the comparison; a `LazyColumn`'s `items(configurations, key = { it.id })` is the analog of the SwiftUI `Identifiable`-driven `ForEach`. Port `uniqueName(_:avoiding:)` as a companion-object function with the same `while` loop.
- **React/Web**: model as a plain TypeScript type, `interface AIProviderConfiguration { id: string; name: string; pluginIdentifier: string; templateId: string }`, with `id` generated via `crypto.randomUUID()`. JavaScript objects have no synthesized structural equality, so port `equatable-conformance`/`hashable-conformance` as an explicit `equalConfigs(a, b)` helper (or a library like a deep-equal check) comparing all four fields — omitting this is the most likely spot a web port silently diverges from `identifier-immutability`'s "different `id` means different configuration" rule. Port `uniqueName(base, taken)` as a pure exported function mirroring the same suffix loop.
- **WinUI 3**: model as a `sealed class AIProviderConfiguration` (not a `record`, so `Name` can remain independently settable while `Id`, `PluginIdentifier`, and `TemplateId` stay `{ get; }`-only) implementing `IEquatable<AIProviderConfiguration>` by comparing all four properties, matching `equatable-conformance`'s inclusion of `Id`: `public Guid Id { get; }`, `public string Name { get; set; }`, `public string PluginIdentifier { get; }`, `public string TemplateId { get; }`, with a constructor defaulting `Id` to `Guid.NewGuid()` the way the Swift initializer defaults to `UUID()`. Use `System.Text.Json`'s `JsonSerializer.Serialize`/`Deserialize<List<AIProviderConfiguration>>` for `codable-conformance`'s JSON round-trip. If the port binds a list of these to a WinUI 3 `ListView`/`ItemsRepeater` through an `ObservableCollection<AIProviderConfiguration>`, note the divergence from the source: mutating `Name` on a class instance already in the collection does **not** raise `CollectionChanged`, and WinUI's binding will not refresh that row unless `AIProviderConfiguration` also implements `INotifyPropertyChanged` for `Name` — the Swift source needs no such mechanism because `@Published var configurations: [AIProviderConfiguration]` re-publishes the whole array by value on every mutation (see `value-semantics`). Port `uniqueName(_:avoiding:)` as `public static string UniqueName(string @base, ISet<string> taken)` with the identical `while (taken.Contains($"{@base} {suffix}")) { suffix++; }` loop.

