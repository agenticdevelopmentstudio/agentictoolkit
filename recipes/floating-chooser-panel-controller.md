---
id: ba1406b3-bcf8-4580-9d65-daed2311cccf
title: FloatingChooserPanelController
domain: agentictoolkit://recipes/floating-chooser-panel-controller
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit base class for the app''s floating, titleless chooser panels: shared
  positioning, activation, focus-loss dismissal, and reentrant-close guarding.'
platforms:
- swift
- macos
tags:
- panel-controller
- floating-panel
- window-controller
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/extension-quick-pick-view-controller
- agentictoolkit://recipes/extension-input-box-view-controller
references: []
approved-by: ''
approved-date: ''
---

# FloatingChooserPanelController

## Overview

`FloatingChooserPanelController` (AppKit, macOS) is the shared `NSWindowController`
base class for every transient chooser panel in the app — the command palette
and the quick-pick / input-box panels an extension can ask for. It owns
everything those choosers have in common: a floating, titleless `NSPanel`
hosting the subclass's content view controller as a genuine child in the
view-controller hierarchy, pointer-relative positioning near the top of the
screen, activation-before-show, dismissal when the panel loses key status, and
a reentrancy guard around the single dismissal path. A subclass decides
exactly three things: the panel's size (via the `contentRect` passed to
`init`), whether losing focus dismisses the panel (`dismissesOnFocusLoss`),
and what happens on the way in and out (`takeInitialFocus()` and
`panelWillClose()`). This recipe documents only what this base class itself
does; a subclass's own sizing, content, and focus/dismissal behavior belongs
to that subclass's own recipe.

## Behavioral Requirements

- **hosts-content-as-child-controller**: The panel MUST add the hosted
  content view controller as a child of an intermediate container view
  controller, and that container — not the content controller itself — MUST
  be the window's `contentViewController`.
- **pins-content-to-container-edges**: The hosted content's view MUST be
  constrained to the top, leading, trailing, and bottom anchors of the
  container's view, with zero additional padding, using Auto Layout
  (`translatesAutoresizingMaskIntoConstraints = false`).
- **uses-titled-panel-style-mask**: The panel's window MUST be an `NSPanel`
  created with style mask `[.titled, .closable, .fullSizeContentView]`.
- **hides-title-text**: The window's title MUST be invisible: `titleVisibility`
  MUST be `.hidden` and `titlebarAppearsTransparent` MUST be `true`.
- **hides-standard-window-buttons**: The window's close, miniaturize, and
  zoom title-bar buttons MUST be hidden, even though the style mask includes
  `.closable`.
- **floats-above-normal-windows**: The window's level MUST be `.floating`.
- **joins-all-spaces-and-full-screen-auxiliary**: The window's
  `collectionBehavior` MUST include `.canJoinAllSpaces` and
  `.fullScreenAuxiliary`.
- **is-not-user-resizable**: The window MUST NOT be resizable by the user;
  its style mask MUST NOT include `.resizable`.
- **survives-close-without-releasing**: The window's `isReleasedWhenClosed`
  MUST be `false`, so the same window instance MUST remain reusable across
  repeated close/show cycles.
- **rejects-coder-initialization**: `init?(coder:)` MUST be unavailable and
  MUST call `fatalError()` if somehow invoked.
- **guards-show-against-missing-window**: `show()` MUST return immediately,
  performing no positioning, activation, or focus work, if `window` is `nil`.
- **positions-on-pointer-screen**: Showing the panel MUST position it on the
  screen whose frame contains the current mouse location
  (`NSEvent.mouseLocation`).
- **falls-back-to-main-screen**: If no screen contains the mouse location,
  positioning MUST fall back to `NSScreen.main`.
- **falls-back-to-centering-without-visible-frame**: If the resolved screen
  has no `visibleFrame` available — including when no screen contains the
  mouse location and `NSScreen.main` is also `nil` — the panel MUST be
  positioned with `NSWindow.center()` instead of the pointer-relative
  calculation.
- **centers-horizontally-on-screen**: The panel's horizontal position MUST
  center it within the target screen's visible frame
  (`origin.x = visibleFrame.midX - width / 2`).
- **offsets-top-edge-by-fixed-fraction**: The panel's top edge MUST sit 20%
  of the visible frame's height below the top of the visible frame
  (`topInsetFraction = 0.2`).
- **activates-app-before-showing**: `show()` MUST activate the application
  (`NSApp.activateUnlessQuiet()`) before ordering the panel's window to the
  front.
