---
id: c79094d2-1f4b-4c3f-8005-8fb095fb1b40
title: Breadcrumb Popover
domain: agentictoolkit://cookbook/workspace/documents/breadcrumb-popover-view
type: ingredient
version: 1.2.0
status: review
language: en
created: 2026-09-23
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Filterable, keyboard-driven list of a directory's files shown in a breadcrumb's
  popover; selecting a file returns its URL, directories are inert.
platforms:
- swift
- macos
tags:
- picker
- filter
- popover
depends-on: []
related:
- agentictoolkit://cookbook/workspace/documents/breadcrumb-view
references: []
approved-by: ''
approved-date: ''
---

# Breadcrumb Popover

## Overview

This component shows the content of the popover a breadcrumb's crumb opens: a
small, filterable, keyboard-navigable list of one directory's immediate
children. Typing in the filter field narrows the list to entries whose name
matches, with matched characters shown in bold; arrow keys, Return, and
Escape are handled by shared keyboard-navigation logic rather than bespoke
keyboard code. Selecting a file row invokes a selection callback with that
file's URL; selecting a directory row does nothing — this popover only opens
files, it does not browse further down the tree.

## Behavioral Requirements

- **load-directory-children**: Component MUST load the immediate children of
  the directory at initialization and MUST use that list as both the
  unfiltered entry list and the initial filtered list.
- **fixed-content-size**: Component MUST size the popover's content to
  280×320 points at initialization.
- **filter-placeholder-text**: The filter field MUST display the placeholder
  text "Filter" when empty.
- **filter-updates-immediately**: Component MUST re-run filtering on every
  keystroke in the filter field, without waiting for the user to finish
  typing or press Return.
- **filter-by-name-match**: Component MUST filter entries to only those whose
  name contains at least one case-insensitive, diacritic-sensitive substring
  occurrence of the current filter text — a literal substring search, not a
  prefix-only or fuzzy/subsequence match.
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
- **focus-filter-field-on-appear**: Component MUST give the filter field
  keyboard focus when the view appears.
- **escape-key-cancels**: For the entire time the view is visible — from
  when it appears until it is about to disappear — Escape MUST trigger the
  cancel action (see invoke-cancel-callback-when-set, no-op-cancel-when-unset)
  regardless of which control has keyboard focus, and MUST NOT trigger it
  once the view has disappeared.
- **double-click-chooses-row**: Double-clicking a row MUST perform the same
  choose action as invoking choose through the keyboard.
- **open-selected-file**: Choosing a row MUST invoke the selection callback
  with the selected entry's URL only when that entry is a file.
- **ignore-directory-choice**: Choosing a row whose entry is a directory MUST
  NOT invoke the selection callback.
- **ignore-choose-without-valid-selection**: Choosing MUST NOT invoke the
  selection callback when there is no valid selected row index.
- **invoke-cancel-callback-when-set**: Component MUST invoke the cancel
  callback when keyboard navigation reports cancel and the cancel callback
  has been set.
- **no-op-cancel-when-unset**: Component MUST have no observable effect from
  a cancel when the cancel callback has not been set.
- **reuse-row-views**: Component MUST reuse a previously constructed row view
  for the table's column when one is available, constructing a new row view
  only when none exists yet, rather than always constructing a new one on
  reload.
- **truncate-row-label-middle**: The row label MUST truncate overflowing text
  in the middle.
- **single-column-table**: The table MUST present exactly one column.
- **no-column-header**: The table MUST NOT display a column header.
- **no-decoded-initialization**: Component MUST NOT support construction from
  a serialized/decoded representation (such as a saved interface file) and
  MUST fail fast if such construction is attempted.

## Appearance

- **Corner radius**: Not applicable — the component draws no custom layer;
  any rounding on the popover's chrome comes from the platform's own default
  popover appearance, not from this component's view hierarchy.
