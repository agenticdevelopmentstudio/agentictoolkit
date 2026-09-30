<!-- leaf: implement-file/tree-outline-view-controller--states · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller

## States

| State | Appearance change |
|-------|------------------|
| Default | Root headers in `.secondaryText`; node rows show icon and name (plus marker/badge as applicable); nothing selected. |
| Pressed | Not applicable: no row, button, or menu item in this file defines custom pressed-state styling; AppKit's own outline-row press/highlight feedback is unmodified. |
| Disabled | Not applicable: no row or control in this file exposes an `isEnabled` affordance. A placeholder row is unselectable (see Behavioral Requirements) but is never rendered as a disabled control. |
| Focused | Not applicable: no custom focus-ring or keyboard-focus appearance is set on the outline or its rows in this file; AppKit's default focus ring is unmodified. |
| Loading | An empty root manager with `isSyncing == true` shows the placeholder text "Scanning…"; once syncing finishes, the same empty root's placeholder switches to "Empty". |
| Selected | The selected row is highlighted by `ThemedTableRowView`/AppKit's own selection rendering; if the selection is a root header, that header additionally switches from `.secondaryText` to `.primaryText`. |
| Expanded / Collapsed | A directory shows AppKit's standard disclosure triangle, open or closed; expanding starts a lazy read of that directory's contents if it has not already been read. |
| Dirty | A file whose open document is dirty shows a filled-circle marker at the row's trailing edge, tinted `.warning`; it is hidden, not removed, when the document is clean. |
| Git status | A node with a non-`nil` `gitStatus` recolors its name label and shows a trailing single-character badge, both in that status's fixed color (orange=modified, green=added/untracked, red=deleted, blue=renamed/copied, purple=conflicted, gray=ignored). |
