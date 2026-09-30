<!-- leaf: implement-general-view-1/content-viewer-view--edge-cases · source: content-viewer-view.md -->

# Content Viewer View

**Rules** (cite as `implement-general-view-1/content-viewer-view--edge-cases#<slug>`):

- `null-input-no-selection` MUST — selectedNode == nil renders the placeholder only; no grid, header, or divider appears. MUST (see …
- `null-input-no-file-size` MUST — node.fileSize == nil (always true for directories, and possible for a file whose attributes read failed upstream) omits …
- `null-input-no-modification-date` MUST — node.modificationDate == nil omits the "Modified:" row entirely. MUST (see grid-modified-row-conditional).
- `null-input-no-children` MUST — node.children == nil omits the "Items:" row entirely. Per agentictoolkit://recipes/file-tree-outline-view-controller's …
- `boundary-children-not-yet-loaded` MUST — node.children == [] (an empty, non-nil array — per agentictoolkit://recipes/file-tree-outline-view-controller, a …
- `empty-input-no-extension` MUST — A file with an empty pathExtension omits the "Extension:" row and reports the type description as the literal "File" …
- `boundary-very-long-name` MUST — node.name longer than fits two lines is clipped to 2 lines (lineLimit(2)) with SwiftUI's default (tail) truncation, …
- `boundary-very-long-path` MUST — node.url.path longer than fits 3 lines is clipped to 3 lines with default tail truncation, but because …
- `boundary-zero-byte-file` MUST — node.fileSize == 0 still satisfies fileSize != nil, so the "Size:" row is shown, formatted by ByteCountFormatter (e.g. …
- `boundary-package-with-an-extension` MUST — A package node (isPackage == true) has isDirectory == true, so its "Extension:" row is never shown even though its …

## Edge Cases

- **Null input — no selection**: `selectedNode == nil` renders the placeholder only; no grid, header, or divider appears. MUST (see `show-placeholder-without-selection`).
- **Null input — no file size**: `node.fileSize == nil` (always true for directories, and possible for a file whose attributes read failed upstream) omits the "Size:" row entirely rather than showing a placeholder value. MUST (see `grid-size-row-conditional`).
- **Null input — no modification date**: `node.modificationDate == nil` omits the "Modified:" row entirely. MUST (see `grid-modified-row-conditional`).
- **Null input — no children**: `node.children == nil` omits the "Items:" row entirely. Per `agentictoolkit://recipes/file-tree-outline-view-controller`'s Design Decision on `FileTreeNode`'s children semantics, `nil` covers every file, every package, and any directory that has already been read and found to have no children; `FileTreeNode` deliberately reserves an empty array (`[]`) for a directory whose children have not been read yet (see the next edge case). MUST (see `grid-items-row-conditional`).
- **Boundary — children not yet loaded**: `node.children == []` (an empty, non-`nil` array — per `agentictoolkit://recipes/file-tree-outline-view-controller`, a directory whose children have not been read yet) still satisfies `node.children != nil`, so the "Items:" row is shown with value "0" — indistinguishable, from this view alone, from a directory that was read and genuinely has zero children. MUST (see `grid-items-row-conditional`).
- **Empty input — no extension**: A file with an empty `pathExtension` omits the "Extension:" row and reports the type description as the literal "File" rather than "` File"` with a blank extension. MUST (see `grid-extension-row-conditional`, `type-description-fallback-extension`).
- **Boundary — very long name**: `node.name` longer than fits two lines is clipped to 2 lines (`lineLimit(2)`) with SwiftUI's default (tail) truncation, since the source sets no `truncationMode` — unlike this pane's own Path row, which allows 3 lines before truncating, also with the default tail mode. MUST.
- **Boundary — very long path**: `node.url.path` longer than fits 3 lines is clipped to 3 lines with default tail truncation, but because `textSelection(.enabled)` is set on that value, the full untruncated string remains selectable and copyable regardless of what is visually clipped. MUST (see `grid-path-line-limit`, `grid-path-value-selectable`).
- **Boundary — zero-byte file**: `node.fileSize == 0` still satisfies `fileSize != nil`, so the "Size:" row is shown, formatted by `ByteCountFormatter` (e.g. "Zero KB" under its default settings). MUST.
- **Boundary — package with an extension**: A package node (`isPackage == true`) has `isDirectory == true`, so its "Extension:" row is never shown even though its `url.pathExtension` is non-empty — the row's condition checks `!isDirectory`, not `!isPackage`. MUST (see `grid-extension-row-conditional`).
- **Concurrent access**: `FileTreeNode.children`, `childrenLoaded`, and `gitStatus` are `@Published` and can be mutated asynchronously from a background queue (`loadChildrenIfNeeded()` dispatches its read, then assigns `children` back on the main queue). `FileDetailView` holds `node` as a plain `let`, not `@ObservedObject`, so a `children` mutation that happens while this node's detail view is already on screen does not, by itself, trigger this view to re-render its "Items:" row; the row reflects whichever `children` value was current when this view's body was last evaluated. This is a known limitation of the current implementation, produced by `let node`'s lack of observation — not a requirement other platform implementations are expected to reproduce (see the Design Decisions section).
- **Error states**: Not applicable at this layer. `ContentViewerView` performs no file system operation of its own; `node.fileSize` and `node.modificationDate` are populated — or left `nil` on a failed read — by `FileTreeNode`'s own initializer, which silently discards a failed `attributesOfItem(atPath:)` call before this view ever runs. This view's only response to that upstream failure is the already-covered `nil` case (see `grid-size-row-conditional`, `grid-modified-row-conditional`).
- **Offline or disconnected state**: Not applicable. `ContentViewerView` performs no networking of any kind; it only formats and lays out properties already present on the `FileTreeNode` and `FileTreeConfig` it is given.
