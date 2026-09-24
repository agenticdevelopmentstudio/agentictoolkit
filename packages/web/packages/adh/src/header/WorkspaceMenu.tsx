'use client'

import { useCallback, useMemo, type ReactElement } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { ChevronDown } from 'lucide-react'
import { confirmNavigation } from '@agenticdevelopertoolkit/ui/lib/navigation-guard'
import {
  HubMark,
  NavigationPopover,
  type PopoverEntry,
  type PopoverItem,
  type PopoverListEntry,
} from '@agentic-toolkit/adh/header'
// Type-only, so erased: a VALUE import of the sibling would bundle a second copy of its context.
import type { WorkspacesMenu } from './workspaces-menu'
import { useHubPreferences } from '@agentic-toolkit/adh/header/hub-preferences'
import { useHelp } from '@agentic-toolkit/adh/help'
import { useHeaderLinksCollapsed } from './useHeaderLinksCollapsed'
import { buildSiteNavEntries } from './siteNavEntries'
import { menuIcon } from './menu-icons'
import { useSiteMenu } from './useSiteMenu'
import { ADMIN_MENU_GROUPS } from './fleetMenuGroups'
import { helpEntry, settingsTrailing } from './menuChrome'
import type { MenuGroup, SiteMenuChromeProps } from './SiteMenu'

// The workspace rows' section. Distinct from SITE_NAV_SECTION (3), which sits above them on a
// phone, so the divider — and the "Workspaces" heading — fall between the two.
const WORKSPACES_SECTION = 0
// Help closes the list under a divider of its own, apart from the workspaces. The admin
// consoles, for an admin, follow it in ADMIN_SECTION (2) — the number is only required to
// differ from its neighbours', which is what rules a divider between them.
const HELP_SECTION = 1
// Named, because on a phone the site's own nav rows sit above the workspaces in this same
// list, and without a heading nothing says where one population ends and the other begins.
const SECTION_LABELS = { [WORKSPACES_SECTION]: 'Workspaces' }
// A non-admin's tree: nothing. Module-level so the array keeps one identity across renders —
// useSiteMenu memoizes its rows on it.
const NO_GROUPS: MenuGroup[] = []

export type WorkspaceMenuProps = Pick<
  SiteMenuChromeProps,
  // `userIsAdmin` decides whether there are admin rows at all; the four after it are what
  // resolves them exactly as the site menu does (see `adminEntries`).
  | 'userIsAdmin'
  | 'currentSiteId'
  | 'resolveHref'
  | 'personalSlug'
  | 'hubOffersFeature'
  | 'onSettings'
  | 'settingsHref'
  | 'navLinks'
  | 'triggerClassName'
> & {
  /** The signed-in user's workspaces, pre-resolved by the host (see WorkspacesMenuProvider). */
  menu: WorkspacesMenu
}

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
 * a phone, and — for an adh admin — the operations consoles, after Help.
 */
