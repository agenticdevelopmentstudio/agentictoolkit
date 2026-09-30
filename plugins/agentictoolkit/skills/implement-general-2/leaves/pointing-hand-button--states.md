<!-- leaf: implement-general-2/pointing-hand-button--states · source: pointing-hand-button.md -->

# Pointing Hand Button

## States

| State | Appearance change |
|-------|------------------|
| Default | Cursor is `NSCursor.arrow` (the system default) until the pointer enters `bounds`; `PointingHandButton` applies no other styling of its own outside of cursor management. |
| Pressed | Not styled by `PointingHandButton`; the source overrides none of `NSButton`'s press-handling, so the native bezel press feedback applies unmodified. |
| Disabled | Not implemented: none of the five overridden methods reads `isEnabled`, so `resetCursorRects()` and the mouse-entered/moved handlers set `NSCursor.pointingHand` unconditionally, even on a disabled button that cannot be clicked. |
| Focused | Not styled by `PointingHandButton`; no focus-ring override appears in source, so `NSButton`'s native focus appearance applies unmodified. |
| Loading | Not applicable: `PointingHandButton` performs no asynchronous work and defines no loading state. |
