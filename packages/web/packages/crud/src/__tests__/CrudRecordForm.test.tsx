import '@testing-library/jest-dom/vitest'
import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CrudRecordForm, buildPayload, toDraft, writableColumns } from '../CrudRecordForm'
import type { CrudTableMeta } from '../types'

const meta: CrudTableMeta = {
  key: 'demo/widgets',
  schema: 'demo',
  table: 'widgets',
  basePath: '/demo/widgets',
  itemPath: '/demo/widgets/{id}',
  pkParams: ['id'],
  exposure: 'owner',
  columns: [
    { name: 'id', type: 'string', required: false, nullable: false, serverManaged: true },
    { name: 'createdAt', type: 'string', required: false, nullable: false, serverManaged: true },
    { name: 'name', type: 'string', required: true, nullable: false, serverManaged: false, maxLength: 64 },
    { name: 'count', type: 'integer', required: false, nullable: true, serverManaged: false },
    { name: 'active', type: 'boolean', required: false, nullable: false, serverManaged: false },
    { name: 'kind', type: 'string', required: false, nullable: true, serverManaged: false, enum: ['a', 'b'] },
    { name: 'config', type: 'object', required: false, nullable: true, serverManaged: false },
    { name: 'price', type: 'number', required: false, nullable: true, serverManaged: false },
    // jsonb columns come out of the spec as 'unknown' — they must round-trip
    // as JSON like object/array, never through String().
    { name: 'payload', type: 'unknown', required: false, nullable: true, serverManaged: false },
  ],
}

// Mirrors the rdid tables (persona/personas, buckets/schemas): the POST body
// carries `id` but the PUT body doesn't — the backend strips it silently.
const rdidMeta: CrudTableMeta = {
  key: 'persona/personas',
  schema: 'persona',
  table: 'personas',
  basePath: '/persona/personas',
  itemPath: '/persona/personas/{id}',
  pkParams: ['id'],
  exposure: 'owner',
  columns: [
    { name: 'id', type: 'string', required: true, nullable: false, serverManaged: false, createOnly: true },
    { name: 'name', type: 'string', required: true, nullable: false, serverManaged: false },
  ],
}

describe('writableColumns / toDraft', () => {
  it('excludes server-managed columns', () => {
    expect(writableColumns(meta).map((c) => c.name)).toEqual([
      'name',
      'count',
      'active',
      'kind',
      'config',
      'price',
      'payload',
    ])
  })
  it('drafts from an existing row, JSON-encoding object and unknown columns', () => {
    const draft = toDraft(meta, {
      id: 'w1',
      name: 'Widget',
      count: 3,
      active: true,
      kind: 'a',
      config: { color: 'red' },
      price: 1.5,
      payload: { mode: 'fast' },
    })
    expect(draft).toEqual({
      name: 'Widget',
      count: '3',
      active: true,
      kind: 'a',
      config: '{\n  "color": "red"\n}',
      price: '1.5',
      payload: '{\n  "mode": "fast"\n}',
    })
  })
  it('leaves booleans untouched (undefined) on a create draft', () => {
    expect(toDraft(meta).active).toBeUndefined()
  })
})

