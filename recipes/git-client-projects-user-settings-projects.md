---
id: 03a30e6b-8c8c-40d3-8135-078d4fd351ce
title: UserSettings+Projects
domain: agentictoolkit://recipes/git-client-projects-user-settings-projects
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Declares the Projects feature''s three persisted UserSettings: repo-scan
  skip patterns, active-pane outline, and pointer-follows-focus.'
platforms:
- swift
- macos
tags:
- git
- projects
- settings
- storage-keys
depends-on: []
related:
- agentictoolkit://recipes/git-client-projects-git-repo-scanner
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/StorableSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepoScanner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/SettingsStore/UserDefaultsSettingsStoreTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# UserSettings+Projects

## Overview

`UserSettings+Projects.swift` (`packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift`) is an extension on `UserSettings` that declares three persisted settings for the Projects feature: `projectScanSkipPatterns`, a `UserSetting<[String]>` keyed `"projectScanSkipPatterns"` that defaults to `GitRepoScanner.defaultRootSkipPatterns`; `highlightActivePane`, a `UserSetting<Bool>` keyed `"highlight_active_pane"` that defaults to `true`; and `activePaneFollowsMouse`, a `UserSetting<Bool>` keyed `"active_pane_follows_mouse"` that defaults to `false`. Each is a plain property declaration with no logic of its own — no validation, no side effect beyond what `UserSetting` and its underlying store already provide.

The file declares no read, write, remove, or observe mechanics of its own. `UserSetting<Value>` (`Core/SettingStorage/UserSetting.swift`), `StorableSetting` (`Core/SettingStorage/StorableSetting.swift`), and `SettingsStore`/`UserSettings` (`Core/SettingStorage/SettingsStore.swift`, `Core/SettingStorage/UserSettings.swift`) supply that behavior; `UserDefaultsSettingsStorageProvider` (`Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift`) supplies the persistence mechanics. This recipe covers those collaborators only for the contract they give these three properties — their own general contract belongs to a collaborator's own recipe (the [GitRepoScanner](agentictoolkit://recipes/git-client-projects-git-repo-scanner) recipe already covers the scanner that consumes `projectScanSkipPatterns`). The code that reads `projectScanSkipPatterns` and constructs a scanner from it (`ProjectsCoordinator.swift`), the settings panel that edits all three (`ProjectsSettingsPanelViewController.swift`), and the per-project override that can supersede `highlightActivePane` (`ThemeProjectOptions`, consumed in `ComposableTabsActivePane.swift`) are likewise collaborators' own contracts, out of scope here except where this file's own doc comments make a claim about them.

## Behavioral Requirements

