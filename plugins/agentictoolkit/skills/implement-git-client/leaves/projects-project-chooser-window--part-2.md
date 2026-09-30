<!-- leaf: implement-git-client/projects-project-chooser-window--part-2 · source: git-client-projects-project-chooser-window.md -->

# ProjectChooserWindow — continued (part 2)

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
