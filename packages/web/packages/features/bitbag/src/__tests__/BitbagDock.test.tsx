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
// The page lock's last word: whether the dock is holding the page still right now.
const pageLock = vi.hoisted(() => ({ active: false }))
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
vi.mock('@agenticdevelopertoolkit/viewport', () => ({
  useKeyboardInset: () => {},
  usePageScrollLock: (active: boolean) => {
    pageLock.active = active
  },
}))

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

  it('holds the page still only while his always-shown chat is engaged', () => {
    render(<BitbagDock />)
    expect(pageLock.active).toBe(false)
    chatReports(true)
    expect(pageLock.active).toBe(true)
    chatReports(false)
    expect(pageLock.active).toBe(false)
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

    it('opens his chat on a tap, him on its corner as its send control, with the caret in the composer', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      fireEvent.click(screen.getByRole('button', { name: 'Chat with bitbag' }))
      expect(panelOf(container).hidden).toBe(false)
      const face = container.querySelector('.bb-dock__avatar') as HTMLElement
      // Three-quarters of 132: he stands where the send button was, so it is not drawn.
      expect(face.style.width).toBe('99px')
      expect(panelOf(container).style.getPropertyValue('--bb-dock-corner-w')).toBe('99px')
      expect(chat.props.sendButton).toBe(false)
      expect(face).toHaveAttribute('aria-expanded', 'true')
      expect(face).toHaveAttribute('aria-label', 'Send to bitbag')
      expect(document.activeElement).toBe(screen.getByLabelText('Message'))
    })

    it('keeps the caret in the composer when he is pressed while open', () => {
      render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      // Resting, his press is an ordinary one.
      expect(fireEvent.mouseDown(face)).toBe(true)
      fireEvent.click(face)
      // Open, it is cancelled, so the press does not take focus off the composer.
      expect(fireEvent.mouseDown(face)).toBe(false)
    })

    it('keeps the send button for the resting modes that are not him', () => {
      render(<BitbagDock />)
      expect(chat.props.sendButton).toBe(true)
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

    it('holds the page still while his chat is open, and lets it go when he rests', () => {
      render(<BitbagDock rest="avatar" />)
      expect(pageLock.active).toBe(false)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.click(face)
      expect(pageLock.active).toBe(true)
      fireEvent.click(face)
      expect(pageLock.active).toBe(false)
    })

    it('closes on a tap on him while open but not yet engaged, rather than reopening', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.click(face)
      fireEvent.pointerDown(face)
      fireEvent.click(face)
      expect(panelOf(container).hidden).toBe(true)
    })

    it('closes, before his chat is engaged, on a click that no pointerdown preceded — assistive tech, `el.click()`', () => {
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
      chatReports(false)
      expect(chat.props.engaged).toBe(false)
      expect(screen.getByRole('button', { name: 'Chat with bitbag' })).toHaveAttribute('aria-expanded', 'false')
    })

    it('sends, rather than closing, on a tap on him once his chat is engaged', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.click(face)
      chatReports(true)
      fireEvent.pointerDown(face)
      fireEvent.click(face)
      fireEvent.keyDown(face, { key: 'Enter' })
      expect(panelOf(container).hidden).toBe(false)
      expect(chat.props.engaged).toBe(true)
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

    it('tells his chat it was summoned while it is open, and only then', () => {
      render(<BitbagDock rest="avatar" />)
      expect(chat.props.summoned).toBe(false)
      fireEvent.click(screen.getByRole('button', { name: 'Chat with bitbag' }))
      expect(chat.props.summoned).toBe(true)
    })

    it('closes on a press away or Escape before his chat engages, but not on a press on him or in the panel', () => {
      const { container } = render(<BitbagDock rest="avatar" />)
      const face = screen.getByRole('button', { name: 'Chat with bitbag' })
      fireEvent.click(face)
      fireEvent.pointerDown(screen.getByLabelText('Message'))
      fireEvent.pointerDown(face)
      expect(panelOf(container).hidden).toBe(false)
      fireEvent.pointerDown(document.body)
      expect(panelOf(container).hidden).toBe(true)

      fireEvent.click(face)
      fireEvent.keyDown(document.body, { key: 'Escape' })
      expect(panelOf(container).hidden).toBe(true)
    })

    describe('the way back to rest', () => {
      /** Give the panel an exit animation to wait for — jsdom loads no stylesheet. */
      function animated(container: HTMLElement): HTMLElement {
        const panel = panelOf(container)
        panel.style.animationName = 'bb-dock-panel-out'
        return panel
      }

      it('plays out before the panel hides, folding his chat only at the end', () => {
        const { container } = render(<BitbagDock rest="avatar" />)
        const face = screen.getByRole('button', { name: 'Chat with bitbag' })
        fireEvent.click(face)
        chatReports(true)
        const panel = animated(container)
        fireEvent.pointerDown(document.body)

        expect(container.firstElementChild).toHaveClass('bb-dock--closing')
        expect(panel.hidden).toBe(false)
        expect(face).toHaveAttribute('aria-expanded', 'false')
        // Still engaged: folding now would snap it to one line mid-fade.
        expect(chat.props.engaged).toBe(true)

        fireEvent.animationEnd(panel)
        expect(panel.hidden).toBe(true)
        expect(chat.props.engaged).toBe(false)
        expect(container.firstElementChild).not.toHaveClass('bb-dock--closing')
        expect(container.firstElementChild).toHaveClass('bb-dock--returned')
      })

      it('hides the panel anyway if the animation never ends', () => {
        vi.useFakeTimers()
        try {
          const { container } = render(<BitbagDock rest="avatar" />)
          fireEvent.click(screen.getByRole('button', { name: 'Chat with bitbag' }))
          const panel = animated(container)
          fireEvent.pointerDown(document.body)
          expect(panel.hidden).toBe(false)
          act(() => {
            vi.advanceTimersByTime(600)
          })
          expect(panel.hidden).toBe(true)
        } finally {
          vi.useRealTimers()
        }
      })

      it('stays open when he is tapped on his way out', () => {
        const { container } = render(<BitbagDock rest="avatar" />)
        const face = screen.getByRole('button', { name: 'Chat with bitbag' })
        fireEvent.click(face)
        const panel = animated(container)
        fireEvent.pointerDown(document.body)
        fireEvent.click(face)
        expect(container.firstElementChild).not.toHaveClass('bb-dock--closing')
        expect(face).toHaveAttribute('aria-expanded', 'true')
        fireEvent.animationEnd(panel)
        expect(panel.hidden).toBe(false)
      })

      it('does not settle him in on the rest the page loads with', () => {
        const { container } = render(<BitbagDock rest="avatar" />)
        expect(container.firstElementChild).not.toHaveClass('bb-dock--returned')
      })
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
