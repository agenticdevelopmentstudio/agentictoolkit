---
id: c79094d2-1f4b-4c3f-8005-8fb095fb1b40
title: BreadcrumbPopoverViewController
domain: agentictoolkit://recipes/breadcrumb-popover-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Filterable, keyboard-driven list of a directory's files in a BreadcrumbView
  crumb's popover; selecting a file returns its URL, directories are inert.
platforms:
- swift
- macos
tags:
- picker
- filter
- popover
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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
  name has at least one match range against the current filter text, as
  determined by `ProjectFilter.ranges(of:in:)`.
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
- **connect-move-selection-callback**: Component MUST assign its
  `PickerKeyboardController`'s move-selection callback to move the table
  selection by the requested offset when the view appears.
- **connect-choose-callback**: Component MUST assign its
  `PickerKeyboardController`'s choose callback to perform the choose action
  when the view appears.
- **connect-cancel-callback**: Component MUST assign its
  `PickerKeyboardController`'s cancel callback to invoke `onCancel` when the
  view appears.
- **start-escape-monitor-on-appear**: Component MUST start its
  `PickerKeyboardController`'s escape-key monitor, scoped to the view's
  window, when the view appears.
- **focus-filter-field-on-appear**: Component MUST make the filter field the
  window's first responder when the view appears.
- **stop-escape-monitor-on-disappear**: Component MUST stop its
  `PickerKeyboardController`'s escape-key monitor when the view is about to
  disappear.
- **delegate-command-selectors-to-keyboard-controller**: Component MUST route
  the filter field's text-view command selectors (the mechanism by which
  arrow keys, Return, and Escape reach a focused `NSSearchField`) to
  `PickerKeyboardController.handle(_:)` and MUST return that call's result to
  the caller.
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
- **reuse-cell-views**: Component MUST reuse a previously created cell view
  registered for the table column's identifier when one is available, rather
  than always constructing a new one.
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
  fixed at 280×320pt (`Self.contentSize`); the single table column has a
  fixed width of 248pt; no separate min/max constraint exists beyond this one
  fixed size.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected row) | Row label rendered at `NSFont.smallSystemFontSize`; characters matching the current filter text are bold, the rest regular; no selection highlight. |
| Selected row | AppKit's default table row-selection highlight is applied; the row is scrolled into view via `scrollRowToVisible`. |
| Filtered (non-empty query) | Only entries whose name has at least one match range from `ProjectFilter.ranges(of:in:)` are shown; matched characters render bold; row 0 of the new filtered list is reselected. |
| Empty result set | No rows are shown; `selectRow`/`moveSelection` become no-ops because both guard on `!filtered.isEmpty`. |
| Focused (search field) | The search field becomes the window's first responder in `viewDidAppear`; source sets no other explicit focus-ring styling. |
| Disabled | Not applicable: no control in this component (`searchField`, `tableView`, rows) is ever disabled in source. |
| Loading | Not applicable: `FileTreeNode.loadChildren(for:)` is called synchronously in `init`; source defines no loading/pending state or indicator. |

## Accessibility

- **Role/trait**: Not explicitly set via `setAccessibilityRole`/
  `setAccessibilityElement` in source; the search field and table use
  AppKit's default `NSSearchField`/`NSTableView` roles automatically.
- **Label requirements**: The search field and table view each carry an
  explicit accessibility identifier — `"breadcrumb.popover.filter"` and
  `"breadcrumb.popover.table"` respectively, via `accessibilityID(_:)` — for
  automation/testing. Each row's accessible content comes from its
  `NSTextField`'s own `attributedStringValue` (the entry's name, with matched
  characters bolded); source sets no separate `accessibilityLabel` override
  on the cell view or its text field.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. When `applyFilter()` reloads the table with a new,
  possibly much shorter, row count, source posts no accessibility
  notification (e.g. no `NSAccessibility.post(element:notification:)` call)
  informing VoiceOver that the visible option set has changed. What is
  missing: whether a VoiceOver user is told the result count changed, or
  hears nothing until they navigate back into the table. What would settle
  it: a VoiceOver pass over an instantiated popover while typing a filter, or
  an explicit decision to post a row-count-changed/announcement notification
  from `applyFilter()`.
