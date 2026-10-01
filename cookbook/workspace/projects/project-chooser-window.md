---
id: ae0932d6-572f-4173-ba49-df68f4039ba4
title: Project Chooser Window
domain: agentictoolkit://cookbook/workspace/projects/project-chooser-window
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An app-modal Cancel/Open dialog that hosts a project browser in chooser mode and resolves to at most one repository record from a coordinating component's list.
platforms:
- swift
- macos
tags:
- git
- projects
- modal
- chooser
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

# Project Chooser Window

## Overview

The project chooser window is the app-modal "which project?" dialog: it
hosts a private content view that in turn hosts a project browser in
chooser mode behind a Cancel/Open button pair. It resolves to at most one
repository record drawn from a coordinating component's list of
repositories, reached through a single choose-and-callback entry point that
a menu command calls. Per its own design rationale it is deliberately
app-modal rather than a sheet: "this app has no window guaranteed to be on
screen when the question is asked (it can be asked from the menu bar with
nothing open at all), and a sheet with no parent cannot be dismissed".

## Behavioral Requirements

- **coordinator-required-no-default**: Constructing the chooser window and
  its choose-and-callback entry point MUST both require a
  coordinating-component argument with no default value, and the entry
  point MUST NOT construct a chooser window or a coordinating component any
  other way.
- **window-identity-fixed-at-init**: Constructing the chooser window MUST
  create exactly one window sized 460×480, closable and resizable with a
  title bar, titled "Open Project", with a minimum size of 360×300, and
  MUST set that window as both the controller's own window and as the
  target of its own close notifications.
- **content-view-controller-fixed-at-init**: Constructing the chooser
  window MUST construct exactly one content view for the given
  coordinating component and MUST assign it as the window's content.
- **browser-constructed-in-chooser-mode**: Constructing the content view
  MUST construct its hosted project browser in chooser mode.
- **onchoose-single-invocation**: The choose-and-callback entry point MUST
  call its callback exactly once, with the repository record the modal
  session returns, and only when that result is present; when the modal
  session ends with no result (the user cancelled), the callback MUST NOT
  be called at all.
- **runmodal-return-value**: Running the modal session MUST return the
  chosen repository record after the session ends; the chosen value is
  absent unless the finish step was invoked with a present repository
  record at some point during that session.
- **content-onfinish-drives-outcome**: The window's eventual outcome MUST
  be determined entirely by invocations of the content view's finish
  callback, which is wired at the end of construction to call the window's
  own finish step; that finish step MUST assign its argument to the chosen
  value and MUST end the modal session.
- **open-button-forwards-current-selection**: Activating the Open button
  MUST call the finish callback with the browser's currently selected
  repository, forwarding whatever the browser reports at the moment the
  button is activated, not a value captured earlier.
- **cancel-button-forwards-nil**: Activating the Cancel button MUST call
  the finish callback with no repository, unconditionally, regardless of
  the browser's current selection.
- **browser-onchoose-forwarded-unchanged**: The browser's own choose
  callback MUST be wired, at construction, to call the finish callback with
  the exact repository record the browser passes, forwarding it unchanged;
  the conditions under which the browser itself invokes its choose callback
  (double-click, Return) are the browser's own contract, not this dialog's.
- **open-button-enablement-tracks-selection**: The browser's
  selection-change notification MUST be wired, at construction, so that
  every reported selection change enables the Open button when the
  reported repository is present and disables it when absent.
- **open-button-initial-disabled-then-synced**: The Open button MUST be
  explicitly disabled while the view loads, before the browser's view is
  created; creating the browser's view for the first time a few moments
  later synchronously loads the browser, which reports its own initial
  selection through the selection-change notification — so the Open button
  MUST end view loading reflecting the browser's initial selection, not the
  disabled value assigned moments before.
- **window-close-ends-session-as-cancel**: The window's close notification
  MUST call the finish step with no repository whenever the closing window
  is the one currently treated as the active modal window, which is how
  dismissal via the title bar close control or the primary close shortcut —
  both of which bypass Cancel and Open — MUST still end the session.
- **window-close-ignored-when-not-active-modal-session**: The window's
  close notification MUST NOT call the finish step (and therefore MUST NOT
  end the modal session) when the window is not identified as the active
  modal window; per the design rationale, this ends "only end a session we
  are in".
- **runmodal-orders-out-without-closing**: Running the modal session MUST
  bring the window to the front and make it key before entering the modal
  loop, and MUST order the window out immediately after the modal loop
  returns; per the design rationale, this ordering-out step MUST NOT itself
  produce a close notification, so it MUST NOT trigger the window-close
  handling.
