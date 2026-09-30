<!-- leaf: implement-general-controller/breadcrumb-popover-view-controller--test-vectors · source: breadcrumb-popover-view-controller.md -->

# BreadcrumbPopoverViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| breadcrumb-popover-001 | load-directory-children | Initialize with a `directoryURL` containing files "A.txt", "B.txt" and subdirectory "C" | The table shows exactly 3 rows, one per entry returned by `FileTreeNode.loadChildren(for:)`, in that order, before any filter text is entered |
| breadcrumb-popover-002 | fixed-content-size | Read `preferredContentSize` immediately after init | `preferredContentSize == NSSize(width: 280, height: 320)` |
| breadcrumb-popover-003 | filter-placeholder-text | Inspect the search field before any input | `placeholderString == "Filter"` |
| breadcrumb-popover-004 | filter-updates-immediately, filter-by-name-match | Entries "Apple.txt" and "Banana.txt" loaded; type "app" into the filter field | Table reloads to show only "Apple.txt" (the only name with a case-insensitive substring match for "app") before any further keystroke or Return is pressed |
| breadcrumb-popover-005 | show-all-entries-when-filter-empty | Filter field contains "a" and is then cleared to `""` | Table shows all originally loaded entries again |
| breadcrumb-popover-006 | select-first-row-on-load | View controller finishes `viewDidLoad` with 3 entries | Row 0 is selected |
| breadcrumb-popover-007 | reselect-first-row-after-filter | Row 2 is selected; user types a filter that matches multiple entries | Row 0 of the newly filtered list is selected |
| breadcrumb-popover-008 | bold-matched-characters | Filter field contains "ap"; an entry's name is "Apple.txt" | The attributed string's "Ap" range carries the bold system font; the remaining characters carry the regular system font |
| breadcrumb-popover-009 | reject-empty-selection, reject-multiple-selection | Inspect `tableView` configuration after `loadView` | `allowsEmptySelection == false` and `allowsMultipleSelection == false` |
| breadcrumb-popover-010 | clamp-selection-to-list-bounds | 3 filtered entries; call `selectRow(-5)`, then `selectRow(999)` | First call selects row 0; second call selects row 2 |
| breadcrumb-popover-011 | no-op-selection-when-empty | Filter text matches no entries; call `moveSelection(by: 1)` | No row is selected and no index-out-of-range error occurs |
| breadcrumb-popover-012 | scroll-selection-into-view | Selection moves to a row currently scrolled out of view | `scrollRowToVisible` is called with that row index and the row becomes visible |
| breadcrumb-popover-013 | relative-selection-movement | 5 filtered entries; row 1 is selected; call `moveSelection(by: 2)` | Row 3 becomes selected |
| breadcrumb-popover-014 | arrow-keys-move-selection | View has appeared with 3 entries and row 0 selected; filter field has keyboard focus; the Down arrow key is pressed twice | Row 2 becomes selected (see relative-selection-movement) |
| breadcrumb-popover-015 | focus-filter-field-on-appear | View appears | The search field is the window's first responder |
| breadcrumb-popover-016 | escape-key-cancels | `onCancel` is set; Escape is pressed while the view is visible; the view then disappears and Escape is pressed again | The first Escape invokes `onCancel` exactly once; the second Escape, after the view has disappeared, has no effect |
| breadcrumb-popover-017 | return-key-chooses-selection | Filter field has keyboard focus; the selected row is a file "Notes.txt"; Return is pressed | `onSelect` is invoked exactly once with "Notes.txt"'s URL (see open-selected-file) |
| breadcrumb-popover-018 | double-click-chooses-row | User double-clicks a row representing a file | `onSelect` is invoked with that file's URL — the same outcome as choosing it through the keyboard controller |
| breadcrumb-popover-019 | open-selected-file | Selected row is a file "Notes.txt"; choose is invoked | `onSelect` is called exactly once, with "Notes.txt"'s URL |
| breadcrumb-popover-020 | ignore-directory-choice | Selected row is a subdirectory; choose is invoked | `onSelect` is NOT called |
| breadcrumb-popover-021 | ignore-choose-without-valid-selection | The current filter text matches no entries, so the table shows zero rows; Return is pressed | `onSelect` is NOT called |
| breadcrumb-popover-022 | invoke-cancel-callback-when-set | `onCancel` has been set; keyboard controller reports cancel (Escape) | The `onCancel` closure is invoked exactly once |
| breadcrumb-popover-023 | no-op-cancel-when-unset | `onCancel` is `nil`; keyboard controller reports cancel (Escape) | No callback fires and no crash occurs |
| breadcrumb-popover-024 | reuse-row-views | The same 3 entries are shown, then the filter is applied and cleared twice in a row, forcing repeated table reloads | No more than one row view per visible row position is ever constructed; already-constructed views are reused across the reloads and only their displayed text changes |
| breadcrumb-popover-025 | truncate-row-label-middle | Row label text is longer than the 248pt column width | The label's `lineBreakMode == .byTruncatingMiddle` and rendered text is elided in the middle |
| breadcrumb-popover-026 | single-column-table, no-column-header | Inspect `tableView` after `loadView` | Exactly one `NSTableColumn` (identifier `"breadcrumb.entry"`) exists and `headerView == nil` |
| breadcrumb-popover-027 | coder-initialization-unsupported | Attempt `BreadcrumbPopoverViewController(coder:)` | The call traps with a fatal error ("init(coder:) is not supported"); no instance is returned |