- **respects-quiet-activation**: Activation during `show()` MUST go through
  `activateUnlessQuiet()`, which MUST skip `activate(ignoringOtherApps:)`
  when `QuietWindowPresentation.isEnabled` is `true`.
- **shows-and-takes-key-before-initial-focus**: `show()` MUST call
  `showWindow(nil)` and then `window.makeKeyAndOrderFront(nil)` before
  calling `takeInitialFocus()`, so the window MUST already be key when the
  initial-focus hook runs.
- **reshows-idempotently**: Calling `show()` again on a panel that is
  already open MUST reposition and refocus the same window rather than
  creating a second window.
- **defaults-initial-focus-hook-to-no-op**: The base class's
  `takeInitialFocus()` MUST have an empty body; subclasses that need initial
  focus behavior MUST override it.
- **dismisses-on-focus-loss-by-default**: The base class's
  `dismissesOnFocusLoss` MUST default to `true`.
- **closes-on-focus-loss-when-enabled**: When `dismissesOnFocusLoss` is
  `true`, the window is visible, and no dismissal is already in progress,
  `windowDidResignKey` MUST call `close()`.
- **ignores-focus-loss-when-disabled**: When `dismissesOnFocusLoss` is
  `false`, `windowDidResignKey` MUST NOT call `close()`.
- **ignores-focus-loss-while-already-dismissing**: While a dismissal is
  already in progress (`isDismissing == true`), `windowDidResignKey` MUST NOT
  call `close()` again.
- **ignores-focus-loss-when-not-visible**: If the window is not visible
  (`window?.isVisible == false`), `windowDidResignKey` MUST NOT call
  `close()`.
- **guards-close-against-reentrancy**: `close()` MUST return immediately
  without calling `super.close()` if a dismissal is already in progress
  (`isDismissing == true`).
- **resets-dismissing-flag-after-close**: `close()` MUST clear `isDismissing`
  back to `false` after its own call to `super.close()` returns. Only the
  outer call — the one that found `isDismissing == false` and set it to
  `true` — reaches this reset; a nested, reentrant call returns at the
  reentrancy guard before it, so it never touches the flag. The next
  dismissal of a re-shown panel MUST therefore be treated as a fresh entry.
- **calls-panel-will-close-on-window-close**: `windowWillClose` MUST call
  `panelWillClose()` exactly once per dismissal.
- **defaults-panel-will-close-hook-to-no-op**: The base class's
  `panelWillClose()` MUST have an empty body; subclasses that need teardown
  behavior on close MUST override it.
- **decides-size-via-subclass-content-rect**: The window's initial size MUST
  come entirely from the `contentRect` argument a subclass passes to
  `init(content:contentRect:)`; the base class MUST NOT compute or default a
  size of its own.

## Appearance

- **Corner radius**: Not applicable — the controller draws no custom-cornered
  chrome; whatever corner rounding appears is the system's own standard
  `NSPanel` rendering.
- **Padding**: The hosted content view's edge constraints to the container
  view carry no additional constant — 0pt padding on all four sides.
- **Font**: Not applicable — the controller renders no text of its own; any
  text belongs to the hosted `contentController`, a separate ingredient.
- **Background**: Not specified in source — no background color is set on
  the window or the container view in this file; the panel uses the system
  default `NSPanel` background.
- **Foreground/Text**: Not applicable — see Font.
- **Border**: Not applicable — no custom border is configured in this file;
  standard system panel border applies.
- **Shadow**: Not applicable — no custom shadow is configured in this file;
  the standard floating-panel shadow applies.
- **Min/Max size**: Not applicable — the window is not user-resizable (style
  mask omits `.resizable`), so no min/max size constraint is needed or set;
  the window's fixed size is the `contentRect` a subclass passes to `init`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Newly initialized, not yet shown (window not visible); `isDismissing == false`. |
| Pressed | Not applicable — the controller renders no pressable surface of its own; per-press visuals belong to whatever `contentController` a subclass hosts. |
| Disabled | Not applicable — no enabled/disabled state exists for this window controller in source. |
| Focused | Window is key (`makeKeyAndOrderFront` ran in `show()`); first responder is whatever `takeInitialFocus()` set, per subclass. |
| Loading | Not applicable — `show()` is synchronous; no loading/spinner state exists in source. |
| Dismissing | `isDismissing == true`, from entry into `close()` until its call to `super.close()` returns; a nested `close()` call or a `windowDidResignKey` notification arriving during this interval MUST have no effect. |
| Focus lost, `dismissesOnFocusLoss == true` | Panel closes (`windowDidResignKey` calls `close()`). |
| Focus lost, `dismissesOnFocusLoss == false` | Panel remains open and visible; only key-window status is lost. |

