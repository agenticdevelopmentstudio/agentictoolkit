---
id: 46b9d1b8-8a6e-4b61-98ec-5201be24302f
title: Pointing Hand Button
domain: agentictoolkit://cookbook/ui/controls/pointing-hand-button
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A button that shows the pointing-hand cursor over its bounds even when
  its window does not have focus, via a cursor rect plus an always-active
  hover-tracking region.
platforms:
- swift
- macos
tags:
- ui
- button
- cursor
depends-on: []
related: []
references:
- https://developer.apple.com/documentation/appkit/nscursor
- https://developer.apple.com/documentation/appkit/nstrackingarea
- https://developer.apple.com/documentation/appkit/nsview/resetcursorrects()
- https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)
approved-by: ''
approved-date: ''
---

# Pointing Hand Button

## Overview

This is a button that shows the pointing-hand cursor whenever the pointer
is within its bounds, whether or not its window currently has focus. Per
the source's own doc comment, a plain cursor-rect update alone is not
enough for the windows this toolkit puts on screen: a floating panel
beside the terminal the user is typing into is often not the focused
window, and the platform's cursor-rect mechanism only takes effect in the
focused window, so the one clickable thing in an unfocused list would
otherwise look like the surrounding text. This component combines the
ordinary cursor-rect update with an always-active hover-tracking mechanism
that sets the cursor directly from enter/move/exit callbacks, covering the
unfocused-window case, while the cursor rect still covers the ordinary
case where the platform resets the cursor on the way out.

## Behavioral Requirements

- **cursor-rect**: The component MUST register the pointing-hand cursor
  over its full `bounds` via the platform's cursor-rect mechanism.
- **tracking-area-replacement**: WHEN the hover-tracking registration step
  runs, the component MUST first defer to the default tracking-area setup,
  and, if a previously registered hover-tracking region exists, MUST
  remove it before adding the new one.
- **always-active-tracking**: WHEN the hover-tracking registration step
  runs, the component MUST register a new hover-tracking region covering
  its full `bounds`, owned by itself, configured to report pointer entry,
  exit, and movement, and to remain active regardless of window focus, so
  tracking remains active whether or not the button's window has focus.
- **enter-cursor**: WHEN a pointer-entered event is delivered, the
  component MUST set the current cursor to the pointing-hand cursor.
- **move-cursor**: WHEN a pointer-moved event is delivered, the component
  MUST set the current cursor to the pointing-hand cursor.
- **exit-cursor**: WHEN a pointer-exited event is delivered, the component
  MUST set the current cursor to the default arrow cursor.

## Appearance

- **Corner radius**: Not set by this component; governed entirely by the
  platform's default button bezel style — no bezel-style or layer
  customization appears in source.
- **Padding**: Not set; this component applies no internal padding of its
  own.
- **Font**: Not set; font is never assigned, so the platform's default
  control font applies unmodified.
- **Background**: Not set; this component performs no drawing or layer
  coloring of its own.
- **Foreground/Text**: Not set; no title-color or styled-title
  customization appears in source.
- **Border**: Not set; no border or bezel customization appears in source.
- **Shadow**: Not set; no shadow customization appears in source.
- **Min/Max size**: Not set; the component adds no size constraints —
  `bounds` is read wherever it appears (cursor rect, hover-tracking region)
  but never written.

## States

| State | Appearance change |
|-------|------------------|
| Default | Cursor is the default arrow cursor until the pointer enters `bounds`; this component applies no other styling of its own outside of cursor management. |
| Pressed | Not styled by this component; the source overrides none of the platform's press-handling, so the native bezel press feedback applies unmodified. |
| Disabled | Not implemented: none of the overridden methods reads the enabled state, so the cursor-rect update and the pointer-entered/moved handlers set the pointing-hand cursor unconditionally, even on a disabled button that cannot be clicked. |
| Focused | Not styled by this component; no focus-ring override appears in source, so the platform's native focus appearance applies unmodified. |
| Loading | Not applicable: this component performs no asynchronous work and defines no loading state. |

## Accessibility

- **Role**: Not set by this component; inherited from the platform's
  default button — no accessibility-role override appears in source.
- **Label**: Not set by this component; the accessible name follows the
  platform's own title-based naming, which this component never reads or
  writes.
- **Announce state changes**: Not applicable: this component introduces
  no state of its own beyond the standard button states (see States); the
  one behavior it does add — cursor shape on hover — is not a state the
  platform's accessibility APIs announce.
- **Keyboard navigation**: Inherited from the platform's default button
  unmodified — this component overrides no key-handling or focus method,
  so Tab/Shift-Tab focus movement and Space/Return activation follow the
  platform's native behavior.
