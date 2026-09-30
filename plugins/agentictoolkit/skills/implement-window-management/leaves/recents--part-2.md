<!-- leaf: implement-window-management/recents--part-2 · source: window-management-recents.md -->

# Window Management Recents — continued (part 2)

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
