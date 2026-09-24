'use client'

import { type ReactElement } from 'react'
import { ChevronDown } from 'lucide-react'
import { PopupMenu } from '@agenticdevelopertoolkit/ui/blocks'
import type { WorkspaceOption } from './WorkspaceOption'

/**
 * The workspace switcher in WorkspaceBar: a plain PopupMenu over the caller's workspaces.
 * Presentational and data-free — it takes a list and a callback, so the mounted one and the
 * tested one cannot drift apart.
 *
 * A switcher, and nothing else: no "All" row (one workspace is always chosen). Nor is there a "New
 * Organization" entry: an org is created inside the hub's Organizations feature, where the new org
 * then appears, not from a switcher that sits above every route.
 *
 * `allLabel` doubles as PopupMenu's EMPTY-SELECTION trigger text, which is why the three
 * pre-selection states ride on it rather than on a fourth prop. Each renders one inert row in the
 * open menu, which says the same thing the trigger does. The third state is reachable, not
 * theoretical: `workspaces` can load (non-empty) before `selected` does — useWorkspaceRoute
 * resolves a workspace only once its prefs GET settles (or its 5s bail fires), and that GET can
 * easily outlast the workspace list's own fetch. Without folding it into "Loading…" too, that
 * window renders a blank trigger — a real state loaded and non-empty, but nothing chosen yet.
 */
export function WorkspacePicker({
  workspaces,
  selected,
  onSelect,
}: {
  /** The caller's workspaces, or null while the list is still loading. */
  workspaces: readonly WorkspaceOption[] | null
  /** The chosen workspace's slug, or null before resolution. */
  selected: string | null
  onSelect: (slug: string) => void
}): ReactElement {
  const allLabel =
    workspaces === null
      ? 'Loading…'
      : workspaces.length === 0
        ? 'No workspaces'
        : selected === null
          ? 'Loading…'
          : null

  return (
    <PopupMenu
      items={(workspaces ?? []).map((w) => ({ id: w.slug, label: w.name }))}
      selectedId={selected}
      // A switcher never deselects, and this guard is what enforces that — it is NOT dead. While
      // `allLabel` is non-null PopupMenu renders an "All"-position row that reports `null`, and
      // one of the three states above (a loaded list with no selection yet) leaves it non-null for
      // as long as resolution takes. `selectedId={null}` also marks that row CHECKED, so during
      // the settle window the user sees "Loading…" selected above their real workspaces; clicking
      // it is swallowed here rather than deselecting anything.
      onSelect={(id) => {
        if (id) onSelect(id)
      }}
      allLabel={allLabel}
      ariaLabel="Workspace"
      icon={<ChevronDown size={14} aria-hidden className="shrink-0 text-apt-text-muted" />}
      // Sized to its content, not PopupMenu's default full width, so the chooser reads as one
      // control centred in WorkspaceBar rather than a field spanning it. `max-w-full` caps it at
      // its root; what lets that root shrink to the bar, so a long name truncates instead of
      // overflowing, is the bar's `.adh-home__toolbar > * { min-width: 0 }` rule.
      className="w-auto max-w-full"
    />
  )
}