- **skip-patterns-key**: `UserSettings.projectScanSkipPatterns.name` MUST equal the string `"projectScanSkipPatterns"` (`UserSettings+Projects.swift`).
- **skip-patterns-default**: `UserSettings.projectScanSkipPatterns.defaultValue` MUST equal `GitRepoScanner.defaultRootSkipPatterns` — the literal array `["Library", "Music", "Pictures", "Movies", "Dropbox", "* Dropbox", "Google Drive"]` (`UserSettings+Projects.swift`; `GitRepoScanner.swift`).
- **highlight-active-pane-key**: `UserSettings.highlightActivePane.name` MUST equal the string `"highlight_active_pane"` (`UserSettings+Projects.swift`).
- **highlight-active-pane-default**: `UserSettings.highlightActivePane.defaultValue` MUST equal `true` (`UserSettings+Projects.swift`).
- **follows-mouse-key**: `UserSettings.activePaneFollowsMouse.name` MUST equal the string `"active_pane_follows_mouse"` (`UserSettings+Projects.swift`).
- **follows-mouse-default**: `UserSettings.activePaneFollowsMouse.defaultValue` MUST equal `false` (`UserSettings+Projects.swift`).
- **main-actor-isolation**: All three settings MUST be read and written only on the main actor. `UserSettings+Projects.swift` adds these static properties to `UserSettings` with no `@MainActor` attribute of its own, but `UserSettings` carries that attribute at its primary declaration (`UserSettings.swift`), and `UserSetting<Value>` is itself a `@MainActor`-isolated class (`UserSetting.swift`); the isolation reaches these three properties by inheritance from the extended type rather than by an attribute repeated in this file.
- **value-round-trip**: For each of the three settings, reading `.value` MUST return the most recently written value for that key, and writing `.value = newValue` MUST persist `newValue` so a later read returns it — via the `StorableSetting.value` getter/setter (`UserSettings.swift`), routed through `UserSettings.shared.get`/`set` (`SettingsStore.swift`, `35-38`).
- **removal-reverts-to-default**: Calling `.remove()` on any of the three settings MUST cause a subsequent read of `.value` to return that property's own `defaultValue` — via `StorableSetting.remove()` (`UserSettings.swift`), routed to `SettingsStore.remove` (`SettingsStore.swift`) and the storage provider's own removal.
- **existence-check**: `.existsInStore()` MUST return `true` only once a value has been explicitly stored for that setting's key, and `false` before any write and again after `.remove()` — via `StorableSetting.existsInStore()` (`UserSettings.swift`).
- **array-setting-json-encoded**: Because `[String]` is not one of the types `UserDefaultsSettingsStorageProvider` stores natively — `Int`, `Double`, `Float`, `Bool`, `String`, `Data`, `URL`, `Date` (`UserDefaultsSettingsStorageProvider.swift`) — a write to `projectScanSkipPatterns` MUST be JSON-encoded and stored as `Data` under the key `"projectScanSkipPatterns"`, and a read MUST JSON-decode that `Data` back into a `[String]` (`UserDefaultsSettingsStorageProvider.swift`, `44-53`).
- **bool-settings-natively-stored**: Because `Bool` is one of the types `UserDefaultsSettingsStorageProvider` stores natively, a write to `highlightActivePane` or `activePaneFollowsMouse` MUST be stored directly as a native `Bool` object under that setting's key, with no JSON encoding (`UserDefaultsSettingsStorageProvider.swift`, `44-46`, `65-69`).
- **not-secure**: All three settings MUST be stored through the non-secure `UserDefaultsSettingsStorageProvider`, never the Keychain-backed secure provider. None of the three `UserSetting.init` calls passes an `isSecure` argument, so `isSecure` defaults to `false` for each (`UserSettings+Projects.swift`; `UserSetting.swift`), and `SettingsStore` dispatches on `key.isSecure` to choose the provider (`SettingsStore.swift`).
- **corrupt-data-falls-back-to-default**: If the stored value for any of the three keys cannot be read back as that setting's `Value` type — undecodable `Data` for `projectScanSkipPatterns`, or an object that fails an `as? Bool` cast for the other two — a read MUST return that setting's `defaultValue` rather than throwing or crashing, via `UserDefaultsSettingsStorageProvider.get`'s fallthrough to `key.defaultValue` (`UserDefaultsSettingsStorageProvider.swift`).
- **change-notification**: A write to any of the three settings' `.value` MUST update that `UserSetting`'s `currentValue` (and its `@Published` projection) synchronously, within the same call, before the write's assignment statement returns. `UserDefaultsSettingsStorageProvider.set` stores the value, then sends the key name on a `PassthroughSubject`, delivered synchronously; `UserSetting.init`'s subscription filters for its own name and immediately re-reads and assigns `currentValue`, with no queue hop (`UserDefaultsSettingsStorageProvider.swift`; `UserSetting.swift`).
- **no-pattern-validation**: `projectScanSkipPatterns` MUST accept and store any `[String]` as its value, including empty strings, duplicate entries, and strings that are not valid `fnmatch` glob syntax. The declaration performs no check of its own on the strings it stores (`UserSettings+Projects.swift`); the doc comment states the scanner is handed this list as a plain parameter specifically so its own walk logic — not this setting — can be tested independently of a settings store.
- **highlight-active-pane-override**: `highlightActivePane`'s own doc comment states that a per-project `ThemeProjectOptions.highlightActivePane` overrides it (`UserSettings+Projects.swift`); the consumer that implements this precedence reads `overrides?.highlightActivePane ?? UserSettings.highlightActivePane.value` (`ComposableTabsActivePane.swift`), confirming that, when present, the override MUST take precedence over this setting's value.

