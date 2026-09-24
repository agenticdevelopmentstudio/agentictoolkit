'use client'

import {
  memo,
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent,
  type PointerEvent,
} from 'react'
import { ButtonBar, type ButtonBarActions, type PaneExitGuard } from '@agenticdevelopertoolkit/ui/blocks'
import { AlertModal } from '@agenticdevelopertoolkit/ui/components/alert-modal'
import { Badge } from '@agenticdevelopertoolkit/ui/components/badge'
import { Button } from '@agenticdevelopertoolkit/ui/components/button'
import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox'
import { ApiButton } from '@agentic-toolkit/api-explorer'
import { useReportBusy } from '@agentic-toolkit/resource'
import { MoveToEcosystemDialog } from './MoveToEcosystemDialog'
import { ResizableSplit } from '@agenticdevelopertoolkit/ui/components/resizable-split'
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner'
import { CrudFieldInput } from './CrudFieldInput'
import { buildPayload, toDraft, type CrudDraft } from './CrudRecordForm'
import { isColumnEditable, isColumnHidden, type EditableMode } from './editability'
import { isRowDirty, mergeDraft } from './edits'
import { canWriteTable } from './exposure'
import { useViewer } from './viewer'
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text'
import { useAction } from '@agenticdevelopertoolkit/ui/hooks/useAction'
import { rowKey, useCrudResource } from './useCrudResource'
import type { CrudColumn, CrudRow, CrudTableMeta } from './types'
import { fieldCaptionClass } from '@agenticdevelopertoolkit/ui/lib/typography'

export interface CrudDataViewProps {
  /** The table whose data this view shows — the single input, so the later
   *  drop-in stays mechanical. */
  meta: CrudTableMeta
  /** Optional column-equality LIST filter (e.g. `{ sourceProvider: 'reddit' }`),
   *  passed to {@link useCrudResource}. */
  filter?: Record<string, string>
  /** Optional target-ecosystem scope override (`?ecosystemId=` on every verb) for the
   *  backend's ecosystem-param-scoped tables — the integration Data tab names the
   *  ecosystem it is configuring, since the caller's JWT ecosystem is never that one.
   *  Passed to {@link useCrudResource}. */
  scopeEcosystemId?: string
  /** Registers this view's unsaved-work guard with the enclosing browser (a stable
   *  object, or null on unmount) so navigating away from a dirty editor can prompt
   *  Save / Discard / Cancel instead of silently dropping staged edits. Omitted
   *  when the view is used standalone. */
  onGuardChange?: (guard: PaneExitGuard | null) => void
  /** Values a NEW row starts with, for columns the surface already knows (a bucket's table view
   *  seeds `ecosystemId` with the bucket's ecosystem). Without it a create omits the column, the
   *  backend stamps the CALLER's ecosystem, and the row vanishes from a list filtered to another
   *  one the moment it saves (Mike, 2026-09-24). Only writable columns are seeded, and a seeded
   *  column is PINNED: hidden from the row form, because the surface has already decided it — a
   *  bucket's row cannot be moved to another ecosystem from inside that bucket (Mike, 2026-09-24:
   *  "you cannot change the ecosystem id here, don't show it"). */
  createDefaults?: Record<string, string>
}

/** A synthetic local key prefix for create drafts — rows that exist only in the
 *  editor (no server id yet). Kept distinct from any real {@link rowKey}, which
 *  is a '/'-joined run of URL-encoded pk values. */
const DRAFT_PREFIX = '__draft-'

/** Smallest a column may be dragged to (px) — keeps a header readable. */
const MIN_COL_WIDTH = 64

/** Keyboard column-resize step (px); Shift takes a larger stride. */
const COL_STEP = 8
const COL_STEP_LARGE = 24

/**
 * One source of a cell's FULL value as display text — used by the row list, the
 * draft rows, AND the read-only detail so all three read identically: empty when
 * null/undefined, `true`/`false` for booleans, strings verbatim, everything else
 * (objects/arrays/numbers) serialised to JSON/String. The list truncates it
 * visually and reveals the whole value on hover.
 */
function formatCellDisplay(value: unknown): string {
  if (value == null) return ''
  if (typeof value === 'boolean') return value ? 'true' : 'false'
  if (typeof value === 'string') return value
  return JSON.stringify(value)
}

