import { act, render } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// A controllable app router: `pathname` is what the next render commits, `push` records.
const nav = vi.hoisted(() => ({ pathname: '/start', pushed: [] as string[] }))
vi.mock('next/navigation', () => ({
  usePathname: () => nav.pathname,
  useRouter: () => ({ push: (href: string) => nav.pushed.push(href) }),
}))

import { SLIDE_ATTR, SlideTransitions, canSlide, slideNavigate } from '../SlideNavigation'

type Update = () => Promise<void> | void

/** A stand-in for `document.startViewTransition` that runs the update when told to, the way
 *  the browser runs it after capturing the old page. */
function installViewTransitions() {
  const pending: Update[] = []
  const finished: Array<() => void> = []
  ;(document as unknown as { startViewTransition: unknown }).startViewTransition = (update: Update) => {
    pending.push(update)
    return { finished: new Promise<void>((resolve) => finished.push(resolve)) }
  }
  return {
    pending,
    async runUpdate() {
      await pending.shift()!()
    },
    finishAll() {
      finished.splice(0).forEach((f) => f())
    },
  }
}

function setUrl(path: string) {
  window.history.replaceState(null, '', path)
}

describe('slideNavigate', () => {
  beforeEach(() => {
    nav.pathname = '/start'
    nav.pushed = []
    setUrl('/start')
    window.matchMedia = ((q: string) => ({ matches: false, media: q })) as unknown as typeof window.matchMedia
  })
  afterEach(() => {
    delete (document as unknown as { startViewTransition?: unknown }).startViewTransition
    document.documentElement.removeAttribute(SLIDE_ATTR)
  })

  it('declines where the View Transitions API is missing, so the link navigates as usual', () => {
    render(<SlideTransitions />)
    expect(canSlide()).toBe(false)
    expect(slideNavigate('/me/profile')).toBe(false)
    expect(nav.pushed).toEqual([])
  })

  it('declines for a reader who asked for reduced motion', () => {
    installViewTransitions()
    window.matchMedia = ((q: string) => ({ matches: q.includes('reduce'), media: q })) as unknown as typeof window.matchMedia
    render(<SlideTransitions />)
    expect(slideNavigate('/me/profile')).toBe(false)
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

  beforeEach(() => {
    routerSaw = []
    nav.pathname = '/start'
    nav.pushed = []
    setUrl('/start')
    window.matchMedia = ((q: string) => ({ matches: false, media: q })) as unknown as typeof window.matchMedia
    // Stands in for the app router's own (bubbling) popstate listener.
    window.addEventListener('popstate', routerListener)
  })
  afterEach(() => {
    window.removeEventListener('popstate', routerListener)
    delete (document as unknown as { startViewTransition?: unknown }).startViewTransition
    document.documentElement.removeAttribute(SLIDE_ATTR)
  })

  async function slideToProfile(vt: ReturnType<typeof installViewTransitions>, rerender: (ui: JSX.Element) => void) {
    slideNavigate('/me/profile')
    const done = vt.runUpdate()
    setUrl('/me/profile')
    nav.pathname = '/me/profile'
    rerender(<SlideTransitions />)
    await act(async () => done)
    vt.finishAll()
    await act(async () => {})
  }

  it('holds Back from a slid page until the old page is captured, then replays it to the router', async () => {
    const vt = installViewTransitions()
    const { rerender } = render(<SlideTransitions />)
    await slideToProfile(vt, rerender)

    setUrl('/start')
    window.dispatchEvent(new PopStateEvent('popstate', { state: { tag: 'back' } }))
    // Held: the router has not heard of it, and the slide is marked the other way.
    expect(routerSaw).toHaveLength(0)
    expect(document.documentElement.getAttribute(SLIDE_ATTR)).toBe('back')
    const done = vt.runUpdate()
    // Replayed from inside the transition, with the same history state.
    expect(routerSaw).toHaveLength(1)
    expect(routerSaw[0]!.state).toEqual({ tag: 'back' })
    nav.pathname = '/start'
    rerender(<SlideTransitions />)
    await act(async () => done)
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
