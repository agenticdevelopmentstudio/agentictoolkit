<!-- leaf: implement-general-controller/split-view-controller--test-vectors-part-2 · source: split-view-controller.md -->

# SplitViewController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| split-view-controller-045 | propagates-navigation-change-upward | This instance is nested inside an outer split, selection changes | Both this instance's `onNavigationChange` and the outer split's navigation-change handling fire |
| split-view-controller-046 | reports-current-panel-from-detail-container | Show panel `a` via `show(_:)` | `currentPanel === a` |
| split-view-controller-047 | reports-effective-help-from-current-panel | `currentPanel.effectiveHelpContent` is non-`nil` | `effectiveHelp` equals that same value |
| split-view-controller-048 | refreshes-help-through-detail-chrome-and-outward | This instance is nested, call `refreshHelp()` | `panelHost.setHelp(_:)` is called with `effectiveHelp`; the outer split's `refreshHelp()` is also called |
| split-view-controller-049 | hosts-self-managing-panels-without-wrapper | Show a panel that is itself a `SplitViewController` | `panelHost`'s content is that panel's view directly, no `PanelScrollView` wrapper |
| split-view-controller-050 | wraps-other-panels-in-scroll-view | Show a plain panel with `hostsOwnScroll == false` | `panelHost`'s content is a `PanelScrollView` wrapping that panel's view |
| split-view-controller-051 | updates-help-and-floor-on-every-show | Call `show(nil)` | `panelHost.setContent(nil)`, `panelHost.setHelp(nil)`, and the detail-floor recompute all run |
| split-view-controller-052 | locates-enclosing-split-by-parent-chain | This instance is added as a child of an outer `SplitViewController` via `addPanel` | `enclosingSettingsSplit` returns that outer instance |
| split-view-controller-053 | (edge case: `removePanel(_:)` on a non-member) | Panels `[a, b]`, call `removePanel(z)` where `z` is not in `panels` | `panels` is unchanged (`[a, b]`); navigation history is still reset, the sidebar's panel list is still re-set, and `onNavigationChange` still fires |
| split-view-controller-054 | (edge case: stale nested-detail floor) | Two nested `SplitViewController` siblings raise `nestedDetailFloor` to `420`; `removePanel` drops the nested count to one | `nestedDetailFloor` remains `420` (not reset toward `0`), because `unifyNestedSidebars()`'s `guard nested.count > 1` returns early before recomputing it |
