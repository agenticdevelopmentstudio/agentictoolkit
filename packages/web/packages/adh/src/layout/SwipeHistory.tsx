'use client'

import { useEffect } from 'react'

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
 */
const EXEMPT_SELECTOR =
  'input, textarea, select, [contenteditable=""], [contenteditable="true"], ' +
  '[role="dialog"], [role="menu"], [role="listbox"], [role="slider"], [data-no-swipe-nav]'

/** True when `el` or an ancestor scrolls horizontally — the swipe is that element's to use. */
function insideHorizontalScroller(el: Element | null): boolean {
  for (let node = el; node && node !== document.body; node = node.parentElement) {
    if (node.scrollWidth <= node.clientWidth) continue
    const overflowX = getComputedStyle(node).overflowX
    if (overflowX === 'auto' || overflowX === 'scroll') return true
  }
  return false
}

function swipeExempt(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) return false
  return target.closest(EXEMPT_SELECTOR) !== null || insideHorizontalScroller(target)
}

/**
 * Turns a horizontal flick on a touch screen into browser back / forward. Renders nothing.
 *
 * History, not a router call: `history.back()` is exactly what the browser's own button does,
 * so the in-app back chevrons, the URL-driven narrow-mode stack and a swipe all land on the
 * same entry — there is one stack, the browser's.
 *
 * Touch-only (`pointer: coarse`): a trackpad's two-finger swipe is already the OS's, and a
 * mouse drag is never a navigation. Listeners are passive — this never calls preventDefault,
 * so scrolling stays on the compositor.
 */
export function SwipeHistory(): null {
  useEffect(() => {
    if (!window.matchMedia?.('(pointer: coarse)').matches) return
    let start: SwipeSample | null = null

    const onStart = (e: TouchEvent) => {
      start = null
      if (e.touches.length !== 1 || swipeExempt(e.target)) return
      const touch = e.touches[0]
      start = { x: touch.clientX, y: touch.clientY, t: e.timeStamp }
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
      if (direction === 'back') window.history.back()
      else if (direction === 'forward') window.history.forward()
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
