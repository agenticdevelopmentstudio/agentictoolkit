<!-- leaf: implement-window-management/window-frame-manager--test-vectors · source: window-management-window-frame-manager.md -->

# WindowFrameManager

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
