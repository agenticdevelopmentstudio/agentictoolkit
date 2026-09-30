<!-- leaf: implement-general-1/crud-table--logging · source: crud-table.md -->

# CrudTable

## Logging

No logging. `CrudTable` is presentational; the caller's `onNew`/`onEdit`/`onDelete`
handlers (and `useCrudResource`) own any telemetry or error reporting.
