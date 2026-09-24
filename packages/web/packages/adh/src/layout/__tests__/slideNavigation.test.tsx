import type { ReactElement } from 'react'
import { act, render } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// A controllable app router: `pathname` is what the next render commits, `push` records.
const nav = vi.hoisted(() => ({ pathname: '/start', pushed: [] as string[] }))
vi.mock('next/navigation', () => ({
  usePathname: () => nav.pathname,
  useRouter: () => ({ push: (href: string) => nav.pushed.push(href) }),
}))

// By package path, as every importer must: the module's state is shared across the package's
// entries only through this one specifier (see the `layout/SlideNavigation` tsup entry).
import { SLIDE_ATTR, SlideTransitions, canSlide, slideNavigate } from '@agentic-toolkit/adh/layout/SlideNavigation'

type Update = () => Promise<void> | void

/** A stand-in for `document.startViewTransition` that runs the update when told to, the way
 *  the browser runs it after capturing the old page. `skipped` records, in start order, which
 *  transitions were given up with `skipTransition()`. */
function installViewTransitions() {
  const pending: Update[] = []
  const finished: Array<() => void> = []
  const skipped: boolean[] = []
  ;(document as unknown as { startViewTransition: unknown }).startViewTransition = (update: Update) => {
    const n = skipped.push(false) - 1
    pending.push(update)
    return {
      finished: new Promise<void>((resolve) => finished.push(resolve)),
      skipTransition: () => {
        skipped[n] = true
      },
    }
  }
  return {
    pending,
    skipped,
    async runUpdate() {
      await pending.shift()!()
    },
    /** Settle the oldest unfinished transition only. */
    finishNext() {
      finished.shift()?.()
    },
    finishAll() {
      finished.splice(0).forEach((f) => f())
    },
  }
}

/** jsdom has no Navigation API. This stands in for the one thing the module reads from it, the
 *  current entry's position — which the browser has already moved to the destination by the
 *  time `popstate` fires, so tests call `at()` before dispatching one. */
function installNavigation() {
  const navigation = { currentEntry: { index: 0 } }
  ;(window as unknown as { navigation?: unknown }).navigation = navigation
  return {
    at(index: number) {
      navigation.currentEntry.index = index
    },
  }
}

function removeNavigation() {
  delete (window as unknown as { navigation?: unknown }).navigation
}

function setUrl(path: string, state: unknown = null) {
  window.history.replaceState(state, '', path)
}

const REDUCE = ((q: string) => ({ matches: q.includes('reduce'), media: q })) as unknown as typeof window.matchMedia
const NO_PREFERENCE = ((q: string) => ({ matches: false, media: q })) as unknown as typeof window.matchMedia

