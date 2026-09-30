<!-- leaf: implement-general-1/crud-table · source: crud-table.md -->

**Rules** (cite as `implement-general-1/crud-table#<slug>`):

- `render-pk-then-scalar-columns` MUST
- `cap-columns` MUST
- `header-columns-by-name` MUST
- `label-row-actions-header` MUST
- `format-null-cells` MUST
- `stringify-non-string-cells` MUST
- `truncate-long-cells` MUST
- `show-loading-state` MUST
- `show-error` MUST
- `show-empty-state` MUST
- `offer-new-action` MUST
- `offer-per-row-edit-delete` MUST
- `show-row-count` MUST
- `body-precedence` MUST
- `composite-row-key` MUST
- `retain-rows-on-error` MUST

# CrudTable

## Overview

`CrudTable` in `@agentic-toolkit/crud` is a **metadata-driven** row list for one
generic-CRUD table. Given a `CrudTableMeta` (generated from the backend OpenAPI
spec) plus the current `rows`, it renders a plain table whose columns are chosen
from the metadata: the primary-key column(s) first, then the remaining **scalar**
columns (object/array columns are form-only), capped at six. Each row carries
per-row **Edit** and **Delete** ghost buttons, and a header **New** action sits
above the table beside a row count.

It is a **placeholder-grade** list — no sorting, search, or pagination (the
backend caps lists at 500 rows) — used by the `/all-data` generic table browser
and any admin surface that needs a quick, uniform view of one table. It owns no
data-fetching or state: the caller supplies `rows`, `loading`, and `error` (from
`useCrudResource`) and handles the `onNew` / `onEdit` / `onDelete` intents.

## Behavioral Requirements

- **render-pk-then-scalar-columns**: The table MUST render the metadata's
  primary-key column(s) first, followed by the remaining scalar columns, and MUST
  omit `object` and `array` columns (they are form-only).
- **cap-columns**: The table MUST render at most six columns, taken from the
  combined PK-then-scalar list in metadata column order. Scalars survive the
  cap in the order they appear in `meta.columns`. The cap applies to the
  combined list, not to scalars alone: when there are more than six PK
  columns, only the first six (in metadata order) render and no scalar column
  appears at all — PK columns are not exempt from the cap.
- **header-columns-by-name**: Each column header MUST show the column's `name`
  exactly as served by the API.
- **label-row-actions-header**: The trailing per-row actions column header
  MUST carry `aria-label="Row actions"` and render no visible text.
- **format-null-cells**: A cell whose value is `null`/`undefined` MUST render
  as an em dash (`—`).
- **stringify-non-string-cells**: A non-string cell value MUST render as its
  JSON string form.
- **truncate-long-cells**: A rendered cell longer than 80 characters MUST be
  truncated with a trailing ellipsis (`…`).
- **show-loading-state**: While `loading` is true, the table body MUST show a
  spinner and the count MUST read "Loading…" instead of the row table.
- **show-error**: When `error` is non-null, the table MUST surface the error
  message.
- **show-empty-state**: When there are zero rows and no error (and not
  loading), the table MUST show a "No rows yet." placeholder instead of a table.
- **offer-new-action**: The header MUST render a New button that invokes
  `onNew` when activated.
- **offer-per-row-edit-delete**: Every data row MUST render Edit and Delete
  actions that invoke `onEdit(row)` / `onDelete(row)` with that row.
  `CrudTable` MUST NOT confirm before calling `onDelete`: confirming (or not)
  is the caller's job inside its `onDelete` handler, so implementers don't
  add a second, bespoke confirmation dialog.
- **show-row-count**: When not loading, the header MUST show the row count,
  correctly singularized ("1 row" vs "N rows"), including "0 rows" while the
  empty-state placeholder is showing.
- **body-precedence**: When more than one state applies at once, the table
  body MUST resolve them in this order: the loading spinner (`loading` true,
  regardless of `error` or `rows`); otherwise the empty placeholder (`rows`
  is empty AND `error` is falsy); otherwise the row table. The error line
  renders independently above the body whenever `error` is truthy, so it MAY
  appear alongside the spinner or alongside a populated table.
- **composite-row-key**: Each rendered row's key MUST be `rowKey(meta, row)`:
  every `pkParams` value coerced to a string (`''` for `null`/`undefined`),
  percent-encoded, and joined with `/` in `pkParams` order. The row's array
  index is used only when that computed key is the empty string (for example,
  when `pkParams` is empty).
- **retain-rows-on-error**: When `error` is set but `rows` is non-empty (a
  failed background refresh after a prior successful load), the table MUST
  keep showing the existing rows; the empty placeholder MUST NOT replace them
  merely because `error` is set.

## Appearance

```
┌──────────────────────────────────────────────────────────────┐
│ 12 rows                                              [ New ]   │
│ (error line, when error != null)                              │
├──────────────────────────────────────────────────────────────┤
│  id        name         status      …            (actions)    │
│ ─────────────────────────────────────────────────────────────│
│  ab12…      Ada          active            [ Edit ] [ Delete ]│
│  cd34…      Grace        —                 [ Edit ] [ Delete ]│
└──────────────────────────────────────────────────────────────┘
     loading → centered Spinner ·  empty → "No rows yet."
```

