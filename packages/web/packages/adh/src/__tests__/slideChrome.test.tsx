/**
 * A slide navigation (layout/SlideNavigation.tsx) moves the page body and holds the chrome
 * still, and it holds the chrome still by NAMING it: while `data-adh-slide` is on <html>,
 * adh-site.css gives the shell's header, its footer and bitbag's dock a view-transition-name
 * each, so each is a group of its own and paints above the sliding page. Left in the root
 * snapshot they painted UNDER it, and on any page taller than the screen the slide swept
 * across all three.
 *
 * A name must be unique among the page's elements, or the browser skips the whole transition,
 * and a page can hold a second header and footer: the theme editor's specimens, in the Debug
 * console. So this lays a page out as the shell does, opens the console's previews over it,
 * turns the slide on, and asks the sheet's own naming rules what they name. jsdom runs no view
 * transition; which element carries which name is the whole of what the rules decide.
 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render } from '@testing-library/react'
import { createPortal } from 'react-dom'
import type { ComponentType } from 'react'

// The shell mounts SlideTransitions, which takes the app router's push; there is no app
// router under vitest, so stand one in.
vi.mock('next/navigation', () => ({ usePathname: () => '/', useRouter: () => ({ push: () => {} }) }))

// A plain anchor: next/link's own needs an app router this file has no use for.
vi.mock('next/link', () => ({
  default: ({ href, prefetch: _prefetch, ...rest }: { href: string; prefetch?: boolean }) => (
    <a href={href} {...rest} />
  ),
}))

// The bell opens a live channel the moment it mounts; who gets one is site-header.test's subject.
vi.mock('@agentic-toolkit/messaging/components/notification-bell', () => ({
  NotificationBell: () => null,
}))

// bitbag's dock, as the page's footer mounts it: the element his naming rule is for. That the
// rule's selector finds the REAL dock is footerDock.test's (REST_DOCK_SELECTOR, below).
vi.mock('../footer/FooterChat', () => ({
  FooterChat: () => <div className="bb-dock adh-footer__chat" />,
}))

import { AdhAppShell } from '../layout/AdhAppShell'
import { SLIDE_ATTR } from '@agentic-toolkit/adh/layout/SlideNavigation'
import { SiteHeader } from '../header/SiteHeader'
import { SiteFooter } from '../footer/SiteFooter'
import { REST_DOCK_SELECTOR } from '../footer/useFooterRestOffset'
import { THEME_AREAS } from '../theme-editor/areas'
import { adhStylesheet, styleRules } from './stylesheetRules'

const SLIDE = `:root[${SLIDE_ATTR}]`
const rules = styleRules(adhStylesheet('adh-site.css')).filter((r) => r.at.length === 0)

/** Every selector the sheet names an element by while a slide runs, with the name it gives. */
const naming = rules
  .filter((r) => r.properties.includes('view-transition-name') && r.selectors.every((s) => s.startsWith(SLIDE)))
  .flatMap((r) => r.selectors.map((selector) => ({ selector, name: r.get('view-transition-name') })))

/** The elements the sheet gives `name` to, on the page as it stands. */
const namedElements = (name: string): Element[] =>
  naming.filter((n) => n.name === name).flatMap((n) => Array.from(document.querySelectorAll(n.selector)))

/** What the sheet finally declares for `property` on exactly `selector`: the last rule wins. */
const declared = (selector: string, property: string): string =>
  rules.filter((r) => r.selectors.includes(selector) && r.properties.includes(property)).at(-1)?.get(property) ?? ''

/** The preview the theme editor shows for one of its items. */
function preview(itemId: string): ComponentType {
  const item = THEME_AREAS.flatMap((area) => area.items).find((i) => i.id === itemId)
  if (!item?.Preview) throw new Error(`the theme editor has no preview for ${itemId}`)
  return item.Preview
}

/** The Debug console with the theme editor on its chrome: opened from inside the page's tree,
 *  and portaled to <body>, as FloatingWindow does. */
