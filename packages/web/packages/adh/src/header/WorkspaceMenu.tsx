'use client'

import { useCallback, useMemo, type ReactElement } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { Settings } from 'lucide-react'
import { confirmNavigation } from '@agenticdevelopertoolkit/ui/lib/navigation-guard'
import {
  HubMark,
  NavigationPopover,
  type PopoverEntry,
  type PopoverItem,
} from '@agentic-toolkit/adh/header'
// Type-only, so erased: a VALUE import of the sibling would bundle a second copy of its context.
import type { WorkspacesMenu } from './workspaces-menu'
import { useHubPreferences } from '@agentic-toolkit/adh/header/hub-preferences'
import { useHelp } from '@agentic-toolkit/adh/help'
import { useHeaderLinksCollapsed } from './useHeaderLinksCollapsed'
import { buildSiteNavEntries } from './siteNavEntries'
import { menuIcon } from './menu-icons'
import type { SiteMenuChromeProps } from './SiteMenu'

export type WorkspaceMenuProps = Pick<
  SiteMenuChromeProps,
  'onSettings' | 'settingsHref' | 'navLinks' | 'triggerClassName'
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
 * the hub keeps the current feature and remembers the pick (see WorkspacesMenu.select).
 */
export function WorkspaceMenu({
  menu,
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

  const workspaceRows = useMemo<PopoverEntry[]>(() => {
    const items: PopoverItem[] = menu.workspaces.map((w) => ({
      key: `ws:${w.id}`,
      label: w.label,
      href: w.href,
      icon: menuIcon('workspaces'),
      current: w.current,
    }))
    if (!items.length) {
      items.push({ key: 'ws:empty', label: menu.loading ? 'Loading…' : 'No workspaces yet' })
    }
    return items.map((item) => ({ kind: 'leaf', section: 0, item }))
  }, [menu])

  // The site's own primary nav, exactly while the bar has dropped it (below 768px) — the same
  // hand-over the site menu does, because on a phone whichever menu sits in this slot IS the
  // site's navigation. See SiteMenu's `navSection`.
  const linksCollapsed = useHeaderLinksCollapsed()
  const navSection = useMemo<PopoverEntry[]>(
    () => (linksCollapsed ? buildSiteNavEntries(navLinks, { pathname }) : []),
    [linksCollapsed, navLinks, pathname],
  )

  const entries = useMemo<PopoverEntry[]>(
    () => [
      ...navSection,
      ...workspaceRows,
      {
        kind: 'leaf',
        section: 1,
        item: { key: 'help', label: 'Help', icon: menuIcon('help'), onSelect: () => openHelp() },
      },
    ],
    [navSection, workspaceRows, openHelp],
  )

  const navigate = useCallback(
    (item: PopoverItem): void => {
      const href = item.href
      if (!href) return
      const workspace = menu.workspaces.find((w) => `ws:${w.id}` === item.key)
      void confirmNavigation().then((ok) => {
        if (!ok) return
        if (workspace && menu.select) menu.select(workspace)
        else router.push(href)
      })
    },
    [menu, router],
  )

  return (
    <NavigationPopover
      entries={entries}
      openShortcut={{ keys: siteMenuShortcut, label: 'Workspace menu' }}
      onChoose={navigate}
      triggerLabel={`${label} — switch workspace`}
      triggerText={label}
      triggerIcon={<HubMark className="adh-nav-popover__mark" />}
      triggerClassName={triggerClassName}
      placeholder="Search workspaces"
      emptyLabel="No matching workspaces"
      commandTrailing={({ close }) =>
        onSettings ? (
          <button
            type="button"
            className="adh-site-switcher__help"
            aria-label="User settings"
            onClick={() => {
              close({ restoreFocus: false })
              requestAnimationFrame(() => onSettings())
            }}
          >
            <Settings className="adh-site-switcher__help-icon" aria-hidden />
          </button>
        ) : settingsHref ? (
          <a className="adh-site-switcher__help" aria-label="User settings" href={settingsHref}>
            <Settings className="adh-site-switcher__help-icon" aria-hidden />
          </a>
        ) : null
      }
    />
  )
}
