// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, cleanup, waitFor, fireEvent, screen } from '@testing-library/react'
import type { ReactNode } from 'react'
import type {
  PopoverClose,
  PopoverEntry,
  PopoverItem,
  PopoverListEntry,
  PopoverNotice,
} from '@agentic-toolkit/adh/header'

// The signed-in header's switcher. What it owes is data-shaped — which rows, which one is current,
// what the trigger says, and WHERE a pick goes — so the popover engine is replaced by a spy that
// records its props. The engine's own search/keyboard behaviour is the site menu's, and is covered
// there; re-testing it through this caller would pin two things to one fixture.

const push = vi.fn()
vi.mock('next/navigation', () => ({
  usePathname: () => '/mine/llm-providers',
  useRouter: () => ({ push }),
}))

const seen: { current: Record<string, unknown> | null } = { current: null }
vi.mock('@agentic-toolkit/adh/header', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@agentic-toolkit/adh/header')>()),
  NavigationPopover: (props: Record<string, unknown>) => {
    seen.current = props
    return null
  },
}))

import { WorkspaceMenu } from '../WorkspaceMenu'
import type { MenuWorkspace } from '../workspaces-menu'

const WORKSPACES: MenuWorkspace[] = [
  { id: 'individual:mine', label: 'Mike Fullerton', href: '/mine', current: true },
  { id: 'organization:temporal', label: 'Temporal', href: '/temporal' },
]

function props(): {
  entries: PopoverListEntry[]
  triggerContent: ReactNode
  triggerLabel: string
  onChoose: (item: PopoverItem) => void
  sectionLabels: Record<number, string>
  commandTrailing?: (api: { close: PopoverClose }) => ReactNode
} {
  if (!seen.current) throw new Error('NavigationPopover never rendered')
  return seen.current as never
}

function workspaceItems(): PopoverItem[] {
  return props()
    .entries.filter((e): e is Extract<PopoverEntry, { kind: 'leaf' }> => e.kind === 'leaf')
    .map((e) => e.item)
    .filter((i) => i.key.startsWith('ws:'))
}

function notices(): PopoverNotice[] {
  return props().entries.filter((e): e is PopoverNotice => e.kind === 'notice')
}

/** Where each row sits, by its label: a leaf by its item's, a topic by its own. */
function labels(): string[] {
  return props().entries.map((e) =>
    e.kind === 'leaf' ? e.item.label : e.kind === 'topic' ? e.label : `(${e.text})`,
  )
}

function topic(label: string): Extract<PopoverEntry, { kind: 'topic' }> | undefined {
  return props().entries.find(
    (e): e is Extract<PopoverEntry, { kind: 'topic' }> => e.kind === 'topic' && e.label === label,
  )
}

beforeEach(() => {
  seen.current = null
  push.mockClear()
})
afterEach(cleanup)