## Accessibility

- Role/traits: Not applicable at this layer — the controller sets no
  accessibility role, trait, or identifier of its own; the standard
  `NSPanel` role applies, and interactive elements (list rows, search
  fields, buttons) belong to whichever `contentController` a subclass hosts,
  each with its own recipe.
- Keyboard/focus: The panel MUST become the key window before
  `takeInitialFocus()` is called (`show()` calls `showWindow(nil)`, then
  `window.makeKeyAndOrderFront(nil)`, then `takeInitialFocus()`), so a
  subclass's initial-focus hook can always assume the window is already key.
  No explicit focus-restoration code exists in this file beyond `close()`
  itself; losing key status when the panel closes is standard AppKit
  behavior.
- Label requirements: Not applicable — no accessibility label or identifier
  is assigned to the window or the container view in this file.
- Announce state changes: Not applicable — the panel has no loading or
  disabled state to announce.
- Minimum tap target: Not applicable — this controller renders no
  interactive control of its own; the window's standard title-bar buttons
  are explicitly hidden, and the hosted content's controls are covered by
  that content controller's own recipe.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| floating-chooser-panel-controller-001 | hosts-content-as-child-controller | Construct the controller with a content VC and any `contentRect` | `window.contentViewController` is the container controller; the content VC appears in the container's `children`. |
