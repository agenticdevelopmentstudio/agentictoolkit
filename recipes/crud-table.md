---
id: ec64b22b-8a25-431d-8866-b7a01acd91fe
title: CrudTable
domain: agentictoolkit://recipes/crud-table
type: ingredient
version: 1.2.1
status: review
language: en
created: '2026-07-03'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Metadata-driven row list from @agentic-toolkit/crud: renders a table's PK + scalar columns from its CrudTableMeta, with per-row Edit/Delete and a New action."
platforms:
- typescript
- web
tags:
- crud
- table
- metadata
- list
depends-on: []
related:
- agentictoolkit://recipes/crud-record-form
references: []
---

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

## States

| State | Appearance change |
|---|---|
| Loading | count reads "Loading…"; body is a centered `Spinner` |
| Error | `ErrorText` line under the header |
| Empty (0 rows, no error) | "No rows yet." centered placeholder, no table |
| Populated | count ("N rows"); table of PK+scalar columns with per-row Edit/Delete |
| Row value null | cell shows `—` |
| Cell text > 80 chars | truncated with a trailing `…` |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | render-pk-then-scalar-columns, cap-columns | meta with 2 pk + 8 scalars + 1 object column | Headers = the 2 pk columns then 4 scalars (6 total); the object column absent |
| T2 | header-columns-by-name | column `name: "createdAt"` | Header cell text is "createdAt" |
| T3 | format-null-cells | row `{ status: null }` | That cell renders `—` |
| T4 | stringify-non-string-cells | row `{ count: 3 }` | Cell renders "3" (JSON form) |
| T5 | truncate-long-cells | a 200-char string cell | Cell shows first 80 chars + `…` |
| T6 | show-loading-state | `loading=true` | Spinner in body; count reads "Loading…" |
| T7 | show-error | `error="Boom"` | "Boom" shown via `ErrorText` |
| T8 | show-empty-state | `rows=[]`, `error=null`, `loading=false` | "No rows yet." shown; no table |
| T9 | offer-new-action | Click "New" | `onNew` called |
| T10 | offer-per-row-edit-delete | Click Edit / Delete on a row | `onEdit(row)` / `onDelete(row)` called with that row |
| T11 | show-row-count | `rows.length === 1` | Count reads "1 row" (singular) |
| T12 | show-row-count | `rows.length === 3` | Count reads "3 rows" (plural) |
| T13 | show-row-count, show-empty-state | `rows=[]`, `error=null`, `loading=false` | Header count reads "0 rows" while the body shows "No rows yet." |
| T14 | body-precedence | `loading=true`, `error="Boom"`, `rows` non-empty | Spinner shown in the body AND the `ErrorText` "Boom" line shown above it |
| T15 | retain-rows-on-error | `error="Boom"`, `rows` non-empty | The existing rows still render as a table; no empty placeholder |
| T16 | cap-columns | meta with 8 pk columns and 0 scalars | Only the first 6 pk columns (metadata order) render; no scalar column appears |
| T17 | composite-row-key | `pkParams: ['orgId', 'userId']`, row `{ orgId: 'a/b', userId: 'c' }` | Row key is `"a%2Fb/c"` |
| T18 | composite-row-key | `pkParams: []` | Row key falls back to the row's array index |
| T19 | offer-per-row-edit-delete | Click Delete | `onDelete(row)` is called directly, with no confirmation dialog rendered by `CrudTable` |
| T20 | label-row-actions-header | header row | The trailing actions `<th>` carries `aria-label="Row actions"` and no visible text |
| T21 | truncate-long-cells | a cell value exactly 80 characters long | Cell shows all 80 characters with no trailing `…` |
| T22 | render-pk-then-scalar-columns, cap-columns, format-null-cells, stringify-non-string-cells, truncate-long-cells | import `{ displayColumns, cellText }` directly from the module | Both are callable as pure functions, independent of rendering `CrudTable` |

## Edge Cases

- A table whose only columns are the primary key still renders (PK columns are
  never filtered out by type).
- Composite primary keys: see **composite-row-key**.
- `object`/`array` columns never appear in the list (they are edited only in the
  record form); a table dominated by such columns may show only its PK.
