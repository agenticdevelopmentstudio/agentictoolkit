import { type ReactNode } from 'react';
/** A workspace as the menu needs it — fully pre-resolved by the hub (no slug/label
 *  logic in shared chrome). */
export type MenuWorkspace = {
    /** Stable id (the hub's workspace composite id) — React key + de-dupe. */
    id: string;
    /** Display label (e.g. "My Workspace" for the individual one, else the name). */
    label: string;
    /** Destination href — the workspace's home. */
    href: string;
    /** True for the currently-active workspace. */
    current?: boolean;
};
/** The Workspaces flyout's data + loading state. */
export type WorkspacesMenu = {
    workspaces: MenuWorkspace[];
    loading: boolean;
    /** True when the list could not be fetched. Optional so a host with nothing to fail (a
     *  canned list) need not say so. It exists because "no rows, not loading" was all the menu
     *  could see, and it told someone whose fetch had failed that they had "No workspaces yet" —
     *  a false statement about their account, where the truth is that we could not ask. */
    error?: boolean;
    /** How a chosen row switches, when the host has something better than following `href`. The
     *  hub fills it while a workspace route is mounted, and what it adds is the FEATURE: its switch
     *  keeps the page you are on under the new workspace (the route's `switchHrefFor`), where a
     *  plain `href` lands on the bare workspace. Remembering the pick is NOT the difference: the
     *  route records any fresh arrival on a `/<slug>` it did not seed itself — a followed link and
     *  the back button alike — as the preference (teams excepted; see `useWorkspaceRoute`), so a
     *  plain link is remembered too. Absent ⇒ the menu navigates to `href`. */
    select?: (workspace: MenuWorkspace) => void;
};
/** Provide the site menu's Workspaces data (hub-only). Absent off the hub, so the
 *  menu hides the Workspaces row there. */
export declare function WorkspacesMenuProvider({ value, children, }: {
    value: WorkspacesMenu;
    children: ReactNode;
}): ReactNode;
/** Read the Workspaces flyout data, or null when no provider is mounted (off-hub). */
export declare function useWorkspacesMenu(): WorkspacesMenu | null;
//# sourceMappingURL=workspaces-menu.d.ts.map