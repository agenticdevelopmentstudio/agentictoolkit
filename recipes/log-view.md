---
id: c5a74f9a-d38f-4724-ad1d-f6460ebc2bb0
title: Log View
domain: agentictoolkit://recipes/log-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Themed AppKit log table driven by a LogProvider, with per-column click hooks
  and tail-follow.
platforms:
- swift
- macos
tags:
- log
- table
- macos
- appkit
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
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

This component has no ingredient recipe of its own for the collaborator
types it takes; a consumer implementing them needs only this minimal
contract:

- **`LogProvider`** (`@MainActor` protocol): a settable `delegate:
  LogProviderDelegate?` that this component assigns itself to at init;
  `columns: [LogColumn]`, captured once at `init(provider:)`; `lines:
  [LogLine]`, re-read on every table reload; and `maxLines: Int`, which this
  component never reads (row-count capping is the provider's own concern).
- **`LogProviderDelegate`** (`@MainActor` protocol): one method,
  `logProvider(_:didChange:)`, called with a `LogChange` — `.appended(count:
  Int)`, `.replaced`, or `.cleared`.
- **`LogColumn`**: `id: String` (the table column's identifier and the key
  into `LogLine.values`), `title: String`, `defaultWidth`/`minWidth`/
  `maxWidth: CGFloat`, `alignment: NSTextAlignment`, and optional
  `onClick`/`onDoubleClick: ((LogLine) -> Void)?` hooks.
- **`LogLine`**: `values: [String: LogCellValue]` keyed by column id, where
  `LogCellValue` is `.plain(String)` or `.attributed(NSAttributedString)`; a
  column with no entry in `values` renders as an empty string.
- **`ThemedLabel`, `ThemedTableView`, `ThemedScrollView`,
  `ThemedTableRowView`**: themed AppKit view types that resolve semantic
  theme roles (`.windowBackground`, `.primaryText`, `.selection`,
  `.divider`) to the active palette's concrete colors; this component only
  selects which role each one uses.

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
- **cell-request-uses-column-reuse-identifier**: Every cell view MUST be
  requested via `NSTableView.makeView(withIdentifier:owner:)` using a reuse
  identifier scoped to that cell's column id, rather than always
  constructing a new view directly (see Design Decisions).
- **cell-text-not-selectable**: Cell text MUST NOT be user-selectable; the
  table's row-level selection is the only selection surface this component
  provides.
- **selected-row-uses-theme-selection-color**: A selected row MUST be
  highlighted by filling a rounded rectangle — 4pt corner radius, inset 2pt
  horizontally and 1pt vertically from the row's bounds — with the active
  theme's `selection` role color.
- **selection-fill-reflects-current-theme**: A row's selection-fill color
  MUST reflect the active theme's `selection` role at the time the row is
  drawn, including for a row that was already on screen when the theme
  changed (see Design Decisions).
- **single-click-dispatches-column-hook**: A single click on a cell whose
  row and column both resolve to a valid line and column MUST invoke that
  column's `onClick` closure with the clicked `LogLine`.
- **double-click-dispatches-column-hook**: A double click meeting the same
  validity conditions MUST invoke that column's `onDoubleClick` closure with
  the clicked `LogLine`.
- **click-outside-valid-cell-is-inert**: A click whose column index is
  negative, whose row index is negative, or whose row index is at or beyond
  `provider.lines.count` MUST NOT invoke any click hook.
- **public-dispatch-applies-same-guards**: The public click-dispatch method
  MUST apply the same column/row validity guards as the mouse-driven click
  actions, so calling it directly with a given column index, row, and kind
  behaves identically to a real click or double-click at that same index
  (see Design Decisions for why it is exposed publicly).
- **reloads-on-every-provider-change**: Every provider change notification
  — appended, replaced, or cleared — MUST result in the table reloading its
  data before any auto-scroll decision for that change is applied.
- **append-follows-tail-only-if-already-at-bottom**: On an appended change,
  the component MUST scroll to the last row after reloading if and only if
  `followTail` is `true` and, measured before the reload at the moment the
  change arrived, the table's document view (flipped, so Y increases
  downward from the top) satisfies `documentView.bounds.height -
  scrollView.documentVisibleRect.maxY <= 2` — or the table had zero rows
  (see `empty-table-counts-as-at-bottom`).
