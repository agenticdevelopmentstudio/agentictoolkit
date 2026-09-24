---
id: ce223be3-818a-4310-b136-9e1e84e9af54
title: TopicListViewController
domain: agentictoolkit://recipes/topic-list-view-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Domain-agnostic AppKit outline sidebar: sectioned rows, single selection,
  optional title/footer/header-accessory, theme-driven repaint, and an AXPress-reachable
  row label'
platforms:
- swift
- macos
tags:
- sidebar
- list
- selection
- view-controller
- appkit
depends-on: []
related:
- agentictoolkit://recipes/settings-panel-list-view-controller
references:
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
approved-by: ''
approved-date: ''
---

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

## Appearance

- **Corner radius**: 4pt (`xRadius`/`yRadius`) on the selection-highlight
  rounded rect drawn by `ThemedTableRowView.drawSelection(in:)`, the row
  view this controller returns from `outlineView(_:rowViewForItem:)`. No
  other corner radius appears in this file.
- **Padding**: Title header: 10pt top / 6pt bottom inset from `headerView`'s
  edges to `headerStack`; 14pt leading (`titleLeadingInset`) and 14pt
  trailing (`headerTrailingInset`) inset from `headerView`'s edges to
  `headerStack`; 8pt vertical gap (`headerAccessorySpacing`) between the
  title label and the accessory container. Item cell: 4pt leading inset
  (`iconLeadingInset`) from the cell to the icon; 6pt gap
  (`iconToTextGap`) between icon and label; 4pt trailing inset
  (`textTrailingInset`) from the label to the cell's trailing edge. Header
  (group) cell: 2pt leading inset (`headerLeadingInset`), vertically
  centered.
- **Font**: `CellMetrics.itemFont` = `palette.font(.body)` (item labels);
  `CellMetrics.headerFont` = `palette.font(.caption)` (group header labels);
  `CellMetrics.titleFont` = `palette.font(.button)` (title label). All three
  read the live theme palette rather than a fixed point size, and are
  reapplied on every cell reuse (`viewFor tableColumn:` runs on pooled
  cells) rather than baked in once at cell creation.
- **Background**: `view`, `contentStack`, `headerView`, and `footerContainer`
  are all painted with `palette.windowBackgroundColor` via their
  `CALayer.backgroundColor` in `applyTheme(_:)`; `scrollView.backgroundColor`
  and `outlineView.backgroundColor` are set to the same value.
- **Foreground/Text**: Item label: `palette.primaryTextColor` when enabled,
  `palette.tertiaryTextColor` when `isDisabled`. Item icon tint:
  `palette.accentColor` when enabled, `palette.tertiaryTextColor` when
  `isDisabled`. Group header label: `palette.secondaryTextColor`. Title
  label: `palette.secondaryTextColor`.
- **Border**: Not set explicitly anywhere in this file; `scrollView`'s
  `borderType` is never assigned, so it keeps `NSScrollView`'s own default
  value, `.noBorder` — no border is drawn around the scroll view.
- **Shadow**: Not applicable — no shadow is drawn, and no `CALayer` shadow
  property is configured, anywhere in this file.
- **Min/Max size**: No explicit min/max width or height constraint is
  applied to the controller's own view; `preferredWidth()` instead computes
  a content-driven width for a caller (e.g. an enclosing split view) to size
  the sidebar to, rather than the sidebar enforcing its own bounds. The item
  icon has a fixed 16×16pt size (`CellMetrics.iconSize`).

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected, enabled item row) | `itemFont`, `primaryTextColor` label, `accentColor`-tinted icon; row background follows `windowBackgroundColor`. |
| Disabled item row | `itemFont`, `tertiaryTextColor` label, `tertiaryTextColor`-tinted icon; identical selection/press behavior to an enabled row (see **disabled-item-selectability**). |
| Selected row | `ThemedTableRowView.drawSelection(in:)` fills a 4pt-corner-radius rect, inset 2pt horizontally / 1pt vertically, with `palette.nsColor(.selection)`. |
| Group header row | `headerFont`, `secondaryTextColor`, `isGroupItem == true`; not selectable; no disclosure control. |
| Pressed | Not applicable: this file defines no visual state distinct from Selected for a row's press — a click or `AXPress` both resolve directly to `selectRowIndexes`, with no separate transient "pressed" appearance. |
| Focused | Not applicable beyond AppKit's own default keyboard-focus-ring behavior on the outline view; source sets no custom focus-ring color, width, or override. |
| Loading | Not applicable: `setItems`/`setSections` apply their row model synchronously; source defines no async load and no loading/pending indicator. |

