---
id: b307116d-3ab8-422a-b031-885710e11e70
title: File Tree Outline View Controller
domain: agentictoolkit://recipes/file-tree-outline-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit NSOutlineView controller: a lazily-loaded, git-status-aware file
  tree with restore-on-relaunch, reveal-from-editor, and live dirty-file tracking.'
platforms:
- swift
- macos
tags:
- file-browser
- tree-view
- view-controller
- macos
depends-on: []
related:
- agentictoolkit://recipes/file-browser-view-controller
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# File Tree Outline View Controller

## Overview

`FileTreeOutlineViewController` is an `NSViewController` that draws the file
tree itself: one collapsible header row per root directory (a `FileTreeManager`),
and the files and folders under each one, in an `NSOutlineView` rather than a
SwiftUI `List`. It is hosted inside `FileBrowserViewController` (see the
`file-browser-view-controller` recipe), which owns the footer strip and the
per-root `FileTreeManager`s; this component owns only the tree surface: lazy
per-directory loading, expand/collapse and selection state kept in sync with
injected model objects (`FileBrowserSelection`, `FileBrowserRestorationState`,
`FileBrowserDirectories`), a "reveal the file the editor is showing" API, a
live unsaved-changes indicator sourced from `TextDocumentStore`, and a
right-click context menu for opening, revealing, and copying a path.

## Behavioral Requirements

- **top-level-rows-are-managers**: The outline's top-level rows MUST be
  exactly `roots.managers`, one row per `FileTreeManager`, in the order that
  array supplies.
- **child-ordering-directories-first**: Rows for a directory's contents MUST
  list subdirectories before files, each group sorted alphabetically and
  case-insensitively (`FileTreeNode.loadChildren`).
- **hidden-files-shown-ds-store-excluded**: Rows MUST include hidden
  (dot-prefixed) files and directories, but MUST NOT include a `.DS_Store`
  entry (`FileTreeNode.loadChildren`).
- **empty-root-placeholder-text**: A root manager with no children currently
  loaded MUST render a single placeholder row reading "Scanning…" while
  `manager.isSyncing` is `true`, or "Empty" otherwise.
- **placeholder-not-selectable**: A placeholder row MUST NOT be selectable.
- **unread-directory-shows-triangle**: A directory whose contents have not yet
  been read (`children == []`) MUST be reported expandable, so its disclosure
  triangle appears before anything is known to be inside it.
- **leaf-hides-triangle**: A file, a package, or a directory whose read
  completed with nothing inside (`children == nil`) MUST NOT be reported
  expandable.
- **expand-loads-children-lazily**: Expanding a directory row MUST call
  `loadChildrenIfNeeded()` on its node, which starts an asynchronous read of
  that one directory's contents.
- **expand-watches-children-publisher**: Expanding a directory row MUST begin
  watching that node's `children` publisher (`watchChildren(of:)`) so the rows
  update once the read finishes.
- **children-arrival-reloads-subtree-only**: When a watched directory's
  children publish a new value, only that item's row and subtree MUST be
  reloaded (`reloadItem(_:reloadChildren:)`); the rest of the outline MUST NOT
  be reloaded.
- **children-arrival-preserves-expansion-and-selection**: A subtree reload
  triggered by arriving children MUST re-expand the item if it was expanded
  immediately beforehand, and MUST restore whichever row was selected
  beforehand, provided that row is still present afterward.
- **collapse-stops-watching-children**: Collapsing a directory row MUST remove
  its child-change subscription.
- **expand-persists-to-restoration**: A user-initiated expansion (one not
  performed while restoring state) MUST record that path as expanded in
  `restoration` (`setExpanded(true, path:)`).
- **collapse-persists-to-restoration**: A user-initiated collapse MUST record
  that path as not expanded in `restoration` (`setExpanded(false, path:)`).
- **programmatic-expand-collapse-not-persisted**: An expansion or collapse
  performed by the controller itself — restoring saved disclosure, expanding
  a reveal's ancestors, or `collapseAllForTesting()` — MUST NOT be written to
  `restoration`.
- **lone-root-auto-expands-once**: The first time the outline reloads while
  `restoration.expandedPaths` is empty and there is exactly one root manager,
  that root MUST be expanded automatically; this automatic expansion MUST
  happen at most once for the life of the controller.
- **restore-expanded-paths-on-reload**: After any full reload, every currently
  drawn row whose path `restoration.isExpanded(path)` reports `true`, and
  which is not already expanded, MUST be expanded.
- **restore-descends-incrementally**: Restoring a selected path more than one
  unread level deep MUST proceed one additional level per reload triggered by
  that level's children arriving, rather than requiring the whole path to be
  drawn in a single pass.
- **restore-abandons-missing-selection**: If the directory that should contain
  a pending restored selection is drawn, expanded, and has finished reading
  its contents without that path appearing in them, the pending restoration
  MUST be dropped rather than left standing indefinitely.
- **select-root-sets-target-root**: Selecting a root's header row MUST set
  `selection.selectedRoot` to that root's URL.
- **select-node-sets-node-and-target-root**: Selecting a file or directory row
  MUST set `selection.selectedNode` to that row's node, and, if the node's URL
  falls under one of `directories`' roots, MUST also set
  `selection.selectedRoot` to that root.
- **select-persists-path-unless-restore-pending**: A selection change MUST be
  written to `restoration.setSelectedPath(_:)`, except while a selection
  restore from a previous launch is still pending.
- **select-opens-file**: Selecting a row MUST invoke `openIfFile(_:)` with the
  newly selected node.
- **open-skips-plain-directories**: `openIfFile(_:)` MUST NOT invoke
  `onOpenRequest` for a node that is a directory and not a package.
- **open-opens-files-and-packages**: `openIfFile(_:)` MUST invoke
  `onOpenRequest` with the node's URL and `.current` for a file or a package.
