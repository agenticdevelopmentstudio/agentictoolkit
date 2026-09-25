'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { authedJson, authedRequest } from '@agentic-toolkit/auth/client'
import { errorMessage } from '@agenticdevelopertoolkit/ui/lib/errors'
import type { CrudRow, CrudTableMeta } from './types'

/** Every site mounts its BFF proxy at /api (stripped on forward). */
const API_BASE = '/api'

/** Substitute a row's primary-key values into the table's item path template,
 *  e.g. '/persona/personas/{id}' + the row. */
export function itemUrl(meta: CrudTableMeta, row: CrudRow): string {
  let path = meta.itemPath
  for (const param of meta.pkParams) {
    path = path.replace(`{${param}}`, encodeURIComponent(String(row[param] ?? '')))
  }
  return `${API_BASE}${path}`
}

/** A row's primary key as one string — the same per-part escaping as itemUrl,
 *  so a '/' inside a composite-key value can't collide with the separator.
 *  Empty ('') when a single-pk row carries no value. */
export function rowKey(meta: CrudTableMeta, row: CrudRow): string {
  return meta.pkParams.map((param) => encodeURIComponent(String(row[param] ?? ''))).join('/')
}

/** The scope override every verb carries (see {@link useCrudResource}); empty means "none". */
function scopeQueryOf(scopeEcosystemId?: string): string {
  return scopeEcosystemId ? `ecosystemId=${encodeURIComponent(scopeEcosystemId)}` : ''
}

/** The URL {@link useCrudResource} lists `meta`'s rows from under `filter` and `scopeEcosystemId`.
 *  Exported so a caller asking something of the SAME list — All Data's has-rows probe — sends
 *  exactly the URL the open view would, rather than a second copy of it that can drift. */
export function listUrl(
  meta: CrudTableMeta,
  filter?: Record<string, string>,
  scopeEcosystemId?: string,
): string {
  const filterQuery =
    filter && Object.keys(filter).length > 0 ? new URLSearchParams(filter).toString() : ''
  const query = [scopeQueryOf(scopeEcosystemId), filterQuery].filter(Boolean).join('&')
  return `${API_BASE}${meta.basePath}${query ? `?${query}` : ''}`
}

export interface CrudResource {
  rows: CrudRow[]
  /** Nothing to show YET — true until a list lands for the CURRENT table + filter, so a re-list of
   *  the same one keeps its rows on screen instead of flashing while a switch to a different one
   *  does not leave the previous table's rows standing. Drive a table's skeleton with this. */
  loading: boolean
  /** A list call is OPEN, whether or not there are rows already. The one to report upward with
   *  `useReportBusy`: `loading` is false for every re-list of a list already on screen, which is
   *  exactly the read a spinner in front of the list's title exists to show. */
  fetching: boolean
  error: string | null
  refresh: () => Promise<void>
  /** Mutations throw on failure (the caller renders the message inline) and
   *  re-list on success. */
  create: (values: CrudRow) => Promise<void>
  update: (row: CrudRow, values: CrudRow) => Promise<void>
  remove: (row: CrudRow) => Promise<void>
  /** Raw mutators — the same authed PUT/POST/DELETE as create/update/remove but
   *  WITHOUT the trailing re-list, so a batch save (the split editor) can issue
   *  many writes and refresh ONCE at the end. Throw on failure like their
   *  re-listing wrappers. */
  createRow: (values: CrudRow) => Promise<CrudRow>
  updateRow: (row: CrudRow, values: CrudRow) => Promise<CrudRow>
  removeRow: (row: CrudRow) => Promise<void>
}

/** List/create/update/delete one generic-CRUD table through the site's /api
 *  BFF proxy, authenticated by the shared Bearer client. `filter` narrows the LIST
 *  call (column-equality query params the backend list route ANDs with the
 *  ecosystem scope) — except its `workspace`, which is a SCOPE, not a column: it
 *  rides every write too, because the backend reads `?workspace=` on POST/PUT/DELETE
 *  as the owner a create is stamped with and the scope an edit is allowed in. Sent on
 *  the list alone, All Data's workspace view listed an org's rows and then created
 *  under the caller and refused edits to rows another member made (Mike, 2026-09-25). `scopeEcosystemId` names the target
 *  ecosystem on EVERY verb (`?ecosystemId=` — the backend's ecosystem-param scope
 *  override for the integration synced-data tables, authorized server-side against
 *  the ecosystems the caller manages); without it the backend scopes to the caller's
 *  JWT ecosystem. `error` reflects the list call only; mutation errors are thrown to
 *  the caller. */
