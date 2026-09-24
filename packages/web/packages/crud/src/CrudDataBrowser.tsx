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
  const { tables, shell, workspace, selection, basePath, activeSchema, activeTable } = props
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
  const { isAdmin: viewerIsAdmin, ready: viewerReady } = useViewer()
  const allTables = useMemo(
    () =>
      viewerReady
        ? readableTables(tables ?? Object.values(CRUD_TABLES), viewerIsAdmin).filter(
            (t) => !workspace || isWorkspaceScopable(t),
          )
        : [],
    [tables, viewerIsAdmin, viewerReady, workspace],
  )

  // level 0 = distinct schemas (sorted); level 1 = the open schema's tables (sorted). Schemas
  // are derived from the FILTERED tables, so a schema whose every table is admin-only (or an
  // explicit `tables` prop narrowed to none) drops out of the rail entirely rather than opening
  // onto an empty table list.
  const schemas = useMemo(
    () => [...new Set(allTables.map((t) => t.schema))].sort((a, b) => a.localeCompare(b)),
    [allTables],
  )
  // Selection comes from the URL (activeSchema/activeTable) or, when embedded, the host's
  // controlled `selection`. An unknown schema/table falls back to "nothing open".
  const rawSchema = selection ? selection.schema : activeSchema ?? null
  const rawTable = selection ? selection.table : activeTable ?? null
  const schemaSelected = rawSchema && schemas.includes(rawSchema) ? rawSchema : null
  const tablesInSchema = useMemo(
    () =>
      schemaSelected
        ? allTables
            .filter((t) => t.schema === schemaSelected)
            .sort((a, b) => a.table.localeCompare(b.table))
        : [],
    [allTables, schemaSelected],
  )
  const tableSelected =
    schemaSelected && rawTable
      ? tablesInSchema.find((t) => t.table === rawTable) ?? null
      : null

  // Row icons name what a row IS (a schema = a folder of tables; a table): without them every
  // row falls back to the rail's placeholder circle, which reads as "unfinished".
  const schemaItems = useMemo<TopicDetailItem[]>(
    () => schemas.map((s) => ({ id: s, label: s, icon: <FolderTree /> })),
    [schemas],
  )
  const tableItems = useMemo<TopicDetailItem[]>(
    () => tablesInSchema.map((t) => ({ id: t.table, label: t.table, icon: <Table2 /> })),
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
        // "None" and "not known yet" are different answers; say which one this is.
        emptyLabel: viewerReady ? 'No schemas.' : 'Loading…',
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
      viewerReady,
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
  // (which would read as the deep link having failed).
  const content = !viewerReady ? (
    <p className="p-6 font-mono text-sm text-apt-text-dim" role="status">
      Loading…
    </p>
  ) : tableSelected ? (
    <CrudDataView
      key={tableSelected.key}
      meta={tableSelected}
      filter={workspace ? { workspace } : undefined}
      onGuardChange={registerGuard}
    />
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
