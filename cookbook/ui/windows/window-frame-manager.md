---
id: 3b602118-9299-483b-bf4d-62c9d525833d
title: Window Frame Manager
domain: agentictoolkit://cookbook/ui/windows/window-frame-manager
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A service that saves and restores window frames per screen set,
  top-left anchored, with pure frame math and screen matching.
platforms:
- swift
- macos
tags:
- window-management
- screens
- persistence
depends-on:
- agentictoolkit://cookbook/ui/windows/screen-manager
related:
- agentictoolkit://cookbook/ui/windows/single-window-controller
references: []
approved-by: ''
approved-date: ''
---

# Window Frame Manager

## Overview

The window frame manager is the toolkit's window-frame persistence service.
It:

- holds a registry of window specs keyed by window id (default size, minimum
  size, default position, and whether frame and visibility persist);
- restores a window's frame on first show from the placement saved for the
  current screen set, or applies the spec's default position;
- saves a window's frame on every move or resize as a placement keyed by the
  current screen-set id, so a laptop that docks at several desks remembers
  one position per desk;
- repositions managed windows when the screen manager reports a screen
  change;
- persists a window's visible/hidden flag independently of its frame.

Positions are anchored at the window's **top-left** corner from the user's
point of view (x grows right, y grows **down** from the top of the screen's
visible area). Restoring in the same screen set on an exactly matching screen
replays the saved absolute offset, so content-driven resizes cannot walk the
window between launches; a relative (travel-fraction) position is used only
when the literal geometry no longer applies.

The frame math is a pure, side-effect-free library also used directly by
content-hugging windows (the content-hugging frame calculation).

The manager is owned by the window manager. Usage per its own documentation:
register specs at startup, restore a window's frame after creating it, and
save a window's frame on move/resize (the single-instance window base does
this from its own move/resize/close callbacks).

## Behavioral Requirements

### Isolation and ownership

- **single-thread-isolation**: The manager MUST be confined to a single
  designated thread; every public operation, the screen-change handler, and
  the injected window-lister callback MUST run on that thread.
- **storage-single-thread-isolation**: The window-state storage protocol
  MUST be confined to that same single designated thread, so storage
  backends are only called from it.
- **concurrency-safe-value-types**: An anchor, a pair of anchors, a
  placement, the persisted window state, the legacy persisted state, a
  screen fingerprint, a window position preset, and a match-quality value
  MUST be safe to pass across concurrency domains (immutable value types).
- **thread-confined-screen-types**: A screen description, the screen
  provider, the live screen description, the live screen provider, and a
  screen-match result MUST remain confined to the caller's own thread rather
  than being safe to hand across concurrency domains, so the compiler keeps
  them in the caller's isolation domain.
- **sole-writer-precondition**: Callers MUST ensure this process is the only
  writer of a given window id's persisted state; the write-through cache is
  safe only because this process is the sole writer of a given id's state,
  and the manager never re-reads storage for an id it has cached.
- **screen-observer-registration**: Construction MUST register one observer
  with the injected screen manager that forwards each screen change to the
  screen-change handler through a weak reference to the manager.
- **start-observing-delegates**: The start-observing operation MUST forward
  to the screen manager's own start-observing operation and add no
  registration of its own.
- **spec-accessor**: A window controller's registered-spec accessor MUST
  read and write the spec registered under the controller's window ID in the
  window frame manager.

### Data shapes

- **window-placement-fields**: A placement MUST be an immutable, comparable
  value holding a screen fingerprint, a top-left X and Y offset from the
  screen's visible-area top-left (y pointing down), a width and height, a
  relative X and Y (0...1 fractions of travel, 0 = left/top), and a saved-at
  timestamp.
- **persisted-state-shape**: The persisted window state MUST hold a map of
  placements keyed by screen-set id, and a read-only, optional legacy
  record.
- **persisted-state-encode**: Encoding the persisted window state MUST write
  only the placements, and MUST NOT encode the legacy record.
- **persisted-state-decode-v2**: Decoding MUST read the placements when
  present and non-null, with the legacy record set to absent.
- **persisted-state-decode-v1**: When placements are absent or null and the
  payload decodes as a legacy record, decoding MUST produce empty placements
  and that record as the legacy value.
- **persisted-state-decode-degrade**: When the payload has neither a usable
  placements value nor a decodable legacy record (for example an empty
  object, a null placements value, or unrelated fields), decoding MUST
  produce empty placements and no legacy record rather than failing.
- **legacy-state-fields**: The legacy record MUST hold a proportional X and
  Y (bottom-left-anchored fractions of travel), a width and height, a screen
  fingerprint, and a saved-at timestamp.