export function useCrudResource(
  meta: CrudTableMeta,
  filter?: Record<string, string>,
  scopeEcosystemId?: string,
): CrudResource {
  const [rows, setRows] = useState<CrudRow[]>([])
  // The one stored flag: a list call is OPEN. `loading` is DERIVED from it below rather than stored
  // alongside it — the two answer different questions but can never legally disagree about whether
  // a request is in flight, and two `useState`s updated at four sites apiece is four chances for
  // them to drift.
  const [fetching, setFetching] = useState(true)
  const [error, setError] = useState<string | null>(null)
  // The scopes ride every write's URL; empty string means "none". (The list sends them in
  // `listUrl`, the ecosystem one there alongside the filter.)
  const workspace = filter?.workspace
  const scopeQuery = [
    scopeQueryOf(scopeEcosystemId),
    workspace ? `workspace=${encodeURIComponent(workspace)}` : '',
  ]
    .filter(Boolean)
    .join('&')
  // Guards against out-of-order responses: switching tables (a new `meta` on a
  // live hook) starts a new list call while the old one may still be in
  // flight — only the LATEST call may write state, or a slow stale response
  // would overwrite the new table's rows.
  const listSeq = useRef(0)
  // WHICH list the rows on screen came from — not merely whether some list has landed. `loading`
  // blocks the UI (the table swaps to a skeleton), and suppressing it for a re-list of the SAME
  // list is the point: a post-mutation re-list keeps the current rows rendered instead of flashing,
  // and a failed background refresh shows its error next to the stale rows, which is accepted.
  // Switching table or filter is not that case — nothing has loaded for the new list, and a
  // mount-scoped "has loaded" boolean would suppress the skeleton anyway and leave the PREVIOUS
  // table's rows sitting under the new table's header until its list lands.
  // The list's URL is that identity. Serialized once, so an inline `filter={{…}}` literal doesn't
  // change identity every render and re-trigger the list effect.
  const listId = listUrl(meta, filter, scopeEcosystemId)
  const loadedFor = useRef<string | null>(null)

  const refresh = useCallback(async () => {
    const seq = ++listSeq.current
    setFetching(true)
    setError(null)
    try {
      const fetched = await authedJson<CrudRow[]>(listId)
      if (seq !== listSeq.current) return
      loadedFor.current = listId
      setRows(fetched)
    } catch (err) {
      if (seq !== listSeq.current) return
      setError(errorMessage(err))
    } finally {
      // Guarded by the same sequence check as the writes above: a superseded call must not report
      // that the list it was overtaken by has finished.
      if (seq === listSeq.current) setFetching(false)
    }
  }, [meta, listId])

  // Nothing to show YET: a call is open and no answer for THIS list has arrived. Derived, so it
  // cannot be raised, lowered or forgotten independently of `fetching` — every branch that opens or
  // closes a request already moves the one flag it reads.
  const loading = fetching && loadedFor.current !== listId

  useEffect(() => {
    void refresh()
  }, [refresh])

  // Raw mutators (no re-list) — the single home for the authed POST/PUT/DELETE
  // shape, reused by both the re-listing wrappers below and the split editor's
  // batch save (which refreshes once after all writes).
  const createRow = useCallback(
    (values: CrudRow) =>
      authedJson<CrudRow>(`${API_BASE}${meta.basePath}${scopeQuery ? `?${scopeQuery}` : ''}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values),
      }),
    [meta, scopeQuery],
  )

  const updateRow = useCallback(
    (row: CrudRow, values: CrudRow) =>
      authedJson<CrudRow>(`${itemUrl(meta, row)}${scopeQuery ? `?${scopeQuery}` : ''}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values),
      }),
    [meta, scopeQuery],
  )

  const removeRow = useCallback(
    // DELETE answers 204 No Content — authedRequest, not authedJson.
    async (row: CrudRow) => {
      await authedRequest(`${itemUrl(meta, row)}${scopeQuery ? `?${scopeQuery}` : ''}`, {
        method: 'DELETE',
      })
    },
    [meta, scopeQuery],
  )

  const create = useCallback(
    async (values: CrudRow) => {
      await createRow(values)
      await refresh()
    },
    [createRow, refresh],
  )

  const update = useCallback(
    async (row: CrudRow, values: CrudRow) => {
      await updateRow(row, values)
      await refresh()
    },
    [updateRow, refresh],
  )

  const remove = useCallback(
    async (row: CrudRow) => {
      await removeRow(row)
      await refresh()
    },
    [removeRow, refresh],
  )

  return {
    rows,
    loading,
    fetching,
    error,
    refresh,
    create,
    update,
    remove,
    createRow,
    updateRow,
    removeRow,
  }
}
