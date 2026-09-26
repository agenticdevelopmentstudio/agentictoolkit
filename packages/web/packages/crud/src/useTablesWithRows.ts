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

/**
 * How long a remembered answer counts as FRESH: a remount within this window serves it without
 * sweeping again. Revalidating on every remount put a full sweep (dozens of probes) on the wire
 * for every schema or table click — the answer was re-displayed, never re-used. Past the window
 * the answer is still shown at once, and revalidated behind it.
 */
export const TABLES_WITH_ROWS_TTL_MS = 60_000

/** What the has-rows sweep found. */
export interface TablesWithRows {
  /** The keys of the tables holding at least one row, or `null` while the answer is still coming
   *  (and whenever the filter is null, which disables the sweep). */
  populated: Set<string> | null
  /** The keys of the tables whose probe answered with NO rows — listable, just empty. `null`
   *  exactly when `populated` is. Kept apart from a 403/404 table (which this viewer cannot list,
   *  so it is in neither set), because an empty table is where a first row gets created. */
  empty: Set<string> | null
  /** The keys of the tables whose probe failed for a reason that says nothing about their rows
   *  (a 5xx, a 429, a dropped connection) — "couldn't check", not "empty". `null` exactly when
   *  `populated` is. */
  unknown: Set<string> | null
  /** Some probe failed (see `unknown`), so `populated` may be missing tables that DO hold rows. */
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
  /** WHO is asking — the signed-in user's id (`useViewer().principal`). Part of the cache key, so a
   *  remembered answer is never served to a different user, even before the session watcher has
   *  seen the swap. Falls back to the token's subject when omitted. */
  principal?: string | null
}

/** The one "no answer yet" object, returned whenever there is none. */
const PENDING: TablesWithRows = {
  populated: null,
  empty: null,
  unknown: null,
  failed: false,
  firstWithRows: null,
}

/** A remembered answer and when its sweep finished, for {@link TABLES_WITH_ROWS_TTL_MS}. */
interface Remembered {
  answer: TablesWithRows
  at: number
}

/**
 * The last good answer of every sweep, by principal + filter + scope + tables. Module scope,
 * because the browser does not outlive a click: on the standalone /<ws>/all-data route every
 * schema or table click remounts it (the App Router keys the `[[...table]]` subtree by its
 * segment, and without `cacheComponents` it keeps a single back/forward entry), and a stack group
 * renders only its active member, so leaving Storage ▸ All Data and coming back remounts it too.
 * Held in component state, the answer died with each mount: every click blanked the rail and the
 * pane to "Loading…" and swept again — 61 probes for a workspace — before the table's own list
 * started.
 *
 * A remembered answer younger than {@link TABLES_WITH_ROWS_TTL_MS} is served as-is: no sweep. An
 * older one is SHOWN at once and then REVALIDATED: the sweep runs quietly and replaces it when it
 * ends. Never asking again kept a table that gained its first row elsewhere (a note written, a
 * bucket created) out of the rail until the page reloaded; always asking again swept on every
 * click. The principal is part of the key, and every answer is also dropped the moment the
 * signed-in principal changes (see {@link watchSession}) or the page reloads. A FAILED sweep is
 * never kept: coming back asks again, which is what the rail's "couldn't check" asks of the
 * viewer; with an answer on screen, that answer stays rather than being replaced by a partial one.
 */
