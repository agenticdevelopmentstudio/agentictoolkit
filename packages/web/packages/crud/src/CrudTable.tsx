'use client'

import { Badge } from '@agenticdevelopertoolkit/ui/components/badge'
import { Button } from '@agenticdevelopertoolkit/ui/components/button'
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner'
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text'
import { rowKey } from './useCrudResource'
import type { CrudColumn, CrudRow, CrudTableMeta } from './types'
import { cn } from '@agenticdevelopertoolkit/ui/lib/utils'
import { fieldCaptionClass } from '@agenticdevelopertoolkit/ui/lib/typography'

const MAX_COLUMNS = 6
const MAX_CELL_CHARS = 80

/** The columns shown in the list: primary key(s) first, then the remaining
 *  scalar columns up to the cap. Object/array columns are form-only. */
export function displayColumns(meta: CrudTableMeta): CrudColumn[] {
  const pk = meta.columns.filter((c) => meta.pkParams.includes(c.name))
  const scalars = meta.columns.filter(
    (c) => !meta.pkParams.includes(c.name) && c.type !== 'object' && c.type !== 'array',
  )
  return [...pk, ...scalars].slice(0, MAX_COLUMNS)
}

export function cellText(row: CrudRow, column: CrudColumn): string {
  const value = row[column.name]
  if (value == null) return '—'
  const text = typeof value === 'string' ? value : JSON.stringify(value)
  return text.length > MAX_CELL_CHARS ? `${text.slice(0, MAX_CELL_CHARS)}…` : text
}

export interface CrudTableProps {
  meta: CrudTableMeta
  rows: CrudRow[]
  loading: boolean
  error: string | null
  /** Whether the viewer may write this table (see `canWriteTable`). False drops New and Delete
   *  and turns Edit into View — the backend refuses those writes, so offering them is offering
   *  a 403. Required, not defaulted: a caller that hasn't decided must not silently get the
   *  permissive answer. */
  canWrite: boolean
  onNew: () => void
  /** Opens the row — for editing when `canWrite`, else read-only. */
  onEdit: (row: CrudRow) => void
  onDelete: (row: CrudRow) => void
  /** Why a read-only table is read-only, in the viewer's terms. Defaults to the shared-platform
   *  reason, which is the generated tables' only one; a hand-fed table (a bucket's papers) has
   *  its own. */
  readOnlyNote?: string
}

/** Placeholder-grade row list for one table: no sorting/search/pagination (the
 *  backend caps lists at 500); per-row Edit/Delete and a New action. */
export function CrudTable({
  meta,
  rows,
  loading,
  error,
  canWrite,
  onNew,
  onEdit,
  onDelete,
  readOnlyNote = 'Shared platform data — only an administrator can change it.',
}: CrudTableProps) {
  const columns = displayColumns(meta)
  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <span className="font-mono text-[0.7rem] text-apt-text-dim">
          {loading ? 'Loading…' : `${rows.length} row${rows.length === 1 ? '' : 's'}`}
        </span>
        {canWrite ? (
          <Button size="sm" onClick={onNew}>
            New
          </Button>
        ) : (
          // Name the state rather than just losing the button — and say why, in visible text
          // (a `title` tooltip reaches neither a screen reader nor a touch device).
          <span className="flex items-center gap-2">
            <Badge variant="neutral">Read-only</Badge>
            <span className="text-xs text-apt-text-dim">{readOnlyNote}</span>
          </span>
        )}
      </div>
      <ErrorText error={error} />
      {loading ? (
        <div className="flex justify-center py-8">
          <Spinner />
        </div>
      ) : rows.length === 0 && !error ? (
        <p className="py-8 text-center font-mono text-sm text-apt-text-dim">No rows yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-apt-border">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-apt-border">
                {columns.map((column) => (
                  <th
                    key={column.name}
                    className={cn(fieldCaptionClass, "px-3 py-2 font-medium")}
                  >
                    {column.name}
                  </th>
                ))}
                <th className="px-3 py-2" aria-label="Row actions" />
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <tr
                  key={rowKey(meta, row) || index}
                  className="border-b border-apt-border/50 last:border-b-0"
                >
                  {columns.map((column) => (
                    <td key={column.name} className="px-3 py-2 text-apt-text">
                      {cellText(row, column)}
                    </td>
                  ))}
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    <Button variant="ghost" size="sm" onClick={() => onEdit(row)}>
                      {canWrite ? 'Edit' : 'View'}
                    </Button>
                    {canWrite && (
                      <Button variant="ghost" size="sm" onClick={() => onDelete(row)}>
                        Delete
                      </Button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
