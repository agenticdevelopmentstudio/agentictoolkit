import { render } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest'
import { SWIPE_BACK_EVENT } from '@agenticdevelopertoolkit/ui/lib/swipe-back'
import { SwipeHistory } from '../SwipeHistory'

// The gesture end to end, through real document listeners. `swipeHistory.test.ts` covers the
// thresholds (classifySwipe); this covers WHERE a flick is left alone and WHAT it does.

/** jsdom has no Touch constructor, so a touch event here is a plain bubbling Event carrying the
 *  only fields SwipeHistory reads. */
function touch(type: 'touchstart' | 'touchend', target: Element, x: number, y: number, t: number) {
  const event = new Event(type, { bubbles: true })
  const point = [{ clientX: x, clientY: y }]
  Object.defineProperties(event, {
    touches: { value: type === 'touchstart' ? point : [] },
    changedTouches: { value: point },
    timeStamp: { value: t },
  })
  target.dispatchEvent(event)
}

/** 160 px sideways in 200 ms, well clear of the screen edges: a flick by every threshold. */
function flick(target: Element, direction: 'back' | 'forward') {
  const [from, to] = direction === 'back' ? [100, 260] : [300, 140]
  touch('touchstart', target, from, 400, 1000)
  touch('touchend', target, to, 404, 1200)
}

describe('SwipeHistory', () => {
  const mounted: HTMLElement[] = []
  const originalMatchMedia = window.matchMedia
  let back: MockInstance
  let forward: MockInstance

  /** Put `html` in the document and return the element with `id`. */
  function place(html: string, id: string): HTMLElement {
    const host = document.createElement('div')
    host.innerHTML = html
    document.body.append(host)
    mounted.push(host)
    return host.querySelector<HTMLElement>(`#${id}`)!
  }

  beforeEach(() => {
    // A touch screen: SwipeHistory listens only where the primary pointer is coarse.
    window.matchMedia = ((q: string) => ({ matches: q === '(pointer: coarse)', media: q })) as unknown as typeof window.matchMedia
    back = vi.spyOn(window.history, 'back').mockImplementation(() => {})
    forward = vi.spyOn(window.history, 'forward').mockImplementation(() => {})
  })
  afterEach(() => {
    mounted.splice(0).forEach((el) => el.remove())
    window.matchMedia = originalMatchMedia
    vi.restoreAllMocks()
  })

  it('goes back in history on a Back flick nothing on the page claims', () => {
    render(<SwipeHistory />)
    flick(place('<p id="text">Page text</p>', 'text'), 'back')
    expect(back).toHaveBeenCalledTimes(1)
    expect(forward).not.toHaveBeenCalled()
  })

  it('offers a Back flick to the in-page Back under the finger first, and leaves history alone when it claims it', () => {
    render(<SwipeHistory />)
    const row = place('<section id="stack"><p id="row">A settings section</p></section>', 'row')
    const offeredAt: Array<EventTarget | null> = []
    row.closest('section')!.addEventListener(SWIPE_BACK_EVENT, (e) => {
      offeredAt.push(e.target)
      // HTDV's narrow stack showing a local-state Back (hub /settings): it steps back itself.
      e.preventDefault()
    })
    flick(row, 'back')
    expect(offeredAt).toEqual([row])
    expect(back).not.toHaveBeenCalled()
  })

  it('sends a Forward flick straight to history, never offering it', () => {
    render(<SwipeHistory />)
    const offered = vi.fn((e: Event) => e.preventDefault())
    document.addEventListener(SWIPE_BACK_EVENT, offered)
    try {
      flick(place('<p id="text">Page text</p>', 'text'), 'forward')
    } finally {
      document.removeEventListener(SWIPE_BACK_EVENT, offered)
    }
    expect(forward).toHaveBeenCalledTimes(1)
    expect(offered).not.toHaveBeenCalled()
  })

  it('leaves a flick alone inside an open popover panel that carries no role', () => {
    render(<SwipeHistory />)
    // The footer's Legal menu: popover="auto", no role="menu".
    flick(place('<div popover="auto"><a id="link" href="#terms">Terms</a></div>', 'link'), 'back')
    expect(back).not.toHaveBeenCalled()
  })

  it('leaves a resize handle to its drag', () => {
    render(<SwipeHistory />)
    flick(place('<div role="separator" aria-orientation="vertical"><span id="grip"></span></div>', 'grip'), 'back')
    expect(back).not.toHaveBeenCalled()
  })

  it('leaves a drag alone on anything that declares touch-action: none, however deep the finger lands', () => {
    render(<SwipeHistory />)
    // A board card's inner text: touch-action is not inherited, so only the ancestor says so.
    flick(place('<div style="touch-action: none"><div><span id="card">Card</span></div></div>', 'card'), 'back')
    expect(back).not.toHaveBeenCalled()
  })

  it('leaves a flick alone inside a sideways scroller', () => {
    render(<SwipeHistory />)
    const cell = place('<div id="table" style="overflow-x: auto"><span id="cell">Cell</span></div>', 'cell')
    // jsdom lays nothing out, so give the scroller the overflow a real one would have.
    const table = cell.parentElement!
    Object.defineProperty(table, 'scrollWidth', { value: 900 })
    Object.defineProperty(table, 'clientWidth', { value: 300 })
    flick(cell, 'back')
    expect(back).not.toHaveBeenCalled()
  })

  it('reads no layout for a tap or a scroll, only once a touch has turned out to be a flick', () => {
    render(<SwipeHistory />)
    const text = place('<p id="text">Page text</p>', 'text')
    const scrollWidth = vi.spyOn(Element.prototype, 'scrollWidth', 'get')
    const computedStyle = vi.spyOn(globalThis, 'getComputedStyle')
    // A tap, then a vertical scroll — every touch while the chat streams a reply.
    touch('touchstart', text, 200, 400, 1000)
    touch('touchend', text, 202, 401, 1080)
    touch('touchstart', text, 200, 400, 2000)
    touch('touchend', text, 205, 150, 2200)
    expect(scrollWidth).not.toHaveBeenCalled()
    expect(computedStyle).not.toHaveBeenCalled()
    // The spies do see the walk, once there is a flick to check.
    flick(text, 'back')
    expect(scrollWidth).toHaveBeenCalled()
    expect(computedStyle).toHaveBeenCalled()
    expect(back).toHaveBeenCalledTimes(1)
  })
})
