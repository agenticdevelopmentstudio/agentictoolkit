<!-- leaf: implement-general-controller/breadcrumb-popover-view-controller · source: breadcrumb-popover-view-controller.md -->

**Rules** (cite as `implement-general-controller/breadcrumb-popover-view-controller#<slug>`):

- `load-directory-children` MUST
- `fixed-content-size` MUST
- `filter-placeholder-text` MUST
- `filter-updates-immediately` MUST
- `filter-by-name-match` MUST
- `show-all-entries-when-filter-empty` MUST
- `select-first-row-on-load` MUST
- `reselect-first-row-after-filter` MUST
- `bold-matched-characters` MUST
- `reject-empty-selection` MUST
- `reject-multiple-selection` MUST
- `clamp-selection-to-list-bounds` MUST
- `no-op-selection-when-empty` MUST
- `scroll-selection-into-view` MUST
- `relative-selection-movement` MUST
- `arrow-keys-move-selection` MUST
- `return-key-chooses-selection` MUST
- `focus-filter-field-on-appear` MUST
- `escape-key-cancels` MUST
- `double-click-chooses-row` MUST
- `open-selected-file` MUST
- `ignore-directory-choice` MUST
- `ignore-choose-without-valid-selection` MUST
- `invoke-cancel-callback-when-set` MUST
- `no-op-cancel-when-unset` MUST
- `reuse-row-views` MUST
- `truncate-row-label-middle` MUST
- `single-column-table` MUST
- `no-column-header` MUST
- `coder-initialization-unsupported` MUST

# BreadcrumbPopoverViewController

## Overview

`BreadcrumbPopoverViewController` is a macOS `NSViewController` that shows the
content of the popover a `BreadcrumbView` crumb opens: a small, filterable,
keyboard-navigable list of one directory's immediate children. Typing in the
search field narrows the list to entries whose name matches, with matched
characters shown in bold; arrow keys, Return, and Escape are handled by a
shared `PickerKeyboardController` rather than bespoke keyboard code.
Selecting a file row invokes the `onSelect` callback with that file's URL;
selecting a directory row does nothing — this popover only opens files, it
does not browse further down the tree.

## Behavioral Requirements

- **load-directory-children**: Component MUST load the immediate children of
  `directoryURL` via `FileTreeNode.loadChildren(for:)` at initialization and
  MUST use that list as both the unfiltered entry list and the initial
  filtered list.
- **fixed-content-size**: Component MUST set `preferredContentSize` to
  280×320 points at initialization.
- **filter-placeholder-text**: The filter field MUST display the placeholder
  text "Filter" when empty.
- **filter-updates-immediately**: Component MUST re-run filtering on every
  keystroke in the filter field, without waiting for the user to finish
  typing or press Return.
- **filter-by-name-match**: Component MUST filter entries to only those whose
  name contains at least one case-insensitive, diacritic-sensitive substring
  occurrence of the current filter text — a literal substring search, not a
  prefix-only or fuzzy/subsequence match — as determined by
  `ProjectFilter.ranges(of:in:)`.
- **show-all-entries-when-filter-empty**: Component MUST show all loaded
  entries when the filter text is empty.
- **select-first-row-on-load**: Component MUST select the first row of the
  table immediately after the initial data load.
- **reselect-first-row-after-filter**: Component MUST reselect the first row
  of the table every time the filter is applied.
- **bold-matched-characters**: Component MUST render, in a bold system font,
  the character ranges of each entry's name that match the current filter
  text, and MUST render the remaining characters in a regular system font of
  the same size.
- **reject-empty-selection**: The table MUST NOT permit an empty selection.
- **reject-multiple-selection**: The table MUST NOT permit selecting more
  than one row at a time.
- **clamp-selection-to-list-bounds**: Component MUST clamp any requested
  selection index to the range from 0 to one less than the number of
  currently filtered entries.
- **no-op-selection-when-empty**: Component MUST NOT change selection when
  the filtered list is empty.
- **scroll-selection-into-view**: Component MUST scroll the table so a newly
  selected row is visible whenever selection changes programmatically.
- **relative-selection-movement**: Component MUST move the selection by a
  given relative offset from the current selection when instructed to do so,
  treating an absent selection as index 0.
- **arrow-keys-move-selection**: While the filter field has keyboard focus,
  the Down and Up arrow keys MUST move the table selection by a relative
  offset of +1 and -1 respectively (see relative-selection-movement), for as
  long as the view remains on screen.
- **return-key-chooses-selection**: While the filter field has keyboard
  focus, Return MUST perform the choose action on the current selection (see
  open-selected-file, ignore-directory-choice,
  ignore-choose-without-valid-selection).
- **focus-filter-field-on-appear**: Component MUST make the filter field the
  window's first responder when the view appears.
- **escape-key-cancels**: For the entire time the view is visible — from
  when it appears until it is about to disappear — Escape MUST trigger the
  cancel action (see invoke-cancel-callback-when-set, no-op-cancel-when-unset)
  regardless of which control has keyboard focus, and MUST NOT trigger it
  once the view has disappeared.
- **double-click-chooses-row**: Double-clicking a row MUST perform the same
  choose action as invoking choose through the keyboard controller.
