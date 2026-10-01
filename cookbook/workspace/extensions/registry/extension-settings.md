---
id: b360162a-7acb-4354-af85-0f131c84c601
title: Extension Settings
domain: agentictoolkit://cookbook/workspace/extensions/registry/extension-settings
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/workspace/extensions/manifest/contributed-settings
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

# Extension Settings

## Overview

The disabled-extensions setting is the extension host's sole persisted setting. It is keyed `"extensions.disabledIdentifiers"` and holds a set of strings, defaulting to an empty set: every identifier the set holds names an extension a person has switched off; an identifier the set has never held is enabled, so a freshly installed extension runs with no migration needed.

This concept declares no logic of its own beyond that one key and default. A general-purpose settings mechanism supplies the read, write, remove, existence-check, and change-notification behavior this setting inherits, and a persistence layer supplies the storage mechanics; both are collaborators covered by their own recipes, out of scope here. The enablement logic that reads and writes this set — deciding whether a given extension is enabled, disabling it, or removing it entirely — is likewise a collaborator's contract, out of scope in this recipe.

## Behavioral Requirements

- **disabled-identifiers-key**: The disabled-extensions setting's storage key MUST equal the string `"extensions.disabledIdentifiers"`.
- **disabled-identifiers-default**: The disabled-extensions setting's default value MUST be an empty set of strings.
- **enabled-by-default**: An identifier that has never been added to the stored set MUST be treated as enabled, because the set records disabled identifiers rather than enabled ones — deliberately, so a newly added extension needs no migration.
- **thread-confined-access**: The disabled-extensions setting MUST be read and written only from a single, serialized execution context, so that no two accesses interleave.
- **value-round-trip**: Reading the setting's current value MUST return the most recently written set of identifiers for that key, and writing a new value MUST persist it so a later read returns it.
- **removal-reverts-to-default**: Removing the setting's stored value MUST cause a subsequent read of its value to return the default value (an empty set).
- **existence-check**: Checking whether a value has been explicitly stored for the setting MUST answer true only once a value has been explicitly stored under its key, and false before any write and again after removal.
- **json-encoded-persistence**: Because a set of strings is not one of the primitive types the underlying storage mechanism holds natively, a write to the setting MUST be serialized into a portable encoded form (for example JSON) and stored as an opaque blob under its key, and a read MUST decode that blob back into a set of strings.
- **not-secure**: The setting MUST be stored through the ordinary, non-secure settings storage path, never a secure, credential-store-backed one.
- **corrupt-data-falls-back-to-default**: If the blob stored under the setting's key cannot be decoded back into a set of strings, a read MUST return the default value (an empty set) rather than throwing or crashing.
- **change-notification**: A write to the setting's value MUST update any observable projection of its current value synchronously, within the same call, before the write's statement returns.
- **no-identifier-validation**: The setting MUST accept and store any string as a member of the set. It performs no check that a stored identifier names an installed or known extension; validating and reconciling identifiers against installed extensions is a caller's responsibility, not this setting's.
- **case-sensitive-storage**: The set MUST store identifier strings exactly as given, applying no case-folding of its own. Membership is exact-string equality, so a differently-cased spelling of the same identifier is a distinct member unless a caller folds it before writing.

## Appearance

Not applicable — this is a persisted setting declaration, not a visual component.

## States

Not applicable — this is a persisted setting declaration, not a visual component.

## Accessibility

Not applicable — this is a persisted setting declaration, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-settings-001 | disabled-identifiers-key | Read the setting's storage key | equals the string `"extensions.disabledIdentifiers"` |
| extension-settings-002 | disabled-identifiers-default | Read the setting's default value | is empty |
| extension-settings-003 | enabled-by-default, value-round-trip | With no prior write in this run, read the setting's current value | equals the empty set, since nothing has been stored yet and a read falls back to the default value |
| extension-settings-004 | value-round-trip | Write `{"acme.foo"}` as the value, then read the value | equals `{"acme.foo"}` |
| extension-settings-005 | value-round-trip | Write `{"acme.foo", "acme.bar"}`, then write `{"acme.bar"}`, then read the value | equals `{"acme.bar"}` — the second write replaces the stored set rather than merging into it |
| extension-settings-006 | removal-reverts-to-default | Write `{"acme.foo"}`, remove the stored value, then read the value | equals the empty set (the default value) |
| extension-settings-007 | existence-check | Before any write, check whether a value has been stored; then write `{"acme.foo"}` and check again | first check answers false; second check answers true |
| extension-settings-008 | existence-check, removal-reverts-to-default | Write `{"acme.foo"}`, remove the stored value, then check whether a value has been stored | answers false |
| extension-settings-009 | json-encoded-persistence | Write `{"acme.foo", "acme.bar"}`, then inspect the raw object the underlying storage holds under the setting's key | the stored object is an opaque encoded blob, not a native array or string; decoding that blob as a set of strings yields `{"acme.foo", "acme.bar"}` |
| extension-settings-010 | not-secure | Read whether the setting is flagged secure | answers false, confirming writes route through the non-secure storage path and never a secure, credential-store-backed one |
| extension-settings-011 | corrupt-data-falls-back-to-default | Store a payload that does not decode as a set of strings (for example an object shaped `{"not":"a set"}`) directly under the setting's key in the underlying storage, then read the value | returns the empty set (the default value), with no thrown error |
| extension-settings-012 | change-notification | Observe the setting's current value, then write `{"acme.foo"}` | the observer sees `{"acme.foo"}` synchronously, before the statement that performed the write returns |
| extension-settings-013 | no-identifier-validation | Write `{"not-a-real-extension-id", ""}` (an unregistered identifier and an empty string) | both are accepted and persisted verbatim; a subsequent read returns exactly `{"not-a-real-extension-id", ""}`, with no error and no filtering |
| extension-settings-014 | case-sensitive-storage | Write `{"Acme.Foo"}`, then check whether the value contains `"acme.foo"` | answers false — the differently-cased spelling is not treated as the same member |
| extension-settings-015 | thread-confined-access | Attempt to read the setting's value from outside its confined execution context, with no synchronization | is refused (on a platform that enforces this statically, this is a compile-time error) |

