<!-- leaf: implement-file/tree-outline-view-controller--part-3 · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller — continued (part 3)

**Rules** (cite as `implement-file/tree-outline-view-controller--part-3#<slug>`):

- `context-menu-uses-clicked-row` MUST
- `context-menu-omitted-for-missing-path` MUST
- `context-menu-hides-open-items-for-directories` MUST
- `context-menu-item-order` MUST
- `context-menu-open-forwards-destination` MUST
- `context-menu-reveal-in-finder` MUST
- `copy-path-format` MUST
- `double-click-toggles-root` MUST
- `double-click-toggles-loaded-node` MUST
- `double-click-opens-otherwise` MUST
- `icon-chosen-by-node-type` MUST
- `icon-tint-by-role` MUST
- `name-truncation` MUST
- `name-tooltip-is-full-path` MUST
- `git-status-recolors-name` MUST
- `git-status-shows-badge` MUST
- `tree-carries-accessibility-id` MUST
- `coder-init-unavailable` MUST
- `keyboard-and-typeahead-inherited` MUST
- `restore-disclosure-noop-without-pending` MUST
- `document-event-ignores-unparseable-uri` MUST
- `outline-support-standard-nsoutlineview-keyboard` MUST — The outline MUST support standard NSOutlineView keyboard navigation and type-ahead selection …

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
- **copy-path-format**: Choosing "Copy Path" MUST place the
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
- **name-truncation**: A file or directory's name label MUST
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
- **restore-disclosure-noop-without-pending**: `restoreDisclosure()` MUST do
  nothing further once the ancestor-expansion pass completes when there is no
  pending restored selection (`pendingSelectionPath == nil`).
- **document-event-ignores-unparseable-uri**: A document event whose URI does
  not parse into a `URL` (`URL(string: uri)` returns `nil`) MUST be silently
  ignored.
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
- Reduce Motion, Increase Contrast, Differentiate Without Color: see
  **Accessibility Options** below.
- Minimum tap target: Not applicable. This is a pointer-driven macOS control,
  not a touch surface; the 44×44pt guidance for touch targets does not apply.
  The actual row height is 22pt (`outline.rowHeight = 22`).
- The git-status badge is a plain `ThemedLabel` carrying only the raw status
  character (`M`, `A`, `D`, `R`, `C`, `?`, `U`, `!`) as its text; unlike the
  row's icon and unsaved-changes marker, it has no accessibility label or
  description of its own, so VoiceOver announces the bare character or
  punctuation mark rather than a descriptive word such as "Modified".

