'use client'

import { useEffect, useState } from 'react'
import { authedJson } from '@agentic-toolkit/auth/client'
import type { CrudTableMeta } from './types'

/** Every site mounts its BFF proxy at /api (stripped on forward) — same base as useCrudResource. */
const API_BASE = '/api'

/** How many probes are in flight at once: a scoped All Data probes every scopable table, and
 *  opening it should not put dozens of requests on the wire in one burst. */
const PROBE_CONCURRENCY = 8

/**
 * Which of `tables` hold at least one row under `filter` — the keys of the non-empty ones, or
 * `null` while the answer is still coming (and whenever `filter` is null, which disables it).
 *
 * "In All Data only show tables and schemas in the list with data in them" (Mike, 2026-09-24).
 * Each probe is the table's OWN list route with the SAME filter the open view sends, plus
 * `limit=1` — so "has data" is answered by exactly the authorization and scoping that would
 * serve the rows, rather than by a second counting path that could disagree with it. A probe
 * that fails (a 403, a table the backend cannot list) counts as empty: a table that cannot show
 * this viewer a row has nothing to offer them in the rail.
 */
export function useTablesWithRows(
  tables: CrudTableMeta[],
  filter: Record<string, string> | null,
): Set<string> | null {
  const [populated, setPopulated] = useState<Set<string> | null>(null)
  // Content signatures, not identities: callers derive both per render.
  const tablesSig = tables.map((t) => t.key).join('|')
  const filterSig = filter ? JSON.stringify(filter) : null

  useEffect(() => {
    setPopulated(null)
    if (filterSig === null) return
    let live = true
    const query = new URLSearchParams({ ...JSON.parse(filterSig), limit: '1' }).toString()
    const queue = [...tables]
    const found = new Set<string>()
    const worker = async () => {
      for (let t = queue.shift(); t; t = queue.shift()) {
        try {
          const rows = await authedJson<unknown[]>(`${API_BASE}${t.basePath}?${query}`)
          if (Array.isArray(rows) && rows.length > 0) found.add(t.key)
        } catch {
          // Counted as empty — see the docblock.
        }
      }
    }
    void Promise.all(Array.from({ length: PROBE_CONCURRENCY }, worker)).then(() => {
      if (live) setPopulated(found)
    })
    return () => {
      live = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- keyed on the signatures above
  }, [tablesSig, filterSig])

  return populated
}
