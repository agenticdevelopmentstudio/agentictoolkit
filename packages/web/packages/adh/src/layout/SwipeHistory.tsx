'use client'

import { useEffect } from 'react'
import { offerSwipeBack } from '@agenticdevelopertoolkit/ui/lib/swipe-back'

/** Where a touch went down and came up, plus when. Viewport pixels and milliseconds. */
export type SwipeSample = { x: number; y: number; t: number }

export type SwipeDirection = 'back' | 'forward'

/** Minimum horizontal travel for a swipe to count — below this it is a tap or a wobble. */
export const SWIPE_MIN_DISTANCE = 80
/** A swipe slower than this is a drag (selecting text, nudging a slider), not a flick. */
export const SWIPE_MAX_DURATION_MS = 600
/** Horizontal travel must beat vertical by this factor, so a scroll that drifts sideways
 *  never navigates. */
export const SWIPE_AXIS_RATIO = 2
/** Touches that START this close to a screen edge are the browser's. iOS Safari already
 *  turns an edge swipe into back/forward; handling it here as well would navigate TWICE. */
export const SWIPE_EDGE_GUTTER = 24

/**
 * Classify one touch as a history swipe, or not. Pure, so the thresholds are testable without
 * synthesising touch events. A finger moving RIGHT is "back" — the page slides away to reveal
 * the one before it, as in every iOS navigation stack.
 */
export function classifySwipe(
  start: SwipeSample,
  end: SwipeSample,
  viewportWidth: number,
): SwipeDirection | null {
  if (start.x < SWIPE_EDGE_GUTTER || start.x > viewportWidth - SWIPE_EDGE_GUTTER) return null
  const dx = end.x - start.x
  const dy = end.y - start.y
  if (end.t - start.t > SWIPE_MAX_DURATION_MS) return null
  if (Math.abs(dx) < SWIPE_MIN_DISTANCE) return null
  if (Math.abs(dx) < SWIPE_AXIS_RATIO * Math.abs(dy)) return null
  return dx > 0 ? 'back' : 'forward'
}

/**
 * Elements a swipe must be left alone inside: text entry (a swipe there moves the caret or
 * selects), open dialogs and menus (navigating would pull the page out from under them), and
 * anything that opts out explicitly with `data-no-swipe-nav` — a carousel, a slider, a canvas.
 *
 * `[popover]` rather than a role, because an open panel is not always labelled one: the
 * footer's Legal and copyright menus (AdhFooter's FooterMenu) are `popover="auto"` panels
 * with no role at all, so `[role="menu"]` never matched them and a sideways flick inside an
 * open one took the page away from under it. A closed popover is `display: none` (the UA
 * default) and takes no touches, so the bare attribute only ever matches an open panel.
 *
 * `[role="separator"]` is a resize handle — the HTDV rail's (topic-detail), SplitDivider, the
 * data table's column resizers. Widening a rail on a tablet is a quick sideways drag that
 * classifySwipe reads as a flick (x 240 → 375 in 350 ms is "back"), and a handle's own
 * `preventDefault()` acts on pointer events only, so the document still saw both touches and
 * left the page mid-resize. (A handle with no role is caught by its `touch-action: none` —
 * see `ownsHorizontalDrag`.)
 *
 * Attribute tests only: `closest` reads no layout, so this part runs at touchstart.
 */
const EXEMPT_SELECTOR =
  'input, textarea, select, [contenteditable=""], [contenteditable="true"], ' +
  '[role="dialog"], [role="menu"], [role="listbox"], [role="slider"], [role="separator"], ' +
  '[popover], [data-no-swipe-nav]'

