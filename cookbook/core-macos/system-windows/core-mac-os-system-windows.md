---
id: fcd4bf3d-445d-4f01-99a2-ba6f71ce087b
title: SystemWindows Engine
domain: agentictoolkit://cookbook/core-macos/system-windows/core-mac-os-system-windows
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: macOS engine that enumerates other apps' windows, matches them to Accessibility
  elements, moves, resizes and focuses them, and observes window lifecycle.
platforms:
- swift
- macos
tags:
- window-management
- system-windows
- accessibility-api
- macos
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-windows/ui/window-explorer-view
references: []
approved-by: ''
approved-date: ''
---

# SystemWindows Engine

## Overview

The CoreMacOS `SystemWindows` engine lets a host app see and control the
windows of *other* applications on macOS. It is shared logic with no UI, made
of six source files:

- `SystemWindowControlling` — the protocol (list, move, resize, focus,
  set frame) that orchestration code depends on so it can be tested with a
  mock.
- `SystemWindowManager` — the real conformer. It enumerates windows with the
  CoreGraphics window list (no permission needed), applies an enumeration
  policy, backfills missing titles through Accessibility, and manipulates
  windows through Accessibility (`AXUIElement`).
- `SystemWindowAXHelper` — bridges a CoreGraphics window id to an
  `AXUIElement` by PID plus a title/position/size score, and wraps the AX
  attribute reads, writes and the raise action.
- `SystemWindowObserver` — watches app launch/terminate (NSWorkspace) and
  window created/destroyed/title-changed (per-app AX observers) and reports
  them to a `SystemWindowObserverDelegate`.
- `SystemWindowControlError` — the typed errors of the control operations.
- `SystemAccessibilityPermission` — the one place hosts check or prompt for
  Accessibility trust; the engine itself never checks it.

Windows are described by `SystemWindowInfo` (from `AgenticToolkitCore`):
`id` (CGWindowID, `UInt32`), `app`, `pid`, `title`, `frame` (global
top-left-origin coordinates), `display`, `isOnScreen`, `layer`, plus
`withTitle(_:)` which returns a copy with only the title replaced. Use the
engine for window-context switching, window explorers and any feature that
parks, restores or raises third-party windows.

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

### Observer lifecycle

- **observer-start-idempotent**: `startObserving()` MUST do nothing when already observing.
- **observer-start-snapshot**: `startObserving()` MUST snapshot known window ids per PID from `listAllWindows()` before subscribing.
- **observer-start-apps**: `startObserving()` MUST create one AX observer per running app that has a non-empty localized name and a regular activation policy.
- **observer-ax-subscriptions**: Each app observer MUST subscribe to window-created and focused-window-changed on the app element, and to element-destroyed and title-changed on each of the app's existing AX windows.
- **observer-one-per-pid**: The observer MUST NOT create a second AX observer for a PID that already has one.
- **observer-create-failure**: When AX observer creation fails for an app, the observer MUST skip that app silently.
- **observer-registration-errors**: NEEDS REVIEW: Not implemented in source. Every AX notification registration ignores its result code, so an app whose registrations fail (for example with Accessibility trust missing) is counted as monitored yet never reports window events; evidence needed is which registration errors the owner wants logged or surfaced.
- **observer-stop**: `stopObserving()` MUST do nothing when not observing; otherwise it MUST remove both workspace observers, remove every AX observer's run-loop source, clear all AX observers and clear the known-window snapshot.
- **observer-deinit**: Deallocating the observer MUST stop observation.
- **observer-refresh**: `refreshKnownWindows()` MUST replace the whole known-window snapshot with the ids from `listAllWindows()`, grouped by PID.
- **observer-delegate-weak**: The delegate MUST be held weakly; events with no delegate are dropped.

### Observer events

