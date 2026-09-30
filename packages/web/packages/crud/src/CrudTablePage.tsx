'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { Button } from '@agenticdevelopertoolkit/ui/components/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog'
import { AlertModal } from '@agenticdevelopertoolkit/ui/components/alert-modal'
import { SectionHeader } from '@agenticdevelopertoolkit/ui/blocks/section-header'
import { railLinkVariants } from '@agenticdevelopertoolkit/ui/lib/nav-rail'
import { cn } from '@agenticdevelopertoolkit/ui/lib/utils'
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner'
import { CrudRecordForm } from './CrudRecordForm'
import { CrudTable } from './CrudTable'
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text'
import { useAction } from '@agenticdevelopertoolkit/ui/hooks/useAction'
import { canWriteTable, readableTables } from './exposure'
import { useViewer } from './viewer'
import { rowKey, useCrudResource } from './useCrudResource'
import type { CrudRow, CrudTableMeta } from './types'

type Editing = { mode: 'create' } | { mode: 'edit'; row: CrudRow } | null

export interface CrudTablePageProps {
  /** Feature title, e.g. 'Storage'. */
  title: string
  /** The tables this feature edits; must be non-empty. */
  tables: CrudTableMeta[]
  /** URL table segment (CrudTableMeta.table) of the active table; a bare
   *  route falls back to the first table, an unknown segment renders a
   *  notice (and marks no table current). */
  activeTable?: string
  /** The feature's route, e.g. '/storage' — table links are `${baseHref}/<table>`. */
  baseHref: string
}

/** A feature's placeholder workspace: a rail of the tables it edits and a
 *  metadata-driven CRUD surface for the active one. */
export function CrudTablePage({ title, tables, activeTable, baseHref }: CrudTablePageProps) {
  // The same exposure gate the /all-data browser applies, for the same reason: an admin-tier
  // table listed to a non-admin is a rail row (and a LIST request) whose only outcome is a 403.
  // Feature tables are usually all `owner`, so this is usually the identity — but `billing` is
  // catalog end to end, and `usage` is mixed.
  const { isAdmin: viewerIsAdmin, ready: viewerReady } = useViewer()
  const visible = useMemo(() => readableTables(tables, viewerIsAdmin), [tables, viewerIsAdmin])
  const requested =
    activeTable === undefined ? undefined : visible.find((t) => t.table === activeTable)
  // A bare route falls back to the first table; an EXPLICIT segment naming a table that isn't
  // there — unknown, or admin-only for this viewer — must not (silently editing a different
  // table than the URL names). It renders a notice instead, and nothing data-bearing mounts
  // (no authed fetch for a table the user didn't ask for, or may not read).
  const unavailableTable = activeTable !== undefined && requested === undefined
  const meta = unavailableTable ? undefined : requested ?? visible[0]

  // Hold until auth settles rather than render the rail as a non-admin and re-flow it.
  if (!viewerReady) {
    return (
      <div className="flex flex-1 items-center justify-center py-12">
        <Spinner />
      </div>
    )
  }

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-4 px-4 py-6 md:flex-row md:gap-6">
      <nav aria-label={`${title} tables`} className="shrink-0 md:w-56">
        <ul className="flex flex-row flex-wrap gap-1 md:flex-col">
          {visible.map((table) => (
            <li key={table.key}>
              <Link
                href={`${baseHref}/${table.table}`}
                aria-current={table.key === meta?.key ? 'page' : undefined}
                // The shared nav-rail grammar (matches the details-page rail),
                // with mono for the code-like table segment names.
                className={cn(railLinkVariants({ active: table.key === meta?.key }), 'font-mono')}
              >
                {table.table}
              </Link>
            </li>
          ))}
        </ul>
      </nav>
      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <SectionHeader paneTitle title={title} eyebrow={meta?.key} />
        {meta ? (
          // Keyed per table so a rail switch is a fresh mount (first-load
          // spinner, dialog/edit state reset) instead of a stale carry-over.
          <CrudTableSurface
            key={meta.key}
            meta={meta}
            canWrite={canWriteTable(meta, viewerIsAdmin)}
          />
        ) : visible.length === 0 ? (
          <p className="py-8 text-center font-mono text-sm text-apt-text-dim" role="status">
            No tables here are available to you.
          </p>
        ) : (
          // Deliberately one message for "no such table" and "not yours to open": the table
          // names are public in the API spec, so distinguishing them would buy nothing, and a
          // bare "unknown table" would be a lie in the second case.
          <p className="py-8 text-center font-mono text-sm text-apt-text-dim" role="status">
            No table “{activeTable}” here — pick one from the list.
          </p>
        )}
      </div>
    </div>
  )
}

/** The data-bearing half: owns the resource hook and the dialog state, so the
 *  unavailable-table notice never mounts it (rules of hooks keep it a separate
 *  component, not a branch). */
function CrudTableSurface({ meta, canWrite }: { meta: CrudTableMeta; canWrite: boolean }) {
  const resource = useCrudResource(meta)
  const [editing, setEditing] = useState<Editing>(null)
  const [deleting, setDeleting] = useState<CrudRow | null>(null)

  async function submit(values: CrudRow) {
    if (editing?.mode === 'edit') await resource.update(editing.row, values)
    else await resource.create(values)
    setEditing(null)
  }

  return (
    <>
      <CrudTable
        meta={meta}
        rows={resource.rows}
        loading={resource.loading}
        error={resource.error}
        canWrite={canWrite}
        onNew={() => setEditing({ mode: 'create' })}
        onEdit={(row) => setEditing({ mode: 'edit', row })}
        onDelete={(row) => setDeleting(row)}
      />

      <Dialog open={editing !== null} onOpenChange={(open) => !open && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {editing?.mode === 'edit'
                ? `${canWrite ? 'Edit' : 'View'} ${meta.table} row`
                : `New ${meta.table} row`}
            </DialogTitle>
          </DialogHeader>
          {editing && (
            <CrudRecordForm
              // Remount per session so the draft resets between rows/modes
              // (keyed by primary key — rows can hold multi-KB jsonb columns).
              key={editing.mode === 'edit' ? rowKey(meta, editing.row) : 'create'}
              meta={meta}
              initial={editing.mode === 'edit' ? editing.row : undefined}
              canWrite={canWrite}
              onSubmit={submit}
              onCancel={() => setEditing(null)}
            />
          )}
        </DialogContent>
      </Dialog>

      <DeleteConfirm
        // Keyed per target row (and reset when closed) so each open is a fresh
        // mount — otherwise this now-always-mounted component's useAction error
        // from a failed delete would linger and show on the NEXT row's confirm.
        key={deleting ? rowKey(meta, deleting) : 'closed'}
        open={deleting !== null}
        table={meta.table}
        onConfirm={async () => {
          if (deleting) await resource.remove(deleting)
          setDeleting(null)
        }}
        onCancel={() => setDeleting(null)}
      />
    </>
  )
}

/** The platform delete-confirm (shared AlertModal), with the mutation error
 *  surfaced in the description. */
function DeleteConfirm({
  open,
  table,
  onConfirm,
  onCancel,
}: {
  open: boolean
  table: string
  onConfirm: () => Promise<void>
  onCancel: () => void
}) {
  const { busy, error, run } = useAction()
  return (
    <AlertModal
      open={open}
      title={`Delete ${table} row?`}
      description={
        error ? <ErrorText error={error} /> : 'This permanently deletes the row.'
      }
      destructive
      confirmLabel="Delete"
      cancelLabel="Cancel"
      busy={busy}
      onConfirm={() => void run(onConfirm)}
      onCancel={onCancel}
    />
  )
}