## Accessibility

- **Role/trait**: Not explicitly set via `setAccessibilityRole` anywhere in
  this file; the outline, its rows, and its cells use AppKit's default
  `NSOutlineView` roles, with group header rows marked via
  `isGroupItem == true`.
- **Label requirements**: Each item row's label carries an explicit
  accessibility identifier, `"topic-list.item.\(AccessibilityID.slug(item.title))"`
  (see **item-accessibility-id-from-title**), and its accessible name is its
  own `stringValue` (the item's title) — no separate `accessibilityLabel`
  override is set. Group header, title, and footer/accessory views carry no
  accessibility identifier in this file.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. When `setSections(_:)` reloads the outline with a
  different row count, no `NSAccessibility.post(element:notification:)` (or
  equivalent) call informs VoiceOver that the visible row set changed. What
  is missing: whether a VoiceOver user is told the list content changed, or
  hears nothing until navigating back into the outline. What would settle
  it: a VoiceOver pass over an instantiated sidebar while calling
  `setSections(_:)` with a materially different row set, or an explicit
  decision to post a notification from that method.
- **Minimum tap target**: `outlineView.rowSizeStyle = .default` — per
  Apple's documentation, `NSTableView.rowHeight` (whose documented default
  is 16pt) "is used only if the table's `rowSizeStyle` is set to `custom`",
  so with `.default` and no delegate `tableView(_:heightOfRow:)` override
  (neither present in this file) AppKit derives the row's actual height from
  its effective style rather than a literal value this file sets. Whatever
  value that resolves to for the fonts this component uses is well under the
  44×44pt iOS minimum. This is expected for a pointer/keyboard-driven macOS
  list (not a touch surface); the 44×44pt (iOS) / 48×48dp (Android) minimum
  applies to the touch-platform translations described in Platform Notes,
  not to this AppKit control. Additionally, an item row label's
  `accessibilityPerformPress()` gives assistive technology a press path into
  a row regardless of its rendered size, since activation does not depend on
  a pointer hitting a physical target.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| topic-list-001 | group-items-by-section | `setSections` with two sections, each holding two items, in a given order | The outline's rows, top to bottom, are exactly those items in the given section/item order |
