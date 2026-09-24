/** The chrome both header switchers share — the Help row and the command row's settings gear.
 *  SiteMenu and WorkspaceMenu take turns in one slot, so a person meets both; these pin the one
 *  row and the one gear they now both draw, so neither can drift from the other again. */
/// <reference types="@testing-library/jest-dom/vitest" />
import { render, screen, fireEvent, cleanup } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'

import { helpEntry, settingsTrailing } from '../menuChrome'

afterEach(cleanup)

describe('helpEntry', () => {
  it('is an action row in the caller’s section, not a destination', () => {
    const openHelp = vi.fn()
    const entry = helpEntry(openHelp, 1)
    expect(entry.kind).toBe('leaf')
    expect(entry.section).toBe(1)
    if (entry.kind !== 'leaf') throw new Error('unreachable')
    expect(entry.item.key).toBe('help')
    expect(entry.item.label).toBe('Help')
    // No href: choosing it opens the help panel over the page and navigates nowhere.
    expect(entry.item.href).toBeUndefined()
    entry.item.onSelect?.()
    expect(openHelp).toHaveBeenCalledTimes(1)
  })
})

describe('settingsTrailing', () => {
  it('opens the overlay AFTER closing the menu, and without handing focus back to the trigger', () => {
    const close = vi.fn()
    const onSettings = vi.fn()
    let frame: FrameRequestCallback | undefined
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      frame = cb
      return 1
    })
    try {
      render(<>{settingsTrailing({ close, onSettings })}</>)
      fireEvent.click(screen.getByRole('button', { name: 'User settings' }))
      expect(close).toHaveBeenCalledWith({ restoreFocus: false })
      // The overlay waits a frame, so it opens over a menu that has finished closing.
      expect(onSettings).not.toHaveBeenCalled()
      frame?.(0)
      expect(onSettings).toHaveBeenCalledTimes(1)
    } finally {
      raf.mockRestore()
    }
  })

  it('prefers the in-page overlay over a link when a host offers both', () => {
    // The same order AvatarMenu's "User Settings" row applies: one header, one answer.
    render(<>{settingsTrailing({ close: vi.fn(), onSettings: vi.fn(), settingsHref: '/settings' })}</>)
    expect(screen.getByRole('button', { name: 'User settings' })).toBeInTheDocument()
    expect(screen.queryByRole('link')).toBeNull()
  })

  it('is a real link to the settings page for a host with no overlay', () => {
    render(<>{settingsTrailing({ close: vi.fn(), settingsHref: 'https://hub.test/settings' })}</>)
    expect(screen.getByRole('link', { name: 'User settings' })).toHaveAttribute(
      'href',
      'https://hub.test/settings',
    )
  })

  it('is nothing at all when the host offers no settings surface', () => {
    expect(settingsTrailing({ close: vi.fn() })).toBeNull()
  })
})
