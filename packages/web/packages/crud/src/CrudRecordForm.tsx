'use client'

import { type SubmitEvent } from 'react'
import { Button } from '@agenticdevelopertoolkit/ui/components/button'
import { Field } from '@agenticdevelopertoolkit/ui/blocks/field'
import { CrudFieldInput, isJsonColumn } from './CrudFieldInput'
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text'
import { useAction } from '@agenticdevelopertoolkit/ui/hooks/useAction'
import { useDirtyDraft } from '@agenticdevelopertoolkit/ui/hooks/useDirtyDraft'
import type { CrudColumn, CrudRow, CrudTableMeta } from './types'
import { fieldCaptionClass } from '@agenticdevelopertoolkit/ui/lib/typography'

/** The columns a client may set — everything the create body accepts. */
export function writableColumns(meta: CrudTableMeta): CrudColumn[] {
  return meta.columns.filter((c) => !c.serverManaged)
}

/** Editing buffer: writable columns as text; booleans as booleans, except an
 *  untouched checkbox on CREATE stays `undefined` (omitted from the payload so
 *  the DB column default applies — the spec doesn't carry defaults, so sending
 *  `false` would silently override a default-true column). */
export type CrudDraft = Record<string, string | boolean | undefined>

export type CrudFormMode = 'create' | 'edit'

export function toDraft(meta: CrudTableMeta, initial?: CrudRow): CrudDraft {
  const draft: CrudDraft = {}
  for (const column of writableColumns(meta)) {
    const value = initial?.[column.name]
    if (column.type === 'boolean') {
      draft[column.name] = initial ? value === true : undefined
    } else if (isJsonColumn(column)) {
      draft[column.name] = value == null ? '' : JSON.stringify(value, null, 2)
    } else {
      draft[column.name] = value == null ? '' : String(value)
    }
  }
  return draft
}

/** Coerce the draft into a request payload. On CREATE, empty/untouched
 *  optional fields are OMITTED (so backend column defaults apply). On EDIT —
 *  the backend's PUT is a partial update — an emptied optional column must
 *  SEND something or the old value silently survives: `null` where nullable,
 *  `''` for plain strings (spec-valid — no minLength on generic-CRUD bodies);
 *  other types can't represent "cleared", so omission is the honest option.
 *  Empty required fields and malformed numbers/JSON throw with a field-named
 *  message the form shows inline. */
