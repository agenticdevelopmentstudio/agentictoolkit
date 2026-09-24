---
id: b360162a-7acb-4354-af85-0f131c84c601
title: ExtensionSettings
domain: agentictoolkit://recipes/extension-host-core-extensions-extension-settings
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Declares the extension host''s one persisted setting: which extension identifiers
  a person has switched off.'
platforms:
- swift
- macos
tags:
- extensions
- settings
- storage-keys
depends-on: []
related:
- agentictoolkit://recipes/extension-host-core-extensions-contributed-settings
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/StorableSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings+Theme.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionSettingsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/SettingsStore/UserDefaultsSettingsStoreTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ExtensionSettings

## Overview

`ExtensionSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift`) is a `@MainActor` extension on `UserSettings` that declares exactly one static property, `disabledExtensionIdentifiers`: a `UserSetting<Set<String>>` keyed `"extensions.disabledIdentifiers"`, defaulting to an empty set. It is the extension host's sole persisted setting — every identifier the set holds names an extension a person has switched off; an identifier the set has never held is enabled, so a freshly installed extension runs with no migration needed.

The file declares no logic of its own. `UserSetting<Value>` (`Core/SettingStorage/UserSetting.swift`), `StorableSetting` (`Core/SettingStorage/StorableSetting.swift`), and `SettingsStore`/`UserSettings` (`Core/SettingStorage/SettingsStore.swift`, `Core/SettingStorage/UserSettings.swift`) supply the read, write, remove, existence-check, and change-notification behavior this property inherits; `UserDefaultsSettingsStorageProvider` (`Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift`) supplies the persistence mechanics. Those files are consulted below only for the contract they give this one property — this recipe covers `ExtensionSettings.swift` alone; the general contract of `UserSetting`, `SettingsStore`, and `UserDefaultsSettingsStorageProvider` is a collaborator's own recipe to write. The enablement logic that reads and writes this set — `ExtensionRegistry.isEnabled`, `setEnabled`, and `uninstall` (`Core/Extensions/ExtensionRegistry.swift`) — is likewise a collaborator's contract, out of scope here.

## Behavioral Requirements

