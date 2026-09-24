'use client'

import { useMemo, type ReactElement, type ReactNode } from 'react'
import { usePathname } from 'next/navigation'
import { CircleHelp } from 'lucide-react'
// Sibling module, not the '@agentic-toolkit/adh/footer' subpath: a self-referencing package
// specifier would make tsup inline the whole footer entry into this header entry.
import { SITES_OVERVIEW_POPOVER_ID } from '../footer/SitesOverview'
import { getSite, siteHeaderTitle, type SiteId } from '@agentic-toolkit/adh-registry'
import {
  HubMark,
  NavigationPopover,
  useWorkspacesMenu,
  type PopoverEntry,
  type PopoverItem,
} from '@agentic-toolkit/adh/header'
// PRESERVED IMPORT — the recents store's own subpath, never the barrel and never a
// relative path. `recents.ts` holds module-level mutable state (`snapshot`, the
// `listeners` Set); reaching it any other way risks a second copy in this bundle, so
// a visit recorded by the hub's recorder would be invisible to this subscriber. See
// the matching `external` entries in both tsup configs.
import { useRecents } from '@agentic-toolkit/adh/header/recents'
import { useHubPreferences } from '@agentic-toolkit/adh/header/hub-preferences'
import { useSiteMenu } from './useSiteMenu'
import { useHeaderLinksCollapsed } from './useHeaderLinksCollapsed'
import { buildSiteNavEntries } from './siteNavEntries'
import { type NavLink } from './NavLink'
import { menuIcon } from './menu-icons'
import { helpEntry, settingsTrailing } from './menuChrome'
// The section number only — this base renders the Recents flyout that HEADS the fleet
// block, so it has to agree with the rows underneath it or a divider appears between
// them. The tree itself is the subclasses' to supply (see SiteMenuProps.groups).
import { ADMIN_MENU_GROUPS, FLEET_SECTION } from './fleetMenuGroups'
import { StudioWordmark } from './StudioWordmark'
// Package path (the external help entry) so no bundling cost — this pulls only the light
// HelpContext hook, never the code-split window. Safe no-op outside a HelpProvider.
//
// The help subtree lives in @agentic-toolkit/adh (Task 5.5 ported it there from
// the pre-rename @adh-shared/adh, which is how this package briefly depended on the husk).
// Nothing
// temporary remains: the specifier stays a package path, kept out of this bundle by the
// `'@agentic-toolkit/adh/*'` wildcard in tsup.config.ts's `external` — not spelled out
// individually, because that list names only modules holding module-level MUTABLE state
// (see `header/recents` above). This is a React context, and the wildcard is enough to
// keep it a single HelpContext shared with whichever AppShell mounted the provider.
import { useHelp } from '@agentic-toolkit/adh/help'

// ─────────────────────────────────────────────────────────────────────────────
// Declarative config types. A config-only subclass (MarketingSiteMenu /
// WorkspaceSiteMenu) supplies a `MenuGroup[]`; this base turns it into the
// resolved {@link PopoverEntry} rows the engine renders. The subclass declares
// WHAT is in the menu; this base owns HOW each destination link is formed (per
// DEPLOYMENT_ENV), how the trigger reads, and how a chosen row navigates.
//
// A link is either a registry SITE (`site`, resolved via hrefFor — cross-site or
// in-hub, env-aware, SSO-wrapped) or a hub ROUTE (`route`, resolved via routeHref).
// `label`/`description` override the registry defaults. `section` groups rows for
// dividers (a divider falls between sections, never within one).
//
// `external` forces a SITE link to its cross-site deployment URL, at the target's
// landing, even from an in-hub workspace route (where a plain `site` link would
// resolve to the target's `/<slug>/<feature>` workspace view instead). It is for a
// row whose whole purpose is to open the actual site build — never an in-hub route.
// No shipped menu sets it since the dev site-family flyouts that did went with the
// dev-tools dropdown; what it promises is pinned in useSiteMenu.test. See
// useSiteMenu's hrefFor.
export type MenuLink =
  | { site: SiteId; label?: string; description?: string; external?: boolean }
  | { route: string; label: string; description?: string }
  // A destination with no registry site and no in-hub route: an absolute URL,
  // written out. This is how the menu names a site that does not exist as an app
  // yet — the registry cannot carry it, because `registry.test.ts` holds every
  // SiteId to a real folder under `frontend/src/sites/`, and wanting a menu row is
  // not a reason to invent a site.
  //
  // Three things every `{ site }` row gets are absent here, each because the answer
  // does not exist rather than because it was skipped:
  //   - no per-env host mapping (no `testing.`/`staging.` prefix) — the row names ONE
  //     host, and there is no deployment of it in any other environment;
  //   - no SSO wrap — `ssoReturnOrigins` is derived from SITES, so this origin is not
  //     allow-listed, and wrapping the hop would land the visitor on the authorization
  //     server's error instead of the link;
  //   - no `current` marking — "are we on this site?" is a question about a deployment
  //     the family does not have.
  // When the site ships, replace the row with `{ site }` and all three follow.
  | { href: string; label: string; description?: string; iconKey?: string }
