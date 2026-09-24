---
id: e71918a5-9874-48eb-927a-cea5e9b51cdc
title: Window Management Recents
domain: agentictoolkit://recipes/window-management-recents
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The ReopenOnLaunchPolicy enum and the two persisted UserSettings (recentWindowsCount,
  reopenOnLaunchPolicy) that govern Open Recent and launch reopen.
platforms:
- swift
- macos
tags:
- window-management
- recents
- user-settings
- preferences
- foundation
depends-on: []
related: []
references:
- https://developer.apple.com/documentation/appkit/nsdocumentcontroller/maximumrecentdocumentcount
approved-by: ''
approved-date: ''
---

# Window Management Recents

## Overview

The recents slice of the AgenticToolkit window manager is two small files under `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/Recents/`:

- `ReopenOnLaunchPolicy.swift` declares `ReopenOnLaunchPolicy`, a `String`-backed, `Codable`, `Sendable`, `CaseIterable`, `Equatable` enum with three cases (`useSystem`, `always`, `never`) that decides whether previously-open windows reopen at launch. Its doc comment models it on "Xcode's 'Restore open projects and workspaces' preference." It resolves to a `Bool` through `shouldReopen(systemDefault:)`, exposes an English `displayName` per case, and reads the macOS-wide `NSQuitAlwaysKeepsWindows` preference through the static `systemDefault`.
- `UserSettings+Recents.swift` declares two persisted settings on `UserSettings`: `recentWindowsCount` (`UserSetting<Int>`, key `"recentWindowsCount"`, default `10`), the "Maximum number of recent documents shown in File → Open Recent", and `reopenOnLaunchPolicy` (`UserSetting<ReopenOnLaunchPolicy>`, key `"reopenOnLaunchPolicy"`, default `.useSystem`).

These files hold the model and the stored preferences only. Behavior that acts on them lives in the consumers: `WindowManager.applyRecentDocumentCountFromSettings()` mirrors `recentWindowsCount` into AppKit's `NSRecentDocumentsLimit` user default, `WindowManager.reopenRecentsOnLaunch()` evaluates `reopenOnLaunchPolicy`, and `GeneralSettingsPanelViewController.createWindowBehaviorGroup()` presents both settings to the user. Use this ingredient when an app needs a user-selectable "restore windows on launch" policy that can defer to the OS-wide setting, plus a user-adjustable cap on the recent-documents list.

## Behavioral Requirements

### ReopenOnLaunchPolicy

- **policy-cases**: `ReopenOnLaunchPolicy` MUST declare exactly three cases, in this order: `useSystem`, `always`, `never`.
- **policy-raw-values**: Each case MUST use its case name as its `String` raw value: `"useSystem"`, `"always"`, `"never"`.
- **policy-case-iterable**: `ReopenOnLaunchPolicy.allCases` MUST contain exactly 3 elements, in declaration order (`useSystem`, `always`, `never`).
- **policy-codable**: `ReopenOnLaunchPolicy` MUST encode and decode as its raw `String` value (the compiler-synthesized `Codable` conformance for a `String`-backed enum), so a stored value round-trips only for the three raw values listed in policy-raw-values.
- **policy-sendable**: `ReopenOnLaunchPolicy` MUST conform to `Sendable`; as a payload-free enum the compiler enforces this, so a value MAY cross any concurrency-domain boundary without synchronization.
- **policy-equatable**: `ReopenOnLaunchPolicy` MUST conform to `Equatable`, with two values equal if and only if they are the same case.
- **use-system-follows-default**: `shouldReopen(systemDefault:)` on `useSystem` MUST return the `systemDefault` argument unchanged (`true` → `true`, `false` → `false`).
- **always-reopens**: `shouldReopen(systemDefault:)` on `always` MUST return `true` for either value of `systemDefault`.
- **never-reopens**: `shouldReopen(systemDefault:)` on `never` MUST return `false` for either value of `systemDefault`.
- **reopen-decision-pure**: `shouldReopen(systemDefault:)` MUST be a pure function of the receiver and its argument; it MUST NOT read any preference, including `NSQuitAlwaysKeepsWindows`, itself. The caller supplies the system value (in the source, `WindowManager.reopenRecentsOnLaunch()` passes `ReopenOnLaunchPolicy.systemDefault`).
- **display-name-use-system**: `displayName` on `useSystem` MUST return `"Use System Setting"`.
- **display-name-always**: `displayName` on `always` MUST return `"Always"`.
- **display-name-never**: `displayName` on `never` MUST return `"Never"`.
- **system-default-key**: `ReopenOnLaunchPolicy.systemDefault` MUST return the Boolean value of the `NSQuitAlwaysKeepsWindows` key read from the standard user defaults, which search the app's domain and then the global domain.
- **system-default-absent**: `ReopenOnLaunchPolicy.systemDefault` MUST return `false` when `NSQuitAlwaysKeepsWindows` is absent from every searched domain (the standard `bool(forKey:)` result for a missing key).
- **system-default-inverted-label**: `systemDefault` MUST report the stored key, not the System Settings checkbox: per the source doc comment, checking "Close windows when quitting an application" sets `NSQuitAlwaysKeepsWindows = false`, so a checked box yields `systemDefault == false`.
- **system-default-uncached**: `systemDefault` MUST be a computed property that re-reads the preference on every access; it MUST NOT cache the value.
- **system-default-read-only**: `ReopenOnLaunchPolicy` MUST NOT write `NSQuitAlwaysKeepsWindows` or any other preference; its only side effect is the read in `systemDefault`.