| topic-list-002 | header-row-for-titled-section | A section with `title: "Recents"` and one item | A group header row reading "Recents" appears above that item's row |
| topic-list-003 | omit-header-for-untitled-section | A section with `title: nil` and two items | No group header row appears; only the two item rows are shown |
| topic-list-004 | flat-row-hierarchy, hide-disclosure-controls | Any populated outline | `isItemExpandable` returns `false` for every node and `shouldShowOutlineCellForItem` returns `false` for every item, so no row shows a disclosure triangle |
| topic-list-005 | hide-outline-column-header | Inspect `outlineView` after `loadView` | `outlineView.headerView == nil` |
| topic-list-006 | header-rows-not-selectable | Click, or send `AXPress` to, a group header row | `shouldSelectItem` returns `false`; the row does not become selected |
| topic-list-007 | disabled-item-selectability | An item with `isDisabled == true`; select it by click | The row becomes selected and `onSelect` is invoked with that item, identically to an enabled item |
| topic-list-008 | mute-disabled-item-appearance | Two items, one `isDisabled == true`, one `isDisabled == false` | The disabled row's label/icon use `tertiaryTextColor`; the enabled row's use `primaryTextColor`/`accentColor` |
| topic-list-009 | render-item-without-icon-when-nil | An item constructed with `icon: nil` | Its row's `imageView.image == nil`; no placeholder or broken image appears |
| topic-list-010 | user-selection-callback | User clicks an unselected item row | `onSelect` is invoked exactly once with that item |
| topic-list-011 | suppress-onselect-on-programmatic-selection | Call `selectItem(withId:)` for an unselected, present id | The row becomes selected but `onSelect` is NOT invoked |
| topic-list-012 | select-item-by-id, missing-id-selection | Two items with ids "a" and "b"; call `selectItem(withId: "b")`, then `selectItem(withId: "z")` | First call selects "b"'s row; second call leaves "b" selected (no change, no crash) |
| topic-list-013 | noop-select-already-selected-id | Row for id "b" is already selected; call `selectItem(withId: "b")` again | `selectRowIndexes` is not called again; selection and `onSelect` are unaffected |
| topic-list-014 | restore-selection-by-id-after-resection | Item "b" selected; call `setSections` with a new section list that still contains an item with id "b" | After reload, the row for id "b" is selected again, with no `onSelect` firing for the transient deselection |
| topic-list-015 | restore-selection-across-theme-change | A row is selected; the active theme changes | After `applyTheme(_:)` runs, the same row is still selected, with no spurious `onSelect(nil)` |
| topic-list-016 | stable-row-node-identity | Call `setSections` once, then call `selectItem(withId:)` for an item present since that call | `outlineView.row(forItem:)` resolves to a valid (non -1) row for that item |
| topic-list-017 | hide-header-when-title-and-accessory-empty | `setTitle(nil)` and no header accessory view set | `headerView.isHidden == true` |
| topic-list-018 | hide-footer-when-unset | `setFooterView(nil)` | `footerContainer.isHidden == true` |
| topic-list-019 | header-accessory-below-title | `setTitle("Panels")` and `setHeaderAccessoryView(searchField)` | The header shows the title label above `searchField`, both spanning the header's width |
| topic-list-020 | footer-spans-sidebar-width | `setFooterView(actionsBar)` | `actionsBar`'s leading/trailing anchors equal `footerContainer`'s; it visually spans the sidebar |
| topic-list-021 | content-below-titlebar-safe-area | Host the controller's view in a window whose content extends under the titlebar | `contentStack`'s top sits at the safe-area inset, not the raw top of the view, so the titlebar does not overlap the list |
| topic-list-022 | preferred-width | One item titled "A very long item title" and no title/footer/accessory | `preferredWidth()` returns exactly `itemChromeWidth + renderedWidth("A very long item title", itemFont) + outlineChromePadding (64)` |
| topic-list-023 | item-accessibility-id-from-title | An item with `id: "row-7"`, `title: "Appearance"` | The row label's accessibility identifier is `"topic-list.item.appearance"`, not `"topic-list.item.row-7"` |
| topic-list-024 | ax-press-selection | Send `accessibilityPerformPress()` to an item row's label | The press selects the row and returns `true` |
| topic-list-024b | ax-press-selection | Install a delegate override where `shouldSelectItem` returns `false`; send `accessibilityPerformPress()` to an item row's label | `accessibilityPerformPress()` returns `false`; the row does not become selected |
| topic-list-025 | repaint-on-theme-change | Active theme changes from light to dark | Root view, `contentStack`, `headerView`, `footerContainer` backgrounds, title label font/color, and outline/scroll backgrounds all update to the new palette's values |
| topic-list-026 | single-column-fills-width | Enclosing split view widens the sidebar by 40pt | The outline's single column widens by the same amount on the next layout pass; no row clips its label |
| topic-list-027 | overlay-autohide-scroller | Inspect `scrollView` after `loadView` | `scrollView.scrollerStyle == .overlay` and `scrollView.autohidesScrollers == true` |
| topic-list-028 | automatic-outline-style | Inspect `outlineView.style` after `loadView` | `outlineView.style == .automatic` |