- **fingerprint-fields**: A screen fingerprint MUST be an immutable,
  comparable value holding an optional display identifier, an optional
  localized name, a resolution width and height, and a main-screen flag.
- **fingerprint-from-screen**: Deriving a fingerprint from a live screen
  MUST take the display identifier from the platform's own per-display
  identity (absent when unavailable), the localized name from the screen,
  the resolution from the screen's full frame (not its visible area), and
  the main-screen flag from whether the screen is the current main screen.
- **screen-info-contract**: A screen description MUST expose its frame, its
  visible area, its fingerprint, and its backing scale factor; a description
  that does not supply a backing scale factor MUST report 2.
- **screen-provider-contract**: The screen provider MUST expose the current
  list of screens and the current main screen; the live screen provider
  MUST map these from the platform's own live screen list and main screen.
- **window-position-values**: A window position preset MUST map "center" to
  (0.5, 0.5), "top right" to (0.85, 0.85), and a custom preset to its two
  supplied values, as bottom-left-anchored fractions of travel (0 =
  left/bottom, 1 = right/top).
- **frame-anchors-shape**: An anchor MUST have exactly the values "start"
  (left or top) and "end" (right or bottom); a pair of anchors MUST hold one
  horizontal and one vertical anchor.

### Frame math

- **clamped-length-rule**: The clamped-length calculation MUST return
  `min(max(desired, minLength), max(visibleLength, minLength))`, so a length
  is never below `minLength`, never past the visible length, and
  `minLength` wins when the two disagree.
- **min-size-wins-everywhere**: The absolute-frame, frame-from-relative-
  position, content-hugging-frame, and frame-validation calculations MUST
  all size each axis with the clamped-length calculation, so a minimum
  larger than the screen is kept and the window overhangs.
- **proportional-position**: The proportional-position calculation MUST
  return `(origin - visibleOrigin) / (visibleLength - windowLength)` per
  axis, bottom-left anchored, clamped to -0.1...1.1, and 0.5 on an axis with
  no positive travel.
- **absolute-frame**: The absolute-frame calculation MUST clamp width and
  height with the clamped-length calculation, then set each origin to
  `visibleOrigin + proportion * max(visibleLength - clampedLength, 0)`.
- **default-frame**: The default-frame calculation MUST equal the
  absolute-frame calculation with the spec's default-position fractions,
  default size, and minimum size.
- **top-left-offset**: The top-left-offset calculation MUST return
  `(window.minX - visible.minX, visible.maxY - window.maxY)`.
- **frame-from-top-left**: The frame-from-top-left-offset calculation MUST
  return a frame at `x = visible.minX + offset.x`,
  `y = visible.maxY - offset.y - size.height` with the given size
  unclamped.
- **relative-position**: The relative-position calculation MUST return the
  top-left offset divided by the travel (`visibleLength - windowLength`) per
  axis, clamped to 0...1, and 0.5 on an axis with no positive travel.
- **frame-from-relative**: The frame-from-relative-position calculation
  MUST clamp the size with the clamped-length calculation, then place the
  top-left at `relative * max(visibleLength - clampedLength, 0)` from the
  visible top-left.
- **validate-frame-size**: The frame-validation operation MUST clamp width
  and height with the clamped-length calculation.
- **validate-frame-push**: The frame-validation operation MUST then push the
  origin inside the visible frame in this order: right edge, left edge, top
  edge, bottom edge; a window wider or taller than the visible frame
  therefore ends flush with the left and bottom edges.
- **hug-per-axis**: The content-hugging frame calculation MUST solve each
  axis independently in top-left user coordinates through the same one-axis
  fit rule, and return the fitted frame with the anchors it used.
- **hug-nearest-edge**: With no anchor supplied, an axis MUST hold its end
  edge when the end gap is strictly smaller than the start gap, and its
  start edge otherwise (ties, including a window filling the axis, keep
  start).
- **hug-held-anchor**: When a pair of anchors is supplied, the
  content-hugging frame calculation MUST use those anchors unchanged
  instead of re-deriving them from the frame, and MUST return them.
- **hug-end-anchor-offset**: Holding the end anchor MUST keep
  `offset + length` fixed before on-screen correction; holding the start
  anchor MUST keep `offset` fixed.
- **hug-push-on-screen**: After anchoring, the axis offset MUST be clamped
  to at most `visibleLength - newLength`, then to at least 0, so a window
  that cannot fit ends flush with the start (left or top) edge.
- **hug-length-clamp**: The new axis length MUST be the clamped-length
  calculation applied to the desired length, the minimum length, and the
  visible length.

### Screen matching