### Persisted settings

- **recent-count-key**: `UserSettings.recentWindowsCount` MUST persist under the key `"recentWindowsCount"`.
- **recent-count-default**: `UserSettings.recentWindowsCount` MUST read as `10` when no value is stored under its key.
- **recent-count-storage-form**: Because the value type is `Int`, the default `UserDefaultsSettingsStorageProvider` MUST store `recentWindowsCount` as a native integer, not JSON-encoded data.
- **recent-count-range**: A count in the settings UI's range is a caller precondition. `recentWindowsCount` accepts any `Int`, including negative values; the only bound is the settings UI stepper (`minValue: 0`, `maxValue: 50` in `GeneralSettingsPanelViewController`), so a programmatic write of a negative or very large count reaches `NSRecentDocumentsLimit` unchanged.
- **policy-setting-key**: `UserSettings.reopenOnLaunchPolicy` MUST persist under the key `"reopenOnLaunchPolicy"`.
- **policy-setting-default**: `UserSettings.reopenOnLaunchPolicy` MUST read as `.useSystem` when no value is stored under its key.
- **policy-setting-storage-form**: Because `ReopenOnLaunchPolicy` is not a natively stored primitive, the default `UserDefaultsSettingsStorageProvider` MUST store `reopenOnLaunchPolicy` as JSON-encoded data of its raw `String` value.
- **policy-setting-decode-fallback**: When the data stored under `"reopenOnLaunchPolicy"` fails to decode as a `ReopenOnLaunchPolicy`, reading the setting MUST return the default `.useSystem`; the storage provider discards the decode failure without logging it (behavior owned by `UserDefaultsSettingsStorageProvider.get`, not by these files).
- **settings-not-secure**: Both settings MUST be declared non-secure (`isSecure` defaults to `false`), so they route to the store's ordinary settings provider, never the Keychain provider.
- **settings-main-actor**: Both settings MUST be accessed on the main actor: `UserSettings` and `UserSetting` are both declared `@MainActor`, so the compiler rejects reads or writes from any other isolation domain.
- **settings-observable**: Each setting MUST publish its current value through `UserSetting.currentValue` (`@Published`), updating whenever the backing store emits a change for the setting's key.
- **settings-lazy-binding**: Each setting MUST bind to `UserSettings.shared` when the static property is first accessed; the `UserSetting` initializer reads the current value from, and subscribes to changes on, the store that is `UserSettings.shared` at that moment.

### Consumer contract declared by the source

- **recent-count-mirror**: Per the `recentWindowsCount` doc comment ("Mirrored to `NSDocumentController.maximumRecentDocumentCount` by `WindowManager.applyRecentDocumentCountFromSettings()`"), calling `applyRecentDocumentCountFromSettings()` MUST write the current `recentWindowsCount` value to the `NSRecentDocumentsLimit` key in the standard user defaults.
- **recent-count-mirror-live**: After `WindowManager` is constructed, a change to `recentWindowsCount` MUST be mirrored to `NSRecentDocumentsLimit` on a later main-run-loop turn with no explicit call (the manager subscribes to `currentValue` and receives on `RunLoop.main`).
- **policy-consumed-for-documents-only**: `reopenOnLaunchPolicy` MUST govern only the reopen of recent document windows in `WindowManager.reopenRecentsOnLaunch()`; per `ProjectWindowManager.restoreOpenProjects()`'s doc comment, project windows "not consult `reopenOnLaunchPolicy`".
- **no-network-no-files**: Neither file MUST perform network access, file I/O beyond the user-defaults reads and writes described above, process launches, or notification posting.
- **no-errors**: No operation in either file MUST throw or return an error; every read yields a value (stored, or the default).