## Edge Cases

- Null/empty input (MUST): `setSections([])` yields an empty
  `rootNodesCache`; the outline shows zero rows and `selectedItem` returns
  `nil`. `TopicListItem.icon` and `TopicListSection.title` are both
  optional and handled per **render-item-without-icon-when-nil** and
  **omit-header-for-untitled-section**; `TopicListItem.id`/`title` are
  non-optional `String`s, so Swift's type system rules out `nil` for them.
- Boundary values (MUST): With no sections, no title, no footer, and no
  header accessory, `preferredWidth()` returns exactly
  `outlineChromePadding` (64pt) — the minimum value this method can produce.
  Source imposes no maximum on section or item count; any array size is
  handled uniformly through the same `rootNodesCache`/`NSOutlineView` row
  model.
- Duplicate item ids (SHOULD): `selectItem(withId:)` resolves via a
  first-match lookup; if two items across sections share an id, only the row
  for the first match in outline order is ever selected by this method —
  source performs no uniqueness validation. Callers SHOULD supply unique ids
  across all sections passed to one `setSections(_:)` call; this is
  undocumented in source and left to caller discipline. This SHOULD needs no
  separate test vector: the behavior described here is a direct,
  deterministic consequence of the same first-match lookup **select-item-by-id**'s
  vector (topic-list-012) already exercises, and a second, near-identical
  vector for the duplicate-id case would not exercise any additional code
  path.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so Swift's concurrency checker confines all reads and writes of
  `sections`, `rootNodesCache`, and `selectionSuppressionDepth` to the main
  actor; source provides no path for two threads to mutate this view
  controller's state simultaneously.
- Error states: Not applicable — this file contains no throwing function,
  no `Result`, and no network or file-system call; `setItems`, `setSections`,
  and `selectItem(withId:)` are synchronous, non-throwing operations with no
  failure mode to represent beyond the silent no-ops already described
  above (missing id, already-selected id).
- Offline/disconnected: Not applicable — the component performs no
  networking anywhere in source; it only renders caller-supplied in-memory
  data.
- Header row reached via `selectedItem` (MUST): `selectedItem`'s guard
  (`case .item(let item) = node.kind else { return nil }`) returns `nil`
  defensively if `outlineView.selectedRow` were ever a group header row;
  in practice this cannot occur because `shouldSelectItem` already refuses
  to select header rows, but the accessor does not rely on that invariant
  holding elsewhere in the outline's delegate chain.
- Nested selection-suppression scopes (MUST): `selectionSuppressionDepth`
  is an integer nesting counter, not a boolean, specifically so that a
  suppression scope nested inside another still leaves suppression active
  until the outer scope also exits; no call site in this file nests scopes
  today, but `suppressingSelectionCallbacks` supports it without change if
  a future call site does.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sections` | `[TopicListSection]` | `[]` | Full sectioned row model; set via `setSections(_:)` (grouped, headers per non-empty section title) or `setItems(_:)` (flat, wraps items in one untitled section). |
| `onSelect` | `(((any TopicListItemProtocol)?) -> Void)?` | `nil` | Invoked with the newly selected item, or `nil`, on a user-driven selection change; never invoked for a programmatic change made through `selectItem(withId:)` or a theme-triggered reload. |
| `title` (`listTitle`) | `String?` | `nil` | Text shown in the optional header above the list, set via `setTitle(_:)`; `nil` or empty hides the header unless a header accessory view is set. |
| `footerView` | `NSView?` | `nil` | Client view pinned below the list via `setFooterView(_:)`, spanning the sidebar width; `nil` collapses the footer to zero height. |
| `headerAccessoryView` | `NSView?` | `nil` | Client view shown directly beneath the title and above the list via `setHeaderAccessoryView(_:)`, spanning the header's width; `nil` collapses to nothing. |

## Deep Linking

Not applicable: this is a reusable, embeddable sidebar view controller with
no URL scheme, route, or deep-link handler anywhere in source; a host (such
as `PanelListViewController`'s owner) decides how and where to present it.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | — | This file defines no user-facing string literal of its own. |

Not applicable beyond the row above: every displayed string — item titles,
section titles, and the list's own title — comes from caller-supplied data
(`TopicListItem.title`, `TopicListSection.title`, and `setTitle(_:)`'s
parameter), not from a string table owned by this component. The only
string literals in this file (`"TopicListColumn"`, `"TopicListHeader"`,
`"TopicListItem"`, and the `"topic-list.item.…"` accessibility identifier
prefix) are internal AppKit/accessibility identifiers, never shown on
screen.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext` call anywhere in this file; every
  state change (selection, resection, theme repaint) is an instantaneous
  property assignment or a synchronous `reloadData()`.