function DebugConsole() {
  const HeaderPreview = preview('global.header-bar')
  const FooterPreview = preview('global.footer-bar')
  return createPortal(
    <div role="dialog" data-testid="debug-console">
      <HeaderPreview />
      <FooterPreview />
    </div>,
    document.body,
  )
}

/** A page as the shell lays it out, with the console open over it and a slide running. */
function renderSlidingPage() {
  render(
    <AdhAppShell header={<SiteHeader siteId="hub" />} footer={<SiteFooter />}>
      <p>page</p>
      <DebugConsole />
    </AdhAppShell>,
  )
  document.documentElement.setAttribute(SLIDE_ATTR, 'forward')
  const shell = document.querySelector('.adh-app-shell')!
  const own = (selector: string) => Array.from(shell.children).filter((el) => el.matches(selector))
  // The copies are there to be claimed: without them, a rule naming every header would pass.
  const console = document.querySelector('[data-testid="debug-console"]')!
  expect(console.querySelectorAll('.adh-header, .adh-footer'), 'the console shows no specimens').toHaveLength(2)
  return {
    header: own('.adh-header'),
    main: own('.adh-app-shell__main'),
    footer: own('.adh-footer'),
    dock: Array.from(document.querySelectorAll('.bb-dock')),
  }
}

afterEach(() => {
  cleanup()
  document.documentElement.removeAttribute(SLIDE_ATTR)
})

describe('a slide navigation', () => {
  it("names the page, the shell's header and footer, and bitbag's dock — each on one element", () => {
    const page = renderSlidingPage()
    for (const part of Object.values(page)) expect(part).toHaveLength(1)
    const names = [...new Set(naming.map((n) => n.name))].sort()
    expect(names).toEqual(['adh-dock', 'adh-footer', 'adh-header', 'adh-page'])
    // By identity, and only these: the specimen header and footer carry no name, so the
    // browser has one element per name and runs the transition.
    const got = (name: string) => namedElements(name)
    expect(got('adh-page')).toHaveLength(1)
    expect(got('adh-page')[0]).toBe(page.main[0])
    expect(got('adh-header')).toHaveLength(1)
    expect(got('adh-header')[0]).toBe(page.header[0])
    expect(got('adh-footer')).toHaveLength(1)
    expect(got('adh-footer')[0]).toBe(page.footer[0])
    expect(got('adh-dock')).toHaveLength(1)
    expect(got('adh-dock')[0]).toBe(page.dock[0])
  })

  it('finds the dock by the selector the resting offset finds it by', () => {
    // footerDock.test pins REST_DOCK_SELECTOR to bitbag's real dock; one spelling keeps this
    // rule on the element that test checks.
    expect(naming.filter((n) => n.name === 'adh-dock').map((n) => n.selector)).toEqual([
      `${SLIDE} ${REST_DOCK_SELECTOR}`,
    ])
  })

  it('names nothing while no slide runs — an ordinary navigation keeps the default', () => {
    renderSlidingPage()
    document.documentElement.removeAttribute(SLIDE_ATTR)
    expect(naming.flatMap((n) => Array.from(document.querySelectorAll(n.selector)))).toEqual([])
  })

  it('holds the named chrome still, with no old image under the live one', () => {
    // No animation on the group or the new image: the bar stays where it is, as it is. And no
    // old image: the dock is transparent around bitbag's face, so his old face under the new
    // one drew him twice wherever the two differed.
    for (const name of ['adh-header', 'adh-footer', 'adh-dock']) {
      expect(declared(`${SLIDE}::view-transition-group(${name})`, 'animation'), name).toBe('none')
      expect(declared(`${SLIDE}::view-transition-new(${name})`, 'animation'), name).toBe('none')
      expect(declared(`${SLIDE}::view-transition-old(${name})`, 'display'), name).toBe('none')
    }
  })
})