## Appearance

Not applicable — this is a persisted setting declaration, not a visual component.

## States

Not applicable — this is a persisted setting declaration, not a visual component.

## Accessibility

Not applicable — this is a persisted setting declaration, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-user-settings-projects-001 | skip-patterns-key | Read `UserSettings.projectScanSkipPatterns.name` | equals the string `"projectScanSkipPatterns"` |
| git-client-projects-user-settings-projects-002 | skip-patterns-default | Read `UserSettings.projectScanSkipPatterns.defaultValue` | equals `["Library", "Music", "Pictures", "Movies", "Dropbox", "* Dropbox", "Google Drive"]` |
| git-client-projects-user-settings-projects-003 | highlight-active-pane-key, highlight-active-pane-default | Read `UserSettings.highlightActivePane.name` and `.defaultValue` | `name` equals `"highlight_active_pane"`; `defaultValue` equals `true` |
| git-client-projects-user-settings-projects-004 | follows-mouse-key, follows-mouse-default | Read `UserSettings.activePaneFollowsMouse.name` and `.defaultValue` | `name` equals `"active_pane_follows_mouse"`; `defaultValue` equals `false` |
| git-client-projects-user-settings-projects-005 | value-round-trip | Set `UserSettings.projectScanSkipPatterns.value = ["Archive*"]`, then read `.value` | equals `["Archive*"]` |
| git-client-projects-user-settings-projects-006 | value-round-trip | Set `UserSettings.highlightActivePane.value = false`, then read `.value` | equals `false` |
| git-client-projects-user-settings-projects-007 | array-setting-json-encoded | Set `UserSettings.projectScanSkipPatterns.value = ["Foo"]`, then inspect the raw object `UserDefaults.standard` holds under `"projectScanSkipPatterns"` | the stored object is `Data`, not a native array; JSON-decoding that `Data` as `[String]` yields `["Foo"]` |
| git-client-projects-user-settings-projects-008 | bool-settings-natively-stored | Set `UserSettings.highlightActivePane.value = false`, then inspect the raw object `UserDefaults.standard` holds under `"highlight_active_pane"` | the stored object casts directly to `Bool` (`false`), not `Data` |
| git-client-projects-user-settings-projects-009 | removal-reverts-to-default | Set `UserSettings.activePaneFollowsMouse.value = true`, call `.remove()`, then read `.value` | equals `false` (`defaultValue`) |
| git-client-projects-user-settings-projects-010 | existence-check | Before any write, call `UserSettings.highlightActivePane.existsInStore()`; then set `.value = false` and call it again | first call returns `false`; second call returns `true` |
| git-client-projects-user-settings-projects-011 | not-secure | Read `.isSecure` on all three settings | each equals `false` |
| git-client-projects-user-settings-projects-012 | corrupt-data-falls-back-to-default | Store a JSON payload that does not decode as `[String]` (for example an encoded object, not an array) directly under `"projectScanSkipPatterns"` in the backing `UserDefaults`, then read `.value` | returns `GitRepoScanner.defaultRootSkipPatterns` (`defaultValue`), with no thrown error |
| git-client-projects-user-settings-projects-013 | change-notification | Subscribe to `UserSettings.highlightActivePane.$currentValue`, then set `.value = false` | the subscriber observes `false` synchronously, before the statement that performed the write returns |
| git-client-projects-user-settings-projects-014 | no-pattern-validation | Set `UserSettings.projectScanSkipPatterns.value = ["", "not [a valid glob", "dup", "dup"]` | all four entries are accepted and persisted verbatim, in order, with no filtering or deduplication |
| git-client-projects-user-settings-projects-015 | main-actor-isolation | From Swift code compiled with strict concurrency checking, attempt to read `UserSettings.highlightActivePane.value` from a `nonisolated` context with no `await` | fails to compile, because a `@MainActor`-isolated member cannot be accessed synchronously off the main actor — traced to `UserSettings.swift` and `UserSetting.swift` |

