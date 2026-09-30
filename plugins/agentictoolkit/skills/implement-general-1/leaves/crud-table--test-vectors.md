<!-- leaf: implement-general-1/crud-table--test-vectors · source: crud-table.md -->

# CrudTable

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
