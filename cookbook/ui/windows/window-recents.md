---
id: e71918a5-9874-48eb-927a-cea5e9b51cdc
title: Window Management Recents
domain: agentictoolkit://cookbook/ui/windows/window-recents
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A reopen-on-launch policy with three states, plus the two persisted preferences
  (a maximum recent-document count and the policy itself) that govern an app's Open
  Recent list and whether windows reopen at launch.
platforms:
- swift
- macos
tags:
- window-management
- recents
- user-settings
- preferences
depends-on: []
related: []
references:
- https://developer.apple.com/documentation/appkit/nsdocumentcontroller/maximumrecentdocumentcount
approved-by: ''
approved-date: ''
---

# Window Management Recents

## Overview

This ingredient models a reopen-on-launch policy with three states — follow the platform default, always, never — that decides whether previously open windows reopen when the app launches, plus two persisted preferences: a maximum count of recent documents shown in an Open Recent list, and the reopen-on-launch policy itself.

The policy resolves to a boolean through a decision function that takes the platform-wide default as an argument rather than reading it directly, exposes a human-readable display name per state, and reads the platform-wide "keep windows on quit" preference through a system-default accessor.

This concept holds the policy model and the stored preferences only. Behavior that acts on them — mirroring the recent-document count into the platform's own limit, evaluating the policy at launch, and presenting both preferences to the user — lives in consumers described in Platform Notes. Use this ingredient when an app needs a user-selectable "restore windows on launch" policy that can defer to the platform-wide setting, plus a user-adjustable cap on the recent-documents list.

## Behavioral Requirements

### Reopen-on-Launch Policy

- **policy-cases**: The reopen-on-launch policy MUST have exactly three states, in this order: `useSystem`, `always`, `never`.
- **policy-raw-values**: Each state's persisted string value MUST equal its name: `"useSystem"`, `"always"`, `"never"`.
- **policy-case-iterable**: The complete, ordered list of policy states MUST contain exactly 3 elements, in the order given in policy-cases (`useSystem`, `always`, `never`).
- **policy-round-trips-as-string**: The policy MUST serialize to and deserialize from its raw string value, so a stored value round-trips only for the three raw values listed in policy-raw-values.
- **policy-safe-to-share**: The policy MUST be safe to read or pass across concurrent contexts without synchronization; it carries no mutable state.
- **policy-equatable**: Two policy values MUST be equal if and only if they are the same state.
- **use-system-follows-default**: The decision function on `useSystem` MUST return the system-default argument unchanged (`true` → `true`, `false` → `false`).
- **always-reopens**: The decision function on `always` MUST return `true` regardless of the system-default argument.
- **never-reopens**: The decision function on `never` MUST return `false` regardless of the system-default argument.
- **reopen-decision-pure**: The decision function MUST be a pure function of the receiver and its argument; it MUST NOT read any preference, including the platform's keep-windows-on-quit preference, itself. The caller supplies the platform value (see Platform Notes for which consumer does this and how).
- **display-name-use-system**: The display name for `useSystem` MUST be `"Use System Setting"`.
- **display-name-always**: The display name for `always` MUST be `"Always"`.
- **display-name-never**: The display name for `never` MUST be `"Never"`.
- **system-default-key**: The system-default accessor MUST return the boolean value of the platform's keep-windows-on-quit preference, searched from the app's own preference domain and then the platform-global domain.
- **system-default-absent**: The system-default accessor MUST return `false` when the keep-windows-on-quit preference is absent from every searched domain.
- **system-default-inverted-label**: The system-default accessor MUST report the preference's stored value as it is stored. Where the platform's own on-screen control for this preference has an inverted sense from the stored value (see Platform Notes), the accessor still reports the raw stored value, never the checkbox's sense.
- **system-default-uncached**: The system-default accessor MUST be re-evaluated on every access; it MUST NOT cache the value.
- **system-default-read-only**: The reopen-on-launch policy MUST NOT write the keep-windows-on-quit preference or any other preference; its only side effect is the read described in system-default-key.

### Persisted Settings

