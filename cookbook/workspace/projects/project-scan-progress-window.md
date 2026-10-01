---
id: 46e79f87-0dbb-4bd5-b11c-bd65ae0087a9
title: Project Scan Progress Window
domain: agentictoolkit://cookbook/workspace/projects/project-scan-progress-window
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Floating, non-modal panel that shows an indeterminate progress indicator
  while a project scan runs, then completes and closes itself a second later.
platforms:
- swift
- macos
tags:
- git
- projects
- window-controller
- progress
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/git-repo-scanner
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectScanProgressWindow.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Scan Progress Window

## Overview

The progress window owns a small floating panel shown while a project scan
runs. It presents a headline label and an indeterminate progress indicator,
and nothing else: no counts, no scanned path, no cancel control. Presenting
it shows the panel and starts the indicator animating; finishing it switches
the indicator to a completed determinate state, updates the headline, and
closes the panel itself one second later. The projects coordinator
constructs one instance per scan, presents it before starting the scan,
finishes it when the scan completes, and drops its own reference to the
instance immediately after finishing it.

## Behavioral Requirements

- **main-thread-confined**: the progress window's construction, its present
  and finish operations, and its headline and progress-indicator state MUST
  only be accessed from the UI's main execution context.
- **fixed-panel-geometry-and-style**: construction MUST give the panel a
  content size of 240 by 72 points and a chrome style of a titled,
  utility-style window.
- **panel-title**: construction MUST set the panel's title to "Scanning".
- **floating-non-modal-presentation**: construction MUST make the panel a
  floating, non-modal panel; nothing exposed by this component presents it
  modally.
- **deactivation-visibility**: construction MUST leave the panel visible
  when the host application becomes inactive, rather than hiding it on
  deactivation.
- **key-only-if-needed**: construction MUST configure the panel so it
  becomes the focused window only if something inside it actually requires
  focus, never simply by being shown.
- **centered-on-screen**: construction MUST center the panel on the screen
  that contains it.
- **automation-identifiers-assigned**: construction MUST assign the
  automation identifier "project-scan.window" to the panel, and MUST assign
  the automation identifier "project-scan.headline" to the headline label.
- **initial-headline-text**: the headline label MUST be initialized with
  the literal string "Scanning for projects…".
- **initial-progress-bar-state**: the progress indicator MUST be
  initialized as an indeterminate bar at a small control size, animated on
  its own thread, with a value range of 0 to 1.
- **present-starts-animation-and-orders-front**: presenting MUST start the
  progress indicator's animation and MUST bring the window to the front
  without making it the focused (key) window.
- **present-guards-missing-window**: presenting MUST do nothing — MUST NOT
  start the animation or bring anything to the front — when the panel's
  window no longer exists.
- **finish-completes-progress-bar**: finishing MUST stop the progress
  indicator's animation, MUST switch it to a determinate state, and MUST
  set its value to its maximum.
- **finish-updates-headline-text**: finishing MUST set the headline text to
  the literal string "Scan complete".
- **finish-schedules-delayed-close**: finishing MUST schedule the panel to
  close on the main thread after exactly the linger duration (1.0 second)
  has elapsed.
- **finish-outlives-caller-reference**: the scheduled close MUST keep the
  panel itself alive until it fires, even if every other reference to the
  instance has already been released by the time it runs.

## Appearance

Not applicable — this is a window controller, not a visual component.

## States

Not applicable — this is a window controller, not a visual component.

## Accessibility

