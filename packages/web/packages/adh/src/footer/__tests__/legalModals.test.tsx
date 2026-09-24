import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { openLegalModal, TERMS_DIALOG_ID } from '../LegalModals'

// A footer Legal link opens its modal in place, but only for a click the page is
// meant to handle: a new-tab / new-window / download click belongs to the browser,
// which follows the anchor's own /terms href. This handler used to carry its own
// copy of that rule, and the copy had dropped the button check the other four kept.

afterEach(cleanup)

function renderLegalLink() {
  // jsdom has no Popover API; give the dialog the one method the handler probes for.
  const showPopover = vi.fn()
  const handler = openLegalModal(TERMS_DIALOG_ID)
  // Every button the handler SAW, so a pass-through test cannot pass vacuously: React
  // drops secondary-button clicks before any onClick, but it does deliver a middle one.
  const seen: number[] = []
  const view = render(
    <>
      <div id={TERMS_DIALOG_ID} />
      <a
        href="/terms"
        onClick={(e) => {
          seen.push(e.button)
          handler(e)
        }}
      >
        Terms of Service
      </a>
    </>,
  )
  Object.assign(view.container.querySelector(`#${TERMS_DIALOG_ID}`)!, { showPopover })
  return { showPopover, seen, link: screen.getByRole('link', { name: 'Terms of Service' }) }
}

describe('openLegalModal', () => {
  it('opens the modal in place of navigating on a plain click', () => {
    const { showPopover, link } = renderLegalLink()
    const notPrevented = fireEvent.click(link)
    expect(showPopover).toHaveBeenCalledTimes(1)
    expect(notPrevented).toBe(false)
  })

  it('leaves a middle-click to the browser (a new tab on /terms)', () => {
    const { showPopover, seen, link } = renderLegalLink()
    const notPrevented = fireEvent.click(link, { button: 1 })
    expect(seen).toEqual([1]) // the handler got it, and declined it
    expect(showPopover).not.toHaveBeenCalled()
    expect(notPrevented).toBe(true)
  })

  it('leaves a modified click to the browser', () => {
    const { showPopover, link } = renderLegalLink()
    expect(fireEvent.click(link, { metaKey: true })).toBe(true)
    expect(showPopover).not.toHaveBeenCalled()
  })
})
