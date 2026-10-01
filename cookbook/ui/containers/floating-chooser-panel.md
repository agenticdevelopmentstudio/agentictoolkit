---
id: ba1406b3-bcf8-4580-9d65-daed2311cccf
title: Floating Chooser Panel
domain: agentictoolkit://cookbook/ui/containers/floating-chooser-panel
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Shared foundation for the app''s floating, titleless chooser panels: shared
  positioning, activation, focus-loss dismissal, and reentrant-close guarding.'
platforms:
- swift
- macos
tags:
- panel-controller
- floating-panel
- window-controller
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-quick-pick-view
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-input-box-view
references: []
approved-by: ''
approved-date: ''
---

# Floating Chooser Panel

## Overview

This is the shared foundation for every transient chooser panel in the app —
the command palette and the quick-pick / input-box panels an extension can
ask for. It owns everything those choosers have in common: a floating,
titleless panel hosting an extending component's content as a genuine child
in the content hierarchy, pointer-relative positioning near the top of the
screen, activation-before-show, dismissal when the panel loses key status,
and a reentrancy guard around the single dismissal path. An extending
component decides exactly three things: the panel's size (via the
`contentRect` value passed at construction), whether losing focus dismisses
the panel (`dismissesOnFocusLoss`), and what happens on the way in and out
(the initial-focus hook and the pre-close hook). This recipe documents only
what this shared foundation itself does; an extending component's own
sizing, content, and focus/dismissal behavior belongs to that component's
own recipe.

## Behavioral Requirements

- **hosts-content-as-child-controller**: The panel MUST add the hosted
  content as a child of an intermediate container, and that container — not
  the hosted content itself — MUST be the window's top-level content.
- **pins-content-to-container-edges**: The hosted content's view MUST be
  constrained to the top, leading, trailing, and bottom edges of the
  container, with zero additional padding.
- **uses-titled-panel-style-mask**: The panel's window MUST use a titled
  panel style that supports closing and lets hosted content extend into the
  title-bar area.
- **hides-title-text**: The window's title text MUST be invisible, and the
  title bar's background MUST be transparent.
- **hides-standard-window-buttons**: The window's close, minimize, and zoom
  title-bar buttons MUST be hidden, even though the title bar style supports
  a close button.
- **floats-above-normal-windows**: The window MUST float above normal
  application windows.
- **joins-all-spaces-and-full-screen-auxiliary**: The window MUST remain
  visible on every virtual desktop/workspace, and MUST be treated as an
  auxiliary window while another window is in full-screen mode.
- **is-not-user-resizable**: The window MUST NOT be resizable by the user.
- **survives-close-without-releasing**: Closing the panel MUST NOT
  release/destroy the underlying window; the same window instance MUST
  remain reusable across repeated close/show cycles.
- **rejects-coder-initialization**: See Platform Notes.
- **guards-show-against-missing-window**: Showing the panel MUST return
  immediately, performing no positioning, activation, or focus work, if the
  underlying window does not exist.
- **positions-on-pointer-screen**: Showing the panel MUST position it on
  the screen whose frame contains the current pointer location.
- **falls-back-to-main-screen**: If no screen contains the pointer
  location, positioning MUST fall back to the main screen.
- **falls-back-to-centering-without-visible-frame**: If the resolved screen
  has no usable visible area — including when no screen contains the
  pointer location and there is no main screen either — the panel MUST be
  centered on the screen instead of using the pointer-relative calculation.
- **centers-horizontally-on-screen**: The panel's horizontal position MUST
  center it within the target screen's visible area: horizontal position =
  the visible area's horizontal midpoint minus half the panel's width.
- **offsets-top-edge-by-fixed-fraction**: The panel's top edge MUST sit 20%
  of the visible area's height below the top of the visible area.
- **activates-app-before-showing**: Showing the panel MUST activate the
  application before ordering the panel's window to the front.
- **respects-quiet-activation**: Activation during showing MUST go through
  a quiet-aware activation path that skips forcibly activating the app
  (bringing it to the front over other apps) when quiet-window presentation
  is enabled.
- **shows-and-takes-key-before-initial-focus**: Showing the panel MUST make
  the window key and bring it to the front before calling the initial-focus
  hook, so the window MUST already have keyboard focus when that hook runs.
- **reshows-idempotently**: Showing an already-open panel again MUST
  reposition and refocus the same window rather than creating a second
  window.
- **defaults-initial-focus-hook-to-no-op**: The initial-focus hook MUST do
  nothing in the base implementation; an extending component that needs
  initial-focus behavior MUST override it.
