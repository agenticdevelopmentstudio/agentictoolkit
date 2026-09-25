'use client'

import { useEffect, useState } from 'react'
import {
  authedJson,
  AuthHttpError,
  onSessionChange,
  readTokenSubject,
} from '@agentic-toolkit/auth/client'
import { listUrl } from './useCrudResource'
import type { CrudTableMeta } from './types'

/** How many probes are in flight at once: a scoped All Data probes every scopable table, and
 *  opening it should not put dozens of requests on the wire in one burst. */
const PROBE_CONCURRENCY = 8

/** What the has-rows sweep found. */
export interface TablesWithRows {
  /** The keys of the tables holding at least one row, or `null` while the answer is still coming
   *  (and whenever the filter is null, which disables the sweep). */
  populated: Set<string> | null
  /** Some probe failed for a reason that says nothing about the table's rows (a 5xx, a 429, a
   *  dropped connection), so `populated` may be missing tables that DO hold rows. */
  failed: boolean
  /** While `populated` is still `null`: the `first` table (see {@link TablesWithRowsOptions}) once
   *  its own probe has found a row, so the table the viewer opened can mount without waiting on
   *  the rest of the sweep. `null` before that, and in every finished answer. */
  firstWithRows: string | null
}

export interface TablesWithRowsOptions {
  /** The open view's `scopeEcosystemId`, so that each probe is the very list the view would send. */
  scopeEcosystemId?: string
  /** The key of the table the viewer has open. It is probed ahead of the rest, and reported as
   *  `firstWithRows` the moment its probe finds a row. */
  first?: string | null
}

/** The one "no answer yet" object, returned whenever there is none. */
const PENDING: TablesWithRows = { populated: null, failed: false, firstWithRows: null }

/**
 * The last good answer of every sweep, by filter + scope + tables. Module scope, because the
 * browser does not outlive a click: on the standalone /<ws>/all-data route every schema or table
 * click remounts it (the App Router keys the `[[...table]]` subtree by its segment, and without
 * `cacheComponents` it keeps a single back/forward entry), and a stack group renders only its
 * active member, so leaving Storage ▸ All Data and coming back remounts it too. Held in component
 * state, the answer died with each mount: every click blanked the rail and the pane to
 * "Loading…" and swept again — 61 probes for a workspace — before the table's own list started.
 *
 * A remembered answer is SHOWN at once and then REVALIDATED: the sweep still runs, quietly, and
 * replaces it when it ends. Serving it without asking again kept a table that gained its first
 * row elsewhere (a note written, a bucket created) out of the rail until the page reloaded —
 * "only tables with data", broken for the very table the viewer had just filled. An answer lives
 * until the signed-in principal changes (see {@link watchSession}) or the page reloads. A FAILED
 * sweep is never kept: with nothing remembered, the rail says it couldn't load and coming back
 * asks again, which is what its "Try again" asks of the viewer; with an answer on screen, that
 * answer stays rather than being replaced by a partial one.
 */
const answers = new Map<string, TablesWithRows>()
/** The principal `answers` were collected for. */
let answersFor: string | null = null
/** Bumped by every clear, so a sweep that was already running cannot write its answer back in. */
let generation = 0
let watching = false

/**
 * Empty `answers` the moment the signed-in principal changes — data/src/query's guard on its own
 * module-scope client, for its reason: the map survives a sign-out and the next sign-in, and its
 * keys (a workspace slug, an ecosystem id) are shared by every member of that workspace, so the
 * next person to sign in on this machine would be shown the previous one's rail. The SUBJECT and
 * not the raw token, since a refresh writes a new token for the same user every time it runs;
 * `storage` covers the same swap performed in another tab. Bound by the first sweep, so nothing
 * depends on a module-level side effect.
 */
function watchSession(): void {
  if (watching || typeof window === 'undefined') return
  watching = true
  answersFor = readTokenSubject()
  const check = () => {
    const subject = readTokenSubject()
    if (subject === answersFor) return
    answersFor = subject
    answers.clear()
    generation += 1
  }
  onSessionChange(check)
  window.addEventListener('storage', check)
}

/** Forget every answer. For tests: module state outlives a `render()`, so two tests with the same
 *  filter and tables would otherwise read each other's answer. */
export function resetTablesWithRows(): void {
  answers.clear()
  generation += 1
}