- **Minimum tap target**: The table's row height is 20pt, well under the
  44×44pt iOS minimum; this is expected for a pointer/keyboard-driven macOS
  list (not a touch surface) and is not a tap-target defect on this platform.
  The 44×44pt (iOS) / 48×48dp (Android) minimum applies to the touch-platform
  translations described in Platform Notes, not to this AppKit control.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| breadcrumb-popover-001 | load-directory-children | Initialize with a `directoryURL` containing files "A.txt", "B.txt" and subdirectory "C" | `entries` and `filtered` both contain exactly those three nodes, as returned by `FileTreeNode.loadChildren(for:)` |
| breadcrumb-popover-002 | fixed-content-size | Read `preferredContentSize` immediately after init | `preferredContentSize == NSSize(width: 280, height: 320)` |
| breadcrumb-popover-003 | filter-placeholder-text | Inspect the search field before any input | `placeholderString == "Filter"` |
| breadcrumb-popover-004 | filter-updates-immediately, filter-by-name-match | Entries "Apple.txt" and "Banana.txt" loaded; type "a" into the filter field | Table reloads to show only "Apple.txt" before any further keystroke or Return is pressed |
| breadcrumb-popover-005 | show-all-entries-when-filter-empty | Filter field contains "a" and is then cleared to `""` | Table shows all originally loaded entries again |
| breadcrumb-popover-006 | select-first-row-on-load | View controller finishes `viewDidLoad` with 3 entries | Row 0 is selected |
| breadcrumb-popover-007 | reselect-first-row-after-filter | Row 2 is selected; user types a filter that matches multiple entries | Row 0 of the newly filtered list is selected |
| breadcrumb-popover-008 | bold-matched-characters | Filter field contains "ap"; an entry's name is "Apple.txt" | The attributed string's "Ap" range carries the bold system font; the remaining characters carry the regular system font |
| breadcrumb-popover-009 | reject-empty-selection, reject-multiple-selection | Inspect `tableView` configuration after `loadView` | `allowsEmptySelection == false` and `allowsMultipleSelection == false` |
| breadcrumb-popover-010 | clamp-selection-to-list-bounds | 3 filtered entries; call `selectRow(-5)`, then `selectRow(999)` | First call selects row 0; second call selects row 2 |
| breadcrumb-popover-011 | no-op-selection-when-empty | Filter text matches no entries; call `moveSelection(by: 1)` | No row is selected and no index-out-of-range error occurs |
| breadcrumb-popover-012 | scroll-selection-into-view | Selection moves to a row currently scrolled out of view | `scrollRowToVisible` is called with that row index and the row becomes visible |
| breadcrumb-popover-013 | relative-selection-movement | 5 filtered entries; row 1 is selected; call `moveSelection(by: 2)` | Row 3 becomes selected |
| breadcrumb-popover-014 | connect-move-selection-callback, connect-choose-callback, connect-cancel-callback, start-escape-monitor-on-appear | View appears | `keyboard.onMoveSelection`, `keyboard.onChoose`, and `keyboard.onCancel` are all non-nil; the escape-key monitor has been started for the view's window |
| breadcrumb-popover-015 | focus-filter-field-on-appear | View appears | The search field is the window's first responder |
| breadcrumb-popover-016 | stop-escape-monitor-on-disappear | View is about to disappear | The escape-key monitor is stopped |
| breadcrumb-popover-017 | delegate-command-selectors-to-keyboard-controller | The down-arrow key is pressed while the search field has focus | `control(_:textView:doCommandBy:)` forwards the command selector to `keyboard.handle(_:)` and returns its `Bool` result |
| breadcrumb-popover-018 | double-click-chooses-row | User double-clicks a row representing a file | `chooseAction()` runs and `onSelect` is invoked with that file's URL |
| breadcrumb-popover-019 | open-selected-file | Selected row is a file "Notes.txt"; choose is invoked | `onSelect` is called exactly once, with "Notes.txt"'s URL |
| breadcrumb-popover-020 | ignore-directory-choice | Selected row is a subdirectory; choose is invoked | `onSelect` is NOT called |
| breadcrumb-popover-021 | ignore-choose-without-valid-selection | Filtered list is empty (`selectedRow == -1`); choose is invoked | `onSelect` is NOT called |
| breadcrumb-popover-022 | invoke-cancel-callback-when-set | `onCancel` has been set; keyboard controller reports cancel (Escape) | The `onCancel` closure is invoked exactly once |
| breadcrumb-popover-023 | no-op-cancel-when-unset | `onCancel` is `nil`; keyboard controller reports cancel (Escape) | No callback fires and no crash occurs |
| breadcrumb-popover-024 | reuse-cell-views | Table reloads repeatedly with the same column identifier | `makeView(withIdentifier:owner:)` returns and reuses the existing `NSTableCellView` rather than a newly constructed one on later reloads |
| breadcrumb-popover-025 | truncate-row-label-middle | Row label text is longer than the 248pt column width | The label's `lineBreakMode == .byTruncatingMiddle` and rendered text is elided in the middle |
| breadcrumb-popover-026 | single-column-table, no-column-header | Inspect `tableView` after `loadView` | Exactly one `NSTableColumn` (identifier `"breadcrumb.entry"`) exists and `headerView == nil` |
| breadcrumb-popover-027 | coder-initialization-unsupported | Attempt `BreadcrumbPopoverViewController(coder:)` | The call traps with a fatal error ("init(coder:) is not supported"); no instance is returned |