export type MenuGroup =
  // A promoted top-level link row (with an optional inline description via `blurb`).
  | { kind: 'leaf'; section: number; blurb?: boolean; link: MenuLink }
  // An always-visible link row INDENTED under the row above it (an inline sub-item,
  // e.g. Hub's ecosystem sites). Renders like a leaf but nested; not a flyout.
  | { kind: 'inline'; section: number; blurb?: boolean; link: MenuLink }
  // A row that opens a cascading flyout submenu of its `links`. `link` makes the
  // trigger itself a destination as well as a disclosure — the shape the fleet menu
  // needs, where "Hub" both opens the hub's sites and IS the hub. Click (or Enter)
  // navigates; hover and → still open the flyout. Omit `link` for a pure grouping
  // header with nowhere of its own to go (Plan, Build).
  //
  // The trigger's icon is `iconKey`'s (a menu-icons key), else the one `link`
  // resolves to — a topic that IS a site wears that site's glyph without restating
  // it. A grouping header has no link, so it must name an `iconKey` to have one.
  | {
      kind: 'topic'
      section: number
      label: string
      links: MenuLink[]
      link?: MenuLink
      description?: string
      iconKey?: string
    }

/** The header-chrome props every site menu (and the dispatcher) carry. */
export type SiteMenuChromeProps = {
  /** Which site this header belongs to — marks the "current" row in the menu list.
   *  (The trigger label is always the hub brand, not this site.) */
  currentSiteId: SiteId
  /** Whether a user is signed in. Gates the settings affordance only (the trigger
   *  label is always the hub brand, regardless of route or auth state). */
  authenticated?: boolean
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
  userIsAdmin?: boolean
  /** Replaces the trigger's default "Agentic Developer Hub ⌄" content — e.g. a
   *  site's own logo. Used by bitbag.ai to surface the family menu behind its
   *  wordmark. */
  triggerContent?: ReactNode
  /** Extra class on the trigger button (e.g. to style a logo trigger). */
  triggerClassName?: string
  /** Transform a cross-site destination href before it's used (link + navigate).
   *  Injected by the auth-aware header: when the user is signed in it wraps the
   *  href into a silent SSO redirect so the target lands ALREADY logged in (no
   *  logged-out flash). Absent ⇒ plain navigation. The current site's own entry
   *  ('/') is never passed through. */
  resolveHref?: (defaultHref: string) => string
  /** The signed-in user's personal workspace slug, forwarded to {@link useSiteMenu}
   *  as the in-hub slug fallback on the slug-less workspace routes (`/home`,
   *  `/settings/*`). Supplied by the auth-aware header on the hub. */
  personalSlug?: string
  /** Whether the workspace the visitor is in offers a fleet segment's hub route — forwarded
   *  to {@link useSiteMenu}, which reroutes a site row to `/<slug>/<segment>` only when the
   *  answer is yes. Supplied by the hub (the only host that knows what a workspace TYPE
   *  grants); absent everywhere else, and then no row is rerouted. See UseSiteMenuOpts. */
  hubOffersFeature?: (segment: string) => boolean
  /** When signed in, the command row swaps the "?" help button for a settings
   *  gear. `onSettings` (preferred) opens an in-app overlay over the current
   *  route; otherwise `settingsHref` makes the gear a link (satellites redirect
   *  to the hub's settings page). Both absent, or signed out ⇒ the "?" help
   *  button. Gated on `authenticated`: settings never show signed out. The
   *  {@link WorkspaceMenu} draws the same gear (see `settingsTrailing`), and with
   *  both absent shows nothing there — it is not the family launcher, so it has no
   *  family overview to offer. */
  settingsHref?: string
  onSettings?: () => void
  /** The signed-OUT top-section links (Login / Sign up). Supplied by AdhHeader (its
   *  env-resolved login/signup hrefs); when signed in, or absent, those rows are
   *  omitted (the signed-in top section shows Home / Workspaces / Recents instead). */
  loginHref?: string
  signupHref?: string
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
  navLinks?: NavLink[]
}