/**
 * Which of `tables` hold at least one row under `filter` — see {@link TablesWithRows}.
 *
 * "In All Data only show tables and schemas in the list with data in them" (Mike, 2026-09-24).
 * Each probe is the table's OWN list — {@link listUrl}, with the SAME filter and scope the open
 * view sends — plus `limit=1`, so "has data" is answered by exactly the authorization and scoping
 * that would serve the rows, rather than by a second counting path that could disagree with it. A
 * probe refused with a 403 (this viewer may not list the table) or a 404 (the backend has no such
 * list for them) counts as empty: a table that cannot show this viewer a row has nothing to offer
 * them in the rail. Any other failure is NOT an answer about the rows, so it marks the sweep
 * `failed` instead — counting every failure as empty hid tables that hold rows, and when every
 * probe failed the rail said "No data yet." about a scope full of data.
 *
 * A remembered answer (see `answers` above) is returned from the first render and revalidated
 * behind it. Otherwise the `first` table goes to the head of the queue: the viewer who
 * deep-linked or clicked a table is waiting on THAT table, which used to wait for the whole sweep
 * before its own list could start.
 *
 * Leaving mid-sweep (an unmount, or a scope change) aborts the probes in flight and drops the
 * queued ones. The workers used to drain the whole queue for an answer nobody would read, and a
 * remount's sweep then overlapped the orphaned one, breaking the {@link PROBE_CONCURRENCY} bound
 * (StrictMode's dev double-mount probed every table twice).
 */
export function useTablesWithRows(
  tables: CrudTableMeta[],
  filter: Record<string, string> | null,
  { scopeEcosystemId, first = null }: TablesWithRowsOptions = {},
): TablesWithRows {
  // Content signatures, not identities: callers derive both per render.
  const tablesSig = tables.map((t) => t.key).join('|')
  const filterSig = filter ? JSON.stringify(filter) : null
  // Everything a probe's URL is built from, so one key names one sweep's answer.
  const key = filterSig === null ? null : `${filterSig}|${scopeEcosystemId ?? ''}|${tablesSig}`
  // This mount's answer, tagged with the key it answers. A remembered one seeds it.
  const [swept, setSwept] = useState<{ key: string; answer: TablesWithRows } | null>(() => {
    const known = key === null ? undefined : answers.get(key)
    return key !== null && known ? { key, answer: known } : null
  })

  useEffect(() => {
    if (key === null || filterSig === null) return
    watchSession()
    const known = answers.get(key)
    if (known) {
      // Remembered: shown with no blanking, and revalidated by the sweep below. Held in state as
      // well, so a clear of `answers` while it is on screen (a sign-in in another tab) cannot
      // strand the rail on "Loading…".
      setSwept((prev) => (prev?.key === key ? prev : { key, answer: known }))
    }
    const since = generation
    let live = true
    const controller = new AbortController()
    const scope = JSON.parse(filterSig) as Record<string, string>
    const queue = [...tables]
    const head = queue.findIndex((t) => t.key === first)
    if (head > 0) queue.unshift(...queue.splice(head, 1))
    const found = new Set<string>()
    let failed = false
    const worker = async () => {
      for (let t = queue.shift(); t; t = queue.shift()) {
        const list = listUrl(t, scope, scopeEcosystemId)
        const probe = `${list}${list.includes('?') ? '&' : '?'}limit=1`
        try {
          const rows = await authedJson<unknown[]>(probe, { signal: controller.signal })
          if (Array.isArray(rows) && rows.length > 0) {
            found.add(t.key)
            // Only a sweep with nothing on screen reports its first table early: over a remembered
            // answer, a `populated: null` answer would blank the rail it is quietly revalidating.
            if (live && !known && t.key === first) {
              setSwept({ key, answer: { populated: null, failed: false, firstWithRows: t.key } })
            }
          }
        } catch (err) {
          // Only a 403/404 counts as empty — see the docblock. The cleanup's abort lands here too,
          // and is never read: `live` is already false.
          if (!(err instanceof AuthHttpError && (err.status === 403 || err.status === 404))) {
            failed = true
          }
        }
      }
    }
    void Promise.all(Array.from({ length: PROBE_CONCURRENCY }, worker)).then(() => {
      if (!live) return
      // A failed revalidation leaves the remembered answer on screen: some tables' probes said
      // nothing, so this answer is partial, and the last good one is the better guess.
      if (failed && known) return
      const answer: TablesWithRows = { populated: found, failed, firstWithRows: null }
      // Neither a failed sweep nor one a change of principal overtook is kept.
      if (!failed && since === generation) answers.set(key, answer)
      setSwept({ key, answer })
    })
    return () => {
      live = false
      // Each worker stops at its next shift, and the probes in flight are cancelled.
      queue.length = 0
      controller.abort()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- keyed on `key`; `first` only orders the queue
  }, [key])

  if (key === null) return PENDING
  return swept?.key === key ? swept.answer : answers.get(key) ?? PENDING
}
