---
id: ae0932d6-572f-4173-ba49-df68f4039ba4
title: ProjectChooserWindow
domain: agentictoolkit://cookbook/macos/features/projects/project-chooser-window
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: App-modal Cancel/Open dialog around a chooser-mode ProjectBrowserViewController; resolves to at most one GitRepo from a ProjectsCoordinator.
platforms:
- swift
- macos
tags:
- git
- projects
- window-controller
- modal
- chooser
- macos
- appkit
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectChooserWindow.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectBrowserViewController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/NSApplication+QuietActivation.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectChooserWindow

## Overview

`ProjectChooserWindow` (`ProjectChooserWindow.swift`) is the app-modal
"which project?" dialog: an `NSWindowController` that hosts a private
`ProjectChooserContentViewController`, which in turn hosts a
`ProjectBrowserViewController` in `.chooser` mode behind a Cancel/Open
button pair. It resolves to at most one `GitRepo` drawn from a
`ProjectsCoordinator`'s `repos`, reached through the static entry point
`ProjectChooserWindow.choose(from:onChoose:)` that `ProjectsCoordinator.showProjectChooser()`
calls. Per its own doc comment it is deliberately app-modal rather than a
sheet: "this app has no window guaranteed to be on screen when the question
is asked (it can be asked from the menu bar with nothing open at all), and a
sheet with no parent cannot be dismissed". Both
`ProjectChooserWindow` and its private content view controller are declared
`@MainActor`.

## Behavioral Requirements

- **coordinator-required-no-default**: `init(coordinator:)` and the static
  `choose(from:onChoose:)` MUST both require a `ProjectsCoordinator` argument
  with no default value, and `choose(from:onChoose:)` MUST NOT construct a
  `ProjectChooserWindow` or a coordinator any other way.
- **window-identity-fixed-at-init**: `init(coordinator:)` MUST construct
  exactly one `NSWindow` with `contentRect` 460×480, `styleMask`
  `[.titled, .closable, .resizable]`, `backing: .buffered`, `defer: false`,
  title `"Open Project"`, and `minSize` 360×300, and MUST set that same
  window as both the controller's own `window` and the target of
  `window.delegate`.
- **content-view-controller-fixed-at-init**: `init(coordinator:)` MUST
  construct exactly one `ProjectChooserContentViewController` for the given
  `coordinator` and MUST assign it as `window.contentViewController`.
- **coder-init-unavailable**: `ProjectChooserWindow.init?(coder:)` MUST be
  marked unavailable and MUST call `fatalError` if it is ever invoked, so the
  type MUST NOT be instantiated from a storyboard or nib; the
  same requirement applies to `ProjectChooserContentViewController.init?(coder:)`.
- **main-actor-isolation**: `ProjectChooserWindow` and
  `ProjectChooserContentViewController` MUST both be declared `@MainActor`
  and MUST NOT declare `Sendable` conformance; every stored property
  (`content`, `chosen`, `onFinish`, `browser`, `openButton`) and every method
  of both types is therefore confined to the main actor by that declaration
  alone, not by any lock either type defines itself.
- **browser-constructed-in-chooser-mode**: `ProjectChooserContentViewController.init(coordinator:)`
  MUST construct its `ProjectBrowserViewController` with `mode: .chooser`.
- **onchoose-single-invocation**: `ProjectChooserWindow.choose(from:onChoose:)`
  MUST call `onChoose` exactly once, with the `GitRepo` returned by
  `runModal()`, and only when that result is non-nil; when `runModal()`
  returns `nil` (the user cancelled), `onChoose` MUST NOT be called at all.
- **runmodal-return-value**: `runModal()` MUST return `chosen` after the
  modal session ends; `chosen` is `nil` unless `finish(with:)` was called
  with a non-nil `GitRepo` at some point during that session.
- **content-onfinish-drives-outcome**: The window's eventual outcome MUST be
  determined entirely by invocations of `content.onFinish`, which is wired
  at the end of `init(coordinator:)` to call `finish(with:)` on the window; `finish(with:)` MUST assign its argument to `chosen` and MUST
  call `NSApp.stopModal()`.
