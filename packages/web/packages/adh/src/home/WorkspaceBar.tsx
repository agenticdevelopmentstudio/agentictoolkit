'use client'

import { type ReactElement } from 'react'
import { WorkspacePicker } from './WorkspacePicker'
import type { WorkspaceOption } from './WorkspaceOption'

/**
 * The workspace switcher, CENTRED in a full-width bar directly under the header: a feature
 * site's, mounted by SiteHomeShell. Presentational and data-free — it takes a list, a selection
 * and a callback — which is what lets workspaceBarLayout.test.tsx pin its structure with no
 * workspace to resolve.
 *
 * It was extracted from SiteHomeShell so the hub could mount the SAME bar rather than a second
 * copy. The hub has since moved its switcher INTO its header (WorkspaceMenu, fed by a provider
 * the hub's own layout mounts), so SiteHomeShell is the only mount left and the `home` barrel no
 * longer exports this.
 *
 * The chooser used to be portaled into the header's centre slot above 768px, with this bar as the
 * narrow-only fallback. That arrangement is gone: the header is built by a site's root layout,
 * above the route, so reaching its centre took a context published by a provider the host had to
 * remember to mount — and a host that forgot lost the chooser silently, above 768px only, in
 * production only. One bar the route renders itself has no such precondition and no second copy
 * to keep in step. (The hub's header menu takes that precondition back on, for the hub alone: its
 * provider is the hub's to mount, and nothing here asks a feature site to mount one.)
 *
 * The switcher and nothing else. This had an `action` slot for a trailing control, and only the
 * hub's "New Organization" button ever filled it. The hub took that button out of its workspace
 * chrome — an org is created inside Organizations, from that feature's own list, where the org
 * just made then appears, and a create button pinned above every one of a workspace's routes
 * answers a question none of them asks — and then stopped mounting this bar, so the slot went
 * too. A control added beside the picker would also pull it off centre (see the rule's comment).
 */
export function WorkspaceBar({
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
  return (
    // The picker is the bar's ONLY child, and a DIRECT one; the CSS depends on both. The bar is a
    // flex row that centres what it holds, so a sibling would share the row and pull the chooser
    // off centre. And `.adh-home__toolbar > *` is what lets a long name truncate, so it has to land
    // on the picker's own root: under the flex wrapper that used to sit here it didn't, and a long
    // name overflowed the bar instead (see adh-components.css).
    <div className="adh-home__toolbar">
      {/* No visible "Workspace" word: the picker's trigger reads as the workspace's name, which
          says what the control is, and the label was a second element saying it again. Assistive
          tech still hears it — the trigger carries `ariaLabel="Workspace"` (see WorkspacePicker). */}
      <WorkspacePicker workspaces={workspaces} selected={selected} onSelect={onSelect} />
    </div>
  )
}
