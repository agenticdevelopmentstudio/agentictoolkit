<!-- leaf: implement-window-matching/core-mac-os-system-windows--part-2 · source: window-matching-core-mac-os-system-windows.md -->

# SystemWindows Engine — continued (part 2)

**Rules** (cite as `implement-window-matching/core-mac-os-system-windows--part-2#<slug>`):

- `window-info-value` MUST
- `window-info-with-title` MUST
- `parse-required-fields` MUST
- `parse-optional-defaults` MUST
- `parse-bounds-defaults` MUST
- `parse-display-from-center` MUST
- `display-fallback` MUST
- `parse-no-policy` MUST
- `list-on-screen` MUST
- `list-all` MUST
- `list-failure-empty` MUST
- `policy-layer` MUST
- `policy-excluded-apps` MUST
- `policy-zero-size` MUST
- `list-order` MUST
- `list-no-permission-needed` MUST
- `backfill-trigger` MUST
- `backfill-skip` MUST
- `backfill-batch-per-pid` MUST
- `backfill-single-window-app` MUST
- `backfill-unique-frame` MUST
- `backfill-ambiguous` MUST
- `backfill-empty-result` MUST
- `backfill-read-only` MUST
- `ax-element-lookup` MUST
- `ax-element-unknown-id` MUST
- `ax-element-no-ax-windows` MUST
- `match-title-score` MUST
- `match-empty-title-score` MUST
- `match-position-score` MUST
- `match-size-score` MUST
- `match-unreadable-attribute` MUST
- `match-winner` MUST
- `match-zero-rejected` MUST
- `ax-windows-for-pid` MUST
- `attr-read-nil` MUST
- `attr-write-result` MUST
- `resolve-not-found` MUST
- `resolve-no-ax` MUST
- `move` MUST
- `resize` MUST
- `set-frame-order` MUST
- `set-frame-partial` MUST
- `set-frame-stops` MUST
- `focus-unpark` MUST
- `focus-raise` MUST
- `focus-activate` MUST
- `axelement-public` MUST
- `no-permission-check` MUST
- `horizontal-visibility` MUST
- `error-descriptions` MUST
- `permission-is-granted` MUST
- `permission-request` MUST
- `permission-request-user-initiated` SHOULD

## Behavioral Requirements

### Data shape

- **window-info-value**: `SystemWindowInfo` MUST be an immutable value type that is `Codable`, `Identifiable` (by `id`), `Equatable` and `Sendable`.
- **window-info-with-title**: `withTitle(_:)` MUST return a copy whose every field except `title` equals the original.

### Parsing a window-list record

- **parse-required-fields**: `SystemWindowManager.windowInfo(from:)` MUST return nil when any of window number (`UInt32`), owner PID (`Int32`), layer (`Int32`) or bounds dictionary is missing or of the wrong type.
- **parse-optional-defaults**: A missing owner name MUST become `""`, a missing window name MUST become `""`, and a missing on-screen flag MUST become `false`.
- **parse-bounds-defaults**: Each missing bounds key (`X`, `Y`, `Width`, `Height`) MUST default to 0.
- **parse-display-from-center**: `display` MUST be the display containing the frame's center point, resolved by `displayForPoint(_:)`.
- **display-fallback**: `displayForPoint(_:)` MUST return the main display id when no display contains the point or the display query fails.
- **parse-no-policy**: `windowInfo(from:)` MUST NOT filter by layer, app or size; policy is applied only by enumeration.

### Enumeration

- **list-on-screen**: `listWindows()` MUST enumerate only on-screen windows, excluding desktop elements.
- **list-all**: `listAllWindows()` MUST enumerate all windows including off-screen (minimized or parked) ones, excluding desktop elements.
- **list-failure-empty**: Both list operations MUST return `[]` when the window-list query returns nothing; the failure is not distinguishable from "no windows".
- **policy-layer**: Enumeration MUST drop every window whose `layer` is not 0.
- **policy-excluded-apps**: Enumeration MUST drop every window whose `app` is in `excludedApps`: "Window Server", "WindowManager", "Dock", "Control Center", "Notification Center", "SystemUIServer".
- **policy-zero-size**: Enumeration MUST drop every window whose frame width or height is not greater than 0.
- **list-order**: Enumeration MUST preserve the order in which the system window list returned the records.
- **list-no-permission-needed**: Enumeration MUST succeed without Accessibility permission; only title backfill depends on it.

### Title backfill

- **backfill-trigger**: After policy filtering, each list operation MUST attempt to backfill titles only for windows whose `title` is empty.
- **backfill-skip**: When no window has an empty title, the list MUST be returned unchanged with no Accessibility calls.
- **backfill-batch-per-pid**: The engine MUST enumerate the AX windows of each owning PID that needs a title exactly once per list call.
- **backfill-single-window-app**: When the owning app exposes exactly one AX window, that window's AX title MUST be used regardless of frame.
- **backfill-unique-frame**: When the app exposes more than one AX window, the title MUST come from the single AX window whose position and size each lie within 2 points (strictly less than 2) of the window's frame.
- **backfill-ambiguous**: When zero or more than one AX window matches the frame, the title MUST stay empty.
- **backfill-empty-result**: An AX title that is nil or empty MUST leave the title empty.
- **backfill-read-only**: Backfill MUST use AX attribute reads only (no actions, no observers), so list operations MAY run on a background queue, as the source's `backfillTitles` comment declares.

