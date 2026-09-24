import { type ReactElement } from 'react';
import { type SiteMenuChromeProps } from './SiteMenu';
export type SiteMenuSwitcherProps = SiteMenuChromeProps;
/**
 * The header site-name dropdown — a thin DISPATCHER with no menu content of its
 * own. It picks one of the two config-only site menus by ROUTE: on an app route on
 * the hub (`/home` or a feature route like `/ecosystems`) it renders the
 * {@link WorkspaceSiteMenu}; on the marketing landing `/`, every other hub page,
 * satellites, and signed out it renders the {@link MarketingSiteMenu}. All menu
 * logic lives in {@link SiteMenu}; the two configs are fully independent.
 *
 * REGISTRY-AWARE composition (adh's site menu taxonomy — recents, workspaces, the
 * fleet tree). Named `SiteMenuSwitcher` rather than `SiteSwitcher`: this package already
 * has a `SiteSwitcher` — the registry-FREE primitive (plain caller-supplied
 * `sites` list, no menu taxonomy) that `AdhHeader`'s `siteSwitcher` slot expects.
 * The two are unrelated components that happen to share a role name; this one is
 * adh's actual switcher, injected through that slot by {@link SiteHeader}.
 *
 * SIGNED IN, ON A WORKSPACE ROUTE, on a host that supplies the user's workspaces (the hub, via
 * WorkspacesMenuProvider), the fleet menu is set aside and the slot holds the
 * {@link WorkspaceMenu} instead — inside the product, switching workspace is the everyday move.
 * Everywhere else — the landing `/` and the other marketing routes, even signed in — keeps the
 * site menu: the swap once ignored the route and took the site menu off `/` for every signed-in
 * visitor (Mike, 2026-09-24). A host with no provider (every satellite) keeps the site menu at
 * every auth state: it has no workspaces to offer.
 *
 * The swap drops what is about SITES (the family tree, Home, Recents), the signed-out rows (which
 * cannot apply) and `triggerContent` (the WorkspaceMenu's trigger is its own). Everything else
 * passes through — `userIsAdmin` above all: on a workspace route the WorkspaceMenu is the only
 * switcher a signed-in admin sees, and the admin consoles have no other door there.
 */
export declare function SiteMenuSwitcher(props: SiteMenuSwitcherProps): ReactElement;
//# sourceMappingURL=SiteMenuSwitcher.d.ts.map