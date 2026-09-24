'use client'

import { useLayoutEffect } from 'react'

/** The custom property adh-site.css translates bitbag's resting face by. */
export const REST_OFFSET_VAR = '--adh-footer-rest-x'

/** Where the bar's reserved slot is: the room `adh-footer--with-chat` opens up as the
 *  Legal menu's left margin (adh-site.css). Exported for the test. */
export const REST_SLOT_SELECTOR = '.adh-footer--with-chat .adh-footer__legal'

/** The horizontal distance from the dock's centre — where bitbag's face sits with no
 *  transform — to the centre of the slot, or null when there is no slot to rest in. */
export function restOffset(doc: Document): number | null {
  const host = doc.querySelector<HTMLElement>(REST_SLOT_SELECTOR)
  if (!host) return null
  const slot = parseFloat(getComputedStyle(host).marginLeft) || 0
  // The dock is `position: fixed; left: 0; right: 0`, so its centre is the middle of
  // the viewport EXCLUDING a classic scrollbar — clientWidth, not innerWidth. `vw`
  // (what this replaced) counts the scrollbar and put him half its width too far right.
  return host.getBoundingClientRect().left - slot / 2 - doc.documentElement.clientWidth / 2
}

/**
 * Keeps {@link REST_OFFSET_VAR} on the root element pointing at the bar's reserved slot.
 *
 * MEASURED, because CSS alone cannot say where the slot is. It sits just left of the
 * Legal menu, which holds the far-right position, so its centre is the viewport's edge
 * less the padding, Legal's width and the slot's half — and Legal's width is the
 * theme's footer font's to decide. The dock is portaled to `document.body`, out from
 * under the footer, so it cannot use the bar's layout either; and a CSS anchor could
 * place the dock but not drive the transform that animates his wake.
 *
 * A LAYOUT effect: the dock mounts in the same commit, so the offset is set before his
 * first paint and he appears in the slot instead of sliding into it from the centre.
 * Re-measured whenever the footer, Legal or the viewport changes size, and once the web
 * fonts settle, since those are what move Legal.
 */
export function useFooterRestOffset(): void {
  useLayoutEffect(() => {
    const root = document.documentElement
    const update = () => {
      const x = restOffset(document)
      if (x === null) root.style.removeProperty(REST_OFFSET_VAR)
      else root.style.setProperty(REST_OFFSET_VAR, `${x}px`)
    }
    update()
    window.addEventListener('resize', update)
    const ro = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(update)
    for (const el of document.querySelectorAll('.adh-footer, ' + REST_SLOT_SELECTOR)) ro?.observe(el)
    let live = true
    document.fonts?.ready.then(() => {
      if (live) update()
    })
    return () => {
      live = false
      window.removeEventListener('resize', update)
      ro?.disconnect()
      root.style.removeProperty(REST_OFFSET_VAR)
    }
  }, [])
}
