'use client'

import { useEffect } from 'react'
import { usePathname, useRouter } from 'next/navigation'

export type SlideDirection = 'forward' | 'back'

/** The one attribute the stylesheet keys the slide on (adh-site.css, "SLIDE NAVIGATION"). Set
 *  on <html> for the life of one transition and removed after, so an ordinary navigation —
 *  which never goes through here — keeps the browser's default of no animation at all. */
export const SLIDE_ATTR = 'data-adh-slide'

/** How long a slide waits for the destination to COMMIT before it gives the slide up.
 *
 *  A route with a loading boundary commits its skeleton almost at once, and a skeleton is a
 *  fine thing to slide in: the "new" side of a view transition is live, so the page streams
 *  into it mid-slide. A dynamic route WITHOUT one commits nothing until its data arrives: the
 *  Profile row's own destination, the hub's /[workspace]/profile, awaits its principal fetch
 *  and first shipped with no loading boundary above it. When the wait ran out the transition
 *  used to finish anyway, with the "new" capture still the OLD page — the old page slid over a
 *  copy of itself for 280 ms and then the real one cut in. So running out SKIPS the transition
 *  (`skipTransition()`): the screen unfreezes and the destination simply cuts in when it
 *  lands. 1.5 s because a screen frozen any longer is worse than a lost slide. */
const RENDER_TIMEOUT_MS = 1500

/** Pairs of paths this module slid between, newest last. They decide WHETHER a history step
 *  slides — only one between exactly two such pages does — and never which way it goes: that
 *  is the history position's to say (see `SlideTransitions`). Bounded: a long session must not
 *  grow it. */
const slides: Array<{ from: string; to: string }> = []
const MAX_SLIDES = 20

/** The path React has actually COMMITTED, as opposed to the one in the address bar — which
 *  Back changes before the page does. Written by `SlideTransitions`' effect. */
let renderedPath: string | null = null
/** Where that committed page sits in the session history (`navigation.currentEntry.index`,
 *  read when it commits), or null without the Navigation API. What a traversal's destination
 *  is compared against to tell Back from Forward. */
let renderedIndex: number | null = null
/** Slides waiting for their destination to commit; each resolves `true` when it does, `false`
 *  when the wait times out or is abandoned. */
const waiters = new Set<{ path: string; resolve: (rendered: boolean) => void }>()

/** The app router's push, registered by the mounted `SlideTransitions`. Held here rather than
 *  taken as an argument so a caller — the avatar menu, which is rendered in places with no app
 *  router at all (its tests, a static preview) — never has to reach for `useRouter`, which
 *  throws there. No `SlideTransitions` mounted ⇒ nothing registered ⇒ no slide, and the
 *  caller's own link navigates exactly as it would have. */
let push: ((href: string) => void) | null = null

type NavigationWindow = Window & { navigation?: { currentEntry: { index: number } | null } }

/** The current session-history entry's position, from the Navigation API. Null where the API
 *  is missing, or reports an entry outside the list (index -1): plain `history` has no notion
 *  of position at all, which is why a missing API means no reverse slide rather than a guess. */
function currentEntryIndex(): number | null {
  const index = (window as NavigationWindow).navigation?.currentEntry?.index
  return typeof index === 'number' && index >= 0 ? index : null
}

function markRendered(path: string): void {
  renderedPath = path
  renderedIndex = currentEntryIndex()
  for (const w of waiters) {
    if (w.path === path) {
      waiters.delete(w)
      w.resolve(true)
    }
  }
}

function untilRendered(path: string): Promise<boolean> {
  if (renderedPath === path) return Promise.resolve(true)
  return new Promise((resolve) => {
    const waiter = { path, resolve }
    waiters.add(waiter)
    setTimeout(() => {
      if (waiters.delete(waiter)) resolve(false)
    }, RENDER_TIMEOUT_MS)
  })
}

/** End every pending wait now, as a timeout would — see the popstate listener. */
function abandonWaits(): void {
  for (const w of waiters) w.resolve(false)
  waiters.clear()
}

type ViewTransitionDocument = Document & {
  startViewTransition?: (update: () => Promise<void> | void) => {
    finished: Promise<void>
    skipTransition(): void
  }
}

/**
 * Whether a slide can run here: the View Transitions API exists, and the reader has not asked
 * for less motion — in the Appearance settings first, then the OS. Where it cannot, callers
 * navigate exactly as they did before.
 *
 * The Appearance choice has to be honoured HERE, not left to the stylesheet. It lands on
 * <html> as `data-reduce-motion` — "on", "off", or absent for "auto", which follows the OS —
 * and the themes' accessibility rules that zero animation durations under it select `*`,
 * `*::before` and `*::after`, none of which matches a `::view-transition-*` pseudo-element. So
 * a reader who chose "on" still got the slide, and one who chose "off" (keep motion even
 * though the OS asks for less) never did.
 */