describe('slideNavigate', () => {
  beforeEach(() => {
    nav.pathname = '/start'
    nav.pushed = []
    setUrl('/start')
    window.matchMedia = NO_PREFERENCE
    installNavigation()
  })
  afterEach(() => {
    delete (document as unknown as { startViewTransition?: unknown }).startViewTransition
    delete document.documentElement.dataset.reduceMotion
    document.documentElement.removeAttribute(SLIDE_ATTR)
    removeNavigation()
    vi.useRealTimers()
  })

  it('declines where the View Transitions API is missing, so the link navigates as usual', () => {
    render(<SlideTransitions />)
    expect(canSlide()).toBe(false)
    expect(slideNavigate('/me/profile')).toBe(false)
    expect(nav.pushed).toEqual([])
  })

  it('declines for a reader who asked for reduced motion', () => {
    installViewTransitions()
    window.matchMedia = REDUCE
    render(<SlideTransitions />)
    expect(slideNavigate('/me/profile')).toBe(false)
  })

  it('follows the Appearance setting over the OS: "on" never slides, "off" slides even when the OS asks for less', () => {
    installViewTransitions()
    const root = document.documentElement
    root.dataset.reduceMotion = 'on'
    expect(canSlide()).toBe(false)
    window.matchMedia = REDUCE
    root.dataset.reduceMotion = 'off'
    expect(canSlide()).toBe(true)
    // "Auto" writes no attribute, and the OS decides again.
    delete root.dataset.reduceMotion
    expect(canSlide()).toBe(false)
  })

  it('declines with no SlideTransitions mounted — there is no router to push with', () => {
    installViewTransitions()
    expect(slideNavigate('/me/profile')).toBe(false)
  })

  it('pushes inside the transition, after the old page is captured, and marks it forward', async () => {
    const vt = installViewTransitions()
    const { rerender } = render(<SlideTransitions />)
    expect(slideNavigate('/me/profile')).toBe(true)
    expect(document.documentElement.getAttribute(SLIDE_ATTR)).toBe('forward')
    // Not yet — the browser has not run the update.
    expect(nav.pushed).toEqual([])
    const done = vt.runUpdate()
    expect(nav.pushed).toEqual(['/me/profile'])
    // The update waits for the destination to COMMIT, not for the URL to change.
    nav.pathname = '/me/profile'
    rerender(<SlideTransitions />)
    await act(async () => done)
    // Committed in time, so the slide plays.
    expect(vt.skipped).toEqual([false])
    vt.finishAll()
    await act(async () => {})
    expect(document.documentElement.hasAttribute(SLIDE_ATTR)).toBe(false)
  })

  it('gives the slide up when the destination has not committed in time, rather than slide the old page over itself', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    const vt = installViewTransitions()
    render(<SlideTransitions />)
    expect(slideNavigate('/me/profile')).toBe(true)
    const waiting = vt.runUpdate()
    await vi.advanceTimersByTimeAsync(1499)
    expect(vt.skipped).toEqual([false])
    // /me/profile never committed (a dynamic route with no loading boundary, still fetching).
    await vi.advanceTimersByTimeAsync(1)
    await waiting
    expect(vt.skipped).toEqual([true])
  })

  it('never lets an older slide clear the mark of a newer one going the same way', async () => {
    const vt = installViewTransitions()
    render(<SlideTransitions />)
    slideNavigate('/me/profile')
    slideNavigate('/me/settings')
    // The first one settles first — starting the second skipped it.
    vt.finishNext()
    await act(async () => {})
    expect(document.documentElement.getAttribute(SLIDE_ATTR)).toBe('forward')
    vt.finishAll()
    await act(async () => {})
    expect(document.documentElement.hasAttribute(SLIDE_ATTR)).toBe(false)
  })

  it('declines a push to the page already showing', () => {
    installViewTransitions()
    render(<SlideTransitions />)
    expect(slideNavigate('/start')).toBe(false)
  })
})

