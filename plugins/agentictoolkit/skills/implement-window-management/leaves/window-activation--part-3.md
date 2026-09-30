<!-- leaf: implement-window-management/window-activation--part-3 · source: window-management-window-activation.md -->

# Window Activation — continued (part 3)

## Platform Notes

- **SwiftUI**: No SwiftUI surface. A SwiftUI host would run `runAllTests()` inside `Task.detached` and bind `ActivationTestLog.text` into a view after completion; the package itself stays AppKit and ApplicationServices based.
- **Compose**: Android has no cross-app window activation; a port would limit itself to bringing its own task forward via `ActivityManager.moveTaskToFront` or an `Intent` with `FLAG_ACTIVITY_REORDER_TO_FRONT`. The log maps to a `Mutex`-guarded `MutableList<String>` plus `File.appendText`, with `Dispatchers.IO` for the blocking work.
- **React/Web**: Browsers cannot enumerate or raise other applications' windows; only `window.focus()` on a window the page opened is possible. An Electron port would use `BrowserWindow.focus()` for its own windows and a native module for others; the log maps to `fs.appendFileSync` with `new Date().toISOString()`.
- **AppKit / UIKit**: Source platform. `BuiltInActivationStrategies.swift` and `WindowActivationTester.swift` use `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue` with `kAXWindowsAttribute` / `kAXTitleAttribute` / `kAXFocusedWindowAttribute`, `AXUIElementPerformAction(kAXRaiseAction)`, `AXIsProcessTrusted`, `NSRunningApplication.activate()` and `NSApp.activate(ignoringOtherApps:)`; `RunningAppsProvider.swift` wraps `NSWorkspace`; `TTYResolver.swift` uses `Process` and `Pipe`; `ActivationTestLog.swift` uses a serial `DispatchQueue`, `ISO8601DateFormatter` and `FileHandle`; AppleScript goes through `AppleScriptRunner` (`NSAppleScript`). UIKit has no equivalent: iOS apps cannot activate other apps' windows.
- **WinUI 3**: Enumerate top-level windows with Win32 `EnumWindows` plus `GetWindowText` / `GetWindowThreadProcessId` (P/Invoke or CsWin32), or UI Automation (`System.Windows.Automation.AutomationElement.RootElement.FindAll` with `NameProperty`) as the analogue of the AX title walk; raise with `SetForegroundWindow` (subject to foreground-lock rules, often needing `AllowSetForegroundWindow` or an `AttachThreadInput` workaround) and `ShowWindow(SW_RESTORE)`. Running apps come from `System.Diagnostics.Process.GetProcesses()` / `GetProcessesByName`, with `Process.MainWindowHandle` for the bring-to-front strategy; the catalog keys become process names (`WindowsTerminal`, `Code`) since `$TERM_PROGRAM` is rarely set. The iTerm2 TTY strategy has no Windows analogue; a Windows Terminal port would match by title or use `wt.exe` focus-tab commands. Verification reads `GetForegroundWindow` then `GetWindowText`. There is no Accessibility-trust gate, but UIPI blocks raising elevated windows from a non-elevated process. The log maps to a `lock`-guarded `List<string>` plus `File.AppendAllText` under `Windows.Storage.ApplicationData.Current.LocalFolder` (packaged) or `Environment.SpecialFolder.LocalApplicationData`, timestamps from `DateTimeOffset.UtcNow.ToString("o")`; `runAllTests` becomes a `Task.Run` returning `(int Passed, int Failed)`, with `Task.Delay` replacing `Thread.sleep` and `DispatcherQueue.TryEnqueue` replacing the final main-queue hop.

## Design Decisions

**Decision**: Activation is a cascade of pluggable `WindowActivationStrategy` values run in order, stopping at the first success.
**Rationale**: Each terminal needs a different technique (AppleScript TTY lookup for iTerm2, accessibility title match for others, plain app activation as a last resort); the protocol's `appliesTo` gate keeps inapplicable strategies out of the log as FAILED lines, and callers can supply their own list.
**Approved**: pending

**Decision**: Verification after the cascade only checks that some window other than the host app is frontmost with a non-empty title, and the host app is reported under the fixed label `Sessions`.
**Rationale**: The harness was written for the Session Watcher's "Sessions" window; the check detects "focus left our app" rather than "the target is frontmost", which makes PASS a weak signal (see Edge Cases).
**Approved**: pending

**Decision**: Fixed blocking sleeps (0.15 s, 0.5 s, 1.0 s) sequence activation, verification and the next target.
**Rationale**: App activation and window raising complete asynchronously in the window server; the harness is documented to run on a background thread, so blocking sleeps are an accepted diagnostic-only cost.
**Approved**: pending

**Decision**: `ActivationTestLog` never truncates an existing file on append and silently drops a line it cannot write.
**Rationale**: The `appendToFile` doc comment prefers losing one line over risking truncation of the history; memory keeps every entry regardless.
**Approved**: pending

**Decision**: `RunningAppsProvider` abstracts `NSWorkspace` so strategies and the tester can run against a stubbed app list, while the terminal inventory always uses `KnownTerminals.all`.
**Rationale**: Testability of strategies was the goal of the abstraction; the inventory is diagnostic output and was not parameterized by catalog.
**Approved**: pending