- Outer: `flex min-w-0 flex-col gap-3`. Header row: `flex items-center
  justify-between gap-2` with a `font-mono text-[0.7rem] text-apt-text-dim` count
  on the left and a `size="sm"` primary `Button` ("New") on the right.
- Table: wrapped in `overflow-x-auto rounded-lg border border-apt-border`;
  `w-full text-left text-sm`. Header cells use the shared `fieldCaptionClass` +
  `px-3 py-2 font-medium`; body cells `px-3 py-2 text-apt-text`; row separators
  `border-b border-apt-border/50`.
- Actions cell: right-aligned, `whitespace-nowrap`, two `variant="ghost"
  size="sm"` buttons (Edit, Delete).
- No raw hex; no `!important` (all color via `apt-*` tokens).

## Accessibility

- Renders a semantic `<table>` with a `<thead>`/`<tbody>`; header cells are `<th>`.
- The trailing per-row actions column header is empty visually but carries
  `aria-label="Row actions"` so it is named for assistive tech.
- Edit / Delete / New are real, focusable `<button>`s (the shared `Button`) with
  visible text labels and keyboard activation.
- The count line ("N rows" / "Loading…") gives sighted and AT users a sense
  of table size. It is plain text with no `aria-live` region, so an assistive
  technology user does not get an automatic announcement when it changes.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The header, cell, and muted caption text color resolves from the active theme's apt-* text token roles against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file. This would be settled by a theme-level contrast audit of apt-* text tokens against the backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `meta` | `CrudTableMeta` | — | The generated table descriptor; drives which columns render. |
| `rows` | `CrudRow[]` | — | The current rows to display (already fetched by the caller). |
| `loading` | `boolean` | — | Show the spinner + "Loading…" count. |
| `error` | `string \| null` | — | Error message to surface (null = none). |
| `onNew` | `() => void` | — | Invoked by the header New button. |
| `onEdit` | `(row: CrudRow) => void` | — | Invoked by a row's Edit button. |
| `onDelete` | `(row: CrudRow) => void` | — | Invoked by a row's Delete button. |

Two pure helpers are also exported for reuse/testing: `displayColumns(meta)` (the
PK-first, scalar-only, capped column list) and `cellText(row, column)` (the em
dash / JSON-stringify / 80-char-truncate cell formatter).

## Platform Notes

- **React / Web (TypeScript, source):** `packages/web/packages/crud/src/CrudTable.tsx`,
  exported from `@agentic-toolkit/crud`. Built from the shared `Button`, `Spinner`, and
  the package-local `ErrorText`; typography from `@agenticdevelopertoolkit/ui/lib/typography`
  (`fieldCaptionClass`). Note it lives in `@agentic-toolkit/crud`, not
  `@agenticdevelopertoolkit/ui`. Metadata comes from `src/generated/table-metadata.ts`,
  emitted by `packages/web/packages/adh-api-types/tools/gen_table_metadata.py` from the
  backend OpenAPI spec; `rows`/`loading`/`error` are typically supplied by
  `useCrudResource(meta)`. Demo: `ui-showcase` Topic `crud-table` (feeds a static `meta` +
  local `rows`). **Responsive:** the table is wrapped in `overflow-x-auto`, so it scrolls
  horizontally rather than overflowing the page on narrow viewports; verify at
  375 / 768 / 1440 via Playwright.
- **SwiftUI**: No native implementation exists (this is a web-sourced component). The
  equivalent would use a `Table` (macOS 13+ / iOS 16+) or a `List` of custom rows, one
  `TableColumn` (or `HStack` cell) per entry from `displayColumns`, a header
  `Button("New")`, per-row `Button("Edit")` / `Button("Delete")`, a `ProgressView` for
  the loading state, and a `ContentUnavailableView` for the empty state.
- **Compose**: No native implementation exists. The equivalent would use a `LazyColumn`
  with a header `Row` of column names and one data `Row` per record (each cell a
  `Text`), a `TextButton`/`IconButton` pair per row for Edit/Delete, a
  `CircularProgressIndicator` for the loading state, and a centered `Text` for the empty
  state.
- **AppKit / UIKit**: No native implementation exists. On AppKit the equivalent is an
  `NSTableView` with one `NSTableColumn` per entry from `displayColumns`, an
  `NSProgressIndicator` for the loading state, and a custom cell view whose trailing
  `NSButton`s call the Edit/Delete callbacks. UIKit has no direct multi-column table
  control, so the closest equivalent is a `UICollectionView` with a compositional
  layout (or a `UITableView` cell that stacks the scalar columns as labels) plus
  trailing swipe actions or accessory buttons for Edit/Delete.
- **WinUI 3**: No native implementation exists. The equivalent uses the Community
  Toolkit `DataGrid` (or a `ListView` with a `GridView`-style `ItemTemplate`), one
  column/cell per entry from `displayColumns`, a `ProgressRing` for the loading state,
  and per-row `Button`s in the row template for Edit/Delete.