- **empty-table-counts-as-at-bottom**: The component's scroll-position check
  MUST treat a table with zero rows as already at the bottom, so that the
  first append to a previously empty log follows the tail whenever
  `followTail` is `true`.
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
  `selected-row-uses-theme-selection-color`). No other element carries a
  corner radius.
- **Padding**: 2pt horizontal / 1pt vertical inset applied only to the
  selection highlight's fill rectangle. No other cell, row, or container
  inset is set; `NSTableView`'s system-default intercellSpacing applies
  unmodified.
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
- **Shadow**: None.
- **Min/Max size**: None set by this component. The table's row height
  comes from AppKit's system default for `rowSizeStyle: .default`; no
  explicit row, column, or component height/width constraint is set beyond
  each column's own `defaultWidth`/`minWidth`/`maxWidth`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Rows render per `provider.lines`, styled as described in Appearance. |
| Pressed | Not applicable: no distinct pressed-state styling is defined; whatever mouse-down feedback `NSTableView` supplies for an unselected row before a click resolves is unmodified here. |
| Disabled | Not applicable: the component exposes no enabled/disabled toggle and defines no disabled appearance. |
| Focused | Not applicable: no custom focus-ring appearance is set on the table view or its cells; the system default focus ring is unmodified. |
| Loading | Not applicable: the component has no loading indicator or in-flight state; a provider push is reflected synchronously from the view's perspective. |
| Selected | Row is filled with a 4pt-corner-radius rounded rectangle, inset 2pt/1pt, in the theme's `selection` role color (see `selected-row-uses-theme-selection-color`). |
| Empty | When `provider.lines` is empty, the table shows zero rows; the scroll-to-end operation is a no-op; and, per `empty-table-counts-as-at-bottom`, a subsequent append on a previously empty log follows the tail. |

## Accessibility

- Role/trait: The component adds no custom `NSAccessibility` conformance or
  role override; VoiceOver sees AppKit's built-in table accessibility
  hierarchy (table, then row, then cell) unmodified.
- Label requirements: Each cell's accessible value is its own displayed
  text, which AppKit exposes automatically as the text field's accessibility
  value; column headers get their accessible name from the caller-supplied,
  required `LogColumn.title`. No cell or column is left without a label.
- Minimum tap target: Not applicable. This is a pointer-driven macOS
  control, not a touch surface; row height is left to AppKit's system
  default for `rowSizeStyle: .default`, and no explicit width or height is
  set on the table, its columns, or its cells.
- Contrast: Not applicable at this component's level. The component fixes
  no numeric color value itself — it selects semantic theme roles
  (`.windowBackground`, `.divider`, `.selection`, and `ThemedLabel`'s
  default `.primaryText`) whose concrete colors, and therefore their
  contrast ratios, are resolved by the active theme palette at runtime.
  Meeting a contrast standard is that palette's responsibility, not
  something decidable from this file.