- **app-launched**: On an app launch with a non-nil localized name, the observer MUST, 1.0 second later and only if still observing, create an AX observer for the PID, refresh the snapshot, then call `appLaunched(appName:pid:)`.
- **app-launched-policy**: The launch path MUST NOT filter by activation policy or empty name, unlike `startObserving()`.
- **app-terminated**: On an app termination with a non-nil localized name, the observer MUST remove that PID's AX observer and snapshot entry, then call `appTerminated(appName:pid:)` synchronously.
- **window-created-baseline**: On a window-created notification the observer MUST subscribe the new window to destroyed and title-changed notifications and capture the baseline id set at once: the owning PID's known ids when the PID is readable, otherwise all known ids.
- **window-created-report**: 0.5 second later, only if still observing, the observer MUST list all windows, scope them to the PID when known, refresh the snapshot, and call `windowCreated(window:)` for each scoped window whose id is not in the baseline, in list order.
- **window-destroyed**: On an element-destroyed notification the observer MUST synchronously list all windows, refresh the snapshot, and call `windowDestroyed(windowID:)` for every previously known id no longer listed, across all apps.
- **title-changed-match**: On a title-changed notification the observer MUST read the element's title, position and size, and report `windowTitleChanged(windowID:newTitle:)` for the first listed window, scoped to the element's PID when readable, whose origin and size each lie within 2 points of the element's.
- **title-changed-drop**: When the title, position or size is unreadable, or no window matches, the title change MUST be dropped without a delegate call.
- **focused-window-changed**: On a focused-window-changed notification the observer MUST read the app's focused window and subscribe it to destroyed and title-changed notifications, relying on AX deduplication of repeated registrations.

### Concurrency

- **observer-main-confinement**: `SystemWindowObserver` MUST be used only on the main thread: it is declared `@unchecked Sendable` on the documented invariant that AX sources run on the main run loop, workspace observers use the main queue and delayed work hops through the main queue; callers of `startObserving()`, `stopObserving()` and `refreshKnownWindows()` MUST honor it.
- **manager-non-sendable**: `SystemWindowManager` is a public non-`Sendable` final class with no stored state, so the compiler keeps each instance in its isolation domain; list operations MAY run off the main thread, as `backfillTitles` documents.
- **helpers-stateless**: `SystemWindowAXHelper` and `SystemAccessibilityPermission` MUST hold no state; every call is independent.
- **no-timeouts**: Every operation MUST run synchronously with no AX messaging timeout of its own, no cancellation and no retry, so a call is bounded only by the system's default AX timeout.

### Side effects

- **side-effects**: Control operations MUST change only the targeted window's position, size, z-order and the owning app's activation; list operations and permission reads MUST have no side effect on other apps.
- **no-persistence**: The engine MUST NOT persist anything; the observer's snapshot lives only in memory.

## Appearance

Not applicable — this is a window enumeration, matching and control engine, not a visual component.

## States

Not applicable — this is a window enumeration, matching and control engine, not a visual component.

## Accessibility

Not applicable — this is a window enumeration, matching and control engine, not a visual component.

## Conformance Test Vectors

