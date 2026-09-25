import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, renderHook } from '@testing-library/react'
import {
  REST_CENTRE_CLEARANCE,
  REST_DOCK_SELECTOR,
  REST_OFFSET_VAR,
  REST_SLOT_HOST_CLASS,
  restOffset,
  useFooterRestOffset,
} from '../useFooterRestOffset'

/** One bar item that keeps the slot: where its box starts, and whether it has a box at all.
 *  A host hidden by CSS has none (`getClientRects()` is empty) and reads `left: 0`, as any
 *  element without a box does. Mutable, so a test can move it and have the hook look again. */
type Host = { name: string; left: number; laidOut: boolean }

const legal = (left: number, laidOut = true): Host => ({ name: 'legal', left, laidOut })

/** A chat footer whose links nav holds `hosts`, each keeping a `slot`-wide left margin, in a
 *  `width`-wide viewport, with a copyright line ending at `copyright` when one is given.
 *  jsdom lays nothing out, so every box is stated rather than computed. Returns the
 *  elements the hook watches. */
function bar({
  hosts,
  slot = 68,
  width,
  copyright,
}: {
  hosts: Host[]
  slot?: number
  width: number
  copyright?: number
}) {
  const { container } = render(
    <footer className="adh-footer adh-footer--with-chat">
      {copyright !== undefined && <span className="adh-footer__copyright" />}
      <nav className="adh-footer__links">
        {hosts.map((h) => (
          <span
            key={h.name}
            data-host={h.name}
            className={REST_SLOT_HOST_CLASS}
            style={{ marginLeft: `${slot}px` }}
          />
        ))}
      </nav>
    </footer>,
  )
  for (const h of hosts) {
    const el = container.querySelector<HTMLElement>(`[data-host="${h.name}"]`)!
    el.getBoundingClientRect = () => ({ left: h.laidOut ? h.left : 0 }) as DOMRect
    el.getClientRects = () => (h.laidOut ? [{} as DOMRect] : []) as unknown as DOMRectList
  }
  const line = container.querySelector<HTMLElement>('.adh-footer__copyright')
  if (line) {
    line.getBoundingClientRect = () => ({ right: copyright }) as DOMRect
    line.getClientRects = () => [{} as DOMRect] as unknown as DOMRectList
  }
  Object.defineProperty(document.documentElement, 'clientWidth', { configurable: true, value: width })
  return { footer: container.querySelector('footer')!, nav: container.querySelector('nav')!, line }
}

/** bitbag's dock root as FooterChatInner portals it: the element the offset is written on.
 *  Rendered before the hook runs, as it is in the real commit. */
function dock(): HTMLElement {
  render(<div className="bb-dock adh-footer__chat" />)
  return document.querySelector<HTMLElement>(REST_DOCK_SELECTOR)!
}

/** A ResizeObserver that records what it is asked to watch and lets a test fire it. The
 *  root setup's stand-in (jsdom has none) observes nothing and never calls back. */
class RecordingObserver {
  static made: RecordingObserver[] = []
  readonly observed: Element[] = []
  disconnected = false
  readonly notify: () => void
  constructor(notify: () => void) {
    this.notify = notify
    RecordingObserver.made.push(this)
  }
  observe(el: Element) {
    this.observed.push(el)
  }
  unobserve() {}
  disconnect() {
    this.disconnected = true
  }
}

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
  RecordingObserver.made = []
  document.documentElement.style.removeProperty(REST_OFFSET_VAR)
})

