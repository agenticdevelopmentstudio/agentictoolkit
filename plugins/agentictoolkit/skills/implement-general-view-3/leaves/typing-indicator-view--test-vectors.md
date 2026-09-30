<!-- leaf: implement-general-view-3/typing-indicator-view--test-vectors · source: typing-indicator-view.md -->

# TypingIndicatorView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| typing-indicator-001 | three-dot-layout | Inspect a constructed instance's view tree | The container holds a horizontal row of exactly 3 dot elements, with 4pt spacing between each |
| typing-indicator-002 | pill-container-shape | Any constructed instance | The container's own corner radius equals 12pt; its width and height resolve to 48pt and 28pt respectively |
| typing-indicator-003 | stack-centered-in-container | Any constructed instance placed in a superview | The row of dots is centered within the container on both the horizontal and vertical axes |
| typing-indicator-004 | dot-size-and-shape | Any dot element | Width and height both equal 7pt; corner radius equals 3.5pt |
| typing-indicator-005 | container-fill-tracks-theme | Construct under theme A, then switch the active theme to theme B | Container background color equals theme A's `secondaryText` at 0.08 alpha immediately at construction, then updates to theme B's equivalent color after the switch, with no view re-creation |
| typing-indicator-006 | dot-color-tracks-theme | Construct under theme A, then switch the active theme to theme B | Every dot's background color equals theme A's `secondaryText` at full alpha immediately at construction, then updates to theme B's equivalent color after the switch |
| typing-indicator-007 | start-resets-dot-alpha | Call `startAnimating()` on a freshly constructed instance | All three dots' opacity equal 0.3 synchronously, before the first tick |
| typing-indicator-008 | start-schedules-repeating-timer | Call `startAnimating()`, then allow exactly one tick to fire | Dot 0 is the dot animated to opacity 1.0 on that first tick, and the interval from the call to that tick, and between each subsequent tick, is 0.35 seconds |
| typing-indicator-009 | single-dot-highlighted-per-tick | `startAnimating()`, then allow one tick | Exactly one dot animates opacity to 1.0 over 0.2 seconds while the other two animate to 0.3 over the same 0.2 seconds |
| typing-indicator-010 | single-dot-highlighted-per-tick | `startAnimating()`, then allow three consecutive ticks | The highlighted dot index advances 0 → 1 → 2 → 0, wrapping modulo 3 |
| typing-indicator-011 | timer-invalidated-on-removal | `startAnimating()`, then remove the view from its superview, then wait longer than one tick interval | No dot's opacity changes after removal; the highlight animation does not continue |
| typing-indicator-012 | start-schedules-repeating-timer, timer-invalidated-on-removal | Call `startAnimating()` twice in a row without an intervening removal from the view hierarchy | The second call replaces the animation timer without invalidating the first one, which remains scheduled independently; both timers then drive the tick against the shared highlight state, roughly doubling the effective tick rate — well-defined by the source, not a crash (see Edge Cases) |
