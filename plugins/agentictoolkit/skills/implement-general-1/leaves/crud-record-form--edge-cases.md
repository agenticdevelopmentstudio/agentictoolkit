<!-- leaf: implement-general-1/crud-record-form--edge-cases · source: crud-record-form.md -->

# CrudRecordForm

## Edge Cases

- Create vs edit is inferred purely from `initial` (absent = create). No mode prop.
- Untouched create checkbox: stays `undefined` and is omitted so a default-true DB
  column isn't silently forced to `false`; a required boolean instead sends `false`.
- Edit clearing an optional field: nullable columns send `null`, plain (non-enum)
  strings send `''`; other types can't represent "cleared", so the column is
  omitted (its old value survives — the honest option for a partial PUT).
- `createOnly` columns (client-supplied `rdid`s — a caller-chosen identifier,
  e.g. a slug, rather than a server-generated one): rendered disabled on edit
  and stripped from the PUT payload before any required-validation runs.
- `1e999` in a number field: rejected (`Number.isFinite` is false) rather than
  silently serialized to `null`.
- A validation throw (required/number/JSON) surfaces inline via `useAction`'s error
  and leaves the draft intact so the user can fix and resubmit.
- Object/array/unknown columns round-trip as JSON text (pretty-printed when seeded);
  `unknown` is treated as JSON because the backend OpenAPI spec (surfaced via
  `gen_table_metadata.py`) types jsonb columns that way.