- **match-quality-order**: A match quality MUST order "position only" (1) <
  "name only" (2) < "identifier-and-resolution changed" (3) < "exact" (4).
- **match-uuid-tier**: A screen whose display identifier equals the saved
  non-absent display identifier MUST match as exact when both resolution
  components differ by less than 1 point, and as
  identifier-and-resolution-changed otherwise; that screen MUST NOT be
  considered for a lower tier.
- **match-name-tier**: A screen not matched by identifier whose localized
  name equals the saved non-absent localized name MUST match as name-only,
  even when both identifiers are present and differ.
- **match-position-tier**: A screen not matched by identifier or name MUST
  match as position-only when both the saved and current fingerprints have
  the main-screen flag set.
- **match-best**: The best-match search MUST return the candidate with the
  highest quality, the first such candidate in the screen list's order on a
  tie, and nothing when no screen matches.

### Registration

- **register-spec**: The spec-registration operation MUST store the spec
  under the id, replacing any spec previously registered under it.

### Restore

- **restore-tags-window**: The restore operation MUST set the window's
  identifier to a "wm_"-prefixed form of the id before any other step,
  including when it then fails.
- **restore-no-spec**: With no spec registered for the id, restore MUST log
  a warning, center the window geometrically on the main screen's visible
  area, and return false.
- **restore-min-size**: With a spec, restore MUST set the window's minimum
  size to the spec's minimum size.
- **restore-no-persistence**: When the spec does not persist frames, or no
  state is stored for the id, restore MUST apply the spec's default frame on
  the main screen (first screen if there is no main) and return false.
- **restore-touch-set**: Before looking a placement up, restore MUST ask the
  screen manager to refresh its notion of the current screen set and then
  read the current set id.
- **restore-no-screens**: When the provider reports no screens, restore
  MUST center the window geometrically and return false.
- **restore-known-set**: When a placement exists under the current set id,
  restore MUST apply the resolved frame (see placement-resolution rules) and
  return true.
- **restore-known-set-resave**: When that resolution was not an exact
  screen match, restore MUST immediately save the window's frame so the
  placement records the new screen geometry.
- **restore-unknown-set**: When no placement exists for the current set but
  other placements do, restore MUST apply the relative-fallback frame, save
  the window's frame under the current set, and return true.
- **restore-legacy-migration**: When there are no placements and a legacy
  record exists, restore MUST place the window with the absolute-frame
  calculation from the legacy proportions and size on the best-matching
  screen (main, then first screen when none matches), pass it through the
  frame-validation operation, apply it, save the frame as a per-set
  placement, and return true.
- **restore-fallthrough**: When stored state has neither placements nor a
  legacy record, restore MUST apply the spec's default frame and return
  false.

### Placement resolution

- **resolve-screen-choice**: A saved placement MUST be resolved on the
  screen the screen matcher finds for its fingerprint, falling back to the
  main screen, then the first screen.
- **resolve-exact-replay**: On an exact match the frame MUST be rebuilt from
  the saved top-left X/Y and saved size with the frame-from-top-left-offset
  calculation.
- **resolve-relative**: On any non-exact match or no match, the frame MUST
  be rebuilt from the saved relative X/Y and saved size with the
  frame-from-relative-position calculation and the spec's minimum size.
- **resolve-validate**: Every resolved frame MUST pass through the
  frame-validation operation against the chosen screen's visible area and
  the spec's minimum size.
- **relative-fallback-source**: The relative fallback MUST use the
  placement with the latest saved-at timestamp, placed on the main screen
  (first screen when there is no main), through the frame-from-relative-
  position calculation then the frame-validation operation; it MUST produce
  nothing when there are no placements.

### Save

- **save-guard-spec**: The save operation MUST do nothing when no spec is
  registered for the id or the spec does not persist frames.
- **save-touch-first**: Save MUST ask the screen manager to refresh its
  notion of the current screen set and read the current set id before
  choosing the screen to fingerprint, so a move the platform delivers before
  the screen-change notification is filed under the live set.
- **save-best-screen**: Save MUST fingerprint the screen that contains the
  largest area of the window's frame intersected with each screen's visible
  area; with no intersecting screen it MUST fall back to the window's own
  screen, then the system main screen, both read directly from the platform
  rather than the injected provider.
- **save-no-screen**: When no screen can be chosen, save MUST return
  without writing.
- **save-placement-values**: The placement written MUST carry the chosen
  screen's fingerprint, the window's top-left offset and relative position
  computed against that screen's visible area, the window's current width
  and height, and a saved-at timestamp equal to the screen manager's current
  time.
- **save-preserves-other-sets**: Save MUST rebuild state from the cached (or
  freshly loaded) placements, replace only the current set's entry, and
  keep other sets' entries subject to pruning.