- **external-selection-highlights-and-scrolls**: When `selection.selectedNode`
  changes to a value different from what the outline currently has selected,
  and the corresponding row is drawn, that row MUST become the outline's
  selection and MUST be scrolled into view.
- **external-selection-suppresses-writeback**: Applying an externally-driven
  selection change (the previous requirement) MUST NOT cause that same value
  to be written back into `selection` through the outline's own
  selection-changed delegate callback.
- **external-deselect-clears-highlight**: When `selection.selectedNode`
  becomes `nil` while a `FileTreeNode` row is the outline's selection, the
  outline MUST deselect all rows.
- **target-root-header-emphasis**: The root header row whose URL equals
  `selection.selectedRoot` MUST render its label with the `.primaryText` role;
  every other root header row MUST render with `.secondaryText`.
- **target-root-change-redraws-headers**: A change to `selection.selectedRoot`
  MUST reload the outline so header emphasis is redrawn; a republish of the
  same value MUST NOT trigger a reload.
- **managers-list-change-reloads**: A change to `roots.managers` MUST rebuild
  the per-manager subscriptions and reload the outline.
- **root-node-change-reloads**: A change to any manager's `rootNode` MUST
  reload the outline.
- **syncing-change-reloads**: A change to any manager's `isSyncing` MUST
  reload the outline.
- **reload-preserves-selection**: A full reload MUST re-select whatever row
  was selected immediately beforehand, if that row (by identity, or by path
  when identity changed) is still present afterward.
- **reload-clears-selection-when-row-gone**: If the row selected before a full
  reload is a `FileTreeNode` and is no longer present afterward (by identity
  or by path), `selection.selectedNode` MUST be set to `nil`.
- **path-lookup-correct-after-structural-change**: A lookup for the row
  currently displaying a given path MUST return the row that is actually
  showing that path (or report "not drawn") immediately after any reload,
  expansion, or collapse — never a stale answer left over from before that
  change.
- **row-lookup-avoids-full-scan**: A path lookup SHOULD be answered from a
  cached path-to-row index rather than scanning every drawn row on each call,
  rebuilding that index only when a structural change may have invalidated it.
- **dirty-updates-row-in-place**: A document open, change, dirty-state-change,
  or close event for a URI whose row is drawn and whose row view is currently
  instantiated MUST update only that row view's unsaved-changes marker
  (`setDirty(_:)`), without reloading or reselecting anything.
- **dirty-falls-back-to-item-reload**: If the drawn row's view has been
  recycled away, the same event MUST instead reload that one item, in a way
  that does not clear the outline's current selection.
- **dirty-ignored-when-row-not-drawn**: A document event for a URI with no
  currently drawn row MUST be ignored.
- **dirty-marker-always-built**: A file row's unsaved-changes marker view MUST
  always be constructed as part of the row, and MUST be shown or hidden rather
  than added or removed after construction.
- **reveal-noop-if-already-shown**: Calling `reveal(_:)` with the URL already
  selected MUST do nothing.
- **reveal-expands-drawn-ancestors**: Calling `reveal(_:)` MUST expand every
  ancestor directory of the target URL that is currently drawn and not
  already expanded.
- **reveal-selects-and-scrolls-when-drawn**: If the target row is drawn once
  its ancestors are expanded, `reveal(_:)` MUST select it and scroll it into
  view.
- **reveal-writes-model-directly**: `reveal(_:)` and `revealNothing()` MUST
  write the resulting selection into `selection.selectedNode` (and
  `selection.selectedRoot`, when the URL falls under a known root) directly,
  rather than relying on the outline's own selection-changed delegate
  callback to do it.
- **reveal-defers-when-not-drawn**: If the target row is not yet drawn,
  `reveal(_:)` MUST record it as a pending selection that later reloads
  complete once the relevant directory's contents arrive.
- **reveal-nothing-clears-selection**: Calling `revealNothing()` MUST deselect
  all rows and MUST set `selection.selectedNode` to `nil`.
- **context-menu-uses-clicked-row**: The context menu MUST be built for the
  row under the cursor (`outline.clickedRow`), not for the currently selected
  row.
- **context-menu-omitted-for-missing-path**: No context menu items MUST be
  added for a row whose path no longer exists on disk.
- **context-menu-hides-open-items-for-directories**: The "Open", "Open in a
  New Tab", and "Open to the Side" items MUST be omitted for a path that is a
  directory.
- **context-menu-item-order**: When both groups of items apply, the menu MUST
  list the open items first, then a separator, then "Reveal in Finder" and
  "Copy Path".
- **context-menu-open-forwards-destination**: Choosing "Open", "Open in a New
  Tab", or "Open to the Side" MUST call `onOpenRequest` with the row's URL and
  `.current`, `.newTab`, or `.toTheSide` respectively.
- **context-menu-reveal-in-finder**: Choosing "Reveal in Finder" MUST call
  `NSWorkspace.shared.activateFileViewerSelecting(_:)` with the row's URL.
- **context-menu-copy-path-is-posix**: Choosing "Copy Path" MUST place the
  URL's POSIX path (not a `file://` URL string) on the general pasteboard.
- **double-click-toggles-root**: Double-clicking a root header row MUST expand
  it if collapsed, or collapse it if expanded.
- **double-click-toggles-loaded-node**: Double-clicking a node whose
  `children` is non-`nil` MUST toggle its expansion.
- **double-click-opens-otherwise**: Double-clicking a node whose `children` is
  `nil` MUST call `openIfFile(_:)` instead of toggling expansion.
- **icon-chosen-by-node-type**: A row's icon MUST be `shippingbox.fill` for a
  package; for a directory, a name-specific icon (`.claude` gets `brain`,
  `.git` gets `arrow.triangle.branch`, `Sources`/`Source`/`src` get
  `folder.fill.badge.gearshape`, `Tests`/`test`/`tests` get
  `folder.fill.badge.questionmark`, any other dot-prefixed name gets
  `folder.badge.gearshape`, everything else gets `folder.fill`); for a file,
  an icon resolved by extension — a user-configured custom mapping first, then
  a shared built-in extension table, falling back to a generic document icon
  (`doc`) when neither matches.