- **open-button-forwards-current-selection**: Activating the Open button
  MUST call `onFinish?(browser.selectedRepo)`, forwarding whatever
  `browser.selectedRepo` reports at the moment the button is activated, not
  a value captured earlier.
- **cancel-button-forwards-nil**: Activating the Cancel button MUST call
  `onFinish?(nil)` unconditionally, regardless of the browser's current
  selection.
- **browser-onchoose-forwarded-unchanged**: `browser.onChoose` MUST be wired,
  at construction, to call `onFinish?(repo)` with the exact `GitRepo` the
  browser passes, forwarding it unchanged; the conditions under
  which the browser itself invokes `onChoose` (double-click, Return) are
  `ProjectBrowserViewController`'s own contract, not this file's.
- **open-button-enablement-tracks-selection**: `browser.onSelectionChange`
  MUST be wired, at construction, so that every reported selection change
  sets `openButton.isEnabled` to `true` when the reported `GitRepo?` is
  non-nil and to `false` when it is `nil`.
- **open-button-initial-disabled-then-synced**: `openButton.isEnabled` MUST
  be explicitly set to `false` during `loadView()`, before the browser's
  view is created; accessing `browser.view` for the first time a
  few lines later synchronously loads the browser, which reports
  its own initial selection through `onSelectionChange` — so
  `openButton.isEnabled` MUST end `loadView()` reflecting the browser's
  initial selection, not the `false` value assigned moments before.
- **window-close-ends-session-as-cancel**: `windowWillClose(_:)` MUST call
  `finish(with: nil)` whenever the closing window is the one AppKit
  currently treats as the active modal window (`NSApp.modalWindow === window`),
  which is how dismissal via the title bar close control or ⌘W — both of
  which bypass Cancel and Open — MUST still end the session.
- **window-close-ignored-when-not-active-modal-session**: `windowWillClose(_:)`
  MUST NOT call `finish(with:)` (and therefore MUST NOT call
  `NSApp.stopModal()`) when `NSApp.modalWindow` does not identify this
  window; per the inline comment, this ends "only end a session we are in".
- **runmodal-orders-out-without-closing**: `runModal()` MUST call
  `window.makeKeyAndOrderFront(nil)` before entering the modal loop and
  `window.orderOut(nil)` immediately after `NSApp.runModal(for:)` returns;
  per the inline comment, this `orderOut` call MUST NOT itself produce a
  close notification, so it MUST NOT trigger `windowWillClose(_:)`.
- **runmodal-activation-respects-quiet-presentation**: Before showing the
  window, `runModal()` MUST call `NSApp.activateUnlessQuiet()`,
  which MUST call `NSApplication.activate(ignoringOtherApps: true)` unless
  `QuietWindowPresentation.isEnabled` is `true`, in which case activation
  MUST be skipped entirely (`NSApplication+QuietActivation.swift`).
- **stock-buttons-fixed-key-equivalents**: `loadView()` MUST create Cancel
  and Open as `NSButton` instances with `bezelStyle: .push`, MUST set
  Cancel's `keyEquivalent` to the Escape character (`"\u{1b}"`) and Open's
  `keyEquivalent` to Return (`"\r"`), and MUST route Cancel's action to
  `cancelChoosing(_:)` and Open's action to `openChosen(_:)`.
- **accessibility-identifiers-fixed**: `ProjectChooserWindow` MUST set the
  accessibility identifier `"project-chooser.window"` on its window,
  `"project-chooser.cancel"` on the Cancel button, and
  `"project-chooser.open"` on the Open button.

## Appearance

Not applicable — this is an app-modal window controller and its content
view controller, not a visual component.

## States

Not applicable — this is an app-modal window controller and its content
view controller, not a visual component. Its one runtime state machine —
whether the modal session is still running and what it will resolve to — is
covered under Behavioral Requirements (**runmodal-return-value**,
**content-onfinish-drives-outcome**), not here.

## Accessibility

