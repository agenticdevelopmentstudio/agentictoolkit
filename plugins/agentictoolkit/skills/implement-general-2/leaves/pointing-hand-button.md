<!-- leaf: implement-general-2/pointing-hand-button · source: pointing-hand-button.md -->

**Rules** (cite as `implement-general-2/pointing-hand-button#<slug>`):

- `cursor-rect` MUST
- `tracking-area-replacement` MUST
- `always-active-tracking` MUST
- `enter-cursor` MUST
- `move-cursor` MUST
- `exit-cursor` MUST
- `minimum-tap-target` MUST — PointingHandButton sets no controlSize, width, or height of its own, so its click target is whatever NSButton's …

# Pointing Hand Button

## Overview

`PointingHandButton` is an AppKit `NSButton` subclass (`packages/apple/AgenticToolkit/CoreUI/PointingHandButton.swift`) that shows the pointing-hand cursor over itself whenever the pointer is inside its bounds, whether or not its window is the key window. Per the source's own doc comment, [`resetCursorRects()`](https://developer.apple.com/documentation/appkit/nsview/resetcursorrects%28%29)/cursor rects alone are not enough for the windows this toolkit puts on screen: a floating panel beside the terminal the user is typing into is not key, and AppKit honours cursor rects only in the key window, so the one clickable thing in an unfocused list would otherwise look like the surrounding text. `PointingHandButton` combines the ordinary cursor-rect override with an `.activeAlways` [`NSTrackingArea`](https://developer.apple.com/documentation/appkit/nstrackingarea) that sets the [`NSCursor`](https://developer.apple.com/documentation/appkit/nscursor) directly from mouse-entered/moved/exited callbacks, covering the non-key case, while the cursor rect still covers the ordinary case where AppKit resets the cursor on the way out.

## Behavioral Requirements

- **cursor-rect**: The component MUST add a cursor rect covering its full `bounds` with the `NSCursor.pointingHand` cursor from `resetCursorRects()`.
- **tracking-area-replacement**: WHEN `updateTrackingAreas()` is called, the component MUST call `super.updateTrackingAreas()` first, and, if a previously registered tracking area exists, MUST remove it before adding the new one.
- **always-active-tracking**: WHEN `updateTrackingAreas()` is called, the component MUST register a new `NSTrackingArea` covering its full `bounds`, owned by itself, with options `.mouseEnteredAndExited`, `.mouseMoved`, and `.activeAlways`, so tracking remains active whether or not the button's window is key.
- **enter-cursor**: WHEN `mouseEntered(with:)` is invoked, the component MUST set the current cursor to `NSCursor.pointingHand`.
- **move-cursor**: WHEN `mouseMoved(with:)` is invoked, the component MUST set the current cursor to `NSCursor.pointingHand`.
- **exit-cursor**: WHEN `mouseExited(with:)` is invoked, the component MUST set the current cursor to `NSCursor.arrow`.

## Appearance

- **Corner radius**: Not set by `PointingHandButton`; governed entirely by `NSButton`'s default bezel style — no `bezelStyle`, `isBordered`, or layer customization appears in source.
- **Padding**: Not set; `PointingHandButton` applies no internal padding of its own.
- **Font**: Not set; `font` is never assigned, so `NSButton`'s default control font applies unmodified.
- **Background**: Not set; `PointingHandButton` performs no drawing or layer coloring of its own.
- **Foreground/Text**: Not set; no title-color or `attributedTitle` customization appears in source.
- **Border**: Not set; no border or bezel customization appears in source.
- **Shadow**: Not set; no shadow customization appears in source.
- **Min/Max size**: Not set; the class adds no size constraints — `bounds` is read wherever it appears (cursor rect, tracking area) but never written.

## Accessibility

- **Role**: Not set by `PointingHandButton`; inherited from `NSButton` — no accessibility-role override appears in source.
- **Label**: Not set by `PointingHandButton`; the accessible name follows `NSButton`'s own title, which this class never reads or writes.
- **Announce state changes**: Not applicable: `PointingHandButton` introduces no state of its own beyond the standard `NSButton` states (see States); the one behavior it does add — cursor shape on hover — is not a state AppKit's accessibility APIs announce.
- **Keyboard navigation**: Inherited from `NSButton` unmodified — `PointingHandButton` overrides no key-handling, focus, or responder-chain method, so Tab/Shift-Tab focus movement and Space/Return activation follow `NSButton`'s native behavior.
- **Minimum tap target**: `PointingHandButton` sets no `controlSize`, width, or height of its own, so its click target is whatever `NSButton`'s regular-size system bezel computes for its title. macOS is a pointer-driven platform, not a touch-driven one, so no minimum touch-target size applies here (see Compliance). Ports to touch platforms MUST give the equivalent control at least the platform minimum (44×44 pt on iOS, 48×48 dp on Android, 40×40 epx on WinUI 3).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `PointingHandButton` applies no animation or transition; cursor changes are instantaneous system cursor swaps, not motion. |
| Increase Contrast | Not applicable: `PointingHandButton` sets no custom colors of its own; the pointing-hand and arrow cursor images are the system's own imagery, unaffected by this component. |
| Differentiate Without Color | Not applicable: `PointingHandButton` conveys no state through color; its one signal is the system pointing-hand cursor shape, which is already a non-color affordance. |

