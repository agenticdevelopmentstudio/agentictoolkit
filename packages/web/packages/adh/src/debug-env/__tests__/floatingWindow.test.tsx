// @vitest-environment jsdom
/**
 * FloatingWindow's geometry: where it sits, what bounds it, and what happens when the viewport
 * changes under it.
 *
 * Two failures this pins. On a desktop the window was capped at the room right of and below its
 * own corner, so every drag RESIZED it (and the HTDV inside refitted its rails on each
 * pointermove); its 520 x 360 floor beat that cap; and nothing moved it when the browser
 * narrowed — opened at 2560px and narrowed to 1000, its × sat past the right edge. On a phone the
 * sheet was sized ONCE, in measured px, so a viewport change that stayed on the phone side (a
 * 400px window widened to 620, a phone rotated) kept the old size with the live page beside it.
 *
 * jsdom lays nothing out, so the viewport is supplied through innerWidth/innerHeight and a
 * matchMedia that evaluates the query it is given, and the box the browser would have drawn
 * through offsetWidth/offsetHeight: the size written on the element, unless a test says CSS
 * would have drawn something else.
 */
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { PHONE_SHEET_CLASSES } from '@agenticdevelopertoolkit/ui/components/dialog'

import { FloatingWindow } from '../FloatingWindow'

type Listener = () => void

const viewport = { width: 1440, height: 900 }
// Each subscribed matchMedia listener, with the query it listens to.
const listeners = new Map<Listener, string>()
// The box the browser drew; a side left undefined is the size written on the element.
let drawn: { w?: number; h?: number } = {}

// Both spellings the phone line has had — `(max-width: 639px)` before the shared constant,
// `(width < 40rem)` after — so a test here fails on the old window for the reason it names,
// not because the old query never matched. Any other query is not the phone line.
function mediaMatches(query: string): boolean {
  const px = /^\(max-width:\s*([\d.]+)px\)$/.exec(query)
  if (px) return viewport.width <= Number(px[1])
  const rem = /^\(width < ([\d.]+)rem\)$/.exec(query)
  if (rem) return viewport.width < Number(rem[1]) * 16
  return false
}

// A browser resize: the resize event, then a `change` to each media query whose answer flipped.
function setViewport(width: number, height: number) {
  const before = new Map([...listeners].map(([l, q]) => [l, mediaMatches(q)]))
  viewport.width = width
  viewport.height = height
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: width })
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: height })
  act(() => {
    window.dispatchEvent(new Event('resize'))
    for (const [l, q] of listeners) if (mediaMatches(q) !== before.get(l)) l()
  })
}

function openWindow(): HTMLElement {
  render(
    <FloatingWindow open onClose={vi.fn()} title="Debug">
      <p>body</p>
    </FloatingWindow>,
  )
  const el = document.querySelector('[role="dialog"]')
  if (!(el instanceof HTMLElement)) throw new Error('the window did not open')
  return el
}

const originalMatchMedia = window.matchMedia
const originalWidth = window.innerWidth
const originalHeight = window.innerHeight

beforeEach(() => {
  drawn = {}
  listeners.clear()
  window.matchMedia = ((query: string) => ({
    media: query,
    get matches() {
      return mediaMatches(query)
    },
    onchange: null,
    addEventListener: (_type: string, l: Listener) => listeners.set(l, query),
    removeEventListener: (_type: string, l: Listener) => listeners.delete(l),
    addListener: (l: Listener) => listeners.set(l, query),
    removeListener: (l: Listener) => listeners.delete(l),
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia
  const px = (v: string) => Number.parseFloat(v) || 0
  vi.spyOn(HTMLElement.prototype, 'offsetWidth', 'get').mockImplementation(function (this: HTMLElement) {
    return this.getAttribute('role') === 'dialog' ? (drawn.w ?? px(this.style.width)) : 0
  })
  vi.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockImplementation(function (this: HTMLElement) {
    return this.getAttribute('role') === 'dialog' ? (drawn.h ?? px(this.style.height)) : 0
  })
  setViewport(1440, 900)
})

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
  window.matchMedia = originalMatchMedia
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: originalWidth })
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: originalHeight })
})

