---
id: 3dc693ab-28e4-4624-9b2d-8dc81f81e037
title: CRUD Record Form
domain: agentictoolkit://cookbook/ui/crud/crud-record-form
type: recipe
version: 1.3.0
status: review
language: en
created: '2026-07-03'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Metadata-driven create/edit form for a generic CRUD table: builds one field per writable column from the table's metadata (enum columns become a select, boolean columns become a checkbox), and skips server-managed columns."
platforms:
- typescript
- web
tags:
- crud
- form
- metadata
- validation
ingredients:
- agenticdevelopertoolkit://recipes/field
depends-on: []
related:
- agentictoolkit://cookbook/ui/crud/crud-table
references: []
---

# CRUD Record Form

## Overview

The form is a **metadata-driven** create/edit form for one generic-CRUD
table. From the table's metadata it builds one control per **writable**
column — skipping every server-managed column (ids, timestamps) — picking
the control by column type: enum → a select, boolean → a checkbox,
integer/number → numeric input, object/array/unknown → JSON textarea,
everything else → text input. Each non-boolean control is wrapped in a
shared field wrapper (label + optional "JSON" hint); booleans ride inline
beside their caption.

Absence of an `initial` row means **create**; a supplied `initial` means
**edit**. The form owns a text/boolean **draft** buffer seeded from
`initial` and, on submit, coerces the draft into a typed payload:
required-but-empty fields and malformed numbers/JSON **throw** a
field-named error shown inline; on create, untouched optional fields are
omitted so DB defaults apply; on edit, `createOnly` columns are disabled
and skipped (the backend strips them from the update). Submission runs
through a shared submission-state mechanism, which drives the busy/error
state and disables the buttons while saving.

It powers any surface that creates/edits one CRUD row without
hand-authored fields (see Platform Notes for its first consumer).

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| Field | agenticdevelopertoolkit://recipes/field | Label + optional hint wrapper around each non-boolean control | yes | `label` = `name` (+ ` *` when required); `hint="JSON"` for object/array/unknown columns |

Composed shared primitives without their own recipe domains: the per-type
control picker (rendering a select, checkbox, textarea, or text input
depending on column type), a button pair (Cancel + Save), inline error
text, and the shared submission-state mechanism (busy/error orchestration).
The metadata→payload logic (selecting writable columns, seeding the draft,
and building the submit payload) is exported alongside the component. See
Platform Notes for the exact names of these pieces in the source
implementation.

## Integration Requirements

- **build-fields-from-writable-columns**: The form MUST render one control per
  writable column and MUST NOT render any `serverManaged` column.
- **pick-control-by-type**: The form MUST pick each control from the column
  type — enum → a select, boolean → a checkbox, integer/number → numeric
  input, object/array/unknown → JSON textarea, otherwise text input.
- **wrap-nonboolean-in-field**: The form MUST wrap each non-boolean control in
  a field wrapper labeled with the column name, and MUST render a boolean
  inline beside its caption.
- **mark-required-and-json**: The form MUST append ` *` to a required column's
  label and MUST show a `JSON` hint on object/array/unknown columns.
- **seed-draft-from-initial**: The form MUST seed its draft from `initial` when
  editing (booleans as booleans, JSON columns pretty-printed, others as text) and
  MUST start create fields empty (booleans left unset).
- **reject-empty-required**: On submit, the form MUST block submission and show
  a "`<name>` is required" error when a required column is empty. A required
  **boolean** column is exempt from this check: an untouched one sends `false`
  instead of throwing (see **omit-untouched-optionals-on-create**).
- **validate-numbers**: On submit, a non-finite number MUST be rejected with
  "`<name>` must be a number", and a non-integer in an integer column with
  "`<name>` must be an integer".
- **validate-json**: On submit, an object/array/unknown column whose text is
  not valid JSON MUST be rejected with "`<name>` must be valid JSON".
- **omit-untouched-optionals-on-create**: On create, an empty/untouched
  optional field MUST be omitted from the payload so the backend column default
  applies; an untouched required boolean MUST send `false`.
- **disable-and-skip-create-only-on-edit**: On edit, a `createOnly` column MUST
  be rendered disabled and MUST be excluded from the update payload — stripped
  before required-field validation runs, so an empty, disabled `createOnly`
  column never blocks submission.
- **clear-field-by-type-on-edit**: On edit, clearing an optional field MUST
  send `null` for a nullable column, `''` for a plain (non-enum) string
  column, and MUST omit every other column type from the payload (its prior
  value survives the partial update).
- **run-submit-through-busy-state**: On submit the form MUST call the
  provided submit callback with the payload, disabling Cancel/Save and
  showing "Saving…" while the call is pending, and MUST surface a thrown
  error inline without losing the draft.

## Layout

