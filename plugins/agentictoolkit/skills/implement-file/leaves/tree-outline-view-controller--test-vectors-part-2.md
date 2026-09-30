<!-- leaf: implement-file/tree-outline-view-controller--test-vectors-part-2 · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-tree-outline-046 | reveal-defers-when-not-drawn | Call `reveal(url)` for a file under a directory that has not yet been read. | The reveal is recorded as pending and completes once that directory's contents arrive. |
| file-tree-outline-047 | reveal-nothing-clears-selection | Call `revealNothing()` with a row selected. | The outline deselects all rows and `selection.selectedNode` becomes `nil`. |
| file-tree-outline-048 | context-menu-uses-clicked-row | Right-click file A while file B is the current selection. | The menu is built for file A, not file B. |
| file-tree-outline-049 | context-menu-omitted-for-missing-path | Right-click a row whose file has just been deleted from disk. | No menu items are added. |
| file-tree-outline-050 | context-menu-hides-open-items-for-directories | Right-click a plain directory row. | The menu shows only "Reveal in Finder" and "Copy Path". |
| file-tree-outline-051 | context-menu-item-order | Right-click a file row. | Menu order is Open, Open in a New Tab, Open to the Side, separator, Reveal in Finder, Copy Path. |
| file-tree-outline-052 | context-menu-open-forwards-destination | Choose "Open to the Side" from a file's context menu. | `onOpenRequest` is called with that file's URL and `.toTheSide`. |
| file-tree-outline-053 | context-menu-reveal-in-finder | Choose "Reveal in Finder". | `NSWorkspace.shared.activateFileViewerSelecting(_:)` is called with that row's URL. |
| file-tree-outline-054 | copy-path-format | Choose "Copy Path" for a file at `/Users/x/Notes.md`. | The pasteboard's string is `/Users/x/Notes.md`, not a `file://` URL. |
| file-tree-outline-055 | double-click-toggles-root | Double-click a collapsed root header, then double-click it again. | It expands, then collapses. |
| file-tree-outline-056 | double-click-toggles-loaded-node | Double-click a directory row with `children != nil`. | Its expansion toggles. |
| file-tree-outline-057 | double-click-opens-otherwise | Double-click a file row (`children == nil`). | `onOpenRequest` is called instead of any expansion change. |
| file-tree-outline-058 | icon-chosen-by-node-type | Inspect rows for a `.claude` directory, a `Tests` directory, a `.xcodeproj` package, and a `.swift` file. | Icons are `brain`, `folder.fill.badge.questionmark`, `shippingbox.fill`, and the file's extension-resolved icon, respectively. |
| file-tree-outline-059 | icon-tint-by-role | Inspect icon tints for a package, a `.claude` directory, an ordinary directory, and a `.swift` file. | Tints resolve to `.warning`, `.info`, `.accent`, and `.warning` respectively. |
| file-tree-outline-060 | name-truncation | Render a name too long for the row's width. | The label truncates in the middle and stays on one line. |
| file-tree-outline-061 | name-tooltip-is-full-path | Hover a row's name label. | The tooltip shows the node's full filesystem path. |
| file-tree-outline-062 | git-status-recolors-name | Give a node `gitStatus == .modified`. | The name label's text color equals `NSColor.systemOrange`. |
| file-tree-outline-063 | git-status-shows-badge | Give a node `gitStatus == .deleted`. | A trailing badge reading "D" appears in `NSColor.systemRed`. |
| file-tree-outline-064 | tree-carries-accessibility-id | Inspect the outline view's accessibility identifier. | It equals `file-browser.tree`. |
| file-tree-outline-065 | coder-init-unavailable | Attempt to construct via `NSCoder`-based decoding. | Compilation fails (unavailable), or a runtime `fatalError` occurs if bypassed. |
| file-tree-outline-066 | keyboard-and-typeahead-inherited | With the outline focused, press the down-arrow key, then type a letter matching a row's first character. | Selection moves to the next row, then jumps to the type-ahead match; no custom key handler intercepts either. |
| file-tree-outline-068 | target-root-change-redraws-headers | Set `selection.selectedRoot` to a different root among three roots. | The outline reloads and header emphasis is redrawn to reflect the new target. |
| file-tree-outline-069 | programmatic-expand-collapse-not-persisted | Restore a stored expanded path via `restoreDisclosure()` (or expand an ancestor via `reveal(_:)`), with no matching entry yet in `restoration`. | `restoration`'s stored expanded set gains no new entry for that path as a result of the programmatic expansion itself. |
| file-tree-outline-070 | restore-disclosure-noop-without-pending | Call `restoreDisclosure()` when `pendingSelectionPath` is `nil` and no directory in `restoration.expandedPaths` needs expanding. | No selection, expansion, or scroll change occurs, and no crash results. |
| file-tree-outline-071 | document-event-ignores-unparseable-uri | Fire a document event whose URI string does not parse into a `URL` (`URL(string:)` returns `nil`). | No row lookup, reload, or crash occurs. |

**Testing note**: `selectedURLForTesting`, `selectedNodeInModelForTesting`, and
`collapseAllForTesting()` are additional `@testable`-only surface used to read
and drive state directly in tests; they are not behavioral requirements in
their own right, so no vector above exists solely to prove their presence.
