/** SiteMenuSwitcher's hand-over, end to end through the real popover: signed in on a host that
 *  supplies workspaces (the hub), the slot holds the WorkspaceMenu instead of the site menu — and
 *  what the site menu carried that is not about SITES has to come across with it. The admin
 *  consoles are the case that went missing: the swap passed the WorkspaceMenu no `userIsAdmin`,
 *  so an admin signed in to the hub had no door to any console anywhere in the header. */
/// <reference types="@testing-library/jest-dom/vitest" />
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'

vi.mock('next/navigation', () => ({
  usePathname: () => '/mine/llm-providers',
  useRouter: () => ({ push: vi.fn() }),
}))

// The package path, as SiteMenuSwitcher reads it: the provider must fill the ONE context the
// switcher asks.
import {
  SiteMenuSwitcher,
  WorkspacesMenuProvider,
  type WorkspacesMenu,
} from '@agentic-toolkit/adh/header'

afterEach(cleanup)

// jsdom has no layout, so no scrollIntoView; the popover calls it on a keyboard highlight.
Element.prototype.scrollIntoView = vi.fn()

const MENU: WorkspacesMenu = {
  workspaces: [
    { id: 'individual:mine', label: 'Mike Fullerton', href: '/mine', current: true },
    { id: 'organization:temporal', label: 'Temporal', href: '/temporal' },
  ],
  loading: false,
}

async function openMenu(trigger: string): Promise<void> {
  fireEvent.click(screen.getByRole('button', { name: trigger }))
  await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
}

describe('SiteMenuSwitcher — signed in on the hub', () => {
  it('swaps in the workspace menu, which still offers an admin the operations consoles', async () => {
    render(
      <WorkspacesMenuProvider value={MENU}>
        <SiteMenuSwitcher currentSiteId="hub" authenticated userIsAdmin />
      </WorkspacesMenuProvider>,
    )
    await openMenu('Mike Fullerton Workspace — switch workspace')
    expect(screen.getByRole('combobox', { name: 'Search workspaces' })).toBeInTheDocument()
    expect(screen.getByRole('menuitem', { name: 'Mike Fullerton' })).toHaveAttribute(
      'aria-current',
      'page',
    )
    expect(screen.getByRole('menuitem', { name: 'Help' })).toBeInTheDocument()
    expect(screen.getByRole('menuitem', { name: /^Admin/ })).toBeInTheDocument()
  })

  it('offers the consoles to nobody else', async () => {
    render(
      <WorkspacesMenuProvider value={MENU}>
        <SiteMenuSwitcher currentSiteId="hub" authenticated />
      </WorkspacesMenuProvider>,
    )
    await openMenu('Mike Fullerton Workspace — switch workspace')
    expect(screen.getByRole('menuitem', { name: 'Help' })).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', { name: /^Admin/ })).toBeNull()
  })

  it('passes the settings gear through', async () => {
    render(
      <WorkspacesMenuProvider value={MENU}>
        <SiteMenuSwitcher currentSiteId="hub" authenticated onSettings={vi.fn()} />
      </WorkspacesMenuProvider>,
    )
    await openMenu('Mike Fullerton Workspace — switch workspace')
    expect(screen.getByRole('button', { name: 'User settings' })).toBeInTheDocument()
  })

  it('says a failed list failed — as text, not as a row to pick', async () => {
    render(
      <WorkspacesMenuProvider value={{ workspaces: [], loading: false, error: true }}>
        <SiteMenuSwitcher currentSiteId="hub" authenticated />
      </WorkspacesMenuProvider>,
    )
    await openMenu('Workspaces — switch workspace')
    expect(screen.getByRole('status')).toHaveTextContent("Couldn't load your workspaces")
    expect(screen.queryByText('No workspaces yet')).toBeNull()
    expect(screen.getAllByRole('menuitem').map((row) => row.textContent)).toEqual(['Help'])
  })
})
