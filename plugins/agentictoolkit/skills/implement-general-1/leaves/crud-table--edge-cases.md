<!-- leaf: implement-general-1/crud-table--edge-cases · source: crud-table.md -->

# CrudTable

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
