<!-- leaf: implement-window-matching/window-discovery--part-2 · source: window-matching-window-discovery.md -->

# WindowDiscoveryViewModel — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `session` | `SessionWatcher.SessionWatcherSession` | required | Supplies `projectName` (last path component of `cwd`, or `"Unknown"`) that windows are matched against. |
| `onWindowActivated` | `(() -> Void)?` | `nil` | Called after a successful focus so the host can close the panel. |
| `HeuristicRegistry.shared` | shared singleton | built-in Xcode, Warp, Brave, VS Code, Terminal heuristics plus any registered custom rules | Per-app title-pattern extraction used by `matches`; not injectable. |
| `SystemWindowManager` | private engine instance | created per model | Window enumeration and focus; not injectable. |
| Accessibility permission | system trust state | — | Required for discovery; read via `SystemAccessibilityPermission.isGranted`. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Unknown` | Fallback `DiscoveredApp.name` for an application with no localized name; hardcoded English, not localized. |

The `"Unknown"` compared in `matches` is the sentinel value from `SessionWatcherSession.projectName`, not display text. Log messages are English developer diagnostics and are not localized.

## Privacy

- **Data collected**: the titles, pids and window numbers of every titled window owned by a regular app, plus each app's localized name and icon.
- **Storage**: in memory only, in `apps`; nothing is written to disk.
- **Transmission**: none; no data leaves the device.
- **Retention**: until the next discovery replaces `apps` or the model is released. The activation log line records the chosen window's title as public (unredacted) text in the unified log, where it is retained under the system's log policy.

## Platform Notes

- **SwiftUI**: Source is Swift/AppKit: `WindowDiscoveryViewModel.swift` in `AgenticToolkit/macOS/Features/WindowDiscovery`, driven by the AppKit `WindowDiscoveryView` through Combine subscriptions to `$isLoading`, `$accessibilityDenied` and `$apps`. A SwiftUI host can bind the same `ObservableObject` with `@ObservedObject`; a port to Swift 6 style would make it `@MainActor @Observable` and run enumeration in a `Task.detached`, replacing `DispatchQueue` hops and the `@unchecked Sendable`.
- **Compose**: Android has no cross-app window enumeration or focus API; a Kotlin port keeps only the pure parts — `matches` as a plain function and the grouping/sort over a `List` with `sortedWith(compareByDescending { it.hasMatch }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })` — exposed from a `ViewModel` via `StateFlow`, with enumeration running in `viewModelScope.launch(Dispatchers.Default)`.
- **React/Web**: Browsers cannot see other applications' windows; a web port applies only to an Electron-style host (`desktopCapturer.getSources({ types: ['window'] })` gives titles and ids). Matching becomes `title.toLocaleLowerCase().includes(project.toLocaleLowerCase())` and sorting uses `localeCompare` with `sensitivity: 'base'`; state lives in a store or `useState`.
- **AppKit / UIKit**: This is the AppKit source. Enumeration relies on `CGWindowListCopyWindowInfo` with the all-windows option, `NSWorkspace.shared.runningApplications` filtered on `activationPolicy == .regular`, Accessibility (`AXIsProcessTrusted`, AX raise action) for backfill and focus, and `NSRunningApplication.activate()`. UIKit has no equivalent; iOS apps cannot enumerate or focus other apps' windows.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject` with `[ObservableProperty]`) exposing `IsLoading`, `AccessibilityDenied` and an `ObservableCollection<DiscoveredApp>`. Enumerate with Win32 `EnumWindows` + `IsWindowVisible`/`GetWindowText`/`GetWindowThreadProcessId` via CsWin32 P/Invoke, keeping windows whose owner has a main window (`Process.MainWindowHandle != IntPtr.Zero`) as the "regular app" analogue, and taking icons from `Icon.ExtractAssociatedIcon` on the process path. Run it in `Task.Run` and marshal back with `DispatcherQueue.TryEnqueue`. Focus with `SetForegroundWindow` after `ShowWindow(hwnd, SW_RESTORE)` for minimized windows. Differences: Windows needs no Accessibility permission to read titles, so the denied branch has no direct counterpart (UI Automation is only needed for elevated windows); `SetForegroundWindow` can be refused by the foreground-lock rules and returns `false` rather than throwing, which maps to the failure-logged path. Sort with `StringComparer.CurrentCultureIgnoreCase` and match with `title.Contains(project, StringComparison.CurrentCultureIgnoreCase)`.

## Design Decisions

**Decision**: Match on the heuristic pattern OR the raw title.
**Rationale**: The source comment says the raw-title check is kept "so existing substring matches still hold". For the built-in Xcode heuristic the pattern is a prefix of the title, so the raw-title test already covers it; the pattern only adds matches when a custom heuristic returns text not present verbatim in the title.
**Approved**: pending

**Decision**: Treat `"Unknown"` and the empty string as "no project".
**Rationale**: `SessionWatcherSession.projectName` returns `"Unknown"` for an empty or root cwd; matching it would flag any window whose title contains the word.
**Approved**: pending

**Decision**: Include minimized and off-screen windows.
**Rationale**: The type's doc comment says the panel lists them "so the user can bring any of them back"; the engine's focus moves a parked window back on-screen.
**Approved**: pending

**Decision**: Keep the panel open when focus fails, reporting only via the log.
**Rationale**: The `activateWindow` doc comment: "on failure it logs and leaves the panel open so the user can retry or pick another window, rather than silently closing as if it worked."
**Approved**: pending

**Decision**: Snapshot running apps on the calling thread, enumerate windows in the background.
**Rationale**: The source comment names `NSWorkspace`/`NSRunningApplication` as main-thread APIs; the window list and Accessibility backfill can be slow, so they run off the main thread.
**Approved**: pending
