/** The two things NavigationPopover gained for the site menu: an optional global chord that
 *  TOGGLES it, and the chrome-hover collapse.
 *
 *  The dropdown is base-ui backed and its portal returns null while closed, so every
 *  assertion about menu content opens the menu first — a cold query would either fail or
 *  match the trigger's own label. */
/// <reference types="@testing-library/jest-dom/vitest" />
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'
import { type ReactElement } from 'react'
import { useRegisteredShortcuts } from '@agenticdevelopertoolkit/ui/hooks/useShortcut'

import { NavigationPopover, type PopoverEntry } from '../NavigationPopover'

// This package's vitest config has no auto-cleanup setup file, so each render must be torn
// down explicitly or the next test's queries see both mounted trees. It matters more than
// usual here: an undismounted popover leaves its chord registered.
afterEach(cleanup)

// jsdom implements no layout, so it ships no `scrollIntoView` — and the popover calls it
// on the active row whenever the keyboard moved the highlight. Without this, any test that
// arrows through the menu dies inside an effect rather than on its own assertion.
Element.prototype.scrollIntoView = vi.fn()

const ENTRIES: PopoverEntry[] = [
  {
    kind: 'leaf',
    section: 1,
    item: { key: 'bitbag', label: 'Bitbag', href: 'https://bitbag.test' },
  },
  {
    kind: 'topic',
    section: 1,
    label: 'Hire',
    items: [{ key: 'consultants', label: 'Consultants', href: 'https://consultants.test' }],
  },
]

const TRIGGER = 'Menu — switch site'

/** jsdom reports no Apple platform, so `mod` is Ctrl — hence ctrlKey below. */
const CHORD = { key: 'K', ctrlKey: true, shiftKey: true }

function Menu(props: Partial<Parameters<typeof NavigationPopover>[0]>): ReactElement {
  return (
    <NavigationPopover
      entries={ENTRIES}
      triggerLabel={TRIGGER}
      triggerText="Menu"
      footer={<span data-testid="wordmark">Agentic Development Studio</span>}
      onChoose={vi.fn()}
      {...props}
    />
  )
}

async function expectOpen(): Promise<void> {
  await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
}

async function expectClosed(): Promise<void> {
  await waitFor(() => expect(screen.queryByRole('menu')).toBeNull())
}

describe('NavigationPopover — openShortcut', () => {
  it('opens on the chord, and closes on it again — a chord you can only press one way is one you need the mouse to undo', async () => {
    render(<Menu openShortcut={{ keys: 'mod+shift+k', label: 'Site menu' }} />)
    expect(screen.queryByRole('menu')).toBeNull()
    fireEvent.keyDown(document.body, CHORD)
    await expectOpen()
    fireEvent.keyDown(document.body, CHORD)
    await expectClosed()
  })

  it('closes from inside its OWN command field — the press that opened it left focus there', async () => {
    // Not a redundant restatement of the toggle above: the popup stops keydown at its
    // portal container, so the document-level registry never sees this press. Focus is
    // inside the menu the moment it opens, so this IS the ordinary way a user closes it.
    render(<Menu openShortcut={{ keys: 'mod+shift+k', label: 'Site menu' }} />)
    fireEvent.keyDown(document.body, CHORD)
    await expectOpen()
    fireEvent.keyDown(screen.getByRole('combobox'), CHORD)
    await expectClosed()
  })

  it('leaves a chord the menu was NOT given alone, rather than closing on any modifier key', async () => {
    render(<Menu openShortcut={{ keys: 'mod+shift+k', label: 'Site menu' }} />)
    fireEvent.keyDown(document.body, CHORD)
    await expectOpen()
    fireEvent.keyDown(screen.getByRole('combobox'), { key: 'J', ctrlKey: true, shiftKey: true })
    // Nothing to wait for; assert it is still open after the event had its chance.
    expect(screen.getByRole('menu')).toBeInTheDocument()
  })

  it('fires an UNMODIFIED chord from inside a text field too — that is what allowInInput buys', async () => {
    render(
      <>
        <input aria-label="Somewhere else" />
        <Menu openShortcut={{ keys: '?', label: 'Site menu' }} />
      </>,
    )
    fireEvent.keyDown(screen.getByLabelText('Somewhere else'), { key: '?', shiftKey: true })
    await expectOpen()
  })

  it('registers no chord at all when none was given', async () => {
    render(<Menu />)
    fireEvent.keyDown(document.body, CHORD)
    // Nothing to wait for — assert it stays shut rather than racing an open that never comes.
    await expectClosed()
  })

  it('registers no chord when the user turned it off, and advertises none either', async () => {
    render(
      <>
        <ShortcutList />
        <Menu openShortcut={{ keys: '', label: 'Site menu' }} />
      </>,
    )
    fireEvent.keyDown(document.body, CHORD)
    await expectClosed()
    // An empty chord must not reach the shortcut list as a binding with no keys — the list
    // is how a user discovers what is bound, and a blank row is worse than no row.
    expect(screen.queryByText('Site menu')).toBeNull()
  })

  it('advertises the chord it WAS given, so the shortcut list can show it', () => {
    render(
      <>
        <ShortcutList />
        <Menu openShortcut={{ keys: 'mod+shift+k', label: 'Site menu' }} />
      </>,
    )
    expect(screen.getByRole('listitem')).toHaveTextContent('Navigation · mod+shift+k · Site menu')
  })
})

