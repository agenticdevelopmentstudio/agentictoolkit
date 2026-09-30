<!-- leaf: implement-composable-tabs/view-controller--states · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController

## States

| State | Appearance change |
|-------|------------------|
| Default (arranged) | Panes/nested splits occupy the fractions of the split's extent recorded in `thicknessFraction`, or share evenly when none is set; dividers are drawn at the gutter thickness for the split's axis. |
| Dragging a divider | The user's drag moves the divider live via AppKit; once released, `splitViewDidResizeSubviews(_:)` schedules a 300ms-debounced write of the new fractions rather than persisting on every intermediate frame. |
| Minimized (rail) | The pane's owning split item is pinned to a fixed thickness (`minimumThickness == maximumThickness`) with `holdingPriority = .defaultHigh`; the item cannot be dragged narrower or wider, and a window resize is taken out of its neighbours instead. |
| Zoomed | Every split item off the path from the root to the zoomed leaf has `isCollapsed = true`; the zoomed leaf's ancestors on that path stay visible and sized as before. Only one leaf per tab may be zoomed at a time (`zoomedLeaf`, root-only). |
| Collapsed by spec | Not applicable in this file: `NSSplitViewItem.canCollapse` is set from the pane's descriptor `isCollapsible`, but nothing in this source ever collapses an item on that basis outside of the zoom path above — user-driven collapse-by-drag is AppKit's own default `NSSplitViewController` behavior for a `canCollapse` item. |
| Pressed | Not applicable: neither the split view nor its dividers expose a pressed/highlighted visual state in this source. |
| Disabled | Not applicable: no split item, divider, or child is ever disabled in this source. |
| Focused | Not applicable to the split itself: first responder moves among the *panes* it hosts (see `remove-rehomes-focus`); the split view controller has no focus appearance of its own. |
| Loading | Not applicable: every mutation (`split`, `remove`, `rebuild`, `move`) is synchronous; source defines no loading/pending indicator. |