describe('WorkspaceMenu', () => {
  it('reads as the workspace you are in, followed by the word "Workspace", on the trigger only', () => {
    render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false }} />)
    const trigger = render(<>{props().triggerContent}</>).container
    expect(trigger.querySelector('.adh-workspace-trigger__label')?.textContent).toBe(
      'Mike Fullerton',
    )
    expect(trigger.querySelector('.adh-workspace-trigger__suffix')?.textContent).toBe('Workspace')
    expect(trigger.textContent).toBe('Mike FullertonWorkspace')
    // The name starts with the words on screen, so "click Mike Fullerton Workspace" finds it.
    expect(props().triggerLabel).toBe('Mike Fullerton Workspace — switch workspace')
    // …and the menu's own rows are the bare names.
    expect(workspaceItems().map((i) => i.label)).toEqual(['Mike Fullerton', 'Temporal'])
  })

  it('lists every workspace, marking the current one', () => {
    render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false }} />)
    expect(workspaceItems().map((i) => [i.label, Boolean(i.current)])).toEqual([
      ['Mike Fullerton', true],
      ['Temporal', false],
    ])
  })

  it('heads the workspace rows\' section "Workspaces", and only that section', () => {
    render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false }} />)
    const { entries, sectionLabels } = props()
    const wsSection = entries.find((e) => e.kind === 'leaf' && e.item.key.startsWith('ws:'))!.section
    const help = entries.find((e) => e.kind === 'leaf' && e.item.key === 'help')!.section
    expect(sectionLabels[wsSection]).toBe('Workspaces')
    expect(sectionLabels[help]).toBeUndefined()
  })

  describe('with no workspaces to list', () => {
    // A line of text where the rows would be — NOT a row. The rows these used to be were
    // menuitems the arrow keys landed on and Enter "chose", closing the menu and going nowhere.

    it('says it is loading rather than claiming there are no workspaces', () => {
      render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: [], loading: true }} />)
      // No "Workspace" after a placeholder: it names no workspace.
      expect(props().triggerLabel).toBe('Loading… — switch workspace')
      expect(notices().map((n) => n.text)).toEqual(['Loading…'])
      expect(workspaceItems()).toEqual([])
    })

    it('says the list failed to load, which is not the same as an empty account', () => {
      render(
        <WorkspaceMenu currentSiteId="hub" menu={{ workspaces: [], loading: false, error: true }} />,
      )
      expect(notices().map((n) => n.text)).toEqual(["Couldn't load your workspaces"])
      expect(workspaceItems()).toEqual([])
    })

    it('says there are none only when the account really has none', () => {
      render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: [], loading: false }} />)
      expect(notices().map((n) => n.text)).toEqual(['No workspaces yet'])
      expect(workspaceItems()).toEqual([])
    })

    it('keeps the line in the "Workspaces" section, and ONE line across its changes of text', () => {
      // One key for loading → failed, so the popover updates the one live region (which
      // announces the change) rather than mounting a second one (which may not).
      const { rerender } = render(
        <WorkspaceMenu currentSiteId="hub" menu={{ workspaces: [], loading: true }} />,
      )
      const loadingKey = notices()[0]!.key
      expect(props().sectionLabels[notices()[0]!.section]).toBe('Workspaces')
      rerender(
        <WorkspaceMenu currentSiteId="hub" menu={{ workspaces: [], loading: false, error: true }} />,
      )
      expect(notices()[0]!.key).toBe(loadingKey)
    })
  })

  it("hands a pick to the host's own switch when it supplies one", async () => {
    // The hub's switch keeps the feature you are on; a plain link to the row's href would not,
    // so it must NOT also navigate.
    const select = vi.fn()
    render(
      <WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false, select }} />,
    )
    const temporal = workspaceItems().find((i) => i.label === 'Temporal')!
    props().onChoose(temporal)
    await waitFor(() => expect(select).toHaveBeenCalledWith(WORKSPACES[1]))
    expect(push).not.toHaveBeenCalled()
  })

  it("follows the row's href when the host supplies no switch", async () => {
    render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false }} />)
    props().onChoose(workspaceItems().find((i) => i.label === 'Temporal')!)
    await waitFor(() => expect(push).toHaveBeenCalledWith('/temporal'))
  })

  describe('for an adh admin', () => {
    // This menu REPLACES the site menu for a signed-in hub user, and the site menu is where an
    // admin's consoles live. Dropping them here left an admin on the hub no door to any console.

    it('offers the operations consoles, after Help and apart from it', () => {
      render(
        <WorkspaceMenu
          currentSiteId="hub"
          userIsAdmin
          menu={{ workspaces: WORKSPACES, loading: false }}
        />,
      )
      const admin = topic('Admin')
      expect(admin).toBeDefined()
      expect(admin!.items.map((i) => i.label)).toContain('Fleet Monitor')
      const order = labels()
      expect(order.indexOf('Admin')).toBeGreaterThan(order.indexOf('Help'))
      // A different section is what rules a divider between the two.
      const help = props().entries.find((e) => e.kind === 'leaf' && e.item.key === 'help')!
      expect(admin!.section).not.toBe(help.section)
    })

    it('offers them to nobody else', () => {
      render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false }} />)
      expect(topic('Admin')).toBeUndefined()
      cleanup()
      render(
        <WorkspaceMenu
          currentSiteId="hub"
          userIsAdmin={false}
          menu={{ workspaces: WORKSPACES, loading: false }}
        />,
      )
      expect(topic('Admin')).toBeUndefined()
    })

    it('opens a console on its own host, not as a route on this one, and not as a workspace', async () => {
      // A console is a cross-site destination. A router.push of its absolute URL is not how you
      // get there, and handing it to the host's workspace switch would be a pick of nothing.
      const select = vi.fn()
      render(
        <WorkspaceMenu
          currentSiteId="hub"
          userIsAdmin
          menu={{ workspaces: WORKSPACES, loading: false, select }}
        />,
      )
      const monitor = topic('Admin')!.items.find((i) => i.label === 'Fleet Monitor')!
      const assign = vi.fn()
      const loc = Object.getOwnPropertyDescriptor(window, 'location')
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: { host: 'localhost', hostname: 'localhost', assign },
      })
      try {
        props().onChoose(monitor)
        await waitFor(() =>
          expect(assign).toHaveBeenCalledWith('https://lewis.agenticdeveloperhub.com'),
        )
      } finally {
        if (loc) Object.defineProperty(window, 'location', loc)
      }
      expect(push).not.toHaveBeenCalled()
      expect(select).not.toHaveBeenCalled()
    })
  })

  describe('the command row', () => {
    const close = vi.fn()
    beforeEach(() => close.mockClear())

    it("carries the site menu's settings gear, which opens the overlay the menu closes for", () => {
      const onSettings = vi.fn()
      const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
        cb(0)
        return 0
      })
      try {
        render(
          <WorkspaceMenu
            currentSiteId="hub"
            onSettings={onSettings}
            menu={{ workspaces: WORKSPACES, loading: false }}
          />,
        )
        render(<>{props().commandTrailing?.({ close })}</>)
        fireEvent.click(screen.getByRole('button', { name: 'User settings' }))
        expect(close).toHaveBeenCalledWith({ restoreFocus: false })
        expect(onSettings).toHaveBeenCalledTimes(1)
      } finally {
        raf.mockRestore()
      }
    })

    it('links to the settings page for a host with no overlay', () => {
      render(
        <WorkspaceMenu
          currentSiteId="hub"
          settingsHref="/settings"
          menu={{ workspaces: WORKSPACES, loading: false }}
        />,
      )
      render(<>{props().commandTrailing?.({ close })}</>)
      expect(screen.getByRole('link', { name: 'User settings' })).toHaveAttribute('href', '/settings')
    })

    it('shows nothing there when the host offers no settings at all', () => {
      render(<WorkspaceMenu currentSiteId="hub" menu={{ workspaces: WORKSPACES, loading: false }} />)
      expect(props().commandTrailing?.({ close }) ?? null).toBeNull()
    })
  })
})
