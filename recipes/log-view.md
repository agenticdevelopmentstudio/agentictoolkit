---
id: c5a74f9a-d38f-4724-ad1d-f6460ebc2bb0
title: Log View
domain: agentictoolkit://recipes/log-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit NSView; a themed, scrollable NSTableView driven by a LogProvider that
  renders its columns/lines, dispatches per-column click hooks, and auto-follows the
  tail.
platforms:
- swift
- macos
tags:
- log
- table
- macos
- appkit
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# Log View

## Overview

`LogView` is an `NSView` that renders a scrolling, multi-column table of
`LogLine`s supplied by a caller-provided `LogProvider`. It builds its table
columns from `provider.columns` at construction time, redraws whenever the
provider notifies it of an append, replace, or clear, and routes single- and
double-clicks on a cell to the hooks defined on that cell's column so that
domain logic (opening a session detail, copying an id, etc.) stays with the
consumer rather than the view. It deliberately ships no toolbar, filter UI,
or status indicator — those are caller concerns, composed around the view
(for example inside `LogWindowController`) or embedded elsewhere.

## Behavioral Requirements

- **embeds-table-in-full-bleed-scroll-view**: The component MUST embed its
  table view inside a scroll view pinned to the component's top, leading,
  trailing, and bottom edges, filling the component's bounds.
- **vertical-only-scrolling**: The scroll view MUST show a vertical
  scroller, MUST NOT show a horizontal scroller, and MUST auto-hide its
  scrollers.
- **columns-built-once-from-provider**: The component MUST create exactly
  one table column per entry in `provider.columns`, in that order, at
  initialization, using each column's `id` as the table column's identifier
  and each column's `title`, `defaultWidth`, `minWidth`, and `maxWidth` to
  configure it.
- **column-layout-fixed-after-init**: The component MUST NOT rebuild, add,
  or remove table columns after initialization, even if the provider's
  `columns` were to differ later; the layout captured at `init(provider:)`
  is permanent for the life of the instance.
- **columns-user-resizable-uniform**: Table columns MUST be resizable by the
  user, and MUST resize uniformly across all columns when the table view's
  own width changes.
- **horizontal-grid-lines-only**: The table MUST draw a horizontal rule
  between rows and MUST NOT draw vertical rules between columns.
- **row-count-matches-provider**: The number of rows the table reports MUST
  always equal `provider.lines.count`.
- **renders-initial-lines-at-init**: The component MUST reload and display
  whatever lines the provider already holds at the moment `init(provider:)`
  runs, before any subsequent change notification arrives.
- **plain-cell-value-rendering**: A cell whose `LogLine` value for that
  column is `.plain(String)` MUST display that string as the cell's text.
- **attributed-cell-value-rendering**: A cell whose value is
  `.attributed(NSAttributedString)` MUST display that attributed string as
  the cell's text, preserving whatever font and color attributes the caller
  supplied on it.
- **missing-cell-value-renders-empty**: A cell with no entry for its column
  in `LogLine.values` MUST render as an empty string.
- **cell-alignment-follows-column**: A cell's text alignment MUST equal the
  `alignment` configured on that cell's column.
- **cell-text-truncates-tail**: Cell text that overflows the column's width
  MUST truncate with a trailing ellipsis.
- **cell-tooltip-mirrors-display-text**: Every cell MUST carry a tooltip
  equal to the text currently displayed in that cell.
- **cell-view-reused-per-column**: The component MUST reuse one text-field
  view per column id across row renders, keyed by a per-column reuse
  identifier, rather than allocating a new view for every rendered row.
- **cell-text-not-selectable**: Cell text MUST NOT be user-selectable; the
  table's row-level selection is the only selection surface this component
  provides.
- **selected-row-uses-theme-selection-color**: A selected row MUST be
  highlighted by filling a rounded rectangle — 4pt corner radius, inset 2pt
  horizontally and 1pt vertically from the row's bounds — with the active
  theme's `selection` role color.
- **row-view-freshly-constructed-per-call**: The delegate's row-view
  callback MUST return a newly constructed row view on every call rather
  than dequeuing or reusing an existing instance by identifier.
