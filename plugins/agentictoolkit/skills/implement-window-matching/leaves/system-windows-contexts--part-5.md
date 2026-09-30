<!-- leaf: implement-window-matching/system-windows-contexts--part-5 · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts — continued (part 5)

**Rules** (cite as `implement-window-matching/system-windows-contexts--part-5#<slug>`):

- `winui-3` SHOULD — Enumerate top-level windows with EnumWindows plus GetWindowThreadProcessId and GetWindowText (P/Invoke), and use HWND …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowContextStore(rootDirectory:)` | `URL` | none (required) | Root holding `state.json`, `contexts/`, `.lock`, and (by default) the custom rules file `heuristics.json`. |
| `windowManager` | `SystemWindowControlling` | none (required) | Lists windows and moves, resizes, focuses, and frames them; injected into both manager and model. |
| `windowMatcher` | `SystemWindowMatcher` | `SystemWindowMatcher()` | Fingerprinting, scoring, and batch matching; `autoAssignThreshold` is `80`. |
| `customHeuristicStore` | `CustomHeuristicStore?` | store at the state root | Persists user-defined heuristic rules. |
| `SystemWindowContextManager.parkingMargin` | `CGFloat` | `30_000` | Distance left of the leftmost screen where inactive windows are parked. |
| `createContext(name:color:)` color | `String` | `"#007AFF"` | Context color hex string. |
| `configuration.selfAppName` | `String?` | `nil` | Host app name exposed to views; own windows are excluded by PID, not by this name. |
| `configuration.settingsKey` | `String` | none (required) | `UserSettings` key for `SystemWindowContextsSettings`. |
| `configuration.contextNoun` / `contextNounPlural` | `String` | `"context"` / noun + `"s"` | Nouns used in create-failure messages and exposed to views. |
| `configuration.notificationTitle` / `notificationIdentifier` | `String` | none (required) | Reconcile notification title and request identifier. |
| `configuration.defaultContexts` | `[DefaultContext]` | `[]` | Contexts seeded on first launch. |
| `configuration.managesAppActivationPolicy` | `Bool` | `true` | Tells the settings UI whether to show the Dock toggle. |
| `isTestEnvironment` | `Bool` | `NSClassFromString("XCTestCase") != nil` | Disables notifications, observation, and seeding. |
| `notificationsEnabled` / `observationEnabled` | `Bool` | `true` (false in tests) | Runtime switches on the model. |
| `SystemWindowContextsSettings` fields | see settings-shape | see settings-shape | Launch at login, reconcile behavior, hidden apps, Dock visibility. |

## Localization

Every user-facing string in these files is a hardcoded English literal with no string-catalog lookup: the `errorDescription` of both error enums, the model's `lastError` prefixes, and the notification body.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Failed to load state: <error>` | `lastError` when `loadState()` fails |
| (none; literal) | `Failed to create <contextNoun>: <error>` | `lastError` on create; the noun comes from configuration |
| (none; literal) | `Failed to delete context: <error>` / `Failed to rename context: <error>` / `Failed to update context color: <error>` / `Failed to switch context: <error>` | `lastError` on those operations |
| (none; literal) | `Failed to add window: <error>` / `Failed to remove window: <error>` / `Failed to assign window: <error>` / `Failed to skip item: <error>` | `lastError` on window operations |
| (none; literal) | `Failed to add heuristic rule: <error>` / `Failed to update heuristic rule: <error>` / `Failed to delete heuristic rule: <error>` | `lastError` on rule operations |
| (none; literal) | `Re-matching failed: <error>` | `lastError` from launch reconciliation |
| (none; literal) | `Unmatched item not found.` | `lastError` from `assignWindow` |
| (none; literal) | `No active context. Switch to a context first.` | `lastError` from `addFrontmostWindow` |
| (none; literal) | `No window found to add.` / `No window found to remove.` | `lastError` from the frontmost-window actions |
| (none; literal) | `This window is not assigned to any context.` | `lastError` from `removeFrontmostWindow` |
| (none; literal) | `<n> window needs assignment` / `<n> windows need assignment` | Notification body, pluralized by an English-only `count == 1` test |
| (none; literal) | `Context not found: <uuid>`, `Window <id> is already assigned to context '<name>'`, `Failed to persist state: <error>`, and the other `errorDescription` values | Surfaced through `lastError` via `localizedDescription` |

Only `contextNoun` is host-configurable; the other messages say "context" regardless of the configured noun.