The source has no unit tests for these six files; `SystemWindowContextManagerTests.swift` exercises only a mock `SystemWindowControlling`. Every vector below is derived from the named function.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| system-windows-001 | parse-required-fields | Record with number 7, PID 100, bounds, but no layer key | `windowInfo(from:)` returns nil |
| system-windows-002 | parse-optional-defaults, parse-bounds-defaults | Record with number 7, PID 100, layer 0, bounds `{X: 10, Width: 300}`, no owner name, no window name, no on-screen flag | `app == ""`, `title == ""`, `isOnScreen == false`, frame (10, 0, 300, 0) |
| system-windows-003 | policy-layer | Records: layer 0 frame 100×100 app "Notes"; layer 25 same frame | List contains only the layer-0 window |
| system-windows-004 | policy-excluded-apps | Layer-0 100×100 windows owned by "Dock" and "Notes" | List contains only the "Notes" window |
| system-windows-005 | policy-zero-size | Layer-0 windows of "Notes" sized 0×50, 50×0, 50×50 | List contains only the 50×50 window |
| system-windows-006 | backfill-skip | Every listed window has a non-empty title | List returned unchanged; no AX window enumeration performed |
| system-windows-007 | backfill-single-window-app | Window titled "" at (0,0,500,400); app has one AX window titled "Doc" at (900,900) | Title becomes "Doc" |
| system-windows-008 | backfill-unique-frame | Window "" at (100,100,500,400); AX windows "A" at (101,100) 500×401 and "B" at (300,300) 200×200 | Title becomes "A" |
| system-windows-009 | backfill-ambiguous | Window "" at (100,100,500,400); two AX windows "A" and "B" both at (100,100) 500×400 | Title stays "" |
| system-windows-010 | backfill-unique-frame | Window "" at (100,100,500,400); AX windows at (102,100) 500×400 and (0,0) 10×10 | Title stays "" (a 2-point delta is not within tolerance) |
| system-windows-011 | match-title-score, match-winner | Target "Report" at (0,0,800,600); AX: W1 "Other" at (0,0) 800×600 (score 8), W2 "Report" at (500,500) 100×100 (score 10) | W2 selected |
| system-windows-012 | match-winner | Target "Report" at (0,0,800,600); AX: W1 and W2 both "Report" at (0,0) 800×600 | W1 selected |
| system-windows-013 | match-zero-rejected | Target "Report" at (0,0,800,600); AX: one window "X" at (500,500) 10×10 | nil; `move` throws `accessibilityNotAvailable` |
| system-windows-014 | match-empty-title-score | Target "" at (0,0,800,600); AX: W1 "" elsewhere (1), W2 "Tab" elsewhere (0) | W1 selected |
| system-windows-015 | resolve-not-found | `move(windowID: 424242, to: .zero)` with no such window listed | Throws `windowNotFound(windowID: 424242)` |
| system-windows-016 | set-frame-partial | Movable but non-resizable window; `setFrame` to (50,50,300,300) | Throws `attributeSetFailed(attribute: "AXSize", …)`; window origin is (50,50) |
| system-windows-017 | horizontal-visibility | One screen, frame x 0…1440; window frames (-5000,200,800,600) and (-100,200,800,600) | false for the first, true for the second |
| system-windows-018 | display-fallback | Point (-99999,-99999) | Returns the main display id |
| system-windows-019 | focus-unpark | Main screen visible minX 0; window parked at (-5000,300,800,600) | Before raise, window moved to (80,300) |
| system-windows-020 | focus-activate | Window listed, AX element found, raise succeeds, owning app has quit | Throws `activationFailed(app:pid:)` |
| system-windows-021 | error-descriptions | `.attributeSetFailed(attribute: "AXPosition", axError: -25200)` | description "Failed to set AXPosition: AXError code -25200" |
| system-windows-022 | observer-start-idempotent, observer-refresh | Mock control listing windows {1,2} for PID 10 and {3} for PID 20; call `startObserving()` twice | `listAllWindows` called once; snapshot {10: {1,2}, 20: {3}} |
| system-windows-023 | window-destroyed | Snapshot {10: {1,2}}; mock now lists {1}; destroyed notification | `windowDestroyed(windowID: 2)` exactly once; snapshot {10: {1}} |
| system-windows-024 | window-created-baseline, window-created-report | Snapshot {10: {1}}; created notification for PID 10; before 0.5 s a destroy refresh adds id 5; after 0.5 s mock lists {1,5} | `windowCreated` called for id 5 |
| system-windows-025 | title-changed-match | Element of PID 10 at (0,0) 800×600 titled "New"; mock lists PID 20 window id 9 and PID 10 window id 4, both at (0,0,800,600) | `windowTitleChanged(windowID: 4, newTitle: "New")` |
| system-windows-026 | observer-stop | Observing; `stopObserving()`; then a launch notification | No delegate call; AX observers and snapshot empty |
| system-windows-027 | permission-is-granted | Untrusted process; read `isGranted` ten times | Returns false each time; no system prompt appears |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowManager.init()` | — | — | No parameters; the manager is stateless. |
| `SystemWindowManager.excludedApps` | `Set<String>` (static let) | six system process names | Owner names dropped from enumeration. |
| `SystemWindowObserver.init(windowManager:)` | `SystemWindowControlling` | required | Window source used for snapshots and diffs; a mock can be injected. |
| `SystemWindowObserver.delegate` | `SystemWindowObserverDelegate?` (weak) | nil | Receives lifecycle events. |
| `SystemWindowAXHelper.axElement(for:windowInfo:)` `windowInfo` | `SystemWindowInfo?` | nil | Pre-fetched info; nil triggers a fresh window-list lookup. |
| Geometry tolerance | `CGFloat` (constant) | strictly less than 2 points | Position and size match tolerance for matching, backfill and title changes. |
| Match weights | `Int` (constants) | title 10, position 5, size 3, both-empty title 1 | `bestMatch` scoring. |
| Unpark x offset | `CGFloat` (constant) | 80 | Points right of the main screen's visible minX. |
| Launch delay | seconds (constant) | 1.0 | Wait before subscribing to a newly launched app. |
| Window-created delay | seconds (constant) | 0.5 | Wait before diffing for a new window. |

## Deep Linking

Not applicable: the engine exposes no routes or URL handling; it is driven by direct calls and system notifications.

## Localization

`SystemWindowControlError.description` returns hardcoded English strings with no localization; the `accessibilityNotAvailable` text addresses the user.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `No window found with CGWindowID <windowID>` | `windowNotFound` |
| (none) | `Accessibility not available for <app> (PID <pid>). Grant Accessibility permission in System Settings.` | `accessibilityNotAvailable` |
| (none) | `Failed to set <attribute>: AXError code <axError>` | `attributeSetFailed` |
| (none) | `Failed to activate <app> (PID <pid>)` | `activationFailed` |

## Accessibility Options

Not applicable: the engine renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color do not affect it.

## Feature Flags

Not applicable: the source reads no feature flag; every operation runs when called.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Other apps' names, PIDs, window ids, titles (which often name documents, pages or paths), frames, displays and on-screen state.
- **Storage**: In memory only; the observer keeps window ids per PID, and nothing is written to disk.
- **Transmission**: None; data goes to the caller and the delegate. Log lines go to the unified log.
- **Retention**: For the life of the returned values and, for the observer snapshot, until the next refresh or `stopObserving()`.

## Logging

Subsystem: main bundle identifier (via `Loggable`) | Category: `SystemWindowObserver`

| Event | Level | Message |
|-------|-------|---------|
| Observation started | info | `SystemWindowObserver started, monitoring <count> applications` |
| Observation stopped | info | `SystemWindowObserver stopped` |
| App launched | info | `App launched: <appName> (PID <pid>)` |
| App terminated | info | `App terminated: <appName> (PID <pid>)` |
| Window created | info | `Window created: <app> — '<title>' (ID <id>)` |
| Window destroyed | info | `Window destroyed: ID <windowID>` |
| Title changed | debug | `Title changed: <app> — '<newTitle>' (ID <id>)` |

Interpolated strings (app names, titles) use the unified log's default private redaction; integers are public. `SystemWindowManager`, `SystemWindowAXHelper` and `SystemAccessibilityPermission` do not log, and observer creation or registration failures are not logged.

## Platform Notes

- **SwiftUI**: SwiftUI has no API for other apps' windows. A SwiftUI host keeps this engine as is and wraps the observer's delegate in an `@Observable` model on the main actor; permission UI calls `SystemAccessibilityPermission.isGranted` on scene activation and `request()` from a button.
- **Compose**: Android offers no way for an app to enumerate, move or focus another app's windows. The closest start is an `AccessibilityService` reading `getWindows()` (`AccessibilityWindowInfo` with `getTitle`, `getBoundsInScreen`, `getId`) and `TYPE_WINDOWS_CHANGED` events; move and resize have no equivalent, and window ids are direct so no matching step is needed.
- **React/Web**: A browser cannot see other applications' windows. An Electron or Node host would start from a native addon (for example `node-window-manager` or `active-win`) over the platform APIs; the matching and policy logic ports as plain TypeScript over the returned records.
- **AppKit / UIKit**: Source files are `SystemWindowManager.swift` (CoreGraphics `CGWindowListCopyWindowInfo`, `CGGetDisplaysWithPoint`, `NSScreen`, `NSRunningApplication.activate()`), `SystemWindowAXHelper.swift` (ApplicationServices `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue`, `AXValue`, `kAXRaiseAction`), `SystemWindowObserver.swift` (`AXObserverCreate` with a C callback bridged through an unretained refcon, `CFRunLoopGetMain`, `NSWorkspace` notifications, `os.Logger`), `SystemWindowControlError.swift`, `SystemWindowControlling.swift` and `SystemAccessibilityPermission.swift` (`AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions` with the string key `AXTrustedCheckOptionPrompt`). The matching step exists only because `AXUIElement` exposes no CGWindowID. UIKit has no equivalent: iOS apps cannot see other apps' windows.
- **WinUI 3**: Windows App SDK's `Microsoft.UI.Windowing.AppWindow` controls only the app's own windows, so a port calls Win32 through P/Invoke or CsWin32. Enumerate with `EnumWindows`, filter with `IsWindowVisible`, `GetWindowLongPtr` (`WS_EX_TOOLWINDOW`) and `DwmGetWindowAttribute(DWMWA_CLOAKED)` instead of the layer-0 and excluded-app policy, read `GetWindowText`, `GetWindowRect` and `GetWindowThreadProcessId`, and get the app name from `System.Diagnostics.Process.GetProcessById`. An `HWND` is both id and control handle, so the AX matching step and its title/geometry score disappear. Move, resize and set-frame become one `SetWindowPos` call (atomic, unlike the source's two writes); focus becomes `ShowWindow(SW_RESTORE)` plus `SetForegroundWindow`, which Windows may refuse under its foreground lock (map that to `ActivationFailed`). Display comes from `MonitorFromPoint` with `MONITOR_DEFAULTTOPRIMARY`, matching the main-display fallback. There is no Accessibility trust gate; the equivalent failure is UIPI, which blocks a non-elevated process from moving an elevated window. Replace `SystemWindowObserver` with `SetWinEventHook` (`EVENT_OBJECT_CREATE`, `EVENT_OBJECT_DESTROY`, `EVENT_OBJECT_NAMECHANGE`, `WINEVENT_OUTOFCONTEXT`) or UI Automation (`Automation.AddAutomationEventHandler` with `WindowPattern.WindowOpenedEvent`), and app launch and exit with a `ManagementEventWatcher` on `Win32_ProcessStartTrace`/`Win32_ProcessStopTrace` or `Process.Exited`. Keep the observer on the UI thread through `DispatcherQueue`, expose windows as an `ObservableCollection<SystemWindowInfo>` with `INotifyPropertyChanged` where a view binds them, turn the delegate into C# events, and replace the `asyncAfter` delays with `await Task.Delay`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/SystemAccessibilityPermission.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/SystemWindowAXHelper.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/SystemWindowControlError.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/SystemWindowControlling.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/SystemWindowManager.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/SystemWindowObserver.swift` |