| floating-chooser-panel-controller-002 | pins-content-to-container-edges | Inspect the container's view constraints after `init` | The content view's top, leading, trailing, and bottom anchors are each pinned to the container view's matching anchor with constant 0. |
| floating-chooser-panel-controller-003 | uses-titled-panel-style-mask | Inspect `window.styleMask` after `init` | `styleMask == [.titled, .closable, .fullSizeContentView]`. |
| floating-chooser-panel-controller-004 | hides-title-text | Inspect `window.titleVisibility` and `titlebarAppearsTransparent` | `titleVisibility == .hidden`; `titlebarAppearsTransparent == true`. |
| floating-chooser-panel-controller-005 | hides-standard-window-buttons | Inspect `window.standardWindowButton(_:)` for `.closeButton`, `.miniaturizeButton`, `.zoomButton` | Each returns a button with `isHidden == true`. |
| floating-chooser-panel-controller-006 | floats-above-normal-windows | Inspect `window.level` | `level == .floating`. |
| floating-chooser-panel-controller-007 | joins-all-spaces-and-full-screen-auxiliary | Inspect `window.collectionBehavior` | Contains `.canJoinAllSpaces` and `.fullScreenAuxiliary`. |
| floating-chooser-panel-controller-008 | is-not-user-resizable | Inspect `window.styleMask`; attempt to drag-resize the shown window | `styleMask` does not contain `.resizable`; the drag has no effect. |
| floating-chooser-panel-controller-009 | survives-close-without-releasing | Call `close()`, then reuse the same controller instance in a later `show()` | `window.isReleasedWhenClosed == false`; the same instance reopens successfully. |
| floating-chooser-panel-controller-010 | rejects-coder-initialization | Attempt to construct via `init?(coder:)` | Unavailable at compile time; a forced runtime call traps via `fatalError()`. |
| floating-chooser-panel-controller-011 | positions-on-pointer-screen | Two-screen setup, mouse over screen B; call `show()` | Panel is positioned relative to screen B's visible frame. |
| floating-chooser-panel-controller-012 | falls-back-to-main-screen | Mouse location outside every screen's frame; call `show()` | Panel positions relative to `NSScreen.main`'s visible frame. |
| floating-chooser-panel-controller-013 | falls-back-to-centering-without-visible-frame | Resolved screen's `visibleFrame` is unavailable; call `show()` | `window.center()` runs instead of the pointer-relative calculation. |
| floating-chooser-panel-controller-014 | centers-horizontally-on-screen | Visible frame width 1000pt, window width 400pt; call `show()` | Window `origin.x == visibleFrame.midX - 200`. |
| floating-chooser-panel-controller-015 | offsets-top-edge-by-fixed-fraction | Visible frame height 1000pt; call `show()` | Window's top edge (`origin.y + height`) equals `visibleFrame.maxY - 200`. |
| floating-chooser-panel-controller-016 | activates-app-before-showing | Call `show()` with another app frontmost | `NSApp.activateUnlessQuiet()` runs before `showWindow(nil)`/`makeKeyAndOrderFront(nil)`. Manual/integration-only: the recipe names no injected seam for observing `NSApp.activateUnlessQuiet()`, so this requires swizzling to verify. |
| floating-chooser-panel-controller-017 | respects-quiet-activation | `QuietWindowPresentation.isEnabled == true`; call `show()` | `activate(ignoringOtherApps:)` is not invoked; the window still shows and orders front. Manual/integration-only: the recipe names no injected seam for replacing the static `QuietWindowPresentation.isEnabled`, so this requires swizzling to verify. |
| floating-chooser-panel-controller-018 | shows-and-takes-key-before-initial-focus | Subclass overrides `takeInitialFocus()` to record `window.isKeyWindow` | Recorded value is `true`. |
| floating-chooser-panel-controller-019 | reshows-idempotently | Call `show()` twice in succession | Exactly one window exists; the second call repositions/refocuses it. |
| floating-chooser-panel-controller-020 | defaults-initial-focus-hook-to-no-op | Call `show()` on the base class directly (no override); record the first responder immediately before and after the call | First responder after `show()` is whatever AppKit's own `makeKeyAndOrderFront(nil)` set it to; it is unchanged from that value once `takeInitialFocus()` returns, since the base hook has an empty body. No crash. |
| floating-chooser-panel-controller-021 | dismisses-on-focus-loss-by-default | Read `dismissesOnFocusLoss` on the base class with no override | Returns `true`. |
| floating-chooser-panel-controller-022 | closes-on-focus-loss-when-enabled | `dismissesOnFocusLoss == true`, window visible, `isDismissing == false`; window resigns key | `close()` is invoked and the window closes. |
| floating-chooser-panel-controller-023 | ignores-focus-loss-when-disabled | Subclass overrides `dismissesOnFocusLoss` to `false`; window resigns key | `close()` is not invoked; window remains open. |
| floating-chooser-panel-controller-024 | ignores-focus-loss-while-already-dismissing | `isDismissing == true`; window resigns key while it is still `true` | `close()` is not invoked a second time. |
| floating-chooser-panel-controller-025 | ignores-focus-loss-when-not-visible | `window.isVisible == false`; simulate `windowDidResignKey` | `close()` is not invoked. |
| floating-chooser-panel-controller-026 | guards-close-against-reentrancy | Call `close()` re-entrantly from within `panelWillClose()` | The nested call returns immediately without a second `super.close()`. |
| floating-chooser-panel-controller-027 | resets-dismissing-flag-after-close | Call `close()` to completion, then call `close()` again | The second call proceeds normally (`isDismissing` was reset to `false`). |
| floating-chooser-panel-controller-028 | calls-panel-will-close-on-window-close | Subclass overrides `panelWillClose()` with a counter; dismiss the panel once | Counter equals 1. |
| floating-chooser-panel-controller-029 | defaults-panel-will-close-hook-to-no-op | Close the base class directly (no override); compare controller state before and after | `isDismissing` ends `false` and the window ends closed, with no other controller state changed beyond that; no crash. |
| floating-chooser-panel-controller-030 | decides-size-via-subclass-content-rect | Construct two instances with `contentRect` A (200×100) and B (400×300) | Each window's initial frame size matches its own `contentRect`, independent of the other. |
| floating-chooser-panel-controller-031 | guards-show-against-missing-window | Set `window` to `nil` on a constructed controller, then call `show()` | `position(_:)`, `NSApp.activateUnlessQuiet()`, `showWindow(nil)`, and `takeInitialFocus()` are not invoked; `show()` returns immediately with no effect. |
| floating-chooser-panel-controller-032 | falls-back-to-centering-without-visible-frame | No screen's frame contains the mouse location, and `NSScreen.main` is also `nil`; call `show()` | `window.center()` runs instead of the pointer-relative calculation; no crash from the nil screen. |

## Edge Cases

- **Null/empty input**: `show()` guards `window` being `nil` and returns
  without effect if so (**guards-show-against-missing-window**) — in
  practice the window always exists once `init` has run, but the guard is
  present. If no screen contains the mouse location and `NSScreen.main` is
  also unavailable, `position(_:)` falls back to `window.center()` rather
  than computing an invalid origin
  (**falls-back-to-centering-without-visible-frame**).
