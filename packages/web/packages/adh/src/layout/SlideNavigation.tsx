'use client'

import { useEffect } from 'react'
import { usePathname, useRouter } from 'next/navigation'

export type SlideDirection = 'forward' | 'back'

/** The one attribute the stylesheet keys the slide on (adh-site.css, "SLIDE NAVIGATION"). Set
 *  on <html> for the life of one transition and removed after, so an ordinary navigation —
 *  which never goes through here — keeps the browser's default of no animation at all. */
export const SLIDE_ATTR = 'data-adh-slide'

/** How long a slide waits for the destination to render before letting the transition finish
 *  anyway. A route that is still fetching after this long is showing its loading state, which
 *  is a fine thing to have slid in; holding the screen frozen for longer is not. */
const RENDER_TIMEOUT_MS = 1500

/** Pairs of paths this module slid between, newest last — what lets Back slide the other way
 *  between exactly those two pages and no others. Bounded: a long session must not grow it. */
const slides: Array<{ from: string; to: string }> = []
const MAX_SLIDES = 20

/** The path React has actually COMMITTED, as opposed to the one in the address bar — which
 *  Back changes before the page does. Written by `SlideTransitions`' effect. */
let renderedPath: string | null = null
const waiters = new Set<{ path: string; resolve: () => void }>()

/** The app router's push, registered by the mounted `SlideTransitions`. Held here rather than
 *  taken as an argument so a caller — the avatar menu, which is rendered in places with no app
 *  router at all (its tests, a static preview) — never has to reach for `useRouter`, which
 *  throws there. No `SlideTransitions` mounted ⇒ nothing registered ⇒ no slide, and the
 *  caller's own link navigates exactly as it would have. */
let push: ((href: string) => void) | null = null

function markRendered(path: string): void {
  renderedPath = path
  for (const w of waiters) {
    if (w.path === path) {
      waiters.delete(w)
      w.resolve()
    }
  }
}

function untilRendered(path: string): Promise<void> {
  if (renderedPath === path) return Promise.resolve()
  return new Promise((resolve) => {
    const waiter = { path, resolve }
    waiters.add(waiter)
    setTimeout(() => {
      if (waiters.delete(waiter)) resolve()
    }, RENDER_TIMEOUT_MS)
  })
}

type ViewTransitionDocument = Document & {
  startViewTransition?: (update: () => Promise<void> | void) => { finished: Promise<void> }
}

/** Whether a slide can run here: the View Transitions API exists, and the reader has not asked
 *  for less motion. Where it cannot, callers navigate exactly as they did before. */
export function canSlide(): boolean {
  if (typeof document === 'undefined') return false
  if (typeof (document as ViewTransitionDocument).startViewTransition !== 'function') return false
  return !window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

function runSlide(direction: SlideDirection, target: string, update: () => void): void {
  const root = document.documentElement
  root.setAttribute(SLIDE_ATTR, direction)
  const transition = (document as ViewTransitionDocument).startViewTransition!(async () => {
    update()
    await untilRendered(target)
  })
  void transition.finished.finally(() => {
    // Only clear our own mark: a second slide started meanwhile owns the attribute now.
    if (root.getAttribute(SLIDE_ATTR) === direction) root.removeAttribute(SLIDE_ATTR)
  })
}

function pathOf(href: string): string {
  return new URL(href, window.location.href).pathname
}

/**
 * Navigate to `href` with the page sliding in from the right, as if pushed onto a stack — and
 * remember the pair, so Back (the browser's button, or a swipe; see `SwipeHistory`) slides it
 * off again to the page it came from. It is an ordinary `router.push`: the history entry, the
 * URL and the destination are exactly what the plain link would have produced. The slide is
 * decoration.
 *
 * Returns whether it took the navigation. `false` — no API, reduced motion, no router
 * registered, or already there — means the caller should let its link navigate as usual, so
 * the call is always safe to make from a link's click handler before `preventDefault()`.
 */
export function slideNavigate(href: string): boolean {
  const navigate = push
  if (!navigate || !canSlide()) return false
  const from = window.location.pathname
  const to = pathOf(href)
  if (from === to) return false
  slides.push({ from, to })
  if (slides.length > MAX_SLIDES) slides.shift()
  runSlide('forward', to, () => navigate(href))
  return true
}

/** Which way a history step between two paths slides, if it is one this module slid. */
export function slideDirectionFor(from: string, to: string): SlideDirection | null {
  for (let i = slides.length - 1; i >= 0; i--) {
    const s = slides[i]!
    if (s.to === from && s.from === to) return 'back'
    if (s.from === from && s.to === to) return 'forward'
  }
  return null
}

/** Marks a popstate this module re-dispatched itself, so its own listener lets it through. */
const REPLAYED = Symbol('adh-slide-replayed')

/**
 * Render-free. Tracks the committed path for `slideNavigate`, and plays the reverse slide when
 * the browser's history steps between two pages that were slid between.
 *
 * WHY BACK HAS TO BE HELD FOR A FRAME: a view transition photographs the OLD page at the next
 * frame after it starts. On Back the app router starts rendering the destination the moment
 * `popstate` fires, and for a cached route it can commit before that frame — the "old" photo
 * would already be the new page, and the slide would move a page over a copy of itself. So
 * this listener runs first (capture, on the target — it precedes every bubbling `popstate`
 * listener, the router's included), holds the event back, and re-dispatches it from inside the
 * transition's update callback, once the old page is safely captured. Only a step between a
 * slid pair is held; every other popstate — including the unsaved-changes guard's same-URL
 * sentinel — passes straight through untouched.
 */
export function SlideTransitions(): null {
  const pathname = usePathname()
  const router = useRouter()

  useEffect(() => {
    const own = (href: string) => router.push(href)
    push = own
    return () => {
      if (push === own) push = null
    }
  }, [router])

  useEffect(() => {
    if (pathname) markRendered(pathname)
  }, [pathname])

  useEffect(() => {
    const onPopState = (e: PopStateEvent) => {
      if ((e as PopStateEvent & { [REPLAYED]?: true })[REPLAYED]) return
      const from = renderedPath
      const to = window.location.pathname
      if (!from || from === to || !canSlide()) return
      const direction = slideDirectionFor(from, to)
      if (!direction) return
      e.stopImmediatePropagation()
      const state: unknown = e.state
      runSlide(direction, to, () => {
        const replay = new PopStateEvent('popstate', { state }) as PopStateEvent & { [REPLAYED]?: true }
        replay[REPLAYED] = true
        window.dispatchEvent(replay)
      })
    }
    window.addEventListener('popstate', onPopState, { capture: true })
    return () => window.removeEventListener('popstate', onPopState, { capture: true })
  }, [])

  return null
}
