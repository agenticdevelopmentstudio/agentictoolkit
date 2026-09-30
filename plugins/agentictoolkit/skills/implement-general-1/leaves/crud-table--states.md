<!-- leaf: implement-general-1/crud-table--states · source: crud-table.md -->

# CrudTable

## States

| State | Appearance change |
|---|---|
| Loading | count reads "Loading…"; body is a centered `Spinner` |
| Error | `ErrorText` line under the header |
| Empty (0 rows, no error) | "No rows yet." centered placeholder, no table |
| Populated | count ("N rows"); table of PK+scalar columns with per-row Edit/Delete |
| Row value null | cell shows `—` |
| Cell text > 80 chars | truncated with a trailing `…` |