## Edge Cases

- Null/empty input (MUST): `directoryURL` and `onSelect` are non-optional,
  non-failable-typed initializer parameters, so Swift's type system rules
  out `nil` for either; the component provides, and needs, no nil-handling
  path for them. A `directoryURL` whose immediate contents are empty yields
  `entries == []` and `filtered == []`; the table shows zero rows and
  `selectRow`/`moveSelection` are no-ops (both guard on `!filtered.isEmpty`).
- Boundary values (MUST): `selectRow(_:)` clamps any index via
  `max(0, min(filtered.count - 1, index))` — e.g. `selectRow(-5)` with 3
  filtered entries selects row 0, and `selectRow(999)` selects row 2.
  `moveSelection(by:)` reuses the same clamp, so moving far past either end
  of the list settles on the nearest boundary row rather than wrapping or
  erroring.
- Concurrent access: Not applicable — the class is declared `@MainActor`, so
  Swift's concurrency checker confines all reads and writes of `entries`,
  `filtered`, and the UI to the main actor; source provides no path for two
  threads to mutate this view controller's state simultaneously.
- Error states (MUST): `FileTreeNode.loadChildren(for:)` is called
  synchronously and non-throwing in `init`, and its return value is assigned
  to `entries`/`filtered` unconditionally, with no `try`, `Result`, or error
  branch anywhere in source. The component performs no validation or error
  handling of its own on this call; whatever `loadChildren` returns —
  including an empty array, if that is how it represents an unreadable
  directory — is treated identically to a directory with no children. Any
  error handling for an unreadable directory is `FileTreeNode.loadChildren(for:)`'s
  own responsibility, and that function's implementation is outside the given
  source.
- Offline/disconnected: Not applicable — the component reads only the local
  file system via `FileTreeNode.loadChildren(for:)`; source contains no
  network call.