describe('FloatingWindow on a desktop', () => {
  it('opens centred at its requested size', () => {
    const win = openWindow()
    expect([win.style.width, win.style.height]).toEqual(['1368px', '792px'])
    expect([win.style.left, win.style.top]).toEqual(['36px', '54px'])
  })

  it('is capped by the viewport, not by the room beside its corner', () => {
    const win = openWindow()
    expect(win.style.maxWidth).toBe('100vw')
    expect(win.style.maxHeight).toBe('100dvh')
  })

  it('has a floor that can never beat that cap', () => {
    // CSS lets min-width win over max-width, so a bare 520 x 360 floor overran the viewport.
    const win = openWindow()
    expect(win.style.minWidth).toBe('min(520px, 100vw)')
    expect(win.style.minHeight).toBe('min(360px, 100dvh)')
  })

  it('moves when dragged by its title bar, and never resizes', () => {
    const win = openWindow()
    fireEvent.pointerDown(screen.getByText('Debug'), { button: 0, clientX: 100, clientY: 20 })
    fireEvent.pointerMove(window, { clientX: 150, clientY: 20 })
    fireEvent.pointerUp(window)
    expect(win.style.left).toBe('86px')
    expect(win.style.width).toBe('1368px')
    expect(win.style.maxWidth).toBe('100vw')
  })

  it('shifts as the browser shrinks, before it shrinks itself, so its × stays on screen', () => {
    setViewport(2560, 1440)
    const win = openWindow()
    expect([win.style.left, win.style.top]).toEqual(['580px', '260px'])
    // Still room for all 1400 x 920 of it: moved in, not shrunk.
    setViewport(1700, 1000)
    expect([win.style.left, win.style.top]).toEqual(['300px', '80px'])
    // Narrower than the window itself: the 100vw / 100dvh caps draw it at the viewport's size,
    // and it sits in the corner.
    drawn = { w: 1000, h: 700 }
    setViewport(1000, 700)
    expect([win.style.left, win.style.top]).toEqual(['0px', '0px'])
  })

  it('fits its corner to the box that rendered, when the floor draws it taller than asked', () => {
    // A short viewport still wider than the phone line, so it floats (a landscape phone): 282px
    // is asked for and centred at 19, and the min-height floor draws all 320 — 19px off the bottom.
    setViewport(700, 320)
    drawn = { h: 320 }
    const win = openWindow()
    expect(win.style.height).toBe('282px')
    expect(win.style.top).toBe('0px')
  })
})

// On the phone side the sheet's size is the shared dialog's classes, which jsdom cannot lay out:
// what these pin is that the window wears exactly those classes and that NO size is written on
// the element, since a written size beats a class. What the classes draw is the dialog's own
// test (ui's phoneSheet.test.tsx compiles them).
describe('FloatingWindow on a phone', () => {
  it('opens as the shared phone sheet, with no measured size a later resize could leave stale', () => {
    setViewport(400, 800)
    const win = openWindow()
    expect([win.style.width, win.style.height]).toEqual(['', ''])
    expect(win.className).toContain(PHONE_SHEET_CLASSES)
    expect([win.style.left, win.style.top]).toEqual(['', ''])
    // Still on the phone side, so nothing re-renders: whatever was written on open is what the
    // 620px window gets.
    setViewport(620, 800)
    expect([win.style.width, win.style.height]).toEqual(['', ''])
  })

  it('clears the floating size when the viewport crosses onto the phone side, and restores it after', () => {
    const win = openWindow()
    expect(win.style.width).toBe('1368px')
    setViewport(390, 844)
    expect([win.style.width, win.style.height]).toEqual(['', ''])
    expect(win.className).toContain(PHONE_SHEET_CLASSES)
    for (const prop of ['left', 'top', 'minWidth', 'maxWidth', 'resize'] as const) expect(win.style[prop], prop).toBe('')
    setViewport(1440, 900)
    expect([win.style.width, win.style.height]).toEqual(['1368px', '792px'])
    expect([win.style.left, win.style.top]).toEqual(['36px', '54px'])
    expect(win.className).not.toContain('max-sm:')
  })
})
