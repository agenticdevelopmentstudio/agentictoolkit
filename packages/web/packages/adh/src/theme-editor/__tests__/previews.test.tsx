/**
 * The theme editor's header and footer previews are SPECIMENS: copies of the page's own chrome,
 * shown inside the Debug console while the real chrome is still on the page. Each is the full adh
 * component, so each can reach what the page already has — an id looked up across the whole
 * document, the host's context — and act on the page instead of on itself. These tests mount a
 * preview beside what the page has around it and ask what a click in the preview reaches.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render } from '@testing-library/react'
import type { ComponentType } from 'react'
import type { PopoverEntry, PopoverItem } from '@agentic-toolkit/adh/header'

const push = vi.hoisted(() => vi.fn())
vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push }),
}))

// A plain anchor: next/link's own needs an app router this file has no use for.
vi.mock('next/link', () => ({
  default: ({ href, prefetch: _prefetch, ...rest }: { href: string; prefetch?: boolean }) => (
    <a href={href} {...rest} />
  ),
}))

// The bell opens a live channel the moment it mounts; who gets one is site-header.test's subject.
vi.mock('@agentic-toolkit/messaging/components/notification-bell', () => ({
  NotificationBell: () => null,
}))

// The switcher's popover engine, replaced by a spy on what it is handed: which rows, and what a
// pick does (`onChoose`). What a click reaches is data here, so no Base UI popup is needed to see
// it; the engine's own behaviour is navigationPopover.test's.
//
// At its own module, not through the barrel the menus import it from: the barrel re-exports this
// module, so every menu gets the spy. A barrel mock reaches only the modules loaded after it, and
// this file loads the barrel's own graph (areas.tsx imports it) before any menu asks for it.
const popovers = vi.hoisted(() => [] as Array<{ entries: PopoverEntry[]; onChoose: (item: PopoverItem) => void }>)
vi.mock('../../header/NavigationPopover', () => ({
  NavigationPopover: (props: (typeof popovers)[number]) => {
    popovers.push(props)
    return null
  },
}))

// bitbag stands in as the one element the page's footer mounts for him, so a second one would
// show. He portals to <body> for real, which is exactly why a preview cannot hide him.
vi.mock('../../footer/FooterChat', () => ({
  FooterChat: () => <div className="bb-dock adh-footer__chat" />,
}))

import {
  SiteMenuSwitcher,
  WorkspacesMenuProvider,
  type MenuWorkspace,
  type WorkspacesMenu,
} from '@agentic-toolkit/adh/header'
import { SiteFooter } from '@agentic-toolkit/adh/footer'
import { THEME_AREAS } from '../areas'

/** The preview the editor shows for one of its items. */
function preview(itemId: string): ComponentType {
  const item = THEME_AREAS.flatMap((area) => area.items).find((i) => i.id === itemId)
  if (!item?.Preview) throw new Error(`the theme editor has no preview for ${itemId}`)
  return item.Preview
}

beforeEach(() => {
  popovers.length = 0
  push.mockClear()
})
afterEach(cleanup)

