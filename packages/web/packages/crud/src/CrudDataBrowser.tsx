'use client'

import { useMemo, type ComponentType, type ReactNode } from 'react'
import { useRouter } from 'next/navigation'
import { FolderTree, Table2 } from 'lucide-react'
import {
  HierarchicalDetailView,
  type PaneExitGuard,
  type TopicDetailItem,
  type TopicLevel,
} from '@agenticdevelopertoolkit/ui/blocks'
import { CRUD_TABLES } from './generated/table-metadata'
import { CrudDataView } from './CrudDataView'
import { readableTables } from './exposure'
import { useViewer } from './viewer'
import { useExitGuardChannel } from './useExitGuardChannel'
import { useTablesWithRows } from './useTablesWithRows'
import type { CrudTableMeta } from './types'

export interface CrudShellProps {
  /** The schema ▸ table rail levels to render. */
  levels: TopicLevel[]
  /** Root breadcrumb label for the standalone rail. */
  rootLabel?: string
  /** The open table editor's unsaved-work guard, routed to whichever stack renders the rail
   *  (the standalone HierarchicalTopicDetail, or the workspace shell's merged stack). */
  exitGuard?: PaneExitGuard | null
  /** The frontier detail (the table view / hint). */
  children: ReactNode
}

/**
 * Renders the browser's schema/table rail. The default is a standalone
 * {@link HierarchicalTopicDetail}; a host embedded in a larger rail (e.g. the hub's workspace
 * shell) injects one that PUBLISHES these levels into the enclosing merged stack instead of
 * nesting its own — so schema/table become siblings of the outer rails, not a detached sub-rail.
 */
export type CrudShell = ComponentType<CrudShellProps>

export function DefaultCrudShell({ levels, rootLabel, exitGuard, children }: CrudShellProps) {
  return (
    <HierarchicalDetailView levels={levels} rootLabel={rootLabel} exitGuard={exitGuard ?? null}>
      {children}
    </HierarchicalDetailView>
  )
}

/**
 * Controlled/local selection for the browser. When supplied (instead of `basePath`), the host owns
 * the open schema/table in its own state and the browser calls these setters on select — it does
 * NOT route. Use it when the browser is embedded in a URL scheme that can't cede the two segments
 * URL mode needs (the hub's ecosystem ▸ Storage rail): a schema click then re-renders in place
 * instead of navigating to the standalone /all-data route and unmounting the enclosing rails.
 */
export interface CrudBrowserSelection {
  /** The open schema (CrudTableMeta.schema), or null for none. */
  schema: string | null
  /** The open table (CrudTableMeta.table) within `schema`, or null for none. */
  table: string | null
  /** Select the schema, or clear it with null. Changing OR clearing the schema must also clear the
   *  table (a different schema has different tables) — the host owns that reset. */
  onSelectSchema: (schema: string | null) => void
  /** Select the table within the open schema, or clear it with null. */
  onSelectTable: (table: string | null) => void
}

interface CrudDataBrowserCommon {
  /** The tables to browse; defaults to every backend CRUD table (no per-schema
   *  filter — every schema the backend exposes appears). */
  tables?: CrudTableMeta[]
  /** How to render the schema/table rail. Defaults to a standalone HierarchicalTopicDetail;
   *  inject one (e.g. via StackLevels) to publish into an enclosing workspace shell's stack. */
  shell?: CrudShell
  /** The workspace slug whose data this browser shows. Every list is sent `?workspace=<slug>`,
   *  which the backend reads as "only rows this workspace owns", and the rail drops every table
   *  that cannot be scoped that way — a global catalog no workspace owns would otherwise list
   *  every tenant's rows under a workspace's name. Omit it for the unscoped, cross-tenant
   *  browser. */
  workspace?: string
  /** The ecosystem (rdid or uuid) whose data this browser shows — narrower than `workspace`,
   *  which spans every ecosystem the workspace owns. Every list and every write is sent
   *  `?ecosystemId=<id>`, a new row starts pinned to it, and the rail keeps only
   *  ecosystem-columned tables: an owner-pair table has no ecosystem to narrow by, so under an
   *  ecosystem it would show the workspace's rows, not this ecosystem's.
   *  "ONLY THE ECOSYSTEMS TABLES SHOULD SHOW - this is a huge huge huge data leak" (Mike,
   *  2026-09-24), from an ecosystem's Storage ▸ All Data listing its sibling ecosystem's
   *  buckets. */
  ecosystemId?: string
}