## Edge Cases

- **Null and empty input**: setting `projectScanSkipPatterns.value = []` (an explicit empty array) leaves a later read of `.value` returning `[]`; calling `.remove()` instead leaves a later read returning the non-empty `GitRepoScanner.defaultRootSkipPatterns` list, because `removal-reverts-to-default` reverts to whatever `defaultValue` is, not to an empty array (`UserSettings+Projects.swift`). The empty string is also accepted as an ordinary member of the list, with no special-case rejection (`no-pattern-validation`). MUST behave this way.
- **Boundary values**: the source imposes no maximum on the number of entries in `projectScanSkipPatterns` or on the length of any one entry; a list with hundreds of patterns is JSON-encoded and stored as one `Data` blob the same way a single-entry list is (`array-setting-json-encoded`). MUST behave this way.
- **Concurrent access**: every read, write, and remove on all three settings is confined to the main actor (`main-actor-isolation`), so two calls issued from different `Task`s MUST execute in some serialized order with no interleaving of the underlying `UserDefaults` access — the actor, not this file, is what rules out a data race. MUST behave this way.
- **Error states**: a `JSONEncoder.encode` failure during a write to `projectScanSkipPatterns` is swallowed — `UserDefaultsSettingsStorageProvider.set` uses `try? encoder.encode(value)` and simply returns, sending no change notification, if encoding fails (`UserDefaultsSettingsStorageProvider.swift`). Encoding a `[String]` of ordinary Swift strings does not fail in practice, so this path is unreachable for this specific setting; it is documented here because it is a real, inherited behavior of the storage layer this property depends on, not because it is expected to occur. SHOULD be understood as inherited, unreachable-for-this-type behavior, not a gap in `UserSettings+Projects.swift`.
- **Offline or disconnected state**: not applicable — `UserSettings+Projects.swift` performs no network call of any kind; `UserDefaults` is local, on-device storage with no connectivity dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `projectScanSkipPatterns` storage key | `String` (fixed) | `"projectScanSkipPatterns"` | The literal name `UserSetting.init` is constructed with; pinned per `skip-patterns-key` (`UserSettings+Projects.swift`). |
| `projectScanSkipPatterns` default | `[String]` (fixed) | `GitRepoScanner.defaultRootSkipPatterns` | Returned whenever no value has been stored or a stored value cannot be decoded (`UserSettings+Projects.swift`). |
| `highlightActivePane` storage key | `String` (fixed) | `"highlight_active_pane"` | Pinned per `highlight-active-pane-key` (`UserSettings+Projects.swift`). |
| `highlightActivePane` default | `Bool` (fixed) | `true` | Returned whenever no value has been stored (`UserSettings+Projects.swift`). |
| `activePaneFollowsMouse` storage key | `String` (fixed) | `"active_pane_follows_mouse"` | Pinned per `follows-mouse-key` (`UserSettings+Projects.swift`). |
| `activePaneFollowsMouse` default | `Bool` (fixed) | `false` | Returned whenever no value has been stored (`UserSettings+Projects.swift`). |
| `isSecure` (all three) | `Bool` (fixed) | `false` | Not passed explicitly at any of the three call sites, so `UserSetting.init`'s parameter default applies, routing all three through `UserDefaultsSettingsStorageProvider` rather than the Keychain-backed provider (`UserSettings+Projects.swift`; `UserSetting.swift`). |
| `UserSettings.shared` | `UserSettings` (a `SettingsStore`) | a fresh `UserSettings()`, itself defaulting to `UserDefaultsSettingsStorageProvider(defaults: .standard)` and `KeychainSecureSettingsStorageProvider()` | The store all three settings read and write through. The client app may replace `UserSettings.shared` before first access (`UserSettings.swift`; `SettingsStore.swift`). |

No environment variable is read by this file — it is three plain property declarations with no parameters of their own; `ProjectsCoordinator.swift` is the one caller that reads `UserSettings.projectScanSkipPatterns.currentValue` and passes it into `GitRepoScanner`'s own `rootSkipPatterns` initializer parameter, but that wiring lives outside this component's own file and is not part of its contract.

