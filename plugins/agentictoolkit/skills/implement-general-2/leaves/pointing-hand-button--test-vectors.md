<!-- leaf: implement-general-2/pointing-hand-button--test-vectors · source: pointing-hand-button.md -->

# Pointing Hand Button

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pointing-hand-button-001 | cursor-rect | Call `resetCursorRects()` on a `PointingHandButton` laid out at bounds (0, 0, 100, 30) | A cursor rect covering (0, 0, 100, 30) is registered with cursor `NSCursor.pointingHand` |
| pointing-hand-button-003 | tracking-area-replacement | Call `updateTrackingAreas()` twice in succession on the same instance | Among the button's registered tracking areas, exactly one has `owner === button` and `options` containing `.activeAlways` — the second call replaced the first instead of adding a duplicate |
| pointing-hand-button-004 | always-active-tracking | Call `updateTrackingAreas()` on a button whose window is not key | A registered `NSTrackingArea` has `rect == bounds`, `owner === button`, and `options` containing `.mouseEnteredAndExited`, `.mouseMoved`, and `.activeAlways` |
| pointing-hand-button-005 | enter-cursor | Invoke `mouseEntered(with:)` with a synthetic `NSEvent` | The current system cursor becomes `NSCursor.pointingHand` |
| pointing-hand-button-006 | move-cursor | Invoke `mouseMoved(with:)` with a synthetic `NSEvent` | The current system cursor becomes `NSCursor.pointingHand` |
| pointing-hand-button-007 | exit-cursor | Invoke `mouseExited(with:)` with a synthetic `NSEvent` | The current system cursor becomes `NSCursor.arrow` |