## Appearance

Not applicable — this is a preference model and two persisted settings, not a visual component.

## States

Not applicable — this is a preference model and two persisted settings, not a visual component.

## Accessibility

Not applicable — this is a preference model and two persisted settings, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| recents-001 | use-system-follows-default | `ReopenOnLaunchPolicy.useSystem.shouldReopen(systemDefault: true)` | `true` (`ReopenOnLaunchPolicyTests`) |
| recents-002 | use-system-follows-default | `ReopenOnLaunchPolicy.useSystem.shouldReopen(systemDefault: false)` | `false` (`ReopenOnLaunchPolicyTests`) |
| recents-003 | always-reopens | `ReopenOnLaunchPolicy.always.shouldReopen(systemDefault:)` with `false`, then `true` | `true`, then `true` (`ReopenOnLaunchPolicyTests`) |
| recents-004 | never-reopens | `ReopenOnLaunchPolicy.never.shouldReopen(systemDefault:)` with `false`, then `true` | `false`, then `false` (`ReopenOnLaunchPolicyTests`) |
| recents-005 | display-name-use-system, display-name-always, display-name-never | `displayName` of `useSystem`, `always`, `never` | `"Use System Setting"`, `"Always"`, `"Never"` (`ReopenOnLaunchPolicyTests`) |
| recents-006 | policy-case-iterable, policy-cases | `ReopenOnLaunchPolicy.allCases` | 3 elements: `useSystem`, `always`, `never` (count asserted in `ReopenOnLaunchPolicyTests`) |
| recents-007 | policy-raw-values | `rawValue` of each case; `ReopenOnLaunchPolicy(rawValue: "always")`; `ReopenOnLaunchPolicy(rawValue: "sometimes")` | `"useSystem"`, `"always"`, `"never"`; `.always`; `nil` |
| recents-008 | policy-codable | JSON-encode `.never`, then decode the result | Encoded JSON is the string `"never"`; decodes back to `.never` |
| recents-009 | policy-equatable | `.always == .always`; `.always == .never` | `true`; `false` |
| recents-010 | reopen-decision-pure | Set `NSQuitAlwaysKeepsWindows = true` in the app domain, then call `ReopenOnLaunchPolicy.never.shouldReopen(systemDefault: false)` | `false`; the preference has no effect on the result |
| recents-011 | system-default-key | Standard defaults with `NSQuitAlwaysKeepsWindows = true` | `ReopenOnLaunchPolicy.systemDefault == true` |
| recents-012 | system-default-absent | Standard defaults with `NSQuitAlwaysKeepsWindows` removed from every searched domain | `ReopenOnLaunchPolicy.systemDefault == false` |
| recents-013 | system-default-uncached | Read `systemDefault` with the key `false`, set the key `true`, read again | First read `false`, second read `true` |
| recents-014 | system-default-inverted-label | "Close windows when quitting an application" checked in System Settings (stores `NSQuitAlwaysKeepsWindows = false`) | `systemDefault == false`; `useSystem.shouldReopen(systemDefault: systemDefault) == false` |
| recents-015 | system-default-read-only | Snapshot the standard defaults, read `systemDefault` and every `displayName` | Defaults unchanged |
| recents-016 | recent-count-key, recent-count-default | Empty settings store; read `UserSettings.recentWindowsCount.currentValue` | `10`; `UserSettings.recentWindowsCount.name == "recentWindowsCount"` |
| recents-017 | recent-count-storage-form | Set `UserSettings.recentWindowsCount.value = 7` with the default provider | `UserDefaults.standard.integer(forKey: "recentWindowsCount") == 7`, stored as a number |
| recents-018 | policy-setting-key, policy-setting-default | Empty settings store; read `UserSettings.reopenOnLaunchPolicy.currentValue` | `.useSystem`; `name == "reopenOnLaunchPolicy"` |
| recents-019 | policy-setting-storage-form | Set `UserSettings.reopenOnLaunchPolicy.value = .always` with the default provider | `UserDefaults.standard.data(forKey: "reopenOnLaunchPolicy")` holds the JSON string `"always"`; reading the setting returns `.always` |
| recents-020 | policy-setting-decode-fallback | Store data for the JSON string `"sometimes"` under `"reopenOnLaunchPolicy"` | Reading the setting returns `.useSystem`; nothing is thrown or logged |
| recents-021 | settings-not-secure | Inspect `isSecure` on both settings | `false` for both |
| recents-022 | settings-observable | Subscribe to `UserSettings.reopenOnLaunchPolicy.$currentValue`, then set `.value = .never` | Subscriber receives `.never` |
| recents-023 | recent-count-mirror | `recentWindowsCount.value = 7`, call `applyRecentDocumentCountFromSettings()`; then `3`, call again | `UserDefaults.standard.integer(forKey: "NSRecentDocumentsLimit")` is `7`, then `3` (`WindowManagerRecentsTests.testApplyRecentDocumentCountFromSettingsWritesUserDefault`) |
| recents-024 | recent-count-mirror-live | Touch `WindowManager.shared`, set `recentWindowsCount.value = 12`, check on the next main-queue turn | `NSRecentDocumentsLimit == 12` with no explicit apply call (`WindowManagerRecentsTests.testSettingChangePropagatesViaCombineSink`) |
| recents-025 | policy-consumed-for-documents-only | `reopenOnLaunchPolicy = .never`; call `ProjectWindowManager.restoreOpenProjects()` with a project whose window was open last session and whose folder exists | The project window reopens; the policy is not consulted |
| recents-026 | settings-main-actor | Read `UserSettings.recentWindowsCount.currentValue` from a nonisolated context with no `await` | Rejected at compile time under strict concurrency |
| recents-027 | no-errors, no-network-no-files | Call every public member of both files | None throws; no file, network, or process activity beyond the user-defaults reads and writes |