```
┌ Form (vertical layout, gapped rows) ─────────────────────────┐
│ Field  "name *"        [ text input                     ]  │
│ Field  "tier"          [ Select: Select… / free / pro   ]  │
│ ☑  "active"            (boolean rides inline w/ caption)   │
│ Field  "config"  JSON  [ textarea (rows=3)              ]  │
│ Error text (inline, on validation / submit failure)         │
│                                     [ Cancel ]  [ Save ]   │
└────────────────────────────────────────────────────────────┘
```

- Root form container, laid out as a vertical column with a gap between
  rows; one row per writable column.
- Non-boolean: wrapped in a Field (stacked label above the control);
  required labels get ` *`, object/array/unknown get a `JSON` hint.
  Boolean: a horizontally laid-out label pairing the checkbox with a
  caption styled in the shared uppercase-mono caption style.
- Footer: right-aligned, laid out horizontally with a gap — a ghost-styled
  Cancel control and a primary Save control, both small-sized, disabled
  while saving; Save reads "Saving…" while pending.
- Error text renders between the fields and the footer.
- No raw hex colors; no style overrides — color/typography come from the
  toolkit's shared design tokens plus shared classes.

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| `meta` (table metadata) | Caller | Field builder + payload builder | Down | Parameter |
| `initial` (existing row, optional) | Caller | Draft seed + create/edit mode | Down | Parameter |
| `draft` (text/boolean buffer) | The form | Per-column controls | Down | Local state + a field setter |
| field edits | Per-column controls | `draft` | Up | Change callback → the field setter |
| `busy` / `error` | Submission-state mechanism | Buttons (disabled/"Saving…") + inline error text | Down | Internal state |
| submit payload | The form (payload builder) | Caller's submit callback | Up | Callback (awaited) |
| cancel intent | Footer Cancel | Caller's cancel callback | Up | Callback |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | build-fields-from-writable-columns | meta with a `serverManaged` `id` column | No control for `id`; controls for every writable column |
| T2 | pick-control-by-type | columns of enum / boolean / integer / object type | A select / a checkbox / numeric input / JSON textarea respectively |
| T3 | wrap-nonboolean-in-field, mark-required-and-json | required string col + object col | String field labeled "`name` *"; object field wrapped in a Field with a `JSON` hint |
| T4 | seed-draft-from-initial | `initial = { name:"Ada", active:true }` (edit) | Name input pre-filled "Ada"; the active checkbox checked |
| T5 | reject-empty-required | submit with a required field blank | Submission blocked; "`<name>` is required" shown inline |
| T6 | validate-numbers | integer column = "1.5" | Blocked; "`<name>` must be an integer" |
| T7 | validate-numbers | number column = "abc" | Blocked; "`<name>` must be a number" |
| T8 | validate-json | object column = "{bad" | Blocked; "`<name>` must be valid JSON" |
| T9 | omit-untouched-optionals-on-create | create; leave an optional string empty | Payload omits that key (DB default applies) |
| T10 | disable-and-skip-create-only-on-edit | edit; a `createOnly` column holding a client-supplied `rdid` (a caller-chosen id, not server-generated) | Its control is disabled; payload excludes it |
| T11 | run-submit-through-busy-state | valid submit; submit callback pending | Cancel/Save disabled; Save shows "Saving…" until it completes |
| T12 | run-submit-through-busy-state | submit callback fails | Error shown inline; draft values retained |
| T13 | seed-draft-from-initial | edit; `initial` has an object/array column value | Draft is prefilled with the pretty-printed (2-space indented) JSON text |
| T14 | omit-untouched-optionals-on-create, reject-empty-required | create; leave a required boolean untouched | Payload sends `false` for that column |
| T15 | omit-untouched-optionals-on-create | create; leave an optional boolean untouched | Payload omits that key |
| T16 | validate-numbers | number column = "1e999" | Blocked; "`<name>` must be a number" (the value is not a finite number) |
| T17 | clear-field-by-type-on-edit | edit; clear a nullable optional column | Payload sends `null` for that column |
| T18 | clear-field-by-type-on-edit | edit; clear a plain (non-enum) optional string column | Payload sends `''` for that column |
| T19 | clear-field-by-type-on-edit | edit; clear an optional enum/integer/JSON column | Column omitted from the payload; its old value survives |
| T20 | disable-and-skip-create-only-on-edit | edit; a required, empty `createOnly` column | Submission succeeds — no "is required" error; column excluded from the payload |

## Edge Cases

- Create vs edit is inferred purely from `initial` (absent = create). No
  separate mode parameter.
- Untouched create checkbox: stays unset and is omitted so a default-true DB
  column isn't silently forced to `false`; a required boolean instead sends `false`.
- Edit clearing an optional field: nullable columns send `null`, plain (non-enum)
  strings send `''`; other types can't represent "cleared", so the column is
  omitted (its old value survives — the honest option for a partial update).
- `createOnly` columns (client-supplied `rdid`s — a caller-chosen identifier,
  e.g. a slug, rather than a server-generated one): rendered disabled on edit
  and stripped from the update payload before any required-validation runs.
- `1e999` in a number field: rejected (not a finite number) rather than
  silently serialized to `null`.