- Directory rows are inert (MUST): Per the type's doc comment, "Choosing a
  directory row does nothing; only files can be opened from here" —
  `chooseAction()` guards on `!node.isDirectory`, so a user cannot drill into
  a subdirectory from this popover; Return, double-click, and any other route
  into `chooseAction()` all have the same no-op outcome for a directory row.
- No empty-results messaging (MUST): When the current filter matches zero
  entries, the table renders zero rows with no placeholder text, icon, or
  "no results" view; source defines no empty-state UI for this case.
- `onCancel` set after construction (MUST): `onCancel` is documented as "Set
  by `BreadcrumbView` after construction, since only it holds the
  `NSPopover`." If Escape is pressed before the owning `BreadcrumbView` has
  assigned `onCancel`, the optional call `onCancel?()` is silently a no-op —
  the popover does not close through this path.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directoryURL` | `URL` | — (required) | The one directory whose immediate children are loaded and listed; read once at init and never reloaded. |
| `onSelect` | `(URL) -> Void` | — (required) | Invoked with a chosen file's URL when the user picks a non-directory row. |
| `onCancel` | `(() -> Void)?` | `nil` | Invoked when the keyboard controller reports cancel (Escape); typically set by `BreadcrumbView` after construction, since only it holds the `NSPopover`. |

## Deep Linking

Not applicable: this is a transient popover content view controller with no
URL scheme, route, or deep-link handler in source; `BreadcrumbView` presents
it programmatically as an `NSPopover`'s content view controller.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Filter" | Search field placeholder text |

Not applicable beyond the table above: row labels come from `FileTreeNode.name`
(file system entry names), not from a localized string table, so there is
nothing else in this file for the component itself to localize.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext` call; every state change (selection,
  filtering) is an instantaneous property assignment or synchronous
  `reloadData()`.
- **Increase Contrast**: Not applicable — `BreadcrumbPopoverViewController.swift`
  sets no custom `NSColor` anywhere; row and search-field appearance come
  entirely from AppKit's default control/label rendering.
- **Differentiate Without Color**: Satisfied — matched filter characters are
  conveyed by bold font weight (`attributedTitle(for:)`), not by color; row
  selection is AppKit's default highlight, not a component-defined color
  cue.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
source; the popover's content always renders once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call; `onSelect`
and `onCancel` are the only observable callbacks, both consumer-supplied.

## Privacy

- **Data collected**: None by the component itself — it reads local
  file/directory names via `FileTreeNode.loadChildren(for:)` for display
  only.
- **Storage**: In-memory only (`entries`, `filtered` arrays), for the view
  controller's lifetime; nothing is written to disk, `UserDefaults`, or any
  other store by this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view controller's lifetime; state is
  discarded when the popover closes.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
logger reference anywhere in this file).

## Platform Notes

- **SwiftUI**: Use a `List(filteredEntries, selection: $selectedID)` inside a
  `.popover`/sheet, with a `.searchable(text: $filterText)` modifier feeding
  the same substring-match predicate as `applyFilter`. Bind arrow-key,
  Return, and Escape handling via `.onKeyPress(_:)` in place of
  `PickerKeyboardController`'s command-selector routing, and highlight
  matched-range substrings by building an `AttributedString` per row with
  `.bold()` applied to the matched runs, mirroring `attributedTitle(for:)`.
  Give the list a fixed `.frame(width: 280, height: 320)` in place of
  `preferredContentSize`. A directory row's tap/selection action should be a
  no-op, mirroring `guard !node.isDirectory`.
- **Compose**: Host in a `Popup` or `DropdownMenu` sized to a fixed
  280×320dp `Box`. Compose's `LazyColumn` has no built-in keyboard-driven
  single selection the way `NSTableView` plus `PickerKeyboardController`
  provides, so intercept Up/Down/Enter/Escape with
  `Modifier.onPreviewKeyEvent` on the filter `OutlinedTextField`, moving a
  `selectedIndex` state and calling `LazyListState.animateScrollToItem` — the
  Compose analog of `scrollRowToVisible`. Render matched substrings with
  `buildAnnotatedString` and `SpanStyle(fontWeight = FontWeight.Bold)` over
  the matched ranges. A directory row's `onClick` should be a no-op,
  mirroring `guard !node.isDirectory`.