- **icon-tint-by-role**: The icon's tint MUST come from the palette:
  `.warning` for a package, `.info` for a directory literally named
  `.claude`, `.accent` for every other directory, `.warning` for `.swift` and
  `.json` files, `.accent` for `.md` and `.markdown` files, and
  `.secondaryText` for any other file extension.
- **name-truncates-middle-single-line**: A file or directory's name label MUST
  truncate in the middle when it does not fit, and MUST render on a single
  line.
- **name-tooltip-is-full-path**: A file or directory row's name label MUST
  carry the node's full filesystem path as its tooltip.
- **git-status-recolors-name**: When a node has a non-`nil` `gitStatus`, its
  name label's text color MUST be overridden to that status's fixed color
  (`GitFileStatus.nsColor`), not a theme role.
- **git-status-shows-badge**: When a node has a non-`nil` `gitStatus`, its row
  MUST show a trailing badge whose text is that status's single display
  character, colored with the same fixed status color.
- **tree-carries-accessibility-id**: The outline view MUST carry the
  accessibility identifier `file-browser.tree`.
- **coder-init-unavailable**: `init(coder:)` MUST be marked unavailable at
  compile time and MUST call `fatalError` if invoked at runtime.
- **keyboard-and-typeahead-inherited**: The outline MUST support standard
  `NSOutlineView` keyboard navigation — arrow-key row movement and
  expand/collapse, and type-ahead row selection — since this file overrides
  none of that behavior.
- **testing-hooks-available**: The component MAY expose `selectedURLForTesting`,
  `selectedNodeInModelForTesting`, and `collapseAllForTesting()` as additional,
  `@testable`-only surface for verifying state in tests.

## Appearance

- **Corner radius**: None specified in source for the tree, its rows, or any
  row content view.
- **Padding**: Every row's content is inset 2pt from the row's leading edge
  and at most 6pt from its trailing edge (`FileTreeRowView`); a file/directory
  row's horizontal content stack additionally pins its trailing edge 6pt in
  from the row's own trailing edge.
- **Font**: Root header label — `.caption` text role. Placeholder label —
  `.caption` text role. File/directory name label — `.body` text role.
  Git-status badge — `.code` text role. (Text *role* here means the theme
  palette's `TextRole`, which resolves to a concrete font/size; no literal
  point size is set in this file.)
- **Background**: The outline itself fills with the `.windowBackground` theme
  role (`ThemedOutlineView(role: .windowBackground)`); no row or content view
  sets its own background fill in this file.
- **Foreground/Text**: Name label — `.primaryText` role, overridden per-node
  to a fixed git-status color when `gitStatus` is set. Root header label —
  `.primaryText` when its root is the current selection target,
  `.secondaryText` otherwise. Placeholder label — `.tertiaryText`. Git-status
  badge — `.primaryText` role, overridden to the same fixed status color as
  the name. Icon tint — semantic palette roles per node type (see
  `icon-tint-by-role`). Unsaved-changes marker — `.warning` theme role,
  regardless of node type.
- **Border**: None specified.
- **Shadow**: None specified.
- **Min/Max size**: Row height is fixed at 22pt (`outline.rowHeight = 22`);
  indentation per tree level is fixed at 14pt
  (`outline.indentationPerLevel = 14`); the icon is constrained to 16pt wide;
  the unsaved-changes marker glyph is rendered at 6pt point size, regular
  weight. No min/max width or height constraint is placed on the outline or
  its scroll view in this file.
- **Outline configuration**: `NSOutlineView.Style.inset`, header hidden
  (`headerView = nil`), a single non-resizing outline column
  (`autoresizesOutlineColumn = false`), single selection only
  (`allowsMultipleSelection = false`), empty selection permitted
  (`allowsEmptySelection = true`).
- **Scrolling**: Vertical scroller only, auto-hiding
  (`hasVerticalScroller = true`, `autohidesScrollers = true`).
- **Row content layout**: Icon, name, unsaved-changes marker, and (when
  present) a flexible spacer plus the git-status badge, laid out in a
  horizontal `NSStackView` with 5pt spacing, center-aligned vertically.

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
| Dirty | A file whose open document is dirty shows a filled-circle marker at the row's trailing edge, tinted `.warning`; the marker is hidden, not removed, when the document is clean. |
| Git status | A node with a non-`nil` `gitStatus` recolors its name label and shows a trailing single-character badge, both in that status's fixed color (orange=modified, green=added/untracked, red=deleted, blue=renamed/copied, purple=conflicted, gray=ignored). |

## Accessibility

- The outline view carries the accessibility identifier `file-browser.tree`
  (`tree-carries-accessibility-id`).
- Each row's icon carries an explicit accessibility description of "Folder"
  or "File", chosen by `node.isDirectory`. Because a package's `isDirectory`
  is also `true`, a package's icon is described as "Folder" even though a
  package behaves like an openable file (`open-opens-files-and-packages`),
  not like a directory a user discloses — a naming quirk of reusing
  `isDirectory` for the description text, not a functional defect.
- The unsaved-changes marker carries the accessibility description "Unsaved
  changes" and the accessibility identifier
  `whippet.filebrowser.dirty-indicator`. That identifier's prefix
  (`whippet.filebrowser`) does not match the tree's own identifier prefix
  (`file-browser.tree`) — a naming inconsistency present in source, carried
  here as-is rather than normalized.
- The outline MUST support standard `NSOutlineView` keyboard navigation and
  type-ahead selection (`keyboard-and-typeahead-inherited`); no key-handling
  code is added or overridden in this file, so whatever AppKit provides by
  default for an outline view with a data source and delegate applies
  unmodified.