- **Increase Contrast**: Not applicable to this file specifically —
  `TopicListViewController.swift` never assigns a raw `NSColor` literal;
  every color it uses is read from `SemanticPalette` (via
  `ThemePaletteObserver`/`view.resolvedThemeScope.palette`). Whether the
  active palette itself adjusts under Increase Contrast is that theme
  system's responsibility, not something this component decides or can
  override.
- **Differentiate Without Color**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. A disabled item (`isDisabled == true`) is
  distinguished from an enabled one only by color — `tertiaryTextColor`
  versus `primaryTextColor`/`accentColor` (see **mute-disabled-item-appearance**)
  — with no accompanying non-color cue (no icon change, no strikethrough,
  no opacity reduction, since `alphaValue` is explicitly set to `1.0` for
  every row). What is missing: a way for a Differentiate Without Color user
  to tell a disabled row from an enabled one without relying on color
  contrast. What would settle it: a design decision on a secondary cue (an
  icon overlay, a trailing "Coming Soon" label, or similar) for
  `isDisabled` rows, or confirmation that this is an accepted limitation.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
this file; the sidebar always renders whatever `setItems`/`setSections` is
given.

## Analytics

Not applicable: this file contains no analytics or telemetry call. `onSelect`
is the only observable callback, and it is entirely consumer-supplied — this
component neither logs nor reports on its own selection changes.

## Privacy

- **Data collected**: None by the component itself — it only renders
  caller-supplied `TopicListItem`/`TopicListSection` values for display.
- **Storage**: In-memory only (`sections`, `rootNodesCache`), for the view
  controller's lifetime; nothing is written to disk, `UserDefaults`, or any
  other store by this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view controller's lifetime; state is
  discarded when the controller is deallocated.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
logger reference anywhere in this file).

## Platform Notes

- **SwiftUI**: Use a `List(selection: $selectedID)` built from the same
  `TopicListSection`/`TopicListItem` model, with `Section(header: Text(title))`
  wherever a section's title is non-nil (mirroring
  **header-row-for-titled-section** / **omit-header-for-untitled-section**),
  and a plain, unsectioned `ForEach` when it is nil. Render a disabled row's
  label and `Label` icon with `.foregroundStyle(.tertiary)` while still
  leaving the row tappable/selectable (mirroring
  **disabled-item-selectability** — do not use SwiftUI's `.disabled()`
  modifier, since that would also block selection, unlike the source
  behavior). Compose the optional title/accessory/footer as sibling views
  above and below the `List` in a `VStack`, collapsing each with
  `if let` rather than SwiftUI's `.hidden()` (which still reserves layout
  space), mirroring the zero-height collapse behavior of `isHidden` on a
  `NSStackView` arranged subview. Read the row's rendered text width with
  `(text as NSString).size(withAttributes:)` if a content-driven sidebar
  width equivalent to `preferredWidth()` is needed.