- **save-drops-legacy**: The state written by save MUST have no legacy
  record, so the first save consumes a decoded legacy record.
- **save-prune**: Save MUST keep a placement only when its key is the
  current set id, or its key is one of the screen manager's known set ids,
  or its saved-at timestamp is later than the current time minus the
  maximum set age.
- **save-write-through**: Save MUST update the in-memory cache for the id
  and then write to storage exactly once.

### Cache

- **cache-read-through**: Restore and screen-change handling MUST read an
  id's state from the in-memory cache when present, and otherwise load it
  from storage and cache the result.
- **cache-miss-not-cached**: A load that returns nothing MUST leave the
  cache without an entry for the id, so the next read loads from storage
  again.

### Reset and clear

- **reset-frame**: The reset-frame operation MUST remove the id's stored
  state, clear its cache entry, and apply the spec's default frame, or
  center the window geometrically when no spec is registered.
- **reset-all-frames**: The reset-all-frames operation MUST remove stored
  state for every registered id and empty the whole cache; it MUST NOT
  reposition any window and MUST NOT remove stored state for ids that are
  not registered.
- **clear-saved-state**: The clear-saved-state operation MUST remove the
  id's stored state and cache entry without moving any window.
- **reset-leaves-visibility**: The reset-frame, reset-all-frames, and
  clear-saved-state operations MUST NOT touch persisted visibility.

### Visibility

- **load-visibility**: The load-visibility operation MUST return nothing
  when no spec is registered or the spec does not persist visibility, and
  otherwise the storage's value (nothing when never saved).
- **save-visibility**: The save-visibility operation MUST write the flag
  only when a spec is registered that persists visibility, and otherwise do
  nothing.
- **clear-visibility**: The clear-visibility operation MUST remove the
  stored flag without consulting the spec.
- **visible-window-ids**: The visible-window-ids operation MUST return the
  storage's list of ids whose saved visibility is true.

### Default placement

- **default-position-screen**: Applying a default position MUST use the
  main screen's visible area, falling back to the first screen, and MUST
  center geometrically when there are no screens.
- **geometric-center**: Geometric centering MUST set the window origin to
  `visible.origin + (visible.size - window.size) / 2` on each axis, keeping
  the window's size; with no screen at all it MUST fall back to the
  platform's own default window-centering placement.

### Screen-change handling

- **change-no-screens**: On a screen change with no screens, the handler
  MUST do nothing.
- **change-window-lookup**: The handler MUST snapshot the live windows once
  per event, key them by the id after the "wm_" identifier prefix, and
  consider every registered spec whose window is present, visible or
  hidden.
- **change-known-placement**: For a window with a placement under the
  current set, the handler MUST apply the resolved frame, for every kind of
  screen change.
- **change-new-set-fallback**: For a screen-set change where the window has
  no placement under the current set but has other placements, the handler
  MUST apply the relative-fallback frame and then save the window's frame.
- **change-reclamp**: Every other managed window (no persisted state, frame
  persistence off, or a non-set change with no placement) MUST keep its
  current frame pushed on screen through the frame-validation operation on
  its best screen.
- **change-apply-only-real**: The handler MUST skip re-applying the frame
  when the validated frame equals the window's current frame.
- **change-animate-visible**: The handler MUST animate the frame change only
  when the window is visible.
- **change-resave-by-delegate**: Apart from the new-set fallback, the
  handler MUST NOT save frames itself; re-saving after a reposition relies
  on the window controller's own move/resize callbacks.

### Persistence durability

- **storage-default-backend**: The default storage backend MUST store each
  id's state as JSON under a key of the form `WindowState_<id>` and
  visibility as a boolean under a key of the form `WindowVisible_<id>`,
  both qualified by the window-state namespace, so state survives app
  relaunch.
- **storage-failure-signal**: NEEDS REVIEW: Not implemented in source. The
  window-state storage protocol has no error channel; the default backend
  returns nothing for undecodable data (restore then applies the default
  frame and the next save overwrites the blob) and silently skips a write
  whose encoding fails, with no log. Settle by deciding whether load/save
  failures must be logged or surfaced to the window frame manager.

## Appearance

Not applicable — this is a window-frame persistence service and frame-math
library, not a visual component.

## States

Not applicable — this is a window-frame persistence service and frame-math
library, not a visual component.

## Accessibility

Not applicable — this is a window-frame persistence service and frame-math
library, not a visual component.

## Conformance Test Vectors