- **recent-count-key**: The recent-window-count preference MUST persist under the key `"recentWindowsCount"`.
- **recent-count-default**: The recent-window-count preference MUST read as `10` when no value is stored under its key.
- **recent-count-storage-form**: Because its value is an integer, the preference store MUST persist recent-window-count as a native integer, not JSON-encoded data.
- **recent-count-range**: A count within the settings UI's range is a caller precondition. The recent-window-count preference MUST accept any integer, including negative values; the only bound enforced is in the settings UI (a range of 0 to 50), so a programmatic write of a negative or very large count reaches the mirrored platform limit unchanged.
- **policy-setting-key**: The reopen-on-launch preference MUST persist under the key `"reopenOnLaunchPolicy"`.
- **policy-setting-default**: The reopen-on-launch preference MUST read as `useSystem` when no value is stored under its key.
- **policy-setting-storage-form**: Because the policy is not a natively stored primitive, the preference store MUST persist it as JSON-encoded data of its raw string value.
- **policy-setting-decode-fallback**: When the data stored under `"reopenOnLaunchPolicy"` fails to decode as a policy value, reading the preference MUST return the default `useSystem`; the preference store discards the decode failure without logging it.
- **settings-not-secure**: Both preferences MUST be declared non-secure, so they route through the store's ordinary preference path, never a secure-storage path (such as a keychain).
- **settings-single-threaded-access**: Both preferences MUST be accessed only from a single, consistent execution context (the UI thread); a read or write from any other context MUST be rejected at compile time by the platform's concurrency-checking rules.
- **settings-change-notifying**: Each preference MUST publish its current value through a change-notifying mechanism, updating whenever the backing store emits a change for the preference's key.
- **settings-lazy-binding**: Each preference MUST bind to the shared preference store when first accessed; from that point it reads the current value from, and subscribes to changes on, that store.

### Consumer Contract

- **recent-count-mirror**: Applying the recent-window-count preference to the platform MUST write its current value to the platform's own recent-documents limit.
- **recent-count-mirror-live**: After the window manager is constructed, a change to the recent-window-count preference MUST be mirrored to the platform's recent-documents limit on a later turn of the main run loop with no explicit call; the manager subscribes to the preference's value changes.
- **policy-consumed-for-documents-only**: The reopen-on-launch preference MUST govern only the reopen of recent document windows; project (workspace) windows MUST NOT consult it.
- **no-network-no-files**: Neither the policy nor the preferences MUST perform network access, file I/O beyond the preference-store reads and writes described above, process launches, or notification posting.
- **no-errors**: No operation described above MUST throw or return an error; every read yields a value (stored, or the default).

## Appearance

Not applicable — this is a preference model and two persisted settings, not a visual component.

## States

Not applicable — this is a preference model and two persisted settings, not a visual component.

## Accessibility

