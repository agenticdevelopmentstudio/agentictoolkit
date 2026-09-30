<!-- leaf: implement-git-client/projects-project-scan-progress-window · source: git-client-projects-project-scan-progress-window.md -->

**Rules** (cite as `implement-git-client/projects-project-scan-progress-window#<slug>`):

- `mainactor-isolation` MUST
- `fixed-panel-geometry-and-style` MUST
- `panel-title` MUST
- `floating-non-modal-presentation` MUST
- `deactivation-visibility` MUST
- `key-only-if-needed` MUST
- `centered-on-screen` MUST
- `automation-identifiers-assigned` MUST
- `initial-headline-text` MUST
- `initial-progress-bar-state` MUST
- `coder-initialization-unsupported` MUST
- `present-starts-animation-and-orders-front` MUST
- `present-guards-missing-window` MUST
- `finish-completes-progress-bar` MUST
- `finish-updates-headline-text` MUST
- `finish-schedules-delayed-close` MUST
- `finish-close-closure-strong-capture` MUST
- `react-web` MUST — Port as a small, fixed-position, non-modal status element (a div with role="status", not a native <dialog>, since …

# ProjectScanProgressWindow

## Overview

`ProjectScanProgressWindow` is an `NSWindowController` subclass that owns a
small floating panel shown while a project scan runs. It presents a headline
label and an indeterminate progress bar, and nothing else: no counts, no
scanned path, no cancel control. `present()` shows the panel and starts the
bar animating; `finish()` switches the bar to a completed determinate state,
updates the headline, and closes the panel itself one second later.
`ProjectsCoordinator.swift` constructs one instance per scan, calls
`present()` before starting the scan, calls `finish()` when the scan
completes, and drops its own reference to the instance immediately after
calling `finish()` (`ProjectsCoordinator.swift`).

## Behavioral Requirements

- **mainactor-isolation**: `ProjectScanProgressWindow` MUST be declared
  `@MainActor`, so `init()`, `present()`, `finish()`, and its `headline` and
  `bar` properties MUST only be called or accessed from the main actor
  (`ProjectScanProgressWindow.swift`).
- **fixed-panel-geometry-and-style**: `init()` MUST construct its window as
  an `NSPanel` with a content rect of 240 by 72 points and a style mask of
  `.titled` and `.utilityWindow`, created with `backing: .buffered` and
  `defer: false` (`ProjectScanProgressWindow.swift`).
- **panel-title**: `init()` MUST set the panel's `title` to "Scanning"
  (`ProjectScanProgressWindow.swift`).
- **floating-non-modal-presentation**: `init()` MUST set `isFloatingPanel` to
  `true`; the class exposes no method that presents the panel modally
  (`ProjectScanProgressWindow.swift`).
- **deactivation-visibility**: `init()` MUST set `hidesOnDeactivate` to
  `false`, so the panel remains visible when the host application becomes
  inactive (`ProjectScanProgressWindow.swift`).
- **key-only-if-needed**: `init()` MUST set `becomesKeyOnlyIfNeeded` to
  `true` (`ProjectScanProgressWindow.swift`).
- **centered-on-screen**: `init()` MUST center the panel via `panel.center()`
  (`ProjectScanProgressWindow.swift`).
- **automation-identifiers-assigned**: `init()` MUST assign the accessibility
  identifier "project-scan.window" to the panel, and `makeContentView()` MUST
  assign the accessibility identifier "project-scan.headline" to the
  headline label (`ProjectScanProgressWindow.swift`).
- **initial-headline-text**: The `headline` label MUST be initialized with
  the literal string "Scanning for projects…"
  (`ProjectScanProgressWindow.swift`).
- **initial-progress-bar-state**: `makeContentView()` MUST configure `bar`
  with style `.bar`, `isIndeterminate` `true`, `controlSize` `.small`,
  `usesThreadedAnimation` `true`, `minValue` `0`, and `maxValue` `1`
  (`ProjectScanProgressWindow.swift`).
- **coder-initialization-unsupported**: `init?(coder:)` MUST be marked
  unavailable and MUST call `fatalError` with the message "init(coder:) is
  not supported" if it is ever invoked
  (`ProjectScanProgressWindow.swift`).
- **present-starts-animation-and-orders-front**: `present()` MUST call
  `bar.startAnimation(nil)` and MUST order the window to the front via
  `orderFrontRegardless()`, never via a method that makes the window key
  (`ProjectScanProgressWindow.swift`).
- **present-guards-missing-window**: `present()` MUST do nothing — MUST NOT
  call `startAnimation` or `orderFrontRegardless` — when its `window`
  property is `nil` (`ProjectScanProgressWindow.swift`).
- **finish-completes-progress-bar**: `finish()` MUST call
  `bar.stopAnimation(nil)`, MUST set `bar.isIndeterminate` to `false`, and
  MUST set `bar.doubleValue` equal to `bar.maxValue`
  (`ProjectScanProgressWindow.swift`).
- **finish-updates-headline-text**: `finish()` MUST set
  `headline.stringValue` to the literal string "Scan complete"
  (`ProjectScanProgressWindow.swift`).
- **finish-schedules-delayed-close**: `finish()` MUST schedule a call to
  `close()` on the main queue after exactly `lingerAfterFinishing` (1.0
  second) has elapsed, via `DispatchQueue.main.asyncAfter(deadline: .now() +
  Self.lingerAfterFinishing)` (`ProjectScanProgressWindow.swift`).
- **finish-close-closure-strong-capture**: The closure `finish()` passes to
  `asyncAfter` MUST capture `self` strongly, not weakly
  (`ProjectScanProgressWindow.swift`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `lingerAfterFinishing` (private static constant) | `TimeInterval` | `1.0` | Seconds `finish()` waits before calling `close()`; not exposed to callers or configurable at the call site (`ProjectScanProgressWindow.swift`). |

`init()`, `present()`, and `finish()` take no parameters at all. There is no
caller-supplied configuration surface, environment variable, or settings key
anywhere in `ProjectScanProgressWindow.swift`. The one caller-side wiring
point lives outside this file: `ProjectsCoordinator.swift` constructs a bare
`ProjectScanProgressWindow()` with no arguments, calls `present()` before
starting a scan, and calls `finish()` when the scan completes
(`ProjectsCoordinator.swift`).

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — inline literal) | Scanning | The `NSPanel`'s window title, set in `init()` (`ProjectScanProgressWindow.swift`). |
| (none — inline literal) | Scanning for projects… | The headline label's initial text (`ProjectScanProgressWindow.swift`). |
| (none — inline literal) | Scan complete | The headline text `finish()` sets once the scan is done (`ProjectScanProgressWindow.swift`). |

None of these three strings are extracted to a string catalog, an
`NSLocalizedString` call, or any other localization mechanism; each is a
Swift string literal hardcoded at its use site
(`ProjectScanProgressWindow.swift`).

## Platform Notes

- **SwiftUI**: Model presentation state (`isPresented`, indeterminate vs.
  determinate, the headline string) in an `ObservableObject`, and drive it
  from a `ProgressView()` (indeterminate) that switches to
  `ProgressView(value: 1, total: 1)` when finished, hosted in a small
  auxiliary window or `NSHostingView`-backed panel rather than a SwiftUI
  `Window` scene, since a `Window` scene cannot reproduce
  `becomesKeyOnlyIfNeeded`/`orderFrontRegardless` semantics on its own. Use
  `Task { try? await Task.sleep(for: .seconds(1)) }` in place of
  `DispatchQueue.main.asyncAfter`, and keep the presenting object retained
  by that `Task` (or by the view model) for the same reason `self` is
  captured strongly in the source.
- **Compose**: There is no Compose Desktop equivalent of an AppKit utility
  panel that floats above other windows without taking focus; approximate it
  with a small, undecorated `androidx.compose.ui.window.Window` (or a
  non-modal `Dialog` with `focusable = false` in its `DialogProperties`) to
  approximate `becomesKeyOnlyIfNeeded`. Use a `CircularProgressIndicator()`
  (indeterminate) that switches to `CircularProgressIndicator(progress = {
  1f })` on completion, and use a `kotlinx.coroutines.delay(1000)` inside a
  `CoroutineScope` owned by the panel itself (not by the caller) before
  closing it, to reproduce the deliberate strong-capture lifetime.
- **React/Web**: Port as a small, fixed-position, non-modal status element
  (a `div` with `role="status"`, not a native `<dialog>`, since `<dialog>`
  implies modal semantics this component deliberately avoids) containing a
  spinner and the headline text, swapped for a "Scan complete" state on
  finish. Use `setTimeout(..., 1000)` to remove it from the DOM; because a
  JavaScript closure keeps its captured variables alive by default, there is
  no weak-capture failure mode to reproduce, but a cleanup effect (e.g. a
  React `useEffect` teardown) MUST NOT clear that timer early, or the panel
  will never disappear.
- **AppKit / UIKit**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectScanProgressWindow.swift`,
  using `NSWindowController`, `NSPanel`, `NSProgressIndicator`,
  `NSStackView`, `NSLayoutConstraint`, and `DispatchQueue.main.asyncAfter`,
  plus two components from the project's shared AppKit UI toolkit,
  `ThemedLabel` and `ThemedBackgroundView`, and an `accessibilityID(_:)`
  helper for identifier assignment. UIKit has no equivalent of a separate,
  always-on-top utility window that does not take focus; a UIKit port would
  need a floating overlay `UIView` pinned within the current window's view
  hierarchy (e.g. a small banner anchored to a corner via Auto Layout)
  rather than a second `UIWindow`.
- **WinUI 3**: This is the platform this recipe exists to unblock. Represent
  the panel as a secondary `Window` (or `Microsoft.UI.Xaml.Window` opened via
  interop) whose native `HWND` owner is set to the main window's `HWND`
  through `WinRT.Interop.WindowNative.GetWindowHandle` plus
  `Microsoft.UI.Windowing.AppWindow.GetFromWindowId`/`SetOwner`, giving the
  same "floats above, closes with, but is not blocked by" relationship
  `isFloatingPanel` gives on AppKit. Show it without ever calling
  `Window.Activate()` — call the Win32 `ShowWindow` with `SW_SHOWNOACTIVATE`
  through interop instead — to reproduce `becomesKeyOnlyIfNeeded` and
  `orderFrontRegardless()`'s "visible but never key" behavior. Content is a
  XAML `ProgressBar` with `IsIndeterminate="True"` bound to a view model
  implementing `INotifyPropertyChanged`, alongside a `TextBlock` bound to the
  headline string; `finish()` flips `IsIndeterminate` to `false` and sets
  `Value` equal to `Maximum`. Use `await Task.Delay(TimeSpan.FromSeconds(1))`
  for the linger, then resume on the UI thread via
  `DispatcherQueue.TryEnqueue` before calling `Window.Close()` (a
  `Task.Delay` continuation does not automatically resume on the UI thread
  the way `DispatchQueue.main.asyncAfter` does). Keep a strong reference to
  the window instance across that awaited delay — in a field, not a local
  that can be collected — to reproduce the deliberate strong `self` capture
  in `finish()`; a weak reference here would let the window be
  garbage-collected before `Close()` runs, leaving it on screen exactly as
  the source's inline comment warns.