- Differentiate Without Color: git status is never conveyed by color alone —
  every colored name and badge is paired with the status's own single-letter
  text (`M`, `A`, `D`, `R`, `C`, `?`, `U`, `!`); the dirty marker is conveyed
  by the presence or absence of a shape, not by a color distinction alone.
- Reduce Motion: Not applicable. This file contains no `NSAnimationContext`,
  transition, or motion effect of any kind; every visual change (reload,
  expand, collapse, recolor) is an immediate property or layout change.
- Increase Contrast: Not applicable at this component's level. Every color
  used through the theme palette (`.primaryText`, `.secondaryText`,
  `.tertiaryText`, `.accent`, `.info`, `.warning`, `.secondaryText`) is a
  semantic role resolved by the palette/theme system; this file contains no
  contrast-specific branching of its own, so any contrast adaptation belongs
  to that system, not here. Git-status colors are the one exception: they are
  fixed system colors (`NSColor.systemOrange`, etc.), chosen so every git
  client's red/orange/green vocabulary stays recognizable regardless of theme.
- Minimum tap target: Not applicable. This is a pointer-driven macOS control,
  not a touch surface; the 44×44pt guidance for touch targets does not apply.
  The actual row height is 22pt (`outline.rowHeight = 22`).
- NEEDS REVIEW: Not implemented in source. Behavior undefined. The git-status
  badge's visible text is the raw status character (`M`, `A`, `D`, `R`, `C`,
  `?`, `U`, `!`) with no separate accessibility label spelling out what it
  means (e.g. "Modified"); a screen-reader user would hear the bare character
  or punctuation mark read aloud, not a descriptive word. This is not resolved
  anywhere in `FileTreeOutlineViewController.swift` or `GitFileStatus`, and
  would be settled by adding an explicit accessibility label/description to
  the badge, or by product/accessibility review confirming the raw character
  is an acceptable VoiceOver experience.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-tree-outline-001 | top-level-rows-are-managers | Construct with `roots.managers` containing three `FileTreeManager`s. | The outline has exactly 3 top-level rows, in that order. |
