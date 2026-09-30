<!-- leaf: implement-general-1/crud-record-form--part-2 · source: crud-record-form.md -->

# CrudRecordForm — continued (part 2)

## Platform Notes

- **React / Web (TypeScript):** `packages/web/packages/crud/src/CrudRecordForm.tsx`,
  exported from `@agentic-toolkit/crud`. Composes the shared `Field`, `Button`,
  `useAction` (from `@agenticdevelopertoolkit/ui`) and the package-local `CrudFieldInput` +
  `ErrorText`. Note it lives in `@agentic-toolkit/crud`, not `@agenticdevelopertoolkit/ui`.
- The pure metadata→payload helpers are exported for reuse/testing: `writableColumns`,
  `toDraft`, `buildPayload`, plus the `CrudDraft` / `CrudFormMode` types.
- Metadata comes from `src/generated/table-metadata.ts` (backend OpenAPI →
  `gen_table_metadata.py`); `onSubmit` typically maps to `useCrudResource`'s
  `create`/`update`.
- Demo: `ui-showcase` Topic `crud-record-form` (static `meta`; logs the payload).
- First consumer: the `/all-data` generic table editor (`AllDataPane`).
- **Responsive:** Fields stack in a single column; verify at 375 / 768 / 1440 via
  Playwright.
- **SwiftUI / Compose:** No native implementation in this repo; the same
  `CrudTableMeta`-driven mapping would render `Picker` (SwiftUI) /
  `DropdownMenu` (Compose) for enum columns, `Toggle` / `Switch` for booleans, a
  multi-line `TextEditor` / `OutlinedTextField` for JSON columns, and
  `TextField` / `OutlinedTextField` for everything else, following the same
  required/`serverManaged`/`createOnly` rules above.
- **AppKit / UIKit:** No native implementation in this repo; the same mapping
  would render `NSPopUpButton` / `UIPickerView` for enum columns, `NSSwitch` /
  `UISwitch` for booleans, a plain multi-line text view for JSON columns, and
  `NSTextField` / `UITextField` for everything else, following the same
  required/`serverManaged`/`createOnly` rules above.
- **WinUI 3:** No native implementation in this repo; the same mapping would
  render `ComboBox` for enum columns, `ToggleSwitch` for booleans, a multi-line
  `TextBox` for JSON columns, and `TextBox` for everything else, following the
  same required/`serverManaged`/`createOnly` rules above.

## Design Decisions

**Decision**: Fields are generated from `CrudTableMeta`, not hand-authored.
**Rationale**: one form serves every generic-CRUD table; new tables need no new
form code.
**Approved**: pending

**Decision**: `serverManaged` columns are skipped; `createOnly` columns are
disabled + stripped on edit.
**Rationale**: the form only ever offers what the backend will actually accept,
so a save can't silently no-op.
**Approved**: pending

**Decision**: Untouched optional fields are omitted on create rather than sent
as empty.
**Rationale**: the backend OpenAPI spec (surfaced via `gen_table_metadata.py`)
carries no column defaults, so sending `''`/`false` would override a DB
default; omission lets the backend default win.
**Approved**: pending

**Decision**: Validation throws field-named errors surfaced inline via
`useAction`.
**Rationale**: the message names the offending column and the draft is
retained, so the fix is obvious and non-destructive.
**Approved**: pending

**Decision**: Object/array/unknown columns use a JSON textarea and round-trip
via `JSON.parse`/`stringify`.
**Rationale**: jsonb columns must survive edit without a plain-text path
corrupting an object to "[object Object]".
**Approved**: pending

**Decision**: The draft is a flat text/boolean buffer coerced only at submit.
**Rationale**: controls stay simple (all text/checkbox), and type coercion +
validation live in one place (`buildPayload`).
**Approved**: pending

**Decision**: Create vs. edit mode is inferred from whether `initial` is
supplied (`mode = initial ? 'edit' : 'create'`), with no separate mode prop.
**Rationale**: a single source of truth for mode rules out a caller passing a
row and a conflicting mode flag out of sync with each other.
**Approved**: pending