Not applicable — this is an app-modal window controller and its content
view controller, not a visual component. The fixed accessibility
identifiers it stamps on its own window and buttons are covered under
Behavioral Requirements (**accessibility-identifiers-fixed**); the
accessibility of the hosted project list is `ProjectBrowserViewController`'s
concern, not this file's.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-chooser-window-001 | onchoose-single-invocation, open-button-forwards-current-selection, content-onfinish-drives-outcome, runmodal-return-value | `ProjectChooserWindow.choose(from: coordinator) { repo in captured = repo }` where `coordinator.repos == [a, b]`; select `b`, then activate Open. | `captured == b`; `onChoose` is invoked exactly once. |
| git-client-projects-project-chooser-window-002 | cancel-button-forwards-nil, onchoose-single-invocation, runmodal-return-value | Same setup as 001; activate Cancel instead of Open. | `captured` is never assigned (`onChoose` not invoked); `runModal()` returns `nil`. |
| git-client-projects-project-chooser-window-003 | window-close-ends-session-as-cancel, runmodal-return-value | With the chooser window as the sole open modal session, send it a close (title bar close control or ⌘W) so `windowWillClose(_:)` fires while `NSApp.modalWindow === window`. | `finish(with: nil)` runs; `chosen` is `nil`; `runModal()` returns `nil`; `onChoose` is not invoked. |
| git-client-projects-project-chooser-window-004 | window-close-ignored-when-not-active-modal-session | Open a second, nested `ProjectChooserWindow` on top of the first (so `NSApp.modalWindow` now identifies the second window); trigger `windowWillClose(_:)` on the first window's `NSWindowDelegate` directly. | `finish(with:)` is not called on the first window; its modal session is unaffected; `NSApp.stopModal()` is not called on its behalf. |
| git-client-projects-project-chooser-window-005 | open-button-initial-disabled-then-synced, open-button-enablement-tracks-selection | Construct a `ProjectChooserWindow` from a coordinator with `repos == [a, b]` (non-empty) and force `loadView()` to run. | `openButton.isEnabled == true` once `loadView()` returns, because the browser auto-selects its first project and reports it through `onSelectionChange` during the same call. |
| git-client-projects-project-chooser-window-006 | open-button-initial-disabled-then-synced, open-button-enablement-tracks-selection | Construct a `ProjectChooserWindow` from a coordinator with `repos == []` (empty) and force `loadView()` to run. | `openButton.isEnabled == false` once `loadView()` returns. |
| git-client-projects-project-chooser-window-007 | stock-buttons-fixed-key-equivalents | Inspect the Cancel and Open buttons after `loadView()`. | `cancel.keyEquivalent == "\u{1b}"`; `openButton.keyEquivalent == "\r"`; `cancel.bezelStyle == .push` and `openButton.bezelStyle == .push`. |
| git-client-projects-project-chooser-window-008 | window-identity-fixed-at-init | Inspect `window` immediately after `init(coordinator:)` returns. | `window.title == "Open Project"`; `window.frame.size == NSSize(width: 460, height: 480)`; `window.minSize == NSSize(width: 360, height: 300)`; `window.styleMask == [.titled, .closable, .resizable]`. |
| git-client-projects-project-chooser-window-009 | runmodal-activation-respects-quiet-presentation | Call `runModal()` with `QuietWindowPresentation.isEnabled == false`. | `NSApplication.activate(ignoringOtherApps: true)` is invoked before the window is made key. |
| git-client-projects-project-chooser-window-010 | runmodal-activation-respects-quiet-presentation | Call `runModal()` with `QuietWindowPresentation.isEnabled == true`. | `NSApplication.activate(ignoringOtherApps:)` is not invoked; the window is still made key and ordered front. |
| git-client-projects-project-chooser-window-011 | accessibility-identifiers-fixed | Inspect `window`, `cancel`, and `openButton` after `loadView()`. | Their accessibility identifiers read `"project-chooser.window"`, `"project-chooser.cancel"`, and `"project-chooser.open"` respectively. |

## Edge Cases