| file-tree-outline-002 | child-ordering-directories-first | Expand a directory containing `zeta.txt`, `Alpha/`, `beta.txt`. | Rows appear as `Alpha/`, `beta.txt`, `zeta.txt`. |
| file-tree-outline-003 | hidden-files-shown-ds-store-excluded | Expand a directory containing `.env`, `.DS_Store`, `readme.md`. | `.env` and `readme.md` appear as rows; `.DS_Store` does not. |
| file-tree-outline-004 | empty-root-placeholder-text | A root manager with no `rootNode` children, `isSyncing == true`, then set to `false`. | Placeholder row reads "Scanning…", then "Empty" after the change. |
| file-tree-outline-005 | placeholder-not-selectable | Attempt to click-select a placeholder row. | The outline's selection does not change to the placeholder row. |
| file-tree-outline-006 | unread-directory-shows-triangle | A directory node with `children == []`. | `isItemExpandable` returns `true` for that node. |
| file-tree-outline-007 | leaf-hides-triangle | A file node, and a directory node whose read completed with `children == nil`. | `isItemExpandable` returns `false` for both. |
| file-tree-outline-008 | expand-loads-children-lazily | Expand an unread directory row. | `loadChildrenIfNeeded()` is called on that node. |
| file-tree-outline-009 | expand-watches-children-publisher | Expand a directory row, then publish a new `children` value on its node. | The row's subtree reloads without a further explicit call. |
| file-tree-outline-010 | children-arrival-reloads-subtree-only | Expand one directory among several drawn rows; its children arrive. | Only that directory's row/subtree is reloaded; sibling rows are untouched. |
| file-tree-outline-011 | children-arrival-preserves-expansion-and-selection | Expand directory A, select a file inside it, then have A's children publish again. | A remains expanded and the same file remains selected afterward. |
| file-tree-outline-012 | collapse-stops-watching-children | Expand then collapse a directory, then publish new `children` on its node. | No reload occurs as a result of that publish. |
| file-tree-outline-013 | expand-persists-to-restoration | Expand a directory row by clicking its disclosure triangle. | `restoration.isExpanded(path)` becomes `true` for that path. |
| file-tree-outline-014 | collapse-persists-to-restoration | Collapse a previously expanded directory row. | `restoration.isExpanded(path)` becomes `false` for that path. |
| file-tree-outline-015 | programmatic-expand-collapse-not-persisted | Call `collapseAllForTesting()`, then reload the outline while `restoration` still marks those paths expanded. | `restoration`'s stored expanded set is unchanged by the collapse-all call itself. |
| file-tree-outline-016 | lone-root-auto-expands-once | Construct with one root manager and an empty `restoration.expandedPaths`; reload; collapse the root; reload again. | The root auto-expands on the first reload only; it stays collapsed after the user closes it and a later reload. |
| file-tree-outline-017 | restore-expanded-paths-on-reload | Set `restoration` to mark two drawn directory paths expanded, then reload. | Both directories are expanded after the reload. |
| file-tree-outline-018 | restore-descends-incrementally | Set a pending restored selection three unread levels deep, then reload. | The selection is reached after the corresponding number of triggered reloads, not immediately. |
| file-tree-outline-019 | restore-abandons-missing-selection | Set a pending restored selection for a file that has since been deleted, with its parent directory drawn, expanded, and fully read. | The pending selection is cleared and no further restoration attempt occurs. |
| file-tree-outline-020 | select-root-sets-target-root | Click a root header row. | `selection.selectedRoot` equals that root's URL. |
| file-tree-outline-021 | select-node-sets-node-and-target-root | Click a file row under root R. | `selection.selectedNode` is that file's node; `selection.selectedRoot` becomes R. |
| file-tree-outline-022 | select-persists-path-unless-restore-pending | Click a file row with no pending restoration in progress. | `restoration.selectedPath` equals that file's path. |
| file-tree-outline-023 | select-opens-file | Click a file row. | `onOpenRequest` is called with that file's URL and `.current`. |
| file-tree-outline-024 | open-skips-plain-directories | Click a plain (non-package) directory row. | `onOpenRequest` is not called. |
| file-tree-outline-025 | open-opens-files-and-packages | Click a package row. | `onOpenRequest` is called with the package's URL and `.current`. |
| file-tree-outline-026 | external-selection-highlights-and-scrolls | Set `selection.selectedNode` to a drawn, off-screen row from outside the outline. | That row becomes selected and is scrolled into view. |
| file-tree-outline-027 | external-selection-suppresses-writeback | Perform the previous scenario. | `selection.selectedNode` is not reassigned a second time as a side effect. |
| file-tree-outline-028 | external-deselect-clears-highlight | With a `FileTreeNode` row selected, set `selection.selectedNode` to `nil`. | The outline's selection is cleared. |
| file-tree-outline-029 | target-root-header-emphasis | Set `selection.selectedRoot` to root B among three roots. | Root B's header renders `.primaryText`; the other two render `.secondaryText`. |
| file-tree-outline-030 | target-root-change-redraws-headers | Set `selection.selectedRoot` to the same value it already holds. | No reload occurs. |
| file-tree-outline-031 | managers-list-change-reloads | Append a new `FileTreeManager` to `roots.managers`. | The outline reloads and shows the new root. |
| file-tree-outline-032 | root-node-change-reloads | Replace a manager's `rootNode`. | The outline reloads. |
| file-tree-outline-033 | syncing-change-reloads | Toggle a manager's `isSyncing`. | The outline reloads. |
| file-tree-outline-034 | reload-preserves-selection | Select a file, then trigger a full reload without removing that file. | The same file remains selected afterward. |
| file-tree-outline-035 | reload-clears-selection-when-row-gone | Select a file, delete its underlying node from the model, then trigger a full reload. | `selection.selectedNode` becomes `nil`. |
| file-tree-outline-036 | path-lookup-correct-after-structural-change | Expand a directory (adding rows), then immediately look up the row for a path below it. | The lookup returns the row currently showing that path, not a pre-expansion index. |
| file-tree-outline-037 | row-lookup-avoids-full-scan | Perform two lookups for the same path with no structural change between them. | The second lookup is served without re-scanning every drawn row. |
| file-tree-outline-038 | dirty-updates-row-in-place | Mark an open, drawn file's document dirty. | Only that row's marker becomes visible; no reload or reselection occurs. |
| file-tree-outline-039 | dirty-falls-back-to-item-reload | Mark a drawn file dirty after its row view has been recycled away by the outline. | That one item is reloaded, and the current selection is unchanged afterward. |
| file-tree-outline-040 | dirty-ignored-when-row-not-drawn | Fire a dirty-state-change event for a file whose row is not currently drawn (its parent is collapsed). | No row update, reload, or crash occurs. |
| file-tree-outline-041 | dirty-marker-always-built | Inspect a clean file's row view. | The marker view exists in the view hierarchy and is hidden. |
| file-tree-outline-042 | reveal-noop-if-already-shown | Call `reveal(url)` for the URL that is already selected. | No selection, expansion, or scroll change occurs. |
| file-tree-outline-043 | reveal-expands-drawn-ancestors | Call `reveal(url)` for a file two collapsed, drawn levels deep. | Both ancestor directories expand. |
| file-tree-outline-044 | reveal-selects-and-scrolls-when-drawn | Call `reveal(url)` for a file whose row becomes drawn after its ancestors expand. | That row is selected and scrolled into view. |
| file-tree-outline-045 | reveal-writes-model-directly | Call `reveal(url)` for a drawn target. | `selection.selectedNode` equals the revealed node without relying on a separate selection click. |
| file-tree-outline-046 | reveal-defers-when-not-drawn | Call `reveal(url)` for a file under a directory that has not yet been read. | The reveal is recorded as pending and completes once that directory's contents arrive. |
| file-tree-outline-047 | reveal-nothing-clears-selection | Call `revealNothing()` with a row selected. | The outline deselects all rows and `selection.selectedNode` becomes `nil`. |
| file-tree-outline-048 | context-menu-uses-clicked-row | Right-click file A while file B is the current selection. | The menu is built for file A, not file B. |
| file-tree-outline-049 | context-menu-omitted-for-missing-path | Right-click a row whose file has just been deleted from disk. | No menu items are added. |
| file-tree-outline-050 | context-menu-hides-open-items-for-directories | Right-click a plain directory row. | The menu shows only "Reveal in Finder" and "Copy Path". |
| file-tree-outline-051 | context-menu-item-order | Right-click a file row. | Menu order is Open, Open in a New Tab, Open to the Side, separator, Reveal in Finder, Copy Path. |
| file-tree-outline-052 | context-menu-open-forwards-destination | Choose "Open to the Side" from a file's context menu. | `onOpenRequest` is called with that file's URL and `.toTheSide`. |
| file-tree-outline-053 | context-menu-reveal-in-finder | Choose "Reveal in Finder". | `NSWorkspace.shared.activateFileViewerSelecting(_:)` is called with that row's URL. |
| file-tree-outline-054 | context-menu-copy-path-is-posix | Choose "Copy Path" for a file at `/Users/x/Notes.md`. | The pasteboard's string is `/Users/x/Notes.md`, not a `file://` URL. |
| file-tree-outline-055 | double-click-toggles-root | Double-click a collapsed root header, then double-click it again. | It expands, then collapses. |
| file-tree-outline-056 | double-click-toggles-loaded-node | Double-click a directory row with `children != nil`. | Its expansion toggles. |
| file-tree-outline-057 | double-click-opens-otherwise | Double-click a file row (`children == nil`). | `onOpenRequest` is called instead of any expansion change. |
| file-tree-outline-058 | icon-chosen-by-node-type | Inspect rows for a `.claude` directory, a `Tests` directory, a `.xcodeproj` package, and a `.swift` file. | Icons are `brain`, `folder.fill.badge.questionmark`, `shippingbox.fill`, and the file's extension-resolved icon, respectively. |
| file-tree-outline-059 | icon-tint-by-role | Inspect icon tints for a package, a `.claude` directory, an ordinary directory, and a `.swift` file. | Tints resolve to `.warning`, `.info`, `.accent`, and `.warning` respectively. |
| file-tree-outline-060 | name-truncates-middle-single-line | Render a name too long for the row's width. | The label truncates in the middle and stays on one line. |
| file-tree-outline-061 | name-tooltip-is-full-path | Hover a row's name label. | The tooltip shows the node's full filesystem path. |
| file-tree-outline-062 | git-status-recolors-name | Give a node `gitStatus == .modified`. | The name label's text color equals `NSColor.systemOrange`. |
| file-tree-outline-063 | git-status-shows-badge | Give a node `gitStatus == .deleted`. | A trailing badge reading "D" appears in `NSColor.systemRed`. |
| file-tree-outline-064 | tree-carries-accessibility-id | Inspect the outline view's accessibility identifier. | It equals `file-browser.tree`. |
| file-tree-outline-065 | coder-init-unavailable | Attempt to construct via `NSCoder`-based decoding. | Compilation fails (unavailable), or a runtime `fatalError` occurs if bypassed. |
| file-tree-outline-066 | keyboard-and-typeahead-inherited | With the outline focused, press the down-arrow key, then type a letter matching a row's first character. | Selection moves to the next row, then jumps to the type-ahead match; no custom key handler intercepts either. |
| file-tree-outline-067 | testing-hooks-available | Select a node, then read `selectedURLForTesting` and `selectedNodeInModelForTesting`. | Both reflect the current selection. |

