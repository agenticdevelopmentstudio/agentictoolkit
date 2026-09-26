---
id: 3b602118-9299-483b-bf4d-62c9d525833d
title: WindowFrameManager
domain: agentictoolkit://cookbook/macos/system-integration/window-manager/window-frame-manager
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: macOS main-actor service that saves and restores window frames per screen
  set, top-left anchored, with pure frame math and screen matching.
platforms:
- swift
- macos
tags:
- window-management
- screens
- persistence
- macos
depends-on:
- agentictoolkit://cookbook/macos/system-integration/window-manager/screen-manager
related:
- agentictoolkit://cookbook/macos/system-integration/window-manager/windows/single-window-controller
references: []
approved-by: ''
approved-date: ''
---

# WindowFrameManager

## Overview

`WindowFrameManager` (in `WindowFrameManager.swift`, with its helpers
`FrameCalculator`, `FrameAnchor` / `FrameAnchors`, `PersistedWindowState`,
`WindowPlacement`, `LegacyPersistedWindowState`, `ScreenFingerprint`,
`ScreenInfo` / `ScreenProvider`, `RealScreenInfo` / `RealScreenProvider`,
`ScreenMatcher` and `WindowPosition`) is the toolkit's window-frame
persistence service on macOS. It:

- holds a registry of `WindowSpec`s keyed by window id (default size, minimum
  size, default position, and whether frame and visibility persist);
- restores a window's frame on first show from the placement saved for the
  current screen set, or applies the spec's default position;
- saves a window's frame on every move or resize as a `WindowPlacement` keyed
  by `ScreenManager.currentSetID`, so a laptop that docks at several desks
  remembers one position per desk;
- repositions managed windows when `ScreenManager` reports a screen change;
- persists a window's visible/hidden flag independently of its frame.

Positions are anchored at the window's **top-left** corner from the user's
point of view (x grows right, y grows **down** from the top of the screen's
visible area). Restoring in the same screen set on an exactly matching screen
replays the saved absolute offset, so content-driven resizes cannot walk the
window between launches; a relative (travel-fraction) position is used only
when the literal geometry no longer applies.

`FrameCalculator` is a pure, side-effect-free namespace of frame math that is
also used directly by content-hugging windows (`contentHuggingFrame`).

The manager is owned by `WindowManager` and reached as
`WindowManager.shared.frames`. Usage per its doc comment: register specs at
startup with `register(id:spec:)`, call `restoreFrame(for:id:)` after creating
a window, and call `saveFrame(for:id:)` on move/resize
(`SingleWindowController` does this from its delegate hooks).

## Behavioral Requirements

### Isolation and ownership

- **main-actor-isolation**: `WindowFrameManager` MUST be `@MainActor`-isolated; every public operation, the screen-change handler, and the injected `windowLister` closure run on the main actor.
- **storage-main-actor**: The `WindowStateStorage` protocol MUST be `@MainActor`, so storage backends are only called from the main actor.
- **sendable-value-types**: `FrameAnchor`, `FrameAnchors`, `WindowPlacement`, `PersistedWindowState`, `LegacyPersistedWindowState`, `ScreenFingerprint`, `WindowPosition` and `ScreenMatcher.MatchQuality` MUST be `Sendable` value types.
- **non-sendable-screen-types**: `ScreenInfo`, `ScreenProvider`, `RealScreenInfo`, `RealScreenProvider` and `ScreenMatcher.ScreenMatch` MUST remain non-`Sendable`, so the compiler keeps them in the caller's isolation domain.
- **sole-writer-precondition**: Callers MUST ensure this process is the only writer of a given window id's persisted state; the `stateCache` doc comment states the write-through cache is "safe because this process is the sole writer of a given id's state", and the manager never re-reads storage for an id it has cached.
- **screen-observer-registration**: `init` MUST register one observer with the injected `ScreenManager` that forwards each `ScreenChange` to the screen-change handler through a weak reference to the manager.
- **start-observing-delegates**: `startObservingScreenChanges()` MUST delegate to `ScreenManager.startObservingScreenChanges()` and add no registration of its own.
- **spec-accessor**: `SingleWindowController.windowSpec` MUST read and write the spec registered under the controller's `windowID` in `WindowManager.shared.frames`.

### Data shapes