## Design Decisions

**Decision**: Enumerate with the CoreGraphics window list and manipulate through Accessibility.
**Rationale**: Per the `SystemWindowManager` doc comment, the window list needs no permission and gives ids and PIDs, while move, resize and focus need Accessibility; the split keeps listing available to hosts without trust.
**Approved**: pending

**Decision**: Bridge a window id to an `AXUIElement` by PID plus a weighted title/position/size score, with title weighted 10 over geometry 5 and 3 and score 0 rejected.
**Rationale**: `AXUIElement` has no constructor from a CGWindowID; per the `bestMatch` comment a title match must dominate a geometry match, and two windows sharing both title and frame are inherently ambiguous, so the first wins.
**Approved**: pending

**Decision**: Geometry comparisons use a tolerance of strictly less than 2 points.
**Rationale**: The source's comments cite rounding differences between CoreGraphics bounds and AX geometry.
**Approved**: pending

**Decision**: Backfill empty titles through Accessibility, batched once per PID, taking a single-window app's title regardless of frame and refusing ambiguous frame matches.
**Rationale**: The window list omits titles without Screen Recording permission; per the `axTitle(forFrame:in:)` comment, an empty title is better than the wrong window's, and the single-window rule is what gives minimized windows a title.
**Approved**: pending

**Decision**: `focus` unparks a window by fixing only X, and visibility is tested on X alone.
**Rationale**: Parking moves windows far left while keeping Y; per the `isOnScreenHorizontally` comment, testing X avoids comparing CoreGraphics top-left Y with AppKit bottom-left screen Y.
**Approved**: pending