describe('SlideTransitions on Back', () => {
  let routerSaw: PopStateEvent[]
  const routerListener = (e: PopStateEvent) => routerSaw.push(e)
  let navigation: ReturnType<typeof installNavigation>

  beforeEach(() => {
    routerSaw = []
    nav.pathname = '/start'
    nav.pushed = []
    setUrl('/start')
    window.matchMedia = NO_PREFERENCE
    navigation = installNavigation()
    // Stands in for the app router's own (bubbling) popstate listener.
    window.addEventListener('popstate', routerListener)
  })
  afterEach(() => {
    window.removeEventListener('popstate', routerListener)
    delete (document as unknown as { startViewTransition?: unknown }).startViewTransition
    document.documentElement.removeAttribute(SLIDE_ATTR)
    removeNavigation()
  })

  /** Render at /start (entry 0), then slide to /me/profile, which becomes entry 1. */
  async function mountAndSlideToProfile(vt: ReturnType<typeof installViewTransitions>) {
    const { rerender } = render(<SlideTransitions />)
    slideNavigate('/me/profile')
    const done = vt.runUpdate()
    navigation.at(1)
    setUrl('/me/profile')
    nav.pathname = '/me/profile'
    rerender(<SlideTransitions />)
    await act(async () => done)
    vt.finishAll()
    await act(async () => {})
    return rerender
  }

  /** The browser's half of a history step: move the entry and the URL, then fire popstate. */
  function traverse(index: number, path: string, state: unknown = null) {
    navigation.at(index)
    setUrl(path, state)
    window.dispatchEvent(new PopStateEvent('popstate', { state }))
  }

  it('holds Back from a slid page until the old page is captured, then replays it to the router', async () => {
    const vt = installViewTransitions()
    const rerender = await mountAndSlideToProfile(vt)

    traverse(0, '/start', { tag: 'back' })
    // Held: the router has not heard of it, and the slide is marked the other way.
    expect(routerSaw).toHaveLength(0)
    expect(document.documentElement.getAttribute(SLIDE_ATTR)).toBe('back')
    const done = vt.runUpdate()
    // Replayed from inside the transition, with the entry's history state.
    expect(routerSaw).toHaveLength(1)
    expect(routerSaw[0]!.state).toEqual({ tag: 'back' })
    nav.pathname = '/start'
    rerender(<SlideTransitions />)
    await act(async () => done)
  })

  it('takes the direction from the history position, not from which way the pair was slid', async () => {
    const vt = installViewTransitions()
    const rerender = await mountAndSlideToProfile(vt)
    // Home again by a PLAIN push (the avatar menu's Home row): /start, /me/profile, /start.
    navigation.at(2)
    setUrl('/start')
    nav.pathname = '/start'
    rerender(<SlideTransitions />)

    // Back runs /start → /me/profile — the slid pair's own orientation — and is still a Back.
    traverse(1, '/me/profile')
    expect(document.documentElement.getAttribute(SLIDE_ATTR)).toBe('back')
    const back = vt.runUpdate()
    nav.pathname = '/me/profile'
    rerender(<SlideTransitions />)
    await act(async () => back)
    vt.finishAll()
    await act(async () => {})

    // And Forward onto that plain /start entry is a push, not a pop.
    traverse(2, '/start')
    expect(document.documentElement.getAttribute(SLIDE_ATTR)).toBe('forward')
    const forward = vt.runUpdate()
    nav.pathname = '/start'
    rerender(<SlideTransitions />)
    await act(async () => forward)
  })

  it('lets Back through unslid where there is no Navigation API to say which way it went', async () => {
    const vt = installViewTransitions()
    removeNavigation()
    await mountAndSlideToProfile(vt)
    setUrl('/start')
    window.dispatchEvent(new PopStateEvent('popstate', { state: null }))
    expect(routerSaw).toHaveLength(1)
    expect(document.documentElement.hasAttribute(SLIDE_ATTR)).toBe(false)
  })

  it('drops a held Back that another step overtook, rather than replay a stale tree to the router', async () => {
    const vt = installViewTransitions()
    await mountAndSlideToProfile(vt)
    traverse(0, '/start', { tag: 'start' })
    expect(routerSaw).toHaveLength(0)
    // Forward again before the old page was captured. The page on screen is still /me/profile,
    // so to this module it is no step at all, and the router gets it straight away.
    traverse(1, '/me/profile', { tag: 'profile' })
    expect(routerSaw.map((e) => e.state)).toEqual([{ tag: 'profile' }])
    await act(async () => vt.runUpdate())
    // The held Back is dropped, not replayed on top, and its transition is given up at once
    // instead of waiting out the timeout for a /start that is never coming.
    expect(routerSaw.map((e) => e.state)).toEqual([{ tag: 'profile' }])
    expect(vt.skipped.at(-1)).toBe(true)
  })

  it('replays the entry state as it stands at release, not the copy the event captured', async () => {
    const vt = installViewTransitions()
    const rerender = await mountAndSlideToProfile(vt)
    traverse(0, '/start', { tag: 'captured' })
    // The entry is rewritten while the step is held (Next's history sync replaces it).
    setUrl('/start', { tag: 'current' })
    const done = vt.runUpdate()
    expect(routerSaw.map((e) => e.state)).toEqual([{ tag: 'current' }])
    nav.pathname = '/start'
    rerender(<SlideTransitions />)
    await act(async () => done)
  })

  it('ends a slide still waiting for its page the moment history moves again', async () => {
    const vt = installViewTransitions()
    render(<SlideTransitions />)
    slideNavigate('/me/profile')
    const waiting = vt.runUpdate()
    // Back to some other page before /me/profile committed: nothing to slide there, and the
    // pending wait is for a page history is no longer heading to.
    traverse(0, '/elsewhere')
    await act(async () => waiting)
    expect(vt.skipped).toEqual([true])
    expect(routerSaw).toHaveLength(1)
  })

  it('lets every other popstate straight through', async () => {
    installViewTransitions()
    render(<SlideTransitions />)
    setUrl('/elsewhere')
    window.dispatchEvent(new PopStateEvent('popstate', { state: null }))
    expect(routerSaw).toHaveLength(1)
    expect(document.documentElement.hasAttribute(SLIDE_ATTR)).toBe(false)
  })

  it('lets a same-URL popstate (the unsaved-changes guard\'s sentinel) straight through', async () => {
    installViewTransitions()
    render(<SlideTransitions />)
    window.dispatchEvent(new PopStateEvent('popstate', { state: null }))
    expect(routerSaw).toHaveLength(1)
  })
})
