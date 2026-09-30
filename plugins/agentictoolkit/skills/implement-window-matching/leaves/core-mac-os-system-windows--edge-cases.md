<!-- leaf: implement-window-matching/core-mac-os-system-windows--edge-cases · source: window-matching-core-mac-os-system-windows.md -->

# SystemWindows Engine

**Rules** (cite as `implement-window-matching/core-mac-os-system-windows--edge-cases#<slug>`):

- `window-list-query-fails` MUST — Both list operations (MUST) return []; control operations then throw windowNotFound for every id.
- `record-missing-required-fields` MUST — The record (MUST) is skipped by compactMap; it never appears in a list and cannot be controlled.
- `accessibility-not-trusted` MUST — Listing (MUST) still succeeds with CoreGraphics titles; titles CoreGraphics omits (no Screen Recording permission) stay …
- `screen-recording-granted` MUST — CoreGraphics returns titles, so backfill (MUST) makes near-zero AX calls.
- `minimized-or-off-screen-window-in-a-multi-window-app` MUST — Its CG bounds differ from its AX geometry, so backfill (MUST) leaves its title empty unless the app has only one AX …
- `sheet-over-its-document` MUST — Two AX windows share one frame, so backfill (MUST) leaves the title empty, and control matching (MUST) picks the …
- `two-windows-with-identical-title-and-frame` MUST — Matching (MUST) returns the first; the public AX API exposes no window id, per the bestMatch comment.
- `window-id-recycled-between-list-and-control` MUST — Resolution (MUST) targets whatever window now holds the id; nothing checks identity beyond the id and the score.
- `window-closes-between-resolution-and-write` MUST — The write MUST fail and surface as attributeSetFailed with the raw AX code.
- `non-resizable-or-non-movable-window` MUST — The failing write MUST surface as attributeSetFailed; for setFrame, a size failure after a successful move leaves the …
- `parked-window-with-no-main-screen` MUST — focus MUST skip the unpark and raise the window where it is.
- `activation-refused-by-the-system` MUST — focus (MUST) throw activationFailed after the window has already been raised within its app.
- `app-launched-during-observation` MUST — Windows that appear within the 1.0-second launch delay MUST be absorbed by the refresh and never reported through …
- `app-that-does-not-support-ax` MUST — Observer creation fails and the app MUST be skipped silently; its windows are never reported as created or …
- `destroy-event-for-one-app` MUST — The diff (MUST) report every vanished id across all apps, including windows of apps with no AX observer.
- `title-change-while-pid-unreadable` MUST — Matching (MUST) consider every app's windows and report the first geometric match.
- `window-moved-before-the-title-event-is-handled` MUST — No geometry match MUST mean the title change is dropped.
- `unresponsive-target-app` MUST — AX calls MUST block the caller up to the system's default AX messaging timeout; the engine sets no timeout, …
- `stop-during-pending-delayed-work` MUST — The 1.0 s and 0.5 s blocks MUST check isObserving and do nothing after stopObserving(); a restart within the delay lets …
- `empty-inputs` MUST — A zero point or zero size MUST be sent to the target window unvalidated; the target app decides the outcome and any …

## Edge Cases

- **Window-list query fails**: Both list operations (MUST) return `[]`; control operations then throw `windowNotFound` for every id.
- **Record missing required fields**: The record (MUST) is skipped by `compactMap`; it never appears in a list and cannot be controlled.
- **Accessibility not trusted**: Listing (MUST) still succeeds with CoreGraphics titles; titles CoreGraphics omits (no Screen Recording permission) stay empty; every control operation throws `accessibilityNotAvailable`.
- **Screen Recording granted**: CoreGraphics returns titles, so backfill (MUST) makes near-zero AX calls.
- **Minimized or off-screen window in a multi-window app**: Its CG bounds differ from its AX geometry, so backfill (MUST) leaves its title empty unless the app has only one AX window.
- **Sheet over its document**: Two AX windows share one frame, so backfill (MUST) leaves the title empty, and control matching (MUST) picks the earliest AX window when titles also tie.
- **Two windows with identical title and frame**: Matching (MUST) returns the first; the public AX API exposes no window id, per the `bestMatch` comment.
- **Window id recycled between list and control**: Resolution (MUST) targets whatever window now holds the id; nothing checks identity beyond the id and the score.
- **Window closes between resolution and write**: The write MUST fail and surface as `attributeSetFailed` with the raw AX code.
- **Non-resizable or non-movable window**: The failing write MUST surface as `attributeSetFailed`; for `setFrame`, a size failure after a successful move leaves the window moved.
- **Parked window with no main screen**: `focus` MUST skip the unpark and raise the window where it is.
- **Unpark write fails**: See the open question on focus-unpark-failure.
- **Activation refused by the system**: `focus` (MUST) throw `activationFailed` after the window has already been raised within its app.
- **App launched during observation**: Windows that appear within the 1.0-second launch delay MUST be absorbed by the refresh and never reported through `windowCreated`.
- **App that does not support AX**: Observer creation fails and the app MUST be skipped silently; its windows are never reported as created or title-changed, though their destruction can still be reported when another app's destroy event triggers the diff.
- **AX registration errors**: See the open question on observer-registration-errors.
- **Destroy event for one app**: The diff (MUST) report every vanished id across all apps, including windows of apps with no AX observer.
- **Title change while PID unreadable**: Matching (MUST) consider every app's windows and report the first geometric match.
- **Window moved before the title event is handled**: No geometry match MUST mean the title change is dropped.
- **Unresponsive target app**: AX calls MUST block the caller up to the system's default AX messaging timeout; the engine sets no timeout, cancellation or retry.
- **Concurrent access**: The observer is confined to the main thread by its documented invariant; `SystemWindowManager` is non-`Sendable` and stateless, so concurrent list calls from separate instances do not share state.
- **Stop during pending delayed work**: The 1.0 s and 0.5 s blocks MUST check `isObserving` and do nothing after `stopObserving()`; a restart within the delay lets them run against the new session.
- **Offline / network**: Not applicable: the engine performs no network I/O.
- **Empty inputs**: A zero point or zero size MUST be sent to the target window unvalidated; the target app decides the outcome and any rejection surfaces as `attributeSetFailed`.
