---
id: 46e79f87-0dbb-4bd5-b11c-bd65ae0087a9
title: ProjectScanProgressWindow
domain: agentictoolkit://recipes/git-client-projects-project-scan-progress-window
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Floating, non-modal AppKit panel that shows an indeterminate progress bar
  while a project scan runs, then completes and closes itself a second later.
platforms:
- swift
- macos
tags:
- git
- projects
- window-controller
- progress
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/git-client-projects-git-repo-scanner
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectScanProgressWindow.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a window controller, not a visual component.

## States

Not applicable — this is a window controller, not a visual component.

## Accessibility

Not applicable — this is a window controller, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-scan-progress-window-001 | mainactor-isolation | Call `present()` or `finish()` from code that is not on the main actor and does not `await` the call. | Compilation fails, since `ProjectScanProgressWindow` is `@MainActor` and neither method is `nonisolated` or `async`. |
| git-client-projects-project-scan-progress-window-002 | fixed-panel-geometry-and-style | Construct `ProjectScanProgressWindow()`. | The instance's `window` is an `NSPanel` whose initial content size is 240×72 points and whose `styleMask` contains `.titled` and `.utilityWindow`. |
| git-client-projects-project-scan-progress-window-003 | panel-title | Construct `ProjectScanProgressWindow()`. | `window!.title` equals "Scanning". |
| git-client-projects-project-scan-progress-window-004 | floating-non-modal-presentation | Construct `ProjectScanProgressWindow()`. | `window!.isFloatingPanel` equals `true`; the class exposes no modal-presentation method to call instead. |
| git-client-projects-project-scan-progress-window-005 | deactivation-visibility | Construct `ProjectScanProgressWindow()`. | `window!.hidesOnDeactivate` equals `false`. |
| git-client-projects-project-scan-progress-window-006 | key-only-if-needed | Construct `ProjectScanProgressWindow()`. | `window!.becomesKeyOnlyIfNeeded` equals `true`. |
| git-client-projects-project-scan-progress-window-007 | centered-on-screen | Construct `ProjectScanProgressWindow()`. | `window!.frame` is centered on the screen that contains it, per `NSWindow.center()`. |
| git-client-projects-project-scan-progress-window-008 | automation-identifiers-assigned | Construct `ProjectScanProgressWindow()`. | The panel's accessibility identifier equals "project-scan.window" and the headline view's accessibility identifier equals "project-scan.headline". |
| git-client-projects-project-scan-progress-window-009 | initial-headline-text | Construct `ProjectScanProgressWindow()` and read the headline before calling `present()` or `finish()`. | The headline label's `stringValue` equals "Scanning for projects…". |
| git-client-projects-project-scan-progress-window-010 | initial-progress-bar-state | Construct `ProjectScanProgressWindow()`. | `bar.style` equals `.bar`, `bar.isIndeterminate` equals `true`, `bar.controlSize` equals `.small`, `bar.usesThreadedAnimation` equals `true`, `bar.minValue` equals `0`, and `bar.maxValue` equals `1`. |
| git-client-projects-project-scan-progress-window-011 | coder-initialization-unsupported | Call `ProjectScanProgressWindow(coder:)` with any `NSCoder`. | The process terminates via `fatalError` with the message "init(coder:) is not supported". |
| git-client-projects-project-scan-progress-window-012 | present-starts-animation-and-orders-front | Construct `ProjectScanProgressWindow()`, then call `present()`. | `bar`'s animation is running and the window becomes visible on screen without becoming the key window. |
| git-client-projects-project-scan-progress-window-013 | present-guards-missing-window | On an instance whose `window` has been set to `nil`, call `present()`. | No crash occurs; `bar.startAnimation` is not invoked and no window is ordered front. |
| git-client-projects-project-scan-progress-window-014 | finish-completes-progress-bar | Construct, call `present()`, then call `finish()`. | `bar.isIndeterminate` becomes `false` and `bar.doubleValue` equals `bar.maxValue` (`1`). |
| git-client-projects-project-scan-progress-window-015 | finish-updates-headline-text | Construct, call `present()`, then call `finish()`. | The headline label's `stringValue` equals "Scan complete". |
| git-client-projects-project-scan-progress-window-016 | finish-schedules-delayed-close | Call `finish()`, then observe the window before and after 1.0 second elapses. | Before 1.0 second, `window!.isVisible` is still `true`; after 1.0 second, `close()` has been called and `window!.isVisible` is `false`. |
| git-client-projects-project-scan-progress-window-017 | finish-close-closure-strong-capture | Call `finish()`, then immediately release every external strong reference to the instance. | After 1.0 second, the panel still closes itself; the instance is not deallocated early, since its own `asyncAfter` closure holds a strong reference to `self`. |
| git-client-projects-project-scan-progress-window-018 | finish-completes-progress-bar, finish-updates-headline-text, finish-schedules-delayed-close | Construct `ProjectScanProgressWindow()` and call `finish()` without ever calling `present()`. | The bar and headline update exactly as in vectors 014-015, and `close()` still fires after 1.0 second, even though the window was never shown. |
| git-client-projects-project-scan-progress-window-019 | present-starts-animation-and-orders-front | Call `present()` twice in succession. | `bar.startAnimation` is invoked again and the window is simply re-ordered front; no error and no duplicate window are produced. |
| git-client-projects-project-scan-progress-window-020 | finish-schedules-delayed-close | Call `finish()` twice in succession. | Two `asyncAfter` closures are scheduled; the first calls `close()` after 1.0 second, and the second's `close()` call on the already-closed window is a no-op that produces no crash. |

