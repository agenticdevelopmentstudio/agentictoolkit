'use client'

// The shared workspace-route shell: one workspace chooser in a bar under the header, the site's
// own HTDV below it.
// Its own entry (and hence its own export subpath) so only a page that imports it pays for the
// package's @agentic-toolkit/data dependency — the header ships on every public page and must
// not carry workspace vocabulary.
//
// A site needs three of these at most: `defineSiteHome` to declare its model, `SiteHomeRoute` to
// render it, and `noSubPath` if it has no grammar below the workspace. `SiteHomeShell` and
// `WorkspacePicker` are the parts the route assembles, exported for tests and for anything that
// legitimately needs one alone — a site reaching for them is rebuilding by hand the arrangement
// the model exists to own.
//
// `useWorkspaceRoute` is the half of SiteHomeShell exported for ONE caller with a legitimate need:
// the hub. Not the URL any more — its workspace is the bare `/<slug>` like everyone's since the
// route convergence — but the ROWS. The shell fills its picker from `workspacesApi.list()`, which
// returns the caller's own workspace and their organizations; the hub's list also carries teams
// and the per-workspace feature grants that decide which of its topics a row may open. Feeding
// those through the shell would mean either every site grows teams or the hub loses them, which is
// a product decision and not this module's to take. It mounts the hook directly so the resolution
// behind its switcher stays the fleet's, not a second implementation. A feature site never needs
// it.
//
// The shell's other half, `WorkspaceBar`, is not exported. The hub mounted it too until its
// switcher moved into its header (WorkspaceMenu), which left SiteHomeShell, importing it
// relatively, as its only caller.
export { SiteHomeRoute } from './SiteHomeRoute'
export { defineSiteHome, noSubPath } from './SiteHomeModel'
export type {
  SiteHomeModel,
  SiteHomeContext,
  SiteHomeScope,
  SiteHomeShellProps,
  SiteHomeHostSeams,
} from './SiteHomeModel'
export { SiteHomeShell } from './SiteHomeShell'
export { WorkspaceOrProfileGate } from './WorkspaceOrProfileGate'
export { WorkspacePicker } from './WorkspacePicker'
export { useWorkspaceRoute } from './useWorkspaceRoute'
// Exported for the same one caller as the hook above: the hub builds its own `switchHrefFor`, so
// it needs the same answer to "which segments are the selection" that this shell uses.
export { workspacePathTail } from './workspacePathTail'
export type { WorkspaceOption } from './WorkspaceOption'