## Edge Cases

- **Null/empty input**: An empty root (no `rootNode`, or `rootNode.children`
  empty) renders the placeholder row rather than zero rows (see
  `empty-root-placeholder-text`); the placeholder is never selectable and
  never opens anything. `restoreDisclosure()` MUST do nothing further when
  `pendingSelectionPath` is `nil`. A document event whose URI does not parse
  into a `URL` (`URL(string: uri)` returns `nil`) MUST be silently ignored.
- **Boundary values**: The one-shot auto-expand
  (`lone-root-auto-expands-once`) only applies when there is exactly one root
  manager and `restoration.expandedPaths` is empty; a browser with two or
  more roots always starts fully collapsed unless `restoration` says
  otherwise. Restoring a selection many directory levels deep has no explicit
  maximum-depth cap in source; it is bounded only by how many reload cycles
  the real directory depth requires (`restore-descends-incrementally`).
- **Concurrent access**: This controller, `FileTreeManager`,
  `FileBrowserSelection`, `FileBrowserRestorationState`, and
  `TextDocumentStore` are all `@MainActor`-isolated, and every Combine
  subscription this file installs additionally hops
  `.receive(on: RunLoop.main)`. `FileTreeNode.loadChildrenIfNeeded()` performs
  its filesystem read on a background queue but publishes the result back via
  `DispatchQueue.main.async`, so this controller never observes a children
  update off the main thread. Multiple browser panes can share one
  `FileBrowserSelection`/`FileBrowserRestorationState`; a selection or
  disclosure change made by one pane's outline is observed and mirrored by
  every other pane's own `isSyncingSelection`/`isSyncingExpansion`-guarded
  code path, so cross-pane updates highlight/disclose without looping back
  into a second write.
- **Error states**: A directory whose contents cannot be read (for example,
  permission denied) is rendered identically to a genuinely empty directory —
  the "Empty" placeholder — because `FileTreeNode.loadChildren` swallows a
  `contentsOfDirectory` failure into an empty array before it ever reaches
  this controller; this component surfaces no distinct error state or
  affordance for that case. A context-menu action for a path that no longer
  exists on disk produces no menu items rather than an error dialog (see
  `context-menu-omitted-for-missing-path`). If the row selected before a
  reload can no longer be found by identity or by path, the component treats
  that as "the user's file is gone" and clears the selection
  (`reload-clears-selection-when-row-gone`) rather than treating it as an
  error condition.
- **Offline/disconnected state**: Not applicable. This component reads and
  watches the local filesystem only; it makes no network requests, so there
  is no connectivity-loss behavior to define here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `roots` | `FileBrowserRootsModel` | required (no default) | Supplies the ordered list of `FileTreeManager`s shown as top-level rows. |
| `directories` | `FileBrowserDirectories` | required (no default) | The root URLs used to resolve which root a clicked node's target-selection belongs to. |
| `selection` | `FileBrowserSelection` | required (no default) | Shared selected-node/selected-root object; supply one to let a host read or drive the selection. |
| `restoration` | `FileBrowserRestorationState` | required (no default) | Shared expanded-paths/selected-path object; supply one to restore or persist disclosure and selection across launches. |
| `documentStore` | `TextDocumentStore` | required (no default) | App-wide open-document registry; supplies the dirty state shown by each file row's unsaved-changes marker. |
| `onOpenRequest` | `((URL, DocumentDestination) -> Void)?` | `nil` | Set by a host to receive open requests — from a click, double-click, or context-menu choice — naming the file and where it should be shown. |

## Deep Linking