- **dismisses-on-focus-loss-by-default**: The base implementation's
  focus-loss dismissal setting (`dismissesOnFocusLoss`) MUST default to
  `true`.
- **closes-on-focus-loss-when-enabled**: When focus-loss dismissal is
  enabled, the window is visible, and no dismissal is already in progress,
  losing key status MUST close the panel.
- **ignores-focus-loss-when-disabled**: When focus-loss dismissal is
  disabled, losing key status MUST NOT close the panel.
- **ignores-focus-loss-while-already-dismissing**: While a dismissal is
  already in progress (`isDismissing == true`), losing key status MUST NOT
  close the panel again.
- **ignores-focus-loss-when-not-visible**: If the window is not visible,
  losing key status MUST NOT close the panel.
- **guards-close-against-reentrancy**: Closing the panel MUST return
  immediately without performing the underlying close if a dismissal is
  already in progress (`isDismissing == true`).
- **resets-dismissing-flag-after-close**: Closing the panel MUST clear
  `isDismissing` back to `false` after the underlying close completes.
  Only the outer call — the one that found `isDismissing == false` and set
  it to `true` — reaches this reset; a nested, reentrant call returns at
  the reentrancy guard before it, so it never touches the flag. The next
  dismissal of a re-shown panel MUST therefore be treated as a fresh entry.
- **calls-panel-will-close-on-window-close**: The window closing MUST run
  the pre-close hook exactly once per dismissal.
- **defaults-panel-will-close-hook-to-no-op**: The pre-close hook MUST do
  nothing in the base implementation; an extending component that needs
  teardown behavior on close MUST override it.
- **decides-size-via-subclass-content-rect**: The window's initial size
  MUST come entirely from the `contentRect` value an extending component
  supplies at construction; the base implementation MUST NOT compute or
  default a size of its own.

## Appearance

- **Corner radius**: Not applicable — the controller draws no
  custom-cornered chrome; whatever corner rounding appears is the system's
  own standard panel rendering.
- **Padding**: The hosted content view's edge constraints to the container
  view carry no additional constant — 0pt padding on all four sides.
- **Font**: Not applicable — the controller renders no text of its own; any
  text belongs to the hosted content component, a separate ingredient.
- **Background**: Not specified in source — no background color is set on
  the window or the container view in this file; the panel uses the system
  default panel background.
- **Foreground/Text**: Not applicable — see Font.
- **Border**: Not applicable — no custom border is configured in this file;
  standard system panel border applies.
- **Shadow**: Not applicable — no custom shadow is configured in this file;
  the standard floating-panel shadow applies.
- **Min/Max size**: Not applicable — the window is not user-resizable, so
  no min/max size constraint is needed or set; the window's fixed size is
  the `contentRect` value an extending component supplies at construction.

## States

| State | Appearance change |
|-------|------------------|
| Default | Newly initialized, not yet shown (window not visible); `isDismissing == false`. |
| Pressed | Not applicable — the controller renders no pressable surface of its own; per-press visuals belong to whatever content component an extending component hosts. |
| Disabled | Not applicable — no enabled/disabled state exists for this window controller in source. |
| Focused | Window is key (showing the panel made it key); first responder is whatever the initial-focus hook set, per extending component. |
| Loading | Not applicable — showing the panel is synchronous; no loading/spinner state exists in source. |
| Dismissing | `isDismissing == true`, from entry into closing the panel until the underlying close completes; a nested close call or a focus-loss notification arriving during this interval MUST have no effect. |
| Focus lost, `dismissesOnFocusLoss == true` | Panel closes (losing key status closes the panel). |
| Focus lost, `dismissesOnFocusLoss == false` | Panel remains open and visible; only key-window status is lost. |

## Accessibility

- Role/traits: Not applicable at this layer — the controller sets no
  accessibility role, trait, or identifier of its own; the standard panel
  role applies, and interactive elements (list rows, search fields,
  buttons) belong to whichever content component an extending component
  hosts, each with its own recipe.
- Keyboard/focus: The panel MUST become the key window before the
  initial-focus hook is called (showing the panel makes the window key and
  brings it to the front, then calls the initial-focus hook), so an
  extending component's initial-focus hook can always assume the window is
  already key. No explicit focus-restoration code exists in this file
  beyond closing the panel itself; losing key status when the panel closes
  is standard platform behavior.
- Label requirements: Not applicable — no accessibility label or identifier
  is assigned to the window or the container view in this file.
- Announce state changes: Not applicable — the panel has no loading or
  disabled state to announce.