### Window-id to AX element matching

- **ax-element-lookup**: `SystemWindowAXHelper.axElement(for:windowInfo:)` MUST use the supplied `SystemWindowInfo` when given, and otherwise look the id up in the full window list (all windows, excluding desktop elements) using the same parser as enumeration, without enumeration policy or backfill.
- **ax-element-unknown-id**: The lookup MUST return nil when the id is not in the window list.
- **ax-element-no-ax-windows**: The lookup MUST return nil when the owning app's AX windows attribute cannot be read.
- **match-title-score**: A candidate MUST score +10 when the target title is non-empty and equals the candidate's AX title exactly.
- **match-empty-title-score**: A candidate MUST score +1 when both the target title and the candidate's AX title are empty.
- **match-position-score**: A candidate MUST score +5 when both its AX position coordinates lie within 2 points (strictly less than 2) of the target frame origin.
- **match-size-score**: A candidate MUST score +3 when both its AX width and height lie within 2 points (strictly less than 2) of the target frame size.
- **match-unreadable-attribute**: An AX attribute that cannot be read MUST contribute 0 to the score.
- **match-winner**: The candidate with the strictly highest score MUST win; on a tie the earliest candidate in the app's AX window order MUST win.
- **match-zero-rejected**: A candidate with score 0 MUST NOT be selected; when every candidate scores 0 the lookup MUST return nil.
- **ax-windows-for-pid**: `axWindows(forPID:)` MUST return the app's AX windows, or `[]` when the attribute cannot be read.

### AX attribute helpers

- **attr-read-nil**: `title(of:)`, `position(of:)` and `size(of:)` MUST return nil when the attribute read fails or the value is not of the expected type.
- **attr-write-result**: `setPosition(of:to:)`, `setSize(of:to:)` and `raise(_:)` MUST return the raw AX result code, with `.failure` when the AX value cannot be created.

### Control operations

- **resolve-not-found**: Every control operation MUST throw `SystemWindowControlError.windowNotFound(windowID:)` when the id is absent from `listAllWindows()` (after enumeration policy).
- **resolve-no-ax**: Every control operation MUST throw `SystemWindowControlError.accessibilityNotAvailable(app:pid:)` when the window is listed but no AX element matches, whatever the underlying reason (permission missing, attribute unreadable, no scoring candidate).
- **move**: `move(windowID:to:)` MUST set the AX position to the point and throw `attributeSetFailed(attribute:axError:)` with the position attribute name and the raw AX code when the write fails.
- **resize**: `resize(windowID:to:)` MUST set the AX size and throw `attributeSetFailed` with the size attribute name and the raw AX code when the write fails.
- **set-frame-order**: `setFrame(windowID:to:)` MUST set position first and size second, from one AX element resolution.
- **set-frame-partial**: When the size write fails after a successful position write, `setFrame` MUST throw `attributeSetFailed` for the size attribute and MUST leave the window at its new position (no rollback).
- **set-frame-stops**: When the position write fails, `setFrame` MUST throw for the position attribute without attempting the size write.
- **focus-unpark**: `focus(windowID:)` MUST first move a window whose frame overlaps no screen horizontally to x = main screen visible-frame minX + 80, keeping its y, when a main screen exists.
- **focus-unpark-failure**: NEEDS REVIEW: Not implemented in source. `focus` discards the AX result of the unpark move, so a failed unpark lets focus raise a still-invisible window and return success with no signal; the owner of `SystemWindowManager` needs to decide whether that failure throws `attributeSetFailed`.
- **focus-raise**: `focus` MUST then perform the AX raise action and throw `attributeSetFailed` with the raise action name when it fails.
- **focus-activate**: `focus` MUST then activate the owning app and throw `activationFailed(app:pid:)` when no running app has the PID or activation returns false.
- **axelement-public**: `SystemWindowManager.axElement(for:)` MUST return the resolved element and its `SystemWindowInfo`, throwing the same resolution errors as the control operations.
- **no-permission-check**: The manager MUST NOT check or prompt for Accessibility permission; missing permission surfaces only as `accessibilityNotAvailable` or as empty backfilled titles.
- **horizontal-visibility**: `isOnScreenHorizontally(_:)` MUST return true exactly when the frame's X extent overlaps at least one screen's frame X extent (strict `maxX > minX` and `minX < maxX`); Y is never compared.

### Errors

- **error-descriptions**: Each `SystemWindowControlError` case MUST produce the description text given under Localization, interpolating its associated values.

### Permission helper

- **permission-is-granted**: `SystemAccessibilityPermission.isGranted` MUST report the current Accessibility trust without showing any system prompt.
- **permission-request**: `request()` MUST ask the system to show the Accessibility prompt and return the current trust state, which is false until the user grants trust and the process is re-evaluated.
- **permission-request-user-initiated**: Hosts SHOULD call `request()` only from user-initiated actions, per its doc comment, because it surfaces a system dialog and System Settings.

