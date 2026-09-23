---
id: ec64b22b-8a25-431d-8866-b7a01acd91fe
title: CrudTable
domain: agentictoolkit://recipes/crud-table
type: ingredient
version: 1.0.0
status: draft
language: en
created: '2026-07-03'
modified: '2026-07-03'
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
above the table beside a live row count.

It is a **placeholder-grade** list — no sorting, search, or pagination (the
backend caps lists at 500 rows) — used by the `/all-data` generic table browser
and any admin surface that needs a quick, uniform view of one table. It owns no
data-fetching or state: the caller supplies `rows`, `loading`, and `error` (from
`useCrudResource`) and handles the `onNew` / `onEdit` / `onDelete` intents.

## Behavioral Requirements

- **must-render-pk-then-scalar-columns**: The table MUST render the metadata's
  primary-key column(s) first, followed by the remaining scalar columns, and MUST
  omit `object` and `array` columns (they are form-only).
- **must-cap-columns**: The table MUST render at most six columns.
- **must-header-columns-by-name**: Each column header MUST show the column's `name`
  exactly as served by the API.
- **must-format-null-cells**: A cell whose value is `null`/`undefined` MUST render
  as an em dash (`—`).
- **must-stringify-non-string-cells**: A non-string cell value MUST render as its
  JSON string form.
- **must-truncate-long-cells**: A rendered cell longer than 80 characters MUST be
  truncated with a trailing ellipsis (`…`).
- **must-show-loading-state**: While `loading` is true, the table body MUST show a
  spinner and the count MUST read "Loading…" instead of the row table.
- **must-show-error**: When `error` is non-null, the table MUST surface the error
  message.
- **must-show-empty-state**: When there are zero rows and no error (and not
  loading), the table MUST show a "No rows yet." placeholder instead of a table.
- **must-offer-new-action**: The header MUST render a New button that invokes
  `onNew` when activated.
- **must-offer-per-row-edit-delete**: Every data row MUST render Edit and Delete
  actions that invoke `onEdit(row)` / `onDelete(row)` with that row.
- **must-show-row-count**: When not loading, the header MUST show the row count,
  correctly singularized ("1 row" vs "N rows").

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
- The count line ("N rows" / "Loading…") gives sighted and AT users a live sense
  of table size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | must-render-pk-then-scalar-columns, must-cap-columns | meta with 2 pk + 8 scalars + 1 object column | Headers = the 2 pk columns then 4 scalars (6 total); the object column absent |
| T2 | must-header-columns-by-name | column `name: "createdAt"` | Header cell text is "createdAt" |
| T3 | must-format-null-cells | row `{ status: null }` | That cell renders `—` |
| T4 | must-stringify-non-string-cells | row `{ count: 3 }` | Cell renders "3" (JSON form) |
| T5 | must-truncate-long-cells | a 200-char string cell | Cell shows first 80 chars + `…` |
| T6 | must-show-loading-state | `loading=true` | Spinner in body; count reads "Loading…" |
| T7 | must-show-error | `error="Boom"` | "Boom" shown via `ErrorText` |
| T8 | must-show-empty-state | `rows=[]`, `error=null`, `loading=false` | "No rows yet." shown; no table |
| T9 | must-offer-new-action | Click "New" | `onNew` called |
| T10 | must-offer-per-row-edit-delete | Click Edit / Delete on a row | `onEdit(row)` / `onDelete(row)` called with that row |
| T11 | must-show-row-count | `rows.length === 1` | Count reads "1 row" (singular) |
| T12 | must-show-row-count | `rows.length === 3` | Count reads "3 rows" (plural) |

## Edge Cases

- A table whose only columns are the primary key still renders (PK columns are
  never filtered out).
- Composite primary keys: all `pkParams` columns lead, in `pkParams` order; the row
  key is their per-part-escaped join (via `rowKey`), falling back to the row index
  when empty.
- `object`/`array` columns never appear in the list (they are edited only in the
  record form); a table dominated by such columns may show only its PK.
- More than six eligible columns: only the first six (PK-first) are shown; the rest
  are reachable via the record form.
- Error alongside stale rows: a failed background refresh surfaces `error` while the
  previously loaded rows stay rendered (the empty placeholder only shows when there
  are genuinely zero rows AND no error).
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

- **React / Web (TypeScript):** `websites/shared/crud/src/CrudTable.tsx`, exported
  from `@agentic-toolkit/crud`. Built from the shared `Button`, `Spinner`, and the
  package-local `ErrorText`; typography from `@agenticdevelopertoolkit/ui/lib/typography`
  (`fieldCaptionClass`). Note it lives in `@agentic-toolkit/crud`, not
  `@agenticdevelopertoolkit/ui`.
- Metadata comes from `src/generated/table-metadata.ts`, emitted by
  `scripts/gen_table_metadata.py` from the backend OpenAPI spec. `rows`/`loading`/
  `error` are typically supplied by `useCrudResource(meta)`.
- Demo: `ui-showcase` Topic `crud-table` (feeds a static `meta` + local `rows`).
- **Responsive:** The table is wrapped in `overflow-x-auto`, so it scrolls
  horizontally rather than overflowing the page on narrow viewports; verify at
  375 / 768 / 1440 via Playwright.
- **SwiftUI / Compose:** Not applicable — web-only shared component.

## Design Decisions

- **Metadata-driven columns, not hand-authored.** The list must work for *any*
  generic-CRUD table without per-table code, so `displayColumns(meta)` derives the
  columns from the descriptor (PK first, scalars next). **Rationale:** one list for
  ~all tables; new tables need no new UI.
- **PK-first, six-column cap, scalars only.** Primary keys identify the row and lead;
  object/array columns don't render usefully in a cell and are form-only; six keeps
  the row scannable. **Rationale:** a readable at-a-glance list, with full detail in
  the record form.
- **Placeholder-grade: no sort/search/pagination.** The backend caps lists at 500
  rows, so a plain table suffices. **Rationale:** ship the simplest thing that
  works; defer richer table behavior until a real need (optimize-for-change).
- **Owns no state or fetching.** `rows`/`loading`/`error` and the action callbacks
  are all props. **Rationale:** the same list can be driven by `useCrudResource` or
  by static demo data, and stays trivial to test.
- **`cellText` truncates for display only.** An 80-char cap with `…` keeps rows
  scannable without mutating the data. **Rationale:** long JSON/text values don't
  blow out the layout, and the full value survives for editing.

## Compliance

| Check | Status | Category |
|---|---|---|
| Artifact formatting (ingredient) | passed | artifact-formatting |
| No raw hex / arbitrary colors / `!important` | passed | project-guidelines UI |
| Components sourced from `@agentic-toolkit` (no bespoke UI) | passed | project-guidelines UI |
| Semantic table + labeled actions column | passed | accessibility |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-07-03 | Mike Fullerton | Initial recipe; documents the metadata-driven CrudTable from @adh-shared/crud. |
