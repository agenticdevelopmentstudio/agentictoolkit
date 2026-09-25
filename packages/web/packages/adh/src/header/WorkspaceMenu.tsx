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
// Help, then the platform's rows (PLATFORM_GROUPS), close the list under a divider of their
// own, apart from the workspaces. The admin consoles, for an admin, follow them in
// ADMIN_SECTION (2) — the number is only required to differ from its neighbours', which is
// what rules a divider between them.
const HELP_SECTION = 1
// Named, because on a phone the site's own nav rows sit above the workspaces in this same
// list, and without a heading nothing says where one population ends and the other begins.
const SECTION_LABELS = { [WORKSPACES_SECTION]: 'Workspaces' }
// The platform's front door, for everyone: Toolkit, Tools and Support. They closed every
// workspace's rail until 2026-09-24, when they left it because "the site menu already carries
// them" — but on a /<workspace>/* route a signed-in user's menu slot holds THIS menu, not the
// site menu, so with nothing here they had no door on a workspace route at all. Help is not
// among them: the Help row above them already answers it, by opening the help panel.
// Resolved by useSiteMenu like any site row — the hub's own `/<slug>/<segment>` route where
// the workspace offers it (`hubOffersFeature`), the site's own host otherwise (a team slug).
// Module-level, both arrays, so each keeps one identity across renders — useSiteMenu memoizes
// its rows on it.
const PLATFORM_GROUPS: MenuGroup[] = (['toolkit', 'tools', 'support'] as const).map(
  (site): MenuGroup => ({ kind: 'leaf', section: HELP_SECTION, link: { site } }),
)
// An admin's tree: the same platform rows, then the operations consoles.
const PLATFORM_AND_ADMIN_GROUPS: MenuGroup[] = [...PLATFORM_GROUPS, ...ADMIN_MENU_GROUPS]

export type WorkspaceMenuProps = Pick<
  SiteMenuChromeProps,
  // `userIsAdmin` decides whether there are admin rows at all; the four after it are what
  // resolves them, and the platform's rows, exactly as the site menu does (see `siteEntries`).
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
 * a phone, and — for an adh admin — the operations consoles, after Help. Of the family's sites it
 * carries three, the platform's Toolkit, Tools and Support, after Help too: the workspace rail gave
 * them up to the site menu, which this one displaces on a workspace route (see PLATFORM_GROUPS).
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
  // "Workspace" follows a real name only: "Loading… Workspace" and "Workspaces Workspace" are
  // not phrases, and a placeholder is not a workspace you are in. Nor does it follow a label that
  // already ends in the word: the hub labels a nameless workspace "My Workspace" or "Workspace"
  // (its workspaceListLabel), and the trigger read "My Workspace Workspace".
  const suffixed = current != null && !/\bworkspace$/i.test(label.trim())
  const triggerText = suffixed ? `${label} Workspace` : label

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

  // The site rows, resolved the way the site menu resolves its own (env-aware hrefs, SSO-wrapped
  // when cross-site, onto the hub's own route where the workspace offers one, `current`-marked):
  // the platform's Toolkit, Tools and Support for everyone (see PLATFORM_GROUPS), then, for an
  // admin, the consoles the site menu appends below the family tree. This menu REPLACES that one
  // for a signed-in hub user on a workspace route (SiteMenuSwitcher), and it used to drop the
  // consoles: an admin on the hub then had no link to a console anywhere — the avatar menu is
  // closed at six rows, the footer's overview leaves admin-only sites out, and the rail carries
  // only the fleet tree. `authenticated: true` because this menu is only ever mounted signed in
  // (SiteMenuSwitcher), so there is no auth state to pass along.
  const { entries: siteEntries, navigate: navigateSiteRow } = useSiteMenu(
    userIsAdmin === true ? PLATFORM_AND_ADMIN_GROUPS : PLATFORM_GROUPS,
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
    () => [...navSection, ...workspaceRows, helpEntry(openHelp, HELP_SECTION), ...siteEntries],
    [navSection, workspaceRows, openHelp, siteEntries],
  )

  const navigate = useCallback(
    (item: PopoverItem): void => {
      const workspace = menu.workspaces.find((w) => `ws:${w.id}` === item.key)
      // Every other row — the site's own nav on a phone, a platform row, an admin console — is a
      // site-menu destination, and goes the site menu's way: same-origin through the router,
      // cross-site as a full-page load. A console lives on a host of its own, and a router.push
      // of its absolute URL is not how you get there.
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
      // The NAME starts with exactly the text on screen — "<name> Workspace" — because a speech
      // user says what they see ("click Acme Workspace"), and a name that did not contain it
      // fails WCAG 2.5.3 (label in name). The part after the dash says what the button does,
      // which the visible text leaves to the chevron.
      triggerLabel={`${triggerText} — switch workspace`}
      // One line: the mark, the name, then the word "Workspace", so the name says WHAT it is. It
      // replaced a small "Workspace:" caption stacked above the name (Mike, 2026-09-24). The word
      // is on the TRIGGER only — a menu row is already under a "Workspaces" heading. It is its
      // own span so that a long name clips before it, and the word never does.
      triggerContent={
        <>
          <HubMark className="adh-nav-popover__mark" />
          <span className="adh-workspace-trigger__name">
            <span className="adh-workspace-trigger__label">{label}</span>
            {suffixed ? <span className="adh-workspace-trigger__suffix">Workspace</span> : null}
            <ChevronDown className="adh-nav-popover__chevron" aria-hidden />
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