const answers = new Map<string, Remembered>()
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
 * list for them) puts the table in no set: a table that cannot show this viewer a row has nothing
 * to offer them in the rail. A probe that answers with no rows puts it in `empty`. Any other
 * failure is NOT an answer about the rows, so it puts the table in `unknown` and marks the sweep
 * `failed` — counting every failure as empty hid tables that hold rows, and when every probe
 * failed the rail said "No data yet." about a scope full of data.
 *
 * A remembered answer (see `answers` above) is returned from the first render, and revalidated
 * behind it once it is older than {@link TABLES_WITH_ROWS_TTL_MS}. Otherwise the `first` table
 * goes to the head of the queue: the viewer who deep-linked or clicked a table is waiting on THAT
 * table, which used to wait for the whole sweep before its own list could start.
 *
 * Leaving mid-sweep (an unmount, or a scope change) aborts the probes in flight and drops the
 * queued ones. The workers used to drain the whole queue for an answer nobody would read, and a
 * remount's sweep then overlapped the orphaned one, breaking the {@link PROBE_CONCURRENCY} bound
 * (StrictMode's dev double-mount probed every table twice).
 */
export function useTablesWithRows(
  tables: CrudTableMeta[],
  filter: Record<string, string> | null,
  { scopeEcosystemId, first = null, principal }: TablesWithRowsOptions = {},
): TablesWithRows {
  // Content signatures, not identities: callers derive both per render.
  const tablesSig = tables.map((t) => t.key).join('|')
  const filterSig = filter ? JSON.stringify(filter) : null
  const who = principal ?? (typeof window === 'undefined' ? null : readTokenSubject()) ?? ''
  // WHO asks plus everything a probe's URL is built from, so one key names one sweep's answer.
  const key =
    filterSig === null
      ? null
      : `${JSON.stringify(who)}|${filterSig}|${scopeEcosystemId ?? ''}|${tablesSig}`
  // This mount's answer, tagged with the key it answers. A remembered one seeds it.
  const [swept, setSwept] = useState<{ key: string; answer: TablesWithRows } | null>(() => {
    const known = key === null ? undefined : answers.get(key)
    return key !== null && known ? { key, answer: known.answer } : null
  })

  useEffect(() => {
    if (key === null || filterSig === null) return
    watchSession()
    const remembered = answers.get(key)
    const known = remembered?.answer
    if (remembered && known) {
      // Remembered: shown with no blanking. Held in state as well, so a clear of `answers` while
      // it is on screen (a sign-in in another tab) cannot strand the rail on "Loading…".
      setSwept((prev) => (prev?.key === key ? prev : { key, answer: known }))
      // Fresh: served as-is, no sweep. Stale: revalidated by the sweep below.
      if (Date.now() - remembered.at < TABLES_WITH_ROWS_TTL_MS) return
    }
    const since = generation
    let live = true
    const controller = new AbortController()
    const scope = JSON.parse(filterSig) as Record<string, string>
    const queue = [...tables]
    const head = queue.findIndex((t) => t.key === first)
    if (head > 0) queue.unshift(...queue.splice(head, 1))
    const found = new Set<string>()
    const empty = new Set<string>()
    const unknown = new Set<string>()
    const worker = async () => {
      for (let t = queue.shift(); t; t = queue.shift()) {
        const list = listUrl(t, scope, scopeEcosystemId)
        const probe = `${list}${list.includes('?') ? '&' : '?'}limit=1`
        try {
          const rows = await authedJson<unknown[]>(probe, { signal: controller.signal })
          if (!Array.isArray(rows) || rows.length === 0) {
            empty.add(t.key)
          } else {
            found.add(t.key)
            // Only a sweep with nothing on screen reports its first table early: over a remembered
            // answer, a `populated: null` answer would blank the rail it is quietly revalidating.
            if (live && !known && t.key === first) {
              setSwept({ key, answer: { ...PENDING, firstWithRows: t.key } })
            }
          }
        } catch (err) {
          // A 403/404 puts the table in no set — see the docblock. The cleanup's abort lands here
          // too, and is never read: `live` is already false.
          if (!(err instanceof AuthHttpError && (err.status === 403 || err.status === 404))) {
            unknown.add(t.key)
          }
        }
      }
    }
    void Promise.all(Array.from({ length: PROBE_CONCURRENCY }, worker)).then(() => {
      if (!live) return
      const failed = unknown.size > 0
      // A failed revalidation leaves the remembered answer on screen: some tables' probes said
      // nothing, so this answer is partial, and the last good one is the better guess.
      if (failed && known) return
      const answer: TablesWithRows = {
        populated: found,
        empty,
        unknown,
        failed,
        firstWithRows: null,
      }
      // Neither a failed sweep nor one a change of principal overtook is kept.
      if (!failed && since === generation) answers.set(key, { answer, at: Date.now() })
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
  return swept?.key === key ? swept.answer : answers.get(key)?.answer ?? PENDING
}