- **open-selected-file**: Choosing a row MUST invoke the `onSelect` callback
  with the selected entry's URL only when that entry is a file.
- **ignore-directory-choice**: Choosing a row whose entry is a directory MUST
  NOT invoke the `onSelect` callback.
- **ignore-choose-without-valid-selection**: Choosing MUST NOT invoke the
  `onSelect` callback when there is no valid selected row index.
- **invoke-cancel-callback-when-set**: Component MUST invoke the `onCancel`
  callback when the keyboard controller reports cancel and `onCancel` has
  been set.
- **no-op-cancel-when-unset**: Component MUST have no observable effect from
  a cancel when `onCancel` has not been set.
- **reuse-row-views**: Component MUST reuse a previously constructed row view
  for the table's column when one is available, constructing a new row view
  only when none exists yet, rather than always constructing a new one on
  reload.
- **truncate-row-label-middle**: The row label MUST truncate overflowing text
  in the middle.
- **single-column-table**: The table MUST present exactly one column.
- **no-column-header**: The table MUST NOT display a column header.
- **coder-initialization-unsupported**: Component MUST NOT support
  initialization via `init(coder:)` and MUST fail fast (fatal error) if it is
  invoked.

## Appearance

- **Corner radius**: Not applicable — the component draws no custom layer;
  any rounding on the popover's chrome comes from `NSPopover`'s own default
  appearance, not from this view controller's view hierarchy.
- **Padding**: Root view: 8pt top/leading/trailing around the search field;
  6pt gap between the search field's bottom and the scroll view's top; 8pt
  leading/trailing/bottom around the scroll view. Row label: 4pt
  leading/trailing inset from the cell view's edges, centered vertically.
- **Font**: Row label uses `NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)`
  for unmatched characters and `NSFont.boldSystemFont(ofSize:
  NSFont.smallSystemFontSize)` for characters matching the current filter
  text.
- **Background**: Not set explicitly anywhere in source; the root view,
  search field, table, and scroll view all use their default AppKit
  backgrounds.
- **Foreground/Text**: Not set explicitly anywhere in source; row labels use
  `NSTextField(labelWithString:)`'s default label text color, with only font
  weight (regular vs. bold) varying by match state.
- **Border**: `scrollView.borderType = .noBorder`; no border is configured on
  the search field or the table view.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: `preferredContentSize` and the root view's frame are
  fixed at 280×320pt (`Self.contentSize`; see fixed-content-size), the
  popover's one defined size constant, referenced elsewhere in this recipe by
  name rather than restated as a bare number; the single table column has a
  fixed width of 248pt (`column.width`); no separate min/max constraint
  exists beyond these two fixed sizes.

## Accessibility

- **Role/trait**: Not explicitly set via `setAccessibilityRole`/
  `setAccessibilityElement` in source; the search field and table use
  AppKit's default `NSSearchField`/`NSTableView` roles automatically.
- **Label requirements**: The search field and table view each carry an
  explicit accessibility identifier — `"breadcrumb.popover.filter"` and
  `"breadcrumb.popover.table"` respectively, via `accessibilityID(_:)` — for
  automation/testing, not for VoiceOver, which does not speak identifiers.
  Neither control sets an accessibility label (`setAccessibilityLabel`):
  VoiceOver has only the `"Filter"` placeholder for the search field and no
  spoken name for the table. Each row's accessible content comes from its
  `NSTextField`'s own `attributedStringValue` (the entry's name, with matched
  characters bolded); source sets no separate `accessibilityLabel` override
  on the cell view or its text field.
- **Announce state changes**: Not implemented in source. When `applyFilter()`
  reloads the table with a new, possibly much shorter, row count, source
  posts no accessibility notification (e.g. no
  `NSAccessibility.post(element:notification:)` call) informing VoiceOver
  that the visible option set has changed; a VoiceOver user hears nothing
  until navigating back into the table.
- **Minimum tap target**: The table's row height is 20pt, well under the
  44×44pt iOS minimum; this is expected for a pointer/keyboard-driven macOS
  list (not a touch surface) and is not a tap-target defect on this platform.
  The 44×44pt (iOS) / 48×48dp (Android) minimum applies to the touch-platform
  translations described in Platform Notes, not to this AppKit control.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directoryURL` | `URL` | — (required) | The one directory whose immediate children are loaded and listed; read once at init and never reloaded. |
| `onSelect` | `(URL) -> Void` | — (required) | Invoked with a chosen file's URL when the user picks a non-directory row. |
| `onCancel` | `(() -> Void)?` | `nil` | Invoked when the keyboard controller reports cancel (Escape); typically set by `BreadcrumbView` after construction, since only it holds the `NSPopover`. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Filter" | Search field placeholder text |

`"Filter"` is assigned to `searchField.placeholderString` as a plain AppKit
`String` literal (BreadcrumbPopoverViewController.swift), not through
`String(localized:)` or `NSLocalizedString`, so it never reaches a string
catalog; there is no localization key or catalog entry for the placeholder.

Not applicable beyond the table above: row labels come from `FileTreeNode.name`
(file system entry names), not from a localized string table, so there is
nothing else in this file for the component itself to localize.