describe('buildPayload', () => {
  it('coerces numbers, parses JSON, keeps booleans, omits empty optionals on create', () => {
    expect(
      buildPayload(
        meta,
        { name: 'Widget', count: '3', active: false, kind: '', config: '{"color":"red"}' },
        'create',
      ),
    ).toEqual({ name: 'Widget', count: 3, active: false, config: { color: 'red' } })
  })
  it('omits an untouched boolean on create so the DB default applies', () => {
    expect(buildPayload(meta, { name: 'Widget', active: undefined }, 'create')).toEqual({
      name: 'Widget',
    })
  })
  it('sends null for emptied nullable columns on edit (PUT is partial)', () => {
    expect(buildPayload(meta, { name: 'Widget', count: '', active: true, kind: '' }, 'edit')).toEqual(
      { name: 'Widget', count: null, active: true, kind: null, config: null, price: null, payload: null },
    )
  })
  it('sends "" for an emptied optional NON-nullable string on edit, omits other types', () => {
    const clearMeta: CrudTableMeta = {
      ...meta,
      columns: [
        { name: 'note', type: 'string', required: false, nullable: false, serverManaged: false },
        { name: 'level', type: 'string', required: false, nullable: false, serverManaged: false, enum: ['a', 'b'] },
        { name: 'rank', type: 'integer', required: false, nullable: false, serverManaged: false },
      ],
    }
    // note must SEND '' (omission would silently keep the old value); enum and
    // number can't represent '' so omission stays correct for them.
    expect(buildPayload(clearMeta, { note: '', level: '', rank: '' }, 'edit')).toEqual({ note: '' })
  })
  it('rejects an empty required field', () => {
    expect(() => buildPayload(meta, { name: '', active: false }, 'create')).toThrow(
      'name is required',
    )
  })
  it('rejects a malformed number', () => {
    expect(() => buildPayload(meta, { name: 'x', count: 'NaN-ish', active: false }, 'create')).toThrow(
      'count must be a number',
    )
  })
  it('rejects an Infinity-overflowing number ("1e999")', () => {
    expect(() => buildPayload(meta, { name: 'x', count: '1e999' }, 'create')).toThrow(
      'count must be a number',
    )
  })
  it('rejects a fractional value for an integer column, accepts whole values', () => {
    expect(() => buildPayload(meta, { name: 'x', count: '3.5' }, 'create')).toThrow(
      'count must be an integer',
    )
    expect(buildPayload(meta, { name: 'x', count: '3', price: '3.5' }, 'create')).toEqual({
      name: 'x',
      count: 3,
      price: 3.5,
    })
  })
  it('rejects malformed JSON', () => {
    expect(() => buildPayload(meta, { name: 'x', active: false, config: '{nope' }, 'create')).toThrow(
      'config must be valid JSON',
    )
  })
  it('parses unknown (jsonb) columns as JSON, and keeps non-JSON text as a string', () => {
    expect(buildPayload(meta, { name: 'x', payload: '{"mode":"fast"}' }, 'create')).toEqual({
      name: 'x',
      payload: { mode: 'fast' },
    })
    // Untyped jsonb holds any JSON value, so `bar` is the string "bar" (Mike, 2026-09-24).
    expect(buildPayload(meta, { name: 'x', payload: 'bar' }, 'create')).toEqual({
      name: 'x',
      payload: 'bar',
    })
  })
  it('skips createOnly columns on edit, before the required check', () => {
    expect(buildPayload(rdidMeta, { id: '', name: 'Thing' }, 'edit')).toEqual({ name: 'Thing' })
  })
  it('keeps createOnly columns required and included on create', () => {
    expect(buildPayload(rdidMeta, { id: 'com.x.thing', name: 'Thing' }, 'create')).toEqual({
      id: 'com.x.thing',
      name: 'Thing',
    })
    expect(() => buildPayload(rdidMeta, { id: '', name: 'Thing' }, 'create')).toThrow(
      'id is required',
    )
  })
})

