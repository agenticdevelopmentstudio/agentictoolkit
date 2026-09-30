<!-- leaf: implement-general-2/pointing-hand-button--edge-cases · source: pointing-hand-button.md -->

# Pointing Hand Button

## Edge Cases

- **Null/empty input**: Not applicable — `PointingHandButton` defines no initializer, property, or configuration input of its own; the only inputs are the `NSEvent` arguments AppKit supplies to `mouseEntered`/`mouseMoved`/`mouseExited`, which are never nil.
- **Boundary values**: `PointingHandButton` passes `bounds` unmodified to both `addCursorRect` and `NSTrackingArea`, with no minimum-size guard in source. A zero-size or not-yet-laid-out `bounds` is passed through as-is — the resulting cursor-rect/tracking-area behavior for a zero-area rect is AppKit's own, not something this class special-cases.
- **Concurrent access**: Not applicable — `resetCursorRects()`, `updateTrackingAreas()`, and the mouse-event callbacks are all AppKit view-lifecycle methods that execute on the main thread only; the single `hoverArea` property is read and written exclusively from those main-thread callbacks.
- **Error states**: Not applicable — `PointingHandButton` has no dependency on network, database, or file-system access; cursor and tracking-area management cannot fail in the way this source uses them.
- **Offline/disconnected state**: Not applicable — `PointingHandButton` performs no networking.
- **Non-key window with pointer inside bounds**: This is the case the class exists to handle. Because tracking uses `.activeAlways` rather than `.activeInKeyWindow` (per the source's own comment), `mouseEntered`/`mouseMoved`/`mouseExited` continue to fire even while the button's window is not key, so the pointing-hand cursor still appears — unlike a plain `NSButton` relying on `resetCursorRects()` alone, whose cursor rect AppKit only honors in the key window.
- **Exit into a cursor-owning sibling**: `mouseExited(with:)` unconditionally calls `NSCursor.arrow.set()` (see conformance vector pointing-hand-button-007), with no check on what the pointer moved onto. If the pointer exits `PointingHandButton`'s bounds directly into a sibling view that manages its own cursor (for example, a text view showing the I-beam cursor), this handler's `.arrow` push can momentarily overwrite that sibling's cursor before the sibling's own tracking area or cursor rect re-asserts it. This is a known limitation of the source's unconditional `.arrow` reset, not a coordinated hand-off between views.
