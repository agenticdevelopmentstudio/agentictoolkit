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
    /** How a chosen row switches, when the host has something better than following `href`. The
     *  hub fills it while a workspace route is mounted: its switch KEEPS the feature you are on and
     *  REMEMBERS the pick as your preference — and a plain link can do neither, since the
     *  route's resolver cannot tell a followed link from the back button, which must never
     *  persist. Absent ⇒ the menu navigates to `href`. */
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