- **disabled-identifiers-key**: `UserSettings.disabledExtensionIdentifiers.name` MUST equal the string `"extensions.disabledIdentifiers"` (`ExtensionSettings.swift:19`; asserted by `ExtensionSettingsTests.theStorageKeyIsPinned`, `ExtensionSettingsTests.swift:21-25`).
- **disabled-identifiers-default**: `UserSettings.disabledExtensionIdentifiers.defaultValue` MUST be an empty `Set<String>` (`ExtensionSettings.swift:20`; asserted by `ExtensionSettingsTests.nothingIsDisabledByDefault`, `ExtensionSettingsTests.swift:31-34`).
- **enabled-by-default**: An identifier that has never been added to the stored value MUST be treated as enabled, because the set records disabled identifiers rather than enabled ones — the doc comment states this is deliberate, so a newly added extension needs no migration (`ExtensionSettings.swift:11-13`).
- **main-actor-isolation**: `disabledExtensionIdentifiers` MUST be read and written only on the main actor. The enclosing `extension UserSettings` is declared `@MainActor` (`ExtensionSettings.swift:8`), and `UserSetting<Value>` is itself a `@MainActor`-isolated class (`UserSetting.swift:11`), so every access is confined and serialized by construction.
- **value-round-trip**: Reading `UserSettings.disabledExtensionIdentifiers.value` MUST return the most recently written `Set<String>` for that key, and writing `.value = newValue` MUST persist `newValue` so a later read returns it — via the `StorableSetting.value` getter/setter (`UserSettings.swift:16-20`), routed through `UserSettings.shared.get`/`set` (`SettingsStore.swift:31-33`, `35-38`).
- **removal-reverts-to-default**: Calling `UserSettings.disabledExtensionIdentifiers.remove()` MUST cause a subsequent read of `.value` to return `defaultValue` (an empty set) — via `StorableSetting.remove()` (`UserSettings.swift:22-24`), routed to `SettingsStore.remove` (`SettingsStore.swift:40-43`) and `UserDefaultsSettingsStorageProvider.remove`, which deletes the stored `UserDefaults` object (`UserDefaultsSettingsStorageProvider.swift:55-58`).
- **existence-check**: `UserSettings.disabledExtensionIdentifiers.existsInStore()` MUST return `true` only once a value has been explicitly stored for `"extensions.disabledIdentifiers"`, and `false` before any write and again after `remove()` — via `StorableSetting.existsInStore()` (`UserSettings.swift:26-28`), routed to `UserDefaultsSettingsStorageProvider.contains`, which checks whether `UserDefaults.object(forKey:)` is non-nil (`UserDefaultsSettingsStorageProvider.swift:60-62`).
- **json-encoded-persistence**: Because `Set<String>` is not one of the types `UserDefaultsSettingsStorageProvider` stores natively — `Int`, `Double`, `Float`, `Bool`, `String`, `Data`, `URL`, `Date` (`UserDefaultsSettingsStorageProvider.swift:65-69`) — a write to `disabledExtensionIdentifiers` MUST be JSON-encoded with `JSONEncoder` and stored as `Data` under the key `"extensions.disabledIdentifiers"`, and a read MUST JSON-decode that `Data` back into a `Set<String>` (`UserDefaultsSettingsStorageProvider.swift:28-42`, `44-53`).
- **not-secure**: `disabledExtensionIdentifiers` MUST be stored through the non-secure `UserDefaultsSettingsStorageProvider`, never the Keychain-backed secure provider. `UserSetting.init` is called with no `isSecure` argument, so `isSecure` defaults to `false` (`ExtensionSettings.swift:18-21`; `UserSetting.swift:28`), and `SettingsStore` dispatches on `key.isSecure` to choose the provider (`SettingsStore.swift:51-54`).
- **corrupt-data-falls-back-to-default**: If the `Data` stored under `"extensions.disabledIdentifiers"` cannot be decoded as `Set<String>`, a read MUST return `defaultValue` (an empty set) rather than throwing or crashing. The decode uses `try?` and falls through to `key.defaultValue` on failure (`UserDefaultsSettingsStorageProvider.swift:36-41`); this fallback is a declared, tested contract of the storage layer itself (`UserDefaultsSettingsStoreTests.testCodableStructFallsBackToDefaultOnCorruptedData`), not a gap particular to this file.
- **change-notification**: A write to `disabledExtensionIdentifiers.value` MUST update `UserSetting.currentValue` (and its `@Published` projection) synchronously, within the same call, before the write's assignment statement returns. `UserDefaultsSettingsStorageProvider.set` stores the value, then sends the key name on a `PassthroughSubject`, which delivers to subscribers synchronously (`UserDefaultsSettingsStorageProvider.swift:44-53`); `UserSetting.init`'s subscription filters for its own name and immediately re-reads and assigns `currentValue`, with no queue hop (`UserSetting.swift:36-41`). This differs from `UserSettingObserver`, whose `onChange` callback explicitly redispatches to `DispatchQueue.main` (`UserSetting.swift:77`) — a detail belonging to that collaborator, named here so a port does not assume the same delay applies to `currentValue` itself.
- **no-identifier-validation**: `disabledExtensionIdentifiers` MUST accept and store any `String` as a member of the set. The declaration performs no check that a stored identifier names an installed or known extension (`ExtensionSettings.swift:18-21`); validating and reconciling identifiers against installed extensions is a caller's responsibility, not this property's.
- **case-sensitive-storage**: The set MUST store identifier strings exactly as given, applying no case-folding of its own. `Set<String>` equality is exact-string equality, so a differently-cased spelling of the same identifier is a distinct member unless a caller folds it before writing (`ExtensionSettings.swift:18-21`).

## Appearance

Not applicable — this is a persisted setting declaration, not a visual component.

## States

Not applicable — this is a persisted setting declaration, not a visual component.

## Accessibility

