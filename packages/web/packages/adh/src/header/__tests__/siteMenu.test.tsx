/** SiteMenu's Workspaces flyout, through the real popover. It appears only once there is a
 *  workspace to list in it: a flyout's rows are menuitems, and the "Loading…" row it used to hold
 *  while the list was in flight was one the arrow keys landed on and Enter "chose" — closing the
 *  menu and going nowhere. */
/// <reference types="@testing-library/jest-dom/vitest" />
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn() }),
}))

// The package path, as SiteMenu reads the provider's context.
import { SiteMenu, WorkspacesMenuProvider, type WorkspacesMenu } from '@agentic-toolkit/adh/header'

afterEach(cleanup)

// jsdom has no layout, so no scrollIntoView; the popover calls it on a keyboard highlight.
Element.prototype.scrollIntoView = vi.fn()

function renderSignedIn(menu: WorkspacesMenu): void {
  render(
    <WorkspacesMenuProvider value={menu}>
      <SiteMenu groups={[]} currentSiteId="hub" authenticated />
    </WorkspacesMenuProvider>,
  )
}

async function openMenu(): Promise<void> {
  fireEvent.click(screen.getByRole('button', { name: /switch site$/ }))
  await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
}

describe('SiteMenu — the Workspaces flyout', () => {
  it('lists the workspaces once there are some', async () => {
    renderSignedIn({
      workspaces: [{ id: 'individual:mine', label: 'Mike Fullerton', href: '/mine', current: true }],
      loading: false,
    })
    await openMenu()
    expect(screen.getByRole('menuitem', { name: 'Workspaces' })).toBeInTheDocument()
  })

  it('is absent while the list is loading, rather than holding a row that goes nowhere', async () => {
    renderSignedIn({ workspaces: [], loading: true })
    await openMenu()
    // The signed-in top section did render — only the flyout is missing.
    expect(screen.getByRole('menuitem', { name: 'Home' })).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', { name: 'Workspaces' })).toBeNull()
    expect(screen.queryByText('Loading…')).toBeNull()
  })

  it('is absent when the list failed or is empty', async () => {
    renderSignedIn({ workspaces: [], loading: false, error: true })
    await openMenu()
    expect(screen.queryByRole('menuitem', { name: 'Workspaces' })).toBeNull()
    cleanup()
    renderSignedIn({ workspaces: [], loading: false })
    await openMenu()
    expect(screen.queryByRole('menuitem', { name: 'Workspaces' })).toBeNull()
  })
})