Screens are bottom-left-origin rectangles `(x, y, width, height)`. Vectors
marked with a test name come from `FrameCalculatorTests.swift`,
`ScreenMatcherTests.swift` or `WindowManagerSimulatedRelaunchTests.swift`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wfm-001 | proportional-position | Visible (0,0,1920,1080); window (760,340,400,400) | (0.5, 0.5) (`testProportionalPositionCenter`) |
| wfm-002 | proportional-position | Window (0,0,1920,1080) fills visible (0,0,1920,1080) | (0.5, 0.5) exactly (`testProportionalPositionWindowFillsScreen`) |
| wfm-003 | absolute-frame | Proportions (0.5, 0.5), size 600×480, visible (0,0,1920,1080), min 100×100 | (660, 300, 600, 480) (`testAbsoluteFrameCenter`) |
| wfm-004 | default-frame, window-position-values | Spec default 340×300, min 280×120, top right; visible (0,0,1920,1080) | origin ≈ (1342, 663) (`testDefaultFrameTopRight`) |
| wfm-005 | top-left-offset | Visible top-left and window top-left 60 right and 40 down of it | offset (60, 40) (`testTopLeftOffsetMeasuresDownFromVisibleTop`) |
| wfm-006 | relative-position | Window with no travel on either axis | (0.5, 0.5) (`testRelativePositionCenteredWhenNoTravel`) |
| wfm-007 | frame-from-relative, clamped-length-rule | Size larger than an 800×600 visible frame, small min | size 800×600 (`testFrameFromRelativePositionClampsSizeToScreen`) |
| wfm-008 | validate-frame-push | Frame hanging off the right of (0,0,1920,1080), width 400 | maxX 1920, width 400 (`testValidateFramePushesFromRight`) |
| wfm-009 | min-size-wins-everywhere | Visible (0,0,150,60), min 200×100, desired 10×10 through the absolute-frame, frame-from-relative-position, frame-validation, and content-hugging-frame calculations | every result has size 200×100 (`testEveryPathKeepsAMinimumLargerThanTheScreen`) |
| wfm-010 | hug-nearest-edge, hug-per-axis | Visible (0,0,1600,1000), min 200×100; window left 400 top 300, 500×300; desired 560×420, no anchors | minX 400, maxY unchanged, size 560×420 (`testContentHuggingGrowsDownAndRightWhenNowhereNearAnEdge`) |
| wfm-011 | hug-push-on-screen | Same visible; window left 40 top 40, 500×300; desired 1600×300 | width 1600, minX 0 (`testAWindowNearTheLeftEdgeGrowsRightwardWithoutMoving`) |
| wfm-012 | hug-held-anchor | Window left 600 top 300, 400×300; grow to 600×300 with no anchors supplied, then shrink to 400×300 passing the returned anchors | first step keeps minX; second step returns the original frame (`testAWindowInTheMiddleComesBackToWhereItStarted`) |
| wfm-013 | hug-nearest-edge | Same two steps but anchors re-derived (none supplied) on the second step | second step minX 800 (`testRereadingTheAnchorEachStepWalksTheWindow`) |
| wfm-014 | hug-held-anchor, hug-end-anchor-offset | Window left 1060 top 300, 500×300; anchors (end, start); desired 200×300 | maxX unchanged; returned anchors equal (end, start) (`testAHeldEndAnchorOutranksWhereTheWindowNowSits`) |
| wfm-015 | hug-nearest-edge | Window left 1060 top 20, 500×300; desired 520×320; no anchors supplied | anchors (end, start) (`testAFitReportsTheAnchorsItChose`) |
| wfm-016 | hug-push-on-screen, min-size-wins-everywhere | Visible and current (0,0,150,60), min 200×100, desired 10×10 | size 200×100, minX 0, maxY 60 (flush top) (`testAWindowKeepsItsMinimumOnAScreenTooSmallForIt`) |
| wfm-017 | match-uuid-tier | Saved fingerprint identifier and resolution equal a current screen's | quality exact (`testExactMatchByUUIDAndResolution`) |
| wfm-018 | match-uuid-tier | Same identifier, different resolution | quality identifier-and-resolution-changed (`testUUIDMatchWithResolutionChange`) |
| wfm-019 | match-name-tier | Different identifiers, same localized name | quality name-only (`testNameMatchWhenUUIDDiffers`) |
| wfm-020 | match-position-tier | No identifier or name match; saved and current both main | quality position-only (`testPositionMatchMainScreen`) |
| wfm-021 | match-best | No screen matches on any tier | nothing (`testNoMatchReturnsNil`) |
| wfm-022 | match-best, match-uuid-tier | One screen matches by identifier with changed resolution, another by name | the identifier match, quality identifier-and-resolution-changed (`testPreferUUIDOverName`) |
| wfm-023 | save-placement-values, restore-known-set, resolve-exact-replay | Save window (300,400,600,300) on a 1920×1080 screen; new manager on same storage and screens; restore | returns true; frame (300,400,600,300) (`testSameSetRestoreIsExactAfterRelaunch`) |
| wfm-024 | resolve-relative | Save (1320,600,600,480) on a 1920×1080 display; relaunch with the same display at 2560×1440; restore | returns true; frame (1960,960,600,480) (`testRestoreAfterResolutionChangeUsesRelativePosition`) |
| wfm-025 | restore-known-set-resave | As wfm-024 with a window saved at (300,500,600,300) | stored placement fingerprint resolution becomes 2560×1440 (`testNonExactRestoreReSavesPlacementWithNewResolution`) |
| wfm-026 | restore-unknown-set, relative-fallback-source, save-preserves-other-sets | Save centered (2900,480,600,480) on an external-only set; relaunch on a built-in 1920×1080 set; restore | frame (660,300,600,480); storage holds placements for both set ids (`testUnknownScreenSetFallsBackToMainScreenAndSavesPlacement`) |
| wfm-027 | save-preserves-other-sets | Save different frames under the undocked and docked sets; restore under each | each set restores its own frame exactly (`testEachScreenSetRemembersItsOwnPlacement`) |
| wfm-028 | resolve-validate, clamped-length-rule | Save 1200×900 on a 2560×1440 display; relaunch with the same display at 800×600 | size equals the 800×600 visible frame and the frame lies inside it (`testOversizeSavedWindowIsClampedToShrunkenScreenOnRelaunch`) |
| wfm-029 | persisted-state-decode-v1, restore-legacy-migration, save-drops-legacy | Legacy record (proportions 0.7/0.3, 600×480, main built-in 1920×1080); restore | origin ≈ (924, 180), size 600×480; stored state has no legacy record and a placement under the current set (`testLegacyV1StateMigratesToPlacementOnRestore`) |
| wfm-030 | persisted-state-decode-degrade | Decode an empty object, a null placements value, and an object with only unrelated fields | no failure; empty placements; no legacy record (`testEmptyOrMalformedJSONDecodesToEmptyPlacementsInsteadOfThrowing`) |
| wfm-031 | persisted-state-encode, persisted-state-decode-v2 | Encode state with one placement under key `SET`, decode | placements equal the original; no legacy record (`testV2StateSurvivesJSONRoundTrip`) |
| wfm-032 | restore-no-spec, restore-tags-window | Restore for an unregistered id | returns false; identifier `wm_<id>`; window geometrically centered on the main visible frame |
| wfm-033 | restore-no-persistence | Spec with frame persistence off; restore | returns false; frame equals the default frame on the main screen; minimum size equals the spec's |
| wfm-034 | save-guard-spec | Save for an unregistered id, and for a spec with frame persistence off | storage is never written to |
| wfm-035 | save-prune | Stored placement under a set id unknown to the screen manager, saved-at older than the maximum set age; save under the current set | the old placement is absent from the written state |
| wfm-036 | load-visibility, save-visibility | Spec without visibility persistence; the save-visibility operation invoked with true, then the load-visibility operation | storage untouched; the load-visibility operation returns nothing |
| wfm-037 | reset-all-frames | Stored state for a registered id and an unregistered id; the reset-all-frames operation | registered id's state removed; unregistered id's state remains; no window moved |
| wfm-038 | change-apply-only-real | Screen change where the validated frame equals the window's current frame | the frame is not re-applied |
| wfm-039 | change-new-set-fallback | A screen-set change to a set with no placement for a window that has another set's placement | window moved to the relative-fallback frame and a placement saved under the new set |