Not applicable — this is a persisted setting declaration, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-settings-001 | disabled-identifiers-key | Read `UserSettings.disabledExtensionIdentifiers.name` | equals the string `"extensions.disabledIdentifiers"` — mirrors `ExtensionSettingsTests.theStorageKeyIsPinned`, `ExtensionSettingsTests.swift:21-25` |
| extension-settings-002 | disabled-identifiers-default | Read `UserSettings.disabledExtensionIdentifiers.defaultValue` | `.isEmpty == true` — mirrors `ExtensionSettingsTests.nothingIsDisabledByDefault`, `ExtensionSettingsTests.swift:31-34` |
| extension-settings-003 | enabled-by-default, value-round-trip | With no prior write in this run, read `UserSettings.disabledExtensionIdentifiers.value` | equals the empty set, since nothing has been stored yet and `get` falls back to `defaultValue` |
| extension-settings-004 | value-round-trip | Set `.value = ["acme.foo"]`, then read `.value` | equals `{"acme.foo"}` |
| extension-settings-005 | value-round-trip | Set `.value = ["acme.foo", "acme.bar"]`, then set `.value = ["acme.bar"]`, then read `.value` | equals `{"acme.bar"}` — the second write replaces the stored set rather than merging into it |
| extension-settings-006 | removal-reverts-to-default | Set `.value = ["acme.foo"]`, call `.remove()`, then read `.value` | equals the empty set (`defaultValue`) |
| extension-settings-007 | existence-check | Before any write, call `.existsInStore()`; then set `.value = ["acme.foo"]` and call `.existsInStore()` again | first call returns `false`; second call returns `true` |
| extension-settings-008 | existence-check, removal-reverts-to-default | Set `.value = ["acme.foo"]`, call `.remove()`, then call `.existsInStore()` | returns `false` |
| extension-settings-009 | json-encoded-persistence | Set `.value = ["acme.foo", "acme.bar"]`, then inspect the raw object `UserDefaults.standard` holds under the key `"extensions.disabledIdentifiers"` | the stored object is `Data`, not a native array or string; JSON-decoding that `Data` as `Set<String>` yields `{"acme.foo", "acme.bar"}` |
| extension-settings-010 | not-secure | Read `UserSettings.disabledExtensionIdentifiers.isSecure` | equals `false`, confirming writes route through `UserDefaultsSettingsStorageProvider` and never the Keychain-backed provider |
| extension-settings-011 | corrupt-data-falls-back-to-default | Store a JSON payload that does not decode as `Set<String>` (for example the object `{"not":"a set"}`, encoded to `Data`) directly under `"extensions.disabledIdentifiers"` in the backing `UserDefaults`, then read `.value` | returns the empty set (`defaultValue`), with no thrown error — mirrors the storage layer's own `testCodableStructFallsBackToDefaultOnCorruptedData` |
| extension-settings-012 | change-notification | Subscribe to `UserSettings.disabledExtensionIdentifiers.$currentValue`, then set `.value = ["acme.foo"]` | the subscriber observes `{"acme.foo"}` synchronously, before the statement that performed the write returns |
| extension-settings-013 | no-identifier-validation | Set `.value = ["not-a-real-extension-id", ""]` (an unregistered identifier and an empty string) | both are accepted and persisted verbatim; a subsequent read returns exactly `{"not-a-real-extension-id", ""}`, with no error and no filtering |
| extension-settings-014 | case-sensitive-storage | Set `.value = ["Acme.Foo"]`, then evaluate `.value.contains("acme.foo")` | returns `false` — the differently-cased spelling is not treated as the same member |
| extension-settings-015 | main-actor-isolation | From Swift code compiled with strict concurrency checking, attempt to read `.value` from a `nonisolated` context with no `await` | fails to compile, because a `@MainActor`-isolated member cannot be accessed synchronously off the main actor — traced to `ExtensionSettings.swift:8` and `UserSetting.swift:11` |

## Edge Cases

