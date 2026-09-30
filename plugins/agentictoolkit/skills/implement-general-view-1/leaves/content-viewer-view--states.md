<!-- leaf: implement-general-view-1/content-viewer-view--states · source: content-viewer-view.md -->

# Content Viewer View

## States

| State | Appearance change |
|-------|------------------|
| No selection (`selectedNode == nil`) | Shows the placeholder: 48pt magnifying-glass-over-document icon in `tertiaryText`, heading-styled message in `secondaryText` |
| Selection — directory (not a package) | Header icon in `accent`; Type row reads "Directory"; Items row shown only if `children != nil`; Extension row never shown, because the node's `isDirectory` is true |
| Selection — package | Header icon in `warning`; Type row reads the configured display name or "Package"; neither the Items row nor the Extension row is shown, because a package node has no `children` and `isDirectory` is true |
| Selection — file, recognized extension | Header icon in `warning`, `accent`, or `secondaryText` per extension; Type and Extension rows both shown |
| Selection — file, unrecognized extension | Type row reads "`<EXTENSION>` File"; Extension row shown |
| Selection — file, no extension | Type row reads "File"; Extension row NOT shown, because the extension is empty |
| Pressed | Not applicable: `ContentViewerView` contains no button, tap target, or other interactive control — every element is static display. |
| Focused | Not applicable: nothing in the view is focusable; no `Button`, `TextField`, or other focusable control appears in source. |
| Disabled | Not applicable: the view has no enabled/disabled concept; nothing in it is interactive. |
| Loading | Not applicable: `body` is computed synchronously from properties already resolved on the given `FileTreeNode`; there is no asynchronous fetch and no loading indicator in source. |