Not applicable — this is a window controller, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-scan-progress-window-001 | main-thread-confined | Call present or finish from code that is not on the UI's main execution context and does not hand off to it. | The call is rejected before it can run, since the progress window is confined to the main execution context and neither operation offers an off-context path. |
| git-client-projects-project-scan-progress-window-002 | fixed-panel-geometry-and-style | Construct the progress window. | The instance's window has an initial content size of 240×72 points and a titled, utility-style chrome. |
| git-client-projects-project-scan-progress-window-003 | panel-title | Construct the progress window. | The window's title equals "Scanning". |
| git-client-projects-project-scan-progress-window-004 | floating-non-modal-presentation | Construct the progress window. | The window is a floating panel; the component exposes no modal-presentation operation to call instead. |
| git-client-projects-project-scan-progress-window-005 | deactivation-visibility | Construct the progress window. | The window stays visible when the host application deactivates. |
| git-client-projects-project-scan-progress-window-006 | key-only-if-needed | Construct the progress window. | The window becomes the focused (key) window only if something inside it needs focus. |
| git-client-projects-project-scan-progress-window-007 | centered-on-screen | Construct the progress window. | The window's frame is centered on the screen that contains it. |
| git-client-projects-project-scan-progress-window-008 | automation-identifiers-assigned | Construct the progress window. | The panel's automation identifier equals "project-scan.window" and the headline view's automation identifier equals "project-scan.headline". |
| git-client-projects-project-scan-progress-window-009 | initial-headline-text | Construct the progress window and read the headline before presenting or finishing it. | The headline label's text equals "Scanning for projects…". |
| git-client-projects-project-scan-progress-window-010 | initial-progress-bar-state | Construct the progress window. | The progress indicator is indeterminate, at a small control size, animated on its own thread, with a value range of 0 to 1. |
| git-client-projects-project-scan-progress-window-012 | present-starts-animation-and-orders-front | Construct the progress window, then present it. | The progress indicator's animation is running and the window becomes visible on screen without becoming the focused window. |
| git-client-projects-project-scan-progress-window-013 | present-guards-missing-window | On an instance whose window no longer exists, call present. | No crash occurs; the animation is not started and no window is brought to the front. |
| git-client-projects-project-scan-progress-window-014 | finish-completes-progress-bar | Construct, present, then finish. | The progress indicator becomes determinate and its value equals its maximum (`1`). |
| git-client-projects-project-scan-progress-window-015 | finish-updates-headline-text | Construct, present, then finish. | The headline label's text equals "Scan complete". |
| git-client-projects-project-scan-progress-window-016 | finish-schedules-delayed-close | Finish, then observe the window before and after 1.0 second elapses. | Before 1.0 second, the window is still visible; after 1.0 second, the window has closed. |
| git-client-projects-project-scan-progress-window-017 | finish-outlives-caller-reference | Finish, then immediately release every external reference to the instance. | After 1.0 second, the panel still closes itself; the instance is not disposed of early. |
| git-client-projects-project-scan-progress-window-018 | finish-completes-progress-bar, finish-updates-headline-text, finish-schedules-delayed-close | Construct the progress window and finish it without ever presenting it. | The indicator and headline update exactly as in vectors 014-015, and the window still closes after 1.0 second, even though it was never shown. |
| git-client-projects-project-scan-progress-window-019 | present-starts-animation-and-orders-front | Call present twice in succession. | The animation is started again and the window is simply re-ordered to the front; no error and no duplicate window are produced. |
| git-client-projects-project-scan-progress-window-020 | finish-schedules-delayed-close | Call finish twice in succession. | Two delayed closes are scheduled; the first closes the window after 1.0 second, and the second's close on the already-closed window is a no-op that produces no crash. |

## Edge Cases

- **Null and empty input**: Not applicable — none of construction,
  presenting, or finishing accept any parameter, so there is no null or
  empty input to handle.
- **Boundary values**: The progress indicator's range is fixed at 0 to 1,
  and the close delay is fixed at 1.0 second; none of these are
  caller-supplied, so there is no boundary condition a caller can vary.
  MUST (this is the component's actual, unparameterized behavior).
- **Concurrent access**: all access to the headline, progress indicator,
  and window state is confined to the UI's main execution context (see
  `main-thread-confined`). Calling finish a second time before the first
  call's scheduled close fires MUST queue a second delayed close that also
  closes the panel; the second call lands on an already-closing or
  already-closed window, which is a harmless no-op. MUST.
