import { type ReactElement } from 'react';
import type { WorkspacesMenu } from './workspaces-menu';
import type { SiteMenuChromeProps } from './SiteMenu';
export type WorkspaceMenuProps = Pick<SiteMenuChromeProps, 'userIsAdmin' | 'currentSiteId' | 'resolveHref' | 'personalSlug' | 'hubOffersFeature' | 'onSettings' | 'settingsHref' | 'navLinks' | 'triggerClassName'> & {
    /** The signed-in user's workspaces, pre-resolved by the host (see WorkspacesMenuProvider). */
    menu: WorkspacesMenu;
};
/**
 * The signed-in header's switcher: the user's WORKSPACES, in the site menu's own engine
 * ({@link NavigationPopover} — search, keyboard browse, the global chord) and in the site menu's
 * spot, behind the same hub mark.
 *
 * It replaced two things at once. The fleet site menu is set aside for a signed-in user — a
 * person inside a workspace switches workspaces far more than they switch sites — and the
 * "Workspace [name ▾]" bar under the header is gone, because the control it held is now here. The
 * trigger reads as the workspace you are in, which is what the bar's label + picker said with two
 * elements and a second row of chrome.
 *
 * Data-free, like the site menu: the host resolves every row (label, destination, which one is
 * current), so no workspace or slug logic lives in shared chrome. Choosing a row is an ordinary
 * SPA navigation — or, where the host supplies `menu.select`, the host's own switch, which is how
 * the hub keeps the current feature under the new workspace (see WorkspacesMenu.select).
 *
 * What it keeps of the site menu it replaced is what is not about SITES: Help, the settings gear
 * (both {@link helpEntry} / {@link settingsTrailing}, shared with SiteMenu), the site's own nav on
 * a phone, and — for an adh admin — the operations consoles, after Help. Of the family's sites it
 * carries three, the platform's Toolkit, Tools and Support, after Help too: the workspace rail gave
 * them up to the site menu, which this one displaces on a workspace route (see PLATFORM_GROUPS).
 */
export declare function WorkspaceMenu({ menu, userIsAdmin, currentSiteId, resolveHref, personalSlug, hubOffersFeature, onSettings, settingsHref, navLinks, triggerClassName, }: WorkspaceMenuProps): ReactElement;
//# sourceMappingURL=WorkspaceMenu.d.ts.map