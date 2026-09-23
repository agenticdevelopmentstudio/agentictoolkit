// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, cleanup, waitFor } from '@testing-library/react'
import type { ReactNode } from 'react'
import type { PopoverEntry, PopoverItem } from '@agentic-toolkit/adh/header'

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
  entries: PopoverEntry[]
  triggerContent: ReactNode
  triggerLabel: string
  onChoose: (item: PopoverItem) => void
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

beforeEach(() => {
  seen.current = null
  push.mockClear()
})
afterEach(cleanup)

describe('WorkspaceMenu', () => {
  it('reads as the workspace you are in, captioned "Workspace:" inside the trigger itself', () => {
    render(<WorkspaceMenu menu={{ workspaces: WORKSPACES, loading: false }} />)
    const trigger = render(<>{props().triggerContent}</>).container
    expect(trigger.querySelector('.adh-workspace-trigger__label')?.textContent).toBe(
      'Mike Fullerton',
    )
    // Above the name, in the trigger (so it is part of the click target) — and hidden from
    // assistive tech, whose label already says "switch workspace".
    const caption = trigger.querySelector('.adh-workspace-trigger__caption')
    expect(caption?.textContent).toBe('Workspace:')
    expect(caption).toHaveAttribute('aria-hidden')
    expect(props().triggerLabel).toBe('Mike Fullerton — switch workspace')
  })

  it('lists every workspace, marking the current one', () => {
    render(<WorkspaceMenu menu={{ workspaces: WORKSPACES, loading: false }} />)
    expect(workspaceItems().map((i) => [i.label, Boolean(i.current)])).toEqual([
      ['Mike Fullerton', true],
      ['Temporal', false],
    ])
  })

  it('heads the workspace rows\' section "Workspaces", and only that section', () => {
    render(<WorkspaceMenu menu={{ workspaces: WORKSPACES, loading: false }} />)
    const { entries, sectionLabels } = props() as unknown as {
      entries: PopoverEntry[]
      sectionLabels: Record<number, string>
    }
    const wsSection = entries.find((e) => e.kind === 'leaf' && e.item.key.startsWith('ws:'))!.section
    const help = entries.find((e) => e.kind === 'leaf' && e.item.key === 'help')!.section
    expect(sectionLabels[wsSection]).toBe('Workspaces')
    expect(sectionLabels[help]).toBeUndefined()
  })

  it('says it is loading rather than claiming there are no workspaces', () => {
    render(<WorkspaceMenu menu={{ workspaces: [], loading: true }} />)
    expect(props().triggerLabel).toBe('Loading… — switch workspace')
    expect(workspaceItems().map((i) => i.label)).toEqual(['Loading…'])
  })

  it("hands a pick to the host's own switch when it supplies one", async () => {
    // The hub's switch keeps the feature you are on and remembers the pick; a plain link to the
    // row's href would do neither, so it must NOT also navigate.
    const select = vi.fn()
    render(<WorkspaceMenu menu={{ workspaces: WORKSPACES, loading: false, select }} />)
    const temporal = workspaceItems().find((i) => i.label === 'Temporal')!
    props().onChoose(temporal)
    await waitFor(() => expect(select).toHaveBeenCalledWith(WORKSPACES[1]))
    expect(push).not.toHaveBeenCalled()
  })

  it("follows the row's href when the host supplies no switch", async () => {
    render(<WorkspaceMenu menu={{ workspaces: WORKSPACES, loading: false }} />)
    props().onChoose(workspaceItems().find((i) => i.label === 'Temporal')!)
    await waitFor(() => expect(push).toHaveBeenCalledWith('/temporal'))
  })
})