- **Boundary values**: `topInsetFraction` is a fixed constant (0.2), not a
  configurable input, so there is no boundary range to exercise on it
  directly.
- **position-clamping**: NEEDS REVIEW: Not implemented in source. `position(_:)` computes the panel's origin from a subclass's `contentRect` and the screen's `visibleFrame` with no clamp against either edge — if `contentRect` height exceeds `visibleFrame.height * (1 - topInsetFraction)`, the computed `origin.y` goes negative and the panel renders partly below the visible frame, or off it entirely on a very short screen; resolving it requires the app team to decide whether the clamp belongs here or in each subclass's sizing.
- **Concurrent access**: The controller is `@MainActor`-isolated, so there is
  no defined behavior for access from another thread — none is needed
  because AppKit window controllers are inherently single-threaded. Within
  the main actor, the one reentrancy case the source guards against is
  `close()` being re-entered while a dismissal is already unwinding
  (`isDismissing`), covered by `guards-close-against-reentrancy` and
  `ignores-focus-loss-while-already-dismissing` above (MUST).
- **Error states**: No fallible operation exists in this file — window and
  panel construction, positioning, and dismissal have no return code or
  thrown error to handle, so there is nothing for this file to report or
  recover from.
- **Offline/disconnected state**: Not applicable — the controller performs
  no network requests and has no dependency on connectivity.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `content` | `NSViewController` | required | The chooser's own content view controller, hosted as a child and pinned to the container's edges. |
| `contentRect` | `NSRect` | required | The panel's initial and only size; the base class applies no default or minimum. |
| `dismissesOnFocusLoss` | `Bool` (overridable computed property) | `true` | Whether losing key-window status dismisses the panel. |

## Deep Linking

Not applicable: no URL-scheme or `NSUserActivity` handling appears anywhere
in `FloatingChooserPanelController.swift`. The panel is shown only by code
constructing a subclass directly.

## Localization

Not applicable: this file contains no user-facing string literals at all —
no window title is ever set (`titleVisibility` is `.hidden`), and no other
text is drawn by this controller.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation (movement, scaling, sliding, zooming, parallax, or looping) is implemented anywhere in this file. |
| Increase Contrast | Not applicable: no custom color is set on the window or container view in this file; the system default `NSPanel` appearance already responds to system contrast settings. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator. |

## Feature Flags

Not applicable: no flag-gated behavior (`FeatureFlag`, remote config, or
similar) appears in this file.

## Analytics

Not applicable: no analytics or event-logging calls appear in this file.

## Privacy

- **Data collected**: None — this file persists no data of its own; window
  position is recomputed on every `show()` and never saved.
- **Storage**: Not applicable — no persistence code exists in this file.
- **Transmission**: None — no networking import or call appears in this
  file.
- **Retention**: Not applicable — nothing is stored.

## Logging

Not applicable: no `Logger`/`os_log`/print-based logging calls appear
anywhere in `FloatingChooserPanelController.swift`.

## Platform Notes

- **SwiftUI**: not the source form. SwiftUI's `WindowGroup`/`Scene` APIs
  have no equivalent to an on-demand, pointer-positioned, `.floating`-level
  panel that joins all Spaces, so a SwiftUI-first chooser would still wrap
  its view in an `NSHostingController` and host it inside an `NSPanel`
  managed by a controller shaped like this one, rather than a pure `Scene`.
- **Compose (Desktop)**: the nearest equivalent is an undecorated
  `androidx.compose.ui.window.Window` (`undecorated = true`,
  `alwaysOnTop = true` for floating-level behavior), positioned
  programmatically on each show; Compose for Desktop has no built-in
  equivalent to `.collectionBehavior`'s space-joining or to automatic
  dismissal on focus loss, so both would need direct AWT/Swing interop on
  top of the `Window` composable.
- **React/Web**: the nearest equivalent is a fixed-position, non-modal
  overlay (a portal styled with `position: fixed`), centered horizontally
  and offset from the top by a percentage of the viewport height; dismissal
  on focus loss has no browser-window analog for an in-page element, so it
  would be approximated with an outside-pointerdown listener and an
  `Escape` keydown handler instead of `windowDidResignKey`.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists (iOS has no floating, multi-Space panel
  concept). File: `FloatingChooserPanelController.swift`. It also calls
  `NSApplication.activateUnlessQuiet()`, defined in
  `NSApplication+QuietActivation.swift`.
