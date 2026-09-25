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

/** The copyright line: the bar's left-hand item, which a centred face must keep clear of. */
export const REST_COPYRIGHT_SELECTOR = '.adh-footer--with-chat .adh-footer__copyright'

/** The least air, in px, between a CENTRED resting face and the bar items either side of
 *  it. Closer than this and he reads as crowding the copyright, so he moves to the middle
 *  of the gap instead. Px, like the slot: his resting box is laid out in px. */
export const REST_CENTRE_CLEARANCE = 32

/** What can move the slot when it changes size: the bar, the links nav that holds the
 *  slot host and everything right of it, and the copyright whose right edge he keeps
 *  clear of. */
const RESIZE_SOURCES = [
  '.adh-footer--with-chat',
  '.adh-footer--with-chat .adh-footer__links',
  REST_COPYRIGHT_SELECTOR,
].join(', ')

const laidOut = (el: Element | null): el is HTMLElement =>
  el instanceof HTMLElement && el.getClientRects().length > 0

/** The laid-out item just left of the slot: the nearest preceding link a site added to
 *  the bar, or else the copyright. The hidden no-popover pair before Legal is skipped —
 *  it has no box. */
function leftNeighbour(doc: Document, host: HTMLElement): HTMLElement | null {
  for (let el = host.previousElementSibling; el; el = el.previousElementSibling) {
    if (laidOut(el)) return el
  }
  const copyright = doc.querySelector(REST_COPYRIGHT_SELECTOR)
  return laidOut(copyright) ? copyright : null
}

/**
 * The horizontal distance from the dock's centre — where bitbag's face sits with no
 * transform — to where he rests, or null when the bar keeps no slot for him.
 *
 * Two places, in order of preference:
 * 1. THE CENTRE (0) — the bar's middle, where he opens — when a face that wide sits there
 *    with at least {@link REST_CENTRE_CLEARANCE} to spare on both sides.
 * 2. MIDWAY between the item on his left (the copyright, on an adh bar) and the slot's
 *    host (Legal). The slot guarantees that gap is at least his width, so the middle of it
 *    always fits him.
 */
export function restOffset(doc: Document): number | null {
  // The host that is actually LAID OUT, not merely the first in the DOM. A host with no
  // layout box (display:none on it or an ancestor) reads `left: 0` while its computed
  // margin still says 68px, so measuring it centred his face half a slot beyond the
  // screen's LEFT edge, out of sight and out of reach — which is what every browser
  // without the Popover API got, because there the fallback hides Legal and shows the
  // inline Terms / Privacy pair instead.
  const host = Array.from(doc.querySelectorAll<HTMLElement>(REST_SLOT_SELECTOR)).find(laidOut)
  if (!host) return null
  // The slot is his resting box's width (adh-site.css), so it is also the width a centred
  // face needs.
  const slot = parseFloat(getComputedStyle(host).marginLeft) || 0
  // The dock is `position: fixed; left: 0; right: 0`, so its centre is the middle of
  // the viewport EXCLUDING a classic scrollbar — clientWidth, not innerWidth. `vw`
  // (what this replaced) counts the scrollbar and put him half its width too far right.
  const centre = doc.documentElement.clientWidth / 2
  const right = host.getBoundingClientRect().left
  const neighbour = leftNeighbour(doc, host)
  // Nothing on his left to measure: the slot's own centre, which is always clear.
  if (!neighbour) return right - slot / 2 - centre
  const left = neighbour.getBoundingClientRect().right
  const fitsCentred =
    centre - slot / 2 - left >= REST_CENTRE_CLEARANCE &&
    right - (centre + slot / 2) >= REST_CENTRE_CLEARANCE
  return fitsCentred ? 0 : (left + right) / 2 - centre
}

/**
 * Keeps {@link REST_OFFSET_VAR} on bitbag's dock pointing at where he rests in the bar —
 * the centre where there is room, else midway along the gap the slot keeps open (see
 * {@link restOffset}).
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