describe('restOffset', () => {
  it('is the slot centre (just left of its host) less the viewport centre', () => {
    // Legal at 300 with a 68px slot before it: slot centre 266. Viewport 390: centre 195.
    bar({ hosts: [legal(300)], width: 390 })
    expect(restOffset(document)).toBe(71)
  })

  it('is null when the bar keeps no slot — a footer without chat', () => {
    render(<footer className="adh-footer"><span className={REST_SLOT_HOST_CLASS} /></footer>)
    expect(restOffset(document)).toBeNull()
  })

  it('is null when no host is laid out, so he rests at the centre rather than off the screen', () => {
    // A hidden host still reports its 68px margin, but its box reads left 0. Measured anyway,
    // that put his face at 0 - 34 - 195 = -229px on a 390px phone: wholly off the left edge,
    // out of sight and out of reach.
    bar({ hosts: [legal(300, false)], width: 390 })
    expect(restOffset(document)).toBeNull()
  })

  it('measures the host that is laid out, not the first in the DOM', () => {
    // SiteFooter's order: the inline Terms first, hidden wherever popovers work, then the
    // Legal menu, which is what a browser with popovers lays out.
    bar({ hosts: [{ name: 'terms', left: 200, laidOut: false }, legal(300)], width: 390 })
    expect(restOffset(document)).toBe(71)
  })

  it("measures Terms where a browser without popovers shows it in Legal's place", () => {
    // Without popovers, CSS hides Legal and lays out the inline pair, led by Terms. Before
    // Terms kept the slot too, that fallback bar had no slot at all. Terms at 200: slot
    // centre 166, less 195.
    bar({ hosts: [{ name: 'terms', left: 200, laidOut: true }, legal(300, false)], width: 390 })
    expect(restOffset(document)).toBe(-29)
  })

  it('is the centre when a centred face clears the copyright and Legal by the margin', () => {
    // 1280 wide: a centred 68px face spans 606..674. Copyright ends at 400, Legal at 1180.
    bar({ hosts: [legal(1180)], width: 1280, copyright: 400 })
    expect(restOffset(document)).toBe(0)
  })

  it('is midway between the copyright and Legal when the centre is too close to the copyright', () => {
    // A 430px phone: centred, his face would start at 181, only 9px past a copyright that
    // ends at 172. The gap runs 172..316 (Legal), so he rests at 244, 29 right of centre.
    bar({ hosts: [legal(316)], width: 430, copyright: 172 })
    expect(restOffset(document)).toBe(29)
  })

  it('counts the clearance on both sides, not just the copyright side', () => {
    // Copyright well clear at 100, but Legal at 340 leaves a centred face (266..334) 6px
    // short of it: midway, (100 + 340) / 2 - 300.
    bar({ hosts: [legal(340)], width: 600, copyright: 100 })
    expect(restOffset(document)).toBe(-80)
  })

  it(`goes centred exactly at ${REST_CENTRE_CLEARANCE}px of clearance`, () => {
    // Centre 500: face 466..534. Copyright ending 32px before it, Legal far off.
    bar({ hosts: [legal(900)], width: 1000, copyright: 466 - REST_CENTRE_CLEARANCE })
    expect(restOffset(document)).toBe(0)
  })
})

describe('useFooterRestOffset', () => {
  it("writes the offset on bitbag's dock before paint, never on <html>, and takes it back on unmount", () => {
    const face = dock()
    bar({ hosts: [legal(1100)], width: 1280 })
    const { unmount } = renderHook(() => useFooterRestOffset())
    // 1100 - 34 - 640.
    expect(face.style.getPropertyValue(REST_OFFSET_VAR)).toBe('426px')
    // Its only reader is inside the dock. Written on <html>, every new value re-resolved
    // inherited style for the whole document to move one face.
    expect(document.documentElement.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')
    unmount()
    expect(face.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')
  })

  it("sets nothing when there is no slot, so he rests at the dock's own centre", () => {
    const face = dock()
    renderHook(() => useFooterRestOffset())
    expect(face.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')
  })

  it('does nothing, and does not throw, when there is no dock to place', () => {
    bar({ hosts: [legal(1100)], width: 1280 })
    expect(() => renderHook(() => useFooterRestOffset())).not.toThrow()
    expect(document.documentElement.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')
  })

  it('follows the bar through a ResizeObserver on it and its links, with no window resize listener', () => {
    vi.stubGlobal('ResizeObserver', RecordingObserver)
    const listen = vi.spyOn(window, 'addEventListener')
    const face = dock()
    const host = legal(1100)
    const { footer, nav } = bar({ hosts: [host], width: 1280 })
    const { unmount } = renderHook(() => useFooterRestOffset())

    // The bar spans the viewport, so it sees every width change a window listener would;
    // the nav also sees the links beside the host change width when the bar does not.
    expect(RecordingObserver.made).toHaveLength(1)
    const observer = RecordingObserver.made[0]!
    expect(observer.observed).toEqual([footer, nav])
    expect(listen.mock.calls.filter(([type]) => type === 'resize')).toEqual([])

    host.left = 1000
    observer.notify()
    expect(face.style.getPropertyValue(REST_OFFSET_VAR)).toBe('326px')
    // A slot that stops being laid out takes the offset away rather than leaving it stale.
    host.laidOut = false
    observer.notify()
    expect(face.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')

    unmount()
    expect(observer.disconnected).toBe(true)
  })
})
