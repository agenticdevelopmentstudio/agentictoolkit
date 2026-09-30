<!-- leaf: implement-window/explorer-view--test-vectors · source: window-explorer-view.md -->

# WindowExplorerView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-explorer-view-001 | header-bar | Render the view | Header shows magnifying-glass icon, "Windows", spacer, refresh button, in that order. |
| window-explorer-view-002 | refresh-button-loading-state | `isLoading == true` | Refresh button `isEnabled == false`. |
| window-explorer-view-003 | initial-refresh | View appears for the first time | `refreshAsync()` is invoked without user action. |
| window-explorer-view-004 | activation-refresh-when-accessibility-missing | `needsAccessibility == true`; app posts `didBecomeActiveNotification` | A new scan starts. |
| window-explorer-view-004b | activation-refresh-when-accessibility-missing | `needsAccessibility == false`; app posts `didBecomeActiveNotification` | No new scan starts. |
| window-explorer-view-005 | external-notification-refresh | Constructed with `refreshNotification = .foo`; `.foo` is posted | A new scan starts. |
| window-explorer-view-005b | external-notification-refresh | Constructed with `refreshNotification = nil`; any notification is posted | No scan starts from this path. |
| window-explorer-view-006 | accessibility-banner-visibility | Scan completes with `needsAccessibility == true` | Banner "Accessibility permission needed for window titles." with "Open Settings" is visible. |
| window-explorer-view-007 | accessibility-banner-action | Click "Open Settings" | `SystemAccessibilityPermission.request()` is called. |
| window-explorer-view-008 | loading-state | `isLoading == true` | `ProgressView` and "Scanning windows..." are shown; list content is hidden. |
| window-explorer-view-009 | empty-state | Scan completes with `appGroups.isEmpty == true` | "No windows found" and the Accessibility hint are shown. |
| window-explorer-view-010 | app-grouping | Windows from apps "beta" and "Alpha" | Sections render in order "Alpha", "beta". |
| window-explorer-view-011 | app-section-header | App "Xcode" with 3 windows, running with an icon | Header shows Xcode's running icon, "Xcode", and the count badge "3". |
| window-explorer-view-011b | app-section-header | App with no matching `NSRunningApplication` icon | Header shows the fallback `app.fill` icon. |
| window-explorer-view-012 | section-select-all-toggle | Section has 2 selectable windows, none selected; toggle select-all on | Both windows are added to `selectedWindowIDs`. |
| window-explorer-view-012b | section-select-all-toggle | Section has 2 selectable windows, both selected; toggle select-all off | Both windows are removed from `selectedWindowIDs`. |
| window-explorer-view-013 | select-all-toggle-partial-selection-state | Section has 2 selectable windows, 1 selected | Select-all toggle shows unchecked. |
| window-explorer-view-014 | select-all-toggle-availability | Section's only windows are all owned by a different context | Select-all toggle `isEnabled == false`. |
| window-explorer-view-015 | window-row | Window with title `""`, frame 800x600 | Row shows "(untitled)" and "800x600". |
| window-explorer-view-016 | window-context-badge | `activeGroupID == B`; window owned by context `A` | Row shows a badge reading context `A`'s name in `A`'s color. |
| window-explorer-view-016b | window-context-badge | `activeGroupID == A`; window owned by context `A` | No context badge is shown. |
| window-explorer-view-017 | window-row-selectability-state | Window owned by a context other than `activeGroupID` | Row toggle `isEnabled == false`; title color is `theme.secondaryText`. |
| window-explorer-view-018 | window-selectability | Window owned by no context | `isSelectable(window) == true`. |
| window-explorer-view-018b | window-selectability | Window owned by context `C`; `activeGroupID == nil` | `isSelectable(window) == false`. |
| window-explorer-view-019 | scan-window-filter | One window 40x40 on-screen from a regular app; one window 200x200 from a background-only app | Both windows are excluded: the 40x40 window by size, the background-app window by `activationPolicy`. |
| window-explorer-view-019b | scan-window-filter | Window's app name is in `appState.settings.hiddenApps` | Window is excluded from the scan result. |
| window-explorer-view-019c | scan-window-filter | Window's id is in `excludeWindowIDs` | Window is excluded from the scan result. |
| window-explorer-view-019d | scan-window-filter | Window exactly 50 points wide (and taller than 50 points), on-screen, from a regular app | Window is excluded (`> 50` is a strict boundary; exactly 50 does not qualify). |
| window-explorer-view-020 | per-process-accessibility-query | Two windows share one pid; `AXUIElementCopyAttributeValue` fails for that pid | Both windows are skipped for AX enrichment; scan proceeds using their original titles. |
| window-explorer-view-021 | accessibility-title-match | CG window frame `(0,0,100,100)`, empty title; AX window frame `(1,1,101,101)`, title "Notes" | Window title becomes "Notes" (each axis differs by < 3pt). |
| window-explorer-view-021b | accessibility-title-match | CG window frame `(0,0,100,100)`; AX window frame `(4,0,100,100)`, title "Notes" | Window title is unchanged (x differs by exactly 4pt, not < 3pt). |
| window-explorer-view-021c | accessibility-title-match | CG window frame `(0,0,100,100)`; AX window frame `(3,0,100,100)`, title "Notes" | Window title is unchanged (x differs by exactly 3pt, which does not satisfy strict `< 3`). |
| window-explorer-view-022 | discovery-mode-stale-selection-pruning | `activeGroupID == nil`; `selectedWindowIDs` contains an id absent from the new scan | That id is removed from `selectedWindowIDs` after the scan completes. |
| window-explorer-view-023 | assignment-mode-selection-preservation | `activeGroupID != nil`; `selectedWindowIDs` contains an id absent from the new scan | That id remains in `selectedWindowIDs` after the scan completes. |