/**
 * The detail pane for one table in the All-Data browser ({@link CrudDataBrowser}):
 * the split table editor. A top {@link ButtonBar} (Create │ Delete … Cancel Save),
 * then a {@link ResizableSplit} whose top pane is the live row list (a leading
 * select-for-delete checkbox column + resizable headers) and whose bottom pane is
 * the active row's editable details.
 *
 * Edits stage in `edits` (per rowKey, only the changed columns) over a baseline —
 * server values for an existing row, blank defaults for a create draft — so Cancel
 * is a pure revert. Save flushes everything in one pass, dropping each unit's staged
 * state AS it persists (so a partial failure leaves only the un-written units staged
 * and a retry re-sends exactly those): a PUT per dirty existing row, a POST per draft
 * (payloads built exactly as {@link CrudRecordForm} does), then one refetch. Delete
 * multi-selects rows and confirms before issuing a DELETE per row. `meta` stays the
 * only required input.
 */
export function CrudDataView({
  meta,
  filter,
  scopeEcosystemId,
  onGuardChange,
  createDefaults,
}: CrudDataViewProps) {
  const resource = useCrudResource(meta, filter, scopeEcosystemId)
  const { rows, loading, fetching, error } = resource

  // This view is a topic's body in every one of its mounts (the All-Data browser, Knowledge bases,
  // an integration's synced data, a persona's tables), and it publishes no list of its own — so the
  // list above owns the spinner. `fetching`, not `loading`: switching tables keeps the previous
  // table's rows on screen while the new one loads, and a re-list after a save shows nothing at
  // all, which are precisely the reads the pane's own spinner below is written to suppress.
  useReportBusy(fetching)

  // A single active row for the detail pane, identified by its primary key (a
  // server row) or its synthetic draft key. Stable across a re-list, unlike an
  // index. Never the empty key: keyless rows aren't addressable, so they can't
  // become active (see RowList).
  const [activeKey, setActiveKey] = useState<string | null>(null)
  // Create drafts: synthetic keys, in insertion order. Their typed values live in
  // `edits` keyed the same way; their baseline is the table's blank default draft.
  const [draftKeys, setDraftKeys] = useState<string[]>([])
  const draftSeq = useRef(0)
  // Per-row staged edits, keyed by rowKey/draftKey then column name. Carries only
  // CHANGED columns over the baseline, so Cancel = drop the entry and Save merges
  // them back before building the payload.
  const [edits, setEdits] = useState<Record<string, CrudDraft>>({})
  // Rows checked for deletion (server rowKeys only) — a separate axis from the
  // single "active for details" row.
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [confirmingDelete, setConfirmingDelete] = useState(false)
  // Who the viewer is — the input to both write-side gates below. `ready` is false while auth
  // bootstraps; the whole pane waits on it rather than rendering a read-only surface it would
  // then have to re-flow (see the early return before the JSX).
  const { isAdmin: viewerIsAdmin, ready: viewerReady } = useViewer()
  // Whether this viewer may write this table at all, per the backend's documented exposure tier:
  // `catalog` and `admin` tables reserve writes to admins, so for everyone else the whole editing
  // surface goes away — no Create, no Delete, no selection checkboxes, every field locked.
  // Presentation only: the backend refuses the write regardless (see exposure.ts).
  const canWrite = canWriteTable(meta, viewerIsAdmin)
  // Cross-ecosystem move (admin): available on any ecosystem-scoped table (one carrying an
  // `ecosystem_id` column), acting on the checked rows — so the SAME generic action reaches every
  // scoped table (personas included), not a per-feature bolt-on.
  // Column names are the camelCase JSON field names (CrudColumn.name), so the tenant column is
  // `ecosystemId`, not `ecosystem_id`. Single-pk only — the move endpoint takes one id, and the
  // backend refuses composite keys, so a composite-pk table (e.g. persona_memory.links) must not
  // offer the action.
  const canMove =
    viewerIsAdmin &&
    meta.pkParams.length === 1 &&
    meta.columns.some((column) => column.name === 'ecosystemId')
  const [movingOpen, setMovingOpen] = useState(false)

  const save = useAction()
  const del = useAction()

  // O(1) lookup of an addressable server row by its primary key, shared by the
  // dirty check, save, and delete instead of an O(N) scan each. Keyless rows
  // (rowKey '') have no itemPath — they can't be edited, saved, or deleted — so
  // they're excluded here (and non-interactive in the list).
  const rowByKey = useMemo(() => {
    const map = new Map<string, CrudRow>()
    for (const row of rows) {
      const key = rowKey(meta, row)
      if (key !== '') map.set(key, row)
    }
    return map
  }, [rows, meta])

  const isDraftActive = activeKey != null && draftKeys.includes(activeKey)
  const activeRow = useMemo(
    () => (isDraftActive || activeKey == null ? null : (rowByKey.get(activeKey) ?? null)),
    [isDraftActive, activeKey, rowByKey],
  )
  // The active row's baseline as a draft buffer: a draft's is the table's blank
  // defaults; an existing row's is its server values. Displayed value per field is
  // `edits[activeKey][col] ?? baseline[col]`.
  // Serialized so an inline `createDefaults={{…}}` literal doesn't change identity every render.
  const defaultsKey = JSON.stringify(createDefaults ?? {})
  const blankDraft = useCallback((): CrudDraft => {
    const draft = toDraft(meta)
    for (const [name, value] of Object.entries(JSON.parse(defaultsKey) as Record<string, string>))
      if (name in draft) draft[name] = value
    return draft
  }, [meta, defaultsKey])
  const baseline = useMemo<CrudDraft | null>(() => {
    if (isDraftActive) return blankDraft()
    return activeRow ? toDraft(meta, activeRow) : null
  }, [meta, activeRow, isDraftActive, blankDraft])

  const setEdit = (key: string, name: string, value: string | boolean) =>
    setEdits((prev) => ({ ...prev, [key]: { ...prev[key], [name]: value } }))
  const dropEdit = useCallback((key: string) => {
    setEdits((prev) => {
      if (!(key in prev)) return prev
      const { [key]: _removed, ...rest } = prev
      return rest
    })
  }, [])

  // Dirty when any buffered edit on an EXISTING row differs from its baseline (an
  // input typed back to the original, or an edit whose row has since been deleted,
  // leaves nothing to save). Drafts are dirty merely by existing (`hasDrafts`), so a
  // blank new row still enables Save.
  const isDirty = useMemo(() => {
    for (const [key, rowEdits] of Object.entries(edits)) {
      if (draftKeys.includes(key)) continue
      const serverRow = rowByKey.get(key)
      if (!serverRow) continue
      if (isRowDirty(toDraft(meta, serverRow), rowEdits)) return true
    }
    return false
  }, [edits, rowByKey, meta, draftKeys])

  const hasDrafts = draftKeys.length > 0
  // Unsaved work — but only work this viewer could actually persist. `canWrite` is derived from
  // LIVE auth, so it can flip mid-edit (the session expires, a logout fires in another tab)
  // while `edits`/`draftKeys` survive; without this the pane would sit there with "Read-only"
  // beside an enabled Save, and the exit guard would prompt to save writes that all 403.
  const dirty = (isDirty || hasDrafts) && canWrite

  // The server rows that can be checked for deletion (keyless rows are excluded from
  // rowByKey, so its keys ARE exactly the selectable ones).
  const selectableKeys = useMemo(() => [...rowByKey.keys()], [rowByKey])
  const allSelected = selectableKeys.length > 0 && selectableKeys.every((key) => selected.has(key))

  // The RAW primary-key value of each selected row (the move endpoint takes the id itself, not the
  // '/'-encoded rowKey). Single-pk tables only — the backend refuses composite-key moves.
  const moveIds = useMemo(() => {
    const pkProp = meta.pkParams[0]
    if (!pkProp) return []
    return [...selected]
      .map((key) => rowByKey.get(key))
      .filter((row): row is CrudRow => row != null)
      .map((row) => String(row[pkProp] ?? ''))
  }, [selected, rowByKey, meta])

  const toggleSelect = useCallback((key: string, checked: boolean) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (checked) next.add(key)
      else next.delete(key)
      return next
    })
  }, [])
  function toggleSelectAll(checked: boolean) {
    setSelected(checked ? new Set(selectableKeys) : new Set())
  }

  // ── Create: insert a blank draft row and make it the active (editable) row. ──
  function onCreate() {
    // Don't graft a new draft onto an in-flight batch save — the save's terminal
    // cleanup would race it, and the closure it captured can't persist it anyway.
    if (save.busy) return
    const key = `${DRAFT_PREFIX}${draftSeq.current++}`
    setDraftKeys((prev) => [...prev, key])
    setActiveKey(key)
  }

  // ── Cancel: discard every staged edit and draft, reverting to server state. ──
  function onCancel() {
    setEdits({})
    setActiveKey((prev) => (prev != null && draftKeys.includes(prev) ? null : prev))
    setDraftKeys([])
  }

  // The batch write, unit by unit — each unit's staged state is dropped AS it
  // persists, so a partial failure leaves ONLY the un-written units staged and a
  // retry re-sends exactly those (never re-POSTing an already-created draft or
  // re-PUTting a saved row). Throws on the first failure; the caller shows it.
  const performSave = async () => {
    for (const [key, rowEdits] of Object.entries(edits)) {
      if (draftKeys.includes(key)) continue
      const row = rowByKey.get(key)
      if (!row) {
        dropEdit(key) // its row is gone (e.g. just deleted) — nothing to save
        continue
      }
      const base = toDraft(meta, row)
      if (!isRowDirty(base, rowEdits)) {
        dropEdit(key)
        continue
      }
      await resource.updateRow(row, buildPayload(meta, mergeDraft(base, rowEdits), 'edit'))
      dropEdit(key) // persisted — drop its staged edits so a retry won't re-PUT it
    }
    for (const key of draftKeys) {
      await resource.createRow(buildPayload(meta, mergeDraft(blankDraft(), edits[key]), 'create'))
      // created — drop the draft + its edits so a retry won't re-POST a duplicate
      setDraftKeys((prev) => prev.filter((k) => k !== key))
      dropEdit(key)
      if (activeKey === key) setActiveKey(null)
    }
    await resource.refresh()
  }

  // ── Save: run the batch, surfacing busy/error via the action state machine. ──
  function onSave() {
    void save.run(performSave)
  }

  // ── Delete: confirm first, then DELETE every selected row and refetch once. ──
  function onDelete() {
    if (selected.size > 0) setConfirmingDelete(true)
  }
  function confirmDelete() {
    void del.run(async () => {
      try {
        for (const key of [...selected]) {
          const row = rowByKey.get(key)
          if (row) await resource.removeRow(row)
          // Drop from the selection + any staged edits AS the row goes, so a partial
          // failure leaves only the not-yet-deleted rows selected for the retry.
          setSelected((prev) => {
            const next = new Set(prev)
            next.delete(key)
            return next
          })
          dropEdit(key)
          if (activeKey === key) setActiveKey(null)
        }
        setConfirmingDelete(false) // full success closes the modal
      } finally {
        await resource.refresh() // always resync the list, partial failure or not
      }
    })
  }

  const actions: ButtonBarActions = {
    onCreate,
    createLabel: 'Create',
    onCancel,
    canCancel: dirty,
    onSave,
    canSave: dirty,
    saving: save.busy,
    onDelete,
    canDelete: selected.size > 0,
  }

  // Expose the unsaved-work guard to the enclosing browser via a STABLE object whose
  // `isDirty` reads the latest state through a ref (registered once; never churns
  // the parent's exit-guard).
  const dirtyRef = useRef(dirty)
  dirtyRef.current = dirty
  const guard = useMemo<PaneExitGuard>(() => ({ isDirty: () => dirtyRef.current }), [])
  // Published only while DIRTY, so the channel's presence is a render-value dirty signal for the
  // enclosing shell (see useExitGuardChannel). `guard` itself is identity-stable, so before this
  // the effect fired on mount/unmount only and a draft going dirty was invisible upstream.
  useEffect(() => {
    onGuardChange?.(dirty ? guard : null)
    return () => onGuardChange?.(null)
  }, [onGuardChange, guard, dirty])

  // This table's generic-CRUD endpoint (/<schema>/<table>), seeded with the same list
  // filter + ecosystem scope the view itself uses, so "try it" mirrors what's on screen.
  const apiQuery: Record<string, string> = { ...(filter ?? {}) }
  if (scopeEcosystemId) apiQuery.ecosystemId = scopeEcosystemId

  // Hold the whole pane until we know who is looking. Rendering first would mean guessing
  // "non-admin", i.e. showing an admin the read-only surface — no checkbox column, no Create,
  // fields as plain text — and then re-flowing the entire table around them a paint later.
  if (!viewerReady) {
    return (
      <div className="flex min-h-0 flex-1 items-center justify-center p-6">
        <Spinner />
      </div>
    )
  }

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-dirty={dirty || undefined}>
      <ButtonBar
        actions={actions}
        showCreate={canWrite}
        showDelete={canWrite}
        leading={
          !canWrite ? (
            // Say WHY the actions are missing. A bar that silently loses its buttons reads as
            // broken. The reason is VISIBLE text, not a `title`: a tooltip on a non-interactive
            // element reaches neither a screen reader nor a touch device, which is most of the
            // audience that needs telling. `canMove` implies admin, so it can never be the
            // alternative here.
            <span className="flex items-center gap-2">
              <Badge variant="neutral">Read-only</Badge>
              <span className="text-xs text-apt-text-dim">
                Shared platform data — only an administrator can change it.
              </span>
            </span>
          ) : canMove ? (
            <Button
              variant="secondary"
              disabled={selected.size === 0}
              onClick={() => setMovingOpen(true)}
            >
              Move to ecosystem…
            </Button>
          ) : undefined
        }
      />
      <div className="flex justify-end px-4 pt-2">
        <ApiButton
          endpoint={{ method: 'GET', path: `/${meta.schema}/${meta.table}` }}
          queryValues={apiQuery}
          title={`${meta.table} API`}
        />
      </div>
      {save.error && (
        <div className="px-6 py-1">
          <ErrorText error={save.error} />
        </div>
      )}
      <ResizableSplit
        className="min-h-0 flex-1"
        // Persists the divider position across mounts (component state + localStorage).
        storageKey="crud-data-view-split"
        bottomLabel="Row details"
        // The divider is the detail pane's header bar: the active row's identity
        // lives here (was RowDetails' bespoke header) and the bar's disclosure
        // replaces the pane's own CollapseToggle.
        header={
          baseline ? (
            <>
              <span className={fieldCaptionClass}>{isDraftActive ? 'New row' : 'Row'}</span>
              <span className="ml-2 truncate font-mono text-xs text-apt-text">
                {isDraftActive ? '(unsaved)' : (activeRow ? rowKey(meta, activeRow) : null) || '(no primary key)'}
              </span>
            </>
          ) : (
            'Row details'
          )
        }
        top={
          <RowList
            meta={meta}
            rows={rows}
            draftKeys={draftKeys}
            draftBaseline={blankDraft()}
            edits={edits}
            loading={loading}
            error={error}
            activeKey={activeKey}
            onSelect={setActiveKey}
            canWrite={canWrite}
            selected={selected}
            allSelected={allSelected}
            onToggleSelect={toggleSelect}
            onToggleSelectAll={toggleSelectAll}
          />
        }
        bottom={
          <RowDetails
            meta={meta}
            pinned={defaultsKey}
            baseline={baseline}
            canWrite={canWrite}
            mode={isDraftActive ? 'create' : 'edit'}
            edits={activeKey != null ? edits[activeKey] : undefined}
            onEdit={(name, value) => {
              if (activeKey != null) setEdit(activeKey, name, value)
            }}
          />
        }
      />
      <AlertModal
        open={confirmingDelete}
        title={`Delete ${selected.size} row${selected.size === 1 ? '' : 's'}?`}
        description={
          del.error ? (
            <ErrorText error={del.error} />
          ) : (
            `This permanently deletes the selected row${selected.size === 1 ? '' : 's'}.`
          )
        }
        tone="error"
        destructive
        confirmLabel="Delete"
        cancelLabel="Cancel"
        onConfirm={confirmDelete}
        onCancel={() => setConfirmingDelete(false)}
        busy={del.busy}
      />
      {canMove && (
        <MoveToEcosystemDialog
          meta={meta}
          rowIds={moveIds}
          open={movingOpen}
          onClose={() => setMovingOpen(false)}
          onMoved={() => {
            setSelected(new Set())
            void resource.refresh()
          }}
        />
      )}
    </div>
  )
}