- **Minimum tap target**: This component sets no control-size, width, or
  height of its own, so its click target is whatever the platform's
  regular-size system button computes for its title. This platform is
  pointer-driven, not touch-driven, so no minimum touch-target size
  applies here (see Compliance). Ports to touch platforms MUST give the
  equivalent control at least the platform minimum (44×44 pt on iOS,
  48×48 dp on Android, 40×40 epx on WinUI 3).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pointing-hand-button-001 | cursor-rect | Trigger the cursor-rect update on a button laid out at bounds (0, 0, 100, 30) | A cursor rect covering (0, 0, 100, 30) is registered with the pointing-hand cursor |
| pointing-hand-button-003 | tracking-area-replacement | Trigger the hover-tracking registration step twice in succession on the same instance | Among the button's registered hover-tracking regions, exactly one is owned by the button and configured to remain active regardless of window focus — the second call replaced the first instead of adding a duplicate |
| pointing-hand-button-004 | always-active-tracking | Trigger the hover-tracking registration step on a button whose window does not have focus | A registered hover-tracking region covers the button's bounds, is owned by the button, and is configured to report entry, exit, and movement while remaining active regardless of window focus |
| pointing-hand-button-005 | enter-cursor | Deliver a synthetic pointer-entered event | The current system cursor becomes the pointing-hand cursor |
| pointing-hand-button-006 | move-cursor | Deliver a synthetic pointer-moved event | The current system cursor becomes the pointing-hand cursor |
| pointing-hand-button-007 | exit-cursor | Deliver a synthetic pointer-exited event | The current system cursor becomes the default arrow cursor |

## Edge Cases

- **Null/empty input**: Not applicable — this component defines no
  initializer, property, or configuration input of its own; the only
  inputs are the event arguments the platform supplies to the
  pointer-entered/moved/exited callbacks, which are never absent.
- **Boundary values**: This component passes `bounds` unmodified to both
  the cursor-rect registration and the hover-tracking region, with no
  minimum-size guard in source. A zero-size or not-yet-laid-out `bounds`
  is passed through as-is — the resulting cursor-rect/tracking behavior
  for a zero-area rect is the platform's own, not something this
  component special-cases.
- **Concurrent access**: Not applicable — the cursor-rect update, the
  hover-tracking registration step, and the pointer-event callbacks are
  all view-lifecycle methods that execute on the main thread only; the
  one hover-tracking-region property this component holds is read and
  written exclusively from those main-thread callbacks.
- **Error states**: Not applicable — this component has no dependency on
  network, database, or file-system access; cursor and hover-tracking
  management cannot fail in the way this source uses them.
- **Offline/disconnected state**: Not applicable — this component
  performs no networking.