## Edge Cases

- **Null and empty input**: writing an explicit empty set and removing the stored value both leave a later read of the value returning the empty set; only the existence check distinguishes "explicitly emptied" from "never written," because a plain read cannot tell the two apart. MUST behave this way.
- **Null and empty input — the empty string as a member**: writing `{""}` is accepted; the empty string is a member like any other, with no special-case rejection. MUST behave this way.
- **Boundary values**: no maximum is imposed on the number of identifiers the set may hold; a set with hundreds of entries is encoded and stored as one blob the same way a set with one entry is — no size check is performed on this path. MUST behave this way.
- **Concurrent access**: every read, write, and removal is confined to a single execution context, so two accesses issued concurrently MUST execute in some serialized order with no interleaving of the underlying write. MUST behave this way.
- **Error states**: an encoding failure during a write is swallowed — the write simply returns, sending no change notification, if encoding fails. For a set of strings, encoding a collection of ordinary strings does not fail in practice, so this path is unreachable for this specific setting; it is documented here because it is a real behavior of the storage layer this setting depends on, not because it is expected to occur. SHOULD be understood as inherited, unreachable-for-this-type behavior, not a gap in the setting's own declaration.
- **Offline or disconnected state**: not applicable — this setting performs no network call of any kind; its storage is local, on-device storage with no connectivity dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| storage key | string (fixed) | `"extensions.disabledIdentifiers"` | The literal name the setting is declared with; pinned per **disabled-identifiers-key**, never derived at runtime. |
| default value | set of strings (fixed) | `[]` | The literal default the setting is declared with; returned whenever no value has been stored or a stored value cannot be decoded. |
| secure-storage flag | boolean (fixed) | `false` | Routes storage to the non-secure storage path rather than a secure, credential-store-backed one. |
| settings store | the store the setting reads and writes through | a default store backed by non-secure local storage and a secure, credential-store-backed provider | The host app may substitute a different store instance before the setting is first accessed. |

No environment variable is read by this declaration — it is a plain setting declaration with no parameters of its own; the table above lists the fixed values baked into that declaration and the one injected dependency (the settings store) it relies on.

## Deep Linking

Not applicable: this concept defines no URL, route, or navigable destination — it is a setting declaration with no navigation surface.

## Localization

Not applicable: this concept produces no user-facing string. It declares a storage key and a default value; the identifiers it stores are internal extension identifiers, not display text, and no string it owns is ever shown to a person.

## Accessibility Options

Not applicable: this concept renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the declaration is unconditional and gates on no feature-flag key.

## Analytics

Not applicable: this concept emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: the disabled-extensions setting stores extension identifier strings, not a credential or token. It is not flagged secure, so the value stays in local, non-secure storage and is never routed to secure/credential storage, transmitted off-device, or otherwise treated as sensitive.

## Logging

Not applicable: this concept makes no logging call of its own.

## Platform Notes