## Edge Cases

- **Null and empty input**: Not applicable — none of `init()`, `present()`,
  or `finish()` accept any parameter, so there is no null or empty input to
  handle (`ProjectScanProgressWindow.swift`).
- **Boundary values**: The progress bar's range is fixed at `minValue` `0`
  and `maxValue` `1`, and the close delay is fixed at `lingerAfterFinishing`
  (1.0 second); none of these are caller-supplied, so there is no boundary
  condition a caller can vary (`ProjectScanProgressWindow.swift`). MUST (this is the file's actual, unparameterized behavior).
- **Concurrent access**: `ProjectScanProgressWindow` is `@MainActor`, so all
  access to `headline`, `bar`, and `window` is serialized onto the main
  actor by the compiler. Calling `finish()` a second time before the first
  call's scheduled `close()` fires MUST queue a second `asyncAfter` closure
  that also calls `close()`; the second call lands on an already-closing or
  already-closed window, which is a harmless no-op
  (`ProjectScanProgressWindow.swift`). MUST.
- **Error states**: The only defensive check in the file is `present()`'s
  guard against a `nil` `window`; it MUST return silently, with no
  error signal of any kind, since the file declares no `throws` function, no
  `Result` type, and no other error-reporting mechanism
  (`ProjectScanProgressWindow.swift`). MUST.
- **Offline or disconnected state**: Not applicable —
  `ProjectScanProgressWindow.swift` makes no network call; its only work is
  updating local AppKit UI state and scheduling one local timer (whole
  file).
- **Cancellation**: The type provides no cancel operation of any kind; the
  type's doc comment states directly that the panel is "deliberately not
  modal and deliberately not cancellable"
  (`ProjectScanProgressWindow.swift`). This is the file's actual
  behavior, not an unresolved gap.
- **Out-of-order calls**: `finish()` MUST behave identically whether or not
  `present()` was called first — it updates `bar` and `headline` and
  schedules `close()` unconditionally; a panel that was never shown is
  simply closed once, while still hidden
  (`ProjectScanProgressWindow.swift`). MUST.

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

## Deep Linking

Not applicable: `ProjectScanProgressWindow.swift` defines no URL scheme,
route, or navigation destination (whole file).

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

## Accessibility Options

Not applicable: `ProjectScanProgressWindow.swift` contains no check of
`accessibilityDisplayShouldReduceMotion`,
`accessibilityDisplayShouldIncreaseContrast`,
`accessibilityDisplayShouldDifferentiateWithoutColor`, or any other
accessibility display option; `usesThreadedAnimation` is set unconditionally
(`ProjectScanProgressWindow.swift`), and the file has no color-only
state distinction for Differentiate Without Color to apply to.

## Feature Flags

Not applicable: `ProjectScanProgressWindow.swift` contains no feature-flag or
build-configuration check of any kind (whole file).

## Analytics

Not applicable: `ProjectScanProgressWindow.swift` makes no analytics or
event-tracking call of any kind (whole file).

## Privacy

Not applicable: `ProjectScanProgressWindow.swift` handles no credential or
token and displays only the two static status strings above. The type's doc
comment explains that an earlier version's per-directory counts and the
scanned path were deliberately removed because they were "registry
bookkeeping the user had not asked for and could not act on" and "unreadable
at the speed the walk produces it" (`ProjectScanProgressWindow.swift`); the current panel reports no scan results, counts, or file-system
paths at all.

## Logging

Not applicable: `ProjectScanProgressWindow.swift` makes no logging call of
any kind; state changes are communicated only through the visible headline
text and progress bar (whole file).

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

## Design Decisions

**Decision**: The panel reports no per-directory counts and no scanned path,
only the fixed strings "Scanning for projects…" and "Scan complete".
**Rationale**: The type's doc comment states the counts were "registry
bookkeeping the user had not asked for and could not act on," and the path
"flickered through was unreadable at the speed the walk produces it"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: The panel is not presented modally.
**Rationale**: The doc comment states "the scan touches nothing the user
could be editing, so blocking them out of the app would buy nothing"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: The panel provides no Cancel control.
**Rationale**: The doc comment states "a Cancel button that leaves the
registry half-reconciled is worse than a scan that finishes"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: `present()` orders the window front without making it key
(`orderFrontRegardless()` rather than `makeKeyAndOrderFront`), and
`becomesKeyOnlyIfNeeded` is set to `true`.
**Rationale**: The doc comment on `present()` states this is "so a scan at
launch does not steal focus from whatever the user is already doing"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: `finish()` leaves the bar at its full determinate value rather
than leaving it indeterminate or resetting it to empty.
**Rationale**: The doc comment on `finish()` states "an indeterminate bar
frozen part-way through reads as a scan that gave up"
(`ProjectScanProgressWindow.swift`).
**Approved**: pending

**Decision**: The `asyncAfter` closure in `finish()` captures `self`
strongly rather than weakly.
**Rationale**: The inline comment states this directly: the caller "drops
its reference as soon as it has asked for the finish, so a weak capture
leaves nothing alive to run `close()` and the panel stays on screen for
good" (`ProjectScanProgressWindow.swift`), which matches
`ProjectsCoordinator.swift` setting `progressWindow = nil` immediately after
calling `finish()` (`ProjectsCoordinator.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |

Notes: separation-of-concerns passes because
`ProjectScanProgressWindow.swift` does exactly one thing — present and
retire a progress panel — and holds no scan logic, no filesystem access, and
no knowledge of `GitRepoScanner`; the scan itself and the decision to show
this panel both live in `ProjectsCoordinator.swift`. unit-test-coverage
fails because no test file exists for this type anywhere in the repository —
a repository-wide search found only `ProjectScanProgressWindow.swift` itself
and its one caller, `ProjectsCoordinator.swift`, with no
`ProjectScanProgressWindowTests.swift` or equivalent. explicit-error-handling
passes because the file's one `Optional` unwrap, `guard let window else {
return }` in `present()`, is handled with an explicit guard rather than a
force-unwrap, and represents "no window to act on," not a swallowed error —
the file has no `throws` function and nothing that discards a thrown or
returned error. fault-tolerance passes because that same guard means calling
`present()` on an instance with no window cannot crash; every other public
entry point (`finish()`) is unconditional and cannot fail regardless of
prior call order, as shown by test vectors 018-020. native-controls-preference
passes because the panel is composed entirely from native AppKit controls —
`NSPanel`, `NSProgressIndicator`, `NSStackView` — with no custom-drawn
progress indicator or window chrome.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