- **Unfocused window with pointer inside bounds**: This is the case the
  component exists to handle. Because tracking is configured to remain
  active regardless of window focus rather than only within the focused
  window (per the source's own comment), the pointer-entered/moved/exited
  callbacks continue to fire even while the button's window does not have
  focus, so the pointing-hand cursor still appears — unlike a plain button
  relying on the cursor-rect mechanism alone, whose cursor rect the
  platform only honors in the focused window.
- **Exit into a cursor-owning sibling**: The pointer-exited callback
  unconditionally resets to the default arrow cursor (see conformance
  vector pointing-hand-button-007), with no check on what the pointer
  moved onto. If the pointer exits this component's bounds directly into
  a sibling view that manages its own cursor (for example, a text view
  showing a text-insertion cursor), this handler's reset can momentarily
  overwrite that sibling's cursor before the sibling's own tracking or
  cursor-rect mechanism re-asserts it. This is a known limitation of the
  source's unconditional reset, not a coordinated hand-off between views.

## Configuration

Not applicable: this component defines no public initializer, property, or
configuration option of its own; it is a drop-in button with fixed,
unconditional cursor and hover-tracking behavior.

## Deep Linking

Not applicable: this component is a cursor-behavior extension of the
platform's default button with no navigable identity, route, or resource
of its own.

## Localization

Not applicable: this component defines no string literal or string key of
its own; any title text a caller sets on the underlying button is outside
this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this component applies no animation or transition; cursor changes are instantaneous system cursor swaps, not motion. |
| Increase Contrast | Not applicable: this component sets no custom colors of its own; the pointing-hand and arrow cursor images are the system's own imagery, unaffected by this component. |
| Differentiate Without Color | Not applicable: this component conveys no state through color; its one signal is the system pointing-hand cursor shape, which is already a non-color affordance. |

## Feature Flags

Not applicable: the source contains no feature-flag check; this component
applies its cursor and hover-tracking behavior unconditionally.

## Analytics

Not applicable: the source emits no analytics events; this component only
manages cursor and hover-tracking state.

## Privacy

- **Data collected**: None. This component holds only a private
  hover-tracking-region reference; it collects no data.
- **Storage**: N/A — no persistence; state lives only in memory for the
  button's lifetime.
- **Transmission**: N/A — this component performs no network or IPC
  calls.
- **Retention**: N/A — nothing is retained beyond the button's lifetime.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: There is no direct `NSButton`-subclassing counterpart. On macOS 15+, prefer [`.pointerStyle(.link)`](https://developer.apple.com/documentation/swiftui/view/pointerstyle%28_:%29) on a `Button` — SwiftUI's native pointing-hand affordance. On earlier macOS targets, apply `.onHover { isHovering in if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }` instead; verify in a non-key panel that the hover callback still fires there, since SwiftUI's documentation does not state whether `onHover` depends on key-window status the way `resetCursorRects()` does.
- **Compose**: On Compose for Desktop, apply `Modifier.pointerHoverIcon(PointerIcon.Hand)` to the composable; verify in a non-key panel that the pointer icon still applies there, since Compose Desktop's documentation does not state whether pointer-icon handling depends on window focus the way AppKit's cursor rects do.
- **React/Web**: Set CSS `cursor: pointer` on the element. Browsers already display the pointer cursor over an element in any window, focused or not, so there is no equivalent to the source's key-window workaround to port.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/CoreUI/PointingHandButton.swift` is
  macOS-only (`import AppKit`); there is no iOS/UIKit counterpart, since
  UIKit has no cursor-rect or `NSCursor` concept — cursors do not apply to
  a touch interface. The class subclasses `NSButton` and layers an
  `.activeAlways` `NSTrackingArea` (`mouseEntered`/`mouseMoved`/
  `mouseExited`, held as a private `hoverArea` property) on top of the
  ordinary `resetCursorRects()` override, specifically to also cover
  floating, non-key panels that `resetCursorRects()` alone does not reach.
  `cursor-rect` is implemented as `addCursorRect(bounds,
  cursor: .pointingHand)` inside `resetCursorRects()`.
  `tracking-area-replacement`/`always-active-tracking` are implemented in
  an overridden `updateTrackingAreas()`, which calls
  `super.updateTrackingAreas()` first, removes `hoverArea` via
  `if let hoverArea { removeTrackingArea(hoverArea) }` when it exists, and
  then registers a new `NSTrackingArea(rect: bounds, options:
  [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self,
  userInfo: nil)`. `enter-cursor`/`move-cursor`/`exit-cursor` are
  `mouseEntered(with:)`/`mouseMoved(with:)` calling
  `NSCursor.pointingHand.set()`, and `mouseExited(with:)` calling
  `NSCursor.arrow.set()`. None of the five overridden methods reads
  `isEnabled`, and no `bezelStyle`, `isBordered`, `attributedTitle`, or
  `controlSize` customization appears anywhere in source.
- **WinUI 3**: Subclass `Button` and set `ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.Hand)` in the constructor. WinUI applies and restores the protected cursor automatically as the pointer enters and exits the control, so no `PointerEntered`/`PointerExited` handlers are needed. `ProtectedCursor` is `protected`, so this must be set from within a `Button` subclass, not from a containing element — a WinUI 3 port needs only this one constructor assignment, not a second, always-active tracking mechanism.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/CoreUI/PointingHandButton.swift` |

## Design Decisions

**Decision**: The pointing-hand cursor is set from both the cursor-rect
update and an always-active hover-tracking region's enter/move/exit
handlers, rather than from the cursor-rect update alone.
**Rationale**: Per the source's own doc comment, cursor rects are honored
by the platform only in the focused window, but this toolkit places
clickable controls in windows that are not focused (a floating panel
beside the terminal the user is typing into); the always-active
hover-tracking region covers that case, "and the cursor rect still covers
the ordinary one, where AppKit resets the cursor for us on the way out."
(Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: The hover-tracking registration step removes any existing
hover-tracking region before adding a new one, rather than leaving prior
regions registered.
**Rationale**: Traceable to the explicit `if let hoverArea {
removeTrackingArea(hoverArea) }` guard in source; without it, repeated
calls to `updateTrackingAreas()` — which AppKit can invoke whenever the
view's geometry changes — would accumulate duplicate, stale-rect tracking
areas. (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: The disabled (not-enabled) case is left unaddressed in this
recipe rather than described as suppressing the pointing-hand cursor.
**Rationale**: None of the source's five overridden methods reads the
enabled state, so no behavior actually differs between an enabled and a
disabled button. This is recorded in States as a plain fact about
disabled-state cursor behavior, rather than silently normalized to the
idealized behavior a reader might expect. (Applies to the AppKit
implementation.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |

`keyboard-navigable` and `screen-reader-support` pass because this
component overrides no keyboard, focus, or accessibility method, leaving
the platform's default button's own compliant behavior intact.
`native-controls-preference` passes because the whole implementation is
the platform's own system pointing-hand and arrow cursors, with no custom
cursor image.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names and folded the unobservable super-call requirement into tracking-area-replacement; softened the unverified SwiftUI/Compose key-window claims and added the macOS 15 `.pointerStyle(.link)` note; added Apple doc references and linked them in Overview; documented the exit-into-a-cursor-owning-sibling edge case; sharpened the tracking-area-replacement test vector's owner/option assertion and dropped the unobservable super-call-order vector; prescribed a single WinUI 3 `ProtectedCursor` approach; cleaned up the Compliance table (removed the not-applicable touch-target-size and string-externalization rows per the compliance catalog). |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/controls/. |