- Minimum tap target: Not applicable — this controller renders no
  interactive control of its own; the window's standard title-bar buttons
  are explicitly hidden, and the hosted content's controls are covered by
  that content component's own recipe.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| floating-chooser-panel-controller-001 | hosts-content-as-child-controller | Construct the controller with a content component and any `contentRect` | The window's top-level content is the container; the content component appears among the container's children. |
| floating-chooser-panel-controller-002 | pins-content-to-container-edges | Inspect the container's layout constraints after construction | The content view's top, leading, trailing, and bottom edges are each pinned to the container's matching edge with 0 additional padding. |
| floating-chooser-panel-controller-003 | uses-titled-panel-style-mask | Inspect the window's style traits after construction | The window uses a titled panel style that supports closing and lets hosted content extend into the title-bar area. |
| floating-chooser-panel-controller-004 | hides-title-text | Inspect the window's title visibility and title-bar transparency after construction | Title text is hidden; the title bar's background is transparent. |
| floating-chooser-panel-controller-005 | hides-standard-window-buttons | Inspect the window's close, minimize, and zoom title-bar buttons | Each is hidden. |
| floating-chooser-panel-controller-006 | floats-above-normal-windows | Inspect the window's level | The window floats above normal application windows. |
| floating-chooser-panel-controller-007 | joins-all-spaces-and-full-screen-auxiliary | Inspect the window's cross-desktop/full-screen behavior settings | The window is visible on every virtual desktop/workspace and behaves as an auxiliary window during another window's full-screen mode. |
| floating-chooser-panel-controller-008 | is-not-user-resizable | Inspect the window's resizability; attempt to drag-resize the shown window | The window is not resizable; the drag has no effect. |
| floating-chooser-panel-controller-009 | survives-close-without-releasing | Close the panel, then reuse the same controller instance in a later show | The underlying window is not released/destroyed by closing; the same instance reopens successfully. |
| floating-chooser-panel-controller-011 | positions-on-pointer-screen | Two-screen setup, pointer over screen B; show the panel | Panel is positioned relative to screen B's visible area. |
| floating-chooser-panel-controller-012 | falls-back-to-main-screen | Pointer location outside every screen's frame; show the panel | Panel positions relative to the main screen's visible area. |
| floating-chooser-panel-controller-013 | falls-back-to-centering-without-visible-frame | Resolved screen's visible area is unavailable; show the panel | The panel is centered on the screen instead of using the pointer-relative calculation. |
| floating-chooser-panel-controller-014 | centers-horizontally-on-screen | Visible area width 1000pt, window width 400pt; show the panel | Window's horizontal position `== the visible area's horizontal midpoint - 200pt`. |
| floating-chooser-panel-controller-015 | offsets-top-edge-by-fixed-fraction | Visible area height 1000pt; show the panel | The window's top edge sits 200pt below the top of the visible area. |
| floating-chooser-panel-controller-016 | activates-app-before-showing | Show the panel with another app frontmost | The application is activated before the panel's window is brought to the front. Manual/integration-only: the recipe names no injected seam for observing this activation step, so this requires swizzling to verify. |
| floating-chooser-panel-controller-017 | respects-quiet-activation | Quiet-window presentation is enabled; show the panel | The forceful activation step is skipped; the window still shows and comes to the front. Manual/integration-only: the recipe names no injected seam for replacing the quiet-window presentation setting, so this requires swizzling to verify. |
| floating-chooser-panel-controller-018 | shows-and-takes-key-before-initial-focus | Override the initial-focus hook to record whether the window is key at that moment | Recorded value is `true`. |
| floating-chooser-panel-controller-019 | reshows-idempotently | Show the panel twice in succession | Exactly one window exists; the second call repositions/refocuses it. |
| floating-chooser-panel-controller-020 | defaults-initial-focus-hook-to-no-op | Show the base implementation directly (no override); record the first responder immediately before and after | First responder after showing is whatever the platform's own key/front-ordering operation set it to; it is unchanged from that value once the initial-focus hook returns, since the base hook does nothing. No crash. |
| floating-chooser-panel-controller-021 | dismisses-on-focus-loss-by-default | Read the focus-loss dismissal setting on the base implementation with no override | Returns `true`. |
| floating-chooser-panel-controller-022 | closes-on-focus-loss-when-enabled | Focus-loss dismissal enabled, window visible, no dismissal in progress; window loses key status | Closing is invoked and the window closes. |
| floating-chooser-panel-controller-023 | ignores-focus-loss-when-disabled | An extending component disables focus-loss dismissal; window loses key status | Closing is not invoked; window remains open. |
| floating-chooser-panel-controller-024 | ignores-focus-loss-while-already-dismissing | A dismissal is already in progress; window loses key status again while it is still in progress | Closing is not invoked a second time. |
| floating-chooser-panel-controller-025 | ignores-focus-loss-when-not-visible | Window is not visible; simulate a focus-loss notification | Closing is not invoked. |
| floating-chooser-panel-controller-026 | guards-close-against-reentrancy | Call close re-entrantly from within the pre-close hook | The nested call returns immediately without a second underlying close. |
| floating-chooser-panel-controller-027 | resets-dismissing-flag-after-close | Close to completion, then close again | The second call proceeds normally (`isDismissing` was reset to `false`). |
| floating-chooser-panel-controller-028 | calls-panel-will-close-on-window-close | An extending component overrides the pre-close hook with a counter; dismiss the panel once | Counter equals 1. |
| floating-chooser-panel-controller-029 | defaults-panel-will-close-hook-to-no-op | Close the base implementation directly (no override); compare controller state before and after | `isDismissing` ends `false` and the window ends closed, with no other controller state changed beyond that; no crash. |
| floating-chooser-panel-controller-030 | decides-size-via-subclass-content-rect | Construct two instances with `contentRect` A (200×100) and B (400×300) | Each window's initial frame size matches its own `contentRect`, independent of the other. |
| floating-chooser-panel-controller-031 | guards-show-against-missing-window | Set the underlying window to absent on a constructed controller, then show it | Positioning, activation, showing, and the initial-focus hook are not invoked; showing returns immediately with no effect. |
| floating-chooser-panel-controller-032 | falls-back-to-centering-without-visible-frame | No screen's frame contains the pointer location, and there is no main screen either; show the panel | The panel is centered on the screen instead of using the pointer-relative calculation; no crash from the missing screen. |

`rejects-coder-initialization` has no test vector: see Platform Notes for how it is verified.

## Edge Cases

- **Null/empty input**: Showing the panel guards against the underlying
  window not existing and returns without effect if so
  (**guards-show-against-missing-window**) — in practice the window always
  exists once construction has run, but the guard is present. If no screen
  contains the pointer location and there is no main screen either,
  positioning falls back to centering rather than computing an invalid
  origin (**falls-back-to-centering-without-visible-frame**).
- **Boundary values**: The top-edge offset is a fixed 20% fraction, not a
  configurable input, so there is no boundary range to exercise on it
  directly.
- **position-clamping**: NEEDS REVIEW: Not implemented in source.
  Positioning computes the panel's origin from an extending component's
  `contentRect` and the screen's visible area with no clamp against either
  edge — if `contentRect` height exceeds the visible area's height reduced
  by the top-edge offset fraction, the computed vertical origin goes
  negative and the panel renders partly below the visible area, or off it
  entirely on a very short screen; resolving it requires the app team to
  decide whether the clamp belongs here or in each extending component's
  sizing.
- **Concurrent access**: The controller is confined to a single thread of
  execution for its entire lifetime, so there is no defined behavior for
  access from another thread — none is needed because this kind of window
  controller is inherently single-threaded. See Platform Notes for how that confinement is enforced. Within that single
  thread, the one reentrancy case the source guards against is closing
  being re-entered while a dismissal is already unwinding (`isDismissing`),
  covered by `guards-close-against-reentrancy` and
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
| `content` | Content component | required | The chooser's own content component, hosted as a child and pinned to the container's edges. |
| `contentRect` | Rect | required | The panel's initial and only size; the base implementation applies no default or minimum. |
| `dismissesOnFocusLoss` | `Bool` (overridable) | `true` | Whether losing key-window status dismisses the panel. |

## Deep Linking

Not applicable: no URL-scheme or system-activity handling appears anywhere
in this component's source. The panel is shown only by code constructing an
extending component directly.

## Localization

Not applicable: this file contains no user-facing string literals at all —
no window title is ever shown, and no other text is drawn by this
controller.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation (movement, scaling, sliding, zooming, parallax, or looping) is implemented anywhere in this file. |
| Increase Contrast | Not applicable: no custom color is set on the window or container view in this file; the system default panel appearance already responds to system contrast settings. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator. |

## Feature Flags

Not applicable: no flag-gated behavior (feature flag, remote config, or
similar) appears in this file.

## Analytics

Not applicable: no analytics or event-logging calls appear in this file.

## Privacy

- **Data collected**: None — this file persists no data of its own; window
  position is recomputed on every show and never saved.
- **Storage**: Not applicable — no persistence code exists in this file.
- **Transmission**: None — no networking import or call appears in this
  file.
- **Retention**: Not applicable — nothing is stored.

## Logging

Not applicable: no logging calls appear anywhere in this component's
source.

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
  `NSApplication+QuietActivation.swift`. Concrete API mapping for the
  requirements above: the class is `open`, `@MainActor`, and an
  `NSWindowController` subclass; it fails with a fatal error if constructed
  via `init?(coder:)` (`rejects-coder-initialization`), since it provides
  no Interface Builder/`NSCoding` support. The container/content
  relationship is `NSViewController`s, with the container set as
  `window.contentViewController` and the hosted content added as a
  child controller; the content view's edges are pinned with Auto Layout
  (`translatesAutoresizingMaskIntoConstraints = false`). The window is an
  `NSPanel` with `styleMask == [.titled, .closable, .fullSizeContentView]`;
  `titleVisibility == .hidden` and `titlebarAppearsTransparent == true`;
  `standardWindowButton(_:)` for `.closeButton`, `.miniaturizeButton`, and
  `.zoomButton` each have `isHidden == true`; `window.level == .floating`;
  `collectionBehavior` includes `.canJoinAllSpaces` and
  `.fullScreenAuxiliary`; `styleMask` omits `.resizable`;
  `isReleasedWhenClosed == false`. Positioning uses
  `NSEvent.mouseLocation` to find the pointer's screen, falls back to
  `NSScreen.main`, and falls back further to `NSWindow.center()` when
  `visibleFrame` is unavailable; the horizontal formula is
  `origin.x = visibleFrame.midX - width / 2`, and the vertical offset is
  driven by the fixed constant `topInsetFraction = 0.2`. Activation and
  showing go through `NSApp.activateUnlessQuiet()` (which skips
  `activate(ignoringOtherApps:)` when `QuietWindowPresentation.isEnabled`
  is `true`), then `showWindow(nil)`, then
  `window.makeKeyAndOrderFront(nil)`, then the overridable
  `takeInitialFocus()` hook. Dismissal flows through `windowDidResignKey`
  calling `close()` (guarded by the `dismissesOnFocusLoss`,
  `isDismissing`, and window-visibility checks above), `close()` itself
  guarding reentrancy against `super.close()` and clearing `isDismissing`
  after it returns, and `windowWillClose` calling the overridable
  `panelWillClose()` hook exactly once. The initializer signature is
  `init(content: NSViewController, contentRect: NSRect)`.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/Panels/FloatingChooserPanelController.swift` |