export function buildPayload(meta: CrudTableMeta, draft: CrudDraft, mode: CrudFormMode): CrudRow {
  const payload: CrudRow = {}
  for (const column of writableColumns(meta)) {
    // createOnly columns (client-supplied rdids) are stripped from PUT by the
    // backend — sending them would silently no-op, so skip them on edit before
    // ANY validation (the required throw must never fire for them).
    if (mode === 'edit' && column.createOnly) continue
    const value = draft[column.name]
    if (column.type === 'boolean') {
      if (value === undefined) {
        // untouched on create: let the DB default decide (false if required)
        if (column.required) payload[column.name] = false
        continue
      }
      payload[column.name] = value === true
      continue
    }
    const text = typeof value === 'string' ? value.trim() : ''
    if (text === '') {
      if (column.required) throw new Error(`${column.name} is required`)
      if (mode === 'edit') {
        if (column.nullable) payload[column.name] = null
        else if (column.type === 'string' && !column.enum) payload[column.name] = ''
      }
      continue
    }
    if (column.type === 'integer' || column.type === 'number') {
      const num = Number(text)
      // isFinite, not !isNaN: Number('1e999') is Infinity, which
      // JSON.stringify would silently serialize as null.
      if (!Number.isFinite(num)) throw new Error(`${column.name} must be a number`)
      if (column.type === 'integer' && !Number.isInteger(num)) {
        throw new Error(`${column.name} must be an integer`)
      }
      payload[column.name] = num
    } else if (isJsonColumn(column)) {
      try {
        payload[column.name] = JSON.parse(text)
      } catch {
        // An `unknown` (untyped jsonb) column holds ANY JSON value, a string included — so text
        // that isn't JSON is that string, not an error. Typing `bar` into a key/value pair's value
        // was refused as "value must be valid JSON" (Mike, 2026-09-24). A declared object/array
        // column still demands its shape. So does text that opens like JSON (`{`, `[` or `"`):
        // that is a typo in a structured value, and saving it as a string silently replaced the
        // object — a bucket's `metadata`, blanking its Settings description with no error. A
        // literal string starting with one of those is typed JSON-quoted.
        if (column.type !== 'unknown' || /^[[{"]/.test(text)) {
          throw new Error(`${column.name} must be valid JSON`)
        }
        payload[column.name] = text
      }
    } else {
      payload[column.name] = text
    }
  }
  return payload
}

export interface CrudRecordFormProps {
  meta: CrudTableMeta
  /** Editing this row; absent = creating. */
  initial?: CrudRow
  /** Whether the viewer may write this table (see `canWriteTable`). False locks every field
   *  and drops Save, leaving a row VIEWER — the backend refuses the write, so a submit button
   *  here only leads to a 403. Required, not defaulted: a caller that hasn't decided must not
   *  silently get the permissive answer. */
  canWrite: boolean
  onSubmit: (values: CrudRow) => Promise<void>
  onCancel: () => void
}

/** Create/edit form generated from the table metadata: enum → select,
 *  boolean → checkbox, number → numeric input, object/array/unknown → JSON
 *  textarea, everything else → text input. Read-only (`canWrite` false) renders
 *  the same fields locked, with Close in place of Cancel/Save. */
export function CrudRecordForm({
  meta,
  initial,
  canWrite,
  onSubmit,
  onCancel,
}: CrudRecordFormProps) {
  const mode: CrudFormMode = initial ? 'edit' : 'create'
  const { draft, patch, dirty } = useDirtyDraft<CrudDraft>(() => toDraft(meta, initial))
  const { busy: saving, error, run } = useAction()
  // On EDIT, an untouched row has nothing to save — gate on dirty so re-submitting the
  // loaded values (a silent no-op PUT) isn't offered. CREATE has no loaded baseline to
  // diff against — an all-defaults row is a legitimate save, so it stays exempt (same
  // "genuinely create-only" carve-out the rest of the dirty-gating work uses).
  const canSave = mode === 'create' || dirty

  function handleSubmit(event: SubmitEvent) {
    event.preventDefault()
    void run(async () => {
      await onSubmit(buildPayload(meta, draft, mode))
    })
  }

  const setField = (name: string, value: string | boolean) => patch({ [name]: value })

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-3">
      {writableColumns(meta).map((column) => {
        const label = column.required ? `${column.name} *` : column.name
        // createOnly columns can't change on edit (the backend strips them
        // from PUT) — show the seeded value, disabled, not a doomed edit. A viewer
        // without write access gets the same treatment for every column.
        const disabled = !canWrite || (mode === 'edit' && column.createOnly === true)
        const control = (
          <CrudFieldInput
            column={column}
            value={draft[column.name]}
            disabled={disabled}
            onChange={(value) => setField(column.name, value)}
          />
        )
        // Boolean rides inline with its caption; everything else stacks in a Field
        // (JSON columns flag their encoding via the hint).
        if (column.type === 'boolean') {
          return (
            <label key={column.name} className="flex items-center gap-2">
              {control}
              <span className={fieldCaptionClass}>
                {label}
              </span>
            </label>
          )
        }
        return (
          <Field key={column.name} label={label} hint={isJsonColumn(column) ? 'JSON' : undefined}>
            {control}
          </Field>
        )
      })}
      <ErrorText error={error} />
      <div className="flex justify-end gap-2">
        {/* Read-only: one way out, named for what it does. A disabled Save would still
            advertise an action the backend would refuse. */}
        <Button type="button" variant="ghost" size="sm" onClick={onCancel} disabled={saving}>
          {canWrite ? 'Cancel' : 'Close'}
        </Button>
        {canWrite && (
          <Button type="submit" size="sm" disabled={saving || !canSave}>
            {saving ? 'Saving…' : 'Save'}
          </Button>
        )}
      </div>
    </form>
  )
}