- **SwiftUI**: not the source, and not a dependency of it. A SwiftUI consumer reads and writes `UserSettings.disabledExtensionIdentifiers.value` exactly like any other caller, or wraps it in the `@ObservedSetting` property wrapper (`Core/SettingStorage/UserSetting.swift`) to bind a view to `currentValue`'s changes; nothing about the declaration is AppKit- or SwiftUI-specific.
- **AppKit / UIKit**: this is the source. `ExtensionSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift`) is a `@MainActor` extension on `UserSettings` that declares exactly one static property, `disabledExtensionIdentifiers`: a `UserSetting<Set<String>>` keyed `"extensions.disabledIdentifiers"`, defaulting to an empty set. It is part of the macOS-only `AgenticToolkitCore` framework target (`project.yml` declares `platform: macOS` for `AgenticToolkitCore`; no iOS target exists in this repository today, the same scoping the `ContributedSettings` sibling recipe records). The file imports only `Foundation` — no AppKit or UIKit type appears in it, so it would compile unchanged behind a UIKit consumer if the target were extended to iOS. The thread-confinement requirement is enforced by `@MainActor`: the enclosing `extension UserSettings` is declared `@MainActor`, and `UserSetting<Value>` (`Core/SettingStorage/UserSetting.swift`) is itself a `@MainActor`-isolated class, so every access is confined and serialized by construction. `UserSetting<Value>`, `StorableSetting` (`Core/SettingStorage/StorableSetting.swift`), and `SettingsStore`/`UserSettings` (`Core/SettingStorage/SettingsStore.swift`, `Core/SettingStorage/UserSettings.swift`) supply the read/write/remove/existence-check/change-notification behavior; `UserDefaultsSettingsStorageProvider` (`Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift`) supplies the persistence mechanics, JSON-encoding a `Set<String>` (via `JSONEncoder`/`JSONDecoder`) since it is not one of the types stored natively (`Int`, `Double`, `Float`, `Bool`, `String`, `Data`, `URL`, `Date`), falling back to `defaultValue` with `try?` on a decode failure. `isSecure` is not passed at the call site, so `UserSetting.init`'s `false` default routes storage away from the Keychain-backed secure provider. Change notification is synchronous: `UserDefaultsSettingsStorageProvider.set` stores the value, then sends the key name on a `PassthroughSubject`, which delivers to subscribers synchronously; `UserSetting.init`'s subscription filters for its own name and immediately re-reads and assigns `currentValue`, with no queue hop — unlike `UserSettingObserver`, whose `onChange` callback explicitly redispatches to `DispatchQueue.main`.
- **Compose**: model the declaration as a Kotlin `object` property backed by Jetpack `DataStore<Preferences>`, using a `stringSetPreferencesKey("extensions.disabledIdentifiers")` with an empty-set default; mirror the general setting mechanism's get/set/remove/exists surface with `DataStore`'s `Flow`-based read and `edit { }` write, and use `Flow.collect` in place of the Combine `changes` publisher this declaration's setting mechanism subscribes to.
- **React/Web**: model it as a small typed wrapper over `localStorage`, storing a JSON-serialized array under the key `"extensions.disabledIdentifiers"` and converting to and from a JavaScript `Set` of strings at the read/write boundary, since `localStorage` has no native set type; use a small pub-sub, or the browser's `storage` event for cross-tab notification, in place of the synchronous update this declaration's mechanism gets.
- **WinUI 3**: the reason this recipe exists. Model the property as a static member on a settings class backed by `Windows.Storage.ApplicationData.Current.LocalSettings.Values`, keyed `"extensions.disabledIdentifiers"`. `ApplicationDataContainer.Values` stores primitives and `String` natively but not a `HashSet<string>` directly, so serialize with `System.Text.Json.JsonSerializer.Serialize` and `Deserialize` into a stored `string` value — the same fallback-to-encoded-payload shape this declaration's dependency, `UserDefaultsSettingsStorageProvider`, uses for `Data`. Expose the mirrored, observable value through a property that raises `INotifyPropertyChanged`, in place of the setting mechanism's `@Published currentValue`, and raise that notification synchronously from the setter, on the UI thread, to match this setting's synchronous, thread-confined update rather than posting to a dispatcher queue. C# has no direct equivalent to `@MainActor`; document the type as UI-thread-affine by convention, or assert `DispatcherQueue.HasThreadAccess` at each entry point, since the compiler enforces nothing here the way Swift's actor isolation does.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift` |

## Design Decisions

**Decision**: The setting tracks *disabled* identifiers rather than *enabled* ones.
**Rationale**: disabled-rather-than-enabled means a freshly installed extension is on by default and needs no migration when a new extension is added. The inverse representation would require seeding every new extension's identifier into an "enabled" set at install time, and anyone who never relaunched after that seeding step would see the new extension as disabled.
**Approved**: pending

**Decision**: The storage key `"extensions.disabledIdentifiers"` is a literal string, declared once, never derived or namespaced further at this layer.
**Rationale**: the key is load-bearing — changing it orphans every user's existing choices and needs a migration — the same contract a stored theme-customization key carries elsewhere in this settings layer.
**Approved**: pending

**Decision** (Swift/AppKit implementation): the setting is constructed with no secure-storage flag, so the identifiers persist through the ordinary settings store, not the Keychain.
**Rationale**: an extension identifier is a public, non-sensitive string with nothing to gain from Keychain's confidentiality or access-control guarantees; the call site simply omits the flag and takes the setting mechanism's `false` default.
**Approved**: pending

**Decision** (Swift/AppKit implementation): the setting's observable current value updates synchronously, in the same call that writes the value, rather than on a redispatched queue turn.
**Rationale**: the setting mechanism's subscription to the store's change publisher applies no scheduling operator, unlike its observer helper's explicit main-queue redispatch. Recorded here so a port does not assume the observer's dispatched-callback delay also applies to the mirrored current value itself, which this setting exposes directly.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/registry/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
