'use client'

import { type ReactElement } from 'react'
import dynamic from 'next/dynamic'
import { usePathname } from 'next/navigation'
import {
  AdhHeader,
  useClientHost,
  type AdhHeaderAuthProps,
  type HeaderBadge,
  type NavLink,
  type RouteSection,
} from '@agentic-toolkit/adh/header'
// The auth-source contract + the public-site default. Its own subpath, not the header
// barrel: it is the only header module that value-imports @agentic-toolkit/auth, so a
// site that renders a nav link should not pull the auth package in behind it.
import { useAnonymousHeaderAuth, type HeaderAuthSource } from '@agentic-toolkit/adh/header-auth'
import { getSite, siteHeaderTitle, siteHomePath, siteProdUrl, siteUrl, type SiteId } from '@agentic-toolkit/adh-registry'
// The participation leaf, not the '@agentic-toolkit/adh/concepts' barrel: this needs one
// predicate, and the barrel would put the whole taxonomy (structure + content JSON)
// behind the always-loaded header. PRESERVED IMPORT — the package path, never
// '../concepts/participating': the concepts barrel reaches the same module, and a
// relative specifier would give this entry its own copy of its module-level Set.
import { isConceptSite } from '@agentic-toolkit/adh/concepts/participating'
// The shared User Settings overlay AppShell mounts around every site (Task 8). Package
// path, not a relative one — same self-reference reason as `isConceptSite` above, and
// see the matching `external` entry in tsup.config.ts: a relative specifier here would
// fork SettingsOverlayContext from the copy AppShell.tsx's provider writes into, so this
// hook would always read null even with a provider mounted.
import { useSettingsOverlay } from '@agentic-toolkit/adh/settings'
import { hasProfileRoute } from '../profile/profileRoute'
import { SiteMenuSwitcher } from './SiteMenuSwitcher'
import { useDebugOptions } from './useDebugOptions'
import { SITE_TITLE_HELP_ID } from '@agentic-toolkit/adh-ui/help-ids'

import type { ReactNode } from 'react'

// The notification inbox, mounted for every signed-in visitor of every site in the
// family (see `accountActions` below). Code-split for the same reason useDebugOptions
// splits the debug console, and here it is load-bearing rather than a nicety: this
// header ships on every PUBLIC page, and `@agentic-toolkit/messaging` reaches
// `@agentic-toolkit/data` for its SSE wake channel — the one dependency the header
// entry has always kept out of its static graph (see the `home/index` note in
// tsup.config.ts). A dynamic specifier keeps that true where it counts: an anonymous
// visitor never fetches the chunk, because nothing renders it until `user != null`.
const NotificationBell = dynamic(() =>
  import('@agentic-toolkit/messaging/components/notification-bell').then((m) => m.NotificationBell),
)

/**
 * Everything the auth SOURCE owns is Omitted from the public props, so a caller can
 * never clobber it: `user`, `onLogin`, `onLogout`, `resolveSwitchHref` and
 * `authLoading` come from `useAuthSource` and nowhere else. The remaining auth fields
 * (`loginHref`, `signupHref`, `onSignup`, `userIsAdmin`, `settingsHref`, `onSettings`)
 * stay settable per site and WIN over a same-named field the source returns — the
 * precedence the two-component version got from `{...auth} {...rest}`.
 */
export type SiteHeaderProps = Omit<
  AdhHeaderAuthProps,
  'user' | 'onLogin' | 'onLogout' | 'resolveSwitchHref' | 'authLoading'
