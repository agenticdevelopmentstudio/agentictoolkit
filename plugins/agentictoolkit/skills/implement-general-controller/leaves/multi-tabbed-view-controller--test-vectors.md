<!-- leaf: implement-general-controller/multi-tabbed-view-controller--test-vectors · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| multi-tabbed-001 | top-edge-enabled-by-default | Construct a new `MultiTabbedViewController` | `isEdgeEnabled(.top) == true`; `isEdgeEnabled(.right/.bottom/.left) == false` |
| multi-tabbed-002 | edge-toggle-updates-bar-visibility | View loaded; call `setEdgeEnabled(.bottom, true)` | The bottom edge's tab bar becomes visible (no longer hidden) in the view hierarchy; the edge layout constraints are rebuilt |
| multi-tabbed-003 | hidden-edge-retains-tabs | Add a tab on `.bottom`; disable `.bottom`; re-enable `.bottom` | `tabs(on: .bottom)` returns the same tab throughout, and its button reappears once re-enabled |
| multi-tabbed-004 | edge-state-change-triggers-fallback-activation | Active tab lives on `.top`; call `setEdgeEnabled(.top, false)` | Fallback activation runs; `activeTabID` changes (to another tab or `nil`) |
| multi-tabbed-005 | disabled-edge-excluded-from-layout | `.left` disabled | The content area's leading edge is pinned directly to the view's own leading edge, not to the left bar (which is hidden and unconstrained) |
| multi-tabbed-006 | bar-spans-content-perpendicular-dimension | `.top` enabled | The top bar spans the full width of the content area: its leading and trailing edges align with the content area's leading and trailing edges |
| multi-tabbed-007 | add-tab-appends-to-edge | Edge already has 2 tabs; call `addTab(newTab, on: edge)` | `tabs(on: edge).last?.id == newTab.id` |
| multi-tabbed-008 | insert-tab-clamps-index | Edge has 2 tabs; call `insertTab(tab, at: 99, on: edge)` | Tab is inserted at index `2` (the end), not out of bounds |
| multi-tabbed-009 | remove-tab-locates-owning-edge | Tab lives on `.right`; call `removeTab(id: tab.id)` with no edge argument | `tabs(on: .right)` no longer contains the tab |
| multi-tabbed-010 | move-tab-clamps-index-within-edge | Edge has 3 tabs; call `moveTab(id: firstID, to: 50, on: edge)` | Tab moves to index `2` (the last valid index) |
| multi-tabbed-011 | move-tab-no-op-when-index-unchanged | Tab already at index `1`; call `moveTab(id:, to: 1, on:)` | Tab list order is unchanged; `didReorderTab` delegate callback is not invoked |
| multi-tabbed-012 | rename-tab-title-items-only | Call `renameTab(id:, title: "New")` on a `.viewController` tab | `tabs(on: edge).first { $0.id == id }?.title` is unchanged |
| multi-tabbed-013 | set-tab-item-preserves-mounted-content | Active tab's item is replaced via `setTabItem(id:, item:)` | The tab's `viewController` (and, if it is the active tab, the mounted center content) is unchanged |
| multi-tabbed-014 | single-active-tab-invariant | Tabs exist on 2 enabled edges with unrelated groups; select a tab on `.top`, then select a different (ungrouped) tab on `.left` | After the second selection, `activeTabID` names only the `.left` tab; the `.top` bar shows no tab as selected |
| multi-tabbed-015 | tab-defaults-to-own-group | Construct `Tab(title:, viewController:)` with no `groupID` | `tab.groupID == tab.id` |
| multi-tabbed-016 | group-siblings-share-selection-across-edges | Top and bottom tabs share a `groupID`; select the bottom one | The top bar shows its own member of the group (`topTab`) as selected, even though the bottom tab is the one whose content is shown |
| multi-tabbed-017 | ungrouped-tab-shows-no-selection-on-other-edges | Top tab has no shared group with any bottom tab; select the top tab | The bottom bar shows no tab as selected |
| multi-tabbed-018 | first-tab-on-enabled-edge-auto-activates | Edge has no tabs and is enabled; call `addTab(tab, on: edge)` | `activeTabID == tab.id` |
| multi-tabbed-019 | active-tab-removal-neighbor | Active tab at index 1 of 3 on its edge is removed | The tab now at index 1 (the old index 2) becomes active |
| multi-tabbed-020 | removing-last-tab-on-edge-triggers-fallback | Active tab is the only tab on its edge; call `removeTab(id:)` | Fallback activation runs |
| multi-tabbed-021 | fallback-prefers-active-group | Active tab's group has a sibling on another enabled edge; a tab unrelated to the group sits first on the first enabled edge | Fallback activates the group sibling, not the unrelated first tab |
| multi-tabbed-022 | fallback-clears-when-nothing-found | No enabled edge has any tab; fallback runs | `activeTabID == nil` |
| multi-tabbed-023 | active-tab-change-notification | Last tab on the last enabled edge is removed | Delegate receives `activeTabDidChange(nil, on: nil)` |
| multi-tabbed-024 | select-tab-refuses-non-member-id | Call `selectTab(id: unrelatedID, on: edge)` where `unrelatedID` is not in `edge`'s tabs | `activeTabID` is unchanged |
| multi-tabbed-025 | center-shows-active-tab-view-controller | A tab is activated | The shared content area mounts the active tab's view controller as its sole child view |
| multi-tabbed-026 | center-falls-back-to-main-content | No tab active; `mainContentViewController` is set | The shared content area mounts `mainContentViewController`'s view |
| multi-tabbed-027 | center-mount-skips-redundant-remount | `refreshCenterContent()` called twice in a row with the same resolved target | The mounted controller's view is not removed and re-added on the second call |
| multi-tabbed-028 | content-insets-applied-to-mounted-view | `contentInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)` | The mounted content sits 4pt in from the content area's top and leading edges, and 4pt in from its bottom and trailing edges (inset inward) |
| multi-tabbed-029 | center-outline-reflects-color-override-or-fallback | `centerOutlineColor = nil` | The content area's visible border renders in the resolved palette's `.outline` color |
| multi-tabbed-030 | preferred-content-size-change-refreshes-every-bar | Hosted controller on `.left` changes `preferredContentSize`; `preferredContentSizeDidChange(for:)` fires | Every edge's bar — not only `.left`'s — recalculates its thickness to reflect its own hosted items' current preferred content size |
| multi-tabbed-031 | tab-bar-orientation-follows-edge | `TabBarView(edge: .right)` built | The right bar lays out its items down a vertical column, not across a row |
| multi-tabbed-032 | tab-bar-thickness-floor-and-growth | `.left` bar hosts an item with `preferredContentSize.width == 200` | The left bar's thickness (frame width) grows to `206pt` (200 + 6pt padding), above its `140pt` floor |
| multi-tabbed-033 | tab-item-padding-flush-to-content-side | `.top` bar built | The top bar's first item sits `6pt` from the bar's outer (top) edge; on the workspace-facing (bottom) edge, items sit flush with a `0pt` gap |
| multi-tabbed-034 | tab-button-selection-style | `TabButton.isHighlighted = true` | The selected tab's background fills with the `.selection` palette color, and its title text switches to the `.selectionText` role |
| multi-tabbed-035 | hosted-item-highlight-follows-selection | A `.viewController` tab conforming to `TabBarHostedItem` is selected | Its `isHighlighted == true` |
| multi-tabbed-036 | close-icon-hit-region | `mouseDown` at a point inside the close button's frame | The close action fires, closing that tab; the click does not also select the tab |
| multi-tabbed-037 | clicking-hosted-item-selects-its-tab | Real `mouseDown` hit-tested onto a hosted item's interior label | The hosted tab becomes selected |
| multi-tabbed-038 | vertical-edge-cards-overlap-and-order-by-distance | `.left` bar has 3 hosted items; the middle one is selected | The middle item's neighbors are drawn and hit-tested behind it: it visually overlaps and receives clicks over both neighbors |
| multi-tabbed-039 | cross-edge-move-preserves-foreign-controller | A hosted controller is moved from `.left`'s bar to `.right`'s bar (insert-then-remove); `.left`'s bar reconciles afterward | The controller's `parent` and mounted view are unaffected by `.left`'s reconciliation |
| multi-tabbed-040 | new-tab-hook-delegates-without-mutating | Call `newTab(nil)` with a delegate installed | `multiTabbedViewControllerNeedsNewTab(_:)` is invoked; no tab is added by this call itself |
| multi-tabbed-041 | explicit-group-override | Construct two `Tab` instances with the same explicit `groupID`, one per edge; select one | The other tab, sharing the same `groupID`, is also shown as selected on its own edge's bar |
| multi-tabbed-042 | Null/empty input (Edge Cases) | Call `tabs(on: edge)` for an edge with no tabs ever added | Returns `[]`, without trapping |
| multi-tabbed-043 | Error states (Edge Cases) | Set `delegate`, then let it deallocate (no strong reference remains); call `removeTab(id:)` for the last tab on an edge | The tab is removed from `tabs(on: edge)` (the mutation completes); no crash occurs even though `delegate` is now `nil` |
| multi-tabbed-044 | first-tab-on-enabled-edge-auto-activates | Edge has no tabs and is enabled; call `insertTab(tab, at: 0, on: edge)` directly (not `addTab`) | `activeTabID == tab.id` |
