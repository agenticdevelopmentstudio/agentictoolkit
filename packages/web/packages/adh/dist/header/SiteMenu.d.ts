import { type ReactElement, type ReactNode } from 'react';
import { type SiteId } from '@agentic-toolkit/adh-registry';
import { type NavLink } from './NavLink';
export type MenuLink = {
    site: SiteId;
    label?: string;
    description?: string;
    external?: boolean;
} | {
    route: string;
    label: string;
    description?: string;
} | {
    href: string;
    label: string;
    description?: string;
    iconKey?: string;
};
export type MenuGroup = {
    kind: 'leaf';
    section: number;
    blurb?: boolean;
    link: MenuLink;
} | {
    kind: 'inline';
    section: number;
    blurb?: boolean;
    link: MenuLink;
} | {
    kind: 'topic';
    section: number;
    label: string;
    links: MenuLink[];
    link?: MenuLink;
    description?: string;
    iconKey?: string;
};
/** The header-chrome props every site menu (and the dispatcher) carry. */
export type SiteMenuChromeProps = {
    /** Which site this header belongs to — marks the "current" row in the menu list.
     *  (The trigger label is always the hub brand, not this site.) */
    currentSiteId: SiteId;
    /** Whether a user is signed in. Gates the settings affordance only (the trigger
     *  label is always the hub brand, regardless of route or auth state). */
    authenticated?: boolean;
    /** Whether the signed-in user is an adh admin. The ONLY flag that changes which
     *  destinations this menu offers: true appends {@link ADMIN_MENU_GROUPS} (the
     *  operations consoles) below the family tree. The {@link WorkspaceMenu} that takes
     *  this menu's place for a signed-in hub user appends the same rows below its Help
     *  row — it is the only switcher an admin on the hub sees, so a flag it dropped left
     *  them no link to a console anywhere. Resolves asynchronously with the
     *  session, so `undefined` and `false` must behave identically — the section
     *  appears when the answer arrives, and a build that never resolves one shows the
     *  same menu as it does to a visitor.
     *
     *  ⚠️ Showing a link is not granting access. Each console does its own
     *  authorization; this decides who is shown the door, nothing more. */
    userIsAdmin?: boolean;
    /** Replaces the trigger's default "Agentic Developer Hub ⌄" content — e.g. a
     *  site's own logo. Used by bitbag.ai to surface the family menu behind its
     *  wordmark. */
    triggerContent?: ReactNode;
    /** Extra class on the trigger button (e.g. to style a logo trigger). */
    triggerClassName?: string;
    /** Transform a cross-site destination href before it's used (link + navigate).
     *  Injected by the auth-aware header: when the user is signed in it wraps the
     *  href into a silent SSO redirect so the target lands ALREADY logged in (no
     *  logged-out flash). Absent ⇒ plain navigation. The current site's own entry
     *  ('/') is never passed through. */
    resolveHref?: (defaultHref: string) => string;
    /** The signed-in user's personal workspace slug, forwarded to {@link useSiteMenu}
     *  as the in-hub slug fallback on the slug-less workspace routes (`/home`,
     *  `/settings/*`). Supplied by the auth-aware header on the hub. */
    personalSlug?: string;
    /** Whether the workspace the visitor is in offers a fleet segment's hub route — forwarded
     *  to {@link useSiteMenu}, which reroutes a site row to `/<slug>/<segment>` only when the
     *  answer is yes. Supplied by the hub (the only host that knows what a workspace TYPE
     *  grants); absent everywhere else, and then no row is rerouted. See UseSiteMenuOpts. */
    hubOffersFeature?: (segment: string) => boolean;
    /** When signed in, the command row swaps the "?" help button for a settings
     *  gear. `onSettings` (preferred) opens an in-app overlay over the current
     *  route; otherwise `settingsHref` makes the gear a link (satellites redirect
     *  to the hub's settings page). Both absent, or signed out ⇒ the "?" help
     *  button. Gated on `authenticated`: settings never show signed out. The
     *  {@link WorkspaceMenu} draws the same gear (see `settingsTrailing`), and with
     *  both absent shows nothing there — it is not the family launcher, so it has no
     *  family overview to offer. */
    settingsHref?: string;
    onSettings?: () => void;
    /** The signed-OUT top-section links (Login / Sign up). Supplied by AdhHeader (its
     *  env-resolved login/signup hrefs); when signed in, or absent, those rows are
     *  omitted (the signed-in top section shows Home / Workspaces / Recents instead). */
    loginHref?: string;
    signupHref?: string;
    /** The host site's OWN primary nav — the same `NavLink[]` the header bar draws.
     *  Surfaced here as rows ONLY while the bar has dropped them, which it does below
     *  768px (`.adh-header__links { display: none }`): the bar cannot hold the brand,
     *  three-plus destinations and the auth cluster inside a 390px phone.
     *
     *  Without this the phone has no primary nav at all. It used to be reachable in the
     *  avatar dropdown, which carried the signed-in nav; that dropdown is an account menu
     *  now, so the destinations have nowhere else to be. Signed OUT was never covered
     *  even then — the media query hides the links at every auth state.
     *
     *  Above the breakpoint these rows are ABSENT, not hidden: see
     *  {@link useHeaderLinksCollapsed}. */
    navLinks?: NavLink[];
};
export type SiteMenuProps = SiteMenuChromeProps & {
    /** The declarative menu config to render — supplied by a config-only subclass
     *  (MarketingSiteMenu / WorkspaceSiteMenu). This base holds ALL the logic; the
     *  subclass holds ONLY this. */
    groups: MenuGroup[];
};
/**
 * The shared site-menu base: the header's site-switcher trigger rendered as a
 * {@link NavigationPopover} command menu, driven entirely by a declarative
 * {@link MenuGroup} config. It owns everything except the content —
 *
 *  - env-aware destination links (cross-site / in-hub for SITE links via hrefFor,
 *    hub routes via routeHref), each resolved once per row;
 *  - the trigger label (always the hub brand — this menu is the family launcher);
 *  - navigation (SPA for same-origin, full-page for cross-site);
 *  - the signed-in settings gear / signed-out help affordance + the "help" search
 *    command that opens the shared sites-overview popover.
 *
 * The config-only subclasses (MarketingSiteMenu, WorkspaceSiteMenu) supply nothing
 * but their `groups`; the dispatcher (SiteMenuSwitcher) picks which to render by route.
 */
export declare function SiteMenu({ groups, currentSiteId, authenticated, userIsAdmin, triggerContent, triggerClassName, resolveHref, personalSlug, hubOffersFeature, settingsHref, onSettings, loginHref, signupHref, navLinks, }: SiteMenuProps): ReactElement;
//# sourceMappingURL=SiteMenu.d.ts.map