- **single-click-dispatches-column-hook**: A single click on a cell whose
  row and column both resolve to a valid line and column MUST invoke that
  column's `onClick` closure with the clicked `LogLine`.
- **double-click-dispatches-column-hook**: A double click meeting the same
  validity conditions MUST invoke that column's `onDoubleClick` closure with
  the clicked `LogLine`.
- **click-outside-valid-cell-is-inert**: A click whose column index is
  negative, whose row index is negative, or whose row index is at or beyond
  `provider.lines.count` MUST NOT invoke any click hook.
- **dispatch-click-public-test-entry**: The click-dispatch method MAY be
  called directly, since it is exposed publicly, to simulate a click without
  driving a real AppKit mouse event.
- **reloads-on-every-provider-change**: Every provider change notification
  — appended, replaced, or cleared — MUST result in the table reloading its
  data before any auto-scroll decision for that change is applied.
- **append-follows-tail-only-if-already-at-bottom**: On an appended change,
  the component MUST scroll to the last row after reloading if and only if
  `followTail` is `true` and the view was within 2 points of the bottom —
  measured before the reload, at the moment the change arrived.
- **replace-follows-tail-unconditionally**: On a replaced change, the
  component MUST scroll to the last row after reloading whenever `followTail`
  is `true`, regardless of the scroll position before the change.
- **clear-never-follows-tail**: On a cleared change, the component MUST NOT
  scroll to the end, even when `followTail` is `true`.
- **follow-tail-is-mutable-and-effective**: `followTail` MUST default to
  `true`, and setting it to `false` MUST suppress the auto-scroll-to-end
  behavior on every subsequent appended or replaced change until it is set
  back to `true`.
- **scroll-to-end-no-ops-when-empty**: The component's scroll-to-end
  operation MUST scroll the last row into view when at least one row
  exists, and MUST be a no-op when the table has zero rows.
- **reload-is-public-and-unconditional**: The component's public reload
  operation MUST refresh the table's displayed data whenever invoked,
  independent of any provider change notification.
- **coder-init-unavailable**: `init(coder:)` MUST be marked unavailable at
  compile time, and MUST call `fatalError` if somehow invoked at runtime.

## Appearance

- **Corner radius**: 4pt, on the selected-row highlight fill only (see
  `selected-row-uses-theme-selection-color`). No other element in source
  carries a corner radius.
- **Padding**: 2pt horizontal / 1pt vertical inset applied only to the
  selection highlight's fill rectangle. No other cell, row, or container
  inset is set in source; `NSTableView`'s system-default intercellSpacing
  applies unmodified.
- **Font**: Cell text uses `ThemedLabel`'s default text role, `.body`, since
  the cell factory constructs it with no explicit `textRole` argument. A
  `.attributed` cell value can override this with its own font attributes,
  which take precedence for that cell.
- **Background**: The table fills with the theme's `.windowBackground`
  role — not `.surface` — so the log reads as the full content of its own
  window or pane rather than as a sidebar plane (see Design Decisions). The
  scroll view's own background likewise resolves to `.windowBackground`.
- **Foreground/Text**: Cell text color comes from `ThemedLabel`'s default
  role, `.primaryText`, unless a `.attributed` value supplies its own color.
- **Border**: None. Row-to-row separation is drawn as a horizontal grid
  line colored with the theme's `.divider` role (see
  `horizontal-grid-lines-only`); there is no vertical border between
  columns and no border around the component itself.
- **Shadow**: None specified in source.
- **Min/Max size**: None set by this component. The table's row height
  comes from AppKit's system default for `rowSizeStyle: .default`; no
  explicit row, column, or component height/width constraint is set beyond
  each column's own `defaultWidth`/`minWidth`/`maxWidth`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Rows render per `provider.lines`, styled as described in Appearance. |
| Pressed | Not applicable: source defines no distinct pressed-state styling; whatever mouse-down feedback `NSTableView` supplies for an unselected row before a click resolves is unmodified here. |
| Disabled | Not applicable: `LogView` exposes no enabled/disabled toggle and defines no disabled appearance in source. |
| Focused | Not applicable: source sets no custom focus-ring appearance on the table view or its cells; the system default focus ring is unmodified. |
| Loading | Not applicable: `LogView` has no loading indicator or in-flight state; a provider push is reflected synchronously from the view's perspective. |
| Selected | Row is filled with a 4pt-corner-radius rounded rectangle, inset 2pt/1pt, in the theme's `selection` role color (see `selected-row-uses-theme-selection-color`). |
| Empty | When `provider.lines` is empty, the table shows zero rows; the scroll-to-end operation is a no-op; the component's own scroll-position check treats a zero-row table as already at the bottom, so a subsequent append on a previously empty log follows the tail. |