- **WinUI 3**: the closest native shape is a secondary, undecorated
  `Microsoft.UI.Xaml.Window`/`AppWindow` with
  `TitleBar.ExtendsContentIntoTitleBar = true` (the WinUI analog of
  `fullSizeContentView`) and `IsShownInSwitchers = false`. There is no
  direct WinUI equivalent to `.floating` window level or to hiding just the
  close button of a titled window the way `standardWindowButton(_:).isHidden`
  does here — an `OverlappedPresenter` with `IsAlwaysOnTop = true` covers the
  always-on-top intent, but a truly buttonless-yet-framed title bar needs a
  fully custom `AppWindowTitleBar` (via `SetPreferredResizableRegions` /
  `ExtendsContentIntoTitleBar`) rather than hiding individual buttons.
  `.canJoinAllSpaces` has no WinUI counterpart either; Windows virtual
  desktops are a separate `VirtualDesktopManager` API and would need
  explicit pin-to-all-desktops calls to match. Positioning maps to
  `DisplayArea.GetFromWindowId`'s work area: center horizontally, offset the
  top edge by 20% of the work-area height, then call `AppWindow.Move`.
  Dismissal on focus loss maps to the `Window.Activated` event with
  `WindowActivationState.Deactivated`, checked against a
  `DismissesOnFocusLoss`-equivalent property before closing — with the same
  reentrancy guard this base class keeps as an owned boolean, since WinUI
  activation events have the same "state hasn't finished updating yet"
  hazard this file's `isDismissing` comment describes.

## Design Decisions

**Decision**: Guard reentrancy with an owned `isDismissing` boolean rather
than inferring "already closing" from window state.
**Rationale**: Closing the key window resigns key *before* the window is
ordered out, so `windowDidResignKey` re-enters mid-close; AppKit's own
window state has not finished updating at that point, so only a
controller-owned flag can distinguish a resignation that is part of this
close from one caused by the user switching away.
**Approved**: pending

**Decision**: Keep `.closable` in the style mask (which puts a close button
in the frame) and then hide the close/miniaturize/zoom buttons explicitly,
rather than omitting `.closable`.
**Rationale**: `.titled` is required for the standard frame and for
`.fullSizeContentView` to draw hosted content up into the title-bar band;
every way out of the panel already goes through `close()` via Escape,
click-away, or accepting a result, so the traffic-light buttons have
nothing left to do and are hidden rather than removed from the style mask.
**Approved**: pending

**Decision**: Call `NSApp.activateUnlessQuiet()` before `showWindow`/
`makeKeyAndOrderFront`, not after.
**Rationale**: A chooser can be opened by a system-global shortcut while
another app is frontmost; activating after taking key would let AppKit
hand key back to whichever of this app's windows held it last, closing the
just-opened panel immediately once focus-loss dismissal runs.
**Approved**: pending

**Decision**: Set `isReleasedWhenClosed = false`.
**Rationale**: `close()` runs on every dismissal, including a plain focus
loss; a chooser is expected to reopen as the same instance rather than
being rebuilt from scratch each time, so the window and its controller
must survive being closed.
**Approved**: pending

**Decision**: Position the panel relative to the screen under the mouse
pointer, not the key window's screen.
**Rationale**: The chooser can be invoked with no window of this app on
screen at all (a system-global shortcut, or an extension request), so
there may be no key window's screen to anchor to; the pointer is the one
reliable proxy for the screen the user is currently looking at.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |

`focus-management` rests on `show()` calling `showWindow(nil)` then
`window.makeKeyAndOrderFront(nil)` before `takeInitialFocus()` runs
(`FloatingChooserPanelController.swift:174-176`), guaranteeing the window is
already key when a subclass assigns first responder, and on
`windowDidResignKey`/`close()` (lines 244-247, 190-195) tearing the panel
down in a single guarded path on focus loss. No other catalog category
applies: the file renders no text, collects or transmits no data, performs
no moderation-relevant function, and has no user-facing string for
internationalization to check.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: name the show() nil-window guard and the no-screen-at-all fallback as requirements with new test vectors 031/032; mark activation vectors 016/017 manual/integration-only (no injected seam for the global activation seam); reformat Design Decisions to bold labels; add the two hosted content-controller recipes to related; loosen test vectors 002/020/029 to concrete, less brittle assertions; clarify the dismissing-interval terminology in the States table and vector 024; clarify resets-dismissing-flag-after-close to describe only the outer close() clearing the flag; rebuild Compliance against the real catalog (accessibility/focus-management only) |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