- **Null and empty input**: writing `.value = []` (an explicit empty set) and calling `.remove()` both leave a later read of `.value` returning the empty set; only `.existsInStore()` distinguishes "explicitly emptied" from "never written," because `get` cannot tell the two apart (`no-identifier-validation`'s `get` path, `UserDefaultsSettingsStorageProvider.swift:28-42`). MUST behave this way.
- **Null and empty input — the empty string as a member**: `.value = [""]` is accepted; the empty string is a member like any other, with no special-case rejection (`no-identifier-validation`). MUST behave this way.
- **Boundary values**: the source imposes no maximum on the number of identifiers the set may hold; a set with hundreds of entries is JSON-encoded and stored as one `Data` blob the same way a set with one entry is, because `UserDefaultsSettingsStorageProvider` performs no size check on this path (`UserDefaultsSettingsStorageProvider.swift:44-53`). MUST behave this way.
- **Concurrent access**: every read, write, and remove is confined to the main actor (`main-actor-isolation`), so two calls issued from different `Task`s MUST execute in some serialized order with no interleaving of the underlying `UserDefaults` write — the actor, not this file, is what rules out a data race. MUST behave this way.
- **Error states**: a `JSONEncoder.encode` failure during a write is swallowed — `UserDefaultsSettingsStorageProvider.set` uses `try? encoder.encode(value)` and simply returns, sending no change notification, if encoding fails (`UserDefaultsSettingsStorageProvider.swift:44-49`). For `Set<String>`, encoding a collection of Swift strings does not fail in practice, so this path is unreachable for this specific setting; it is documented here because it is a real behavior of the storage layer this property depends on, not because it is expected to occur. SHOULD be understood as inherited, unreachable-for-this-type behavior, not a gap in `ExtensionSettings.swift`.
- **Offline or disconnected state**: not applicable — `ExtensionSettings.swift` performs no network call of any kind; `UserDefaults` is local, on-device storage with no connectivity dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| storage key | `String` (fixed) | `"extensions.disabledIdentifiers"` | The literal name `UserSetting.init` is constructed with; pinned per `disabled-identifiers-key`, never derived at runtime (`ExtensionSettings.swift:19`). |
| default value | `Set<String>` (fixed) | `[]` | The literal default `UserSetting.init` is constructed with; returned whenever no value has been stored or a stored value cannot be decoded (`ExtensionSettings.swift:20`). |
| `isSecure` | `Bool` (fixed) | `false` | Not passed explicitly at the call site, so `UserSetting.init`'s parameter default applies, routing storage to `UserDefaultsSettingsStorageProvider` rather than the Keychain-backed provider (`ExtensionSettings.swift:18-21`; `UserSetting.swift:28`). |
| `UserSettings.shared` | `UserSettings` (a `SettingsStore`) | a fresh `UserSettings()`, itself defaulting to `UserDefaultsSettingsStorageProvider(defaults: .standard)` and `KeychainSecureSettingsStorageProvider()` | The store `disabledExtensionIdentifiers` reads and writes through. The client app may replace `UserSettings.shared` before first access; the doc comment on `UserSettings.swift:12` states client apps should create and set it (`UserSettings.swift:11-14`; `SettingsStore.swift:17-23`). |

No environment variable is read by this file — it is a plain property declaration with no parameters of its own; the table above lists the fixed values baked into that declaration and the one injected dependency (`UserSettings.shared`) it relies on.

## Deep Linking

Not applicable: `ExtensionSettings.swift` defines no URL, route, or navigable destination — it is a setting declaration with no navigation surface.

## Localization

Not applicable: `ExtensionSettings.swift` produces no user-facing string. It declares a storage key and a default value; the identifiers it stores are internal extension identifiers, not display text, and no string this file owns is ever shown to a person.

## Accessibility Options

Not applicable: `ExtensionSettings.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic — the declaration is unconditional.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

Not applicable: `disabledExtensionIdentifiers` stores extension identifier strings, not a credential or token. `isSecure` is not set at the call site and defaults to `false` (`ExtensionSettings.swift:18-21`; `UserSetting.swift:28`), so the value stays in local `UserDefaults` storage and is never routed to the Keychain, transmitted off-device, or otherwise treated as sensitive.

## Logging

Not applicable: `ExtensionSettings.swift` makes no logging call of its own — no `Logger`, `os_log`, or `print` appears in the file.

## Platform Notes

- **SwiftUI**: not the source, and not a dependency of it. A SwiftUI consumer reads and writes `UserSettings.disabledExtensionIdentifiers.value` exactly like any other caller, or wraps it in the `@ObservedSetting` property wrapper (`Core/SettingStorage/UserSetting.swift`) to bind a view to `currentValue`'s changes; nothing about the declaration is AppKit- or SwiftUI-specific.
- **AppKit / UIKit**: this is the source. `ExtensionSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift`) is part of the macOS-only `AgenticToolkitCore` framework target (`project.yml` declares `platform: macOS` for `AgenticToolkitCore`; no iOS target exists in this repository today, the same scoping the `ContributedSettings` sibling recipe records). The file imports only `Foundation` — no AppKit or UIKit type appears in it, so it would compile unchanged behind a UIKit consumer if the target were extended to iOS.
- **Compose**: model the declaration as a Kotlin `object` property backed by Jetpack `DataStore<Preferences>`, using a `stringSetPreferencesKey("extensions.disabledIdentifiers")` with an empty-set default; mirror `UserSetting`'s get/set/remove/exists surface with `DataStore`'s `Flow`-based read and `edit { }` write, and use `Flow.collect` in place of the Combine `changes` publisher this file's `UserSetting` subscribes to.
- **React/Web**: model it as a small typed wrapper over `localStorage`, storing a JSON-serialized array under the key `"extensions.disabledIdentifiers"` and converting to and from a JavaScript `Set` of strings at the read/write boundary, since `localStorage` has no native set type; use a small pub-sub, or the browser's `storage` event for cross-tab notification, in place of the synchronous Combine update this file's `currentValue` gets.
- **WinUI 3**: the reason this recipe exists. Model the property as a static member on a settings class backed by `Windows.Storage.ApplicationData.Current.LocalSettings.Values`, keyed `"extensions.disabledIdentifiers"`. `ApplicationDataContainer.Values` stores primitives and `String` natively but not a `HashSet<string>` directly, so serialize with `System.Text.Json.JsonSerializer.Serialize` and `Deserialize` into a stored `string` value — the same fallback-to-encoded-payload shape this file's dependency, `UserDefaultsSettingsStorageProvider`, uses for `Data`. Expose the mirrored, observable value through a property that raises `INotifyPropertyChanged`, in place of `UserSetting`'s `@Published currentValue`, and raise that notification synchronously from the setter, on the UI thread, to match this property's synchronous, main-actor-confined update rather than posting to a dispatcher queue. C# has no direct equivalent to `@MainActor`; document the type as UI-thread-affine by convention, or assert `DispatcherQueue.HasThreadAccess` at each entry point, since the compiler enforces nothing here the way Swift's actor isolation does.

## Design Decisions

**Decision**: The setting tracks *disabled* identifiers rather than *enabled* ones.
**Rationale**: the source's own doc comment states this directly — disabled-rather-than-enabled means a freshly installed extension is on by default and needs no migration when a new extension is added (`ExtensionSettings.swift:11-13`). The inverse representation would require seeding every new extension's identifier into an "enabled" set at install time, and anyone who never relaunched after that seeding step would see the new extension as disabled.
**Approved**: pending

**Decision**: The storage key `"extensions.disabledIdentifiers"` is a literal string, declared once, never derived or namespaced further at this layer.
**Rationale**: the source's own doc comment calls the key "load-bearing" and states that changing it orphans every user's existing choices and needs a migration — the same contract `theme.custom_themes` carries (`ExtensionSettings.swift:15-17`; `UserSettings+Theme.swift:16`).
**Approved**: pending

**Decision**: `UserSetting<Set<String>>` is constructed with no `isSecure` argument, so the identifiers persist through `UserDefaults`, not the Keychain.
**Rationale**: an extension identifier is a public, non-sensitive string with nothing to gain from Keychain's confidentiality or access-control guarantees; the call site simply omits the argument and takes `UserSetting.init`'s `false` default (`ExtensionSettings.swift:18-21`; `UserSetting.swift:28`).
**Approved**: pending

**Decision**: `UserSetting.currentValue` updates synchronously, in the same call that writes `.value`, rather than on a redispatched queue turn.
**Rationale**: `UserSetting.init`'s subscription to the store's `changes` publisher applies no scheduling operator, unlike `UserSettingObserver`'s explicit `.receive(on: DispatchQueue.main)` hop (`UserSetting.swift:77`). Recorded here so a port does not assume the observer's dispatched-callback delay also applies to the mirrored `currentValue` itself, which this property exposes directly.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [safe-defaults](agenticdevelopercookbook://compliance/user-safety#safe-defaults) | passed | User Safety |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |

`separation-of-concerns` passes because `ExtensionSettings.swift` declares only the setting's identity and default; the read/write/remove/observe mechanics live in `UserSetting`/`SettingsStore`, the persistence mechanics live in `UserDefaultsSettingsStorageProvider`, and the enablement logic that interprets the set lives in `ExtensionRegistry` — none of that logic is duplicated here. `unit-test-coverage` passes because `ExtensionSettingsTests.swift` asserts both facts this declaration is responsible for: the pinned key string and the empty default, exactly the two properties the file's own doc comments call out as load-bearing. `safe-defaults` passes because the default is an empty set, meaning no extension is silently disabled on a fresh install or after a decode failure — the failure mode and the absent-value case both resolve to "nothing disabled," never to an unpredictable or partially-populated set. `explicit-error-handling` is partial because a decode failure on the stored `Data` (per `corrupt-data-falls-back-to-default`) and an encode failure on a write both fall back silently to a default value or a no-op with no signal surfaced to the caller — safe, but not surfaced, and that behavior is inherited from `UserDefaultsSettingsStorageProvider` rather than handled explicitly by this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
