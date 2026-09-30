<!-- leaf: implement-general-view-2/log-view--test-vectors · source: log-view.md -->

# Log View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| log-view-001 | embeds-table-in-full-bleed-scroll-view | Construct the view and inspect its subviews and constraints. | A scroll view is the sole subview, with its top/leading/trailing/bottom anchored to the component's own edges. |
| log-view-002 | vertical-only-scrolling | Inspect the scroll view after construction. | `hasVerticalScroller == true`, `hasHorizontalScroller == false`, `autohidesScrollers == true`. |
| log-view-003 | columns-built-once-from-provider | Construct with a provider exposing 3 columns in a given order. | The table has exactly 3 columns, in that order, each with the source column's id, title, and widths. |
| log-view-004 | column-layout-fixed-after-init | Construct with a provider, then observe the same provider's `columns` differ on a later read. | The table's column set is unchanged from what was captured at construction. |
| log-view-005 | columns-user-resizable-uniform | Construct the view and inspect the table's resizing configuration. | `allowsColumnResizing == true`; column autoresizing style is the uniform style. |
| log-view-006 | horizontal-grid-lines-only | Construct the view and inspect the table's grid style mask. | Only the solid-horizontal-grid-line mask is set; no vertical grid line mask is set. |
| log-view-007 | row-count-matches-provider | Construct with a provider holding 5 lines. | The table's reported row count is 5. |
| log-view-008 | renders-initial-lines-at-init | Construct with a provider that already holds 2 lines. | Immediately after `init`, the table displays 2 rows without any change notification having fired. |
| log-view-009 | plain-cell-value-rendering | Provide a line with a `.plain("hello")` value for a column. | The rendered cell's text is `hello`. |
| log-view-010 | attributed-cell-value-rendering | Provide a line with an `.attributed` value carrying a custom color. | The rendered cell displays that attributed string, including its custom color. |
| log-view-011 | missing-cell-value-renders-empty | Provide a line with no value for one of the table's columns. | That cell's text is the empty string. |
| log-view-012 | cell-alignment-follows-column | Configure a column with `.right` alignment and render a line under it. | The cell's alignment is `.right`. |
| log-view-013 | cell-text-truncates-tail | Provide a value longer than the column's width. | The cell's line-break mode is truncating-tail and the rendered text ends with an ellipsis. |
| log-view-014 | cell-tooltip-mirrors-display-text | Render a cell showing `session-42`. | The cell's tooltip reads `session-42`. |
| log-view-015 | cell-request-uses-column-reuse-identifier | Render two different rows under the same column, capturing the identifier passed to `makeView(withIdentifier:owner:)` for each. | Both renders request the view using the same reuse identifier, scoped to that column's id. |
| log-view-016 | cell-text-not-selectable | Inspect a rendered cell's text field. | `isSelectable == false`. |
| log-view-017 | selected-row-uses-theme-selection-color | Select a row and inspect its row view's drawn selection. | A rounded rectangle (4pt radius, inset 2pt/1pt) is filled with the theme's selection color. |
| log-view-018 | selection-fill-reflects-current-theme | Select a row, change the active theme's `selection` role color, then trigger a redraw of that row (for example, by re-requesting its row view via the delegate callback). | The row's drawn selection fill uses the new theme's `selection` color, not the color in effect when the row was first drawn. |
| log-view-019 | single-click-dispatches-column-hook | Single-click a valid cell whose column has an `onClick` hook. | The hook is invoked once with the clicked line. |
| log-view-020 | double-click-dispatches-column-hook | Double-click a valid cell whose column has an `onDoubleClick` hook. | The hook is invoked once with the clicked line. |
| log-view-021 | click-outside-valid-cell-is-inert | Dispatch a click with a negative column index, then with a negative row index, then with a row index at `provider.lines.count`. | No hook is invoked in any of the three cases. |
| log-view-022 | public-dispatch-applies-same-guards | Call the click-dispatch method directly with a valid column index, row, and kind, without any AppKit mouse event; then call it again with an out-of-range row. | The matching column hook is invoked exactly as it would be from a real click for the valid call, and no hook is invoked for the out-of-range call. |
| log-view-023 | reloads-on-every-provider-change | Trigger an appended, then a replaced, then a cleared change. | The table's data is reloaded after each of the three notifications. |
| log-view-024 | append-follows-tail-only-if-already-at-bottom | With `followTail == true` and, before the change, `documentView.bounds.height - documentVisibleRect.maxY <= 2`, trigger an appended change. | The view scrolls to the new last row after the reload. |
| log-view-025 | append-follows-tail-only-if-already-at-bottom | With `followTail == true` and, before the change, `documentView.bounds.height - documentVisibleRect.maxY > 2`, trigger an appended change. | The view does not scroll; the pre-change scroll position is preserved. |
| log-view-026 | replace-follows-tail-unconditionally | With `followTail == true` and the view scrolled away from the bottom, trigger a replaced change. | The view scrolls to the new last row after the reload. |
| log-view-027 | clear-never-follows-tail | With `followTail == true`, trigger a cleared change. | The view does not scroll to the end; the table shows zero rows. |
| log-view-028 | follow-tail-is-mutable-and-effective | Set `followTail = false`, then trigger an appended change while scrolled to the bottom. | The view does not auto-scroll for that change. |
| log-view-029 | scroll-to-end-no-ops-when-empty | Call the scroll-to-end operation on a view whose provider has zero lines. | No scroll occurs and no error or crash results. |
| log-view-030 | reload-is-public-and-unconditional | Call the public reload operation with no preceding provider change. | The table's data is reloaded. |
| log-view-031 | coder-init-unavailable | Attempt to construct the view via `NSCoder`-based decoding (for example, from a storyboard or XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |
| log-view-032 | empty-table-counts-as-at-bottom | With a provider holding zero lines and `followTail == true`, trigger an appended change adding the first line. | The view scrolls to that new line after the reload, since the pre-append empty state counts as at-bottom. |
