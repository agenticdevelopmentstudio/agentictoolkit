// src/__tests__/BitbagDock.test.tsx
import { describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'

// The avatar engine and the real chat have nothing to assert here — this file is about
// the dock's own open/rest state. The chat stand-in renders just the two things the dock
// reads back: the `.persona-chat` whose `pc-collapsed` class is the chat's engaged fact,
// and the `.pc-input` the dock puts the caret in.
vi.mock('../avatar', () => ({ Bitbag: () => <span data-testid="bitbag" /> }))
vi.mock('../BitbagInfo', () => ({ BitbagInfo: () => null }))
vi.mock('../BitbagChat', () => ({
  BitbagChat: () => (
    <div className="persona-chat pc-collapsed" data-testid="chat">
      <input className="pc-input" aria-label="Message" />
    </div>
  ),
}))
vi.mock('@agenticdevelopertoolkit/viewport', () => ({ useKeyboardInset: () => {} }))

import { BitbagDock } from '../BitbagDock'

function panelOf(container: HTMLElement): HTMLElement {
  return container.querySelector('.bb-dock__panel') as HTMLElement
}

describe('BitbagDock', () => {
  it('rests on his entry line by default — the chat is always shown and he is not a button', () => {
    const { container } = render(<BitbagDock />)
    expect(panelOf(container).hidden).toBe(false)
    expect(screen.queryByRole('button', { name: /bitbag/i })).toBeNull()
    expect((container.querySelector('.bb-dock__avatar') as HTMLElement).style.width).toBe('132px')
  })

  describe("rest='avatar'", () => {
    it('rests as his face alone, laid out at half width, with the chat hidden', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      expect(face).toHaveAttribute('aria-expanded', 'false')
      // Laid out at half width, not scaled: a transform would leave a 132px box over
      // the footer's links taking their clicks.
      expect(face.style.width).toBe('66px')
      expect(panelOf(container).hidden).toBe(true)
      expect(container.firstElementChild).toHaveClass('bb-dock--resting')
    })

    it('opens his chat under him on a tap, full size, with the caret in the composer', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      fireEvent.click(screen.getByRole('button', { name: 'Chat with bitbag' }))
      expect(panelOf(container).hidden).toBe(false)
      const face = container.querySelector('.bb-dock__avatar') as HTMLElement
      expect(face.style.width).toBe('132px')
      expect(face).toHaveAttribute('aria-expanded', 'true')
      expect(document.activeElement).toBe(screen.getByLabelText('Message'))
    })

    it('goes back to rest when the chat folds after being engaged — not the instant it opens folded', async () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      fireEvent.click(screen.getByRole('button', { name: 'Chat with bitbag' }))
      const chat = screen.getByTestId('chat')
      // Still folded, never engaged: must stay open.
      await act(async () => {})
      expect(panelOf(container).hidden).toBe(false)
      // Engaged, then folded (a tap away / Escape): back to rest.
      await act(async () => chat.classList.remove('pc-collapsed'))
      expect(panelOf(container).hidden).toBe(false)
      await act(async () => chat.classList.add('pc-collapsed'))
      expect(panelOf(container).hidden).toBe(true)
    })

    it('closes on a tap on him while open, rather than reopening', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.click(face)
      fireEvent.pointerDown(face)
      fireEvent.click(face)
      expect(panelOf(container).hidden).toBe(true)
    })

    it('toggles from the keyboard with Enter and Space', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.keyDown(face, { key: 'Enter' })
      expect(panelOf(container).hidden).toBe(false)
      fireEvent.keyDown(face, { key: ' ' })
      expect(panelOf(container).hidden).toBe(true)
    })
  })
})
