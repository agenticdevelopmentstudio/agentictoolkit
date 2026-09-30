<!-- leaf: implement-window-management/screen-manager--test-vectors · source: window-management-screen-manager.md -->

# ScreenManager

## Conformance Test Vectors

Derived from `ScreenManagerTests.swift`. Screens: B = uuid `BUILTIN`, name `Built-in`, frame (0,0,1920,1080), main; E = uuid `EXTERNAL`, name `LG Monitor`, frame (1920,0,2560,1440).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| screen-manager-001 | set-identity-order-independent, set-identity-derivation | `identity(of: [B, E])` vs `identity(of: [E, B])` | Equal strings (`BUILTIN+EXTERNAL`) |
| screen-manager-002 | identity-resolution-independent, identity-component-uuid | `identity(of: [B])` vs same uuid at 2560×1440 | Equal |
| screen-manager-003 | set-identity-derivation | `identity(of: [B])` vs `identity(of: [B, E])` | Not equal |
| screen-manager-004 | init-current-set-id, init-upsert-persist, upsert-new, current-set-lookup | Init with [B], clock fixed at t=1,000,000 | `knownSets.count == 1`; `currentSet.id == currentSetID`; `firstSeen == lastSeen == t`; one snapshot with `displayUUID == "BUILTIN"`; storage holds exactly that id |
| screen-manager-005 | touch-in-memory-every-call, upsert-existing | Init at t; clock → t+3600; `touchCurrentSet()` | `firstSeen == t`; `lastSeen == t+3600` |
| screen-manager-006 | init-load-and-prune | Storage has `STALE` (lastSeen now−200 days) and `FRESH` (lastSeen now−1 day); default `maxSetAge`; init with [B] | `knownSetIDs` lacks `STALE`, contains `FRESH` and `currentSetID` |
| screen-manager-007 | classify-no-change | `classifyChange(from: [B,E], to: [B,E])` | `nil` |
| screen-manager-008 | classify-resolution | [B] → B at 2560×1440 | `resolutionChanged` |
| screen-manager-009 | classify-arrangement | [B,E] → [B, E at x = −2560] | `arrangementChanged` |
| screen-manager-010 | classify-set-change-first | [B] → [B,E] | `screenSetChanged(previousSetID: identity([B]), currentSetID: identity([B,E]))` |
| screen-manager-011 | identity-component-name-fallback, classify-resolution | UUID-less `Dock HDMI` 1920×1080 → 2560×1440 | Identities equal; `resolutionChanged` |
| screen-manager-012 | classify-no-pairing, classify-no-change | Two UUID-less `Twin` screens at x=0 and x=1920, unchanged | `nil` |
| screen-manager-013 | classify-no-pairing, classify-arrangement | Twins: second moves from x=1920 to x=3840 | `arrangementChanged` |
| screen-manager-014 | process-real-change, observer-delivery-after-update, known-sets-order | Init [B]; add observer; provider → [B,E]; `processScreenChange()` | Observer receives exactly one `screenSetChanged(solo, docked)`; `currentSetID` read inside the handler equals docked; storage ids = {solo, docked}; `knownSets.first.id == docked` |
| screen-manager-015 | process-spurious-silent | Init [B]; add observer; `processScreenChange()` with no screen change | Observer not called |
| screen-manager-016 | remove-observer | Add then remove observer; provider → [B,E]; `processScreenChange()` | Observer not called |
| screen-manager-017 | reconcile-refresh, touch-persist-throttle | Init [B]; provider → [B,E]; `touchCurrentSet()` (no notification) | `currentSetID == identity([B,E])`; storage contains the docked set |
| screen-manager-018 | reconcile-no-notify, process-diff-baseline | Vector 017 with an observer, then `processScreenChange()` | No call after the touch; after processing, exactly one `screenSetChanged(solo, docked)` |
| screen-manager-019 | reconcile-cheap-guard, upsert-existing | Init [B,E]; call `touchCurrentSet()` 5 times | `currentSetID` unchanged; exactly one `knownSets` entry with that id |
| screen-manager-020 | returning-set-keeps-first-seen | Init [B] at t; t+3600 → [B,E] processed; t+7200 → [B] processed | `currentSetID == solo`; `firstSeen == t`; `lastSeen == t+7200` |
| screen-manager-021 | touch-persist-throttle | Init at t; `touchCurrentSet()` at t (persists); change screens so `screens` differ; `touchCurrentSet()` at t+30 | Second touch updates memory but makes no `saveSets` call; a touch at t+60 calls `saveSets` |
| screen-manager-022 | notification-rearm-idempotent | Call `startObservingScreenChanges()` three times; post `didChangeScreenParametersNotification` after a set change | Observer called exactly once |
| screen-manager-023 | upsert-prune-on-persist | Storage set lastSeen exactly `maxSetAge` before `now()`; init | Set is kept |
| screen-manager-024 | classify-visible-frame-counts | Same frames; one screen's `visibleFrame` height drops by 80 | `resolutionChanged` |
| screen-manager-025 | storage-settings-blob | `SettingsStoreScreenSetStorage` over an empty store; `loadSets()` | `[]` |

Vectors 021–025 are not in `ScreenManagerTests.swift`; they are derived from `touchCurrentSet()`, `startObservingScreenChanges()`, `pruned(_:olderThan:now:)`, `classifyChange(from:to:)` and `ScreenSetsSetting.defaultValue` respectively.