## Privacy

- **Data collected**: application names, window titles, window frames, and display IDs of other applications' windows, plus user-chosen context names and colors and custom rule definitions.
- **Storage**: plain, unencrypted, pretty-printed JSON files under the caller-supplied root (`state.json`, `contexts/<uuid>.json`, `heuristics.json`), written with mode defaults except the `.lock` file (`0644`); settings go to `UserSettings` under `settingsKey`.
- **Transmission**: nothing leaves the device; the only outbound effect is a local user notification whose body carries a count, not titles.
- **Retention**: files persist until the context is deleted (its file is removed), `removeAll()` is called, or the user deletes the directory; skipped or orphaned context files are never cleaned up automatically.
- **Logs**: log messages interpolate context names, app names, and window IDs (for example "Created context '<name>'"); `Logger` string interpolation is private by default, so those values are redacted in release logs unless marked public.

## Platform Notes

- **SwiftUI**: `SystemWindowContextsModel` is already the SwiftUI bridge: observe it with `@StateObject` or `@ObservedObject` and bind sheets to `showReconcileWindow`, `showContextPicker`, `showHelp`, and `showDiscovery`. A port to the Observation framework would swap `ObservableObject` and `@Published` for `@Observable`; the manager needs no change since it is already `@MainActor`.
- **Compose**: Android does not let one app move another app's windows, so parking and restoring have no equivalent; the portable part is the store (Kotlin `kotlinx.serialization` JSON files under `Context.filesDir`, `FileChannel.lock()` in place of `flock`) and the matcher. Expose model state as `StateFlow` from a `ViewModel` and run the manager on `Dispatchers.Main`.
- **React/Web**: Browsers cannot enumerate or move other applications' windows. An Electron port would keep the model and store in the main process (`fs.writeFileSync` to a temp file plus `fs.renameSync` for atomic replace, `proper-lockfile` for the lock) and move windows through a native module; renderer state would come over IPC into a store such as Zustand in place of `@Published`.
- **AppKit / UIKit**: This is the source (macOS only). `SystemWindowContextStore`, `SystemWindowContextsState`, `SystemWindowContextsSettings`, and the reconcile models live in the platform-neutral `Core` target and depend only on Foundation and `flock`. `SystemWindowContextManager`, `SystemWindowContextError`, and `SystemWindowContextsModel` live in `CoreMacOS` because they use `NSScreen.screens` for the parking x and the on-screen test, `CGWindowID`-valued `UInt32` IDs, Accessibility-backed `SystemWindowControlling` moves, `UNUserNotificationCenter`, and a PID from `ProcessInfo`. UIKit cannot manage other apps' windows, so only the `Core` files port to iOS.
- **WinUI 3**: Enumerate top-level windows with `EnumWindows` plus `GetWindowThreadProcessId` and `GetWindowText` (P/Invoke), and use `HWND` values in place of `CGWindowID`; HWNDs are also recycled, so keep the load-time invalidation. Park with `SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)` using x = `SystemInformation.VirtualScreen.Left` (or `GetSystemMetrics(SM_XVIRTUALSCREEN)`) minus 30000, restore with `SetWindowPlacement` or `SetWindowPos` and the saved `RECT`, and focus with `SetForegroundWindow` (subject to foreground-lock rules, so a failure is common and SHOULD be checked). Persist with `System.Text.Json` (`WriteIndented = true`) into `ApplicationData.Current.LocalFolder` for packaged apps or `Environment.SpecialFolder.LocalApplicationData` otherwise; write each file to a temp name and `File.Replace` or `File.Move(overwrite: true)` for atomic replace, and take the cross-process write lock with a named `Mutex` or a `FileStream` opened with `FileShare.None` on the `.lock` file. Model the manager as a class used only from the UI thread (`DispatcherQueue.HasThreadAccess` checks) to match `@MainActor`, and the model as a view model implementing `INotifyPropertyChanged` with `ObservableCollection<SystemWindowContext>` for `contexts` and `unmatchedItems`. Window lifecycle events come from `SetWinEventHook` with `EVENT_OBJECT_CREATE`, `EVENT_OBJECT_DESTROY`, and `EVENT_OBJECT_NAMECHANGE`, delivered on the thread that installed the hook, which gives the ordering the Swift source leaves open. Show the reconcile prompt with `AppNotificationManager` from the Windows App SDK, and put the `lastError` strings in `.resw` resources.

