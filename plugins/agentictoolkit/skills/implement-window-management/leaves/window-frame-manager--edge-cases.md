<!-- leaf: implement-window-management/window-frame-manager--edge-cases · source: window-management-window-frame-manager.md -->

# WindowFrameManager

**Rules** (cite as `implement-window-management/window-frame-manager--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An unregistered id MUST restore to the geometric center and return false; save and visibility writes for it MUST be …
- `no-placements-left-after-decode` MUST — Stored state with empty placements and no legacy record MUST restore to the spec's default frame and return false …
- `boundary-values` MUST — A window exactly equidistant from both edges MUST keep its start anchor; a window filling an axis MUST report relative …
- `minimum-larger-than-the-screen` MUST — Every sizing path MUST keep minSize and overhang; contentHuggingFrame leaves the window flush top-left while …
- `out-of-range-stored-fractions` MUST — relativeX / relativeY are not clamped on restore; a hand-edited value outside 0...1 is placed off the travel range and …
- `stale-absolute-offset` MUST — A placement matched non-exactly (resolution change, name-only or main-only match) MUST NOT replay the absolute offset; …
- `screen-not-matched-at-all` MUST — A placement whose fingerprint matches no current screen MUST resolve on the main screen, then the first screen, via its …
- `display-change-delivered-after-a-move` MUST — A windowDidMove that arrives before didChangeScreenParameters MUST be filed under the live set because save calls …
- `placements-of-aged-out-sets` MUST — A placement whose set is unknown to ScreenManager and older than maxSetAge MUST be dropped at the next save of that …
- `duplicate-registration` MUST — Registering the same id twice MUST keep only the latest spec (MUST).
- `hidden-windows-on-screen-change` MUST — Loaded but hidden managed windows MUST be repositioned without animation (MUST).
- `windows-not-tagged` MUST — Windows whose identifier lacks the wm_ prefix, or whose id has no registered spec, MUST be ignored by the screen-change …
- `concurrent-access` MUST — All operations are serialised on the main actor, so no two calls interleave. Screen-change repositioning triggers …

## Edge Cases

- **Null and empty input**: An unregistered id MUST restore to the geometric center and return `false`; save and visibility writes for it MUST be no-ops. An empty screen list MUST make restore center the window and return `false`, make the screen-change handler do nothing, and make save fall back to AppKit's window screen or main screen (and write nothing if both are nil). An empty or unrecognised stored blob MUST decode to empty placements (MUST).
- **No placements left after decode**: Stored state with empty placements and no legacy record MUST restore to the spec's default frame and return `false` (MUST).
- **Boundary values**: A window exactly equidistant from both edges MUST keep its `start` anchor; a window filling an axis MUST report relative position `0.5` and proportional position `0.5` on that axis; resolutions within 1 point of the saved value MUST count as `exact` (MUST).
- **Minimum larger than the screen**: Every sizing path MUST keep `minSize` and overhang; `contentHuggingFrame` leaves the window flush top-left while `validateFrame` leaves it flush left and bottom, because of their different push orders (MUST, documented quirk).
- **Out-of-range stored fractions**: `relativeX` / `relativeY` are not clamped on restore; a hand-edited value outside 0...1 is placed off the travel range and then pulled on screen by `validateFrame` (MUST, as implemented).
- **Stale absolute offset**: A placement matched non-exactly (resolution change, name-only or main-only match) MUST NOT replay the absolute offset; it MUST use the relative position (MUST).
- **Screen not matched at all**: A placement whose fingerprint matches no current screen MUST resolve on the main screen, then the first screen, via its relative position (MUST).
- **Display change delivered after a move**: A `windowDidMove` that arrives before `didChangeScreenParameters` MUST be filed under the live set because save calls `touchCurrentSet()` first (MUST; `testMoveDuringUndeliveredScreenChangeDoesNotClobberTheDockedPlacement`).
- **Placements of aged-out sets**: A placement whose set is unknown to `ScreenManager` and older than `maxSetAge` MUST be dropped at the next save of that window; one saved more recently MUST survive (MUST).
- **Duplicate registration**: Registering the same id twice MUST keep only the latest spec (MUST).
- **Hidden windows on screen change**: Loaded but hidden managed windows MUST be repositioned without animation (MUST).
- **Windows not tagged**: Windows whose identifier lacks the `wm_` prefix, or whose id has no registered spec, MUST be ignored by the screen-change handler (MUST).
- **Concurrent access**: All operations are serialised on the main actor, so no two calls interleave. Screen-change repositioning triggers delegate-driven `saveFrame` calls synchronously within the same main-actor turn (MUST).
- **Cross-process writers**: A second process writing the same id's state is outside the contract; the cache would not see its writes (per sole-writer-precondition).
- **Error states**: Storage load and save failures are not reported by the protocol (see the open question on storage-failure-signal). A missing spec on restore is logged at warning level.
- **Offline or disconnected state**: Not applicable; the component performs no network I/O.
- **Cancellation and timeouts**: Not applicable; every operation is synchronous and has no timeout or cancellation path.