- More than six eligible columns: see **cap-columns** — the combined PK+scalar
  list is capped at six regardless of how many are PK columns, so a table with
  more than six PK columns loses some of its own PK columns, not just scalars;
  every excluded column is still reachable via the record form.
- Error alongside stale rows: see **retain-rows-on-error** and
  **body-precedence**.
- A very long cell is truncated for display only; the full value is unchanged in the
  row data and editable in the form.

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

## Logging

No logging. `CrudTable` is presentational; the caller's `onNew`/`onEdit`/`onDelete`
handlers (and `useCrudResource`) own any telemetry or error reporting.

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

## Design Decisions

**Decision**: Columns are metadata-driven, not hand-authored: `displayColumns(meta)`
derives the column list (PK first, then scalars) from the table's `CrudTableMeta`
descriptor rather than per-table code.
**Rationale**: One list works for any generic-CRUD table; a new table needs no new UI.
**Approved**: pending

**Decision**: Columns are PK-first, scalar-only, and capped at six: primary keys lead
because they identify the row, object/array columns are excluded because they don't
render usefully in a cell (they're form-only), and the combined list is capped at six.
**Rationale**: Keeps the row scannable at a glance, with full detail available in the
record form.
**Approved**: pending

**Decision**: The table is placeholder-grade: no sorting, search, or pagination.
**Rationale**: The backend caps lists at 500 rows, so a plain table suffices; ship the
simplest thing that works and defer richer table behavior until a real need
(optimize-for-change).
**Approved**: pending

**Decision**: `CrudTable` owns no state or data-fetching: `rows`, `loading`, `error`,
and the action callbacks are all props.
**Rationale**: The same list can be driven by `useCrudResource` or by static demo data,
and stays trivial to test.
**Approved**: pending

**Decision**: `cellText` truncates for display only: an 80-character cap with a
trailing `…` keeps rows scannable without mutating the underlying data.
**Rationale**: Long JSON/text values don't blow out the layout, and the full value
survives for editing.
**Approved**: pending

## Compliance

| Check | Status | Category |
|---|---|---|
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | passed | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`semantic-markup`, `screen-reader-support`, and `keyboard-navigable` rest on the real
`<table>`/`<thead>`/`<tbody>`/`<th>` markup, the `aria-label="Row actions"` header, and
the real, focusable `<button>` elements with visible text labels (`CrudTable.tsx`);
`dynamic-type-support` rests on the component's text sizing using `rem`-based Tailwind
classes (`text-sm`, `text-[0.7rem]`, `text-xs`) rather than fixed pixel sizes;
`contrast-ratio` is partial because the source only names `apt-*` theme tokens
(`text-apt-text`, `text-apt-text-dim`, `text-apt-border`) without the underlying color
values, so the actual ratios can't be confirmed from this file; `no-hardcoded-strings`
is failed because `New`, `Edit`, `Delete`, `Loading…`, `No rows yet.`, and the
row-count text ("N row"/"N rows") are all literal, unwrapped English strings in
`CrudTable.tsx`.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-23 | Mike Fullerton | Lint pass: relinked Compliance to real catalog checks (Accessibility + Internationalization) and dropped two checks with no catalog equivalent; reformatted Design Decisions to the Decision/Rationale/Approved form; gave Platform Notes all five platform bullets (generic guidance for SwiftUI/Compose/AppKit-UIKit/WinUI 3) and corrected the source file path and metadata-generator path; added body-precedence, composite-row-key, retain-rows-on-error, and label-row-actions-header requirements with test vectors, plus vectors for the empty-state row count and the 80-character truncation boundary; clarified that the column cap can drop excess primary-key columns, not just scalars; dropped the unsupported "live" claim about the row count; and stated that delete confirmation is the caller's responsibility in `onDelete`; records the unverified theme-token contrast as an open question. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Renamed every requirement to subject-only kebab-case, dropping the old prefix everywhere it is cited. |
| 1.0.0 | 2026-07-03 | Mike Fullerton | Initial recipe; documents the metadata-driven CrudTable from @adh-shared/crud. |
| 1.2.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
