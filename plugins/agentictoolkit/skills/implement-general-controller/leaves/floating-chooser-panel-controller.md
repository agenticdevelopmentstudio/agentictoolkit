<!-- leaf: implement-general-controller/floating-chooser-panel-controller · source: floating-chooser-panel-controller.md -->

**Rules** (cite as `implement-general-controller/floating-chooser-panel-controller#<slug>`):

- `hosts-content-as-child-controller` MUST
- `pins-content-to-container-edges` MUST
- `uses-titled-panel-style-mask` MUST
- `hides-title-text` MUST
- `hides-standard-window-buttons` MUST
- `floats-above-normal-windows` MUST
- `joins-all-spaces-and-full-screen-auxiliary` MUST
- `is-not-user-resizable` MUST
- `survives-close-without-releasing` MUST
- `rejects-coder-initialization` MUST
- `guards-show-against-missing-window` MUST
- `positions-on-pointer-screen` MUST
- `falls-back-to-main-screen` MUST
- `falls-back-to-centering-without-visible-frame` MUST
- `centers-horizontally-on-screen` MUST
- `offsets-top-edge-by-fixed-fraction` MUST
- `activates-app-before-showing` MUST
- `respects-quiet-activation` MUST
- `shows-and-takes-key-before-initial-focus` MUST
- `reshows-idempotently` MUST
- `defaults-initial-focus-hook-to-no-op` MUST
- `dismisses-on-focus-loss-by-default` MUST
- `closes-on-focus-loss-when-enabled` MUST
- `ignores-focus-loss-when-disabled` MUST
- `ignores-focus-loss-while-already-dismissing` MUST
- `ignores-focus-loss-when-not-visible` MUST
- `guards-close-against-reentrancy` MUST
- `resets-dismissing-flag-after-close` MUST
- `calls-panel-will-close-on-window-close` MUST
- `defaults-panel-will-close-hook-to-no-op` MUST
- `decides-size-via-subclass-content-rect` MUST
- `keyboard-focus-panel-become-key-window-before` MUST — Keyboard/focus: The panel MUST become the key window before takeInitialFocus() is called (show() calls showWindow(nil), …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `content` | `NSViewController` | required | The chooser's own content view controller, hosted as a child and pinned to the container's edges. |
| `contentRect` | `NSRect` | required | The panel's initial and only size; the base class applies no default or minimum. |
| `dismissesOnFocusLoss` | `Bool` (overridable computed property) | `true` | Whether losing key-window status dismisses the panel. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation (movement, scaling, sliding, zooming, parallax, or looping) is implemented anywhere in this file. |
| Increase Contrast | Not applicable: no custom color is set on the window or container view in this file; the system default `NSPanel` appearance already responds to system contrast settings. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator. |