describe('the footer preview, beside the page footer', () => {
  /** The page's footer, then the console holding the editor's preview — the order a page has
   *  them in: the console is opened over a page that already has its footer. */
  function renderBoth() {
    const FooterPreview = preview('global.footer-bar')
    render(
      <>
        <SiteFooter />
        <div data-testid="console">
          <FooterPreview />
        </div>
      </>,
    )
    const [page, specimen] = Array.from(document.querySelectorAll<HTMLElement>('footer.adh-footer'))
    expect(specimen, 'the preview rendered no footer').toBeDefined()
    return { page: page!, specimen: specimen!, console: specimen!.closest('[data-testid="console"]')! }
  }

  it('repeats no id of the page', () => {
    // `popovertarget` finds its panel by id across the whole document, so a repeated id is not
    // just invalid HTML: the specimen's copyright button opened the page's menu.
    renderBoth()
    const ids = Array.from(document.querySelectorAll('[id]'), (el) => el.id)
    expect(ids.filter((id, i) => ids.indexOf(id) !== i)).toEqual([])
  })

  it("opens each footer's menus from that footer, each at its own caret", () => {
    const { page, specimen } = renderBoth()
    for (const footer of [page, specimen]) {
      const triggers = Array.from(footer.querySelectorAll('.adh-footer__menu-trigger'))
      expect(triggers.map((t) => t.textContent?.trim())).toEqual([
        '© 2026 Agentic Development Studio',
        'Legal',
      ])
      for (const trigger of triggers) {
        const panel = document.getElementById(trigger.getAttribute('popovertarget') ?? '')
        // The panel the platform finds is the one in this trigger's own host, which holds the
        // caret the panel is positioned at (adh-components.css, `anchor-scope`).
        expect(panel?.closest('.adh-footer__menu-host')).toBe(trigger.closest('.adh-footer__menu-host'))
      }
    }
    // Where a browser positions by anchor name but cannot scope one, the names themselves must
    // differ: two carets declaring one name hand every panel that names it the LAST one's.
    const anchors = Array.from(document.querySelectorAll<HTMLElement>('.adh-footer__menu-host'), (host) =>
      host.style.getPropertyValue('--adh-footer-menu-anchor'),
    )
    expect(anchors).toHaveLength(4)
    expect(new Set(anchors).size).toBe(anchors.length)
  })

  it("leaves the dialogs and bitbag to the page, and its entries open the page's dialogs", () => {
    const { specimen, console } = renderBoth()
    // Its own two menus are the only popovers it brings; About, Sites, Terms and Privacy are
    // the page's, one each.
    expect(console.querySelectorAll('[popover]')).toHaveLength(2)
    expect(document.querySelectorAll('.bb-dock')).toHaveLength(1)
    // And every entry still opens something: About and Sites find the page's own.
    const targets = Array.from(specimen.querySelectorAll('[popovertarget]'), (el) =>
      el.getAttribute('popovertarget')!,
    )
    expect(targets.filter((id) => document.getElementById(id) === null)).toEqual([])
  })
})

describe('the header preview', () => {
  /** The page's own workspaces, as the hub's provider hands them to its header. */
  const PAGE_WORKSPACES: MenuWorkspace[] = [
    { id: 'individual:grace', label: 'Grace Hopper', href: '/grace', current: true },
    { id: 'organization:navy', label: 'Navy', href: '/navy' },
  ]
  const pageMenu = () => {
    const select = vi.fn<(workspace: MenuWorkspace) => void>()
    const menu: WorkspacesMenu = { workspaces: PAGE_WORKSPACES, loading: false, select }
    return { menu, select }
  }

  /** Every workspace row any rendered switcher offers, with the pick that switcher makes. */
  const workspaceRows = () =>
    popovers.flatMap(({ entries, onChoose }) =>
      entries.flatMap((e) =>
        e.kind === 'leaf' && e.item.key.startsWith('ws:') ? [{ item: e.item, choose: () => onChoose(e.item) }] : [],
      ),
    )

  /** A pick waits on the unsaved-changes guard, a promise, before it switches. */
  const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

  it("reaches the host from the page's own switcher — the control for the wait below", async () => {
    const { menu, select } = pageMenu()
    render(
      <WorkspacesMenuProvider value={menu}>
        <SiteMenuSwitcher currentSiteId="hub" authenticated />
      </WorkspacesMenuProvider>,
    )
    workspaceRows().find((row) => row.item.label === 'Navy')!.choose()
    await settle()
    expect(select).toHaveBeenCalledWith(PAGE_WORKSPACES[1])
  })

  it("offers workspaces of its own on a page that has some, and a pick there changes nothing", async () => {
    // The hub's provider sits above the Debug console. The preview's canned user is signed in,
    // so its header swapped the site menu for the workspace switcher and listed the REAL user's
    // workspaces — and a pick switched the page behind the console and saved the preference.
    const { menu, select } = pageMenu()
    const HeaderPreview = preview('global.header-bar')
    render(
      <WorkspacesMenuProvider value={menu}>
        <HeaderPreview />
      </WorkspacesMenuProvider>,
    )
    const rows = workspaceRows()
    // Still the workspace switcher, as the page's header has; just not the page's workspaces.
    expect(rows.length).toBeGreaterThan(0)
    const pageLabels = PAGE_WORKSPACES.map((w) => w.label)
    expect(rows.map((row) => row.item.label).filter((label) => pageLabels.includes(label))).toEqual([])

    for (const row of rows) row.choose()
    await settle()
    expect(select).not.toHaveBeenCalled()
    expect(push).not.toHaveBeenCalled()
  })

  it('keeps the site menu on a page without workspaces, as that page has', () => {
    // Every satellite: no provider, so the page's own signed-in header shows the site menu, and
    // the preview of that header must too — it is what the editor is styling.
    const HeaderPreview = preview('global.header-bar')
    render(<HeaderPreview />)
    expect(popovers.length, 'the preview rendered no switcher at all').toBeGreaterThan(0)
    expect(workspaceRows()).toEqual([])
  })
})