export function canSlide(): boolean {
  if (typeof document === 'undefined') return false
  if (typeof (document as ViewTransitionDocument).startViewTransition !== 'function') return false
  const choice = document.documentElement.dataset.reduceMotion
  if (choice === 'on') return false
  if (choice === 'off') return true
  return !window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

/** The slide that owns SLIDE_ATTR right now — the one started last. */
let activeSlide: object | null = null

/** Play one slide around `update`, which makes the navigation from inside the transition and
 *  returns whether it did: false (a stale Back — see `SlideTransitions`) means nothing is on
 *  its way, so the transition is skipped at once instead of waiting for `target`. */
function runSlide(direction: SlideDirection, target: string, update: () => boolean): void {
  const root = document.documentElement
  const token = {}
  activeSlide = token
  root.setAttribute(SLIDE_ATTR, direction)
  const transition = (document as ViewTransitionDocument).startViewTransition!(async () => {
    if (!update() || !(await untilRendered(target))) transition.skipTransition()
  })
  void transition.finished.finally(() => {
    // Only clear our own mark: a slide started meanwhile owns the attribute now. By identity,
    // not by the attribute's value — two quick Backs are two 'back' slides, and the first one
    // finishing (skipped, as the second's start skips it) would otherwise strip the mark the
    // second one's animation is keyed on.
    if (activeSlide !== token) return
    activeSlide = null
    root.removeAttribute(SLIDE_ATTR)
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
  runSlide('forward', to, () => {
    navigate(href)
    return true
  })
  return true
}

/** Whether this module slid between `a` and `b`, either way round. */
function slidBetween(a: string, b: string): boolean {
  return slides.some((s) => (s.from === a && s.to === b) || (s.from === b && s.to === a))
}

/** Marks a popstate this module re-dispatched itself, so its own listener lets it through. */
const REPLAYED = Symbol('adh-slide-replayed')
type ReplayedPopState = PopStateEvent & { [REPLAYED]?: true }

/**
 * Render-free. Tracks the committed path for `slideNavigate`, and plays a slide when the
 * browser's history steps between two pages that were slid between.
 *
 * WHICH WAY comes from the history POSITION, never from the pair. The pair only says the two
 * pages were slid between; a step over it can run either way. Reading the direction off the
 * pair's orientation played the PUSH animation on Back in the avatar menu: slide /acme →
 * /acme/profile (the Profile row), go home with the Home row (a plain push, so history reads
 * /acme, /acme/profile, /acme), press Back — /acme to /acme/profile is the pair's own
 * orientation, so it slid "forward" while the reader went back, and Forward onto that plain
 * /acme entry played the pop. `navigation.currentEntry` is already the destination by the time
 * `popstate` fires, so its index against the committed page's says which way the reader went.
 * No Navigation API ⇒ no position ⇒ no slide, rather than a guess.
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
 *
 * A HELD STEP CAN GO STALE before that callback runs. A second Back or Forward inside those
 * frames (key repeat, a mouse's back button double-firing, a slow device) is usually not held
 * itself — a Forward straight back to the page still on screen is no step at all from the
 * committed page's point of view — so it reaches the router first. Replaying the first step's
 * captured state after it handed Next the first destination's tree under the URL the second
 * step left in the address bar; Next wrote that tree into the entry, and the slide sat out the
 * whole render timeout waiting for a path that never committed. So every traversal is counted,
 * a held one is dropped at release if another arrived meanwhile or the address bar has moved
 * on, and a live one replays the CURRENT entry's `history.state` rather than the copy captured
 * with the event. A new traversal also ends any slide still waiting for its page to commit:
 * that page is no longer where history is going, and the wait would only freeze the screen
 * until it timed out.
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
    // Traversals this listener has seen, replays excluded: a held step compares it on release.
    let traversals = 0
    const onPopState = (e: PopStateEvent) => {
      if ((e as ReplayedPopState)[REPLAYED]) return
      const seen = ++traversals
      abandonWaits()
      const from = renderedPath
      const to = window.location.pathname
      if (!from || from === to || !canSlide() || !slidBetween(from, to)) return
      const index = currentEntryIndex()
      if (index === null || renderedIndex === null || index === renderedIndex) return
      e.stopImmediatePropagation()
      runSlide(index < renderedIndex ? 'back' : 'forward', to, () => {
        if (traversals !== seen || window.location.pathname !== to) return false
        const replay: ReplayedPopState = new PopStateEvent('popstate', { state: window.history.state })
        replay[REPLAYED] = true
        window.dispatchEvent(replay)
        return true
      })
    }
    window.addEventListener('popstate', onPopState, { capture: true })
    return () => window.removeEventListener('popstate', onPopState, { capture: true })
  }, [])

  return null
}