- A validation throw (required/number/JSON) surfaces inline via the
  submission-state mechanism's error and leaves the draft intact so the user
  can fix and resubmit.
- Object/array/unknown columns round-trip as JSON text (pretty-printed when
  seeded); `unknown` is treated as JSON because the backend's OpenAPI schema
  types jsonb columns that way (see Platform Notes for how metadata is
  generated).

## Platform Notes

- **React / Web (TypeScript):** `packages/web/packages/crud/src/CrudRecordForm.tsx`,
  exported from `@agentic-toolkit/crud`. Composes the shared `Field`, `Button`,
  `useAction` (from `@agenticdevelopertoolkit/ui`) and the package-local
  `CrudFieldInput` (rendering `Select`/`Checkbox`/`Textarea`/`Input` per
  column type) + `ErrorText`. Note it lives in `@agentic-toolkit/crud`, not
  `@agenticdevelopertoolkit/ui`.
- The pure metadata→payload helpers are exported for reuse/testing: `writableColumns`,
  `toDraft`, `buildPayload`, plus the `CrudDraft` / `CrudFormMode` types. An
  untouched create checkbox is represented as `undefined` in the draft.
  Pretty-printing uses `JSON.stringify(value, null, 2)`; the non-finite-number
  check is `Number.isFinite`.
- Root form: `<form className="flex flex-col gap-3">`. Boolean rows: a
  `<label className="flex items-center gap-2">` wrapping the `Checkbox`, with
  the caption styled via `fieldCaptionClass` (the shared uppercase-mono
  caption class from `@agenticdevelopertoolkit/ui/lib/typography`). Footer:
  `flex justify-end gap-2`; Cancel is `type="button"`, Save is
  `type="submit"`, both `size="sm"`. Colors/typography come from the
  toolkit's `apt-*` design tokens (e.g. `text-apt-text-muted`); no raw hex,
  no `!important`.
- Metadata comes from `src/generated/table-metadata.ts` (backend OpenAPI →
  `gen_table_metadata.py`); the submit callback typically maps to
  `useCrudResource`'s `create`/`update`.
- Demo: `ui-showcase` Topic `crud-record-form` (static `meta`; logs the payload).
- First consumer: the `/all-data` generic table editor (`AllDataPane`).
- **Responsive:** Fields stack in a single column; verify at 375 / 768 / 1440 via
  Playwright.
- **SwiftUI / Compose:** No native implementation in this repo; the same
  metadata-driven mapping would render `Picker` (SwiftUI) /
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

## Reference Implementations

| Platform | Path |
|----------|------|

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

**Decision** (React/Web): Validation throws field-named errors surfaced
inline via `useAction`.
**Rationale**: the message names the offending column and the draft is
retained, so the fix is obvious and non-destructive.
**Approved**: pending

**Decision** (React/Web): Object/array/unknown columns use a JSON textarea and
round-trip via `JSON.parse`/`stringify`.
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

## Compliance

| Check | Status | Category |
|---|---|---|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`screen-reader-support` and `keyboard-navigable` rest on `Field`'s label
wrapping and the native `<label>`/`<input>`/`<button>` elements in
`CrudRecordForm.tsx`. `platform-theming` rests on `fieldCaptionClass` and the
shared classes drawing every color from `apt-*` tokens (no raw hex).
`no-hardcoded-strings` fails because the `Cancel`/`Save`/`Saving…`/`Close`
labels and the required/number/JSON error messages in `CrudRecordForm.tsx` are
literal English strings with no localization call.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.3.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/crud/. |
| 1.2.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-23 | Mike Fullerton | Lint pass: added a Design Decision for the `initial`-presence mode inference; named the backend OpenAPI spec (`gen_table_metadata.py`) in place of "the spec" in two places; added the boolean exception to reject-empty-required and the createOnly-before-validation ordering to disable-and-skip-create-only-on-edit; added clear-field-by-type-on-edit with test vectors T17-T19 and T20 for the createOnly/validation ordering; added T13-T16 for JSON pretty-printing, untouched booleans, and `1e999`; defined `rdid`, `fieldCaptionClass`, and `apt-*` on first use; moved the `/all-data` reference out of Overview into a Platform Notes consumer note; added AppKit/UIKit and WinUI 3 Platform Notes bullets and rewrote the SwiftUI/Compose one so none reads "Not applicable"; reformatted every Design Decision into the three-line form with `**Approved**: pending`; rewrote Compliance to link real catalog checks (accessibility, platform-compliance, internationalization), dropping the two rows with no catalog equivalent; fixed the stale source path and the `@agentic-toolkit`/`@agenticdevelopertoolkit/ui` scope mismatch. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Renamed every requirement to subject-only kebab-case, dropping the old prefix everywhere it is cited. |
| 1.0.0 | 2026-07-03 | Mike Fullerton | Initial recipe; documents the metadata-driven CrudRecordForm from @adh-shared/crud. |
