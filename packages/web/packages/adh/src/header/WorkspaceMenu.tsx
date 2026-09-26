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
import { helpEntry, settingsTrailing } from './menuChrome'
import type { MenuGroup, SiteMenuChromeProps } from './SiteMenu'

// The workspace rows' section. Distinct from SITE_NAV_SECTION (3), which sits above them on a
// phone, so the divider — and the "Workspaces" heading — fall between the two.
const WORKSPACES_SECTION = 0
// Help closes the list under a divider of its own, apart from the workspaces.
const HELP_SECTION = 1
// Named, because on a phone the site's own nav rows sit above the workspaces in this same
// list, and without a heading nothing says where one population ends and the other begins.
const SECTION_LABELS = { [WORKSPACES_SECTION]: 'Workspaces' }
// No site rows. The platform's Toolkit, Tools and Support, and an admin's operations consoles,
// used to close this list; Mike took them out on 2026-09-26 — this menu is the WORKSPACES.
// That is not a like-for-like swap. The hub's Admin workspace (listed among the workspaces by the
// host, for an admin) carries the admin site's sections, but Builds and Fleet Monitor were
// consoles with no Admin section, and they lost their door on a workspace route: an admin reaches
// them from the site menu on the landing and the marketing routes (ADMIN_MENU_GROUPS), and from
// nowhere inside a workspace. The same holds for Toolkit, Tools and Support.
// useSiteMenu is still called for its `navigate`, which the phone's nav rows go through.
// Module-level so it keeps one identity across renders — useSiteMenu memoizes its rows on it.
const NO_SITE_GROUPS: MenuGroup[] = []

export type WorkspaceMenuProps = Pick<
  SiteMenuChromeProps,
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
 * (both {@link helpEntry} / {@link settingsTrailing}, shared with SiteMenu), and the site's own
 * nav on a phone. It carries no site rows (see NO_SITE_GROUPS).
 */
export function WorkspaceMenu({
  menu,
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

  // Only for its `navigate`, which the phone's nav rows go through: there are no site rows (see
  // NO_SITE_GROUPS). `authenticated: true` because this menu is only ever mounted signed in
  // (SiteMenuSwitcher), so there is no auth state to pass along.
  const { navigate: navigateSiteRow } = useSiteMenu(NO_SITE_GROUPS, {
    currentSiteId,
    resolveHref,
    personalSlug,
    authenticated: true,
    hubOffersFeature,
  })

  // The site's own primary nav, exactly while the bar has dropped it (below 768px) — the same
  // hand-over the site menu does, because on a phone whichever menu sits in this slot IS the
  // site's navigation. See SiteMenu's `navSection`.
  const linksCollapsed = useHeaderLinksCollapsed()
  const navSection = useMemo<PopoverEntry[]>(
    () => (linksCollapsed ? buildSiteNavEntries(navLinks, { pathname }) : []),
    [linksCollapsed, navLinks, pathname],
  )

  const entries = useMemo<PopoverListEntry[]>(
    () => [...navSection, ...workspaceRows, helpEntry(openHelp, HELP_SECTION)],
    [navSection, workspaceRows, openHelp],
  )

  const navigate = useCallback(
    (item: PopoverItem): void => {
      const workspace = menu.workspaces.find((w) => `ws:${w.id}` === item.key)
      // Every other row — the site's own nav on a phone — is a site-menu destination, and goes
      // the site menu's way: same-origin through the router, cross-site as a full-page load.
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