> & {
  /** Which site this header belongs to. The display name + the site-switcher's
   *  contents come from the shared sites registry. */
  siteId: SiteId
  /** Optional page/section title, shown centered in the bar.
   *
   *  Defaults to THIS site's short name — `SiteDef.label`, the name the site menu
   *  lists it under ("Cookbook", "Projects") — so the centre of the bar always says
   *  which site the visitor is on. A page that passes its own title REPLACES that: the
   *  centre is a single absolutely-positioned box, so the two cannot both occupy it. */
  pageTitle?: string
  /** Optional interactive content centered in the bar (e.g. the status site's live
   *  indicator + refresh). Unlike `pageTitle` it accepts arbitrary nodes and stays
   *  clickable. When set it occupies the centre slot in place of `pageTitle` — and so
   *  in place of the site name that otherwise fills it. */
  center?: ReactNode
  /** Badges shown under the site name. None by default — the family's preview
   *  notice is the strip the toolkit header draws above the bar, not a badge. */
  badges?: HeaderBadge[]
  /** Site-specific controls injected at the start (left) of the right-hand cluster,
   *  before the nav links + auth. Used for functional controls a site needs in the
   *  bar (e.g. cookbook's search/sidebar/theme). */
  leadingActions?: ReactNode
  /** Static nav links, or a builder given the signed-in flag — resolved AFTER the auth
   *  source runs, so a site can vary its nav by auth state without reading auth itself
   *  (which keeps the page's own header component hook-free). */
  navLinks?: NavLink[] | ((signedIn: boolean) => NavLink[])
  trailingNavLinks?: NavLink[]
  /** The words in the full-width strip above the bar, forwarded verbatim to
   *  {@link AdhHeader} (which defaults them to `DEFAULT_PREVIEW_NOTICE`). Every adh
   *  site takes the default today; the prop exists so the strip's copy is reachable
   *  from this side of the boundary rather than sealed into the toolkit package. */
  previewNotice?: string
  /** The sentence behind the strip's caret, forwarded verbatim to {@link AdhHeader}
   *  (which defaults it to `DEFAULT_PREVIEW_DETAIL`) — same passthrough, and the same
   *  reason, as `previewNotice` above. */
  previewDetail?: string
  /** Curated route map. UNREAD since the header stopped mounting the dev-tools
   *  dropdown, whose "Routes" flyout was its only reader: the bug glyph that opened it
   *  came out of the bar, its Debug Options row moved to the account end of the header
   *  (see `useDebugOptions`), and the dropdown itself was then deleted with nothing
   *  left to mount it. Kept, not removed, only because sites across the fleet still
   *  pass it — dropping it here would break their builds for no behaviour gained.
   *  @deprecated Nothing reads it. */
  routes?: RouteSection[]
  /** The signed-in user's personal workspace slug, forwarded to the site-switcher as
   *  the in-hub slug fallback on the slug-less workspace routes (`/home`, `/settings/*`).
   *  The hub's header passes the signed-in `user.slug`; harmless (and ignored) off
   *  the hub. */
  personalSlug?: string
  /** Whether the workspace the visitor is in offers a fleet segment's hub route — forwarded
   *  to {@link useSiteMenu}, which reroutes a site row to `/<slug>/<segment>` only when the
   *  answer is yes. Supplied by the hub (the only host that knows what a workspace TYPE
   *  grants); absent everywhere else, and then no row is rerouted. See UseSiteMenuOpts. */
  hubOffersFeature?: (segment: string) => boolean
  /** OAuth client id for the login redirect (default 'adh', the shared brand-site
   *  client). Forwarded to the auth source, which decides what to do with it. */
  clientId?: string
  /** Called after a successful logout — e.g. to navigate away from a gated page.
   *  Consumed only by sources that own a logout; the built-in non-adh sources
   *  receive it via opts and ignore it. */
  onAfterLogout?: () => void
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
  useAuthSource?: HeaderAuthSource
}

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
export function SiteHeader({
  siteId,
  pageTitle,
  center,
  badges,
  leadingActions,
  navLinks,
  trailingNavLinks = [],
  previewNotice,
  previewDetail,
  // Destructured only to keep it out of `authOverrides`; see its @deprecated note.
  routes: _routes,
  personalSlug,
  hubOffersFeature,
  clientId,
  onAfterLogout,
  useAuthSource = useAnonymousHeaderAuth,
  ...authOverrides
}: SiteHeaderProps): ReactElement {
  // The chosen source is the ONLY one invoked, unconditionally and first, so its own
  // hooks run in a stable order ahead of this component's — and a site with no adh
  // AuthProvider (status) never reaches a `useAuth()` at all, because the default
  // source has none.
  // `siteId` rides along so a session-aware source can resolve THIS site's post-login
  // landing without being rebuilt per site (MarketingSiteHeader builds one source at
  // module scope for the whole family).
  const source = useAuthSource({ clientId, siteId, onAfterLogout })
  // Source first, caller's explicit props last: the source owns the five fields
  // SiteHeaderProps Omits (so `authOverrides` structurally cannot carry them), while a
  // site's static header config (loginHref, settingsHref, …) still wins over a
  // same-named field the source happened to return. Exactly the precedence the
  // `{...auth} {...rest}` spread in the retired wrapper produced.
  const {
    resolveSwitchHref,
    user,
    userIsAdmin,
    authLoading = false,
    loginHref,
    signupHref,
    onLogin,
    onSignup,
    onLogout,
    settingsHref,
    onSettings,
  } = { ...source, ...authOverrides }
  // The shared overlay AppShell mounts around every site (Task 8). A host may still pass
  // its own onSettings (source or authOverrides, above) — that wins unconditionally, same
  // precedence as every other auth field. Otherwise fall back to the context AppShell
  // supplies, but ONLY once signed in: a signed-out visitor gets no settings row regardless
  // of whether a provider is mounted, matching AdhHeader's own signed-out-vs-signed-in
  // avatar-menu gate. `overlay` is null with no SettingsOverlayProvider above this header at
  // all (a host that renders SiteHeader outside the shared AppShell) — that null propagates
  // through to `undefined` below, so the row is correctly omitted rather than dead.
  const overlay = useSettingsOverlay()
  const resolvedOnSettings = onSettings ?? (user != null ? overlay?.openSettings : undefined)
  // The Debug Options door. It used to be a bug-glyph dropdown of its own beside the
  // site menu; that glyph is gone by the repo owner's instruction, and Debug Options —
  // the one row in it anybody reached for — lives at the account end of the header now:
  // the avatar menu's last row signed in, a Debug Options button beside login / join
  // signed out (AdhHeader draws whichever applies from the one `onDebugOptions`). Same
  // gate as the dropdown's (a dev build on a dev host, or an adh admin), so an ordinary
  // production visitor gets neither.
  const debugOptions = useDebugOptions(userIsAdmin)
  // Auth-dependent nav resolved HERE, after the source decided signed-in-or-not, so a
  // page's header component doesn't need its own useAuth() read just to vary its nav.
  const resolvedNavLinks = (typeof navLinks === 'function' ? navLinks(user != null) : navLinks) ?? []

  // Login/Join live on the hub for every site. A site can override with its own
  // hrefs (the hub passes local /login, /signup); otherwise default to the hub's
  // auth in the current environment. Null on the server + first client render
  // (deterministic — no hydration mismatch), then the env-aware host once mounted.
  const hostname = useClientHost()

  // Concept-graph sites carry a prominent "Details" link before the auth links.
  // Env is read client-side from the hostname (null on SSR/first render → links
  // appear after hydration), mirroring how the auth hrefs upgrade — deterministic,
  // no hydration mismatch.
  const conceptSite = isConceptSite(siteId)
  // ...and only on the site's landing page. The link is a front-door affordance;
  // on an inner page it points back at something the reader has already passed.
  //
  // `usePathname()`, NOT `window.location.pathname` — which is what `defaultReturnTo`
  // in header-auth.ts reads, and is the wrong tool here. That one runs once to build
  // an href; this decides whether a node RENDERS, so it has to re-decide on every
  // navigation. `window.location` is not reactive: under the App Router a soft nav
  // from `/` to an inner page re-renders nothing that reads it, and the Details link
  // would stay on screen for the rest of the session — the exact bug being fixed.
  const onLandingPage = usePathname() === '/'
  // The registry-derived brand name. `siteHeaderTitle` takes the SiteDef, not the id;
  // an unknown id can't happen through the typed `SiteId`, but `getSite` is
  // nominally partial, so fall back to the id rather than widening its return.
  const site = getSite(siteId)
  const siteName = site ? siteHeaderTitle(site) : siteId
  // The centre of the bar names the CURRENT site, on every site in the family. Nothing
  // else in the bar does: the site-menu trigger always reads the hub brand (a site's own
  // `currentSiteId` only marks its row inside the menu), and `siteName` above reaches no
  // rendered node while adh fills the switcher slot — so without this every header in the
  // fleet is byte-identical chrome that never says where you are.
  //
  // `label`, not `fullLabel` or `shortLabel`: it is the registry's SHORT name — the one
  // the site menu lists the site under — which is what a "you are here" marker wants, and
  // it is defined for every site (the other two are optional refinements of it).
  //
  // A DEFAULT of a prop every site already passes through, not a new slot, so the whole
  // fleet gets it without a per-site opt-in and a page keeps the last word.
  const siteShortName = site?.label ?? siteId
  const resolveHubHref = (path: string): string =>
    hostname ? siteUrl('hub', path, hostname) : siteProdUrl('hub', path)
  // Default Login / Sign up carry a `?return_to=` back to THIS site's post-login
  // landing (its /home, or root when it has none), so the hub's /login + /signup
  // send the visitor back here once signed in instead of stranding them on the
  // hub's own /home. `return_to` (the visitor-facing destination) is deliberately
  // NOT the AS's internal `?return=` central-relay callback — hub /login treats
  // those differently (a `return=` relay means no central session yet, so it shows
  // the card; a `return_to` link means "bounce me back once recognized"). See
  // docs/platform/login-and-return.md. Deterministic prod host on SSR/first render
  // (mirrors the hub hrefs above), env-aware once mounted. Skipped when the site
  // drives auth itself (onLogin/onSignup handler) or overrides the href.
  const selfReturn = hostname
    ? siteUrl(siteId, siteHomePath(siteId), hostname)
    : siteProdUrl(siteId, siteHomePath(siteId))
  const hubAuthHref = (path: string): string =>
    `${resolveHubHref(path)}?return_to=${encodeURIComponent(selfReturn)}`
  const resolvedLoginHref = loginHref ?? (onLogin ? undefined : hubAuthHref('/login'))
  const resolvedSignupHref = signupHref ?? (onSignup ? undefined : hubAuthHref('/signup'))

  // The signed-in settings gear in the switcher: prefer the host's in-app overlay
  // (resolvedOnSettings — a caller's own handler, or the shared one AppShell's provider
  // supplies); otherwise make the gear a link — to the site's own settingsHref if it set
  // one, else the hub's settings page (satellites redirect there). Only a link target
  // here; the switcher gates its visibility on `user != null`.
  //
  // `/settings`, not `/home/settings`: the account pages moved off `/home` when that segment
  // became the family's workspace redirect. The old path is still a redirect source in the hub's
  // next.config.ts, so this kept working — one wasted hop, and a link that reads as a route the
  // hub no longer has.
  const switcherSettingsHref = resolvedOnSettings
    ? undefined
    : (settingsHref ?? resolveHubHref('/settings'))

  return (
    <>
      <AdhHeader
        // The registry-derived display name. adh always fills the `siteSwitcher` slot
        // below, so this reaches no rendered node today — it is passed because it is
        // the honest value, and because it is what the toolkit's default switcher
        // would show if the slot were ever dropped.
        siteName={siteName}
        siteSwitcher={
          <SiteMenuSwitcher
            currentSiteId={siteId}
            resolveHref={resolveSwitchHref}
            personalSlug={personalSlug}
            hubOffersFeature={hubOffersFeature}
            authenticated={user != null}
            // Appends the admin consoles — below the family tree, or below the hub's
            // workspace list — and nothing else: the rest of either menu is identical
            // for an admin. See SiteMenu's `userIsAdmin` for why showing the rows is
            // not the same as granting the access.
            userIsAdmin={userIsAdmin}
            onSettings={resolvedOnSettings}
            settingsHref={switcherSettingsHref}
            // Signed-out top section: the menu's Login / Sign up rows reuse the same
            // env-resolved hrefs as the header's auth buttons (omitted when the site
            // uses onLogin/onSignup callbacks instead of hrefs).
            loginHref={resolvedLoginHref}
            signupHref={resolvedSignupHref}
            // This site's own primary nav, so the menu can carry it on a phone — where
            // the bar hides `.adh-header__links` and would otherwise leave the site with
            // no primary navigation at all. `resolvedNavLinks`, not the raw prop: the
            // menu must offer the same destinations the bar would, for the same auth
            // state. `trailingNavLinks` is deliberately not included — it renders outside
            // the collapsing group and survives the phone bar already.
            navLinks={resolvedNavLinks}
          />
        }
        // The site's short name unless the page named itself — see `siteShortName`.
        pageTitle={pageTitle ?? siteShortName}
        // Only when the page named nothing — see AdhHeader's `pageTitleHelp`.
        //
        // `== null`, matching the `??` above rather than a truthiness test: a page
        // that passes `pageTitle=""` names itself with an empty string, so `??` keeps
        // that empty string while `?` would fall through to the site help — annotating
        // a title the site never wrote with copy about a different subject.
        pageTitleHelp={pageTitle == null ? SITE_TITLE_HELP_ID : undefined}
        // Last resort for the three layouts that mount no populated provider:
        // `admin`, `hub-help` and `status` are the only sites of the 44 whose
        // layout does not spread `site.shell` — none of them has a `site.config.ts`
        // at all, so `defineSite` never runs and there is nothing to spread. The
        // registry's own one-line `description` is defined for every site, so the
        // site name still explains itself there instead of warning to the console.
        pageTitleHelpFallback={site?.description}
        center={center}
        badges={badges}
        leadingActions={leadingActions}
        navLinks={resolvedNavLinks}
        trailingNavLinks={trailingNavLinks}
        // Undefined on every adh site today, which is exactly what makes AdhHeader's
        // default apply — a default parameter, so forwarding `undefined` is the same as
        // not forwarding at all. The point of the passthrough is that the words are
        // REACHABLE from here.
        previewNotice={previewNotice}
        previewDetail={previewDetail}
        // The avatar menu's "Home" — THIS site's post-login landing (its /home, or root
        // when it has none), the same destination the default Login/Join links already
        // return to. A relative path, not `selfReturn`'s absolute URL: Home never leaves
        // the site, so it should navigate client-side rather than reload through the
        // env-resolved origin.
        homeHref={siteHomePath(siteId)}
        // The avatar menu's Profile row: present only when BOTH the signed-in account has
        // a slug (a stranger with no slug has no profile address at all) AND this site
        // actually carries the `/<slug>/profile` route — `hasProfileRoute` reads that off
        // the generated per-site route map, not a maintained list, so a site gaining or
        // dropping the route can't drift out of step with this gate. Without the second
        // half every site in the family would offer the row and three of them (today)
        // would send it to a 404.
        profileHref={
          user?.slug && hasProfileRoute(siteId)
            ? `/${encodeURIComponent(user.slug)}/profile`
            : undefined
        }
        // Concept-graph affordances, before the auth cluster. A plain anchor so it
        // works pre-hydration and resolves the real route. The `/details` path and the
        // "Details" copy are adh vocabulary and stay on this side of the boundary.
        preAuthLinks={
          conceptSite && onLandingPage ? (
            <a href="/details" className="adh-header__nav-link adh-header__nav-link--details">
              Details
            </a>
          ) : undefined
        }
        // The notification inbox, on every site in the family rather than on the one
        // that happened to mount it. It is the ONLY surface for account and
        // announcement notifications, so it follows the SESSION, not the site: a
        // visitor signed in on `projects` has the same unread mail as on the hub, and a
        // bell that appears only after they navigate home is a bell they will not find.
        //
        // Gated on `user`, the same value the avatar cluster below reads — so the bell
        // and the avatar can never disagree about whether anyone is signed in, and a
        // site whose auth source never reads a session (the status board's
        // `useAnonymousHeaderAuth`) mounts nothing and issues no request. `authLoading`
        // is deliberately NOT part of the gate: the spinner branch below already owns
        // that window, and `user` is null throughout it.
        accountActions={user != null ? <NotificationBell /> : undefined}
        user={user}
        authLoading={authLoading}
        loginHref={resolvedLoginHref}
        signupHref={resolvedSignupHref}
        onLogin={onLogin}
        onSignup={onSignup}
        onLogout={onLogout}
        settingsHref={settingsHref}
        onSettings={resolvedOnSettings}
        onDebugOptions={debugOptions.onOpen}
        debugOptionsHint={debugOptions.hint}
      />
      {debugOptions.window}
    </>
  )
}