- **Null and empty input**: A `ProjectsCoordinator` whose `repos` is empty
  at construction leaves the browser's selection `nil`, so
  `openButton.isEnabled` MUST stay `false` through `loadView()` (see
  **open-button-enablement-tracks-selection**); Cancel MUST remain fully
  functional regardless (see **cancel-button-forwards-nil**). `runModal()`'s
  `guard let window else { return nil }` MUST return `nil` if
  `window` were ever `nil`, but in practice `init(coordinator:)` always
  calls `super.init(window:)` with a concrete, non-optional window and no other initializer path exists (`init?(coder:)` is
  unavailable), so this guard is a defensive check on a case the file's own
  contract never actually produces.
- **Boundary values**: `window.minSize` fixes the one numeric boundary this
  file defines: AppKit MUST prevent the window from being resized below
  360×300 even though it opens at 460×480 (see
  **window-identity-fixed-at-init**). The number of projects in
  `coordinator.repos` — zero, one, or many — imposes no boundary of its own
  on this file; scale limits on the project list belong to
  `ProjectBrowserViewController`, not to this window.
- **Concurrent access**: Every mutation of `chosen` and every access to
  `content`/`browser`/`openButton` is confined to the main actor by
  `@MainActor` (see **main-actor-isolation**), so no interleaving on this
  file's own state can be observed torn. Neither `ProjectChooserWindow.choose(from:onChoose:)`
  nor `ProjectsCoordinator.showProjectChooser()` guards against being
  invoked a second time before the first session ends — unlike
  `ProjectsCoordinator.scan()`'s `guard !isScanning` — so two rapid
  invocations (for example, the "Open Project…" command fired twice before
  the first window paints) construct two independent `ProjectChooserWindow`
  instances and stack two nested `NSApp.runModal` sessions; AppKit resolves
  this deterministically (last-opened is topmost and must be dismissed
  before the previous session resumes — see
  **window-close-ignored-when-not-active-modal-session**), but the two
  windows and their buttons carry identical, non-instance-scoped
  accessibility identifiers (see **accessibility-identifiers-fixed**), so
  automation driven by those identifiers alone cannot distinguish the two
  simultaneously open chooser windows.
- **Error states**: `ProjectChooserWindow.swift` makes no call that can
  throw and defines no error type of its own; it reads `coordinator.repos`
  only indirectly, through the `ProjectBrowserViewController` it hosts, and
  that property is a non-throwing, already-materialized array — any failure
  in producing it (a scan error, a database read error) happens upstream in
  `ProjectsCoordinator` and `ProjectDatabase`, entirely out of this file's
  view.
- **Offline or disconnected state**: Not applicable — this file makes no
  network request. It only reads local, in-memory state
  (`ProjectsCoordinator.repos`) through the browser it hosts and has no
  notion of connectivity of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `coordinator` (parameter to `init` and to `choose(from:onChoose:)`) | `ProjectsCoordinator` | none — required | Supplies the `repos` the hosted `ProjectBrowserViewController` lists; never constructed internally. |
| `onChoose` (parameter to `choose(from:onChoose:)`) | `(GitRepo) -> Void` | none — required | Called exactly once, with the chosen `GitRepo`, when `runModal()` returns non-nil; never called otherwise. |

`ProjectChooserWindow.swift` reads no environment variable and no settings
key directly. `QuietWindowPresentation.isEnabled`, consulted only through
`NSApp.activateUnlessQuiet()`, is `NSApplication+QuietActivation.swift`'s
own concern, reached by this file only as an opaque call
(see **runmodal-activation-respects-quiet-presentation**).

## Deep Linking

Not applicable: `ProjectChooserWindow.swift` defines no URL scheme, route,
or navigation destination.

## Localization

`ProjectChooserWindow.swift` produces its user-facing strings as Swift
string literals with no localization key or lookup mechanism:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | `Open Project` | Window title, set in `init(coordinator:)`. |
| (none — literal) | `Open` | Open button title. |
| (none — literal) | `Cancel` | Cancel button title. |

## Accessibility Options

Not applicable: `ProjectChooserWindow.swift` renders no animation or motion
effect and encodes no state through color alone, so it has nothing for
Reduce Motion, Increase Contrast, or Differentiate Without Color to act on.

## Feature Flags

Not applicable: `ProjectChooserWindow.swift` contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: `ProjectChooserWindow.swift` makes no analytics or
event-tracking call.