- **Error states**: the only defensive check is present's guard against a
  missing window; it MUST return silently, with no error signal of any
  kind, since nothing here throws or returns an error value. MUST.
- **Offline or disconnected state**: Not applicable — nothing here makes a
  network call; its only work is updating local UI state and scheduling one
  local timer.
- **Cancellation**: the component provides no cancel operation of any
  kind; it is deliberately not modal and deliberately not cancellable. This
  is the component's actual behavior, not an unresolved gap.
- **Out-of-order calls**: finishing MUST behave identically whether or not
  presenting was called first — it updates the indicator and headline and
  schedules the close unconditionally; a panel that was never shown is
  simply closed once, while still hidden. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| linger duration (internal constant) | duration (seconds) | `1.0` | Seconds finishing waits before closing the panel; not exposed to callers or configurable at the call site. |

Construction, presenting, and finishing take no parameters at all. There is
no caller-supplied configuration surface, environment variable, or settings
key anywhere here. The one caller-side wiring point lives outside this
component: the projects coordinator constructs a bare instance with no
arguments, presents it before starting a scan, and finishes it when the scan
completes.

## Deep Linking

Not applicable: the progress window defines no URL scheme, route, or
navigation destination.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — inline literal) | Scanning | The panel's window title, set at construction. |
| (none — inline literal) | Scanning for projects… | The headline label's initial text. |
| (none — inline literal) | Scan complete | The headline text set when finishing. |

None of these three strings are extracted to a string catalog or any other
localization mechanism; each is a literal hardcoded at its use site.

## Accessibility Options

Not applicable: the progress window contains no check of Reduce Motion,
Increase Contrast, Differentiate Without Color, or any other accessibility
display option; the progress indicator's threaded-animation setting is
applied unconditionally, and the component has no color-only state
distinction for Differentiate Without Color to apply to.

## Feature Flags

Not applicable: the progress window contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: the progress window makes no analytics or event-tracking
call of any kind.

## Privacy

Not applicable: the progress window handles no credential or token and
displays only the two static status strings above. An earlier version's
per-directory counts and the scanned path were deliberately removed because
they were "registry bookkeeping the user had not asked for and could not
act on" and "unreadable at the speed the walk produces it"; the current
panel reports no scan results, counts, or file-system paths at all.

## Logging

Not applicable: the progress window makes no logging call of any kind;
state changes are communicated only through the visible headline text and
progress indicator.

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
  helper for identifier assignment. The type is declared `@MainActor`, so
  `init()`, `present()`, `finish()`, and its `headline` and `bar`
  properties can only be called or accessed from the main actor — a call
  from off the main actor fails to compile unless awaited across an
  isolation boundary. The window is constructed as an `NSPanel` with a
  content rect of 240 by 72 points, a style mask of `.titled` and
  `.utilityWindow`, `backing: .buffered`, and `defer: false`;
  `isFloatingPanel` is set to `true` and `hidesOnDeactivate` to `false`;
  `becomesKeyOnlyIfNeeded` is set to `true` so the panel can be ordered
  front via `orderFrontRegardless()` without ever becoming the key window.
  The progress indicator is configured with style `.bar`, `controlSize`
  `.small`, and `usesThreadedAnimation` `true`. `init?(coder:)` is marked
  unavailable and calls `fatalError` with the message "init(coder:) is not
  supported" if it is ever invoked, since this type is never loaded from a
  storyboard or XIB. The closure `finish()` passes to
  `DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerAfterFinishing)`
  captures `self` strongly, not weakly, so the panel outlives the caller's
  own reference to it long enough to close itself. UIKit has no equivalent
  of a separate, always-on-top utility window that does not take focus; a
  UIKit port would need a floating overlay `UIView` pinned within the
  current window's view hierarchy (e.g. a small banner anchored to a corner
  via Auto Layout) rather than a second `UIWindow`.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectScanProgressWindow.swift` |

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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