/** The enumerated view of the registry, as a help sheet would render it. */
function ShortcutList(): ReactElement {
  const shortcuts = useRegisteredShortcuts()
  return (
    <ul>
      {shortcuts.map((s) => (
        <li key={`${s.keys}:${s.label}`}>{`${s.group ?? '—'} · ${s.keys} · ${s.label}`}</li>
      ))}
    </ul>
  )
}

describe('NavigationPopover — hovering off the rows onto the chrome', () => {
  /** Open the menu and disclose the Hire flyout by hovering its row, as a pointer would. */
  async function discloseHire(): Promise<HTMLElement> {
    fireEvent.click(screen.getByRole('button', { name: TRIGGER }))
    await expectOpen()
    const hire = screen.getByText('Hire').closest('[data-nav]') as HTMLElement
    fireEvent.mouseMove(hire)
    await waitFor(() => expect(screen.getByText('Consultants')).toBeInTheDocument())
    expect(hire).toHaveClass('adh-nav-popover__item--active')
    return hire
  }

  it('collapses the flyout when the pointer moves onto the footer', async () => {
    render(<Menu />)
    const hire = await discloseHire()
    // The footer sits inside the popup but outside the list, so DropdownMenuContent's own
    // onMouseLeave never fires for it — without leaveRows the topic stays disclosed and the
    // row stays highlighted, looking exactly as if the pointer were still on Hire.
    fireEvent.mouseMove(screen.getByTestId('wordmark'))
    await waitFor(() => expect(screen.queryByText('Consultants')).toBeNull())
    expect(hire).not.toHaveClass('adh-nav-popover__item--active')
  })

  it('collapses it from the command field at the top, the other non-row chrome', async () => {
    render(<Menu />)
    const hire = await discloseHire()
    fireEvent.mouseMove(screen.getByRole('combobox'))
    await waitFor(() => expect(screen.queryByText('Consultants')).toBeNull())
    expect(hire).not.toHaveClass('adh-nav-popover__item--active')
  })

  it('leaves a keyboard user’s highlight alone — an incidental jiggle is not a hover', async () => {
    render(<Menu />)
    fireEvent.click(screen.getByRole('button', { name: TRIGGER }))
    await expectOpen()
    const input = screen.getByRole('combobox')
    // Arrow down twice to reach the topic row and open it, which sets navByKeyboard.
    fireEvent.keyDown(input, { key: 'ArrowDown' })
    fireEvent.keyDown(input, { key: 'ArrowDown' })
    fireEvent.keyDown(input, { key: 'ArrowRight' })
    await waitFor(() => expect(screen.getByText('Consultants')).toBeInTheDocument())
    // The pointer is merely resting on the chrome; the browser still emits a mousemove for
    // a jiggle, and stealing the highlight for it would be worse than the bug leaveRows fixes.
    fireEvent.mouseMove(screen.getByTestId('wordmark'))
    expect(screen.getByText('Consultants')).toBeInTheDocument()
  })
})

describe('NavigationPopover — sectionLabels', () => {
  const SECTIONED: PopoverEntry[] = [
    { kind: 'leaf', section: 0, item: { key: 'mine', label: 'Mine', href: '/mine' } },
    { kind: 'leaf', section: 0, item: { key: 'temporal', label: 'Temporal', href: '/temporal' } },
    { kind: 'leaf', section: 1, item: { key: 'help', label: 'Help' } },
  ]

  it('heads a section once, above its first row, and the heading is not a row to pick', async () => {
    render(<Menu entries={SECTIONED} sectionLabels={{ 0: 'Workspaces' }} />)
    fireEvent.click(screen.getByRole('button', { name: TRIGGER }))
    await expectOpen()
    // getByText throws on a duplicate, so this also asserts the heading appears once.
    const heading = screen.getByText('Workspaces')
    expect(heading.closest('[role="menuitem"]')).toBeNull()
    // Document order: the heading precedes the section's first row.
    const first = screen.getByText('Mine')
    expect(heading.compareDocumentPosition(first) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })

  it('drops the heading while searching — a filtered list is ranked, not sectioned', async () => {
    render(<Menu entries={SECTIONED} sectionLabels={{ 0: 'Workspaces' }} />)
    fireEvent.click(screen.getByRole('button', { name: TRIGGER }))
    await expectOpen()
    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'temp' } })
    await waitFor(() => expect(screen.queryByText('Mine')).toBeNull())
    expect(screen.queryByText('Workspaces')).toBeNull()
  })
})