Not applicable — this is a preference model and two persisted settings, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| recents-001 | use-system-follows-default | decision function on `useSystem` with system-default `true` | `true` |
| recents-002 | use-system-follows-default | decision function on `useSystem` with system-default `false` | `false` |
| recents-003 | always-reopens | decision function on `always` with system-default `false`, then `true` | `true`, then `true` |
| recents-004 | never-reopens | decision function on `never` with system-default `false`, then `true` | `false`, then `false` |
| recents-005 | display-name-use-system, display-name-always, display-name-never | display name of `useSystem`, `always`, `never` | `"Use System Setting"`, `"Always"`, `"Never"` |
| recents-006 | policy-case-iterable, policy-cases | the complete list of policy states | 3 elements, in order: `useSystem`, `always`, `never` |
| recents-007 | policy-raw-values | raw value of each state; parsing `"always"`; parsing `"sometimes"` | `"useSystem"`, `"always"`, `"never"`; `always`; no match |
| recents-008 | policy-round-trips-as-string | encode `never`, then decode the result | Encoded value is the string `"never"`; decodes back to `never` |
| recents-009 | policy-equatable | `always == always`; `always == never` | `true`; `false` |
| recents-010 | reopen-decision-pure | set the platform's keep-windows-on-quit preference to `true`, then call the decision function on `never` with system-default `false` | `false`; the preference has no effect on the result |
| recents-011 | system-default-key | platform preference domain with keep-windows-on-quit set to `true` | system-default reads `true` |
| recents-012 | system-default-absent | keep-windows-on-quit preference removed from every searched domain | system-default reads `false` |
| recents-013 | system-default-uncached | read system-default with the preference `false`, set the preference `true`, read again | First read `false`, second read `true` |
| recents-014 | system-default-inverted-label | the platform's own "close windows when quitting" control checked (which stores the preference as `false`) | system-default reads `false`; `useSystem`'s decision with that value is `false` |
| recents-015 | system-default-read-only | snapshot the platform preferences, read system-default and every display name | Preferences unchanged |
| recents-016 | recent-count-key, recent-count-default | empty preference store; read recent-window-count | `10`; its key is `"recentWindowsCount"` |
| recents-017 | recent-count-storage-form | set recent-window-count to `7` with the default store | Stored as a native integer `7` under key `"recentWindowsCount"` |
| recents-018 | policy-setting-key, policy-setting-default | empty preference store; read reopen-on-launch preference | `useSystem`; its key is `"reopenOnLaunchPolicy"` |
| recents-019 | policy-setting-storage-form | set reopen-on-launch preference to `always` with the default store | Stored as JSON-encoded data holding the string `"always"`; reading the preference returns `always` |
| recents-020 | policy-setting-decode-fallback | store data for the JSON string `"sometimes"` under `"reopenOnLaunchPolicy"` | Reading the preference returns `useSystem`; nothing is thrown or logged |
| recents-021 | settings-not-secure | inspect the secure flag on both preferences | `false` (non-secure) for both |
| recents-022 | settings-change-notifying | subscribe to change notifications on the reopen-on-launch preference, then set it to `never` | Subscriber receives `never` |
| recents-023 | recent-count-mirror | set recent-window-count to `7`, apply it; then `3`, apply again | The platform's recent-documents limit is `7`, then `3` |
| recents-024 | recent-count-mirror-live | construct the window manager, set recent-window-count to `12`, check on the next main-run-loop turn | The platform's recent-documents limit is `12` with no explicit apply call |
| recents-025 | policy-consumed-for-documents-only | reopen-on-launch preference set to `never`; restore open projects with a project whose window was open last session and whose folder exists | The project window reopens; the policy is not consulted |
| recents-026 | settings-single-threaded-access | read recent-window-count from outside the designated execution context with no explicit hand-off | Rejected at compile time by the platform's concurrency checks |
| recents-027 | no-errors, no-network-no-files | invoke every public operation of the policy and the preferences | None throws; no file, network, or process activity beyond the preference-store reads and writes |

## Edge Cases

