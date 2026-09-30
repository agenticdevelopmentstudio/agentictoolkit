<!-- leaf: implement-extension/tree-view-controller--test-vectors-part-3 · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| etvc-052 | targeted-change-reloads-one-branch | Data source fires `onDidChangeTreeData("h1")` where h1 is a loaded row | Only h1's branch reloads |
| etvc-053 | untargeted-change-reloads-loaded-branches | Data source fires `onDidChangeTreeData(nil)` with branches "" and "h1" already loaded | Both "" and "h1" are re-asked |
| etvc-054 | untargeted-change-reasks-root-when-empty | Data source fires `onDidChangeTreeData(nil)` before the root has ever loaded | The root ("") is asked |
| etvc-055 | change-after-teardown-ignored | Call `paneContentWillBeDiscarded()`, then fire `onDidChangeTreeData(nil)` | No load is triggered |
| etvc-056 | row-view-recycled | Draw one screenful of rows, then scroll through 500 rows | `outline.makeView(withIdentifier: ExtensionTreeRowView.reuseIdentifier, owner:)` returns a non-nil, previously-created instance for each newly-scrolled-in row, so `outlineView(_:viewFor:item:)`'s `?? ExtensionTreeRowView()` fallback is not exercised again |
| etvc-057 | row-icon-from-symbol-name | Item with `symbolName == "folder"`, and item with `symbolName == nil` | First row shows a tinted `.secondaryText` icon; second row's icon is hidden |
| etvc-058 | row-label-shows-item-label | Item label longer than the column width | Label truncates with a tail ellipsis |
| etvc-059 | row-caption-from-description | Item with `description == "3 items"`, and item with `description == nil` | First row's caption shows "3 items"; second row's caption is hidden |
| etvc-060 | row-tooltip-fallback | Item with `tooltip == nil`, `label == "README.md"` | The row's tooltip is "README.md" |
| etvc-061 | row-background-recycled | Draw one screenful of rows, then scroll through 500 rows | `outline.makeView(withIdentifier: Self.backgroundRowIdentifier, owner:)` returns a non-nil, previously-created `ThemedTableRowView` for each newly-scrolled-in row, so `outlineView(_:rowViewForItem:)`'s fresh-`ThemedTableRowView()` fallback is not exercised again |
| etvc-062 | double-click-activates | Double-click a row | `dataSource.activate(_:)` is called with that row's item |
| etvc-063 | return-key-activates-selection | A row is selected; post a keyDown with key code 36 (Return) | `dataSource.activate(_:)` is called with the selected row's item |
| etvc-064 | other-keys-pass-through | Post a keyDown with key code 49 (Space) | `super.keyDown(_:)` runs; no activation occurs |
| etvc-065 | outline-pane-title-source-or-fallback | `dataSource.title == nil`, then `dataSource.title == "Explorer"` | First read of `paneTitle` is the manifest's fallback name; second read is "Explorer" |
| etvc-066 | outline-teardown-idempotent | Call `paneContentWillBeDiscarded()` twice | The second call has no additional effect (e.g. `visibilityDidChange(false)` is not sent twice) |
| etvc-067 | outline-teardown-releases-callbacks-only-if-owner | Outline B has superseded outline A for the same data source (etvc-026); call `paneContentWillBeDiscarded()` on A | The data source's callbacks (still pointing at B) are left untouched; `visibilityDidChange` is not called by A |
| etvc-068 | insert-newline-activates-selection | A row is selected; call `insertNewline(_:)` directly (AppKit's text-editing-command path for Return) | `dataSource.activate(_:)` is called with the selected row's item |