## Edge Cases

- **Missing system key**: `NSQuitAlwaysKeepsWindows` absent from both the app and global domains — `systemDefault` MUST return `false`, so `useSystem` MUST resolve to "do not reopen" (system-default-absent).
- **App-domain override of the system key**: the app writes `NSQuitAlwaysKeepsWindows` in its own domain — `systemDefault` MUST return the app-domain value, because the standard defaults search the app domain before the global domain; the source does not isolate the read to the global domain.
- **Empty settings store**: first launch with nothing stored — `recentWindowsCount` MUST read `10` and `reopenOnLaunchPolicy` MUST read `.useSystem`.
- **Undecodable stored policy**: data under `"reopenOnLaunchPolicy"` that is not a JSON string matching a raw value (a removed case, corrupt data) — reading MUST return `.useSystem` with no error surfaced (policy-setting-decode-fallback). The fallback is deliberate in the storage provider, and the policy degrades to the OS setting.
- **Policy written as a plain string**: a value written outside the store as a plain string (for example `defaults write <bundle> reopenOnLaunchPolicy always`) — reading MUST return `.useSystem`, because the provider reads the key as data and a plain string is not data.
- **Zero recent count**: `recentWindowsCount = 0` (the stepper's minimum) — the mirror MUST write `0` to `NSRecentDocumentsLimit`; how AppKit renders an Open Recent menu capped at zero belongs to AppKit, not to this component.
- **Negative or oversize recent count**: a programmatic write of `-1` or `1000` — the setting MUST store it unchanged and the mirror MUST write it unchanged; nothing in the source clamps it (see recent-count-range).
- **Limit takes effect lazily**: per the `applyRecentDocumentCountFromSettings()` doc comment, AppKit honors a new limit on the next `noteNewRecentDocumentURL` call, so lowering the count SHOULD NOT be expected to trim the existing Open Recent list until the next document is noted. Rationale: the mirror writes only the user default and does not ask AppKit to trim the list.
- **Store replaced after first access**: the app assigns a new `UserSettings.shared` after either setting was first read — the setting MUST keep observing the store it bound to at first access (settings-lazy-binding); hosts set `UserSettings.shared` before touching these settings, per the `UserSettings.shared` comment "Client apps should create and set this".
- **Concurrent access**: both settings are `@MainActor`, so reads and writes are serialized on the main actor and cannot interleave; `ReopenOnLaunchPolicy` values are immutable and `Sendable`; `systemDefault` is a nonisolated read of the thread-safe standard user defaults.
- **Headless launch**: no `NSApplication` (for example a unit-test host) — `WindowManager.reopenRecentsOnLaunch()` MUST return before reading `reopenOnLaunchPolicy`, so the policy is never evaluated.
- **Error states**: none of the operations can fail; every read returns a stored value or the default, and writes go through the store without a return value.
- **Offline or disconnected state**: not applicable; the component performs no network access.
- **Cancellation and timeouts**: not applicable; every operation is a synchronous user-defaults read or write, with no timeout and nothing to cancel.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `UserSettings.recentWindowsCount` (key `recentWindowsCount`) | `Int` | `10` | Maximum number of recent documents shown in File → Open Recent; mirrored to `NSRecentDocumentsLimit` by `WindowManager`. |
| `UserSettings.reopenOnLaunchPolicy` (key `reopenOnLaunchPolicy`) | `ReopenOnLaunchPolicy` | `.useSystem` | Whether windows reopen at launch: follow the OS, always, or never. |
| `NSQuitAlwaysKeepsWindows` (system preference, read-only here) | `Bool` | `false` when absent | macOS-wide "keep windows on quit" value that `useSystem` defers to; set by the inverted System Settings checkbox "Close windows when quitting an application". |
| `NSRecentDocumentsLimit` (AppKit preference, written by the consumer) | `Int` | AppKit's own default until first mirrored | Written by `WindowManager.applyRecentDocumentCountFromSettings()`; not written by these files. |
| `UserSettings.shared` | `UserSettings` | `UserSettings()` backed by `UserDefaultsSettingsStorageProvider` over `UserDefaults.standard` | Injected store both settings bind to at first access. |

## Deep Linking

Not applicable: neither file defines a URL scheme, route, or navigation entry point; both are a preference model and its stored settings.

## Localization

`ReopenOnLaunchPolicy.displayName` returns hardcoded English literals with no string-catalog lookup; the settings panel shows them as the popup's choice labels.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Use System Setting` | `displayName` for `useSystem`, a choice label in the "Restore windows on launch:" popup |
| (none; literal) | `Always` | `displayName` for `always` |
| (none; literal) | `Never` | `displayName` for `never` |

The popup title "Restore windows on launch:" and the stepper title "Number of recent documents:" are literals in `GeneralSettingsPanelViewController`, not in these files.

## Accessibility Options

Not applicable: the component has no visual surface, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: the source declares no feature-flag key and gates no behavior on one; the two settings are user preferences, not flags.

## Analytics

Not applicable: neither file emits analytics events.

## Privacy

Not applicable: the component stores two non-personal UI preferences (an integer and a policy name) in the app's local user defaults and reads one system preference; it collects, transmits, and logs no user data.

## Logging

Not applicable: neither file contains a `Logger`, `os_log`, or `print` call, and the decode fallback in the storage provider is not logged either (policy-setting-decode-fallback).

## Platform Notes

- **SwiftUI**: Source platform is macOS. Store the policy with `@AppStorage("reopenOnLaunchPolicy")` over a `String` raw-value enum, and the count with `@AppStorage("recentWindowsCount")` defaulting to `10`. Note that `@AppStorage` stores the raw string natively, while the source's provider stores JSON data, so the two are not interchangeable on the same key. SwiftUI's `WindowGroup` and `DocumentGroup` restoration still honors `NSQuitAlwaysKeepsWindows`; a `never` policy needs the same close-after-restore override the source's consumer uses.
- **Compose**: Android has no desktop-style "keep windows on quit" preference, so `useSystem` has no system value to read. Map it to a platform choice (for example "follow Activity state restoration", which always restores) and store both values in Jetpack DataStore `Preferences` (`intPreferencesKey("recentWindowsCount")`, `stringPreferencesKey("reopenOnLaunchPolicy")`), exposed as a `Flow` in place of `@Published`. A recents cap would bound the app's own list; Android has no system Open Recent menu.
- **React/Web**: Persist both values in `localStorage` (`JSON.stringify` of the raw string matches the source's JSON form) and model the enum as a string-literal union `'useSystem' | 'always' | 'never'`. Browsers expose no OS keep-windows setting, so `useSystem` has to resolve to an app-chosen constant, and "reopen" means restoring tabs or panels from the app's own saved state. Use a `storage` event listener in place of the Combine subscription for cross-tab updates.
- **AppKit / UIKit**: This is the source. `ReopenOnLaunchPolicy.swift` holds the enum, `shouldReopen(systemDefault:)`, `displayName`, and `systemDefault` (reading `UserDefaults.standard` `NSQuitAlwaysKeepsWindows`). `UserSettings+Recents.swift` holds the two `@MainActor` `UserSetting` statics. On AppKit, `WindowManager` writes `NSRecentDocumentsLimit`, because `NSDocumentController.maximumRecentDocumentCount` is read-only. UIKit has neither `NSDocumentController` recents nor `NSQuitAlwaysKeepsWindows`; scene restoration via `NSUserActivity` / `stateRestorationActivity` stands in for reopening, and `useSystem` has no system value.
- **WinUI 3**: Model the enum as a C# `enum ReopenOnLaunchPolicy { UseSystem, Always, Never }` and persist it with `Enum.ToString()` / `Enum.Parse` in `Windows.Storage.ApplicationData.Current.LocalSettings.Values["reopenOnLaunchPolicy"]`, keeping the count as an `int` under `"recentWindowsCount"` (default `10`). In an unpackaged app, use a JSON file written with `System.Text.Json` instead, since `ApplicationData` requires package identity. Put a `Parse` failure inside a `TryParse` that falls back to `UseSystem`, to match policy-setting-decode-fallback. Windows has no `NSQuitAlwaysKeepsWindows`. The nearest OS signal is the per-user "Automatically save my restartable apps and restart them when I sign back in" setting (the `RestartApps` value under `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon`), read via `Microsoft.Win32.Registry` and treated as `false` when absent. Reopen itself is the app's job: persist open document paths and restore them in `App.OnLaunched`, optionally registering with `RegisterApplicationRestart`. For the recents cap, `Windows.Storage.AccessCache.StorageApplicationPermissions.MostRecentlyUsedList` has a fixed, read-only `MaximumItemsAllowed` (25), so a user-adjustable cap has to be enforced on the app's own list, or on `Windows.UI.StartScreen.JumpList` with `SystemGroupKind = JumpListSystemGroupKind.Recent`. Surface the settings through a view model implementing `INotifyPropertyChanged` in place of `@Published`, and keep access on the UI thread (`DispatcherQueue`) to match the source's `@MainActor` isolation. `displayName` belongs in `.resw` resources rather than literals.

## Design Decisions

**Decision**: `useSystem` is the default policy, and `shouldReopen(systemDefault:)` takes the system value as a parameter instead of reading it.
**Rationale**: Deferring to the OS matches the platform convention (the doc comment models the enum on Xcode's restore preference), and injecting the Boolean keeps the decision pure and testable without touching global defaults, which is how `ReopenOnLaunchPolicyTests` exercises it; `systemDefault` is the one impure accessor.
**Approved**: pending

**Decision**: `systemDefault` reports the raw `NSQuitAlwaysKeepsWindows` value, whose sense is the inverse of the System Settings checkbox label.
**Rationale**: The doc comment records that checking "Close windows when quitting an application" sets the key to `false`; reading the key directly avoids a second inversion, and a missing key reads `false` (do not keep windows).
**Approved**: pending

**Decision**: The recent-documents cap is a toolkit setting mirrored into AppKit's `NSRecentDocumentsLimit` user default by `WindowManager`, rather than set on `NSDocumentController`.
**Rationale**: Per the `WindowManager` comments, `maximumRecentDocumentCount` is read-only and writing the user default is "the public knob" that avoids subclassing `NSDocumentController`; the cost is that a lower cap applies only on the next `noteNewRecentDocumentURL` call.
**Approved**: pending

**Decision**: `reopenOnLaunchPolicy` covers document windows only; project windows restore regardless of it.
**Rationale**: Per `ProjectWindowManager.restoreOpenProjects()`, "A project window is the app's workspace, not a document", and closing the window is how the user stops it reopening.
**Approved**: pending

**Decision**: `displayName` returns English literals.
**Rationale**: The strings serve only as settings-panel choice labels; externalizing them is not done in the source and is recorded as a failed check under Compliance.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`separation-of-concerns` passes because the two files hold only the policy model and the stored settings, while mirroring, launch reopen, and presentation live in `WindowManager` and `GeneralSettingsPanelViewController`. `unit-test-coverage` passes: `ReopenOnLaunchPolicyTests` covers all six `shouldReopen(systemDefault:)` combinations, every `displayName`, and the case count, and `WindowManagerRecentsTests` covers the explicit and Combine-driven mirroring of `recentWindowsCount`. `no-hardcoded-strings` fails because `displayName` returns English literals shown to the user. `data-integrity` is partial because `recentWindowsCount` accepts any integer and passes it to AppKit unchecked outside the settings stepper's 0 to 50 range, and an undecodable stored policy silently falls back to `.useSystem`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