## Deep Linking

Not applicable: `UserSettings+Projects.swift` defines no URL scheme, route, or navigation destination.

## Localization

Not applicable: `UserSettings+Projects.swift` produces no user-facing string of its own. Its three properties store a key name, a default value, and, through `UserSetting`, a way to read and write that value — none of which is displayed text; the settings panel that shows English labels for these values (`ProjectsSettingsPanelViewController.swift`) is a separate file with its own recipe to write.

## Accessibility Options

Not applicable: `UserSettings+Projects.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI surface of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic — all three declarations are unconditional.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `projectScanSkipPatterns` stores folder-name and glob-pattern strings the user has typed or accepted, which can reveal something about how the user organizes their home directory; `highlightActivePane` and `activePaneFollowsMouse` store two boolean UI preferences with no descriptive content of their own (`UserSettings+Projects.swift`).
- **Storage**: all three values live in local `UserDefaults` storage only. `isSecure` is not set at any of the three call sites and defaults to `false` (`UserSetting.swift`), so none of the three is routed to the Keychain (`not-secure`).
- **Transmission**: none — `UserSettings+Projects.swift` makes no network call and transmits nothing.
- **Retention**: each value persists until explicitly overwritten, removed with `.remove()`, or the app's `UserDefaults` domain is deleted; the file itself defines no expiry or automatic cleanup.

## Logging

Not applicable: `UserSettings+Projects.swift` makes no logging call of its own — no `Logger`, `os_log`, or `print` appears in the file.

## Platform Notes

- **SwiftUI**: the source is `packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift`, part of the macOS-only `AgenticToolkitMacOS` target (`project.yml`), importing `AgenticToolkitCore` for `UserSettings`/`UserSetting` and referring to its target-mate `GitRepoScanner.defaultRootSkipPatterns` with no import needed. Nothing here is SwiftUI-specific — the three properties have no view and no state beyond what `UserSetting` already provides; a SwiftUI consumer would bind to them through the `@ObservedSetting` property wrapper (`Core/SettingStorage/UserSetting.swift`).
- **AppKit / UIKit**: this is the source. The file imports only `Foundation` and `AgenticToolkitCore` — no AppKit or UIKit type appears in it, so it would compile unchanged behind a UIKit consumer if the target were extended to iOS. Its first setting's default, however, reaches into `GitRepoScanner.defaultRootSkipPatterns`, and that scanner's own recipe records that an iOS port would need a different filesystem-access model (a user-picked folder or a security-scoped bookmark) rather than the Home-directory scan this default list assumes.
- **Compose**: model the three properties as members of a Kotlin `object` backed by Jetpack `DataStore<Preferences>`. `booleanPreferencesKey("highlight_active_pane")` and `booleanPreferencesKey("active_pane_follows_mouse")` map directly onto the two `Bool` settings. `DataStore`'s native `stringSetPreferencesKey` stores an unordered `Set<String>`, which would silently drop the order-preserving, duplicate-permitting semantics `no-pattern-validation` and `array-setting-json-encoded` describe for `projectScanSkipPatterns` — use a JSON-serialized `stringPreferencesKey("projectScanSkipPatterns")` instead, and decode/encode a `List<String>` at the boundary, to preserve those semantics. Mirror `UserSetting`'s get/set/remove/exists surface with `DataStore`'s `Flow`-based read and `edit { }` write.
- **React/Web**: model the three properties as a small typed wrapper over `localStorage`, since a browser has no direct filesystem-scanning use for `projectScanSkipPatterns` but the setting itself is just a stored list. Store `projectScanSkipPatterns` as a JSON-serialized array under the key `"projectScanSkipPatterns"`, and the two booleans as JSON `"true"`/`"false"` strings under `"highlight_active_pane"` and `"active_pane_follows_mouse"`, parsing at the read boundary since `localStorage` only stores strings natively. Use the browser's `storage` event for cross-tab change notification in place of the synchronous Combine update this file's dependency, `UserSetting`, provides.
- **WinUI 3**: the reason this recipe exists. Model the three properties as static members of a settings class backed by `Windows.Storage.ApplicationData.Current.LocalSettings.Values`, keyed `"projectScanSkipPatterns"`, `"highlight_active_pane"`, and `"active_pane_follows_mouse"`. `ApplicationDataContainer.Values` stores a `Boolean` natively, so the two flag settings map directly; it does not store a `List<string>` directly, so serialize `projectScanSkipPatterns` with `System.Text.Json.JsonSerializer.Serialize`/`Deserialize` into a stored `string` value — the same fallback-to-encoded-payload shape this file's dependency, `UserDefaultsSettingsStorageProvider`, uses for `Data`. Expose each property through a member that raises `INotifyPropertyChanged`, firing synchronously on the UI thread, in place of `UserSetting`'s `@Published currentValue`. C# has no direct equivalent to Swift's compiler-enforced `@MainActor` isolation for a static member; document the class as UI-thread-affine by convention, or assert `DispatcherQueue.HasThreadAccess` at each entry point. Model the `highlightActivePane`/`ThemeProjectOptions` override relationship with a nullable `bool?` on the per-project options type and the same precedence C#'s null-coalescing operator expresses directly: `options?.HighlightActivePane ?? Settings.HighlightActivePane`.

## Design Decisions

**Decision**: `activePaneFollowsMouse` defaults to `false`.
**Rationale**: the source's own doc comment states this directly: focus that moves without being asked to is a preference people hold strongly in both directions, and having keys go somewhere the user did not put them is "the wrong default" (`UserSettings+Projects.swift`).
**Approved**: pending

**Decision**: `GitRepoScanner` receives `projectScanSkipPatterns` as a constructor parameter rather than reading the setting itself.
**Rationale**: the source's own doc comment states the reasoning directly — the scanner runs off the main actor, and a pure walk that is told what to skip is testable without a settings store (`UserSettings+Projects.swift`).
**Approved**: pending

**Decision**: `highlightActivePane` lives alongside the other project settings, and a per-project `ThemeProjectOptions.highlightActivePane` can override it.
**Rationale**: the source's own doc comment states the setting belongs here rather than with the appearance settings because it concerns a project window's panes specifically, and names the override directly (`UserSettings+Projects.swift`); the precedence is confirmed in the consumer, `ComposableTabsActivePane.swift`.
**Approved**: pending

**Decision**: the three storage keys use two different naming conventions — `projectScanSkipPatterns` is camelCase, while `highlight_active_pane` and `active_pane_follows_mouse` are snake_case.
**Rationale**: not stated in the source. The doc comments explain each setting's behavior and default but give no reason for the differing key format between the three (`UserSettings+Projects.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | failed | Reliability |