interface RowListProps {
  meta: CrudTableMeta
  rows: CrudRow[]
  /** Create drafts (synthetic keys), rendered below the server rows. */
  draftKeys: string[]
  /** Staged edits — the source of a draft row's displayed cell values. */
  edits: Record<string, CrudDraft>
  /** What every draft starts from (the view's `createDefaults`), under its staged edits. */
  draftBaseline: CrudDraft
  loading: boolean
  error: string | null
  activeKey: string | null
  onSelect: (key: string) => void
  /** Whether the viewer may write this table. False drops the whole leading checkbox column:
   *  the checkbox exists to feed Delete / Move, both of which are gone, so it would be a
   *  control with nothing to act on. Same flag, same spelling, as RowDetails' — inverting it
   *  per child is how the two drift. */
  canWrite: boolean
  /** Server rowKeys checked for deletion. */
  selected: Set<string>
  allSelected: boolean
  onToggleSelect: (key: string, checked: boolean) => void
  onToggleSelectAll: (checked: boolean) => void
}

/** The top pane: a leading select-for-delete checkbox column (writable tables only), then
 *  every column on a single full-width line (resizable headers), long cells truncated with
 *  the full value on hover. Server rows first, then create drafts (marked "new").
 *  Clicking or pressing Enter/Space on a row makes it the active row the detail
 *  pane edits (keyless rows are non-interactive — they can't be addressed). */