- **Padding**: Root view: 8pt top/leading/trailing around the filter field;
  6pt gap between the filter field's bottom and the scroll container's top;
  8pt leading/trailing/bottom around the scroll container. Row label: 4pt
  leading/trailing inset from the cell's edges, centered vertically.
- **Font**: Row label uses the system font at the platform's small system
  font size for unmatched characters and a bold variant of the system font
  at the same size for characters matching the current filter text.
- **Background**: Not set explicitly anywhere in source; the root view,
  filter field, table, and scroll container all use their platform's default
  backgrounds.
- **Foreground/Text**: Not set explicitly anywhere in source; row labels use
  the platform's default label text color, with only font weight (regular
  vs. bold) varying by match state.
- **Border**: No border is drawn on the scroll container; no border is
  configured on the filter field or the table either.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: The popover's content size and the root view's frame are
  fixed at 280×320pt (see fixed-content-size), the popover's one defined
  size constant, referenced elsewhere in this recipe by name rather than
  restated as a bare number; the single table column has a fixed width of
  248pt; no separate min/max constraint exists beyond these two fixed sizes.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected row) | Row label rendered at the small system font size; characters matching the current filter text are bold, the rest regular; no selection highlight. |
| Selected row | The platform's default row-selection highlight is applied; the row is scrolled into view. |
| Filtered (non-empty query) | Only entries whose name has at least one match for the current filter text are shown; matched characters render bold; row 0 of the new filtered list is reselected. |
| Empty result set | No rows are shown; selection changes become no-ops while the filtered list is empty. |
| Focused (filter field) | The filter field becomes focused when the view appears; source sets no other explicit focus-ring styling. |
| Disabled | Not applicable: no control in this component (filter field, table, rows) is ever disabled in source. |
| Loading | Not applicable: the directory's children are loaded synchronously at initialization; source defines no loading/pending state or indicator. |

## Accessibility

- **Role/trait**: Not explicitly set in source; the filter field and table
  use the platform's default control roles automatically.
