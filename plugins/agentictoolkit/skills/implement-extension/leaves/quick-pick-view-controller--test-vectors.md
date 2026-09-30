<!-- leaf: implement-extension/quick-pick-view-controller--test-vectors · source: extension-quick-pick-view-controller.md -->

# ExtensionQuickPickViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-quick-pick-view-controller-001 | designated-initializer | Call `ExtensionQuickPickViewController(model:)` with a valid model | Controller initializes; attempting `init(coder:)` traps with a fatal error |
| extension-quick-pick-view-controller-002 | fixed-content-size | Read `preferredContentSize` immediately after `init`, before `loadView` is triggered | `preferredContentSize == NSSize(width: 560, height: 400)` |
| extension-quick-pick-view-controller-003 | title-label | `model.request.title = nil`, then load the view | No title label subview exists in the view hierarchy |
| extension-quick-pick-view-controller-004 | title-label | `model.request.title = "Pick a file"`, then load the view | A `ThemedLabel` subview showing "Pick a file" exists |
| extension-quick-pick-view-controller-005 | title-label-position | `model.request.title` non-empty, view loaded | Title label's top/leading/trailing constraints resolve to 12pt from the root view's respective edges |
| extension-quick-pick-view-controller-006 | search-field-position | `model.request.title = nil`, view loaded | Search field's top edge is 12pt below the root view's top |
| extension-quick-pick-view-controller-007 | table-scroll-position | View loaded with any request | Table scroll's top is 8pt below the search field's bottom; leading/trailing are 12pt from root edges; bottom is 12pt from the root's bottom |
| extension-quick-pick-view-controller-008 | search-placeholder | `model.request.placeHolder = nil`, view loaded | `searchField.placeholderString == ""` |
| extension-quick-pick-view-controller-009 | live-filtering | Type a character into the search field, triggering `controlTextDidChange` | `model.query` updates to the field's text, `tableView.reloadData()` is called, and the highlighted row is re-synced |
| extension-quick-pick-view-controller-010 | arrow-and-return-routing | With the search field focused, press the Down arrow key | `control(_:textView:doCommandBy:)` routes `moveDown(_:)` to `PickerKeyboardController`, which calls the controller's move-selection handler |
| extension-quick-pick-view-controller-011 | escape-routing | With the panel's window key, press Escape | The window-level local event monitor fires and `onCancel()` is invoked |
| extension-quick-pick-view-controller-012 | search-field-focus | Call `focusSearchField()` | `view.window?.firstResponder` becomes the search field; `tableView.acceptsFirstResponder == false` |
| extension-quick-pick-view-controller-013 | single-native-selection | `model.request.canPickMany = true`, view loaded | `tableView.allowsMultipleSelection == false` |
| extension-quick-pick-view-controller-014 | table-header | View loaded with any request | `tableView.headerView == nil` |
| extension-quick-pick-view-controller-015 | single-item-column | View loaded with any request | `tableView.tableColumns.count == 1`, with resizing mask `.autoresizingMask` |
| extension-quick-pick-view-controller-016 | single-select-click | `canPickMany = false`; call `handleRowClick(_:)` on a valid non-separator row | `model.highlightedIndex` becomes that row's item index, selection syncs, and `onAccept` is invoked with `[itemIndex]` |
| extension-quick-pick-view-controller-017 | multi-select-click | `canPickMany = true`; call `handleRowClick(_:)` on a valid non-separator row | `model.checkedIndices` toggles that item index, only that row reloads, and `onAccept` is not invoked |
| extension-quick-pick-view-controller-018 | separator-and-out-of-range-clicks | Call `handleRowClick(_:)` on a separator row's index | No change to `model.highlightedIndex` or `model.checkedIndices`; `onAccept` is not invoked |
| extension-quick-pick-view-controller-019 | multi-select-checkbox | `canPickMany = false`, a non-separator row is rendered | The row's checkbox is hidden; the title label's leading constraint is anchored to the row's own leading edge |
| extension-quick-pick-view-controller-020 | checked-state | `canPickMany = true`, item index already in `model.checkedIndices`, row rendered | The row's checkbox `state == .on` |
| extension-quick-pick-view-controller-021 | description-and-detail | `item.description = nil`, `item.detail = "extra"`, row rendered | Description label is hidden; detail label shows "extra" and is visible |
| extension-quick-pick-view-controller-022 | separator-label | Separator `item.label = ""`, row rendered | Separator cell's label is hidden, producing a blank row |
| extension-quick-pick-view-controller-023 | highlight-selection-sync | `model.highlightedIndex` set to an index with no corresponding row in `model.visibleIndices` | `tableView.deselectAll(nil)` is called; `onHighlight` is not invoked |
| extension-quick-pick-view-controller-024 | empty-choose | `canPickMany = false`, `model.highlightedIndex = nil`; invoke `choose()` via Return | `onAccept` is not invoked |
| extension-quick-pick-view-controller-025 | empty-choose | `canPickMany = true`, `model.checkedIndices` empty; invoke `choose()` via Return | `onAccept` is invoked with `[]` |
| extension-quick-pick-view-controller-026 | separator-selection-guard | Call `tableView(_:shouldSelectRow:)` for a separator row's index | Returns `false` |
| extension-quick-pick-view-controller-027 | test-identifiers | View loaded with any request | `searchField.accessibilityIdentifier() == "extension-quick-pick.search-field"`; `tableView.accessibilityIdentifier() == "extension-quick-pick.table"` |
| extension-quick-pick-view-controller-028 | shared-keyboard-controller | With the search field focused, invoke `control(_:textView:doCommandBy:)` with `moveUp(_:)`, `moveDown(_:)`, and `insertNewline(_:)` in turn | Each call returns `true` and reaches `model` only via `PickerKeyboardController.handle(_:)` — `model.highlightedIndex` moves down then up, and `choose()` runs on `insertNewline(_:)`; no separate key-handling path in this file intercepts any of the three |
| extension-quick-pick-view-controller-029 | escape-idempotency | With the panel's window key and the search field focused, deliver one keyCode-53 key-down event | `onCancel()` is invoked exactly once; `control(_:textView:doCommandBy:)` is never called with `cancelOperation(_:)` for that same event |
| extension-quick-pick-view-controller-030 | search-field-position | `model.request.title = "Pick a file"`, view loaded | Search field's top edge is 12pt below the title label's bottom |
| extension-quick-pick-view-controller-031 | search-placeholder | `model.request.placeHolder = "Search extensions"`, view loaded | `searchField.placeholderString == "Search extensions"` |
| extension-quick-pick-view-controller-032 | arrow-and-return-routing | With the search field focused and a highlighted row that is not the first selectable row, press the Up arrow key | `control(_:textView:doCommandBy:)` routes `moveUp(_:)` to `PickerKeyboardController`, which calls the controller's move-selection handler and `model.highlightedIndex` moves to the previous selectable row |
| extension-quick-pick-view-controller-033 | arrow-and-return-routing | `canPickMany = false`, `model.highlightedIndex` set to a valid item; press Return | `control(_:textView:doCommandBy:)` routes `insertNewline(_:)` to `choose()`, and `onAccept` is invoked with `[highlightedIndex]` |
| extension-quick-pick-view-controller-034 | highlight-selection-sync | `model.highlightedIndex` set to an index with a corresponding row in `model.visibleIndices`, `syncSelection()` runs | `tableView.selectRowIndexes` is called for that row and `onHighlight` is invoked with that index |
| extension-quick-pick-view-controller-035 | multi-select-checkbox | `canPickMany = true`, a non-separator row is rendered | The row's checkbox is visible; the title label's leading constraint is anchored to the checkbox's trailing edge |
| extension-quick-pick-view-controller-036 | description-and-detail | `item.description = "extra info"`, row rendered | Description label is visible and shows "extra info" |