/**
 * What a scoped browser's has-rows sweep said about one listed table, best first: it holds rows;
 * its probe failed, so nobody knows; it is listable and holds none. The order is the rail's order.
 */
type RowState = 'rows' | 'unknown' | 'empty'
const ROW_STATE_RANK: Record<RowState, number> = { rows: 0, unknown: 1, empty: 2 }
/** The dim second line a non-populated row carries, so "couldn't check" never reads as "empty". */
const ROW_STATE_SUBLABEL: Record<RowState, string | undefined> = {
  rows: undefined,
  unknown: "Couldn't check for rows",
  empty: 'No rows yet',
}
/** The caption over the secondary group of rows with nothing in them. */
const EMPTY_GROUP_LABEL = 'Empty'

/**
 * Rail rows for `entries`, best {@link RowState} first (then by name), with the rows holding
 * nothing set apart as a secondary "Empty" group under a divider — dim, but still clickable, since
 * an empty table is exactly where a viewer creates its first row.
 */
function railItems(
  entries: { id: string; state: RowState }[],
  icon: ReactNode,
): TopicDetailItem[] {
  const sorted = [...entries].sort(
    (a, b) => ROW_STATE_RANK[a.state] - ROW_STATE_RANK[b.state] || a.id.localeCompare(b.id),
  )
  const firstEmpty = sorted.findIndex((e) => e.state === 'empty')
  return sorted.map((e, i) => ({
    id: e.id,
    label: e.id,
    icon,
    ...(ROW_STATE_SUBLABEL[e.state] ? { sublabel: ROW_STATE_SUBLABEL[e.state] } : {}),
    ...(i === firstEmpty - 1 ? { dividerAfter: true, dividerLabel: EMPTY_GROUP_LABEL } : {}),
  }))
}

/** Whether `meta`'s rows belong to an ecosystem — the only tables an ecosystem scope can narrow. */
function hasEcosystemColumn(meta: CrudTableMeta): boolean {
  return meta.columns.some((c) => c.name === 'ecosystemId')
}

/** Whether the backend can narrow `meta`'s list to one workspace: it scopes an ecosystem-columned
 *  table to the workspace's ecosystems, and an owner-pair table to the workspace's owner. */
function isWorkspaceScopable(meta: CrudTableMeta): boolean {
  const names = new Set(meta.columns.map((c) => c.name))
  return names.has('ecosystemId') || (names.has('ownerKind') && names.has('ownerId'))
}

/**
 * The browser is EITHER URL-driven (deep-linkable — the standalone /all-data route) OR
 * controlled/local (the embedded ecosystem rail). Exactly one of `basePath` / `selection` is given.
 */
export type CrudDataBrowserProps = CrudDataBrowserCommon &
  (
    | {
        /** The route the browser drives — selections push `${basePath}/<schema>/<table>`. */
        basePath: string
        /** URL schema segment (CrudTableMeta.schema) of the open schema. */
        activeSchema?: string
        /** URL table segment (CrudTableMeta.table) within the open schema. */
        activeTable?: string
        selection?: never
      }
    | {
        /** Host-owned selection — see {@link CrudBrowserSelection}. `basePath` is then unused. */
        selection: CrudBrowserSelection
        basePath?: never
        activeSchema?: never
        activeTable?: never
      }
  )