describe('CrudRecordForm', () => {
  it('renders the right control per column type, marking required', () => {
    render(<CrudRecordForm meta={meta} canWrite onSubmit={vi.fn()} onCancel={vi.fn()} />)
    expect(screen.getByLabelText('name *')).toBeInTheDocument()
    expect(screen.getByLabelText('count')).toHaveAttribute('type', 'number')
    expect(screen.getByText('active')).toBeInTheDocument() // checkbox label
    expect(screen.getByLabelText('kind')).toBeInTheDocument() // select
    // the Field hint ("JSON") joins the accessible name, so match by prefix
    expect(screen.getByLabelText(/^config/)).toBeInTheDocument() // textarea
    // server-managed columns never render as fields
    expect(screen.queryByLabelText('id')).toBeNull()
    expect(screen.queryByLabelText('createdAt')).toBeNull()
  })

  it('submits the coerced payload', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<CrudRecordForm meta={meta} canWrite onSubmit={onSubmit} onCancel={vi.fn()} />)
    await user.type(screen.getByLabelText('name *'), 'Widget')
    await user.type(screen.getByLabelText('count'), '5')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() =>
      // 'active' untouched -> omitted so the backend default applies
      expect(onSubmit).toHaveBeenCalledWith({ name: 'Widget', count: 5 }),
    )
  })

  it('shows a submit error inline', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockRejectedValue(new Error('409: duplicate'))
    render(
      <CrudRecordForm
        meta={meta}
        canWrite
        initial={{ name: 'Widget', active: true }}
        onSubmit={onSubmit}
        onCancel={vi.fn()}
      />,
    )
    // An edit mode Save is dirty-gated (see the describe block below) — touch a field
    // first so the click actually reaches onSubmit.
    await user.type(screen.getByLabelText('name *'), '!')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('409: duplicate')
  })

  it('shows a validation error without calling onSubmit', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn()
    render(<CrudRecordForm meta={meta} canWrite onSubmit={onSubmit} onCancel={vi.fn()} />)
    await user.click(screen.getByRole('button', { name: 'Save' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('name is required')
    expect(onSubmit).not.toHaveBeenCalled()
  })

  it('round-trips an unknown (jsonb) column through the edit form', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(
      <CrudRecordForm
        meta={meta}
        canWrite
        initial={{ name: 'Widget', active: true, payload: { mode: 'fast' } }}
        onSubmit={onSubmit}
        onCancel={vi.fn()}
      />,
    )
    // textarea (not a plain input) showing pretty JSON, not "[object Object]"
    expect(screen.getByLabelText(/^payload/)).toHaveValue('{\n  "mode": "fast"\n}')
    // Edit mode Save is dirty-gated — touch an unrelated field so the click submits.
    await user.type(screen.getByLabelText('name *'), '!')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ payload: { mode: 'fast' } })),
    )
  })

  it('parses JSON typed into an unknown column on create', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<CrudRecordForm meta={meta} canWrite onSubmit={onSubmit} onCancel={vi.fn()} />)
    await user.type(screen.getByLabelText('name *'), 'Widget')
    await user.click(screen.getByLabelText(/^payload/))
    await user.paste('{"mode": "fast"}')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({ name: 'Widget', payload: { mode: 'fast' } }),
    )
  })

  it('saves plain text in an unknown (jsonb) column as a string', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<CrudRecordForm meta={meta} canWrite onSubmit={onSubmit} onCancel={vi.fn()} />)
    await user.type(screen.getByLabelText('name *'), 'Widget')
    await user.click(screen.getByLabelText(/^payload/))
    await user.paste('bar')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({ name: 'Widget', payload: 'bar' }))
  })

  it('disables createOnly columns on edit (seeded) and drops them from the payload', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(
      <CrudRecordForm
        meta={rdidMeta}
        canWrite
        initial={{ id: 'com.x.thing', name: 'Thing' }}
        onSubmit={onSubmit}
        onCancel={vi.fn()}
      />,
    )
    const idInput = screen.getByLabelText('id *')
    expect(idInput).toBeDisabled()
    expect(idInput).toHaveValue('com.x.thing')
    // id is locked (createOnly on edit) — name is the only field left to dirty the form.
    await user.type(screen.getByLabelText('name *'), '!')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({ name: 'Thing!' }))
  })

  // The read-only twin of this form: the row is still inspectable, but nothing about it
  // suggests an edit the backend would refuse.
  it('locks every field and drops Save when the viewer may not write', () => {
    render(
      <CrudRecordForm
        meta={meta}
        canWrite={false}
        initial={{ name: 'Widget', count: 5 }}
        onSubmit={vi.fn()}
        onCancel={vi.fn()}
      />,
    )
    expect(screen.getByLabelText('name *')).toBeDisabled()
    expect(screen.getByLabelText('count')).toBeDisabled()
    expect(screen.getByLabelText(/^config/)).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Save' })).not.toBeInTheDocument()
    // One way out, named for what it does.
    expect(screen.getByRole('button', { name: 'Close' })).toBeInTheDocument()
  })

  it('keeps createOnly columns editable and included on create', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<CrudRecordForm meta={rdidMeta} canWrite onSubmit={onSubmit} onCancel={vi.fn()} />)
    const idInput = screen.getByLabelText('id *')
    expect(idInput).toBeEnabled()
    await user.type(idInput, 'com.x.thing')
    await user.type(screen.getByLabelText('name *'), 'Thing')
    await user.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({ id: 'com.x.thing', name: 'Thing' }),
    )
  })
})

describe('CrudRecordForm: edit-mode Save is dirty-gated, create-mode is exempt', () => {
  it('edit mode: Save starts disabled on an untouched row, and enables once a field changes', async () => {
    const user = userEvent.setup()
    render(
      <CrudRecordForm
        meta={meta}
        canWrite
        initial={{ name: 'Widget', count: 5, active: true }}
        onSubmit={vi.fn()}
        onCancel={vi.fn()}
      />,
    )
    const save = screen.getByRole('button', { name: 'Save' })
    expect(save).toBeDisabled()
    await user.type(screen.getByLabelText('name *'), '!')
    expect(save).toBeEnabled()
  })

  it('edit mode: Save disables again once an edit is reverted back to the loaded value', async () => {
    const user = userEvent.setup()
    render(
      <CrudRecordForm
        meta={meta}
        canWrite
        initial={{ name: 'Widget', count: 5, active: true }}
        onSubmit={vi.fn()}
        onCancel={vi.fn()}
      />,
    )
    const save = screen.getByRole('button', { name: 'Save' })
    const name = screen.getByLabelText('name *')
    await user.type(name, '!')
    expect(save).toBeEnabled()
    await user.type(name, '{Backspace}')
    expect(save).toBeDisabled()
  })

  it('create mode: Save starts enabled — there is no loaded baseline to diff against', () => {
    render(<CrudRecordForm meta={meta} canWrite onSubmit={vi.fn()} onCancel={vi.fn()} />)
    expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled()
  })
})