## Privacy

Not applicable: the only data this file touches is the in-memory `GitRepo`
values (a local path and an optional remote URL) a `ProjectsCoordinator`
already exposes elsewhere in the app's menus and windows; it reads, stores,
or transmits no credential, token, or personal data of its own.

## Logging

`ProjectChooserWindow.swift` makes no logging call of its own — no
`Logger`, `os.Logger`, or `print` appears anywhere in the file.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This file emits no log messages. |

## Platform Notes

- **SwiftUI**: The source is entirely AppKit
  (`packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectChooserWindow.swift`):
  `NSWindowController`, `NSWindowDelegate`, `NSWindow`, and a private
  `NSViewController`. A SwiftUI port has no built-in app-modal API on
  macOS — `.sheet` requires a presenting window this app cannot guarantee
  exists (per the source's own doc comment) — so a SwiftUI rewrite would
  still need an `NSWindow`/`NSApp.runModal` bridge (or an `NSHostingController`
  wrapped exactly as this file wraps its AppKit content view controller)
  rather than a pure `WindowGroup`/`Scene`.
- **Compose**: There is no macOS-style "app-modal window with no guaranteed
  parent" concept in Compose; the closest model is a second top-level
  `Window` (or `DialogWindow`) shown independently of any owner, with the
  "wait for a choice" contract expressed as a `CompletableDeferred<GitRepo?>`
  that the caller awaits while the window is visible, completed by the
  Open/Cancel composables and by the window's own close handler — mirroring
  **content-onfinish-drives-outcome** and
  **window-close-ends-session-as-cancel**.
- **React/Web**: A browser has no native modal window or app-modal concept;
  port the chooser as a modal dialog component (a `<dialog>` element or a
  focus-trapping overlay) with Escape and Enter key handlers standing in for
  the Cancel/Open key equivalents, and express `choose(from:onChoose:)`'s
  callback contract as a `Promise<GitRepo | null>` the caller awaits instead.
- **AppKit / UIKit**: The source already is AppKit. iOS has no
  app-modal-window concept at all (an iOS app has one window); the closest
  UIKit port is a modally presented `UIViewController` (`.overFullScreen` or
  a form sheet) with a Cancel bar button and a Done/Open bar button whose
  `isEnabled` mirrors **open-button-enablement-tracks-selection** — there is
  no Escape-key or Return-key hardware default to carry over.
- **WinUI 3**: Port `ProjectChooserWindow` as a secondary
  `Microsoft.UI.Xaml.Window`, not a `ContentDialog` — a `ContentDialog`
  requires an already-visible owner `XamlRoot`, the same "no guaranteed
  parent" problem the source's doc comment raises about `NSPanel` sheets.
  Because WinUI 3 has no `NSApp.runModal` equivalent, express the "wait for
  a choice" contract with a `TaskCompletionSource<GitRepo?>` that button
  click handlers and the window's `Closed` event complete exactly once
  (`TrySetResult`, mirroring **onchoose-single-invocation** and
  **window-close-ends-session-as-cancel**), and have a `ChooseAsync` method
  `await` that source the way `choose(from:onChoose:)` awaits `runModal()`.
  Set the window's initial `AppWindow.Resize` to 460×480 and its minimum
  size to 360×300 (handled in `AppWindow.Changed`/`WindowSizeChanged`, since
  `AppWindow` has no direct `MinSize` property), and title it `"Open
  Project"`. Build the button pair as two `Button` controls in a horizontal
  `StackPanel`; set `IsDefault="True"` on the Open button to mirror the
  Return key-equivalent's default-button tint, and give Cancel a
  `KeyboardAccelerator` with `Key="Escape"` to mirror its Escape
  key-equivalent. Bind the Open button's `IsEnabled` to the hosted list's
  selection-changed event exactly as **open-button-enablement-tracks-selection**
  requires. There is no `NSApp.modalWindow`-identity concept to check in
  `Closed`, so mirror
  **window-close-ignored-when-not-active-modal-session**'s one-shot
  guarantee with `TaskCompletionSource.TrySetResult(null)`, which is a no-op
  once a button click has already completed the source. Set
  `AutomationProperties.AutomationId` on the window, the Cancel button, and
  the Open button to mirror **accessibility-identifiers-fixed**.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectChooserWindow.swift` |

## Design Decisions

**Decision**: The chooser is presented as an app-modal `NSWindow`
(`NSApp.runModal(for:)`) rather than as a sheet.
**Rationale**: Per the source's own doc comment, "this app has no window
guaranteed to be on screen when the question is asked (it can be asked from
the menu bar with nothing open at all), and a sheet with no parent cannot
be dismissed" (`ProjectChooserWindow.swift`).
**Approved**: pending

**Decision**: `windowWillClose(_:)` only calls `finish(with: nil)` when
`NSApp.modalWindow === window`, rather than unconditionally on every close
notification.
**Rationale**: The inline comment states the reason directly — the check
exists to "only end a session we are in," so a close notification for a
window that is not the currently active modal session does not tear down a
different, still-running modal session by calling `NSApp.stopModal()` on
its behalf (`ProjectChooserWindow.swift`).
**Approved**: pending

**Decision**: The title bar close control and ⌘W are routed through
`windowWillClose(_:)` to the same `finish(with:)` path as Cancel, rather
than being left to AppKit's default close behavior.
**Rationale**: The inline comment explains what breaks otherwise: "the
title bar's close button and ⌘W bypass Cancel and Open, so the session has
to be ended from the close notification too," because without it "the
modal session outlives its window" and AppKit keeps disabling Quit, About,
Settings, and every status-item command for the rest of the run
(`ProjectChooserWindow.swift`).
**Approved**: pending

**Decision**: Cancel and Open are built as stock `NSButton`s with
`bezelStyle: .push`, rather than a custom-drawn control pair.
**Rationale**: The inline comment states this is deliberate: "this is the
Open dialog of a Mac app: the pair at the bottom right is a shape people
have known for thirty years, and a hand-drawn substitute is a worse version
of it" (`ProjectChooserWindow.swift`), consistent with the
`native-controls-preference` compliance check below.
**Approved**: pending

**Decision**: The browser and the Cancel/Open pair are split into a
separate `ProjectChooserContentViewController` rather than being assembled
directly inside `ProjectChooserWindow`.
**Rationale**: The inline comment gives the reason: splitting it out gives
"the browser a real parent view controller" so it "gets its appearance
callbacks," which is where the browser's own `viewDidAppear` takes first
responder for its filter field (`ProjectChooserWindow.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |

Notes: separation-of-concerns passes because `ProjectChooserWindow` and its
content view controller own only the modal session, the button pair, and
the choose/cancel wiring between them — the project list itself, its
filtering, and its selection model belong entirely to
`ProjectBrowserViewController`, and the registry data belongs to
`ProjectsCoordinator`; neither is duplicated here. unit-test-coverage fails
because no test file exercises `ProjectChooserWindow` or
`ProjectChooserContentViewController` at all — `packages/apple/AgenticToolkit/Tests`
has no `ProjectChooserWindowTests.swift` or equivalent, so none of this
recipe's requirements (the onFinish wiring, the modal-identity guard on
close, the button enablement synchronization) has automated coverage.
native-controls-preference passes for the reason the source's own doc
comment gives: Cancel and Open are stock `NSButton`s, deliberately, rather
than a hand-drawn pair. platform-design-language passes because the window
uses a standard titled/closable/resizable `NSWindow`, a centered starting
position, and the Return-as-default-button / Escape-as-Cancel convention
every AppKit dialog follows. fault-tolerance passes because every guard in
this file (`runModal()`'s `guard let window`, `windowWillClose(_:)`'s
`guard NSApp.modalWindow === window`, the disabled-until-selected Open
button) fails safe — into a no-op or a `nil` result — rather than crashing
or corrupting `chosen`. main-thread-freedom passes because this file
performs no computation, file I/O, or network call of its own alongside
its UI work; the only blocking call it makes, `NSApp.runModal(for:)`, is the
platform's own intentional modal wait, not work this file could move off
the main thread.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