- **runmodal-activation-respects-quiet-presentation**: Before showing the
  window, running the modal session MUST activate the application unless
  quiet presentation is enabled, in which case activation MUST be skipped
  entirely.
- **stock-buttons-fixed-key-equivalents**: Creating the view MUST create
  Cancel and Open as native platform buttons with a standard push-button
  appearance, MUST set Cancel's key equivalent to Escape and Open's key
  equivalent to Return, and MUST route Cancel's action to the cancel step
  and Open's action to the open step.
- **accessibility-identifiers-fixed**: The chooser window MUST set the
  accessibility identifier "project-chooser.window" on its window,
  "project-chooser.cancel" on the Cancel button, and "project-chooser.open"
  on the Open button.

## Appearance

Not applicable — this is an app-modal window and its content view, not a
visual component.

## States

Not applicable — this is an app-modal window and its content view, not a
visual component. Its one runtime state machine — whether the modal
session is still running and what it will resolve to — is covered under
Behavioral Requirements (**runmodal-return-value**,
**content-onfinish-drives-outcome**), not here.

## Accessibility

Not applicable — this is an app-modal window and its content view, not a
visual component. The fixed accessibility identifiers it stamps on its own
window and buttons are covered under Behavioral Requirements
(**accessibility-identifiers-fixed**); the accessibility of the hosted
project list is the project browser's concern, not this file's.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-chooser-window-001 | onchoose-single-invocation, open-button-forwards-current-selection, content-onfinish-drives-outcome, runmodal-return-value | Show the chooser for a coordinating component whose repository list is `[a, b]`, capturing whatever the callback receives; select `b`, then activate Open. | The captured value is `b`; the callback is invoked exactly once. |
| git-client-projects-project-chooser-window-002 | cancel-button-forwards-nil, onchoose-single-invocation, runmodal-return-value | Same setup as 001; activate Cancel instead of Open. | No value is ever captured (the callback is not invoked); the modal session resolves to no repository. |
| git-client-projects-project-chooser-window-003 | window-close-ends-session-as-cancel, runmodal-return-value | With the chooser window as the sole open modal session, close it (via the title bar close control or the primary close shortcut) so the window-close handling runs while it is the active modal window. | The finish step runs with no repository; the chosen value is absent; the modal session resolves to no repository; the callback is not invoked. |
| git-client-projects-project-chooser-window-004 | window-close-ignored-when-not-active-modal-session | Open a second, nested chooser window on top of the first (so the active modal window is now the second one); trigger the first window's close handling directly. | The finish step is not called on the first window; its modal session is unaffected; the session is not ended on its behalf. |
| git-client-projects-project-chooser-window-005 | open-button-initial-disabled-then-synced, open-button-enablement-tracks-selection | Construct a chooser window from a coordinating component with a non-empty repository list (`[a, b]`) and force the view to load. | The Open button is enabled once the view finishes loading, because the browser auto-selects its first project and reports it through the selection-change notification during the same load. |
| git-client-projects-project-chooser-window-006 | open-button-initial-disabled-then-synced, open-button-enablement-tracks-selection | Construct a chooser window from a coordinating component with an empty repository list and force the view to load. | The Open button is disabled once the view finishes loading. |
| git-client-projects-project-chooser-window-007 | stock-buttons-fixed-key-equivalents | Inspect the Cancel and Open buttons after the view loads. | Cancel's key equivalent is Escape; Open's key equivalent is Return; both have a standard push-button appearance. |
| git-client-projects-project-chooser-window-008 | window-identity-fixed-at-init | Inspect the window immediately after construction. | The window's title is "Open Project"; its size is 460×480; its minimum size is 360×300; it is closable and resizable with a title bar. |
| git-client-projects-project-chooser-window-009 | runmodal-activation-respects-quiet-presentation | Run the modal session with quiet presentation disabled. | The application is activated before the window is made key. |
| git-client-projects-project-chooser-window-010 | runmodal-activation-respects-quiet-presentation | Run the modal session with quiet presentation enabled. | The application is not activated; the window is still made key and brought to the front. |
| git-client-projects-project-chooser-window-011 | accessibility-identifiers-fixed | Inspect the window, the Cancel button, and the Open button after the view loads. | Their accessibility identifiers read "project-chooser.window", "project-chooser.cancel", and "project-chooser.open" respectively. |

## Edge Cases

- **Null and empty input**: A coordinating component whose repository list
  is empty at construction leaves the browser's selection absent, so the
  Open button MUST stay disabled through view loading (see
  **open-button-enablement-tracks-selection**); Cancel MUST remain fully
  functional regardless (see **cancel-button-forwards-nil**). Running the
  modal session MUST resolve to no repository if the window were ever
  absent, but in practice construction always produces a concrete window
  and no other construction path exists, so this is a defensive check on a
  case the dialog's own contract never actually produces.
