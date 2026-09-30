<!-- leaf: implement-general-view-2/log-view · source: log-view.md -->

**Rules** (cite as `implement-general-view-2/log-view#<slug>`):

- `embeds-table-in-full-bleed-scroll-view` MUST
- `vertical-only-scrolling` MUST
- `columns-built-once-from-provider` MUST
- `column-layout-fixed-after-init` MUST
- `columns-user-resizable-uniform` MUST
- `horizontal-grid-lines-only` MUST
- `row-count-matches-provider` MUST
- `renders-initial-lines-at-init` MUST
- `plain-cell-value-rendering` MUST
- `attributed-cell-value-rendering` MUST
- `missing-cell-value-renders-empty` MUST
- `cell-alignment-follows-column` MUST
- `cell-text-truncates-tail` MUST
- `cell-tooltip-mirrors-display-text` MUST
- `cell-request-uses-column-reuse-identifier` MUST
- `cell-text-not-selectable` MUST
- `selected-row-uses-theme-selection-color` MUST
- `selection-fill-reflects-current-theme` MUST
- `single-click-dispatches-column-hook` MUST
- `double-click-dispatches-column-hook` MUST
- `click-outside-valid-cell-is-inert` MUST
- `public-dispatch-applies-same-guards` MUST
- `reloads-on-every-provider-change` MUST
- `append-follows-tail-only-if-already-at-bottom` MUST
- `empty-table-counts-as-at-bottom` MUST
- `replace-follows-tail-unconditionally` MUST
- `clear-never-follows-tail` MUST
- `follow-tail-is-mutable-and-effective` MUST
- `scroll-to-end-no-ops-when-empty` MUST
- `reload-is-public-and-unconditional` MUST
- `coder-init-unavailable` MUST

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

