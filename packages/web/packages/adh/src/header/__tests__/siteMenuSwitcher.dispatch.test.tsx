// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, cleanup, screen } from '@testing-library/react'

// Which menu the header's site-name slot holds, by route and auth. The three menus are stubbed to
// their names: what this dispatcher owes is the CHOICE, and each menu's contents are tested where
// it is defined.

const route = { pathname: '/' }
vi.mock('next/navigation', () => ({ usePathname: () => route.pathname }))

const workspaces = { current: null as object | null }
vi.mock('@agentic-toolkit/adh/header', () => ({ useWorkspacesMenu: () => workspaces.current }))
vi.mock('../WorkspaceMenu', () => ({ WorkspaceMenu: () => <div>workspace menu</div> }))
vi.mock('../WorkspaceSiteMenu', () => ({ WorkspaceSiteMenu: () => <div>workspace site menu</div> }))
vi.mock('../MarketingSiteMenu', () => ({ MarketingSiteMenu: () => <div>marketing site menu</div> }))
vi.mock('../PrefetchSiblingSites', () => ({ PrefetchSiblingSites: () => null }))

import { SiteMenuSwitcher } from '../SiteMenuSwitcher'

function renderAt(pathname: string, authenticated: boolean) {
  route.pathname = pathname
  workspaces.current = { workspaces: [] }
  render(<SiteMenuSwitcher {...({ currentSiteId: 'hub', authenticated } as never)} />)
}

afterEach(() => {
  cleanup()
  workspaces.current = null
})

describe('SiteMenuSwitcher', () => {
  it('keeps the site menu on the landing page when signed in', () => {
    // The swap once ignored the route, so signing in took the site menu off `/` as well — the
    // site menu stays on the marketing routes at every auth state (Mike, 2026-09-24).
    renderAt('/', true)
    expect(screen.getByText('marketing site menu')).toBeTruthy()
    expect(screen.queryByText('workspace menu')).toBeNull()
  })

  it('swaps in the workspace menu on a workspace route when signed in', () => {
    renderAt('/home', true)
    expect(screen.getByText('workspace menu')).toBeTruthy()
    cleanup()
    renderAt('/acme/research', true)
    expect(screen.getByText('workspace menu')).toBeTruthy()
  })

  it('keeps the site menu on a workspace route when signed out', () => {
    renderAt('/home', false)
    expect(screen.queryByText('workspace menu')).toBeNull()
  })
})