`separation-of-concerns` passes because `UserSettings+Projects.swift` declares only each setting's identity, type, and default; the read/write/remove/observe mechanics live in `UserSetting`/`SettingsStore`, the persistence mechanics live in `UserDefaultsSettingsStorageProvider`, the scan logic that consumes `projectScanSkipPatterns` lives in `GitRepoScanner`, and the panel that edits all three lives in `ProjectsSettingsPanelViewController` — none of that logic is duplicated here. `unit-test-coverage` is partial because no test file asserts any of this file's own three facts — the pinned key strings, the two defaults, or the documented `highlightActivePane`/`ThemeProjectOptions` override relationship — even though the generic mechanism these properties rely on is well covered elsewhere, by `UserDefaultsSettingsStoreTests.swift`'s Bool round-trip, string-array round-trip, empty-array round-trip, and corrupted-data-fallback tests. `explicit-error-handling` is partial because a decode failure on `projectScanSkipPatterns`'s stored `Data`, and an encode failure on a write to it, both fall back silently to a default value or a no-op with no signal surfaced to the caller — safe, but not surfaced, and that behavior is inherited from `UserDefaultsSettingsStorageProvider` rather than handled explicitly by this file. `data-integrity` fails because neither a corrupted `Data` payload under `"projectScanSkipPatterns"` nor an unexpectedly-typed object under either Bool key is ever detected or reported as corrupt; both cases resolve silently to `defaultValue`, indistinguishable from the key never having been set at all.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