- **Label requirements**: The filter field and table each carry an explicit
  accessibility identifier — `"breadcrumb.popover.filter"` and
  `"breadcrumb.popover.table"` respectively — for automation/testing, not for
  a screen reader, which does not speak identifiers. Neither control sets an
  explicit accessibility label: a screen reader has only the `"Filter"`
  placeholder for the filter field and no spoken name for the table. Each
  row's accessible content comes from its label's own displayed text (the
  entry's name, with matched characters bolded); source sets no separate
  accessibility-label override on the row or its text label.
- **Announce state changes**: Not implemented in source. When the filter is
  applied and reloads the table with a new, possibly much shorter, row
  count, source posts no accessibility notification informing assistive
  technology that the visible option set has changed; a screen-reader user
  hears nothing until navigating back into the table.
- **Minimum tap target**: The table's row height is 20pt, well under the
  44×44pt iOS minimum; this is expected for a pointer/keyboard-driven list
  (not a touch surface) and is not a tap-target defect on this platform. The
  44×44pt (iOS) / 48×48dp (Android) minimum applies to the touch-platform
  translations described in Platform Notes, not to this control.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| breadcrumb-popover-001 | load-directory-children | Initialize with a directory containing files "A.txt", "B.txt" and subdirectory "C" | The table shows exactly 3 rows, one per loaded entry, in that order, before any filter text is entered |
| breadcrumb-popover-002 | fixed-content-size | Read the popover's content size immediately after initialization | 280×320 points |
| breadcrumb-popover-003 | filter-placeholder-text | Inspect the filter field before any input | Its placeholder text is "Filter" |
| breadcrumb-popover-004 | filter-updates-immediately, filter-by-name-match | Entries "Apple.txt" and "Banana.txt" loaded; type "app" into the filter field | Table reloads to show only "Apple.txt" (the only name with a case-insensitive substring match for "app") before any further keystroke or Return is pressed |
| breadcrumb-popover-005 | show-all-entries-when-filter-empty | Filter field contains "a" and is then cleared to `""` | Table shows all originally loaded entries again |
| breadcrumb-popover-006 | select-first-row-on-load | Component finishes loading with 3 entries | Row 0 is selected |
| breadcrumb-popover-007 | reselect-first-row-after-filter | Row 2 is selected; user types a filter that matches multiple entries | Row 0 of the newly filtered list is selected |
| breadcrumb-popover-008 | bold-matched-characters | Filter field contains "ap"; an entry's name is "Apple.txt" | The name's displayed text carries bold styling for the "Ap" range; the remaining characters carry regular styling |
| breadcrumb-popover-009 | reject-empty-selection, reject-multiple-selection | Inspect the table's configuration after it loads | Empty selection is disallowed and multiple selection is disallowed |
| breadcrumb-popover-010 | clamp-selection-to-list-bounds | 3 filtered entries; request selecting index -5, then index 999 | First request selects row 0; second request selects row 2 |
| breadcrumb-popover-011 | no-op-selection-when-empty | Filter text matches no entries; request moving the selection by +1 | No row is selected and no index-out-of-range error occurs |
| breadcrumb-popover-012 | scroll-selection-into-view | Selection moves to a row currently scrolled out of view | The row scrolls into view and becomes visible |
| breadcrumb-popover-013 | relative-selection-movement | 5 filtered entries; row 1 is selected; request moving the selection by +2 | Row 3 becomes selected |
| breadcrumb-popover-014 | arrow-keys-move-selection | View has appeared with 3 entries and row 0 selected; filter field has keyboard focus; the Down arrow key is pressed twice | Row 2 becomes selected (see relative-selection-movement) |
| breadcrumb-popover-015 | focus-filter-field-on-appear | View appears | The filter field is focused |
| breadcrumb-popover-016 | escape-key-cancels | The cancel callback is set; Escape is pressed while the view is visible; the view then disappears and Escape is pressed again | The first Escape invokes the cancel callback exactly once; the second Escape, after the view has disappeared, has no effect |
| breadcrumb-popover-017 | return-key-chooses-selection | Filter field has keyboard focus; the selected row is a file "Notes.txt"; Return is pressed | The selection callback is invoked exactly once with "Notes.txt"'s URL (see open-selected-file) |
| breadcrumb-popover-018 | double-click-chooses-row | User double-clicks a row representing a file | The selection callback is invoked with that file's URL — the same outcome as choosing it through the keyboard |
| breadcrumb-popover-019 | open-selected-file | Selected row is a file "Notes.txt"; choose is invoked | The selection callback is called exactly once, with "Notes.txt"'s URL |
| breadcrumb-popover-020 | ignore-directory-choice | Selected row is a subdirectory; choose is invoked | The selection callback is NOT called |
| breadcrumb-popover-021 | ignore-choose-without-valid-selection | The current filter text matches no entries, so the table shows zero rows; Return is pressed | The selection callback is NOT called |
| breadcrumb-popover-022 | invoke-cancel-callback-when-set | The cancel callback has been set; keyboard navigation reports cancel (Escape) | The cancel callback is invoked exactly once |
| breadcrumb-popover-023 | no-op-cancel-when-unset | The cancel callback is unset; keyboard navigation reports cancel (Escape) | No callback fires and no crash occurs |
| breadcrumb-popover-024 | reuse-row-views | The same 3 entries are shown, then the filter is applied and cleared twice in a row, forcing repeated table reloads | No more than one row view per visible row position is ever constructed; already-constructed views are reused across the reloads and only their displayed text changes |
| breadcrumb-popover-025 | truncate-row-label-middle | Row label text is longer than the 248pt column width | The label truncates the overflow in the middle |
| breadcrumb-popover-026 | single-column-table, no-column-header | Inspect the table after it loads | Exactly one column (identifier `"breadcrumb.entry"`) exists and no header is shown |
| breadcrumb-popover-027 | no-decoded-initialization | Attempt construction from a serialized/decoded representation | The call fails fast (a fatal/trap error); no instance is returned |

## Edge Cases

- Null/empty input (MUST): the directory reference and the selection
  callback are non-optional, required initializer parameters, so the type
  system rules out an absent value for either; the component provides, and
  needs, no nil-handling path for them. A directory whose immediate contents
  are empty yields an empty entry list and an empty filtered list; the table
  shows zero rows and selection changes are no-ops.
- Boundary values (MUST): selecting an index clamps it to the valid range of
  the filtered list — e.g. selecting index -5 with 3 filtered entries
  selects row 0, and selecting index 999 selects row 2. Moving the selection
  by a relative offset reuses the same clamp, so moving far past either end
  of the list settles on the nearest boundary row rather than wrapping or
  erroring.
- Concurrent access: Not applicable — the component confines all reads and
  writes of its entry lists and UI to a single execution context, enforced
  by the platform's concurrency checker; source provides no path for two
  threads to mutate this component's state simultaneously.
- Error states (MUST): loading the directory's children is called
  synchronously and cannot fail in this component; its return value is
  assigned to the entry lists unconditionally, with no error branch anywhere
  in source. The component performs no validation or error handling of its
  own on this call; whatever the load returns — including an empty list, if
  that is how it represents an unreadable directory — is treated identically
  to a directory with no children. Any error handling for an unreadable
  directory is the loading operation's own responsibility, and its
  implementation is outside the given source.
- Offline/disconnected: Not applicable — the component reads only the local
  file system; source contains no network call.
- Directory rows are inert (MUST): choosing a directory row does nothing;
  only files can be opened from here. The choose action is guarded so it has
  no effect for a directory entry — Return, double-click, and any other
  route to choosing all have the same no-op outcome for a directory row.
- No empty-results messaging (MUST): When the current filter matches zero
  entries, the table renders zero rows with no placeholder text, icon, or
  "no results" view; source defines no empty-state UI for this case.
- Cancel callback set after construction (MUST): the cancel callback is
  documented as set by the breadcrumb view after construction, since only it
  owns the popover. If Escape is pressed before the owning breadcrumb view
  has assigned the callback, the call is silently a no-op — the popover does
  not close through this path.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Directory | directory reference (URL) | — (required) | The one directory whose immediate children are loaded and listed; read once at initialization and never reloaded. |
| Selection callback | callback receiving a URL | — (required) | Invoked with a chosen file's URL when the user picks a non-directory row. |
| Cancel callback | optional callback | unset | Invoked when keyboard navigation reports cancel (Escape); typically set by the breadcrumb view after construction, since only it owns the popover. |

## Deep Linking

Not applicable: this is a transient popover content component with no URL
scheme, route, or deep-link handler in source; the breadcrumb view presents
it programmatically as the popover's content.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Filter" | Filter field placeholder text |

"Filter" is assigned to the filter field's placeholder as a plain string
literal, not through a localization lookup, so it never reaches a string
catalog; there is no localization key or catalog entry for the placeholder.

Not applicable beyond the table above: row labels come from each entry's
file system name, not from a localized string table, so there is nothing
else in this file for the component itself to localize.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation or
  transition; every state change (selection, filtering) is an instantaneous
  property assignment or synchronous reload.
- **Increase Contrast**: Not applicable — source sets no custom color
  anywhere; row and filter-field appearance come entirely from the
  platform's default control/label rendering.
- **Differentiate Without Color**: Satisfied — matched filter characters are
  conveyed by bold font weight, not by color; row selection is the
  platform's default highlight, not a component-defined color cue.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
source; the popover's content always renders once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call; the
selection and cancel callbacks are the only observable callbacks, both
consumer-supplied.

## Privacy

- **Data collected**: None by the component itself — it reads local
  file/directory names for display only.
- **Storage**: In-memory only, for the component's lifetime; nothing is
  written to disk or any other persistent store by this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the component's lifetime; state is discarded
  when the popover closes.

## Logging

Not applicable: source contains no logging call anywhere in this file.

## Platform Notes

- **SwiftUI**: Use a `List(filteredEntries, selection: $selectedID)` inside a
  `.popover`/sheet, with a `.searchable(text: $filterText)` modifier feeding
  the same substring-match predicate as `applyFilter`. Bind arrow-key,
  Return, and Escape handling via `.onKeyPress(_:)` in place of
  `PickerKeyboardController`'s command-selector routing, and highlight
  matched-range substrings by building an `AttributedString` per row with
  `.bold()` applied to the matched runs, mirroring `attributedTitle(for:)`.
  Give the list a fixed `.frame(width: 280, height: 320)` (matching
  fixed-content-size) in place of `preferredContentSize`. A directory row's
  tap/selection action should be a no-op, mirroring `guard !node.isDirectory`.
- **Compose**: Host in a `Popup` or `DropdownMenu` sized to a fixed
  280×320dp `Box` (matching fixed-content-size). Compose's `LazyColumn` has
  no built-in keyboard-driven
  single selection the way `NSTableView` plus `PickerKeyboardController`
  provides, so intercept Up/Down/Enter/Escape with
  `Modifier.onPreviewKeyEvent` on the filter `OutlinedTextField`, moving a
  `selectedIndex` state and calling `LazyListState.animateScrollToItem` — the
  Compose analog of `scrollRowToVisible`. Render matched substrings with
  `buildAnnotatedString` and `SpanStyle(fontWeight = FontWeight.Bold)` over
  the matched ranges. A directory row's `onClick` should be a no-op,
  mirroring `guard !node.isDirectory`.
- **React/Web**: A fixed 280×320px container (matching fixed-content-size)
  with an `<input type="search">`
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
  controller of an `NSPopover` opened by a `BreadcrumbView` crumb. It loads
  the directory's immediate children via `FileTreeNode.loadChildren(for:)`
  synchronously in `init`, and row names come from `FileTreeNode.name`. It
  builds its view by hand in `loadView()` — an `NSSearchField` above an
  `NSTableView` wrapped in an `NSScrollView` (with `scrollView.borderType =
  .noBorder` and no border configured on the search field or table view),
  laid out with Auto Layout constraints against a root `NSView` given an
  explicit 280×320 frame (`Self.contentSize`, also set on
  `preferredContentSize` as `NSSize(width: 280, height: 320)`; see the
  loadView-frame Design Decision) — rather than loading a nib or using
  SwiftUI. The table's single column (`NSTableColumn`, identifier
  `"breadcrumb.entry"`) has a fixed width of 248pt (`column.width`) and
  `headerView == nil`; `tableView.allowsEmptySelection` and
  `allowsMultipleSelection` are both `false`, and `selectRow`/`moveSelection`
  are the concrete methods behind clamp-selection-to-list-bounds and
  relative-selection-movement, with `scrollRowToVisible` behind
  scroll-selection-into-view. The row label is an
  `NSTextField(labelWithString:)` using `NSFont.systemFont(ofSize:
  NSFont.smallSystemFontSize)` for unmatched characters and
  `NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)` for matched
  ones, with `lineBreakMode == .byTruncatingMiddle`; no custom `NSColor` is
  set anywhere, so text color comes from the label's AppKit default.
  Filtering (`applyFilter`), keyboard navigation (`PickerKeyboardController`,
  wired in `viewDidAppear`), and match highlighting
  (`ProjectFilter.ranges(of:in:)`, applied in `attributedTitle(for:)`) are
  shared collaborators reused from the app's other filterable pickers, not
  reimplemented locally. Keyboard routing (arrow-keys-move-selection,
  return-key-chooses-selection, escape-key-cancels) is wired in
  `viewDidAppear` by assigning `keyboard.onMoveSelection`,
  `keyboard.onChoose`, and `keyboard.onCancel` closures and calling
  `keyboard.startEscapeMonitor(for: view.window)`; the monitor is stopped in
  `viewWillDisappear`. Because `NSSearchField` normally consumes arrow keys,
  Return, and Escape as ordinary text-editing commands, the
  `NSSearchFieldDelegate` method `control(_:textView:doCommandBy:)`
  intercepts those command selectors first and forwards them to
  `keyboard.handle(_:)`, returning its `Bool` result so AppKit knows the key
  was handled; this delegate method is also what gives the search field
  first-responder focus in `viewDidAppear` (focus-filter-field-on-appear).
  Row views (reuse-row-views) come from
  `tableView.makeView(withIdentifier:owner:) as? NSTableCellView`, falling
  back to constructing a new `NSTableCellView` only when none is available
  for reuse. `chooseAction()` guards on `!node.isDirectory` for the
  directory-is-inert behavior. Accessibility identifiers
  (`"breadcrumb.popover.filter"`, `"breadcrumb.popover.table"`) are set via
  `accessibilityID(_:)`; no explicit `setAccessibilityRole`/
  `setAccessibilityElement`/`setAccessibilityLabel` call is made anywhere,
  and no `NSAccessibility.post(element:notification:)` call announces a
  filtered-result-count change. No `NSAnimationContext` call wraps any state
  change; every reload goes through synchronous `reloadData()`.
  `init(coder:)` is overridden to call `fatalError` unconditionally
  (no-decoded-initialization). There is no UIKit code path in source; a
  UIKit port would replace `NSSearchField`/`NSTableView` with
  `UISearchBar`/`UITableView`, present the whole thing in a
  `UIPopoverPresentationController` (iPad) or a sheet (iPhone) instead of
  `NSPopover`, would need to grow the 20pt AppKit row height to at least a
  44pt touch target, and would need `UIKeyCommand`-based hardware-keyboard
  handling to reach parity with `PickerKeyboardController`'s arrow-key/
  Return/Escape routing, since UIKit has no built-in equivalent.