function RowList({
  meta,
  rows,
  draftKeys,
  draftBaseline,
  edits,
  loading,
  error,
  activeKey,
  onSelect,
  canWrite,
  selected,
  allSelected,
  onToggleSelect,
  onToggleSelectAll,
}: RowListProps) {
  const columns = meta.columns
  // Per-column widths (px), set by dragging a header divider. Columns left unset
  // share the remaining width evenly (table-fixed). Local to the list — purely
  // presentational, no bearing on the edit/save model.
  const [colWidths, setColWidths] = useState<Record<string, number>>({})
  const setColWidth = useCallback(
    (name: string, width: number) => setColWidths((prev) => ({ ...prev, [name]: width })),
    [],
  )

  if (loading) {
    return (
      <div className="flex justify-center py-8">
        <Spinner />
      </div>
    )
  }

  const draftCount = draftKeys.length

  return (
    <div className="flex min-w-0 flex-col gap-2 p-2">
      <div className="flex items-center justify-between px-1">
        <span className="font-mono text-[0.7rem] text-apt-text-dim">
          {`${rows.length} row${rows.length === 1 ? '' : 's'}`}
          {draftCount > 0 ? ` · ${draftCount} new` : ''}
        </span>
      </div>
      <ErrorText error={error} />
      {rows.length === 0 && draftCount === 0 && !error ? (
        <p className="py-8 text-center font-mono text-sm text-apt-text-dim" role="status">
          No rows yet.
        </p>
      ) : (
        // `table-fixed` so columns share the width evenly and per-cell `truncate`
        // can clip; explicit header widths (drag to resize) override that share.
        <table className="w-full table-fixed text-left text-sm">
          <thead>
            <tr className="border-b border-apt-border">
              {canWrite && (
                <th style={{ width: 36 }} className="px-2 py-2 align-middle">
                  <Checkbox
                    checked={allSelected}
                    disabled={rows.length === 0}
                    aria-label="Select all rows"
                    onCheckedChange={(checked) => onToggleSelectAll(checked === true)}
                  />
                </th>
              )}
              {columns.map((column) => (
                <ColumnHeader
                  key={column.name}
                  name={column.name}
                  width={colWidths[column.name]}
                  onResize={setColWidth}
                />
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => {
              const key = rowKey(meta, row)
              const interactive = key !== ''
              return (
                <ServerRow
                  // Namespaced + index-fallback so a keyless row can never collide
                  // with a real key (e.g. a pk value of "0" vs. index 0).
                  key={`server:${interactive ? key : `idx-${index}`}`}
                  columns={columns}
                  row={row}
                  rowId={interactive ? key : String(index + 1)}
                  cellKey={key}
                  interactive={interactive}
                  active={interactive && key === activeKey}
                  canWrite={canWrite}
                  selected={selected.has(key)}
                  onSelect={onSelect}
                  onToggleSelect={onToggleSelect}
                />
              )
            })}
            {draftKeys.map((key) => {
              const isActive = key === activeKey
              const buffer = edits[key]
              return (
                <tr
                  key={`draft:${key}`}
                  onClick={() => onSelect(key)}
                  onKeyDown={(event) => activateOnKey(event, () => onSelect(key))}
                  tabIndex={0}
                  aria-current={isActive || undefined}
                  className={
                    'cursor-pointer border-b border-apt-border/50 last:border-b-0 outline-none focus-visible:bg-apt-surface ' +
                    (isActive ? 'bg-apt-surface-2' : 'hover:bg-apt-surface')
                  }
                >
                  {/* The drafts' counterpart to the checkbox column — dropped with it so the
                      table stays rectangular. (A read-only table has no drafts to begin with,
                      since Create is gone.) */}
                  {canWrite && (
                    <td className="px-2 py-1.5 align-middle">
                      <span className="font-mono text-[0.6rem] uppercase tracking-wider text-apt-gold">
                        new
                      </span>
                    </td>
                  )}
                  {columns.map((column) => {
                    // The seeded values (a bucket's ecosystem) are the row's values too, and a
                    // server-managed column is filled in on save — so neither reads as a blank
                    // "—" the user might think they forgot (Mike, 2026-09-24: "the row is missing
                    // a ton of things that should be there").
                    const text = formatCellDisplay(
                      buffer?.[column.name] ?? draftBaseline[column.name],
                    )
                    return (
                      <td
                        key={column.name}
                        title={text || undefined}
                        className="truncate px-3 py-1.5 font-mono text-xs text-apt-text"
                      >
                        {text ||
                          (column.serverManaged ? (
                            <span className="italic text-apt-text-dim">auto</span>
                          ) : (
                            <span className="text-apt-text-dim">—</span>
                          ))}
                      </td>
                    )
                  })}
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
    </div>
  )
}

/** Enter/Space activates a click-only element for keyboard users. */
function activateOnKey(event: KeyboardEvent<HTMLElement>, action: () => void) {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault()
    action()
  }
}

/** One server row, memoised so a detail-pane keystroke (which changes only `edits`)
 *  doesn't reconcile every row — it re-renders only when its own row/active/selected
 *  props change. Keyless rows render non-interactive (no click/keyboard/selection). */
const ServerRow = memo(function ServerRow({
  columns,
  row,
  rowId,
  cellKey,
  interactive,
  active,
  canWrite,
  selected,
  onSelect,
  onToggleSelect,
}: {
  columns: CrudColumn[]
  row: CrudRow
  rowId: string
  cellKey: string
  interactive: boolean
  active: boolean
  canWrite: boolean
  selected: boolean
  onSelect: (key: string) => void
  onToggleSelect: (key: string, checked: boolean) => void
}) {
  return (
    <tr
      onClick={interactive ? () => onSelect(cellKey) : undefined}
      onKeyDown={interactive ? (event) => activateOnKey(event, () => onSelect(cellKey)) : undefined}
      tabIndex={interactive ? 0 : undefined}
      aria-current={active || undefined}
      className={
        'border-b border-apt-border/50 last:border-b-0 outline-none ' +
        (interactive ? 'cursor-pointer focus-visible:bg-apt-surface ' : '') +
        (active ? 'bg-apt-surface-2' : interactive ? 'hover:bg-apt-surface' : '')
      }
    >
      {/* The checkbox is its own click target — selecting a row for deletion must
          not also make it the active detail row. */}
      {canWrite && (
        <td className="px-2 py-1.5 align-middle" onClick={(event) => event.stopPropagation()}>
          <Checkbox
            checked={selected}
            disabled={!interactive}
            aria-label={`Select row ${rowId}`}
            onCheckedChange={(checked) => onToggleSelect(cellKey, checked === true)}
          />
        </td>
      )}
      {columns.map((column) => {
        const text = formatCellDisplay(row[column.name])
        return (
          <td
            key={column.name}
            title={text || undefined}
            className="truncate px-3 py-1.5 font-mono text-xs text-apt-text"
          >
            {text || <span className="text-apt-text-dim">—</span>}
          </td>
        )
      })}
    </tr>
  )
})

/** A column header with a draggable right-edge divider that resizes the column.
 *  The drag updates the width live via the DOM (no React state per pointermove, so
 *  the row list isn't re-rendered every pixel); the final width lands in state on
 *  pointer-up. Arrow keys resize it too (Shift = larger stride). */
function ColumnHeader({
  name,
  width,
  onResize,
}: {
  name: string
  width?: number
  onResize: (name: string, width: number) => void
}) {
  const thRef = useRef<HTMLTableCellElement>(null)
  const dragging = useRef(false)
  const startX = useRef(0)
  const startWidth = useRef(0)
  const liveWidth = useRef(0)

  function onPointerDown(e: PointerEvent<HTMLSpanElement>) {
    // Don't let the drag start a text selection or bubble to the header row.
    e.preventDefault()
    e.stopPropagation()
    dragging.current = true
    startX.current = e.clientX
    startWidth.current = thRef.current?.getBoundingClientRect().width ?? MIN_COL_WIDTH
    liveWidth.current = startWidth.current
    e.currentTarget.setPointerCapture(e.pointerId)
  }
  function onPointerMove(e: PointerEvent<HTMLSpanElement>) {
    if (!dragging.current) return
    const next = Math.max(MIN_COL_WIDTH, startWidth.current + (e.clientX - startX.current))
    liveWidth.current = next
    // Live DOM write only — committing to state on every move would re-render the
    // whole list each pixel. The commit happens once, on pointer-up.
    if (thRef.current) thRef.current.style.width = `${next}px`
  }
  function onPointerUp(e: PointerEvent<HTMLSpanElement>) {
    if (!dragging.current) return
    dragging.current = false
    e.currentTarget.releasePointerCapture?.(e.pointerId)
    onResize(name, liveWidth.current)
  }
  function adjust(delta: number) {
    const current = width ?? thRef.current?.getBoundingClientRect().width ?? MIN_COL_WIDTH
    onResize(name, Math.max(MIN_COL_WIDTH, Math.round(current + delta)))
  }
  function onKeyDown(e: KeyboardEvent<HTMLSpanElement>) {
    if (e.key === 'ArrowLeft') {
      e.preventDefault()
      adjust(e.shiftKey ? -COL_STEP_LARGE : -COL_STEP)
    } else if (e.key === 'ArrowRight') {
      e.preventDefault()
      adjust(e.shiftKey ? COL_STEP_LARGE : COL_STEP)
    }
  }

  return (
    <th
      ref={thRef}
      title={name}
      style={width ? { width } : undefined}
      className="relative px-3 py-2 font-mono text-[0.7rem] font-medium uppercase tracking-wider text-apt-text-muted"
    >
      <span className="block truncate pr-2">{name}</span>
      <span
        role="separator"
        aria-orientation="vertical"
        aria-label={`Resize ${name} column`}
        tabIndex={0}
        onKeyDown={onKeyDown}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        className="group absolute inset-y-0 right-0 flex w-2 cursor-col-resize touch-none items-stretch justify-center outline-none focus-visible:bg-apt-gold/30"
      >
        <span className="pointer-events-none w-px bg-apt-border group-hover:bg-apt-border-strong" />
      </span>
    </th>
  )
}

interface RowDetailsProps {
  meta: CrudTableMeta
  /** The view's `createDefaults`, serialized: those columns are fixed by the surface and hidden. */
  pinned: string
  /** The active row's baseline values as a draft buffer, or null when no row. */
  baseline: CrudDraft | null
  /** 'create' for an unsaved draft (createOnly columns editable), else 'edit'. */
  mode: EditableMode
  /** Whether the viewer may write this table. False locks EVERY column, whatever its own
   *  editability says — a viewer-level veto over the schema-level rule, kept as a separate
   *  gate because the two answer different questions (who is asking vs. what the column is). */
  canWrite: boolean
  /** Dirty edits for the active row (col → value), or undefined when clean. */
  edits: CrudDraft | undefined
  onEdit: (name: string, value: string | boolean) => void
}

/**
 * The bottom pane BODY: the active row as a column:value list. Editable columns
 * (per {@link isColumnEditable} in the active mode) render the shared
 * {@link CrudFieldInput} — its `<label htmlFor>` naming the column — writing into
 * the parent's per-row dirty-edits buffer; relational / locked columns render as
 * plain, visibly read-only text. Server-managed columns are hidden here (they stay
 * in the top row list). The row identity + the collapse disclosure live on the
 * split's header bar (CrudDataView passes them), not here.
 */
function RowDetails({ meta, pinned, baseline, mode, canWrite, edits, onEdit }: RowDetailsProps) {
  const bodyId = useId()

  if (!baseline) {
    return (
      <p className="p-4 font-mono text-xs text-apt-text-dim" role="status">
        Select a row to see its details.
      </p>
    )
  }
  const pinnedNames = Object.keys(JSON.parse(pinned) as Record<string, string>)
  const columns = meta.columns.filter(
    (column) => !isColumnHidden(column) && !pinnedNames.includes(column.name),
  )

  return (
    <div className="flex min-w-0 flex-col">
      <dl className="flex flex-col gap-2.5 px-4 py-4">
        {columns.map((column) => {
          const editable = canWrite && isColumnEditable(meta, column, mode)
          const value = edits?.[column.name] ?? baseline[column.name]
          const fieldId = `${bodyId}-${column.name}`
          return (
            <div key={column.name} className="flex min-w-0 flex-col gap-1">
              <dt className={fieldCaptionClass}>
                {editable ? <label htmlFor={fieldId}>{column.name}</label> : column.name}
              </dt>
              <dd className="min-w-0">
                {editable ? (
                  <CrudFieldInput
                    id={fieldId}
                    column={column}
                    value={value}
                    onChange={(next) => onEdit(column.name, next)}
                  />
                ) : (
                  <ReadOnlyValue value={value} />
                )}
              </dd>
            </div>
          )
        })}
      </dl>
    </div>
  )
}

/** A locked column's value as plain, visibly non-editable text — truncated with
 *  the full value on hover, an em dash when empty. Shares {@link formatCellDisplay}
 *  with the row list so a read-only cell reads the same in both panes. */
function ReadOnlyValue({ value }: { value: string | boolean | undefined }) {
  const text = formatCellDisplay(value)
  return (
    <p className="truncate font-mono text-xs text-apt-text-dim" title={text || undefined}>
      {text || <span className="text-apt-text-dim">—</span>}
    </p>
  )
}
