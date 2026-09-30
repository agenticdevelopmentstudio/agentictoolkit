<!-- leaf: implement-general-controller/topic-list-view-controller · source: topic-list-view-controller.md -->

**Rules** (cite as `implement-general-controller/topic-list-view-controller#<slug>`):

- `group-items-by-section` MUST
- `header-row-for-titled-section` MUST
- `omit-header-for-untitled-section` MUST
- `flat-row-hierarchy` MUST
- `hide-disclosure-controls` MUST
- `hide-outline-column-header` MUST
- `header-rows-not-selectable` MUST
- `disabled-item-selectability` MUST
- `mute-disabled-item-appearance` MUST
- `render-item-without-icon-when-nil` MUST
- `user-selection-callback` MUST
- `suppress-onselect-on-programmatic-selection` MUST
- `select-item-by-id` MUST
- `missing-id-selection` MUST
- `noop-select-already-selected-id` MUST
- `restore-selection-by-id-after-resection` MUST
- `restore-selection-across-theme-change` MUST
- `stable-row-node-identity` MUST
- `hide-header-when-title-and-accessory-empty` MUST
- `hide-footer-when-unset` MUST
- `header-accessory-below-title` MUST
- `footer-spans-sidebar-width` MUST
- `content-below-titlebar-safe-area` MUST
- `preferred-width` MUST
- `item-accessibility-id-from-title` MUST
- `ax-press-selection` MUST
- `repaint-on-theme-change` MUST
- `single-column-fills-width` MUST
- `overlay-autohide-scroller` MUST
- `automatic-outline-style` MUST

# TopicListViewController

## Overview