export type SiteMenuProps = SiteMenuChromeProps & {
  /** The declarative menu config to render — supplied by a config-only subclass
   *  (MarketingSiteMenu / WorkspaceSiteMenu). This base holds ALL the logic; the
   *  subclass holds ONLY this. */
  groups: MenuGroup[]
}

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
export function SiteMenu({
  groups,
  currentSiteId,
  authenticated,
  userIsAdmin,
  triggerContent,
  triggerClassName,
  resolveHref,
  personalSlug,
  hubOffersFeature,
  settingsHref,
  onSettings,
  loginHref,
  signupHref,
  navLinks,
}: SiteMenuProps): ReactElement {
  // The trigger is always the hub brand ("Agentic Developer Hub") — this menu is
  // the family launcher, not a breadcrumb, so the label never reflects the site
  // (or workspace area) you're on. The current site is still highlighted in the
  // list (via `currentSiteId` → useSiteMenu).
  const hub = getSite('hub')
  const label = hub ? siteHeaderTitle(hub) : 'Agentic Developer Hub'

  // The tree this render actually shows: the subclass's groups, plus the admin
  // consoles for an admin. Memoized on the flag so the array identity is stable
  // between renders — {@link useSiteMenu} memoizes its rows on it.
  const tree = useMemo(
    () => (userIsAdmin === true ? [...groups, ...ADMIN_MENU_GROUPS] : groups),
    [groups, userIsAdmin],
  )

  // The resolved Hub-core rows + navigation + the Home destination — env-aware,
  // SSO-wrapped, `current`-marked, via the shared {@link useSiteMenu} engine (single
  // source of truth for the link logic).
  const { entries, navigate, homeHref } = useSiteMenu(tree, {
    currentSiteId,
    resolveHref,
    personalSlug,
    authenticated,
    hubOffersFeature,
  })

  // The auth-conditional TOP section, above the fleet tree (section 0, so one divider
  // falls between it and the tree at section 1). Signed out → Login + Sign up. Signed
  // in → Home and an indented Workspaces flyout (hub-only, via context). Recents is
  // NOT here: it heads the fleet block below (see `recentsSection`).
  const pathname = usePathname() ?? '/'
  const workspacesMenu = useWorkspacesMenu()
  const recents = useRecents()
  const { siteMenuShortcut } = useHubPreferences()
  const topSection = useMemo<PopoverEntry[]>(() => {
    if (!authenticated) {
      const out: PopoverEntry[] = []
      if (loginHref) out.push({ kind: 'leaf', section: 0, item: { key: 'login', label: 'Login', href: loginHref, icon: menuIcon('login') } })
      if (signupHref) out.push({ kind: 'leaf', section: 0, item: { key: 'signup', label: 'Sign up', href: signupHref, icon: menuIcon('signup') } })
      return out
    }
    const out: PopoverEntry[] = [
      {
        kind: 'leaf',
        section: 0,
        item: {
          key: 'home',
          label: 'Home',
          href: homeHref,
          icon: menuIcon('home'),
          current: homeHref.startsWith('/') && !homeHref.startsWith('//') && pathname === homeHref,
        },
      },
    ]
    // Workspaces — an indented flyout under Home (hub-only; off-hub there's no
    // provider so it's absent), and only once there is a workspace to list in it.
    // Loading, failed or empty, there is NO flyout rather than one holding a
    // placeholder: a flyout's rows are menuitems, and the "Loading…" row it used to
    // hold was one the arrow keys landed on and Enter "chose" — closing the menu and
    // going nowhere. A line of text in a list is a PopoverNotice, and notices live at
    // the top level; the signed-in hub says loading / failed / empty that way, in the
    // WorkspaceMenu that SiteMenuSwitcher mounts in place of this menu.
    if (workspacesMenu?.workspaces.length) {
      const items: PopoverItem[] = workspacesMenu.workspaces.map((w) => ({
        key: `ws:${w.id}`,
        label: w.label,
        href: w.href,
        current: w.current,
      }))
      out.push({
        kind: 'topic',
        section: 0,
        label: 'Workspaces',
        icon: menuIcon('workspaces'),
        indent: true,
        items,
      })
    }
    return out
  }, [authenticated, loginHref, signupHref, homeHref, workspacesMenu, pathname])

  // Recents — a flyout of the last places visited, newest-first; hidden when empty, and
  // signed-out (the store only ever records workspace routes). It HEADS the fleet block
  // rather than sitting with the chrome above, because it is the same kind of thing as
  // the rows under it: somewhere in the family to go. Hence FLEET_SECTION — a different
  // number here would rule a divider between Recents and the first site.
  //
  // Every row carries an icon, falling back to the hub's mark: the store keys each visit
  // by its feature, and a key this build doesn't know (an older entry persisted by a
  // previous build, a retired feature) would otherwise leave one row in the list blank
  // while its neighbours are iconed. The recorder's own test pins that every LIVE key
  // resolves, so the fallback covers only the stale ones it cannot reach.
  const recentsSection = useMemo<PopoverEntry[]>(() => {
    if (!authenticated || !recents.length) return []
    const items: PopoverItem[] = recents.map((r) => ({
      key: `recent:${r.url}`,
      label: r.label,
      description: r.description,
      href: r.url,
      icon: menuIcon(r.iconKey) ?? menuIcon('hub'),
      current: r.url === pathname,
    }))
    return [
      {
        kind: 'topic',
        section: FLEET_SECTION,
        label: 'Recents',
        description: 'Where you just were',
        icon: menuIcon('recents'),
        items,
      },
    ]
  }, [authenticated, recents, pathname])

  // The host site's own primary nav, surfaced HERE exactly while the bar has dropped
  // it (below 768px). The rows are {@link buildSiteNavEntries}' — a pure builder with
  // its own test — and the gate is
  // {@link useHeaderLinksCollapsed}, which reads the very media query the bar hides on.
  const linksCollapsed = useHeaderLinksCollapsed()
  const navSection = useMemo<PopoverEntry[]>(
    () =>
      linksCollapsed
        ? buildSiteNavEntries(navLinks, {
            // Only signed in does `topSection` above render a Home row for these to
            // duplicate; signed out it is Login / Sign up. Passing `homeHref`
            // regardless would delete community's "Forum" (`/home`) from the menu of
            // an anonymous phone visitor and leave the board unreachable.
            homeHref: authenticated ? homeHref : undefined,
            pathname,
          })
        : [],
    [linksCollapsed, navLinks, authenticated, homeHref, pathname],
  )

  // The Help modal opener — an action row (no navigation), always present regardless of
  // auth. Sits at the foot of the top section (section 0), just above the first divider.
  // The row itself is {@link helpEntry}'s, shared with WorkspaceMenu.
  const openHelp = useHelp().open

  // The full ordered list: the site's own nav (phone only — see navSection), the auth
  // top section closing on the Help row, then the fleet block — Recents at its head,
  // then the tree the subclass supplied.
  //
  // Nothing in this list is gated on the BUILD ENV, so the menu a developer opens is
  // the menu that ships. The dev-only rows this list used to end with (the
  // Marketing/Main site flyouts, Routes, Debug Options) moved to a dev-tools dropdown
  // of their own, and that dropdown is gone too: Debug Options is the account end of
  // the header now (see `useDebugOptions`), and the flyouts had no other host. The
  // single conditional row-set is the admin consoles, gated on the signed-in user's
  // capability rather than on the build (see `tree` above and `userIsAdmin`) — a fact
  // about who is looking, not about which bundle this is.
  //
  // The site's nav goes FIRST because on a phone this menu IS the site's navigation —
  // that is the whole of what the bar handed over. Reaching a page on the site you are
  // already on should not mean scrolling past the family launcher to get to it.
  const allEntries = useMemo<PopoverEntry[]>(
    () => [...navSection, ...topSection, helpEntry(openHelp, 0), ...recentsSection, ...entries],
    [navSection, topSection, recentsSection, entries, openHelp],
  )

  // Open the single shared sites-overview popover (rendered by the always-present
  // footer). Assumes the menu is already closing (the base released focus); the rAF
  // lets Radix finish closing first, and the guard avoids showPopover() throwing if
  // it's somehow already open.
  function showOverview(): void {
    requestAnimationFrame(() => {
      const el = document.getElementById(SITES_OVERVIEW_POPOVER_ID) as
        | (HTMLElement & { showPopover?: () => void; hidePopover?: () => void })
        | null
      if (!el || el.matches(':popover-open')) return
      try {
        el.showPopover?.()
      } catch {
        return /* popover unsupported — no-op */
      }
      el.focus?.()
      // A popover opened programmatically (no invoker, focus elsewhere) isn't
      // reliably dismissed by the UA's Escape handling across browsers, so close it
      // explicitly. Capture-phase + self-cleanup on the popover's `toggle`.
      const onKeyDown = (e: globalThis.KeyboardEvent) => {
        if (e.key === 'Escape') el.hidePopover?.()
      }
      const onToggle = () => {
        if (!el.matches(':popover-open')) {
          document.removeEventListener('keydown', onKeyDown, true)
          el.removeEventListener('toggle', onToggle)
        }
      }
      document.addEventListener('keydown', onKeyDown, true)
      el.addEventListener('toggle', onToggle)
    })
  }

  return (
    <NavigationPopover
      entries={allEntries}
      // The site menu is the ONE popover that claims a global chord — it is the
      // fleet's front door, and the user picks which chord in Settings ▸ Hub
      // Preferences. An empty string there means they turned it off, and
      // NavigationPopover takes that as "no shortcut" rather than falling back.
      openShortcut={{ keys: siteMenuShortcut, label: 'Site menu' }}
      onChoose={navigate}
      triggerLabel={`${label} — switch site`}
      triggerText={label}
      // The hub brand mark before the label (currentColor ⇒ it rides the
      // trigger's accent color and hover brightening with the text).
      triggerIcon={<HubMark className="adh-nav-popover__mark" />}
      triggerContent={triggerContent}
      triggerClassName={triggerClassName}
      placeholder="Search sites, or browse topics"
      emptyLabel="No matching sites"
      // The studio the whole family sits under, closing the menu below its own
      // divider. Not a row: it is the signature on the tree, not a place in it.
      footer={<StudioWordmark />}
      // Typing "help" surfaces a command that opens the family-overview popover.
      searchCommand={{
        matches: (q) => q.toLowerCase() === 'help',
        label: 'Help — about the sites',
        shortcut: 'overview',
        onSelect: showOverview,
      }}
      // The command-row trailing control: signed in, the settings gear (in-app overlay
      // or hub link — {@link settingsTrailing}'s, shared with WorkspaceMenu); signed out,
      // or signed in on a host with no settings surface, the family-overview "?" button.
      commandTrailing={({ close }) => {
        const gear = authenticated ? settingsTrailing({ close, onSettings, settingsHref }) : null
        return (
          gear ?? (
            <button
              type="button"
              className="adh-site-switcher__help"
              aria-label="About the Agentic Developer family"
              onClick={() => {
                close({ restoreFocus: false })
                showOverview()
              }}
            >
              <CircleHelp className="adh-site-switcher__help-icon" aria-hidden />
            </button>
          )
        )
      }}
    />
  )
}