- Keyboard operability: The per-column `onClick`/`onDoubleClick` hooks are
  wired only to the table's mouse click and double-click actions
  (`tableClicked`/`tableDoubleClicked`, both driven by `NSTableView`'s
  `target`/`action`/`doubleAction`); no key-event handler calls
  `dispatchClick(columnIndex:row:kind:)`, so a keyboard-only or
  switch-control user who selects a row with the keyboard has no way to
  trigger that row's column click hook.

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
| log-view-015 | cell-request-uses-column-reuse-identifier | Render two different rows under the same column, capturing the identifier passed to `makeView(withIdentifier:owner:)` for each. | Both renders request the view using the same reuse identifier, scoped to that column's id. |
| log-view-016 | cell-text-not-selectable | Inspect a rendered cell's text field. | `isSelectable == false`. |
| log-view-017 | selected-row-uses-theme-selection-color | Select a row and inspect its row view's drawn selection. | A rounded rectangle (4pt radius, inset 2pt/1pt) is filled with the theme's selection color. |
| log-view-018 | selection-fill-reflects-current-theme | Select a row, change the active theme's `selection` role color, then trigger a redraw of that row (for example, by re-requesting its row view via the delegate callback). | The row's drawn selection fill uses the new theme's `selection` color, not the color in effect when the row was first drawn. |
| log-view-019 | single-click-dispatches-column-hook | Single-click a valid cell whose column has an `onClick` hook. | The hook is invoked once with the clicked line. |
| log-view-020 | double-click-dispatches-column-hook | Double-click a valid cell whose column has an `onDoubleClick` hook. | The hook is invoked once with the clicked line. |
| log-view-021 | click-outside-valid-cell-is-inert | Dispatch a click with a negative column index, then with a negative row index, then with a row index at `provider.lines.count`. | No hook is invoked in any of the three cases. |
| log-view-022 | public-dispatch-applies-same-guards | Call the click-dispatch method directly with a valid column index, row, and kind, without any AppKit mouse event; then call it again with an out-of-range row. | The matching column hook is invoked exactly as it would be from a real click for the valid call, and no hook is invoked for the out-of-range call. |
| log-view-023 | reloads-on-every-provider-change | Trigger an appended, then a replaced, then a cleared change. | The table's data is reloaded after each of the three notifications. |
| log-view-024 | append-follows-tail-only-if-already-at-bottom | With `followTail == true` and, before the change, `documentView.bounds.height - documentVisibleRect.maxY <= 2`, trigger an appended change. | The view scrolls to the new last row after the reload. |
| log-view-025 | append-follows-tail-only-if-already-at-bottom | With `followTail == true` and, before the change, `documentView.bounds.height - documentVisibleRect.maxY > 2`, trigger an appended change. | The view does not scroll; the pre-change scroll position is preserved. |
| log-view-026 | replace-follows-tail-unconditionally | With `followTail == true` and the view scrolled away from the bottom, trigger a replaced change. | The view scrolls to the new last row after the reload. |
| log-view-027 | clear-never-follows-tail | With `followTail == true`, trigger a cleared change. | The view does not scroll to the end; the table shows zero rows. |
| log-view-028 | follow-tail-is-mutable-and-effective | Set `followTail = false`, then trigger an appended change while scrolled to the bottom. | The view does not auto-scroll for that change. |
| log-view-029 | scroll-to-end-no-ops-when-empty | Call the scroll-to-end operation on a view whose provider has zero lines. | No scroll occurs and no error or crash results. |
| log-view-030 | reload-is-public-and-unconditional | Call the public reload operation with no preceding provider change. | The table's data is reloaded. |
| log-view-031 | coder-init-unavailable | Attempt to construct the view via `NSCoder`-based decoding (for example, from a storyboard or XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |
| log-view-032 | empty-table-counts-as-at-bottom | With a provider holding zero lines and `followTail == true`, trigger an appended change adding the first line. | The view scrolls to that new line after the reload, since the pre-append empty state counts as at-bottom. |

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
  mutation and every view update this component performs is serialized onto
  the main actor; Swift's actor isolation is the entirety of the concurrency
  handling, with no additional locking or queuing.
- **Error states**: `LogView` performs no I/O, network, or asynchronous
  operation of its own, so it has no failure mode to report. It has no
  validation of the `LogLine`/`LogColumn` values it is handed beyond the
  guards already covered above (`missing-cell-value-renders-empty`,
  `click-outside-valid-cell-is-inert`); malformed input from a
  misbehaving provider is not specially detected or reported.
- **Offline/disconnected state**: Not applicable. The component makes no
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

Not applicable: the component contains no URL-scheme or route handling.

## Localization

Not applicable: the component defines no string literal of its own. All
user-visible text — column titles and cell values — originates from the
caller-supplied `LogProvider`/`LogColumn`, whose localization is that
caller's responsibility, not this component's.

## Accessibility Options

- **Reduce Motion**: Not applicable. The component calls the
  scroll-to-visible operation directly, with no animation context or
  animator proxy wrapping it, so there is no motion effect to suppress.
- **Increase Contrast**: Not applicable at this component's level. Colors
  are drawn entirely from semantic theme roles; neither this component nor
  the themed view types it uses branch on an increase-contrast accessibility
  setting, so any such adaptation would live in the theme/palette system,
  not here.
- **color-only-selection-cue**: The selected row is conveyed by a background color fill alone (`selected-row-uses-theme-selection-color`) with no additional shape, border, or icon; the component does not respond to Differentiate Without Color.

## Feature Flags

Not applicable: the component contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: the component contains no analytics or event-tracking
calls.

## Privacy

- **Data collected**: None collected by this component itself. It only
  renders whatever `LogLine`s the provider already holds, including each
  line's opaque `context` payload, which `LogView` never reads itself — it
  only forwards the whole line to a column's click hooks.
- **Storage**: None. The component writes nothing to disk or
  `UserDefaults`.
- **Transmission**: None. The component makes no network calls.
- **Retention**: Determined entirely by the provider. `LogView` keeps no
  copy of the data beyond what it reads from `provider.lines` at render
  time; any row-count cap (`maxLines`) is the provider's own concern, not
  this component's.

## Logging

Not applicable: the component contains no `os_log`, `Logger`, or other
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

**Decision**: Fill the table with the `.windowBackground` theme role rather
than `.surface`.
**Rationale**: source comments state the log should read as the full
content of its own window or pane, rather than as a sidebar, matching how a
related timeline's table is themed — so it blends into the backdrop instead
of reading as its own plane.
**Approved**: pending.

**Decision**: Turn off alternating row background colors and rely on a
horizontal-only grid line for row separation instead of banding.
**Rationale**: source comments state banding comes from a system color pair
the theme has no say in, and that without any row separator the log read as
an unbroken block of text with no row boundaries at all — the horizontal
grid line is the theme-controlled substitute.
**Approved**: pending.

**Decision**: Capture `provider.columns` once, at `init(provider:)`, and
never rebuild the table's column set afterward.
**Rationale**: the provider's own documentation states columns are expected
to be stable for the lifetime of the provider and that this component
captures them at init time; later column changes are out of contract.
**Approved**: pending.

**Decision**: Compute the scroll-position check before calling reload on an
appended change, rather than after.
**Rationale**: the tail-follow decision needs the scroll position as it was
before new rows were inserted — checking after the reload would measure
geometry that already includes the newly appended rows, which would always
read as "not at bottom" whenever new content is what pushed the content
taller than the viewport.
**Approved**: pending.

**Decision**: Return a newly constructed row view on every delegate
callback instead of reusing a dequeued instance by identifier.
**Rationale**: source comments state each row needs to own its own theme
observer, since a selection fill baked in at creation would draw stale after
a theme change if the instance were pooled and reused across it; AppKit
still recycles the row views this method returns internally regardless of
whether the caller dequeues them itself. This is the mechanism behind
`selection-fill-reflects-current-theme`.
**Approved**: pending.

**Decision**: Request cell views through `makeView(withIdentifier:owner:)`
with a per-column reuse identifier (`cell.<columnID>`), rather than always
constructing a new `ThemedLabel` for every rendered row.
**Rationale**: source code routes every cell request through AppKit's own
view-reuse pool keyed by that identifier, so a cached view is served back
when one is available; this is the mechanism behind
`cell-request-uses-column-reuse-identifier`.
**Approved**: pending.

**Decision**: Route click hooks only through the table's own click/double-click
actions, and expose the click-dispatch method publicly.
**Rationale**: source comments state this lets tests (and callers doing
programmatic dispatch) drive the same entry point AppKit uses, without
needing to synthesize real mouse events. This is why
`public-dispatch-applies-same-guards` is stated as a MUST rather than left
as an API-visibility note.
**Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |

`screen-reader-support` and `no-hardcoded-strings` pass because the source
adds no custom accessibility overrides that would break AppKit's default
table/row/cell hierarchy and defines no string literal of its own;
`keyboard-navigable` is partial because row selection is keyboard-operable
but the click-dispatch hooks are pointer-only (see Accessibility: Keyboard
operability); `dynamic-type-support` and `contrast-ratio` are partial because
both depend on `ThemedLabel` and the active theme palette, which this file
does not control or expose.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: inlined a minimal LogProvider/LogColumn/LogLine/ThemedLabel contract in Overview; restated two implementation-detail requirements (`selection-fill-reflects-current-theme`, `cell-request-uses-column-reuse-identifier`) as observable behavior and moved their mechanism into Design Decisions; restated `dispatch-click-public-test-entry` as the MUST `public-dispatch-applies-same-guards`; removed source-narrative phrasing outside Design Decisions; moved the guidelines reference from `references` to `related`; reformatted Design Decisions to the bold three-line form; shortened the frontmatter summary; filled in the Compliance table; renumbered the `log-view-024b` test vector and added vectors for the reuse-identifier and empty-table-at-bottom requirements; defined the "within 2 points of the bottom" geometry precisely; and added the `empty-table-counts-as-at-bottom` requirement promoted from the States table. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