/**
 * The /all-data hierarchical data browser: a {@link HierarchicalTopicDetail}
 * whose level 0 is the DB schemas and level 1 is the tables within the open
 * schema, with the selected table's view ({@link CrudDataView}) in the detail
 * pane. The breadcrumb reads All Data ▸ schema ▸ table.
 *
 * URL-driven, mirroring the hub's ResourceTab: `<basePath>` (nothing open) /
 * `<basePath>/<schema>` / `<basePath>/<schema>/<table>`. An unknown schema/table
 * segment falls back to "nothing open" rather than a phantom selection.
 */
export function CrudDataBrowser(props: CrudDataBrowserProps) {
  const { tables, shell, workspace, ecosystemId, selection, basePath, activeSchema, activeTable } =
    props
  const router = useRouter()
  // Admin-tier tables are hidden from a non-admin viewer: the backend refuses them outright, so
  // listing them offers a row whose only outcome is a 403. Catalog-tier tables stay listed —
  // they ARE readable — and CrudDataView renders them read-only. Presentation only; the server
  // gate is the boundary either way (see exposure.ts).
  //
  // Until auth settles the rail is EMPTY (loading), not "filtered for a non-admin": guessing
  // would either flash admin tables at someone who can't open them, or make an admin's
  // deep-linked schema vanish and pop back a paint later. Empty-then-populated is the one
  // sequence that never shows a wrong answer.
  const { isAdmin: viewerIsAdmin, ready: viewerReady, principal } = useViewer()
  const candidates = useMemo(
    () =>
      viewerReady
        ? readableTables(tables ?? Object.values(CRUD_TABLES), viewerIsAdmin).filter((t) =>
            ecosystemId ? hasEcosystemColumn(t) : !workspace || isWorkspaceScopable(t),
          )
        : [],
    [tables, viewerIsAdmin, viewerReady, workspace, ecosystemId],
  )
  // The list filter every table is read with — the open view's AND the has-rows probe's, so the
  // rail never offers a table the view would then show empty.
  const listFilter = useMemo(() => {
    if (!workspace && !ecosystemId) return undefined
    const f: Record<string, string> = {}
    if (workspace) f.workspace = workspace
    if (ecosystemId) f.ecosystemId = ecosystemId
    return f
  }, [workspace, ecosystemId])
  // Selection comes from the URL (activeSchema/activeTable) or, when embedded, the host's
  // controlled `selection`. An unknown schema/table falls back to "nothing open".
  const rawSchema = selection ? selection.schema : activeSchema ?? null
  const rawTable = selection ? selection.table : activeTable ?? null
  // A SCOPED browser leads with the tables holding rows in its scope ("in All Data only show
  // tables and schemas in the list with data in them", Mike, 2026-09-24). The unscoped
  // cross-tenant browser stays a catalogue of every table. A table whose probe FAILED is listed
  // after them, marked "Couldn't check for rows": hiding it hid tables that hold rows. A table
  // that answered with no rows is listed last, in a dim "Empty" group — hiding it left no way to
  // create its first row. A table this viewer cannot list (403/404) is not listed at all.
  // The open table is probed first and opens on its own probe's answer, instead of waiting on the
  // whole sweep; until the sweep ends the rail holds at most that one confirmed table, marked busy.
  const openCandidate =
    rawSchema && rawTable
      ? candidates.find((t) => t.schema === rawSchema && t.table === rawTable)
      : undefined
  const {
    populated,
    empty: emptyTables,
    unknown: uncheckedTables,
    failed: probeFailed,
    firstWithRows,
  } = useTablesWithRows(candidates, viewerReady && listFilter ? listFilter : null, {
    scopeEcosystemId: ecosystemId,
    first: openCandidate?.key ?? null,
    principal,
  })
  // Still asking which tables hold rows (only a scoped browser asks).
  const sweeping = viewerReady && !!listFilter && populated === null
  const ready = viewerReady && !sweeping
  // Every listed table with what the sweep said about it. Unscoped, every candidate "has rows" —
  // the catalogue is not swept, so it carries no marks.
  const listed = useMemo(() => {
    const out = new Map<string, { meta: CrudTableMeta; state: RowState }>()
    for (const t of candidates) {
      const state: RowState | null = !listFilter
        ? 'rows'
        : populated
          ? populated.has(t.key)
            ? 'rows'
            : uncheckedTables?.has(t.key)
              ? 'unknown'
              : emptyTables?.has(t.key)
                ? 'empty'
                : null
          : t.key === firstWithRows
            ? 'rows'
            : null
      if (state) out.set(t.key, { meta: t, state })
    }
    return out
  }, [candidates, listFilter, populated, uncheckedTables, emptyTables, firstWithRows])

  // level 0 = distinct schemas; level 1 = the open schema's tables. Schemas are derived from the
  // LISTED tables, so a schema whose every table is admin-only, refused (403/404), or cut by an
  // explicit `tables` prop drops out of the rail entirely rather than opening onto an empty list.
  // A schema takes the best state among its tables: one populated table puts it in the main group.
  const schemaStates = useMemo(() => {
    const best = new Map<string, RowState>()
    for (const { meta, state } of listed.values()) {
      const prev = best.get(meta.schema)
      if (!prev || ROW_STATE_RANK[state] < ROW_STATE_RANK[prev]) best.set(meta.schema, state)
    }
    return best
  }, [listed])
  const schemaSelected = rawSchema && schemaStates.has(rawSchema) ? rawSchema : null
  const tablesInSchema = useMemo(
    () =>
      schemaSelected
        ? [...listed.values()].filter(({ meta }) => meta.schema === schemaSelected)
        : [],
    [listed, schemaSelected],
  )
  const tableSelected =
    schemaSelected && rawTable
      ? tablesInSchema.find(({ meta }) => meta.table === rawTable)?.meta ?? null
      : null

  // Row icons name what a row IS (a schema = a folder of tables; a table): without them every
  // row falls back to the rail's placeholder circle, which reads as "unfinished".
  const schemaItems = useMemo<TopicDetailItem[]>(
    () =>
      railItems(
        [...schemaStates].map(([id, state]) => ({ id, state })),
        <FolderTree />,
      ),
    [schemaStates],
  )
  const tableItems = useMemo<TopicDetailItem[]>(
    () =>
      railItems(
        tablesInSchema.map(({ meta, state }) => ({ id: meta.table, state })),
        <Table2 />,
      ),
    [tablesInSchema],
  )
  const tableSelectedId = tableSelected?.table ?? null

  // Each level's onSelect/onClear is pure URL navigation; the package owns WHEN to
  // call them (row click, re-click-deselect, breadcrumb up, Back). onClear at a level
  // means "clear this level and everything below, keep ancestors": clearing schema
  // (level 0) returns to nothing-open; clearing table (level 1) drops back to the
  // open schema. The breadcrumb (All Data ▸ schema ▸ table) is driven off these.
  // Every level carries a title so its rail has a heading, like every other stack level.
  // Memoised so a parent re-render doesn't hand the topic-detail block new array
  // references and re-diff its rails for no change.
  const levels = useMemo<TopicLevel[]>(
    () => [
      {
        id: 'schema',
        title: 'Schemas',
        // The frontier's select nudge: name the rows and say what choosing one does.
        itemNoun: 'schema',
        overviewHelp: 'Each schema groups one area’s tables. Pick the schema whose data you want to browse.',
        items: schemaItems,
        selectedId: schemaSelected,
        onSelect: (id) => {
          if (selection) selection.onSelectSchema(id)
          else if (basePath) router.push(`${basePath}/${id}`, { scroll: false })
        },
        onClear: () => {
          if (selection) selection.onSelectSchema(null)
          else if (basePath) router.push(basePath, { scroll: false })
        },
        // "None" and "not known yet" are different answers; say which one this is. So are "none"
        // and "couldn't ask": a sweep whose probes failed must not read as an empty scope.
        emptyLabel: !ready
          ? 'Loading…'
          : listFilter
            ? probeFailed
              ? "Couldn't load this data. Try again."
              : 'No data yet.'
            : 'No schemas.',
        // A rail still being swept is partial (at most the open table's own row), so say so.
        busy: sweeping,
      },
      {
        id: 'table',
        title: schemaSelected ?? 'Tables',
        itemNoun: 'table',
        overviewHelp: 'Pick a table to browse its rows and edit records here.',
        items: tableItems,
        selectedId: tableSelectedId,
        onSelect: (id) => {
          if (selection) selection.onSelectTable(id)
          else if (schemaSelected && basePath)
            router.push(`${basePath}/${schemaSelected}/${id}`, { scroll: false })
        },
        onClear: () => {
          if (selection) selection.onSelectTable(null)
          else if (schemaSelected && basePath)
            router.push(`${basePath}/${schemaSelected}`, { scroll: false })
        },
        emptyLabel: 'No tables.',
        busy: sweeping,
      },
    ],
    [
      schemaItems,
      tableItems,
      schemaSelected,
      tableSelectedId,
      router,
      basePath,
      selection,
      ready,
      listFilter,
      probeFailed,
      sweeping,
    ],
  )

  // The open table's editor registers its unsaved-work guard here; the topic-detail block consults
  // it before a navigation that would replace/unmount the editor, so dirty edits prompt Save /
  // Discard / Cancel instead of being silently dropped. `useExitGuardChannel` keeps a STABLE proxy
  // over the imperatively-registered guard. (A direct sibling-table click is a forward selection the
  // block does not guard.)
  const { exitGuard, registerGuard } = useExitGuardChannel()

  // `children` land in the frontier pane: the table view once a table is open,
  // else a hint to drill in. Keyed per table so a switch is a fresh mount.
  // Before auth settles, a deep link has no answer yet — say "loading", not "pick a schema"
  // (which would read as the deep link having failed). The view comes FIRST: an open table its own
  // probe confirmed mounts mid-sweep, and stays the same element when the sweep ends.
  const content = tableSelected ? (
    // Under an ecosystem the WRITES are scoped too, not just the list: without it a row created
    // from one ecosystem's Storage ▸ All Data was stamped with the caller's JWT ecosystem (every
    // hub JWT is ecosystem zero), and the re-list, filtered to this ecosystem, dropped it; and a
    // non-admin's edit or delete on a `?ecosystemId=`-scoped table, whose row was listed only
    // through that scope, was refused. The create default is pinned, as SchemasPane's bucket
    // view pins its own.
    <CrudDataView
      key={tableSelected.key}
      meta={tableSelected}
      filter={listFilter}
      scopeEcosystemId={ecosystemId}
      createDefaults={ecosystemId ? { ecosystemId } : undefined}
      onGuardChange={registerGuard}
    />
  ) : !ready ? (
    <p className="p-6 font-mono text-sm text-apt-text-dim" role="status">
      Loading…
    </p>
  ) : (
    <p className="p-6 font-mono text-sm text-apt-text-dim" role="status">
      {schemaSelected ? 'Pick a table to view its data.' : 'Pick a schema, then a table.'}
    </p>
  )

  // Standalone → the browser's own HierarchicalTopicDetail. Inside the hub's workspace shell →
  // the injected shell publishes these levels into the ONE merged stack (schema/table become
  // siblings of the workspace ▸ feature rails), so All Data is a hierarchical topic/detail like
  // every other feature rather than a detached sub-rail.
  const Shell = shell ?? DefaultCrudShell
  return (
    <Shell levels={levels} rootLabel="All Data" exitGuard={exitGuard}>
      {content}
    </Shell>
  )
}