- **React/Web**: A fixed 280×320px container with an `<input type="search">`
  for the filter (its `onChange` re-filters immediately, mirroring
  `sendsSearchStringImmediately`/`controlTextDidChange`) above a
  `<ul role="listbox">` of `<li role="option">` rows. Implement Up/Down/
  Enter/Escape in the input's `onKeyDown` handler, updating a `selectedIndex`
  state and calling `element.scrollIntoView({ block: "nearest" })` on the
  newly selected row, mirroring `scrollRowToVisible`. Render matched
  substrings by wrapping the matched ranges in a bold `<strong>`/span,
  mirroring `attributedTitle(for:)`. A directory row should ignore both click
  and Enter-to-choose, mirroring `guard !node.isDirectory`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/BreadcrumbPopoverViewController.swift`.
  A `@MainActor`, `final` `NSViewController` presented as the content view
  controller of an `NSPopover` opened by a `BreadcrumbView` crumb. It builds
  its view by hand in `loadView()` — an `NSSearchField` above an
  `NSTableView` wrapped in an `NSScrollView`, laid out with Auto Layout
  constraints against a root `NSView` given an explicit 280×320 frame (see
  the loadView-frame Design Decision) — rather than loading a nib or using
  SwiftUI. Filtering (`applyFilter`), keyboard navigation
  (`PickerKeyboardController`, wired in `viewDidAppear`), and match
  highlighting (`ProjectFilter.ranges(of:in:)`, applied in
  `attributedTitle(for:)`) are shared collaborators reused from the app's
  other filterable pickers, not reimplemented locally. There is no UIKit code
  path in source; a UIKit port would replace `NSSearchField`/`NSTableView`
  with `UISearchBar`/`UITableView`, present the whole thing in a
  `UIPopoverPresentationController` (iPad) or a sheet (iPhone) instead of
  `NSPopover`, and would need to grow the 20pt AppKit row height to at least
  a 44pt touch target, since UIKit has no keyboard-first, pointer-driven
  `PickerKeyboardController` equivalent to fall back on for non-touch
  selection.
- **WinUI 3** (the reason this recipe exists): Build the popover content as
  an `AutoSuggestBox` (the WinUI analog of `NSSearchField`, already wired for
  immediate `TextChanged` filtering the way `sendsSearchStringImmediately`
  is) stacked above a `ListView` bound to the filtered collection, both
  hosted inside a `Flyout` (not a `MenuFlyout`, since arbitrary content — a
  search box plus a list — is needed, mirroring the AppKit choice of
  `NSPopover` over a plain menu) anchored to the breadcrumb crumb's button,
  sized to a fixed 280×320 epx `Grid` in place of `preferredContentSize`.
  Update the `ListView`'s bound collection on every `AutoSuggestBox.TextChanged`
  event, mirroring `applyFilter`'s `query.isEmpty ? entries :
  entries.filter { ... }` substring match, and reselect index 0 after every
  filter change, mirroring `reselect-first-row-after-filter`. Since WinUI has
  no `doCommandBy:`-style command-selector routing, intercept Up/Down/Enter/
  Escape in the `AutoSuggestBox`'s `PreviewKeyDown` handler, moving
  `ListView.SelectedIndex` and calling `ListView.ScrollIntoView(item)` — the
  direct analog of `scrollRowToVisible` — for Up/Down, invoking the choose
  logic for Enter, and calling `Flyout.Hide()` for Escape, the analog of
  `onCancel`. Render each row as a `TextBlock` containing multiple `Run`
  elements with `FontWeight="Bold"` applied to the matched ranges from the
  same substring-match logic, mirroring `attributedTitle(for:)`, and set
  `TextTrimming="CharacterEllipsis"`; note that WinUI's built-in ellipsis
  trims from the end, so approximating AppKit's middle-truncation
  (`truncate-row-label-middle`) requires either manual string splitting
  around the matched range or accepting end-truncation as the closest native
  equivalent — call this out to implementors as a deliberate platform
  difference. A `ListViewItem` bound to a directory entry should be a no-op
  in the `ItemClick`/`SelectionChanged` handler, mirroring
  `guard !node.isDirectory`.

## Design Decisions

- Decision: Give the popover's root view an explicit pixel frame
  (`NSRect(origin: .zero, size: Self.contentSize)`) in `loadView()`,
  alongside setting `preferredContentSize` in `init`.
  Rationale: Per the `loadView` source comment, `NSPopover` sizes an
  Auto-Layout content view to that view's fitting size and ignores its own
  `contentSize`; with no subview here having an intrinsic width, an unsized
  root would collapse to a 16×46pt sliver. The frame gives the root view an
  explicit width and height (since `translatesAutoresizingMaskIntoConstraints`
  stays `true` on it) for the constrained subviews to hang from, matching
  what `preferredContentSize` tells the popover separately.
  Approved: pending
- Decision: Reuse `PickerKeyboardController` for keyboard wiring and
  `ProjectFilter.ranges(of:in:)` for match highlighting instead of
  implementing either locally.
  Rationale: Per the type's doc comment, these are "the same two pieces the
  provider and model pickers already share" — reusing them keeps keyboard
  behavior and match highlighting consistent across every filterable picker
  in the app instead of a fourth, divergent implementation.
  Approved: pending
- Decision: Guard `chooseAction()` so choosing a directory row is a no-op
  instead of navigating into the subdirectory.
  Rationale: Per the type's doc comment, "Choosing a directory row does
  nothing; only files can be opened from here" — this popover is scoped to
  opening a file at the crumb's own directory level, not to browsing further
  down the tree.
  Approved: pending
- Decision: Unconditionally reselect row 0 in `applyFilter()` after every
  filter change, rather than preserving the previous selection or
  re-selecting the closest surviving match.
  Rationale: `applyFilter()` calls `selectRow(0)` on every invocation with no
  branch to preserve prior selection identity; this keeps the
  type-to-narrow-then-Return flow always landing on the top result without
  added logic to track selection identity across filter changes.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [live-region-announcements](agenticdevelopercookbook://compliance/accessibility#live-region-announcements) | flagged | accessibility |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | failed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |

Keyboard navigation is fully wired via `PickerKeyboardController` and the
search field's `doCommandBy:` delegation, hence passed. Screen-reader support
is partial: `accessibilityID` values are set on the search field and table
for automation, but no explicit `accessibilityLabel` override exists beyond
`NSTextField`'s own text content, and no announcement is posted when the
filtered result set changes (see live-region-announcements
and **Announce state changes** under Accessibility). Differentiate Without Color
passes because matched characters are conveyed by bold font weight, not
color. Touch-target-size is failed because the 20pt table row height falls
well under 44×44pt — expected for this pointer/keyboard-driven macOS list,
not a defect, but the 44×44pt/48×48dp threshold does apply to the
touch-platform translations in Platform Notes. Contrast-ratio is partial
because row and search-field colors come entirely from AppKit's default
system rendering, whose actual contrast values are not stated in this
source. String-externalization is failed because the search field's
`"Filter"` placeholder is a hardcoded English literal with no localization
key. Main-actor-confined passes because the class is declared `@MainActor`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial ingredient recipe for BreadcrumbPopoverViewController, covering directory loading, live filtering with bold match highlighting, clamped/relative selection, PickerKeyboardController wiring, the directory-is-inert choose guard, and one open accessibility question (filtered-result announcement) for review. |
