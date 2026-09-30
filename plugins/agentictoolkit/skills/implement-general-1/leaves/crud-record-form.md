<!-- leaf: implement-general-1/crud-record-form · source: crud-record-form.md -->

**Rules** (cite as `implement-general-1/crud-record-form#<slug>`):

- `build-fields-from-writable-columns` MUST
- `pick-control-by-type` MUST
- `wrap-nonboolean-in-field` MUST
- `mark-required-and-json` MUST
- `seed-draft-from-initial` MUST
- `reject-empty-required` MUST
- `validate-numbers` MUST
- `validate-json` MUST
- `omit-untouched-optionals-on-create` MUST
- `disable-and-skip-create-only-on-edit` MUST
- `clear-field-by-type-on-edit` MUST
- `run-submit-through-useaction` MUST

# CrudRecordForm

## Overview

`CrudRecordForm` in `@agentic-toolkit/crud` is a **metadata-driven** create/edit form
for one generic-CRUD table. From a `CrudTableMeta` it builds one control per
**writable** column — skipping every `serverManaged` column (ids, timestamps) —
picking the control by column type: enum → `Select`, boolean → `Checkbox`,
integer/number → numeric input, object/array/unknown → JSON textarea, everything
else → text input. Each non-boolean control is wrapped in the shared `Field`
(label + optional "JSON" hint); booleans ride inline beside their caption.

Absence of an `initial` row means **create**; a supplied `initial` means **edit**.
The form owns a text/boolean **draft** buffer seeded from `initial` and, on submit,
coerces the draft into a typed payload: required-but-empty fields and malformed
numbers/JSON **throw** a field-named error shown inline; on create, untouched
optional fields are omitted so DB defaults apply; on edit, `createOnly` columns are
disabled and skipped (the backend strips them from PUT). Submission runs through
the shared `useAction` hook, which drives the busy/error state and disables the
buttons while saving.

It powers any surface that creates/edits one CRUD row without hand-authored
fields (see Platform Notes for its first consumer).

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| Field | agenticdevelopertoolkit://recipes/field | Label + optional hint wrapper around each non-boolean control | yes | `label` = `name` (+ ` *` when required); `hint="JSON"` for object/array/unknown columns |

Composed shared primitives without their own recipe domains: `CrudFieldInput` (the
per-type control picker — `Select`/`Checkbox`/`Textarea`/`Input`), `Button`
(Cancel + Save), `ErrorText` (inline error), and the `useAction` hook (busy/error
orchestration). The metadata→payload logic (`writableColumns`, `toDraft`,
`buildPayload`) is exported alongside the component.

## Integration Requirements

- **build-fields-from-writable-columns**: The form MUST render one control per
  writable column and MUST NOT render any `serverManaged` column.
- **pick-control-by-type**: The form MUST pick each control from the column
  type — enum → `Select`, boolean → `Checkbox`, integer/number → numeric input,
  object/array/unknown → JSON textarea, otherwise text input.
- **wrap-nonboolean-in-field**: The form MUST wrap each non-boolean control in
  a `Field` labeled with the column name, and MUST render a boolean inline beside
  its caption.
- **mark-required-and-json**: The form MUST append ` *` to a required column's
  label and MUST show a `JSON` hint on object/array/unknown columns.
- **seed-draft-from-initial**: The form MUST seed its draft from `initial` when
  editing (booleans as booleans, JSON columns pretty-printed, others as text) and
  MUST start create fields empty (booleans untouched/`undefined`).
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
  value survives the partial PUT).
- **run-submit-through-useaction**: On submit the form MUST call
  `onSubmit(payload)` via `useAction`, disabling Cancel/Save and showing "Saving…"
  while the promise is pending, and MUST surface a thrown error inline without
  losing the draft.

## Layout

```
┌ <form> (flex flex-col gap-3) ──────────────────────────────┐
│ Field  "name *"        [ text input                     ]  │
│ Field  "tier"          [ Select: Select… / free / pro   ]  │
│ ☑  "active"            (boolean rides inline w/ caption)   │
│ Field  "config"  JSON  [ textarea (rows=3)              ]  │
│ ErrorText (inline, on validation / submit failure)         │
│                                     [ Cancel ]  [ Save ]   │
└────────────────────────────────────────────────────────────┘
```