- **Compose**: Build the outline as a `LazyColumn` with `stickyHeader` items
  for each section whose title is non-nil, and plain items otherwise. Style
  a disabled item's `Text`/`Icon` with `MaterialTheme.colorScheme.onSurfaceVariant`
  (or `LocalContentColor.current.copy(alpha = …)`) while leaving its
  `Modifier.clickable` active, mirroring **disabled-item-selectability**
  (Compose's built-in `enabled = false` on `clickable` would, like SwiftUI's
  `.disabled()`, block the click entirely — do not use it here; `contentColorFor`
  is also the wrong tool, since it returns the content color paired with a
  given background, not a muted tone). Wrap the whole sidebar
  column in a `Surface` whose `color` is read from the active
  `MaterialTheme.colorScheme` so it repaints on theme change, mirroring
  **repaint-on-theme-change**. Compose an optional title/accessory header
  and footer as sibling composables that emit nothing (`if (condition) { … }`)
  when unset, rather than an `AnimatedVisibility` that would animate a
  collapse this component never animates.
- **React/Web**: Render the sidebar as a `<nav>` containing a single
  `<ul role="listbox">` for the whole list, mirroring **flat-row-hierarchy**'s
  single-outline model — never one `listbox` per section, which would split
  keyboard navigation and single selection across sections. Wrap each titled
  section's rows in an `<li role="group" aria-labelledby="section-id">`
  containing an `<h3 id="section-id">` for the title followed by that
  section's `<li role="option" aria-selected>` rows; an untitled section's
  rows sit directly in the listbox with no wrapping `group`. Style a disabled item with a muted text/icon color
  class while still attaching its `onClick`/keyboard handlers, mirroring
  **disabled-item-selectability** (do not set the native `disabled`
  attribute, which — like SwiftUI's `.disabled()` — would remove it from the
  tab order and block activation). Give each item's element an `id` or
  `data-testid` derived from a slugified title, mirroring
  **item-accessibility-id-from-title**, and drive CSS custom properties
  (`--surface-bg`, `--text-primary`, etc.) from the active theme so a theme
  switch repaints them, mirroring **repaint-on-theme-change**. Collapse an
  unset header/footer with `display: none` (which removes layout space, like
  AppKit's `isHidden` on a stack view's arranged subview) rather than
  `visibility: hidden`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`
  as a `@MainActor`, `open` `NSViewController` that builds its entire view
  hierarchy by hand in `loadView()` — a single-column `NSOutlineView`
  (`ColumnFillingOutlineView`) inside an `NSScrollView`, stacked with an
  optional title/accessory header and an optional client footer in a
  vertical `NSStackView`. It is its own `NSOutlineViewDataSource`/
  `NSOutlineViewDelegate`, with row appearance and theming driven by
  `SemanticPalette` via `ThemePaletteObserver` and `ThemedTableRowView`
  (both defined in the vendored `AgenticDeveloperToolkitUI` framework this
  target re-exports). There is no UIKit code path in source; a UIKit port
  would replace `NSOutlineView`/`NSScrollView` with a `UITableView` (a flat
  list needs no `UICollectionView` compositional layout), use
  `tableView(_:titleForHeaderInSection:)` for group headers, and would need
  to grow the AppKit `.default` row height — well under 44pt — to at least a
  44pt touch target, since UIKit has no keyboard-first,
  `NSOutlineView`-style default row navigation to fall back on for
  pointer-free selection.
- **WinUI 3**: Build the sidebar as a
  `NavigationView` in `Left`/`LeftCompact` display mode, or — if
  `NavigationView`'s chrome (back button, pane toggle) is unwanted — a plain
  `ListView` bound to a flattened collection of `TopicListSection`/
  `TopicListItem` view models, grouped with `CollectionViewSource.IsSourceGrouped
  = true` and a `GroupStyle` whose `HeaderTemplate` renders the section
  title only when it is non-empty (mirroring
  **header-row-for-titled-section**/**omit-header-for-untitled-section** —
  WinUI's `CollectionViewSource` grouping is the direct analog of
  `buildRootNodes(from:)`'s header/item interleaving). Bind each
  `ListViewItem`'s `IsEnabled` to nothing (leave it `true`) and instead bind
  its `Foreground`/icon `Fill` to a converter that returns a muted
  `SolidColorBrush` when the item's `IsDisabled` is set, mirroring
  **disabled-item-selectability** — WinUI's `IsEnabled = false`
  would, like SwiftUI's `.disabled()` and Compose's `enabled = false`,
  also block selection, which source does not do. Use
  `ListView.SelectionMode="Single"` with `SelectedItem`/`SelectionChanged`
  as the analog of `onSelect`, and select an item by identity
  (`ListView.SelectedItem = viewModels.First(vm => vm.Id == id)`) as the
  analog of `selectItem(withId:)`, no-oping when no match is found
  (mirroring **missing-id-selection**). Give the optional title a
  `TextBlock` and the optional accessory/footer `ContentPresenter`s bound to
  nullable view-model properties, collapsing each to `Visibility.Collapsed`
  (which, like AppKit's `isHidden` on a stack panel child, removes it from
  layout — not `Opacity="0"`) when unset, mirroring
  **hide-header-when-title-and-accessory-empty**/**hide-footer-when-unset**.
  Re-theme the `NavigationView`/`ListView`'s brushes from
  `Application.Current.Resources` `ThemeResource`s (or re-apply them in an
  `ActualThemeChanged` handler) so a theme switch repaints the sidebar,
  mirroring **repaint-on-theme-change**. Set `AutomationProperties.AutomationId`
  on each `ListViewItem` to the slugified title (mirroring
  **item-accessibility-id-from-title**) while `AutomationProperties.Name`
  carries the plain title as the item's accessible name, since WinUI's UI
  Automation tree, like AppKit's, exposes the item's own element rather than
  a synthesized row wrapper as the natural place to attach an identifier and
  a name.

## Design Decisions

- Decision: Cache `TopicListNode` instances in `rootNodesCache` across
  accesses, rebuilding them only inside `setSections(_:)`, instead of
  recomputing `rootNodes` fresh on every access.
  Rationale: Per the property's doc comment, `NSOutlineView` identifies
  items by reference; rebuilding on every access (the prior behavior) made
  `outlineView.row(forItem:)` always return -1, which silently broke
  `selectItem(withId:)`.
  Approved: pending
- Decision: Let `shouldSelectItem` and `TopicListItemLabel.accessibilityPerformPress()`
  gate selection only on node kind (`.item` vs. `.header`), never on
  `TopicListItem.isDisabled`.
  Rationale: Source draws no such distinction — a "coming soon" placeholder
  item stays reachable and selectable by mouse, keyboard, and assistive
  technology alike; only its rendered appearance is muted. A consumer that
  wants a disabled item to be truly inert must check `isDisabled` itself
  inside its `onSelect` handler.
  Approved: pending
- Decision: Track suppression of `onSelect` with an integer nesting counter
  (`selectionSuppressionDepth`), not a boolean flag.
  Rationale: Per the property's doc comment, a single suppression scope must
  absorb both the notification `reloadData()` posts when it drops the
  selection and the one the following re-selection posts — AppKit delivers
  both synchronously within the scope — so the counter, not a one-shot
  flag, is what keeps a single scope correct.
  Approved: pending
- Decision: Override `layout()` on `ColumnFillingOutlineView` to call
  `sizeLastColumnToFit()` after `super.layout()`, rather than setting the
  column's `width` directly.
  Rationale: Per the class's doc comment, setting `column.width` directly
  from `layout()` re-enters `NSTableView.tile`/`setFrameSize` and throws;
  `sizeLastColumnToFit()` after `super.layout()` is the safe primitive.
  Approved: pending
- Decision: Set `outlineView.style = .automatic` rather than the more
  visually apt `.sourceList`.
  Rationale: Per the source comment, `.sourceList` forces an internal
  `NSVisualEffectView` dark material regardless of `NSApp.appearance`;
  `.automatic` lets the outline's background follow this component's own
  theme instead.
  Approved: pending
- Decision: Pin `contentStack`'s top anchor to the root view's
  `safeAreaLayoutGuide.topAnchor` instead of its plain `topAnchor`.
  Rationale: Per the source comment, in a window whose content runs the
  full height (so the sidebar's fill reaches up behind the window buttons)
  the titlebar overlaps this view, and the list must begin below it;
  everywhere else that inset is zero and nothing moves.
  Approved: pending
- Decision: Put the accessibility identifier and `AXPress` handling on the
  item's `NSTextField` label (`TopicListItemLabel`), not on
  `NSTableCellView` or `NSTableRowView`.
  Rationale: Per the source comment, AppKit synthesizes a table's `AXRow`
  and `AXCell` elements itself; an identifier or action attached to
  `NSTableRowView`/`NSTableCellView` never reaches the accessibility tree,
  so the label is the row's one real element in it.
  Approved: pending
- Decision: Derive an item row's accessibility identifier from its `title`
  (slugified), not from its `id`.
  Rationale: Per the source comment, `id` is the caller's private key — in
  the settings window it is a panel's index in an array — so it names
  whichever row a given index currently holds and renames itself whenever a
  row is inserted above it. The title is what the row is called on screen,
  which is what someone driving the list actually knows about it.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | passed | Internationalization |

Keyboard-navigable passes because `NSOutlineView`'s default arrow-key row
navigation is never disabled or overridden, and `shouldSelectItem` gates
keyboard-driven selection the same way it gates a click; every item row's
accessible name is also its own title text, with a stable, title-derived
accessibility identifier alongside it. Screen-reader-support is partial:
labels and an `AXPress` path exist, but no announcement is posted when
`setSections(_:)` changes the visible row set, and a disabled item is
distinguished from an enabled one by color alone with no secondary cue (see
the open questions under Accessibility and Accessibility Options).
Dynamic-type-support is partial because `CellMetrics.itemFont`/`headerFont`/
`titleFont` all read live palette fonts (`palette.font(.body)` etc.) rather
than a fixed point size, but this file cannot confirm whether
`SemanticPalette.font(_:)` itself scales with the system's text-size
setting. Contrast-ratio is partial because every color comes from
`SemanticPalette` tokens whose actual contrast values are not stated in this
file's source. Platform-theming passes because the root view, `contentStack`,
`headerView`, `footerContainer`, title label, and outline/scroll backgrounds
all repaint from `SemanticPalette` on every `ThemePaletteObserver` change
(see **repaint-on-theme-change**). String-externalization passes because
this file defines no user-facing string literal of its own — every
displayed string is caller-supplied data. `touch-target-size` is not listed:
AppKit's `.default` row-size style yields a row height well under 44×44pt,
but that check governs touch surfaces and this is a pointer/keyboard-driven
macOS list — not a defect, and not an applicable check for this control (the
44×44pt/48×48dp threshold does apply to the touch-platform translations
described in Platform Notes).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: rewrote requirements and test vectors to remove private AppKit identifiers (`rootNodesCache`, `TopicListNode`, `buildRootNodes(from:)`, `sizeLastColumnToFit()`, `ColumnFillingOutlineView`) in favor of observable behavior, keeping the mechanism under Platform Notes/Design Decisions; renamed five action-phrased requirements to subject-only names (`disabled-item-selectability`, `ax-press-selection`, `preferred-width`, `missing-id-selection`, `user-selection-callback`) and updated every citation; gave the Border and Minimum-tap-target Appearance/Accessibility entries concrete, source-grounded values instead of vague claims; stated the exact `preferred-width` formula and made its test vector assert equality; split the ax-press test vector into a positive and a gated-false case and made the scroller/outline-style vectors deterministic; fixed a false Design-Decisions cross-reference in the duplicate-item-ids edge case; corrected the WinUI `AutomationId`/`Name` mapping, removed an editorializing WinUI aside, fixed the Compose disabled-item color guidance, and restructured the React/Web notes to one listbox with grouped sections; dropped the redundant `macos` tag; rewrote the Compliance table to cite only real catalog checks (dropping fabricated ones and the inapplicable `touch-target-size` row, adding `dynamic-type-support` and `platform-theming`). |