## Accessibility

- Role/trait: Source adds no custom `NSAccessibility` conformance or role
  override; VoiceOver sees AppKit's built-in table accessibility hierarchy
  (table, then row, then cell) unmodified.
- Label requirements: Each cell's accessible value is its own displayed
  text, which AppKit exposes automatically as the text field's accessibility
  value; column headers get their accessible name from the caller-supplied,
  required `LogColumn.title`. No cell or column in this file is left
  without a label.
- Minimum tap target: Not applicable. This is a pointer-driven macOS
  control, not a touch surface; row height is left to AppKit's system
  default for `rowSizeStyle: .default`, and no explicit width or height is
  set on the table, its columns, or its cells in source.
- Contrast: Not applicable at this component's level. `LogView.swift` fixes
  no numeric color value itself — it selects semantic theme roles
  (`.windowBackground`, `.divider`, `.selection`, and `ThemedLabel`'s
  default `.primaryText`) whose concrete colors, and therefore their
  contrast ratios, are resolved by the active theme palette at runtime.
  Meeting a contrast standard is that palette's responsibility, not
  something decidable from this file.
- NEEDS REVIEW: Not implemented in source. Behavior undefined. The
  per-column `onClick`/`onDoubleClick` hooks are wired only to mouse
  actions (the table's click and double-click actions); nothing in
  `LogView.swift` invokes the click-dispatch method from a keyboard event
  (for example, Return or Space on the currently selected row), so a
  keyboard-only or switch-control user has no way to trigger a column's
  click hook. This would be settled by adding a key-event handler that
  calls the dispatch method for the selected row, or by confirming with the
  design owner that click hooks are pointer-only by design.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| log-view-001 | embeds-table-in-full-bleed-scroll-view | Construct the view and inspect its subviews and constraints. | A scroll view is the sole subview, with its top/leading/trailing/bottom anchored to the component's own edges. |
| log-view-002 | vertical-only-scrolling | Inspect the scroll view after construction. | `hasVerticalScroller == true`, `hasHorizontalScroller == false`, `autohidesScrollers == true`. |
| log-view-003 | columns-built-once-from-provider | Construct with a provider exposing 3 columns in a given order. | The table has exactly 3 columns, in that order, each with the source column's id, title, and widths. |
| log-view-004 | column-layout-fixed-after-init | Construct with a provider, then observe the same provider's `columns` differ on a later read. | The table's column set is unchanged from what was captured at construction. |
| log-view-005 | columns-user-resizable-uniform | Construct the view and inspect the table's resizing configuration. | `allowsColumnResizing == true`; column autoresizing style is the uniform style. |
| log-view-006 | horizontal-grid-lines-only | Construct the view and inspect the table's grid style mask. | Only the solid-horizontal-grid-line mask is set; no vertical grid line mask is set. |
| log-view-007 | row-count-matches-provider | Construct with a provider holding 5 lines. | The table's reported row count is 5. |
| log-view-008 | renders-initial-lines-at-init | Construct with a provider that already holds 2 lines. | Immediately after `init`, the table displays 2 rows without any change notification having fired. |
| log-view-009 | plain-cell-value-rendering | Provide a line with a `.plain("hello")` value for a column. | The rendered cell's text is `hello`. |
| log-view-010 | attributed-cell-value-rendering | Provide a line with an `.attributed` value carrying a custom color. | The rendered cell displays that attributed string, including its custom color. |
| log-view-011 | missing-cell-value-renders-empty | Provide a line with no value for one of the table's columns. | That cell's text is the empty string. |
| log-view-012 | cell-alignment-follows-column | Configure a column with `.right` alignment and render a line under it. | The cell's alignment is `.right`. |
| log-view-013 | cell-text-truncates-tail | Provide a value longer than the column's width. | The cell's line-break mode is truncating-tail and the rendered text ends with an ellipsis. |
| log-view-014 | cell-tooltip-mirrors-display-text | Render a cell showing `session-42`. | The cell's tooltip reads `session-42`. |
| log-view-015 | cell-view-reused-per-column | Scroll through many rows under the same column, capturing the cell view identity for two different rows. | Both renders reuse the same underlying view instance for that column's reuse identifier. |
| log-view-016 | cell-text-not-selectable | Inspect a rendered cell's text field. | `isSelectable == false`. |
| log-view-017 | selected-row-uses-theme-selection-color | Select a row and inspect its row view's drawn selection. | A rounded rectangle (4pt radius, inset 2pt/1pt) is filled with the theme's selection color. |
| log-view-018 | row-view-freshly-constructed-per-call | Request a row view for the same row index twice via the delegate callback. | Two distinct row view instances are returned. |
| log-view-019 | single-click-dispatches-column-hook | Single-click a valid cell whose column has an `onClick` hook. | The hook is invoked once with the clicked line. |
| log-view-020 | double-click-dispatches-column-hook | Double-click a valid cell whose column has an `onDoubleClick` hook. | The hook is invoked once with the clicked line. |
| log-view-021 | click-outside-valid-cell-is-inert | Dispatch a click with a negative column index, then with a negative row index, then with a row index at `provider.lines.count`. | No hook is invoked in any of the three cases. |
| log-view-022 | dispatch-click-public-test-entry | Call the click-dispatch method directly with a valid column index, row, and kind, without any AppKit mouse event. | The matching column hook is invoked exactly as it would be from a real click. |
| log-view-023 | reloads-on-every-provider-change | Trigger an appended, then a replaced, then a cleared change. | The table's data is reloaded after each of the three notifications. |
| log-view-024 | append-follows-tail-only-if-already-at-bottom | With `followTail == true` and the view scrolled within 2pt of the bottom, trigger an appended change. | The view scrolls to the new last row after the reload. |
| log-view-024b | append-follows-tail-only-if-already-at-bottom | With `followTail == true` and the view scrolled away from the bottom, trigger an appended change. | The view does not scroll; the pre-change scroll position is preserved. |
| log-view-025 | replace-follows-tail-unconditionally | With `followTail == true` and the view scrolled away from the bottom, trigger a replaced change. | The view scrolls to the new last row after the reload. |
| log-view-026 | clear-never-follows-tail | With `followTail == true`, trigger a cleared change. | The view does not scroll to the end; the table shows zero rows. |
| log-view-027 | follow-tail-is-mutable-and-effective | Set `followTail = false`, then trigger an appended change while scrolled to the bottom. | The view does not auto-scroll for that change. |
| log-view-028 | scroll-to-end-no-ops-when-empty | Call the scroll-to-end operation on a view whose provider has zero lines. | No scroll occurs and no error or crash results. |
| log-view-029 | reload-is-public-and-unconditional | Call the public reload operation with no preceding provider change. | The table's data is reloaded. |
| log-view-030 | coder-init-unavailable | Attempt to construct the view via `NSCoder`-based decoding (for example, from a storyboard or XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |

## Edge Cases

- **Null/empty input**: `provider.lines` empty at construction or after a
  clear MUST render zero rows (see States: Empty). A line with no value for
  a given column MUST render that cell as an empty string
  (`missing-cell-value-renders-empty`). A column with `onClick`/
  `onDoubleClick` both `nil` MUST allow a click to resolve without effect
  (the hook call is a no-op optional invocation).
- **Boundary values**: A click exactly on the last valid row and last valid
  column index MUST dispatch normally; a click one index past the last row
  (`row == provider.lines.count`) MUST be inert
  (`click-outside-valid-cell-is-inert`). An unbounded log (`maxLines ==
  Int.max`) or a log capped by `maxLines` are both handled identically by
  this component, since row-count capping is a `LogProvider` concern —
  `LogView` only ever displays however many lines `provider.lines` reports
  at the time it is asked.
- **Concurrent access**: The component, `LogProvider`, and
  `LogProviderDelegate` are all `@MainActor`-isolated, so every provider
  mutation and every view update this file performs is serialized onto the
  main actor; Swift's actor isolation is the entirety of the concurrency
  handling in source, and there is no additional locking or queuing code
  here.
- **Error states**: `LogView` performs no I/O, network, or asynchronous
  operation of its own, so it has no failure mode to report. It has no
  validation of the `LogLine`/`LogColumn` values it is handed beyond the
  guards already covered above (`missing-cell-value-renders-empty`,
  `click-outside-valid-cell-is-inert`); malformed input from a
  misbehaving provider is not specially detected or reported.
- **Offline/disconnected state**: Not applicable. `LogView.swift` makes no
  network calls; connectivity handling, if any, belongs to whatever
  `LogProvider` implementation feeds it (for example, an SSE subscription),
  which is a separate component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `provider` | `any LogProvider` | required (no default) | The backing data source; its `columns` are captured once at init, its `lines` are re-read on every table reload. |
| `followTail` | `Bool` | `true` | Whether newly appended rows auto-scroll into view and whether a full replace re-anchors to the bottom; setting it to `false` is how a caller builds a "pause auto-scroll" control. |

`LogColumn` (id, title, widths, alignment, click hooks) and `LogLine`
(values, context) are separate value types defined in sibling files, not
owned by this component; this table covers only the options `LogView`
itself exposes.

## Deep Linking

Not applicable: `LogView.swift` contains no URL-scheme or route handling.

## Localization

Not applicable: `LogView.swift` defines no string literal of its own. All
user-visible text — column titles and cell values — originates from the
caller-supplied `LogProvider`/`LogColumn`, whose localization is that
caller's responsibility, not this file's.

## Accessibility Options

- **Reduce Motion**: Not applicable. Source calls the scroll-to-visible
  operation directly, with no animation context or animator proxy wrapping
  it, so there is no motion effect to suppress.
- **Increase Contrast**: Not applicable at this component's level. Colors
  are drawn entirely from semantic theme roles; neither `LogView.swift` nor
  the themed view types it uses branch on an increase-contrast accessibility
  setting, so any such adaptation would live in the theme/palette system,
  not here.
- NEEDS REVIEW: Not implemented in source. Behavior undefined. The selected
  row is conveyed by a background color fill alone (see
  `selected-row-uses-theme-selection-color`) — no additional shape, border,
  or icon marks a selected row when color is hard to distinguish. This
  would be settled by adding a non-color cue (for example, a border or
  leading indicator) to the selected-row rendering, or by confirming with
  the design owner that a color-only cue is acceptable here.

## Feature Flags

Not applicable: `LogView.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `LogView.swift` contains no analytics or event-tracking
calls.

## Privacy

- **Data collected**: None collected by this component itself. It only
  renders whatever `LogLine`s the provider already holds, including each
  line's opaque `context` payload, which `LogView` never reads itself — it
  only forwards the whole line to a column's click hooks.
- **Storage**: None. `LogView.swift` writes nothing to disk or
  `UserDefaults`.
- **Transmission**: None. `LogView.swift` makes no network calls.
- **Retention**: Determined entirely by the provider. `LogView` keeps no
  copy of the data beyond what it reads from `provider.lines` at render
  time; any row-count cap (`maxLines`) is the provider's own concern, not
  this component's.

## Logging

Not applicable: `LogView.swift` contains no `os_log`, `Logger`, or other
logging calls.

## Platform Notes

- **SwiftUI**: The source is pure AppKit (`NSView`/`NSTableView`), not
  SwiftUI. A SwiftUI counterpart would use `Table` (or `List` for a
  single-column case) driven by an `ObservableObject` wrapping the same
  `LogProvider` contract, one `TableColumn` per `LogColumn`, a tap gesture
  or context menu in place of `onClick`/`onDoubleClick`, and a
  `ScrollViewReader` with `scrollTo(id:anchor:.bottom)` in place of the
  scroll-to-end operation and `followTail`.
- **Compose**: Start from a `LazyColumn` (or a row of independently-scrolled
  `LazyColumn`s for true per-column widths) backed by a `StateFlow<List
  <LogLine>>` equivalent to `provider.lines`; per-column click hooks map to
  `Modifier.pointerInput` with `detectTapGestures(onTap, onDoubleTap)`; tail
  follow maps to `LazyListState.animateScrollToItem` on the last index,
  gated the same way — only when already near the bottom, or unconditionally
  on a full replace.
- **React/Web**: Use a virtualized table/grid fed the same column and line
  shape; per-column click handlers become `onClick`/`onDoubleClick` on each
  cell; tail follow is the common scrollback pattern — check whether the
  scroll container is within a small threshold of its bottom before an
  append, then scroll it to the bottom after the DOM updates, mirroring this
  component's pre-reload scroll check.
- **AppKit / UIKit**: This is the source platform (AppKit, macOS). A UIKit
  counterpart has no first-class multi-column table equivalent to
  `NSTableView`; it would use a `UITableView`/`UICollectionView` with a
  compositional, multi-column cell layout, a diffable data source driven by
  the same `LogProvider` contract, a tap and a long-press or double-tap
  gesture recognizer in place of the table's click and double-click
  actions, and a scroll-to-row operation in place of the scroll-to-visible
  call.
- **WinUI 3**: Model the table as a `DataGrid` (from the Windows Community
  Toolkit's WinUI controls), the closest match to a multi-column,
  user-resizable, per-cell-styled `NSTableView`; a plain `ListView` with a
  `Grid`-based row template is the alternative if avoiding that dependency.
  Map each `LogColumn` to a `DataGridTextColumn`/`DataGridTemplateColumn`
  with its `Width`, `MinWidth`, and `MaxWidth` bound from the column model;
  bind `ItemsSource` to an observable collection standing in for
  `provider.lines`; wire a tapped and a double-tapped handler on each cell
  to the same per-column `onClick`/`onDoubleClick` hooks; drive the selected
  row's highlight from a style targeting the row's background in its
  selected visual state, using the app's selection brush — WinUI's
  selection highlight is typically full-bleed rectangular, not the 4pt
  rounded, inset rectangle this AppKit view draws, which is worth calling
  out to implementers as an intentional visual difference rather than a
  bug; and implement tail follow by checking the scroll viewer's vertical
  offset against its scrollable height, using the same 2-point tolerance
  this file uses, before appending, then scrolling to the last item after
  the collection updates.

## Design Decisions

Decision: Fill the table with the `.windowBackground` theme role rather than
`.surface`.
Rationale: source comments state the log should read as the full content of
its own window or pane, rather than as a sidebar, matching how a related
timeline's table is themed — so it blends into the backdrop instead of
reading as its own plane.
Approved: pending.

Decision: Turn off alternating row background colors and rely on a
horizontal-only grid line for row separation instead of banding.
Rationale: source comments state banding comes from a system color pair the
theme has no say in, and that without any row separator the log read as an
unbroken block of text with no row boundaries at all — the horizontal grid
line is the theme-controlled substitute.
Approved: pending.

Decision: Capture `provider.columns` once, at `init(provider:)`, and never
rebuild the table's column set afterward.
Rationale: the provider's own documentation states columns are expected to
be stable for the lifetime of the provider and that this component captures
them at init time; later column changes are out of contract.
Approved: pending.

Decision: Compute the scroll-position check before calling reload on an
appended change, rather than after.
Rationale: the tail-follow decision needs the scroll position as it was
before new rows were inserted — checking after the reload would measure
geometry that already includes the newly appended rows, which would always
read as "not at bottom" whenever new content is what pushed the content
taller than the viewport.
Approved: pending.

Decision: Return a newly constructed row view on every delegate callback
instead of reusing a dequeued instance by identifier.
Rationale: source comments state each row needs to own its own theme
observer, since a selection fill baked in at creation would draw stale after
a theme change if the instance were pooled and reused across it; AppKit
still recycles the row views this method returns internally regardless of
whether the caller dequeues them itself.
Approved: pending.

Decision: Route click hooks only through the table's own click/double-click
actions, and expose the click-dispatch method publicly.
Rationale: source comments state this lets tests (and callers doing
programmatic dispatch) drive the same entry point AppKit uses, without
needing to synthesize real mouse events.
Approved: pending.

## Compliance

No automated compliance checks have been run against this recipe yet. This
table will be populated by the cookbook's compliance tooling on review.

| Check | Status | Category |
|-------|--------|----------|

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