## Edge Cases

- **Null and empty input**: An unregistered id MUST restore to the geometric
  center and return false; save and visibility writes for it MUST be
  no-ops. An empty screen list MUST make restore center the window and
  return false, make the screen-change handler do nothing, and make save
  fall back to the window's own screen or the main screen (read directly
  from the platform), writing nothing if both are absent. An empty or
  unrecognised stored blob MUST decode to empty placements (MUST).
- **No placements left after decode**: Stored state with empty placements
  and no legacy record MUST restore to the spec's default frame and return
  false (MUST).
- **Boundary values**: A window exactly equidistant from both edges MUST
  keep its start anchor; a window filling an axis MUST report relative
  position 0.5 and proportional position 0.5 on that axis; resolutions
  within 1 point of the saved value MUST count as exact (MUST).
- **Minimum larger than the screen**: Every sizing path MUST keep the
  minimum size and overhang; the content-hugging frame calculation leaves
  the window flush top-left while the frame-validation operation leaves it
  flush left and bottom, because of their different push orders (MUST,
  documented quirk).
- **Out-of-range stored fractions**: The saved relative X/Y are not clamped
  on restore; a hand-edited value outside 0...1 is placed off the travel
  range and then pulled on screen by the frame-validation operation (MUST,
  as implemented).