## Design Decisions

**Decision**: Guard reentrancy with an owned `isDismissing` boolean rather
than inferring "already closing" from window state.
**Rationale**: Closing the key window resigns key *before* the window is
ordered out, so `windowDidResignKey` re-enters mid-close; the platform's
own window state has not finished updating at that point, so only a
controller-owned flag can distinguish a resignation that is part of this
close from one caused by the user switching away. (Applies to the AppKit
implementation.)
**Approved**: pending

**Decision**: Keep `.closable` in the style mask (which puts a close button
in the frame) and then hide the close/miniaturize/zoom buttons explicitly,
rather than omitting `.closable`.
**Rationale**: `.titled` is required for the standard frame and for
`.fullSizeContentView` to draw hosted content up into the title-bar band;
every way out of the panel already goes through `close()` via Escape,
click-away, or accepting a result, so the traffic-light buttons have
nothing left to do and are hidden rather than removed from the style mask.
(Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Call `NSApp.activateUnlessQuiet()` before `showWindow`/
`makeKeyAndOrderFront`, not after.
**Rationale**: A chooser can be opened by a system-global shortcut while
another app is frontmost; activating after taking key would let the
platform hand key back to whichever of this app's windows held it last,
closing the just-opened panel immediately once focus-loss dismissal runs.
(Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Set `isReleasedWhenClosed = false`.
**Rationale**: `close()` runs on every dismissal, including a plain focus
loss; a chooser is expected to reopen as the same instance rather than
being rebuilt from scratch each time, so the window and its controller
must survive being closed. (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Position the panel relative to the screen under the mouse
pointer, not the key window's screen.
**Rationale**: The chooser can be invoked with no window of this app on
screen at all (a system-global shortcut, or an extension request), so
there may be no key window's screen to anchor to; the pointer is the one
reliable proxy for the screen the user is currently looking at. (Applies
to the AppKit implementation, though the underlying rationale — anchoring
to wherever the user's attention is, absent a focused window — carries to
any platform's port.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |

`focus-management` rests on `show()` calling `showWindow(nil)` then
`window.makeKeyAndOrderFront(nil)` before `takeInitialFocus()` runs
(`FloatingChooserPanelController.swift`), guaranteeing the window is
already key when a subclass assigns first responder, and on
`windowDidResignKey`/`close()` tearing the panel
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
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/containers/. |