**Decision**: The engine is permission-agnostic; `SystemAccessibilityPermission` is separate and `request()` passes the prompt option as a string literal.
**Rationale**: Per its doc comment the UI decides when to check and prompt, and the SDK's `kAXTrustedCheckOptionPrompt` global is not concurrency-safe to reference under strict concurrency.
**Approved**: pending

**Decision**: `windowInfo(from:)` is shared by enumeration and the helper's lookup.
**Rationale**: Per its doc comment the AX path previously hardcoded the main display; one parser keeps fields and `display` identical on both paths.
**Approved**: pending

**Decision**: The window-created handler captures its baseline immediately, scoped to the owning PID, and waits 0.5 s; app launch waits 1.0 s.
**Rationale**: Per the `handleWindowCreated` comment, reading the baseline inside the delayed block races a synchronous destroy handler's refresh (TOCTOU) and would hide the new window; the delays let titles and windows settle.
**Approved**: pending

**Decision**: The observer is `@unchecked Sendable` with main-run-loop confinement and passes itself to AX callbacks as an unretained refcon.
**Rationale**: `AXObserverCreate` needs a C function pointer; confinement to the main run loop, documented on the type, is what makes the unchecked conformance sound, and `deinit` stops observation before the refcon could dangle.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | partial | Performance |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | partial | Performance |
| [platform-permissions](agenticdevelopercookbook://compliance/platform-compliance#platform-permissions) | passed | Platform Compliance |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

separation-of-concerns passes because enumeration, AX bridging, observation, errors and permission each live in their own type, and orchestration depends on the `SystemWindowControlling` protocol. unit-test-coverage fails because none of the six files has tests; only a mock of the protocol is exercised by `SystemWindowContextManagerTests.swift`, so the parser, policy, scoring and backfill rules are untested although they are pure enough to test. explicit-error-handling is partial: control operations throw typed errors with raw AX codes, but the unpark result in `focus` and every AX notification registration result are discarded (the open questions on focus-unpark-failure and observer-registration-errors), and a failed window-list query is indistinguishable from an empty one. graceful-degradation passes because listing works without Accessibility and missing trust surfaces as a typed error rather than a crash. timeout-handling is partial because the engine relies on the system's default AX messaging timeout and sets none of its own, though a timed-out write surfaces as `attributeSetFailed`. main-thread-freedom is partial: list operations may run off the main thread, but the observer runs full window listings with AX backfill synchronously on the main thread for every destroy and title event. resource-efficiency is partial: backfill is batched per PID and skipped when titles exist, but every control operation re-lists all windows to resolve one id. platform-permissions passes because the engine needs only Accessibility, never prompts on its own, and exposes a side-effect-free check. no-pii-in-logs passes because titles and app names are interpolated with the unified log's default private redaction.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `SystemAccessibilityPermission.swift`, `SystemWindowAXHelper.swift`, `SystemWindowControlError.swift`, `SystemWindowControlling.swift`, `SystemWindowManager.swift` and `SystemWindowObserver.swift` |
