// src/__tests__/BitbagDockRealChat.test.tsx
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'

// The resting dock against his REAL chat and his REAL `i`. BitbagDock.test.tsx stands a
// mock in for the chat, which suits the dock's own state and is blind to the contract
// between the two: the dock closes on the chat's `onEngagedChange`, folds it through
// `engaged`, puts the caret in it by CHAT_INPUT_SELECTOR, and marks its own face and the
// `i` with CHAT_INSIDE_ATTR — each a name the chat package can change without a mocked
// test noticing, which is how the `.pc-collapsed` observer this replaced would have gone
// blind. Here the chat's own gestures (focus in, a tap away, Escape) drive the dock, so a
// rename on either side fails this file. The classes asserted, `.persona-chat` and
// `.pc-collapsed`, are the ones bitbag-dock.css hangs the page scrim on.
//
// Only his face is stubbed (a gsap rig with nothing to say about the dock), and the
// keyboard-inset hook, which has no on-screen keyboard to measure here.
vi.mock('../avatar', () => ({ Bitbag: () => <span data-testid="bitbag" /> }))
vi.mock('@agenticdevelopertoolkit/viewport', () => ({
  useKeyboardInset: () => {},
  usePageScrollLock: () => {},
}))

import { BitbagDock } from '../BitbagDock'

const q = <T extends HTMLElement>(selector: string): T => document.querySelector(selector) as T
const composer = (): HTMLInputElement => q('.pc-input')
const chatBox = (): HTMLElement => q('.persona-chat')
const panel = (): HTMLElement => q('.bb-dock__panel')
const face = (): HTMLElement => q('.bb-dock__avatar')
const infoButton = (): HTMLElement => screen.getByRole('button', { name: 'About bitbag' })

/**
 * Let a gesture's consequences land before asserting on them. The dock reacts within
 * the gesture today, but a close that arrived a microtask later (the way the observer
 * this replaced closed) is still a close: these tests are about what happens, not when.
 */
async function settle(): Promise<void> {
  await act(async () => {})
}

/** Render him resting, let his chat connect, and open it with a tap on him. */
async function openDock(): Promise<void> {
  render(<BitbagDock rest="avatar" />)
  // His chat connects at mount, on timers — it types its welcome and greeting, then
  // enables the composer — and a disabled composer cannot take the caret whose arrival
  // is what engages the chat.
  for (let ms = 0; composer().disabled && ms < 20000; ms += 250) {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(250)
    })
  }
  expect(composer().disabled).toBe(false)
  expect(panel().hidden).toBe(true)

  fireEvent.pointerDown(face())
  fireEvent.click(face())
  await settle()
  expect(panel().hidden).toBe(false)
  expect(document.activeElement).toBe(composer())
  expect(chatBox()).not.toHaveClass('pc-collapsed')
}

function expectResting(): void {
  expect(panel().hidden).toBe(true)
  expect(q('.bb-dock')).toHaveClass('bb-dock--resting')
  expect(face()).toHaveAttribute('aria-expanded', 'false')
  // Folded, not merely hidden: an engaged chat keeps the scrim on over the page.
  expect(chatBox()).toHaveClass('pc-collapsed')
}

describe('BitbagDock with his real chat', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })
  afterEach(() => {
    // Unmount on the fake clock, so the chat's pending timers are cleared by the
    // clock that set them rather than handed to the real one as bare ids.
    cleanup()
    vi.useRealTimers()
  })

  it('goes back to rest when his engaged chat folds on a tap away', async () => {
    await openDock()
    fireEvent.pointerDown(document.body)
    await settle()
    expectResting()
  })

  it('stays open and engaged when the `i` beside the chat is pressed', async () => {
    await openDock()
    fireEvent.pointerDown(infoButton())
    fireEvent.pointerUp(infoButton())
    fireEvent.click(infoButton())
    await settle()
    expect(panel().hidden).toBe(false)
    expect(screen.getByRole('dialog', { name: 'About bitbag' })).toBeInTheDocument()
    expect(chatBox()).not.toHaveClass('pc-collapsed')
  })

  it('spends one Escape per layer — the `i` panel, then the chat — and keeps focus on the page', async () => {
    await openDock()
    fireEvent.click(infoButton())
    await settle()
    const pop = screen.getByRole('dialog', { name: 'About bitbag' })
    expect(document.activeElement).toBe(pop)

    fireEvent.keyDown(pop, { key: 'Escape' })
    await settle()
    expect(screen.queryByRole('dialog', { name: 'About bitbag' })).toBeNull()
    expect(document.activeElement).toBe(infoButton())
    expect(panel().hidden).toBe(false)
    expect(chatBox()).not.toHaveClass('pc-collapsed')

    fireEvent.keyDown(infoButton(), { key: 'Escape' })
    await settle()
    expectResting()
    expect(document.activeElement).toBe(face())
  })

  it('hands focus to him when Escape in the composer puts him back to rest', async () => {
    await openDock()
    fireEvent.keyDown(composer(), { key: 'Escape' })
    await settle()
    expectResting()
    expect(document.activeElement).toBe(face())
  })

  it('folds his chat when he is closed with Enter', async () => {
    await openDock()
    face().focus()
    fireEvent.keyDown(face(), { key: 'Enter' })
    await settle()
    expectResting()
  })

  it('closes, rather than reopening, on a tap on him while his chat is engaged', async () => {
    await openDock()
    fireEvent.pointerDown(face())
    fireEvent.pointerUp(face())
    fireEvent.click(face())
    await settle()
    expectResting()
  })

  it('closes on a click that no pointerdown preceded — assistive tech, `el.click()`', async () => {
    await openDock()
    act(() => face().click())
    await settle()
    expectResting()
  })
})