Not applicable: `FileTreeOutlineViewController.swift` contains no URL-scheme
or route handling. Opening a file is expressed only through the
`onOpenRequest` closure, carrying a plain `URL` and a `DocumentDestination`,
not an app-URL or route.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Scanning…` | Placeholder row text while a root manager is syncing, a literal `String`. |
| (none defined in source) | `Empty` | Placeholder row text for a root with no contents, a literal `String`. |
| (none defined in source) | `Open` | Context menu item title, a literal `String`. |
| (none defined in source) | `Open in a New Tab` | Context menu item title, a literal `String`. |
| (none defined in source) | `Open to the Side` | Context menu item title, a literal `String`. |
| (none defined in source) | `Reveal in Finder` | Context menu item title, a literal `String`. |
| (none defined in source) | `Copy Path` | Context menu item title, a literal `String`. |
| (none defined in source) | `Folder` | Icon accessibility description for a directory, a literal `String`. |
| (none defined in source) | `File` | Icon accessibility description for a file, a literal `String`. |
| (none defined in source) | `Unsaved changes` | Unsaved-changes marker accessibility description, a literal `String`. |

NEEDS REVIEW: Not implemented in source. Behavior undefined. All ten strings
above are assigned directly as `String` literals to AppKit properties
(`NSTextField`/`ThemedLabel` string values, `NSMenuItem.title`,
`accessibilityDescription:`) rather than through any localization key or
`NSLocalizedString` call — this is an AppKit file, so none of these literals
gets SwiftUI's automatic `LocalizedStringKey` treatment. What is missing is a
defined string-key scheme for this component; it would be settled by the
host app's localization owner choosing keys and wiring them in. File and
directory names themselves are user data, not chrome text, and are correctly
excluded from this table.

## Accessibility Options

- **Reduce Motion**: Not applicable. Source contains no animation of any
  kind — every reload, expansion, collapse, and recolor is an immediate
  property or layout change, with no `NSAnimationContext`, transition, or
  opacity fade to substitute.
- **Increase Contrast**: Not applicable at this component's level. All
  non-git colors are semantic theme roles (`.primaryText`, `.secondaryText`,
  `.tertiaryText`, `.accent`, `.info`, `.warning`); `FileTreeOutlineViewController.swift`
  contains no contrast-specific branching of its own, so any adaptation lives
  in the theme/palette system, not here.
- **Differentiate Without Color**: Supported. Git status is always shown as a
  status letter (`M`, `A`, `D`, `R`, `C`, `?`, `U`, `!`) in addition to color,
  never by color alone; the dirty marker is a shape whose presence or absence
  carries the meaning, not a color change on an otherwise-identical shape.

## Feature Flags

Not applicable: `FileTreeOutlineViewController.swift` contains no
feature-flag or build-configuration check of any kind.

## Analytics

Not applicable: `FileTreeOutlineViewController.swift` contains no analytics
or event-tracking calls.

## Privacy

- **Data collected**: File and directory paths the user browses, expands, and
  selects on their own local filesystem; the presence of open documents and
  their dirty state, read from the injected `TextDocumentStore`. Nothing is
  collected automatically beyond what the user's own filesystem and open
  documents already contain.
- **Storage**: This component does not itself write to disk or
  `UserDefaults`. Disclosure and selection changes flow out through
  `FileBrowserRestorationState.onChange`, a closure the host supplies and
  which decides whether and where to persist them (see
  `FileBrowserRestorationState.swift`); this controller only calls
  `setExpanded(_:path:)` and `setSelectedPath(_:)` on that shared object.
- **Transmission**: None. `FileTreeOutlineViewController.swift` makes no
  network calls.
- **Retention**: Determined entirely by the host through
  `FileBrowserRestorationState.onChange`; this component keeps disclosure and
  selection state only in memory, for as long as the controller and its
  injected model objects live.

## Logging

Not applicable: `FileTreeOutlineViewController.swift` contains no `os_log`,
`Logger`, or other logging calls.

## Platform Notes

- **SwiftUI**: The source is pure AppKit (`NSViewController`/`NSOutlineView`),
  deliberately, not SwiftUI — the file's own header comment states that a
  SwiftUI `List` row's tap gesture does not fire reliably when attached to
  arbitrary row content, and that a directory's row, being a disclosure-group
  label, is not something a `List` will select at all; `NSOutlineView`
  selects on mouse-down for every row it draws, which this component relies
  on directly. A SwiftUI port would need `OutlineGroup` or a hand-rolled
  recursive `DisclosureGroup`/`List` combination verified specifically for
  whole-row tap and directory-row selection before adopting it, not a
  drop-in `List(rootNode, children: \.children)`.
- **Compose**: Flatten the currently-visible nodes (respecting each
  directory's expanded/collapsed state) into a single list driven by a
  `LazyColumn`, the way a Compose file-tree is conventionally built; back
  expansion/selection with `remember`/`mutableStateOf` or a `ViewModel`
  exposing `StateFlow`s equivalent to `FileBrowserSelection`/
  `FileBrowserRestorationState`, and trigger a lazy child load from the same
  "row entered the visible window and is a directory with no children yet"
  condition this file expresses as `outlineViewItemWillExpand`.
- **React/Web**: Model the tree as a virtualized list or a headless tree
  library (row-per-visible-node, like the Compose approach) rather than
  nested `<ul>`/`<li>` DOM for every directory, to avoid the DOM cost of a
  large monorepo tree; a row's whole clickable area maps to a single
  `onClick` handler rather than a nested interactive control, mirroring why
  this file avoids a component-per-row tap gesture.
- **AppKit / UIKit**: This is the source platform. `FileTreeOutlineViewController.swift`
  configures a single-column `NSOutlineView` (`ThemedOutlineView`) with
  `rowHeight = 22`, `indentationPerLevel = 14`, `style = .inset`, and a
  hidden header, driving it as both `NSOutlineViewDataSource` and
  `NSOutlineViewDelegate`. On iOS there is no `NSOutlineView` equivalent;
  a `UITableView`/`UICollectionView` with manually flattened, indented rows
  (the same flattening approach as the Compose/React notes above) is the
  usual substitute, since `UIOutlineView` does not exist.
- **WinUI 3**: This is the platform this recipe exists to serve. Model the
  tree as a `TreeView` bound to a hierarchical `ItemsSource` mirroring
  `FileTreeManager`/`FileTreeNode` (one top-level `TreeViewNode` per root,
  matching `top-level-rows-are-managers`); use `TreeViewNode.HasUnrealizedChildren`
  plus the `Expanding` event to drive the same lazy-load-on-first-expand
  behavior as `expand-loads-children-lazily`, and the `Collapsed`/`Expanded`
  events to persist disclosure the way `expand-persists-to-restoration`/
  `collapse-persists-to-restoration` do. Drive `TreeView.SelectionChanged`
  into the same selection/target-root logic as
  `select-node-sets-node-and-target-root`, and use `TreeView.ItemInvoked`
  (or a double-tap gesture) for `double-click-opens-otherwise`. Build the
  context menu from `TreeViewItem.ContextFlyout` populated with
  `MenuFlyoutItem`s in the same Open/Open-in-New-Tab/Open-to-the-Side,
  separator, Reveal, Copy-Path order as `context-menu-item-order`, keyed off
  the flyout's own target node rather than the current selection — the WinUI
  analog of `context-menu-uses-clicked-row`. Represent the root-header
  emphasis (`target-root-header-emphasis`) as a `FontWeight`/`Foreground`
  binding on each root `TreeViewNode`'s content, driven by whichever root is
  the current target. Render the git-status badge as a `TextBlock` whose text
  and `Foreground` both bind to the node's status through a value converter
  mirroring `GitFileStatus.nsColor`'s fixed enum-to-color mapping, and the
  unsaved-changes marker as a small `Ellipse`/`FontIcon` whose `Visibility`
  binds to the same dirty flag, always present in the item template and
  toggled by binding rather than added/removed — the WinUI analog of
  `dirty-marker-always-built`.

## Design Decisions

Decision: Use `NSOutlineView` rather than a SwiftUI `List` for the tree.
Rationale: the file's own header comment states a SwiftUI list row's tap
gesture attached to the row's content never fires, and a directory's row,
being a disclosure-group label, is not something a `List` will select at
all — half the tree answered a click with nothing. `NSOutlineView` selects on
mouse-down for every row it draws, which is the behavior this component
needs.
Approved: pending.

Decision: Use `children == nil` for a leaf, a package, *and* a directory that
was read and found empty — rather than reserving `nil` for leaves only — and
disambiguate the "was this a directory?" question downstream in
`openIfFile(_:)` via `!isDirectory || isPackage`, not via the children value
itself.
Rationale: `FileTreeNode` deliberately sets `children = nil` (not `[]`) for a
directory that reads empty, "so the outline reads an empty array as
'expandable, not yet read'" — keeping `[]` would leave a disclosure triangle
that opens onto nothing. `openIfFile(_:)`'s own guard is what then stops a
double-click or single-click on that now-leaf-shaped empty directory from
being sent to the document viewer as if it were a file.
Approved: pending.

Decision: Cache path→row lookups (`rowIndexByPath`) lazily, and verify a
cache hit against the row's actual content before trusting it, rather than
either always scanning or always trusting the cache.
Rationale: the source comment explains this controller is a
`TextDocumentStore` observer, so every keystroke in *any* open document, in
*every* open file browser, used to cost an O(rows) path-string scan; the
verify-before-trust step exists because a stale hit would otherwise silently
redraw or reselect the wrong file rather than fail loudly.
Approved: pending.

Decision: Use two independent guard flags, `isSyncingSelection` and
`isSyncingExpansion`, rather than a single "the controller is currently
driving the outline" flag.
Rationale: each guards a different feedback loop — `isSyncingSelection`
stops a model-driven selection change from being reported back through
`outlineViewSelectionDidChange`, and `isSyncingExpansion` stops a
restoration- or reveal-driven expand/collapse from being reported back
through `outlineViewItemDidExpand`/`outlineViewItemDidCollapse` — and the two
kinds of programmatic change do not always happen together (restoring
disclosure without touching selection, or vice versa).
Approved: pending.

Decision: `reveal(_:)`/`revealNothing()` write `selection.selectedNode` and
`selection.selectedRoot` directly (`adoptRevealedSelection(_:)`) instead of
relying on the outline's own selection-changed delegate callback to record
the change.
Rationale: the source comment distinguishes "the highlight" from "the
selection" — `isSyncingSelection` deliberately stops the outline's own report
from being written back (so a reveal is not echoed to whatever editor pane it
came from), which would otherwise leave `selection` naming a stale file and
`selectedRoot` pointing at the wrong project root.
Approved: pending.

Decision: Restore a deeply nested expanded/selected path incrementally,
across as many reloads as the depth requires, rather than requiring the
whole path to already be drawn.
Rationale: expanding a directory only *starts* an asynchronous read of its
contents; the source comment explains the loop terminates naturally because
a pass that expands nothing triggers no further reload, so a fixed-depth
single pass would leave anything below the first unread level permanently
unrestored.
Approved: pending.

Decision: Leave `selection.selectedRoot`/orphaned-selection cleanup, when a
root disappears entirely, to the hosting `FileBrowserViewController` rather
than handling it in this file.
Rationale: `reselect(_:)` only clears `selection.selectedNode` when the
outgoing selection was a `FileTreeNode`; a selected root *header*
(`FileTreeManager`) that disappears from a reload is not cleared here. The
sibling `file-browser-view-controller` recipe's
`teardown-clears-orphaned-root-selection` requirement is what actually
guarantees `selection.selectedRoot` is cleared when its root is removed.
Approved: pending.

## Compliance

No automated compliance checks have been run against this recipe yet. This
table will be populated by the cookbook's compliance tooling on review.

| Check | Status | Category |
|-------|--------|----------|

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
