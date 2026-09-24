import { type ReactElement } from 'react';
import type { SiteHomeShellProps } from './SiteHomeModel';
/**
 * The shared shell for a feature site's workspace route: one workspace chooser in a bar
 * directly under the header, and below it that site's own HTDV scoped to the chosen workspace.
 *
 * The DEFAULT, not the only one: a site may declare `shell` on its model and get its own. One
 * does — see SiteHomeModel.shell for which and why. Everything this file defends is owed by a
 * replacement too, so read the reasons below before writing one.
 *
 * Every site that scopes to a workspace used to grow its own chooser inside its HTDV stack —
 * eating the widest column, reimplemented per feature package, and the answer did not travel.
 * This owns all of it once:
 *
 *   - The ONE workspacesApi.list() fetch. The bar and the resolution read it.
 *   - Resolution, the URL-as-truth replace, and persistence of an explicit choice — all of it
 *     useWorkspaceRoute's, which the hub mounts too (it needs a different LIST — the fetch on the
 *     line above drops teams — but the behaviour behind its switcher is the same one).
 *   - A workspace this caller cannot reach: a settled list without the URL's slug renders that
 *     slug's PROFILE (`ProfileFallback`) rather than the workspace. See the check below the hook
 *     for the three states that are NOT that.
 *   - Holding `children` until resolution, so no feature mounts unscoped and fires a list
 *     request the backend would answer with the wrong reach. `children` is a FUNCTION for that
 *     reason: a node would be CONSTRUCTED on every render, including the ones before a workspace
 *     exists, so its props could only be built from the raw URL segment — which is `undefined`
 *     at `/home` and stale mid-redirect. Called instead, it runs once the answer is known and is
 *     handed that answer.
 *   - Rendering the chooser ONCE, in a bar directly under the header, at every width.
 *
 * Signed-out visitors DO reach here: the workspace route's gate is `WorkspaceOrProfileGate`,
 * which renders `children` (this shell) for a caller with a session and the principal's profile
 * for one without. This shell makes the narrower judgement — authenticated, but not a MEMBER of
 * this workspace — and lands in the same place.
 */
export declare function SiteHomeShell({ workspaceSlug, workspaceHref, children, }: SiteHomeShellProps): ReactElement;
//# sourceMappingURL=SiteHomeShell.d.ts.map