## Privacy

- **Data collected**: None. `PointingHandButton` holds only a private `NSTrackingArea` reference; it collects no data.
- **Storage**: N/A — no persistence; state lives only in memory for the button's lifetime.
- **Transmission**: N/A — `PointingHandButton` performs no network or IPC calls.
- **Retention**: N/A — nothing is retained beyond the button's lifetime.

## Platform Notes

- **SwiftUI**: There is no direct `NSButton`-subclassing counterpart. On macOS 15+, prefer [`.pointerStyle(.link)`](https://developer.apple.com/documentation/swiftui/view/pointerstyle%28_:%29) on a `Button` — SwiftUI's native pointing-hand affordance. On earlier macOS targets, apply `.onHover { isHovering in if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }` instead; verify in a non-key panel that the hover callback still fires there, since SwiftUI's documentation does not state whether `onHover` depends on key-window status the way `resetCursorRects()` does.
- **Compose**: On Compose for Desktop, apply `Modifier.pointerHoverIcon(PointerIcon.Hand)` to the composable; verify in a non-key panel that the pointer icon still applies there, since Compose Desktop's documentation does not state whether pointer-icon handling depends on window focus the way AppKit's cursor rects do.
- **React/Web**: Set CSS `cursor: pointer` on the element. Browsers already display the pointer cursor over an element in any window, focused or not, so there is no equivalent to the source's key-window workaround to port.
- **AppKit / UIKit (source)**: `PointingHandButton.swift` (`packages/apple/AgenticToolkit/CoreUI/PointingHandButton.swift`) is macOS-only (`import AppKit`); there is no iOS/UIKit counterpart, since UIKit has no cursor-rect or `NSCursor` concept — cursors do not apply to a touch interface. The class subclasses `NSButton` and layers an `.activeAlways` `NSTrackingArea` (`mouseEntered`/`mouseMoved`/`mouseExited`) on top of the ordinary `resetCursorRects()` override, specifically to also cover floating, non-key panels that `resetCursorRects()` alone does not reach.
- **WinUI 3**: Subclass `Button` and set `ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.Hand)` in the constructor. WinUI applies and restores the protected cursor automatically as the pointer enters and exits the control, so no `PointerEntered`/`PointerExited` handlers are needed. `ProtectedCursor` is `protected`, so this must be set from within a `Button` subclass, not from a containing element — a WinUI 3 port needs only this one constructor assignment, not a second, always-active tracking mechanism.

## Design Decisions

**Decision**: The pointing-hand cursor is set from both `resetCursorRects()` and an `.activeAlways` `NSTrackingArea`'s mouse-entered/moved/exited handlers, rather than from `resetCursorRects()` alone.
**Rationale**: Per the source's own doc comment, cursor rects are honored by AppKit only in the key window, but this toolkit places clickable controls in windows that are not key (a floating panel beside the terminal the user is typing into); the `.activeAlways` tracking area covers that case, "and the cursor rect still covers the ordinary one, where AppKit resets the cursor for us on the way out."
**Approved**: pending

**Decision**: `updateTrackingAreas()` removes any existing `hoverArea` before adding a new one, rather than leaving prior tracking areas registered.
**Rationale**: Traceable to the explicit `if let hoverArea { removeTrackingArea(hoverArea) }` guard in source; without it, repeated calls to `updateTrackingAreas()` — which AppKit can invoke whenever the view's geometry changes — would accumulate duplicate, stale-rect tracking areas.
**Approved**: pending

**Decision**: The disabled (`isEnabled == false`) case is left unaddressed in this recipe rather than described as suppressing the pointing-hand cursor.
**Rationale**: None of the source's five overridden methods reads `isEnabled`, so no behavior actually differs between an enabled and a disabled button. This is recorded in States as a plain fact about disabled-state cursor behavior, rather than silently normalized to the idealized behavior a reader might expect.
**Approved**: pending