- **WinUI 3** (the reason this recipe exists): Build the popover content as
  a `TextBox` with a `TextChanged` handler (not an `AutoSuggestBox`: its
  built-in suggestion flyout would open its own popup list directly under
  the box, clashing with the separate `ListView` this recipe already needs
  below it) stacked above that `ListView`, bound to the filtered collection,
  both hosted inside a `Flyout` (not a `MenuFlyout`, since arbitrary content —
  a search box plus a list — is needed, mirroring the AppKit choice of
  `NSPopover` over a plain menu) anchored to the breadcrumb crumb's button,
  sized to a fixed 280×320 epx `Grid` (matching fixed-content-size) in place
  of `preferredContentSize`. Update the `ListView`'s bound collection on
  every `TextBox.TextChanged` event, mirroring `applyFilter`'s
  `query.isEmpty ? entries : entries.filter { ... }` substring match, and
  reselect index 0 after every filter change, mirroring
  `reselect-first-row-after-filter`. Since WinUI has no `doCommandBy:`-style
  command-selector routing, intercept Up/Down/Enter/Escape in the
  `TextBox`'s `PreviewKeyDown` handler, moving
  `ListView.SelectedIndex` and calling `ListView.ScrollIntoView(item)` — the
  direct analog of `scrollRowToVisible` — for Up/Down, invoking the choose
  logic for Enter, and calling `Flyout.Hide()` for Escape, the analog of the
  cancel callback. Render each row as a `TextBlock` containing multiple `Run`
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/BreadcrumbPopoverViewController.swift` |

## Design Decisions

- **Decision**: Give the popover's root view an explicit pixel frame
  (`NSRect(origin: .zero, size: Self.contentSize)`) in `loadView()`,
  alongside setting `preferredContentSize` in `init`.
  **Rationale**: Per the `loadView` source comment, `NSPopover` sizes an
  Auto-Layout content view to that view's fitting size and ignores its own
  `contentSize`; with no subview here having an intrinsic width, an unsized
  root would collapse to a 16×46pt sliver. The frame gives the root view an
  explicit width and height (since `translatesAutoresizingMaskIntoConstraints`
  stays `true` on it) for the constrained subviews to hang from, matching
  what `preferredContentSize` tells the popover separately.
  **Approved**: pending
- **Decision**: Reuse `PickerKeyboardController` for keyboard wiring and
  `ProjectFilter.ranges(of:in:)` for match highlighting instead of
  implementing either locally.
  **Rationale**: Per the type's doc comment, these are "the same two pieces
  the provider and model pickers already share" — reusing them keeps
  keyboard behavior and match highlighting consistent across every
  filterable picker in the app instead of a fourth, divergent implementation.
  **Approved**: pending
- **Decision**: Guard `chooseAction()` so choosing a directory row is a
  no-op instead of navigating into the subdirectory.
  **Rationale**: Per the type's doc comment, "Choosing a directory row does
  nothing; only files can be opened from here" — this popover is scoped to
  opening a file at the crumb's own directory level, not to browsing further
  down the tree.
  **Approved**: pending
- **Decision**: Unconditionally reselect row 0 in `applyFilter()` after
  every filter change, rather than preserving the previous selection or
  re-selecting the closest surviving match.
  **Rationale**: `applyFilter()` calls `selectRow(0)` on every invocation
  with no branch to preserve prior selection identity; this keeps the
  type-to-narrow-then-Return flow always landing on the top result without
  added logic to track selection identity across filter changes.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

Keyboard navigation is fully wired via `PickerKeyboardController` and the
search field's `doCommandBy:` delegation, hence passed. Screen-reader support
is partial: `accessibilityID` values are set on the search field and table
for automation, but no explicit `accessibilityLabel` override exists beyond
`NSTextField`'s own text content. Touch-target-size is omitted from this table because it does not
apply to this pointer/keyboard-driven macOS list — the 44×44pt/48×48dp
threshold applies only to the touch-platform translations in Platform
Notes, not to this source. Contrast-ratio is partial because row and
search-field colors come entirely from AppKit's default system rendering,
whose actual contrast values are not stated in this source.
String-externalization is failed because the search field's `"Filter"`
placeholder is a hardcoded English literal with no localization key.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial ingredient recipe for BreadcrumbPopoverViewController, covering directory loading, live filtering with bold match highlighting, clamped/relative selection, PickerKeyboardController wiring, the directory-is-inert choose guard, and one open accessibility question (filtered-result announcement) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: stated the case-insensitive substring-match algorithm in filter-by-name-match and fixed test vector 004, which was wrong under that algorithm; replaced the AppKit-wiring requirements (callback assignment, escape-monitor start/stop, command-selector delegation, cell reuse) with behavior-first requirements for arrow-key/Return/Escape routing and row-view reuse, moving the AppKit mechanism detail into Platform Notes; rewrote four test vectors to assert observable table/callback behavior instead of private state or methods; fixed the Compliance table (dropped the non-catalog architecture/main-actor-confined row and the inapplicable touch-target-size row, capitalized categories, changed the disallowed `flagged` status to `failed`); added a `related` link to breadcrumb-view; recommended a `TextBox`/`TextChanged` WinUI 3 control over `AutoSuggestBox` to avoid a conflicting suggestion list; removed an unsupported UIKit claim in favor of a `UIKeyCommand` note; named the fixed content size once and cross-referenced it from every Platform Notes bullet instead of restating it; reformatted Design Decisions into the three-line bold form; and unquoted the frontmatter dates. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/documents/. |
