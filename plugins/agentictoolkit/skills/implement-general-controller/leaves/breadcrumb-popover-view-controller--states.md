<!-- leaf: implement-general-controller/breadcrumb-popover-view-controller--states · source: breadcrumb-popover-view-controller.md -->

# BreadcrumbPopoverViewController

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected row) | Row label rendered at `NSFont.smallSystemFontSize`; characters matching the current filter text are bold, the rest regular; no selection highlight. |
| Selected row | AppKit's default table row-selection highlight is applied; the row is scrolled into view via `scrollRowToVisible`. |
| Filtered (non-empty query) | Only entries whose name has at least one match range from `ProjectFilter.ranges(of:in:)` are shown; matched characters render bold; row 0 of the new filtered list is reselected. |
| Empty result set | No rows are shown; `selectRow`/`moveSelection` become no-ops because both guard on `!filtered.isEmpty`. |
| Focused (search field) | The search field becomes the window's first responder in `viewDidAppear`; source sets no other explicit focus-ring styling. |
| Disabled | Not applicable: no control in this component (`searchField`, `tableView`, rows) is ever disabled in source. |
| Loading | Not applicable: `FileTreeNode.loadChildren(for:)` is called synchronously in `init`; source defines no loading/pending state or indicator. |
