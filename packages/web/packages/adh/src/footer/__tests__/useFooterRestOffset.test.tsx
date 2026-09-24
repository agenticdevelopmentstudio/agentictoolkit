import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, renderHook } from '@testing-library/react'
import { REST_OFFSET_VAR, restOffset, useFooterRestOffset } from '../useFooterRestOffset'

/** A bar with Legal at `left`, its slot margin `slot` wide, in a `width`-wide viewport. */
function bar({ left, slot, width }: { left: number; slot: number; width: number }) {
  const { container } = render(
    <footer className="adh-footer adh-footer--with-chat">
      <span className="adh-footer__legal" style={{ marginLeft: `${slot}px` }} />
    </footer>,
  )
  const legal = container.querySelector<HTMLElement>('.adh-footer__legal')!
  legal.getBoundingClientRect = () => ({ left }) as DOMRect
  Object.defineProperty(document.documentElement, 'clientWidth', { configurable: true, value: width })
}

afterEach(() => {
  cleanup()
  document.documentElement.style.removeProperty(REST_OFFSET_VAR)
})

describe('restOffset', () => {
  it('is the slot centre (just left of Legal) less the viewport centre', () => {
    // Legal at 300 with a 68px slot before it: slot centre 266. Viewport 390: centre 195.
    bar({ left: 300, slot: 68, width: 390 })
    expect(restOffset(document)).toBe(71)
  })

  it('is null when the bar keeps no slot — a footer without chat', () => {
    render(<footer className="adh-footer"><span className="adh-footer__legal" /></footer>)
    expect(restOffset(document)).toBeNull()
  })
})

describe('useFooterRestOffset', () => {
  it('publishes the offset on the root element before paint, and takes it back on unmount', () => {
    bar({ left: 1100, slot: 68, width: 1280 })
    const { unmount } = renderHook(() => useFooterRestOffset())
    expect(document.documentElement.style.getPropertyValue(REST_OFFSET_VAR)).toBe('426px')
    unmount()
    expect(document.documentElement.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')
  })

  it('sets nothing when there is no slot, so he rests at the dock\'s own centre', () => {
    renderHook(() => useFooterRestOffset())
    expect(document.documentElement.style.getPropertyValue(REST_OFFSET_VAR)).toBe('')
  })
})