- **Stale absolute offset**: A placement matched non-exactly (resolution
  change, name-only or main-only match) MUST NOT replay the absolute
  offset; it MUST use the relative position (MUST).
- **Screen not matched at all**: A placement whose fingerprint matches no
  current screen MUST resolve on the main screen, then the first screen,
  via its relative position (MUST).
- **Display change delivered after a move**: A window-move notification
  that arrives before the platform's screen-parameters-changed notification
  MUST be filed under the live set because save refreshes the current
  screen set first (MUST;
  `testMoveDuringUndeliveredScreenChangeDoesNotClobberTheDockedPlacement`).
- **Placements of aged-out sets**: A placement whose set is unknown to the
  screen manager and older than the maximum set age MUST be dropped at the
  next save of that window; one saved more recently MUST survive (MUST).
- **Duplicate registration**: Registering the same id twice MUST keep only
  the latest spec (MUST).
- **Hidden windows on screen change**: Loaded but hidden managed windows
  MUST be repositioned without animation (MUST).
- **Windows not tagged**: Windows whose identifier lacks the `wm_` prefix,
  or whose id has no registered spec, MUST be ignored by the screen-change
  handler (MUST).
- **Concurrent access**: All operations are serialized on the single
  designated thread, so no two calls interleave. Screen-change
  repositioning triggers save calls, made from the window controller's own
  move/resize callbacks, synchronously within the same turn on that thread
  (MUST).
- **Cross-process writers**: A second process writing the same id's state
  is outside the contract; the cache would not see its writes (per
  sole-writer-precondition).
- **Error states**: Storage load and save failures are not reported by the
  protocol (see the open question on storage-failure-signal). A missing
  spec on restore is logged at warning level.
- **Offline or disconnected state**: Not applicable; the component performs
  no network I/O.
- **Cancellation and timeouts**: Not applicable; every operation is
  synchronous and has no timeout or cancellation path.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Screen provider | The screen provider | The live screen provider | Source of live screens and the main screen. |
| Storage | The window-state storage protocol | The default storage backend | Persistence for per-window state and visibility. |
| Screen manager | The screen manager | none (required) | Supplies the current screen-set id, known set ids, maximum set age, the current time, a refresh operation, and screen-change events. |
| Window lister (internal) | A callback returning the live window list | The platform's own list of app windows | Source of live windows for screen-change repositioning; injectable in tests. |
| Minimum size / default size / default position (window spec) | Size / Size / window position preset | per spec | Sizing floor and default frame. |
| "Persists frame" (window spec behavior) | option bit | on (in the default behavior set) | Enables frame save/restore for the id. |
| "Persists visibility" (window spec behavior) | option bit | on (in the default behavior set) | Enables visibility save/load for the id. |
| State-key prefix (default storage backend) | Text | `"WindowState_"` | Key prefix for state blobs (namespaced by the window-state namespace). |
| Visibility-key prefix (default storage backend) | Text | `"WindowVisible_"` | Key prefix for visibility flags (namespaced by the window-state namespace). |
| Anchors (content-hugging frame calculation) | An optional pair of anchors | none | Anchors carried across steps of one resize gesture; none picks them by nearest edge. |

## Deep Linking

Not applicable: the component exposes no routes or URL handling; it is
driven by direct calls and screen-change events from the screen manager.

## Localization

Not applicable: the component produces no user-facing strings; its only
text is developer log messages in English.

## Accessibility Options

Not applicable: the component renders nothing, so Reduce Motion, Increase
Contrast and Differentiate Without Color have no effect on it (screen-change
animation follows only window visibility).

## Feature Flags

Not applicable: the source reads no feature flag; persistence is opted into
per window through the window spec's behavior options.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Per window id and screen set, the window's frame
  (top-left offset, size, relative position), a save timestamp, and the
  screen's display identifier, localized name, resolution and main flag;
  per window id a visible/hidden flag.
- **Storage**: JSON blobs under keys of the form `WindowState_<id>` and
  booleans under keys of the form `WindowVisible_<id>`, each prefixed by the
  window-state namespace, in the platform's own local preferences store
  (default backend).
- **Transmission**: None; nothing leaves the device.
- **Retention**: A placement is kept until its screen set is unknown to the
  screen manager and older than the maximum set age, then dropped at the
  window's next save; the reset-frame, reset-all-frames, and
  clear-saved-state operations remove state on demand.