- **Missing system key**: the keep-windows-on-quit preference absent from every searched domain — system-default MUST return `false`, so `useSystem` MUST resolve to "do not reopen" (system-default-absent).
- **App-domain override of the system key**: the app writes its own value for the keep-windows-on-quit preference in its own preference domain — system-default MUST return the app-domain value, because the lookup searches the app's own domain before the platform-global domain.
- **Empty settings store**: first launch with nothing stored — recent-window-count MUST read `10` and the reopen-on-launch preference MUST read `useSystem`.
- **Undecodable stored policy**: data under `"reopenOnLaunchPolicy"` that is not a JSON string matching a raw value (a removed state, corrupt data) — reading MUST return `useSystem` with no error surfaced (policy-setting-decode-fallback). The fallback is deliberate in the storage layer, and the policy degrades to the platform setting.
- **Policy written as a plain string**: a value written outside the store as a plain string rather than JSON-encoded data — reading MUST return `useSystem`, because the store reads the key as encoded data and a plain string is not that (see Platform Notes for a concrete example).
- **Zero recent count**: recent-window-count of `0` (the settings UI's minimum) — the mirror MUST write `0` to the platform's recent-documents limit; how the platform renders an Open Recent list capped at zero belongs to the platform, not to this component.
- **Negative or oversize recent count**: a programmatic write of `-1` or `1000` — the preference MUST store it unchanged and the mirror MUST write it unchanged; nothing in this concept clamps it (see recent-count-range).
- **Limit takes effect lazily**: the mirror writes only the platform's recent-documents limit and does not force the platform to trim the existing list, so lowering the count SHOULD NOT be expected to take visible effect until the platform's own recents mechanism next updates one (see Platform Notes).
- **Store replaced after first access**: the app assigns a new shared preference store after either preference was first read — each preference MUST keep observing the store it bound to at first access (settings-lazy-binding); hosts are expected to set the shared preference store before either preference is first touched.
- **Concurrent access**: both preferences are restricted to a single execution context, so reads and writes are serialized and cannot interleave; policy values are immutable and safe to share across contexts; system-default is a read of the thread-safe platform preference store, independent of that context.
- **Headless launch**: no running application shell (for example, a unit-test host) — launch reopen MUST return before reading the reopen-on-launch preference, so the policy is never evaluated.
- **Error states**: none of the operations can fail; every read returns a stored value or the default, and writes go through the store without a return value.
- **Offline or disconnected state**: not applicable; the component performs no network access.
- **Cancellation and timeouts**: not applicable; every operation is a synchronous preference-store read or write, with no timeout and nothing to cancel.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Recent window count (key `recentWindowsCount`) | integer | `10` | Maximum number of recent documents shown in an Open Recent list; mirrored into the platform's own recent-documents limit. |
| Reopen-on-launch policy (key `reopenOnLaunchPolicy`) | policy (`useSystem` \| `always` \| `never`) | `useSystem` | Whether windows reopen at launch: follow the platform, always, or never. |
| Platform keep-windows-on-quit preference (read-only here) | boolean | `false` when absent | Platform-wide "keep windows on quit" value that `useSystem` defers to; see Platform Notes for how a given platform exposes and inverts it. |
| Platform recent-documents limit (written by the consumer) | integer | Platform's own default until first mirrored | Written when the recent-window-count preference is applied; not written by this concept directly. |
| Shared preference store | preference store | a default store backed by the platform's standard preference mechanism | Injected store both preferences bind to at first access. |

## Deep Linking

Not applicable: neither the policy nor the preferences define a URL scheme, route, or navigation entry point; both are a preference model and its stored settings.

## Localization

The display name returns hardcoded English literals with no string-catalog lookup; the settings panel shows them as a popup's choice labels.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Use System Setting` | Display name for `useSystem`, a choice label in the "Restore windows on launch:" popup |
| (none; literal) | `Always` | Display name for `always` |
| (none; literal) | `Never` | Display name for `never` |

The popup title "Restore windows on launch:" and the stepper title "Number of recent documents:" are literals in the settings panel that presents these preferences, not in the policy or preference model itself.

## Accessibility Options

Not applicable: the component has no visual surface, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this concept declares no feature-flag key and gates no behavior on one; the two settings are user preferences, not flags.

## Analytics

Not applicable: neither the policy nor the preferences emit analytics events.

## Privacy

Not applicable: the component stores two non-personal UI preferences (an integer and a policy name) in the app's local preference store and reads one platform preference; it collects, transmits, and logs no user data.

## Logging

Not applicable: the policy and preferences perform no logging, and the decode fallback in the storage layer is not logged either (policy-setting-decode-fallback).

## Platform Notes

- **SwiftUI**: Source platform is macOS. Store the policy with `@AppStorage("reopenOnLaunchPolicy")` over a `String` raw-value enum, and the count with `@AppStorage("recentWindowsCount")` defaulting to `10`. Note that `@AppStorage` stores the raw string natively, while the source's provider stores JSON data, so the two are not interchangeable on the same key. SwiftUI's `WindowGroup` and `DocumentGroup` restoration still honors `NSQuitAlwaysKeepsWindows`; a `never` policy needs the same close-after-restore override the source's consumer uses.
- **Compose**: Android has no desktop-style "keep windows on quit" preference, so `useSystem` has no system value to read. Map it to a platform choice (for example "follow Activity state restoration", which always restores) and store both values in Jetpack DataStore `Preferences` (`intPreferencesKey("recentWindowsCount")`, `stringPreferencesKey("reopenOnLaunchPolicy")`), exposed as a `Flow` in place of a published property. A recents cap would bound the app's own list; Android has no system Open Recent menu.
- **React/Web**: Persist both values in `localStorage` (`JSON.stringify` of the raw string matches the source's JSON form) and model the enum as a string-literal union `'useSystem' | 'always' | 'never'`. Browsers expose no OS keep-windows setting, so `useSystem` has to resolve to an app-chosen constant, and "reopen" means restoring tabs or panels from the app's own saved state. Use a `storage` event listener in place of the source's change-notification subscription for cross-tab updates.
- **AppKit / UIKit**: This is the source implementation, on macOS. `ReopenOnLaunchPolicy.swift` declares `ReopenOnLaunchPolicy`, a `String`-backed, `Codable`, `Sendable`, `CaseIterable`, `Equatable` enum modeled on Xcode's "Restore open projects and workspaces" preference; it holds `shouldReopen(systemDefault:)`, `displayName`, and the computed `systemDefault`, which reads the `NSQuitAlwaysKeepsWindows` key from `UserDefaults.standard` (app domain, then global domain), defaulting to `false` when absent. Checking "Close windows when quitting an application" in System Settings sets that key to `false` — the inverse of the checkbox's sense. `UserSettings+Recents.swift` declares the two `@MainActor` `UserSetting<Int>` / `UserSetting<ReopenOnLaunchPolicy>` statics (`recentWindowsCount` default `10`, `reopenOnLaunchPolicy` default `.useSystem`), each backed by `@Published` and bound lazily to `UserSettings.shared` at first access (hosts must set `UserSettings.shared` before that, per its doc comment: "Client apps should create and set this"). The default `UserDefaultsSettingsStorageProvider` stores `recentWindowsCount` as a native integer and `reopenOnLaunchPolicy` as JSON-encoded data of its raw string, discarding (without logging) a decode failure and falling back to `.useSystem` — for example, writing it directly via `defaults write <bundle> reopenOnLaunchPolicy always` stores a plain string rather than JSON data, so it is ignored in favor of the default. `WindowManager.applyRecentDocumentCountFromSettings()` mirrors `recentWindowsCount` to the `NSRecentDocumentsLimit` user default (because `NSDocumentController.maximumRecentDocumentCount` is read-only), including via a Combine subscription that re-applies it on `RunLoop.main` whenever the setting changes; a new limit takes effect only on the next `noteNewRecentDocumentURL` call, so lowering it does not immediately trim an existing Open Recent list. `WindowManager.reopenRecentsOnLaunch()` evaluates `reopenOnLaunchPolicy`, passing `ReopenOnLaunchPolicy.systemDefault` as the `systemDefault:` argument, and returns early with no evaluation when there is no `NSApplication` (for example, a unit-test host); it governs document windows only — per `ProjectWindowManager.restoreOpenProjects()`'s doc comment, project windows "not consult `reopenOnLaunchPolicy`". `GeneralSettingsPanelViewController.createWindowBehaviorGroup()` presents both settings, with a recent-count stepper ranged `minValue: 0, maxValue: 50` and a "Restore windows on launch:" popup labeled by `displayName`. UIKit has neither `NSDocumentController` recents nor `NSQuitAlwaysKeepsWindows`; scene restoration via `NSUserActivity` / `stateRestorationActivity` stands in for reopening, and `useSystem` has no system value.
- **WinUI 3**: Model the enum as a C# `enum ReopenOnLaunchPolicy { UseSystem, Always, Never }` and persist it with `Enum.ToString()` / `Enum.Parse` in `Windows.Storage.ApplicationData.Current.LocalSettings.Values["reopenOnLaunchPolicy"]`, keeping the count as an `int` under `"recentWindowsCount"` (default `10`). In an unpackaged app, use a JSON file written with `System.Text.Json` instead, since `ApplicationData` requires package identity. Put a `Parse` failure inside a `TryParse` that falls back to `UseSystem`, to match policy-setting-decode-fallback. Windows has no `NSQuitAlwaysKeepsWindows`. The nearest OS signal is the per-user "Automatically save my restartable apps and restart them when I sign back in" setting (the `RestartApps` value under `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon`), read via `Microsoft.Win32.Registry` and treated as `false` when absent. Reopen itself is the app's job: persist open document paths and restore them in `App.OnLaunched`, optionally registering with `RegisterApplicationRestart`. For the recents cap, `Windows.Storage.AccessCache.StorageApplicationPermissions.MostRecentlyUsedList` has a fixed, read-only `MaximumItemsAllowed` (25), so a user-adjustable cap has to be enforced on the app's own list, or on `Windows.UI.StartScreen.JumpList` with `SystemGroupKind = JumpListSystemGroupKind.Recent`. Surface the settings through a view model implementing `INotifyPropertyChanged` in place of a published property, and keep access on the UI thread (`DispatcherQueue`) to match the source's single-actor isolation. `displayName` belongs in `.resw` resources rather than literals.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/Recents/` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