- Root `<form className="flex flex-col gap-3">`; one row per writable column.
- Non-boolean: `Field` (stacked label above the control); required labels get ` *`,
  object/array/unknown get a `JSON` hint. Boolean: a `<label className="flex
  items-center gap-2">` with the `Checkbox` then a caption styled with
  `fieldCaptionClass` (the shared uppercase-mono caption class from
  `@agenticdevelopertoolkit/ui/lib/typography`).
- Footer: right-aligned `flex justify-end gap-2` — a ghost `Cancel` (`type="button"`)
  and a primary `Save` (`type="submit"`), both `size="sm"`, disabled while saving;
  Save reads "Saving…" while pending.
- `ErrorText` renders between the fields and the footer.
- No raw hex; no `!important` (color/typography via the toolkit's `apt-*` design
  tokens — e.g. `text-apt-text-muted` — plus shared classes).

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| `meta` (`CrudTableMeta`) | Caller | Field builder + `buildPayload` | Down | Prop |
| `initial` (`CrudRow?`) | Caller | `toDraft` seed + create/edit mode | Down | Prop |
| `draft` (`CrudDraft`) | CrudRecordForm | `CrudFieldInput` controls | Down | `useState` + `setField` |
| field edits | `CrudFieldInput` | `draft` | Up | `onChange` → `setField(name, value)` |
| `busy` / `error` | `useAction` | Buttons (disabled/"Saving…") + `ErrorText` | Down | Hook state |
| submit payload | CrudRecordForm (`buildPayload`) | Caller `onSubmit(values)` | Up | Callback (awaited) |
| cancel intent | Footer Cancel | Caller `onCancel` | Up | Callback |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | build-fields-from-writable-columns | meta with a `serverManaged` `id` column | No control for `id`; controls for every writable column |
| T2 | pick-control-by-type | columns of enum / boolean / integer / object type | Select / Checkbox / numeric input / JSON textarea respectively |
| T3 | wrap-nonboolean-in-field, mark-required-and-json | required string col + object col | String field labeled "`name` *"; object field wrapped in a `Field` with a `JSON` hint |
| T4 | seed-draft-from-initial | `initial = { name:"Ada", active:true }` (edit) | Name input pre-filled "Ada"; the active checkbox checked |
| T5 | reject-empty-required | submit with a required field blank | Submission blocked; "`<name>` is required" shown inline |
| T6 | validate-numbers | integer column = "1.5" | Blocked; "`<name>` must be an integer" |
| T7 | validate-numbers | number column = "abc" | Blocked; "`<name>` must be a number" |
| T8 | validate-json | object column = "{bad" | Blocked; "`<name>` must be valid JSON" |
| T9 | omit-untouched-optionals-on-create | create; leave an optional string empty | Payload omits that key (DB default applies) |
| T10 | disable-and-skip-create-only-on-edit | edit; a `createOnly` column holding a client-supplied `rdid` (a caller-chosen id, not server-generated) | Its control is disabled; payload excludes it |
| T11 | run-submit-through-useaction | valid submit; `onSubmit` pending | Cancel/Save disabled; Save shows "Saving…" until resolve |
| T12 | run-submit-through-useaction | `onSubmit` rejects | Error shown via `ErrorText`; draft values retained |
| T13 | seed-draft-from-initial | edit; `initial` has an object/array column value | Draft is prefilled with the pretty-printed (`JSON.stringify(value, null, 2)`) JSON text |
| T14 | omit-untouched-optionals-on-create, reject-empty-required | create; leave a required boolean untouched | Payload sends `false` for that column |
| T15 | omit-untouched-optionals-on-create | create; leave an optional boolean untouched | Payload omits that key |
| T16 | validate-numbers | number column = "1e999" | Blocked; "`<name>` must be a number" (`Number.isFinite` is false) |
| T17 | clear-field-by-type-on-edit | edit; clear a nullable optional column | Payload sends `null` for that column |
| T18 | clear-field-by-type-on-edit | edit; clear a plain (non-enum) optional string column | Payload sends `''` for that column |
| T19 | clear-field-by-type-on-edit | edit; clear an optional enum/integer/JSON column | Column omitted from the payload; its old value survives |
| T20 | disable-and-skip-create-only-on-edit | edit; a required, empty `createOnly` column | Submission succeeds — no "is required" error; column excluded from the payload |

