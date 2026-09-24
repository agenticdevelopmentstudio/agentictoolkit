'use client'

import { useLayoutEffect } from 'react'

/** How far off the dock's centre bitbag's resting face sits. adh-site.css hands it to the
 *  dock's own resting hook, `--bb-dock-rest-x` (bitbag-dock.css). */
export const REST_OFFSET_VAR = '--adh-footer-rest-x'

/** Marks a bar item that keeps bitbag's resting slot as its left margin (adh-site.css):
 *  the Legal menu, and Terms, which leads the inline pair the no-popover fallback shows in
 *  Legal's place (SiteFooter). CSS shows one of the two. */
export const REST_SLOT_HOST_CLASS = 'adh-footer__rest-slot-host'

/** Where the bar's reserved slot can be: the room `adh-footer--with-chat` opens up as a
 *  slot host's left margin. Exported for the test. */
export const REST_SLOT_SELECTOR = `.adh-footer--with-chat .${REST_SLOT_HOST_CLASS}`

/** bitbag's dock as FooterChatInner mounts it — the element the offset is written on. */
export const REST_DOCK_SELECTOR = '.bb-dock.adh-footer__chat'

/** What can move the slot when it changes size: the bar, and the links nav that holds
 *  the slot host and everything right of it. */
const RESIZE_SOURCES = '.adh-footer--with-chat, .adh-footer--with-chat .adh-footer__links'

/** The horizontal distance from the dock's centre — where bitbag's face sits with no
 *  transform — to the centre of the slot, or null when there is no slot to rest in. */
export function restOffset(doc: Document): number | null {
  // The host that is actually LAID OUT, not merely the first in the DOM. A host with no
  // layout box (display:none on it or an ancestor) reads `left: 0` while its computed
  // margin still says 68px, so measuring it centred his face half a slot beyond the
  // screen's LEFT edge, out of sight and out of reach — which is what every browser
  // without the Popover API got, because there the fallback hides Legal and shows the
  // inline Terms / Privacy pair instead.
  const host = Array.from(doc.querySelectorAll<HTMLElement>(REST_SLOT_SELECTOR)).find(
    (el) => el.getClientRects().length > 0,
  )
  if (!host) return null
  const slot = parseFloat(getComputedStyle(host).marginLeft) || 0
  // The dock is `position: fixed; left: 0; right: 0`, so its centre is the middle of
  // the viewport EXCLUDING a classic scrollbar — clientWidth, not innerWidth. `vw`
  // (what this replaced) counts the scrollbar and put him half its width too far right.
  return host.getBoundingClientRect().left - slot / 2 - doc.documentElement.clientWidth / 2
}

/**
 * Keeps {@link REST_OFFSET_VAR} on bitbag's dock pointing at the bar's reserved slot.
 *
 * MEASURED, because CSS alone cannot say where the slot is. It sits just left of the
 * Legal menu, which holds the far-right position, so its centre is the viewport's edge
 * less the padding, Legal's width and the slot's half — and Legal's width is the
 * theme's footer font's to decide. The dock is portaled to `document.body`, out from
 * under the footer, so it cannot use the bar's layout either; and a CSS anchor could
 * place the dock but not drive the transform that animates his wake.
 *
 * ON THE DOCK'S ROOT, not on <html>: the only reader is his resting avatar, inside the
 * dock, and the value changes on every change of viewport width (the slot is pinned to
 * the right edge while the dock's centre moves half as far). Written on <html>, each new
 * value re-resolved inherited style for the whole document to move one face — in a
 * Chromium trace of a 12k-element page, 4,004 elements restyled per write against 3 with
 * the value on the dock. React never touches the root's inline style (BitbagDock gives it
 * no `style` prop), so the property stays put across his renders.
 *
 * A LAYOUT effect: the dock mounts in the same commit (FooterChatInner portals it and
 * imports it statically), so it exists here, and the offset is set before his first
 * paint — he appears in the slot instead of sliding into it from the centre.
 * Re-measured whenever the footer or its links change size, and once the web fonts
 * settle, since those are what move Legal. The footer spans the viewport, so observing
 * it covers every width change a window `resize` listener would have — which is why
 * there is none — and a height-only resize cannot move the slot. The links nav, not
 * the slot host alone: in the fallback, Privacy sits right of the host and its width
 * moves the host too.
 */
export function useFooterRestOffset(): void {
  useLayoutEffect(() => {
    const dock = document.querySelector<HTMLElement>(REST_DOCK_SELECTOR)
    // No dock, no face to place.
    if (!dock) return
    const update = () => {
      const x = restOffset(document)
      if (x === null) dock.style.removeProperty(REST_OFFSET_VAR)
      else dock.style.setProperty(REST_OFFSET_VAR, `${x}px`)
    }
    update()
    const ro = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(update)
    for (const el of document.querySelectorAll(RESIZE_SOURCES)) ro?.observe(el)
    let live = true
    document.fonts?.ready.then(() => {
      if (live) update()
    })
    return () => {
      live = false
      ro?.disconnect()
      dock.style.removeProperty(REST_OFFSET_VAR)
    }
  }, [])
}