`TopicListViewController` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`)
is a reusable, `@MainActor`, `open` `NSViewController` that renders a
sectioned, single-selection `NSOutlineView` sidebar. Per its own doc comment
it is "a reusable AppKit list with optional section headers, SF-Symbol-friendly
icons, and closure-based selection," and it "knows nothing about settings,
the host app, or any specific data domain." A caller supplies rows through
`setItems(_:)` (a flat list, no section headers) or `setSections(_:)`
(grouped rows, each `TopicListSection` optionally titled) and observes the
user's selection through the `onSelect` closure. `PanelListViewController`
(see `related`) is one concrete consumer: it subclasses this controller to
back the sidebar of `ComposableSettings.SplitViewController`.

Beyond the outline itself, the controller owns an optional title header
(shown above the list, with an optional client accessory view such as a
search field beneath the title) and an optional client footer view pinned
below the list — both collapse to zero height when unset. The whole view
repaints itself on every theme change via `ThemePaletteObserver`.

Two distinct "header" concepts appear in source and are kept separate
throughout this recipe: the controller's own `headerView` (the custom title
+ accessory area above the list) and `outlineView.headerView`, AppKit's
built-in table **column** header row, which this component always disables.
A `TopicListSection`'s optional title renders as a **group header row**
inside the outline itself — a third, unrelated use of "header."

## Behavioral Requirements

- **group-items-by-section**: Component MUST render every section's items,
  in the order sections and items are given to `setSections(_:)`, as leaf
  rows of a single flat outline.
- **header-row-for-titled-section**: Component MUST render a group header
  row carrying the section's title for every `TopicListSection` whose
  `title` is a non-nil, non-empty string.
- **omit-header-for-untitled-section**: Component MUST NOT render a group
  header row for a section whose `title` is `nil` or empty — only a
  non-nil, non-empty title produces a header node.
- **flat-row-hierarchy**: Component MUST report every row — header and item
  alike — as not expandable (`isItemExpandable` always returns `false`) and
  MUST set `indentationPerLevel = 0`, so no row is ever indented or nested
  under another.
- **hide-disclosure-controls**: Component MUST hide the outline's disclosure
  triangle for every row (`shouldShowOutlineCellForItem` always returns
  `false`).
- **hide-outline-column-header**: Component MUST set `outlineView.headerView
  = nil`, so AppKit's built-in table column header bar is never drawn above
  the rows.
- **header-rows-not-selectable**: Component MUST prevent a group header row
  from becoming selected; `shouldSelectItem` returns `true` only for a node
  whose kind is `.item`.
- **disabled-item-selectability**: Component MUST allow selecting an
  item whose `isDisabled == true` through exactly the same paths, and with
  exactly the same result, as an item whose `isDisabled == false` — the
  outline delegate's `shouldSelectItem` check and an item row's
  accessibility press handler (`accessibilityPerformPress()`) both branch
  only on node kind (`.item` vs. `.header`), never on `isDisabled`.
- **mute-disabled-item-appearance**: Component MUST render an item whose
  `isDisabled == true` with `palette.tertiaryTextColor` for both its label
  text and its icon tint, instead of `palette.primaryTextColor` (label) and
  `palette.accentColor` (icon tint) used for an enabled item.
- **render-item-without-icon-when-nil**: Component MUST render an item row
  whose `icon` is `nil` with no image in its image view, since
  `TopicListItem.icon` is an `NSImage?` assigned directly to
  `cell.imageView?.image`.
- **user-selection-callback**: Component MUST invoke
  `onSelect` with the newly selected item, or `nil` if none, whenever the
  outline's selection changes as a direct result of user interaction (i.e.
  outside any selection-suppression scope — see
  **suppress-onselect-on-programmatic-selection**).
- **suppress-onselect-on-programmatic-selection**: Component MUST NOT invoke
  `onSelect` for a selection change made during a programmatic-selection
  scope — i.e. the reload-and-restore performed by `setSections(_:)` and by
  `applyTheme(_:)`, and the selection made by `selectItem(withId:)`.
- **select-item-by-id**: `selectItem(withId:)` MUST select the row of the
  first item, in section/item order, whose id matches the given id, without
  firing `onSelect`.
- **missing-id-selection**: `selectItem(withId:)` MUST leave the current
  selection unchanged when no item's id matches the given id.
- **noop-select-already-selected-id**: `selectItem(withId:)` MUST leave the
  current selection unchanged, and MUST NOT call `selectRowIndexes`, when
  the matching row is already the selected row.
- **restore-selection-by-id-after-resection**: `setSections(_:)` MUST
  re-select, by id, whichever item was selected immediately before the
  call, if an item with that id is still present in the new sections.
- **restore-selection-across-theme-change**: `applyTheme(_:)` MUST preserve
  the outline's selected row indexes across the `reloadData()` it performs,
  re-selecting them with `selectRowIndexes` when they differ afterward.
- **stable-row-node-identity**: Component MUST let `outlineView.row(forItem:)`
  resolve to the same valid row for a given logical row across repeated
  accesses between one `setSections(_:)` call and the next, rather than
  losing that identity (and returning `-1`) because a fresh instance was
  constructed for that row on each access.
- **hide-header-when-title-and-accessory-empty**: Component MUST hide the
  title header view when the trimmed title is empty AND no header accessory
  view is set.
- **hide-footer-when-unset**: Component MUST hide the footer container when
  `footerView` is `nil`.
- **header-accessory-below-title**: When a header accessory view is set via
  `setHeaderAccessoryView(_:)`, component MUST lay it out directly below the
  title label, spanning the full width of the header area.
- **footer-spans-sidebar-width**: A footer view installed via
  `setFooterView(_:)` MUST have its leading, trailing, top, and bottom
  anchors pinned to its container's, spanning the sidebar's full width.
- **content-below-titlebar-safe-area**: Component MUST keep its list content
  below the window's non-safe top inset (e.g. a full-height window's
  titlebar) by pinning its content's top edge to the root view's
  `safeAreaLayoutGuide.topAnchor` rather than its plain `topAnchor`, while
  its leading/trailing/bottom edges match the root view's own edges.
- **preferred-width**: `preferredWidth()` MUST return exactly
  `max(titleCandidate, headerCandidates…, itemCandidates…) +
  outlineChromePadding` — the widest text-based candidate (the title's
  rendered width plus `CellMetrics.titleLeadingInset`; each section header's
  rendered width plus `CellMetrics.headerLeadingInset`; each item's rendered
  width plus `CellMetrics.itemChromeWidth`; defaulting to 0 when there is no
  title, header, or item), plus the fixed `outlineChromePadding` (64pt: 30
  leading inset + 16 scroller gutter + 18 trailing margin) — then MUST widen
  that further to at least the footer view's `fittingSize.width` (when a
  footer is set) and to at least the header accessory view's
  `fittingSize.width` plus `CellMetrics.titleLeadingInset` and
  `CellMetrics.headerTrailingInset` (when an accessory is set). The footer
  and accessory floors are absolute widths, not added to
  `outlineChromePadding`.
- **item-accessibility-id-from-title**: Component MUST set each item row's
  label accessibility identifier to `"topic-list.item.\(AccessibilityID.slug(item.title))"`
  — derived from the item's **title**, not its `id`.
- **ax-press-selection**: An item row's label MUST respond to
  `accessibilityPerformPress()` by locating its row in the enclosing outline
  and calling `selectRowIndexes` on it, and MUST first call the delegate's
  `shouldSelectItem` for that row and return `false` without selecting when
  that call returns `false`.
- **repaint-on-theme-change**: Component MUST update the background color of
  the root view, `contentStack`, `headerView`, and `footerContainer`, the
  title label's font and text color, and the scroll/outline view background,
  to the newly observed `SemanticPalette`'s values every time
  `ThemePaletteObserver` reports a palette change.
- **single-column-fills-width**: The outline's one `NSTableColumn` MUST be
  resized to fill the outline's available width on every layout pass, so no
  row ever clips its label regardless of when the enclosing view settles the
  sidebar's width.
- **overlay-autohide-scroller**: Component MUST configure the scroll view
  with `scrollerStyle = .overlay` and `autohidesScrollers = true`, so the
  vertical scroller floats over content and only appears while scrolling and
  while the list overflows.
- **automatic-outline-style**: Component MUST render the outline with a
  theme-following material rather than a forced dark source-list material,
  regardless of the active appearance — observable as `outlineView.style ==
  .automatic`, never `.sourceList`.