- **window-placement-fields**: `WindowPlacement` MUST be a `Codable`, `Equatable` value holding `screenFingerprint`, `topLeftX`, `topLeftY` (offset from the screen's visible-frame top-left, y pointing down), `width`, `height`, `relativeX`, `relativeY` (0...1 fractions of travel, 0 = left/top) and `savedAt: Date`, all immutable.
- **persisted-state-shape**: `PersistedWindowState` MUST hold `placements: [String: WindowPlacement]` keyed by screen-set id, and a read-only `legacy: LegacyPersistedWindowState?`.
- **persisted-state-encode**: Encoding `PersistedWindowState` MUST write only the `placements` key and MUST NOT encode `legacy`.
- **persisted-state-decode-v2**: Decoding MUST read `placements` when the key is present and non-null, with `legacy` set to `nil`.
- **persisted-state-decode-v1**: When `placements` is absent or null and the payload decodes as `LegacyPersistedWindowState`, decoding MUST produce empty `placements` and that value in `legacy`.
- **persisted-state-decode-degrade**: When the payload has neither a usable `placements` key nor a decodable v1 record (for example `{}`, `{"placements": null}` or `{"unrelated": 1}`), decoding MUST produce empty `placements` and `nil` `legacy` rather than throwing.
- **legacy-state-fields**: `LegacyPersistedWindowState` MUST hold `proportionalX`, `proportionalY` (bottom-left-anchored fractions of travel), `width`, `height`, `screenFingerprint` and `savedAt`.
- **fingerprint-fields**: `ScreenFingerprint` MUST be a `Codable`, `Equatable` value holding `displayUUID: String?`, `localizedName: String?`, `resolutionWidth`, `resolutionHeight` and `isMain`.
- **fingerprint-from-screen**: `ScreenFingerprint.from(_:)` MUST take `displayUUID` from the display's CoreGraphics UUID (nil when the screen number or UUID is unavailable), `localizedName` from the screen, the resolution from the screen's full `frame` (not its visible frame), and `isMain` from whether the screen equals the current main screen.
- **screen-info-contract**: `ScreenInfo` MUST expose `frame`, `visibleFrame`, `fingerprint` and `backingScaleFactor`; conformers that do not supply `backingScaleFactor` MUST report `2`.
- **screen-provider-contract**: `ScreenProvider` MUST expose `screens: [ScreenInfo]` and `mainScreen: ScreenInfo?`; `RealScreenProvider` MUST map `NSScreen.screens` and `NSScreen.main`.
- **window-position-values**: `WindowPosition` MUST map `center` to (0.5, 0.5), `topRight` to (0.85, 0.85), and `custom(horizontal:vertical:)` to its two values, as bottom-left-anchored fractions of travel (0 = left/bottom, 1 = right/top).
- **frame-anchors-shape**: `FrameAnchor` MUST have exactly the cases `start` (left or top) and `end` (right or bottom); `FrameAnchors` MUST hold one `horizontal` and one `vertical` anchor.

### Frame math (FrameCalculator)

- **clamped-length-rule**: `clampedLength(_:min:visible:)` MUST return `min(max(desired, minLength), max(visibleLength, minLength))`, so a length is never below `minLength`, never past the visible length, and `minLength` wins when the two disagree.
- **min-size-wins-everywhere**: `absoluteFrame`, `frame(relativePosition:...)`, `contentHuggingFrame` and `validateFrame` MUST all size each axis with `clampedLength`, so a minimum larger than the screen is kept and the window overhangs.
- **proportional-position**: `proportionalPosition` MUST return `(origin - visibleOrigin) / (visibleLength - windowLength)` per axis, bottom-left anchored, clamped to -0.1...1.1, and `0.5` on an axis with no positive travel.
- **absolute-frame**: `absoluteFrame` MUST clamp width and height with `clampedLength`, then set each origin to `visibleOrigin + proportion * max(visibleLength - clampedLength, 0)`.
- **default-frame**: `defaultFrame(spec:screenVisibleFrame:)` MUST equal `absoluteFrame` with the spec's `defaultPosition` fractions, `defaultSize` and `minSize`.
- **top-left-offset**: `topLeftOffset` MUST return `(window.minX - visible.minX, visible.maxY - window.maxY)`.
- **frame-from-top-left**: `frame(topLeftOffset:size:screenVisibleFrame:)` MUST return a frame at `x = visible.minX + offset.x`, `y = visible.maxY - offset.y - size.height` with the given size unclamped.
- **relative-position**: `relativePosition` MUST return the top-left offset divided by the travel (`visibleLength - windowLength`) per axis, clamped to 0...1, and `0.5` on an axis with no positive travel.
- **frame-from-relative**: `frame(relativePosition:size:screenVisibleFrame:minSize:)` MUST clamp the size with `clampedLength`, then place the top-left at `relative * max(visibleLength - clampedLength, 0)` from the visible top-left.
- **validate-frame-size**: `validateFrame` MUST clamp width and height with `clampedLength`.
- **validate-frame-push**: `validateFrame` MUST then push the origin inside the visible frame in this order: right edge, left edge, top edge, bottom edge; a window wider or taller than the visible frame therefore ends flush with the left and bottom edges.
- **hug-per-axis**: `contentHuggingFrame` MUST solve each axis independently in top-left user coordinates through the same one-axis rule (`fittedAxis`) and return the fitted frame with the anchors it used.
- **hug-nearest-edge**: With no anchor supplied, an axis MUST hold its `end` edge when the end gap is strictly smaller than the start gap, and its `start` edge otherwise (ties, including a window filling the axis, keep `start`).
- **hug-held-anchor**: When `anchors` is supplied, `contentHuggingFrame` MUST use those anchors unchanged instead of re-reading them from the frame, and MUST return them.
- **hug-end-anchor-offset**: Holding `end` MUST keep `offset + length` fixed before on-screen correction; holding `start` MUST keep `offset` fixed.
- **hug-push-on-screen**: After anchoring, the axis offset MUST be clamped to at most `visibleLength - newLength`, then to at least `0`, so a window that cannot fit ends flush with the start (left or top) edge.
- **hug-length-clamp**: The new axis length MUST be `clampedLength(desired, min: minLength, visible: visibleLength)`.

### Screen matching (ScreenMatcher)

- **match-quality-order**: `MatchQuality` MUST order `positionOnly` (1) < `nameOnly` (2) < `uuidResChanged` (3) < `exact` (4).
- **match-uuid-tier**: A screen whose `displayUUID` equals the saved non-nil `displayUUID` MUST match as `exact` when both resolution components differ by less than 1 point, and as `uuidResChanged` otherwise; that screen MUST NOT be considered for a lower tier.
- **match-name-tier**: A screen not matched by UUID whose `localizedName` equals the saved non-nil `localizedName` MUST match as `nameOnly`, even when both UUIDs are present and differ.
- **match-position-tier**: A screen not matched by UUID or name MUST match as `positionOnly` when both the saved and current fingerprints have `isMain` true.
- **match-best**: `findBestMatch` MUST return the candidate with the highest quality, the first such candidate in `screens` order on a tie, and `nil` when no screen matches.

### Registration

- **register-spec**: `register(id:spec:)` MUST store the spec under the id, replacing any spec previously registered under it.

### Restore

- **restore-tags-window**: `restoreFrame(for:id:)` MUST set the window's identifier to `wm_<id>` before any other step, including when it then fails.
- **restore-no-spec**: With no spec registered for the id, restore MUST log a warning, center the window geometrically on the main screen's visible frame, and return `false`.
- **restore-min-size**: With a spec, restore MUST set the window's minimum size to `spec.minSize`.
- **restore-no-persistence**: When the spec does not persist frames, or no state is stored for the id, restore MUST apply the spec's default frame on the main screen (first screen if there is no main) and return `false`.
- **restore-touch-set**: Before looking a placement up, restore MUST call `ScreenManager.touchCurrentSet()` and then read `currentSetID`.
- **restore-no-screens**: When the provider reports no screens, restore MUST center the window geometrically and return `false`.
- **restore-known-set**: When a placement exists under the current set id, restore MUST apply the resolved frame (see placement-resolution rules) and return `true`.
- **restore-known-set-resave**: When that resolution was not an exact screen match, restore MUST immediately save the window's frame so the placement records the new screen geometry.
- **restore-unknown-set**: When no placement exists for the current set but other placements do, restore MUST apply the relative-fallback frame, save the window's frame under the current set, and return `true`.
- **restore-legacy-migration**: When there are no placements and a `legacy` record exists, restore MUST place the window with `absoluteFrame` from the legacy proportions and size on the best-matching screen (main, then first screen when none matches), pass it through `validateFrame`, apply it, save the frame as a per-set placement, and return `true`.
- **restore-fallthrough**: When stored state has neither placements nor a legacy record, restore MUST apply the spec's default frame and return `false`.

### Placement resolution

- **resolve-screen-choice**: A saved placement MUST be resolved on the screen `ScreenMatcher` finds for its fingerprint, falling back to the main screen, then the first screen.
- **resolve-exact-replay**: On an `exact` match the frame MUST be rebuilt from the saved `topLeftX` / `topLeftY` and saved size with `frame(topLeftOffset:...)`.
- **resolve-relative**: On any non-exact match or no match, the frame MUST be rebuilt from `relativeX` / `relativeY` and saved size with `frame(relativePosition:...)` and the spec's `minSize`.
- **resolve-validate**: Every resolved frame MUST pass through `validateFrame` against the chosen screen's visible frame and the spec's `minSize`.
- **relative-fallback-source**: The relative fallback MUST use the placement with the latest `savedAt`, placed on the main screen (first screen when there is no main), through `frame(relativePosition:...)` then `validateFrame`; it MUST return nothing when there are no placements.

### Save

- **save-guard-spec**: `saveFrame(for:id:)` MUST do nothing when no spec is registered for the id or the spec does not persist frames.
- **save-touch-first**: Save MUST call `ScreenManager.touchCurrentSet()` and read `currentSetID` before choosing the screen to fingerprint, so a move that AppKit delivers before the screen-change notification is filed under the live set.
- **save-best-screen**: Save MUST fingerprint the screen that contains the largest area of the window's frame intersected with each screen's visible frame; with no intersecting screen it MUST fall back to the window's own screen, then the system main screen, both read directly from AppKit rather than the injected provider.
- **save-no-screen**: When no screen can be chosen, save MUST return without writing.
- **save-placement-values**: The placement written MUST carry the chosen screen's fingerprint, the window's top-left offset and relative position computed against that screen's visible frame, the window's current width and height, and `savedAt` equal to `ScreenManager.now()`.
- **save-preserves-other-sets**: Save MUST rebuild state from the cached (or freshly loaded) placements, replace only the current set's entry, and keep other sets' entries subject to pruning.
- **save-drops-legacy**: The state written by save MUST have `legacy` equal to `nil`, so the first save consumes a decoded v1 record.
- **save-prune**: Save MUST keep a placement only when its key is the current set id, or its key is in `ScreenManager.knownSetIDs`, or its `savedAt` is later than `now() - maxSetAge`.
- **save-write-through**: Save MUST update the in-memory cache for the id and then call `storage.saveState(_:for:)` exactly once.

### Cache

- **cache-read-through**: Restore and screen-change handling MUST read an id's state from the in-memory cache when present, and otherwise load it from storage and cache the result.
- **cache-miss-not-cached**: A load that returns `nil` MUST leave the cache without an entry for the id, so the next read loads from storage again.

### Reset and clear

- **reset-frame**: `resetFrame(for:id:)` MUST remove the id's stored state, clear its cache entry, and apply the spec's default frame, or center the window geometrically when no spec is registered.
- **reset-all-frames**: `resetAllFrames()` MUST remove stored state for every registered id and empty the whole cache; it MUST NOT reposition any window and MUST NOT remove stored state for ids that are not registered.
- **clear-saved-state**: `clearSavedState(for:)` MUST remove the id's stored state and cache entry without moving any window.
- **reset-leaves-visibility**: `resetFrame`, `resetAllFrames` and `clearSavedState` MUST NOT touch persisted visibility.

### Visibility

- **load-visibility**: `loadVisibility(for:)` MUST return `nil` when no spec is registered or the spec does not persist visibility, and otherwise the storage's value (`nil` when never saved).
- **save-visibility**: `saveVisibility(_:for:)` MUST write the flag only when a spec is registered that persists visibility, and otherwise do nothing.
- **clear-visibility**: `clearVisibility(for:)` MUST remove the stored flag without consulting the spec.
- **visible-window-ids**: `visibleWindowIDs()` MUST return the storage's list of ids whose saved visibility is `true`.

### Default placement

- **default-position-screen**: Applying a default position MUST use the main screen's visible frame, falling back to the first screen, and MUST center geometrically when there are no screens.
- **geometric-center**: Geometric centering MUST set the window origin to `visible.origin + (visible.size - window.size) / 2` on each axis, keeping the window's size; with no screen at all it MUST fall back to the window's own `center()` placement.

### Screen-change handling

- **change-no-screens**: On a screen change with no screens, the handler MUST do nothing.
- **change-window-lookup**: The handler MUST snapshot the live windows once per event, key them by the id after the `wm_` identifier prefix, and consider every registered spec whose window is present, visible or hidden.
- **change-known-placement**: For a window with a placement under the current set, the handler MUST apply the resolved frame, for every kind of `ScreenChange`.
- **change-new-set-fallback**: For a `screenSetChanged` event where the window has no placement under the current set but has other placements, the handler MUST apply the relative-fallback frame and then save the window's frame.
- **change-reclamp**: Every other managed window (no persisted state, frame persistence off, or a non-set change with no placement) MUST keep its current frame pushed on screen through `validateFrame` on its best screen.
- **change-apply-only-real**: The handler MUST skip `setFrame` when the validated frame equals the window's current frame.
- **change-animate-visible**: The handler MUST animate the frame change only when the window is visible.
- **change-resave-by-delegate**: Apart from the new-set fallback, the handler MUST NOT save frames itself; re-saving after a reposition relies on the window controller's move/resize delegate hooks.

### Persistence durability

- **storage-default-backend**: The default `UserDefaultsWindowStateStorage` MUST store each id's state as JSON under `WindowState_<id>` and visibility as a `Bool` under `WindowVisible_<id>`, both qualified by `WindowStateNamespace`, so state survives app relaunch.
- **storage-failure-signal**: NEEDS REVIEW: Not implemented in source. `WindowStateStorage` has no error channel; the default backend returns `nil` for undecodable data (restore then applies the default frame and the next save overwrites the blob) and silently skips a write whose encoding fails, with no log. Settle by deciding whether load/save failures must be logged or surfaced to `WindowFrameManager`.

## Appearance

Not applicable — this is a window-frame persistence service and frame-math library, not a visual component.

## States

Not applicable — this is a window-frame persistence service and frame-math library, not a visual component.

## Accessibility

Not applicable — this is a window-frame persistence service and frame-math library, not a visual component.

## Conformance Test Vectors

Screens are bottom-left-origin rectangles `(x, y, width, height)`. Vectors marked with a test name come from `FrameCalculatorTests.swift`, `ScreenMatcherTests.swift` or `WindowManagerSimulatedRelaunchTests.swift`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wfm-001 | proportional-position | Visible (0,0,1920,1080); window (760,340,400,400) | (0.5, 0.5) (`testProportionalPositionCenter`) |
| wfm-002 | proportional-position | Window (0,0,1920,1080) fills visible (0,0,1920,1080) | (0.5, 0.5) exactly (`testProportionalPositionWindowFillsScreen`) |
| wfm-003 | absolute-frame | Proportions (0.5, 0.5), size 600×480, visible (0,0,1920,1080), min 100×100 | (660, 300, 600, 480) (`testAbsoluteFrameCenter`) |
| wfm-004 | default-frame, window-position-values | Spec default 340×300, min 280×120, `topRight`; visible (0,0,1920,1080) | origin ≈ (1342, 663) (`testDefaultFrameTopRight`) |
| wfm-005 | top-left-offset | Visible top-left and window top-left 60 right and 40 down of it | offset (60, 40) (`testTopLeftOffsetMeasuresDownFromVisibleTop`) |
| wfm-006 | relative-position | Window with no travel on either axis | (0.5, 0.5) (`testRelativePositionCenteredWhenNoTravel`) |
| wfm-007 | frame-from-relative, clamped-length-rule | Size larger than an 800×600 visible frame, small min | size 800×600 (`testFrameFromRelativePositionClampsSizeToScreen`) |
| wfm-008 | validate-frame-push | Frame hanging off the right of (0,0,1920,1080), width 400 | maxX 1920, width 400 (`testValidateFramePushesFromRight`) |
| wfm-009 | min-size-wins-everywhere | Visible (0,0,150,60), min 200×100, desired 10×10 through `absoluteFrame`, `frame(relativePosition:)`, `validateFrame`, `contentHuggingFrame` | every result has size 200×100 (`testEveryPathKeepsAMinimumLargerThanTheScreen`) |
| wfm-010 | hug-nearest-edge, hug-per-axis | Visible (0,0,1600,1000), min 200×100; window left 400 top 300, 500×300; desired 560×420, no anchors | minX 400, maxY unchanged, size 560×420 (`testContentHuggingGrowsDownAndRightWhenNowhereNearAnEdge`) |
| wfm-011 | hug-push-on-screen | Same visible; window left 40 top 40, 500×300; desired 1600×300 | width 1600, minX 0 (`testAWindowNearTheLeftEdgeGrowsRightwardWithoutMoving`) |
| wfm-012 | hug-held-anchor | Window left 600 top 300, 400×300; grow to 600×300 with nil anchors, then shrink to 400×300 passing the returned anchors | first step keeps minX; second step returns the original frame (`testAWindowInTheMiddleComesBackToWhereItStarted`) |
| wfm-013 | hug-nearest-edge | Same two steps but anchors re-read (nil) on the second step | second step minX 800 (`testRereadingTheAnchorEachStepWalksTheWindow`) |
| wfm-014 | hug-held-anchor, hug-end-anchor-offset | Window left 1060 top 300, 500×300; anchors (end, start); desired 200×300 | maxX unchanged; returned anchors equal (end, start) (`testAHeldEndAnchorOutranksWhereTheWindowNowSits`) |
| wfm-015 | hug-nearest-edge | Window left 1060 top 20, 500×300; desired 520×320; nil anchors | anchors (end, start) (`testAFitReportsTheAnchorsItChose`) |
| wfm-016 | hug-push-on-screen, min-size-wins-everywhere | Visible and current (0,0,150,60), min 200×100, desired 10×10 | size 200×100, minX 0, maxY 60 (flush top) (`testAWindowKeepsItsMinimumOnAScreenTooSmallForIt`) |
| wfm-017 | match-uuid-tier | Saved fingerprint UUID and resolution equal a current screen's | quality `exact` (`testExactMatchByUUIDAndResolution`) |
| wfm-018 | match-uuid-tier | Same UUID, different resolution | quality `uuidResChanged` (`testUUIDMatchWithResolutionChange`) |
| wfm-019 | match-name-tier | Different UUIDs, same localized name | quality `nameOnly` (`testNameMatchWhenUUIDDiffers`) |
| wfm-020 | match-position-tier | No UUID or name match; saved and current both main | quality `positionOnly` (`testPositionMatchMainScreen`) |
| wfm-021 | match-best | No screen matches on any tier | `nil` (`testNoMatchReturnsNil`) |
| wfm-022 | match-best, match-uuid-tier | One screen matches by UUID with changed resolution, another by name | the UUID screen, quality `uuidResChanged` (`testPreferUUIDOverName`) |
| wfm-023 | save-placement-values, restore-known-set, resolve-exact-replay | Save window (300,400,600,300) on a 1920×1080 screen; new manager on same storage and screens; restore | returns `true`; frame (300,400,600,300) (`testSameSetRestoreIsExactAfterRelaunch`) |
| wfm-024 | resolve-relative | Save (1320,600,600,480) on a 1920×1080 display; relaunch with the same display at 2560×1440; restore | returns `true`; frame (1960,960,600,480) (`testRestoreAfterResolutionChangeUsesRelativePosition`) |
| wfm-025 | restore-known-set-resave | As wfm-024 with a window saved at (300,500,600,300) | stored placement fingerprint resolution becomes 2560×1440 (`testNonExactRestoreReSavesPlacementWithNewResolution`) |
| wfm-026 | restore-unknown-set, relative-fallback-source, save-preserves-other-sets | Save centered (2900,480,600,480) on an external-only set; relaunch on a built-in 1920×1080 set; restore | frame (660,300,600,480); storage holds placements for both set ids (`testUnknownScreenSetFallsBackToMainScreenAndSavesPlacement`) |
| wfm-027 | save-preserves-other-sets | Save different frames under the undocked and docked sets; restore under each | each set restores its own frame exactly (`testEachScreenSetRemembersItsOwnPlacement`) |
| wfm-028 | resolve-validate, clamped-length-rule | Save 1200×900 on a 2560×1440 display; relaunch with the same display at 800×600 | size equals the 800×600 visible frame and the frame lies inside it (`testOversizeSavedWindowIsClampedToShrunkenScreenOnRelaunch`) |
| wfm-029 | persisted-state-decode-v1, restore-legacy-migration, save-drops-legacy | v1 JSON (proportions 0.7/0.3, 600×480, main built-in 1920×1080); restore | origin ≈ (924, 180), size 600×480; stored state has `legacy` nil and a placement under the current set (`testLegacyV1StateMigratesToPlacementOnRestore`) |
| wfm-030 | persisted-state-decode-degrade | Decode `{}`, `{"placements": null}`, `{"unrelated": 1}` | no throw; empty placements; `legacy` nil (`testEmptyOrMalformedJSONDecodesToEmptyPlacementsInsteadOfThrowing`) |
| wfm-031 | persisted-state-encode, persisted-state-decode-v2 | Encode state with one placement under key `SET`, decode | placements equal the original; `legacy` nil (`testV2StateSurvivesJSONRoundTrip`) |
| wfm-032 | restore-no-spec, restore-tags-window | Restore for an unregistered id | returns `false`; identifier `wm_<id>`; window geometrically centered on the main visible frame |
| wfm-033 | restore-no-persistence | Spec with frame persistence off; restore | returns `false`; frame equals `defaultFrame` on the main screen; `minSize` equals the spec's |
| wfm-034 | save-guard-spec | `saveFrame` for an unregistered id, and for a spec with frame persistence off | `storage.saveState` never called |
| wfm-035 | save-prune | Stored placement under a set id not in `knownSetIDs`, `savedAt` older than `maxSetAge`; save under the current set | the old placement is absent from the written state |
| wfm-036 | load-visibility, save-visibility | Spec without visibility persistence; `saveVisibility(true)` then `loadVisibility` | storage untouched; `loadVisibility` returns `nil` |
| wfm-037 | reset-all-frames | Stored state for a registered id and an unregistered id; `resetAllFrames()` | registered id's state removed; unregistered id's state remains; no window moved |
| wfm-038 | change-apply-only-real | Screen change where the validated frame equals the window's current frame | `setFrame` not called |
| wfm-039 | change-new-set-fallback | `screenSetChanged` to a set with no placement for a window that has another set's placement | window moved to the relative-fallback frame and a placement saved under the new set |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `screenProvider` | `ScreenProvider` | `RealScreenProvider()` | Source of live screens and the main screen. |
| `storage` | `WindowStateStorage` | `UserDefaultsWindowStateStorage()` | Persistence for per-window state and visibility. |
| `screenManager` | `ScreenManager` | none (required) | Supplies `currentSetID`, `knownSetIDs`, `maxSetAge`, `now()`, `touchCurrentSet()` and screen-change events. |
| `windowLister` | `@MainActor () -> [NSWindow]` (internal) | `{ NSApp?.windows ?? [] }` | Source of live windows for screen-change repositioning; injectable in tests. |
| `WindowSpec.minSize` / `defaultSize` / `defaultPosition` | `NSSize` / `NSSize` / `WindowPosition` | per spec | Sizing floor and default frame. |
| `WindowSpec.behavior` `.persistsFrame` | option bit | on (in `.default`) | Enables frame save/restore for the id. |
| `WindowSpec.behavior` `.persistsVisibility` | option bit | on (in `.default`) | Enables visibility save/load for the id. |
| `UserDefaultsWindowStateStorage.keyPrefix` | `String` | `"WindowState_"` | Key prefix for state blobs (namespaced by `WindowStateNamespace`). |
| `UserDefaultsWindowStateStorage.visibilityKeyPrefix` | `String` | `"WindowVisible_"` | Key prefix for visibility flags (namespaced by `WindowStateNamespace`). |
| `anchors` (`contentHuggingFrame`) | `FrameAnchors?` | `nil` | Anchors carried across steps of one resize gesture; `nil` picks them by nearest edge. |

## Deep Linking

Not applicable: `WindowFrameManager` exposes no routes or URL handling; it is driven by direct calls and `ScreenManager` events.

## Localization

Not applicable: the component produces no user-facing strings; its only text is developer log messages in English.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it (screen-change animation follows only window visibility).

## Feature Flags

Not applicable: the source reads no feature flag; persistence is opted into per window through `WindowSpec.behavior`.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Per window id and screen set, the window's frame (top-left offset, size, relative position), a save timestamp, and the screen's display UUID, localized name, resolution and main flag; per window id a visible/hidden flag.
- **Storage**: JSON blobs in `UserDefaults` under `WindowState_<id>` and Booleans under `WindowVisible_<id>`, each prefixed by `WindowStateNamespace` (default backend).
- **Transmission**: None; nothing leaves the device.
- **Retention**: A placement is kept until its screen set is unknown to `ScreenManager` and older than `maxSetAge`, then dropped at the window's next save; `resetFrame`, `resetAllFrames` and `clearSavedState` remove state on demand.

## Logging

Subsystem: main bundle identifier (via `Loggable`) | Category: `WindowFrameManager`

| Event | Level | Message |
|-------|-------|---------|
| Restore with no registered spec | warning | `WindowFrameManager: no spec for '<id>'` |
| Restore from a same-set placement | debug | `WindowFrameManager: restored '<id>' exact=<Bool>` |
| Restore into a new screen set | debug | `WindowFrameManager: placed '<id>' in new set '<setID>'` |
| Legacy v1 migration | debug | `WindowFrameManager: migrated legacy state for '<id>'` |
| Reposition after a screen change | debug | `WindowFrameManager: repositioned '<id>' after screen change` |

Ids and set ids are logged with public privacy. Saves, resets, visibility calls and storage failures are not logged.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. SwiftUI's `.defaultPosition`, `.defaultSize` and scene restoration persist frames per scene but not per screen set; a SwiftUI port keeps this `@MainActor` class and reaches the underlying `NSWindow` (via an `NSViewRepresentable` window accessor) to call `restoreFrame` and `saveFrame`. `FrameCalculator` ports unchanged as pure functions on `CGRect`.
- **Compose**: Compose Desktop's `WindowState` (`position`, `size`) is the starting point, with `GraphicsEnvironment.getScreenDevices()` and `GraphicsConfiguration.bounds` / `Toolkit.getScreenInsets` for visible frames; persist with DataStore plus `kotlinx.serialization`, run on `Dispatchers.Main`. AWT coordinates are top-left-origin, so the top-left offset needs no y flip. Android phones have no free-floating windows; the math applies only to desktop and freeform modes.
- **React/Web**: Browsers expose window placement only for popups (`window.open` features, `moveTo` / `resizeTo`) and the Window Management API (`getScreenDetails()` with `availLeft` / `availTop` / `availWidth` / `availHeight`); persist with `localStorage` and `JSON.stringify`. No display UUID exists, so screen matching falls back to label and geometry; the pure frame math ports directly to TypeScript.
- **AppKit / UIKit**: Source files: `WindowFrameManager.swift` (`NSWindow.setFrame(_:display:animate:)`, `identifier`, `minSize`, `os.Logger` via `Loggable`), `FrameCalculator.swift` (pure `NSRect` math, bottom-left origin converted to top-left user coordinates), `PersistedWindowState.swift` (custom `Codable` with v1 fallback), `ScreenFingerprint.swift` (`CGDisplayCreateUUIDFromDisplayID` from `NSScreenNumber`), `ScreenInfo.swift`, `RealScreenProvider.swift` (`NSScreen.screens` / `NSScreen.main`), `ScreenMatcher.swift`, `WindowPosition.swift`. UIKit has no movable windows on iPhone; on iPad and visionOS use `UIWindowScene` geometry requests instead.
- **WinUI 3**: Start from `Microsoft.UI.Windowing.AppWindow` (`Position`, `Size`, `Move`, `Resize`, `MoveAndResize`, and the `Changed` event with `DidPositionChange` / `DidSizeChange` in place of the move/resize delegate hooks) and `DisplayArea.GetFromWindowId` / `DisplayArea.FindAll()` (`WorkArea` for the visible frame, `OuterBounds` for the resolution, `DisplayId` for identity). Windows coordinates are top-left-origin in physical pixels, so `topLeftOffset` needs no y flip but must account for DPI scaling (`XamlRoot.RasterizationScale`). Enforce `minSize` with `OverlappedPresenter` plus `PreferredMinimumWidth` / `PreferredMinimumHeight`. Keep the manager on the UI thread (`DispatcherQueue`), model `PersistedWindowState` as C# records serialised with `System.Text.Json` (a custom `JsonConverter` for the v1 fallback), and store them in `Windows.Storage.ApplicationData.Current.LocalSettings` (8 KB per value; use a `LocalFolder` file if many sets accumulate). Subscribe to display changes through `WM_DISPLAYCHANGE` / `WM_SETTINGCHANGE` or the `ScreenManager` port's event, and use `Task`/`async` only for file-based storage since the source is synchronous.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowFrameManager/` |

## Design Decisions

**Decision**: Placements are stored per screen set and replay an absolute top-left offset on an exact screen match.
**Rationale**: Per the `WindowPlacement` and class doc comments, replaying the literal offset means content-driven resizes "can never walk the window between launches", which the old proportional scheme did (`testContentRefitCannotDriftTopLeftAcrossRelaunches` records a clamped `proportionalY` of 1.1).
**Approved**: pending

**Decision**: A relative travel-fraction position is saved alongside the offset and used only on a non-exact match or an unknown set.
**Rationale**: A resolution change or a never-seen location makes the absolute offset meaningless; the relative position keeps a window flush to the same corner or centered.
**Approved**: pending

**Decision**: `minSize` wins over the screen size in every sizing path (`clampedLength`).
**Rationale**: Per the `clampedLength` doc comment, four paths used to spell this rule differently and returned different sizes for the same window; collapsing below `minSize` breaks the promise `minSize` makes, so the window overhangs instead.
**Approved**: pending

**Decision**: `contentHuggingFrame` chooses anchors once per gesture and returns them for the caller to pass back.
**Rationale**: Per its doc comment, no stateless nearest-edge rule is reversible under both a start and an end anchor; holding the anchor for the gesture makes "the move out the move back" (wfm-012, wfm-013).
**Approved**: pending

**Decision**: Save and restore call `ScreenManager.touchCurrentSet()` before reading `currentSetID`.
**Rationale**: AppKit repositions windows during a display reconfiguration and the resulting `windowDidMove` can reach `saveFrame` before the screen-change notification, which would otherwise file the placement under the outgoing set.
**Approved**: pending

**Decision**: A non-exact restore re-saves immediately.
**Rationale**: The delegate hooks are not wired during window loading, so without an explicit save the stale fingerprint would force relative placement on every launch instead of reaching the exact fast path.
**Approved**: pending

**Decision**: Per-window state is cached in memory, write-through.
**Rationale**: `saveFrame` fires on every move/resize tick; the cache avoids a `UserDefaults` read and JSON decode each time, under the documented sole-writer precondition.
**Approved**: pending

**Decision**: Placements are pruned with the same rule `ScreenManager` uses for sets, plus a recency grace period.
**Rationale**: Per the `saveFrame` comment, a placement survives while its set is known or it was saved recently, "so a rebuilt set list can't wipe other locations' state".
**Approved**: pending

**Decision**: Geometric centering is implemented by hand instead of `NSWindow.center()`.
**Rationale**: Per the `applyGeometricCenter` comment, `center()` places the window one-third from the top, not at the geometric center; `center()` is kept only as the no-screen fallback.
**Approved**: pending

**Decision**: v1 state is decoded through a fallback path and migrated on first restore; unrecognised blobs degrade to empty state.
**Rationale**: Per the `PersistedWindowState` decoder comment, degrading rather than throwing makes every decode call site start fresh instead of failing.
**Approved**: pending

**Decision**: `bestScreen` falls back to AppKit's window screen and main screen rather than the injected provider.
**Rationale**: This is the source's behavior when the window intersects no provided screen; it means tests with mock screens and an off-screen window can receive a real `NSScreen`. Recorded as a known quirk, not a chosen rule.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | Performance |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [data-retention-policy](agenticdevelopercookbook://compliance/privacy-and-data#data-retention-policy) | passed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

separation-of-concerns passes because frame math (`FrameCalculator`), screen matching (`ScreenMatcher`), screen enumeration (`ScreenProvider`), persistence (`WindowStateStorage`) and screen-set bookkeeping (`ScreenManager`) each sit behind their own type, and the math is pure. unit-test-coverage is partial: `FrameCalculatorTests.swift`, `ScreenMatcherTests.swift` and `WindowManagerSimulatedRelaunchTests.swift` cover the math, matching tiers, same-set, resolution-change, new-set, re-dock, oversize, migration and decode paths, but not placement pruning, `resetAllFrames`, visibility gating or the reclamp path. explicit-error-handling fails because storage load and encode failures vanish without a log or return value (the open question on storage-failure-signal). data-integrity is partial for the same reason: an undecodable blob is silently replaced by the next save. graceful-degradation passes because missing specs, missing screens and malformed state all fall back to a centered or default frame instead of failing. state-recovery passes because placements are reloaded per launch and legacy state is migrated. idempotent-operations passes because restoring or saving an unchanged window on unchanged screens rewrites identical placements, and the screen-change handler skips frames that did not change. caching-strategy passes because the write-through cache has a single documented writer and is cleared on every reset. main-thread-freedom passes because all main-actor work is bounded by the window, screen and placement counts and the hot save path avoids a storage read and decode after the first. data-retention-policy passes because placements age out with their screen sets and can be cleared on demand. no-pii-in-logs passes because log lines carry only window ids and set ids.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `WindowFrameManager.swift`, `FrameCalculator.swift`, `PersistedWindowState.swift`, `ScreenFingerprint.swift`, `ScreenInfo.swift`, `RealScreenProvider.swift`, `ScreenMatcher.swift`, `WindowPosition.swift` and their tests |