- **Boundary values**: The window's minimum size fixes the one numeric
  boundary this file defines: the window MUST NOT be resized below 360×300
  even though it opens at 460×480 (see **window-identity-fixed-at-init**).
  The number of projects in the coordinating component's repository list —
  zero, one, or many — imposes no boundary of its own on this file; scale
  limits on the project list belong to the project browser, not to this
  window.
- **Concurrent access**: Every mutation of the chosen value and every
  access to the content view, browser, or Open button is confined to a
  single execution context (see Platform Notes), so no interleaving on this
  file's own state can be observed torn. Neither the choose-and-callback
  entry point nor the menu command that calls it guards against being
  invoked a second time before the first session ends — unlike the project
  scan operation's own busy-guard — so two rapid invocations (for example,
  an "Open Project…" command fired twice before the first window paints)
  construct two independent chooser windows and stack two nested modal
  sessions; the platform resolves this deterministically (last-opened is
  topmost and must be dismissed before the previous session resumes — see
  **window-close-ignored-when-not-active-modal-session**), but the two
  windows and their buttons carry identical, non-instance-scoped
  accessibility identifiers (see **accessibility-identifiers-fixed**), so
  automation driven by those identifiers alone cannot distinguish the two
  simultaneously open chooser windows.
- **Error states**: This dialog makes no call that can throw and defines
  no error type of its own; it reads the coordinating component's
  repository list only indirectly, through the project browser it hosts,
  and that list is a non-throwing, already-materialized collection — any
  failure in producing it (a scan error, a database read error) happens
  upstream, entirely out of this file's view.
- **Offline or disconnected state**: Not applicable — this file makes no
  network request. It only reads local, in-memory state (the coordinating
  component's repository list) through the browser it hosts and has no
  notion of connectivity of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `coordinator` (construction parameter, also passed to the choose-and-callback entry point) | coordinating-component reference | none — required | Supplies the repository list the hosted project browser lists; never constructed internally. |
| `onChoose` (parameter to the choose-and-callback entry point) | callback taking a repository record | none — required | Called exactly once, with the chosen repository record, when the modal session resolves to a value; never called otherwise. |

This dialog reads no environment variable and no settings key directly.
Quiet presentation, consulted only when activating the application before
showing the window, is a separate concern reached by this file only as an
opaque check (see **runmodal-activation-respects-quiet-presentation**).

## Deep Linking

Not applicable: this dialog defines no URL scheme, route, or navigation
destination.

## Localization

This dialog produces its user-facing strings as literal text with no
localization key or lookup mechanism:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | `Open Project` | Window title, set at construction. |
| (none — literal) | `Open` | Open button title. |
| (none — literal) | `Cancel` | Cancel button title. |

## Accessibility Options

Not applicable: this dialog renders no animation or motion effect and
encodes no state through color alone, so it has nothing for Reduce Motion,
Increase Contrast, or Differentiate Without Color to act on.

## Feature Flags

Not applicable: this dialog contains no feature-flag or build-configuration
check.

## Analytics

Not applicable: this dialog makes no analytics or event-tracking call.

## Privacy

Not applicable: the only data this file touches is the in-memory
repository records (a local path and an optional remote URL) a coordinating
component already exposes elsewhere in the app's menus and windows; it
reads, stores, or transmits no credential, token, or personal data of its
own.

## Logging

This dialog makes no logging call of its own.

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
  rather than a pure `WindowGroup`/`Scene`. The window is constructed with a
  fixed style mask (`[.titled, .closable, .resizable]`), buffered backing,
  and no deferred creation; `init?(coder:)` is unavailable and calls
  `fatalError` if invoked, for both the window controller and its private
  content view controller, so neither can be instantiated from a storyboard
  or nib. Both types are declared `@MainActor` and declare no `Sendable`
  conformance, so every stored property (`content`, `chosen`, `onFinish`,
  `browser`, `openButton`) and every method of both is confined to the main
  actor by that declaration alone, not by any lock either type defines
  itself.
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
  no Escape-key or Return-key hardware default to carry over. Cancel and
  Open are built as stock `NSButton` instances with `bezelStyle: .push`.
  Quiet presentation is checked through `NSApp.activateUnlessQuiet()`
  (`CoreMacOS/DebugAutomation/NSApplication+QuietActivation.swift`), which
  calls `NSApplication.activate(ignoringOtherApps: true)` unless
  `QuietWindowPresentation.isEnabled` is `true`.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
