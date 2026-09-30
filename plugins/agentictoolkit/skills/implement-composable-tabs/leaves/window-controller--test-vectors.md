<!-- leaf: implement-composable-tabs/window-controller--test-vectors · source: composable-tabs-window-controller.md -->

# ComposableTabsWindowController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-window-controller-001 | window-id | Two `ComposableTabsWindowController`s built for repo ids A and B | Their `windowID(for:)` values are `"projectWindow.A"` and `"projectWindow.B"`; each window's saved frame is independent. |
| composable-tabs-window-controller-002 | default-geometry | Show the window for a project with no prior saved frame | Window frame size is 800×500pt. |
| composable-tabs-window-controller-003 | minimum-size | Attempt to resize the window below 400×300pt | Window stops at 400×300pt. |
| composable-tabs-window-controller-004 | frame-persistence | Move/resize the window, close it, build a new controller for the same project id and show it | New window opens at the previously saved frame. |
| composable-tabs-window-controller-005 | standard-window-controls | Inspect the shown window | Close, miniaturize, and zoom buttons are present and enabled; window is resizable by the user. |
| composable-tabs-window-controller-006 | window-title | Project `displayName` is `"Zorkapp"` | Window title reads `"Zorkapp"`. |
| composable-tabs-window-controller-007 | unified-toolbar | Inspect the shown window's toolbar | `toolbarStyle == .unified`; item order is flexible space, search, help. |
| composable-tabs-window-controller-008 | tab-group-creation | Top and left edges enabled; call `addTabGroup()` | A new group has one member on top and one on left, same title, same working directory; the top member is selected. |
| composable-tabs-window-controller-009 | group-close-scope | Two-member group (top, left); request close on the top member | Both the top and left members are removed. |
| composable-tabs-window-controller-010 | last-group-guard | Exactly one tab group exists; request its close | The group remains; tab count is unchanged. |
| composable-tabs-window-controller-011 | last-edge-guard | Only `.top` is enabled; call `setEdgeEnabled(.top, false)` | `.top` remains enabled. |
| composable-tabs-window-controller-012 | edge-top-up | Two groups exist, only `.top` enabled; enable `.right` | `.right` gains one member per existing group, each seeded from the current active tab's arrangement with fresh node ids — none of the new members reuses a node id from the tab they were seeded from. |
| composable-tabs-window-controller-013 | title-tab-fallback | `tabItemDataSource` is `nil`; a tab titled `"Tab 2"` is created | The tab renders `.title("Tab 2")`. |
| composable-tabs-window-controller-014 | arrangement-mirroring | Two tabs exist; drag a divider in the active tab | The other tab's split adopts the same shape and sizes, with its own node ids preserved. |
| composable-tabs-window-controller-015 | structural-change-persistence | Reorder a tab | `project.persistTabs` is invoked synchronously with the new order. |
| composable-tabs-window-controller-016 | focused-leaf-debounce | Change focused leaf twice within 100ms | Only one persist occurs, at least 250ms after the second change. |
| composable-tabs-window-controller-017 | arrange-titlebar-button | Toggle arrange mode on | Arrange button shows accent tint and `.state == .on`. |
| composable-tabs-window-controller-018 | settings-titlebar-button | Click the settings titlebar button | `ComposableTabsSettingsViewController` is presented as a sheet. |
| composable-tabs-window-controller-019 | arrange-menu-state | Arrange mode enabled for the window; validate the bound menu item | Menu item state is `.on`. |
| composable-tabs-window-controller-020 | search-routing | Search target is pane P; type `"foo"` | `P.search(for: "foo")` is called. |
| composable-tabs-window-controller-021 | search-availability | Search target's `isSearchable == false` | Search field `isEnabled == false`. |
| composable-tabs-window-controller-022 | search-target-clearing | Field contains `"foo"`; search target changes to a different searchable pane | Field text becomes `""`. |
| composable-tabs-window-controller-023 | status-footer-content | Project `"Zork"`, tab `"Main"`, pane title `"main.swift"`, no selection description | Footer reads `"Zork › Main › main.swift"`. |
| composable-tabs-window-controller-024 | help-drawer-toggle | Drawer closed; invoke `toggleHelp()` | Drawer opens; invoking again closes it. |
| composable-tabs-window-controller-025 | help-visibility-persistence | Open help, close window, reopen a window for the same project | Drawer reopens automatically. |
| composable-tabs-window-controller-026 | help-tab-width-persistence | Help never opened in this window; close the window | No `drawer.tab`/`drawer.width` setting is written. |
| composable-tabs-window-controller-027 | help-glyph-state | Open the help drawer | Help button glyph is `questionmark.circle.fill`, tooltip "Hide Help", accessibility description still "Help". |
| composable-tabs-window-controller-028 | tab-activation-focus | Tab T's last focus was leaf L; activate T | First responder becomes L's view, one run-loop turn after activation. |
| composable-tabs-window-controller-029 | pane-teardown-on-close | Window has a terminal pane with a running shell; close the window | The shell is terminated (`paneWillBeRemoved()`/`tearDownPanes()` runs for every pane). |
| composable-tabs-window-controller-030 | divider-flush-on-close | Project has stored tabs; drag a divider, then close the window within 300ms | The dragged thickness is persisted before teardown. |
| composable-tabs-window-controller-031 | reload-persist-suppression | Call `reloadTabs()` on a window with 3 tabs | No intermediate persist writes a partial tab set; exactly one persist reflects the final reloaded state. |
| composable-tabs-window-controller-032 | pane-enumeration-order | Two tabs, each split into two panes on `.top` and `.left` | `allPanes()` returns tab-1's panes (top before left, leaf order), then tab-2's, in the same order on repeated calls. |
| composable-tabs-window-controller-033 | scripting-tab-selection | Set `selectedTabIdentifier` to an existing group's id enabled only on `.bottom` | That group's `.bottom` member becomes active. |
| composable-tabs-window-controller-034 | redundant-tab-selection-guard | Tab T is already active; call `selectTab(id: T)` again | No additional persist, focus-restore, or chrome refresh occurs. |
| composable-tabs-window-controller-035 | edge-set-assignment-order | Only `.top` enabled; set `enabledTabEdgeNames = ["bottom"]` | `.bottom` becomes enabled before `.top` is disabled; final state is `.bottom` only. |
| composable-tabs-window-controller-036 | minimum-size | Inspect the controller's `windowSpec` before the window is ever shown | `windowSpec.minSize == NSSize(width: 400, height: 300)`, matching `self.minSize`. |
| composable-tabs-window-controller-037 | status-footer-content | Project `"Zork"`, active tab's title is `""` (empty), pane title `"main.swift"`, no selection description | Footer reads `"Zork › main.swift"` — the empty tab title contributes no leading `" › "`. |
| composable-tabs-window-controller-038 | search-target | The active pane changes from pane A to pane B, triggering `applySearchAvailability(to:)` | `searchTargetNodeID` becomes B's `nodeID`, matching the field's newly computed `isEnabled`/placeholder. |
