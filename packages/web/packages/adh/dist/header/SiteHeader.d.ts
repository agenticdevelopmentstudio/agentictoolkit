import { type ReactElement } from 'react';
import { type AdhHeaderAuthProps, type HeaderBadge, type NavLink, type RouteSection } from '@agentic-toolkit/adh/header';
import { type HeaderAuthSource } from '@agentic-toolkit/adh/header-auth';
import { type SiteId } from '@agentic-toolkit/adh-registry';
import type { ReactNode } from 'react';
/**
 * Everything the auth SOURCE owns is Omitted from the public props, so a caller can
 * never clobber it: `user`, `onLogin`, `onLogout`, `resolveSwitchHref` and
 * `authLoading` come from `useAuthSource` and nowhere else. The remaining auth fields
 * (`loginHref`, `signupHref`, `onSignup`, `userIsAdmin`, `settingsHref`, `onSettings`)
 * stay settable per site and WIN over a same-named field the source returns — the
 * precedence the two-component version got from `{...auth} {...rest}`.
 */
export type SiteHeaderProps = Omit<AdhHeaderAuthProps, 'user' | 'onLogin' | 'onLogout' | 'resolveSwitchHref' | 'authLoading'> & {
    /** Which site this header belongs to. The display name + the site-switcher's
     *  contents come from the shared sites registry. */
    siteId: SiteId;
    /** Optional page/section title, shown centered in the bar.
     *
     *  Defaults to THIS site's short name — `SiteDef.label`, the name the site menu
     *  lists it under ("Cookbook", "Projects") — so the centre of the bar always says
     *  which site the visitor is on. A page that passes its own title REPLACES that: the
     *  centre is a single absolutely-positioned box, so the two cannot both occupy it. */
    pageTitle?: string;
    /** Optional interactive content centered in the bar (e.g. the status site's live
     *  indicator + refresh). Unlike `pageTitle` it accepts arbitrary nodes and stays
     *  clickable. When set it occupies the centre slot in place of `pageTitle` — and so
     *  in place of the site name that otherwise fills it. */
    center?: ReactNode;
    /** Badges shown under the site name. None by default — the family's preview
     *  notice is the strip the toolkit header draws above the bar, not a badge. */
    badges?: HeaderBadge[];
    /** Site-specific controls injected at the start (left) of the right-hand cluster,
     *  before the nav links + auth. Used for functional controls a site needs in the
     *  bar (e.g. cookbook's search/sidebar/theme). */
    leadingActions?: ReactNode;
    /** Static nav links, or a builder given the signed-in flag — resolved AFTER the auth
     *  source runs, so a site can vary its nav by auth state without reading auth itself
     *  (which keeps the page's own header component hook-free). */
    navLinks?: NavLink[] | ((signedIn: boolean) => NavLink[]);
    trailingNavLinks?: NavLink[];
    /** The words in the full-width strip above the bar, forwarded verbatim to
     *  {@link AdhHeader} (which defaults them to `DEFAULT_PREVIEW_NOTICE`). Every adh
     *  site takes the default today; the prop exists so the strip's copy is reachable
     *  from this side of the boundary rather than sealed into the toolkit package. */
    previewNotice?: string;
    /** The sentence behind the strip's caret, forwarded verbatim to {@link AdhHeader}
     *  (which defaults it to `DEFAULT_PREVIEW_DETAIL`) — same passthrough, and the same
     *  reason, as `previewNotice` above. */
    previewDetail?: string;
    /** Curated route map. UNREAD since the header stopped mounting the dev-tools
     *  dropdown, whose "Routes" flyout was its only reader: the bug glyph that opened it
     *  came out of the bar, its Debug Options row moved to the account end of the header
     *  (see `useDebugOptions`), and the dropdown itself was then deleted with nothing
     *  left to mount it. Kept, not removed, only because sites across the fleet still
     *  pass it — dropping it here would break their builds for no behaviour gained.
     *  @deprecated Nothing reads it. */
    routes?: RouteSection[];
    /** The signed-in user's personal workspace slug, forwarded to the site-switcher as
     *  the in-hub slug fallback on the slug-less workspace routes (`/home`, `/settings/*`).
     *  The hub's header passes the signed-in `user.slug`; harmless (and ignored) off
     *  the hub. */
    personalSlug?: string;
    /** Whether the workspace the visitor is in offers a fleet segment's hub route — forwarded
     *  to {@link useSiteMenu}, which reroutes a site row to `/<slug>/<segment>` only when the
     *  answer is yes. Supplied by the hub (the only host that knows what a workspace TYPE
     *  grants); absent everywhere else, and then no row is rerouted. See UseSiteMenuOpts. */
    hubOffersFeature?: (segment: string) => boolean;
    /** OAuth client id for the login redirect (default 'adh', the shared brand-site
     *  client). Forwarded to the auth source, which decides what to do with it. */
    clientId?: string;
    /** Called after a successful logout — e.g. to navigate away from a gated page.
     *  Consumed only by sources that own a logout; the built-in non-adh sources
     *  receive it via opts and ignore it. */
    onAfterLogout?: () => void;
    /**
     * Inject a different auth source — a hook returning `HeaderAuthState`. Defaults to
     * the anonymous public-site source (a fixed logged-out bar that never reads the
     * session), so a site with no adh AuthProvider above it — the status board — renders
     * fine. The hub and admin pass their own session-reading sources; the
     * marketing/feature-site family passes the shared smart SSO one.
     *
     * Named with the `use` prefix because this component invokes it AS a hook,
     * unconditionally at the top of its body: pass a STABLE, top-level hook, never an
     * inline-redefined function, or hook order breaks between renders.
     */
    useAuthSource?: HeaderAuthSource;
};
/**
 * adh's header: the toolkit's registry-free {@link AdhHeader} plus everything that
 * needs the adh site registry.
 *
 * The split is the point. `@agentic-toolkit/adh`'s header knows about a bar, slots,
 * badges and an auth cluster and nothing else — it resolves no site ids and holds no
 * site list, so a non-adh consumer can use it. Everything registry-shaped lives
 * HERE: the site's display name, the env-aware hub login/signup/settings hrefs, the
 * concept-site "Details" affordance, and adh's real {@link SiteMenuSwitcher} (the
 * marketing/workspace menu taxonomy with its recents and workspaces flyouts),
 * injected through the header's `siteSwitcher` slot.
 *
 * The AUTH wiring is injected too, and for the same reason the switcher is: which
 * session a site reads is the site's business, not the header's. Task 6.2 folded the
 * @adh-shared auth-shim wrapper that used to supply it into this component, so there is
 * one SiteHeader again — a site cannot get the registry half without the auth half.
 */
export declare function SiteHeader({ siteId, pageTitle, center, badges, leadingActions, navLinks, trailingNavLinks, previewNotice, previewDetail, routes: _routes, personalSlug, hubOffersFeature, clientId, onAfterLogout, useAuthSource, ...authOverrides }: SiteHeaderProps): ReactElement;
//# sourceMappingURL=SiteHeader.d.ts.map