## Logging

Subsystem: the app's main bundle identifier | Category: `WindowFrameManager`

| Event | Level | Message |
|-------|-------|---------|
| Restore with no registered spec | warning | `WindowFrameManager: no spec for '<id>'` |
| Restore from a same-set placement | debug | `WindowFrameManager: restored '<id>' exact=<Bool>` |
| Restore into a new screen set | debug | `WindowFrameManager: placed '<id>' in new set '<setID>'` |
| Legacy v1 migration | debug | `WindowFrameManager: migrated legacy state for '<id>'` |
| Reposition after a screen change | debug | `WindowFrameManager: repositioned '<id>' after screen change` |

Ids and set ids are logged with public privacy. Saves, resets, visibility
calls and storage failures are not logged.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. SwiftUI's `.defaultPosition`,
  `.defaultSize` and scene restoration persist frames per scene but not per
  screen set; a SwiftUI port keeps this `@MainActor` class and reaches the
  underlying `NSWindow` (via an `NSViewRepresentable` window accessor) to
  call `restoreFrame` and `saveFrame`. `FrameCalculator` ports unchanged as
  pure functions on `CGRect`.
- **Compose**: Compose Desktop's `WindowState` (`position`, `size`) is the
  starting point, with `GraphicsEnvironment.getScreenDevices()` and
  `GraphicsConfiguration.bounds` / `Toolkit.getScreenInsets` for visible
  frames; persist with DataStore plus `kotlinx.serialization`, run on
  `Dispatchers.Main`. AWT coordinates are top-left-origin, so the top-left
  offset needs no y flip. Android phones have no free-floating windows; the
  math applies only to desktop and freeform modes.
- **React/Web**: Browsers expose window placement only for popups
  (`window.open` features, `moveTo` / `resizeTo`) and the Window Management
  API (`getScreenDetails()` with `availLeft` / `availTop` / `availWidth` /
  `availHeight`); persist with `localStorage` and `JSON.stringify`. No
  display UUID exists, so screen matching falls back to label and geometry;
  the pure frame math ports directly to TypeScript.
- **AppKit / UIKit**: Source files: `WindowFrameManager.swift`
  (`NSWindow.setFrame(_:display:animate:)`, `identifier`, `minSize`,
  `os.Logger` via `Loggable`), `FrameCalculator.swift` (pure `NSRect` math,
  bottom-left origin converted to top-left user coordinates),
  `PersistedWindowState.swift` (custom `Codable` with v1 fallback),
  `ScreenFingerprint.swift` (`CGDisplayCreateUUIDFromDisplayID` from
  `NSScreenNumber`), `ScreenInfo.swift`, `RealScreenProvider.swift`
  (`NSScreen.screens` / `NSScreen.main`), `ScreenMatcher.swift`,
  `WindowPosition.swift`. UIKit has no movable windows on iPhone; on iPad
  and visionOS use `UIWindowScene` geometry requests instead.
- **WinUI 3**: Start from `Microsoft.UI.Windowing.AppWindow` (`Position`,
  `Size`, `Move`, `Resize`, `MoveAndResize`, and the `Changed` event with
  `DidPositionChange` / `DidSizeChange` in place of the move/resize delegate
  hooks) and `DisplayArea.GetFromWindowId` / `DisplayArea.FindAll()`
  (`WorkArea` for the visible frame, `OuterBounds` for the resolution,
  `DisplayId` for identity). Windows coordinates are top-left-origin in
  physical pixels, so `topLeftOffset` needs no y flip but must account for
  DPI scaling (`XamlRoot.RasterizationScale`). Enforce `minSize` with
  `OverlappedPresenter` plus `PreferredMinimumWidth` /
  `PreferredMinimumHeight`. Keep the manager on the UI thread
  (`DispatcherQueue`), model `PersistedWindowState` as C# records serialised
  with `System.Text.Json` (a custom `JsonConverter` for the v1 fallback),
  and store them in `Windows.Storage.ApplicationData.Current.LocalSettings`
  (8 KB per value; use a `LocalFolder` file if many sets accumulate).
  Subscribe to display changes through `WM_DISPLAYCHANGE` /
  `WM_SETTINGCHANGE` or the `ScreenManager` port's event, and use
  `Task`/`async` only for file-based storage since the source is
  synchronous.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `WindowFrameManager.swift`, `FrameCalculator.swift`, `PersistedWindowState.swift`, `ScreenFingerprint.swift`, `ScreenInfo.swift`, `RealScreenProvider.swift`, `ScreenMatcher.swift`, `WindowPosition.swift` and their tests |