/**
 * True when `el` or an ancestor takes horizontal drags as its own input, so a flick there is
 * not a navigation: it scrolls sideways (a table, a code block, a tab strip), or it declares
 * `touch-action: none` — what every custom drag surface in the toolkit carries (the resize
 * handles, the dnd grips, the projects board, calendar and timeline items), because without it
 * the browser would claim the pan itself. Walked up the ancestors because touch-action is not
 * inherited: the icon inside a handle computes `auto`.
 *
 * It reads layout (`scrollWidth`) and computed style, so it runs at TOUCHEND and only once
 * `classifySwipe` has said the touch was a flick. It used to run at every touchstart, where the
 * first `scrollWidth` read forces a synchronous layout whenever layout is dirty — on almost
 * every frame while the chat streams a reply — for an answer every tap and scroll then threw
 * away.
 */
function ownsHorizontalDrag(el: Element): boolean {
  for (let node: Element | null = el; node && node !== document.body; node = node.parentElement) {
    const style = getComputedStyle(node)
    if (style.touchAction === 'none') return true
    if (node.scrollWidth <= node.clientWidth) continue
    if (style.overflowX === 'auto' || style.overflowX === 'scroll') return true
  }
  return false
}

/** A touch that began outside every exempt element, and the element it began on — kept for
 *  the touchend checks and for `offerSwipeBack`, since touchend's own target is that same
 *  element anyway. */
type SwipeStart = SwipeSample & { target: EventTarget | null }

/**
 * Turns a horizontal flick on a touch screen into browser back / forward. Renders nothing.
 *
 * History, not a router call: `history.back()` is exactly what the browser's own button does,
 * so wherever an in-page Back is itself a history entry — the in-app back chevrons, the
 * URL-driven narrow-mode stack — a swipe lands on the same entry. Not every in-page Back is
 * one: HTDV's narrow stack reveals a `persistentSelection` level's list through local state,
 * with no history entry, so on hub /settings the chevron on screen showed the section list
 * while a flick left Settings for whatever page came before it. So a Back flick is OFFERED
 * first (`offerSwipeBack`, dispatched at the element the touch began on): an in-page Back that
 * contains it and is showing a Back runs its own and claims it, and only an unclaimed flick
 * goes to history. Forward has no in-page twin, so it goes straight to `history.forward()`.
 *
 * Touch-only (`pointer: coarse`): a trackpad's two-finger swipe is already the OS's, and a
 * mouse drag is never a navigation. Listeners are passive — this never calls preventDefault,
 * so scrolling stays on the compositor.
 */
export function SwipeHistory(): null {
  useEffect(() => {
    if (!window.matchMedia?.('(pointer: coarse)').matches) return
    let start: SwipeStart | null = null

    const onStart = (e: TouchEvent) => {
      start = null
      const touch = e.touches[0]
      if (!touch || e.touches.length !== 1) return
      const target = e.target
      if (target instanceof Element && target.closest(EXEMPT_SELECTOR)) return
      start = { x: touch.clientX, y: touch.clientY, t: e.timeStamp, target }
    }
    const onEnd = (e: TouchEvent) => {
      if (!start) return
      const touch = e.changedTouches[0]
      const from = start
      start = null
      if (!touch) return
      const direction = classifySwipe(
        from,
        { x: touch.clientX, y: touch.clientY, t: e.timeStamp },
        window.innerWidth,
      )
      if (!direction) return
      const { target } = from
      if (target instanceof Element && ownsHorizontalDrag(target)) return
      if (direction === 'back') {
        // Offered before history — an in-page Back under the finger may claim it (see above).
        if (!target || !offerSwipeBack(target)) window.history.back()
      } else {
        window.history.forward()
      }
    }
    const onCancel = () => {
      start = null
    }

    document.addEventListener('touchstart', onStart, { passive: true })
    document.addEventListener('touchend', onEnd, { passive: true })
    document.addEventListener('touchcancel', onCancel, { passive: true })
    return () => {
      document.removeEventListener('touchstart', onStart)
      document.removeEventListener('touchend', onEnd)
      document.removeEventListener('touchcancel', onCancel)
    }
  }, [])
  return null
}