export function WorkspaceMenu({
  menu,
  userIsAdmin,
  currentSiteId,
  resolveHref,
  personalSlug,
  hubOffersFeature,
  onSettings,
  settingsHref,
  navLinks,
  triggerClassName,
}: WorkspaceMenuProps): ReactElement {
  const router = useRouter()
  const pathname = usePathname() ?? '/'
  const { siteMenuShortcut } = useHubPreferences()
  const openHelp = useHelp().open
  const current = menu.workspaces.find((w) => w.current)
  const label = current?.label ?? (menu.loading ? 'Loading…' : 'Workspaces')

  // The rows — or, with none to show, ONE line of text saying why, where the rows would be. Not
  // a row (see PopoverNotice): the "Loading…" / "No workspaces yet" rows this used to push were
  // menuitems the arrow keys landed on and Enter "chose", closing the menu and going nowhere.
  // The three texts are three different facts, so they are told apart: we are still asking; we
  // could not ask — a failed fetch is not an empty account, and telling its owner "No workspaces
  // yet" is false; or the account really has none.
  const workspaceRows = useMemo<PopoverListEntry[]>(() => {
    if (!menu.workspaces.length) {
      return [
        {
          kind: 'notice',
          section: WORKSPACES_SECTION,
          // One key for all three, so a change of text (loading → failed) updates the one live
          // region, which announces it, instead of mounting a new one, which may not be.
          key: 'ws:status',
          text: menu.loading
            ? 'Loading…'
            : menu.error
              ? "Couldn't load your workspaces"
              : 'No workspaces yet',
        },
      ]
    }
    return menu.workspaces.map((w) => ({
      kind: 'leaf',
      section: WORKSPACES_SECTION,
      item: {
        key: `ws:${w.id}`,
        label: w.label,
        href: w.href,
        icon: menuIcon('workspaces'),
        current: w.current,
      },
    }))
  }, [menu])

  // The admin consoles, for an admin — the same rows, resolved the same way (env-aware hrefs,
  // SSO-wrapped when cross-site, `current`-marked), that the site menu appends below the family
  // tree. This menu REPLACES that one for a signed-in hub user, and it used to drop them: an
  // admin on the hub then had no link to a console anywhere — the avatar menu is closed at six
  // rows, the footer's overview leaves admin-only sites out, and the rail carries only the fleet
  // tree. `authenticated: true` because this menu is only ever mounted signed in
  // (SiteMenuSwitcher), so there is no auth state to pass along.
  const { entries: adminEntries, navigate: navigateSiteRow } = useSiteMenu(
    userIsAdmin === true ? ADMIN_MENU_GROUPS : NO_GROUPS,
    { currentSiteId, resolveHref, personalSlug, authenticated: true, hubOffersFeature },
  )

  // The site's own primary nav, exactly while the bar has dropped it (below 768px) — the same
  // hand-over the site menu does, because on a phone whichever menu sits in this slot IS the
  // site's navigation. See SiteMenu's `navSection`.
  const linksCollapsed = useHeaderLinksCollapsed()
  const navSection = useMemo<PopoverEntry[]>(
    () => (linksCollapsed ? buildSiteNavEntries(navLinks, { pathname }) : []),
    [linksCollapsed, navLinks, pathname],
  )

  const entries = useMemo<PopoverListEntry[]>(
    () => [...navSection, ...workspaceRows, helpEntry(openHelp, HELP_SECTION), ...adminEntries],
    [navSection, workspaceRows, openHelp, adminEntries],
  )

  const navigate = useCallback(
    (item: PopoverItem): void => {
      const workspace = menu.workspaces.find((w) => `ws:${w.id}` === item.key)
      // Every other row — the site's own nav on a phone, an admin console — is a site-menu
      // destination, and goes the site menu's way: same-origin through the router, cross-site
      // as a full-page load. A console lives on a host of its own, and a router.push of its
      // absolute URL is not how you get there.
      if (!workspace) {
        navigateSiteRow(item)
        return
      }
      void confirmNavigation().then((ok) => {
        if (!ok) return
        if (menu.select) menu.select(workspace)
        else router.push(workspace.href)
      })
    },
    [menu, router, navigateSiteRow],
  )

  return (
    <NavigationPopover
      entries={entries}
      openShortcut={{ keys: siteMenuShortcut, label: 'Workspace menu' }}
      onChoose={navigate}
      // The NAME starts with exactly the text on screen — "Workspace: <name>" — because a speech
      // user says what they see ("click Workspace Acme"), and a name that began "Acme — switch
      // workspace" did not contain it (WCAG 2.5.3, label in name). The part after the dash says
      // what the button does, which the visible text leaves to the chevron.
      triggerLabel={`Workspace: ${label} — switch workspace`}
      // A lockup rather than icon + text: the mark at twice the site menu's size spans two
      // lines, and a small "Workspace:" caption takes the line above the name, so the name
      // says WHAT it is without growing the bar. The caption is aria-hidden because the
      // trigger's name already carries it: that name is the aria-label above, which replaces
      // the button's content, so hiding the caption changes nothing a screen reader announces.
      triggerContent={
        <>
          <HubMark className="adh-nav-popover__mark adh-workspace-trigger__mark" />
          <span className="adh-workspace-trigger__text">
            <span className="adh-workspace-trigger__caption" aria-hidden>
              Workspace:
            </span>
            <span className="adh-workspace-trigger__name">
              <span className="adh-workspace-trigger__label">{label}</span>
              <ChevronDown className="adh-nav-popover__chevron" aria-hidden />
            </span>
          </span>
        </>
      }
      triggerClassName={triggerClassName}
      placeholder="Search workspaces"
      emptyLabel="No matching workspaces"
      sectionLabels={SECTION_LABELS}
      // The site menu's own gear (signed in by construction — see settingsTrailing).
      commandTrailing={({ close }) => settingsTrailing({ close, onSettings, settingsHref })}
    />
  )
}
