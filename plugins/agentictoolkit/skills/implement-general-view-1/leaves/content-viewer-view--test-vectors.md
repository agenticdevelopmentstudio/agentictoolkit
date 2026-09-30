<!-- leaf: implement-general-view-1/content-viewer-view--test-vectors · source: content-viewer-view.md -->

# Content Viewer View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| content-viewer-view-001 | show-placeholder-without-selection | `selectedNode = nil` | The placeholder view renders; no metadata grid appears |
| content-viewer-view-002 | show-detail-with-selection | `selectedNode` = a file node | The file detail view renders with that node's data; the placeholder does not appear |
| content-viewer-view-003 | fill-available-space | Host the view in a 400×300 container, in both states | The view's rendered frame fills the full 400×300 container in each state |
| content-viewer-view-004 | placeholder-icon-style | `selectedNode = nil`; inspect the placeholder icon | Symbol is `doc.text.magnifyingglass`, font size 48, color equals `theme.tertiaryText` |
| content-viewer-view-005 | placeholder-message-text | `selectedNode = nil`; inspect the placeholder text | Text reads exactly "Select a file to view its details"; font equals `theme.font(.heading)`; color equals `theme.secondaryText` |
| content-viewer-view-006 | header-icon-symbol | `selectedNode` = a directory node | Header icon's symbol equals `node.systemImageName`; font size 40 |
| content-viewer-view-007 | header-icon-color-package | `selectedNode.isPackage == true` | Header icon color equals `theme.warning` |
| content-viewer-view-008 | header-icon-color-directory | `selectedNode.isDirectory == true`, `isPackage == false` | Header icon color equals `theme.accent` |
| content-viewer-view-009 | header-icon-color-swift-or-json | `selectedNode` is a file with extension `SWIFT` (mixed case) | Header icon color equals `theme.warning` |
| content-viewer-view-010 | header-icon-color-markdown | `selectedNode` is a file with extension `markdown` | Header icon color equals `theme.accent` |
| content-viewer-view-010b | header-icon-color-markdown | `selectedNode` is a file with extension `md` | Header icon color equals `theme.accent` |
| content-viewer-view-011 | header-icon-color-default | `selectedNode` is a file with extension `png` | Header icon color equals `theme.secondaryText` |
| content-viewer-view-012 | header-name-text | `selectedNode.name` = a 120-character string | Name renders in `theme.font(.title)`, wraps to at most 2 lines, center-aligned |
| content-viewer-view-013 | header-type-description-text | `selectedNode` is a directory | Text below the name reads "Directory", in `theme.font(.caption)` and `theme.secondaryText` |
| content-viewer-view-014 | divider-between-header-and-grid | Any selected node | Exactly one `Divider` appears between the header block and the metadata grid |
| content-viewer-view-015 | grid-path-row-always-shown | `selectedNode.url.path` = `/Users/x/a.txt` | A "Path:" row appears with value "/Users/x/a.txt" |
| content-viewer-view-016 | grid-path-value-selectable | Inspect the Path row's value text | `textSelection` is `.enabled` on that text; no other grid value has selection enabled |
| content-viewer-view-016c | grid-path-line-limit | `selectedNode.url.path` long enough to exceed 3 lines at the pane's width | The Path row's value text is clipped to 3 lines with default tail truncation; the full string remains selectable via `textSelection(.enabled)` |
| content-viewer-view-017 | grid-size-row-conditional | `selectedNode.fileSize = 2048` | A "Size:" row appears, formatted via `ByteCountFormatter` with `.file` style (e.g. "2 KB") |
| content-viewer-view-017b | grid-size-row-conditional | `selectedNode.fileSize = nil` (a directory) | No "Size:" row appears |
| content-viewer-view-018 | grid-modified-row-conditional | `selectedNode.modificationDate` = a known `Date` | A "Modified:" row appears, formatted with long date style and medium time style |
| content-viewer-view-018b | grid-modified-row-conditional | `selectedNode.modificationDate = nil` | No "Modified:" row appears |
| content-viewer-view-019 | grid-type-row-always-shown | Any selected node | A "Type:" row always appears, with the computed type description as its value |
| content-viewer-view-020 | grid-extension-row-conditional | `selectedNode` is a file with extension `swift` | An "Extension:" row appears with value ".swift" |
| content-viewer-view-020b | grid-extension-row-conditional | `selectedNode` is a directory (isDirectory = true) | No "Extension:" row appears, even if `url.pathExtension` is non-empty |
| content-viewer-view-021 | grid-items-row-conditional | `selectedNode.children` = an array of 3 nodes | An "Items:" row appears with value "3" |
| content-viewer-view-021b | grid-items-row-conditional | `selectedNode.children = nil` | No "Items:" row appears |
| content-viewer-view-021c | grid-items-row-conditional | `selectedNode.children = []` (empty, non-`nil` array) | An "Items:" row appears with value "0" |
| content-viewer-view-022 | grid-label-color | Inspect any grid row's label | Label color equals `theme.secondaryText`; label is trailing-aligned in its column |
| content-viewer-view-023 | grid-value-text-role | Inspect the grid's font modifier | The `Grid` is given `.font(theme.font(.body))` |
| content-viewer-view-024 | type-description-package | `isPackage = true`, extension `{{app_name_lower}}-proj`, `config.packageDisplayNames = ["{{app_name_lower}}-proj": "{{app_name}} Project Package"]` | Type description reads "{{app_name}} Project Package" |
| content-viewer-view-024b | type-description-package | `isPackage = true`, extension `foo`, `config.packageDisplayNames` has no entry for `foo` | Type description reads "Package" |
| content-viewer-view-025 | type-description-directory | `isDirectory = true`, `isPackage = false` | Type description reads "Directory" |
| content-viewer-view-026 | type-description-known-extension | File extension `py` | Type description reads "Python Script" |
| content-viewer-view-026b | type-description-known-extension | File extension `JSON` (mixed case) | Type description reads "JSON File" |
| content-viewer-view-026c | type-description-known-extension | File extension `gitignore` | Type description reads "Git Ignore Rules" |
| content-viewer-view-026d | type-description-known-extension | Each extension in the `type-description-known-extension` mapping (`swift`, `json`, `md`, `markdown`, `txt`, `text`, `plist`, `entitlements`, `xcodeproj`, `xcworkspace`, `png`, `jpg`, `jpeg`, `svg`, `gif`, `sh`, `zsh`, `bash`, `py`, `js`, `ts`, `css`, `html`, `yaml`, `yml`, `toml`, `gitignore`), compared case-insensitively | Each extension's type description equals the fixed string listed for it in the `type-description-known-extension` requirement |
| content-viewer-view-027 | type-description-fallback-extension | File extension `rs` (unrecognized) | Type description reads "RS File" |
| content-viewer-view-027b | type-description-fallback-extension | File with empty extension | Type description reads "File" |
| content-viewer-view-028 | no-filesystem-access-in-view | Render the view with a `selectedNode` pointing at a path that no longer exists on disk | The view renders using only the node's already-resolved properties; it makes no new file system call and does not crash |
