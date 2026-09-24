// src/__tests__/BitbagDock.test.tsx
import { describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'
import type { BitbagChatProps } from '../BitbagChat'

// The avatar engine and the real chat have nothing to assert here — this file is about
// the dock's own open/rest state. (BitbagDockRealChat.test.tsx is the same dock against
// the real chat and the real `i`, where the chat's own gestures drive it.) The chat
// stand-in keeps the props the dock hands it, so a test can speak as the chat through
// `onEngagedChange` and read back the `engaged` the dock imposes, and renders the
// composer the dock puts the caret in: `.pc-input` is what CHAT_INPUT_SELECTOR selects.
const chat = vi.hoisted(() => ({ props: {} as Partial<BitbagChatProps> }))
vi.mock('../avatar', () => ({ Bitbag: () => <span data-testid="bitbag" /> }))
vi.mock('../BitbagInfo', () => ({ BitbagInfo: () => null }))
vi.mock('../BitbagChat', () => ({
  BitbagChat: (props: BitbagChatProps) => {
    chat.props = props
    return (
      <div className="persona-chat" data-testid="chat">
        <input className="pc-input" aria-label="Message" />
      </div>
    )
  },
}))
vi.mock('@agenticdevelopertoolkit/viewport', () => ({ useKeyboardInset: () => {} }))

import { BitbagDock } from '../BitbagDock'

function panelOf(container: HTMLElement): HTMLElement {
  return container.querySelector('.bb-dock__panel') as HTMLElement
}

/** Speak as the chat: report a flip the way its sizing hook does, from a gesture. */
function chatReports(engaged: boolean): void {
  act(() => chat.props.onEngagedChange?.(engaged))
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
      // Opened folded, never engaged: must stay open.
      await act(async () => {})
      expect(panelOf(container).hidden).toBe(false)
      expect(chat.props.engaged).toBe(false)
      // Engaged, then folded (a tap away / Escape): back to rest.
      chatReports(true)
      expect(panelOf(container).hidden).toBe(false)
      expect(chat.props.engaged).toBe(true)
      chatReports(false)
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

    it('closes on a click that no pointerdown preceded — assistive tech, `el.click()`', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      act(() => face.click())
      expect(panelOf(container).hidden).toBe(false)
      act(() => face.click())
      expect(panelOf(container).hidden).toBe(true)
      expect(face).toHaveAttribute('aria-expanded', 'false')
    })

    it('folds his chat when he closes, whichever way he is closed', () => {
      render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      // Hiding a chat does not fold it: left engaged, its scrim and raised z-index
      // (bitbag-dock.css, adh-site.css) stayed over the page with nothing to talk to.
      fireEvent.keyDown(face, { key: 'Enter' })
      chatReports(true)
      fireEvent.keyDown(face, { key: 'Enter' })
      expect(chat.props.engaged).toBe(false)

      fireEvent.click(face)
      chatReports(true)
      fireEvent.pointerDown(face)
      fireEvent.click(face)
      expect(chat.props.engaged).toBe(false)
    })

    it('hands focus back to him when he closes with it inside the panel', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.click(face)
      expect(document.activeElement).toBe(screen.getByLabelText('Message'))
      chatReports(true)
      // Escape in the composer folds the chat, and the fold closes him: `hidden` would
      // otherwise take the focused composer out of the page and drop focus to <body>.
      chatReports(false)
      expect(panelOf(container).hidden).toBe(true)
      expect(document.activeElement).toBe(face)
    })

    it('does not take focus he was not holding when he closes', () => {
      const { container } = render(
        <>
          <button type="button">elsewhere</button>
          <BitbagDock rest="avatar" />
        </>,
      )
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      act(() => face.click())
      const elsewhere = screen.getByRole('button', { name: 'elsewhere' })
      elsewhere.focus()
      act(() => face.click())
      expect(panelOf(container).hidden).toBe(true)
      expect(document.activeElement).toBe(elsewhere)
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
