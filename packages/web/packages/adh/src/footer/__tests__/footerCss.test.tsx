/**
 * The footer's two worlds, read off the stylesheets that make them.
 *
 * What the bar shows is decided by CSS this package's other footer tests cannot see: vitest
 * hands a CSS import back empty, and jsdom applies no author stylesheet. Where the Popover API
 * exists the bar is two menus, the copyright's and Legal's, and their plain forms are hidden;
 * where it does not (iOS before 17, Firefox before 125) an `@supports` block hides every menu
 * and shows the plain forms instead. So this file parses the real sheets (stylesheetRules.ts),
 * takes from them what each world hides, and asks the REAL rendered footer what a visitor in
 * each world can see and reach.
 *
 * The model is the sheets' own selectors, so a rule that stops matching the markup changes the
 * answer here instead of going stale in silence. That is how the no-popover block came to name
 * a Sites trigger that no longer existed, while the copyright menu, which it did not name,
 * stayed on screen as a button that opened nothing.
 */
import { describe, expect, it, vi } from 'vitest'
import { render } from '@testing-library/react'
import { SiteFooter } from '../SiteFooter'
import {
  REST_DOCK_SELECTOR,
  REST_OFFSET_VAR,
  REST_SLOT_SELECTOR,
} from '../useFooterRestOffset'
import {
  adhStylesheet,
  bitbagStylesheet,
  canonicalValue,
  styleRules,
} from '../../__tests__/stylesheetRules'

// A plain anchor: next/link's own needs an app router this file has no use for.
vi.mock('next/link', () => ({
  default: ({ href, prefetch: _prefetch, ...rest }: { href: string; prefetch?: boolean }) => (
    <a href={href} {...rest} />
  ),
}))

// bitbag stands down to nothing. The footer keeps his slot only while it mounts him, so these
// renders mount "him", but what he renders is his own tests' business (footerDock.test.tsx).
vi.mock('../FooterChat', () => ({ FooterChat: () => null }))

/** A build identity, so the version the plain copyright line carries is there to be found. */
const LIVE = { version: '1.0.155', sha: 'a73e79b7c0ffee00deadbeef1234567890abcdef' }

const site = styleRules(adhStylesheet('adh-site.css'))
const components = styleRules(adhStylesheet('adh-components.css'))

/** The block that swaps the menus for their plain forms where popovers are missing. */
const NO_POPOVERS = 'not selector(:popover-open)'
const switchBlock = site.filter(
  (r) => r.at.length === 1 && canonicalValue(r.at[0]!) === NO_POPOVERS,
)
/** What the block hides: every popover and every trigger for one. */
const HIDDEN_WITHOUT_POPOVERS = switchBlock
  .filter((r) => r.get('display') === 'none')
  .flatMap((r) => r.selectors)
/** What it brings back: the plain forms, which are hidden everywhere else. */
const PLAIN_FORMS = switchBlock.filter((r) => r.get('display') === 'revert').flatMap((r) => r.selectors)

type World = 'popovers' | 'no popovers'

const matchesAny = (el: Element, selectors: string[]): boolean => selectors.some((s) => el.matches(s))

/** Whether `el` gets a box in `world`, as far as the popover switch decides it. */
function shown(el: Element, world: World): boolean {
  for (let n: Element | null = el; n; n = n.parentElement) {
    if (world === 'popovers') {
      // Every panel here is closed, and the UA hides a closed popover and all it holds.
      if (n.hasAttribute('popover')) return false
      if (matchesAny(n, PLAIN_FORMS)) return false
    } else if (matchesAny(n, HIDDEN_WITHOUT_POPOVERS)) return false
  }
  return true
}

const text = (el: Element): string => (el.textContent ?? '').replace(/\s+/g, ' ').trim()

/** Every control under `root` that `world` shows: `label (button)`, or `label → href`. */
function reachable(root: Element, world: World): string[] {
  return Array.from(root.querySelectorAll('a[href], button'))
    .filter((el) => shown(el, world))
    .map((el) => (el.tagName === 'A' ? `${text(el)} → ${el.getAttribute('href')}` : `${text(el)} (button)`))
}

/** The text under `root` that `world` shows. */
function visibleText(root: Element, world: World): string {
  const walker = root.ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  let out = ''
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (shown(n.parentElement!, world)) out += n.textContent
  }
  return out.replace(/\s+/g, ' ').trim()
}

/** The bar items `world` lays out that keep bitbag's slot, by the label they show. */
function slotHosts(root: Element, world: World): string[] {
  return Array.from(root.querySelectorAll(REST_SLOT_SELECTOR))
    .filter((el) => shown(el, world))
    .map((el) => text(el.querySelector('.adh-footer__menu-trigger') ?? el))
}

function renderFooter() {
  const { container } = render(<SiteFooter live={LIVE} />)
  return {
    container,
    copyright: container.querySelector('.adh-footer__copyright')!,
    nav: container.querySelector('.adh-footer__links')!,
  }
}

describe('the popover switch itself', () => {
  it('hides the plain forms outside its block, with an earlier and equally specific rule it reverts', () => {
    expect(HIDDEN_WITHOUT_POPOVERS.length, `no \`@supports ${NO_POPOVERS}\` hiding rule in adh-site.css`).toBeGreaterThan(0)
    expect(PLAIN_FORMS.length, 'no `display: revert` rule in that block').toBeGreaterThan(0)
    // The same selectors, so the same specificity, and earlier in the sheet: that is what
    // lets the block's `revert` win where it applies and lose everywhere else.
    const hideEverywhere = site.findIndex(
      (r) =>
        r.at.length === 0 &&
        r.get('display') === 'none' &&
        [...r.selectors].sort().join() === [...PLAIN_FORMS].sort().join(),
    )
    expect(hideEverywhere, 'the plain forms are not hidden outside the @supports block').toBeGreaterThan(-1)
    const revert = site.findIndex((r) => switchBlock.includes(r) && r.get('display') === 'revert')
    expect(revert).toBeGreaterThan(hideEverywhere)
  })

  it('names only what the footer renders', () => {
    // A selector for markup that is gone hides nothing, and says it does. The block named a
    // `.adh-footer__sites-trigger` for as long as Sites had been in the copyright menu.
    renderFooter()
    const stale = switchBlock
      .flatMap((r) => r.selectors)
      .filter((selector) => document.querySelector(selector) === null)
    expect(stale).toEqual([])
  })
})

describe('a browser without the Popover API', () => {
  it('shows no popover, and no trigger for one', () => {
    // A trigger there is a button that opens nothing, and a popover is a panel dumped inline.
    const { container } = renderFooter()
    const popoverParts = Array.from(container.querySelectorAll('[popover], [popovertarget]'))
    expect(popoverParts.length).toBeGreaterThan(0)
    expect(popoverParts.filter((el) => shown(el, 'no popovers')).map((el) => el.outerHTML)).toEqual([])
  })

  it('still reaches the studio, this build, Terms and Privacy, as plain links and text', () => {
    // The copyright menu's About had taken over the studio's link and the version the bar used
    // to carry, so a dead menu left both with no way onto the screen at all.
    const { copyright, nav } = renderFooter()
    expect(reachable(copyright, 'no popovers')).toEqual([
      'Agentic Development Studio → https://agenticdevelopmentstudio.com/',
    ])
    expect(visibleText(copyright, 'no popovers')).toBe(
      '© 2026 Agentic Development Studio · v1.0.155 · a73e79b7',
    )
    expect(reachable(nav, 'no popovers')).toEqual(['Terms → /terms', 'Privacy → /privacy'])
  })

  it("keeps bitbag's slot beside Terms, the item that holds the corner in Legal's place", () => {
    // The slot was Legal's margin alone, and Legal is hidden here: the fallback bar had no
    // slot, and the offset measured off a hidden Legal put his face off the screen.
    const { container } = renderFooter()
    expect(slotHosts(container, 'no popovers')).toEqual(['Terms'])
  })
})

describe('a browser with the Popover API', () => {
  it('shows the two menus and none of their plain forms', () => {
    const { container, copyright, nav } = renderFooter()
    expect(reachable(copyright, 'popovers')).toEqual(['© 2026 Agentic Development Studio (button)'])
    expect(visibleText(copyright, 'popovers')).toBe('© 2026 Agentic Development Studio')
    expect(reachable(nav, 'popovers')).toEqual(['Legal (button)'])
    expect(slotHosts(container, 'popovers')).toEqual(['Legal'])
  })

  it('shows the brand the theme editor reads, which is the first one in the footer', () => {
    // theme-editor/areas.tsx reads the brand's current styling off the first
    // `.adh-footer__brand-link`; were that the hidden plain line's, it would read nothing real.
    const { container } = renderFooter()
    expect(shown(container.querySelector('.adh-footer__brand-link')!, 'popovers')).toBe(true)
  })
})

describe("bitbag's resting place", () => {
  it('is kept as the left margin of the slot host, only while the bar mounts him', () => {
    const slot = site.filter((r) => r.at.length === 0 && r.selectors.includes(REST_SLOT_SELECTOR))
    expect(slot.map((r) => r.get('margin-left'))).toEqual(['var(--adh-footer-rest-slot)'])
  })

  it("reaches him through the hooks bitbag's resting rule reads, never by restating its selectors", () => {
    const bitbag = styleRules(bitbagStylesheet('bitbag-dock.css'))
    const resting = bitbag.filter((r) =>
      r.selectors.includes('.bb-dock--resting .bb-dock__avatar'),
    )
    expect(resting, 'bitbag-dock.css has no `.bb-dock--resting .bb-dock__avatar` rule').toHaveLength(1)
    // Neutral fallbacks: a host that sets nothing gets bitbag's own resting place.
    expect(resting[0]!.get('transform')).toContain('var(--bb-dock-rest-x,0px)')
    expect(resting[0]!.get('margin-bottom')).toContain('var(--bb-dock-rest-lift,0px)')

    // Exactly the hooks he reads, on the element the offset is written on.
    const read = new Set(
      bitbag.flatMap((r) =>
        r.properties.flatMap((p) =>
          Array.from(r.get(p).matchAll(/var\((--bb-dock-rest-[\w-]+)/g), (m) => m[1]!),
        ),
      ),
    )
    const dock = site.filter(
      (r) => r.at.length === 0 && r.selectors.length === 1 && r.selectors[0] === REST_DOCK_SELECTOR,
    )
    const set = dock.flatMap((r) => r.properties.filter((p) => p.startsWith('--bb-dock-rest-')))
    expect(set.sort()).toEqual([...read].sort())
    expect(dock.map((r) => r.get('--bb-dock-rest-x')).join()).toContain(`var(${REST_OFFSET_VAR}`)

    // adh used to restate both of bitbag's resting selectors one class stronger, to win when
    // bitbag's sheet landed later; that held only while the two copies stayed in step, and
    // nothing checked that they did. A `:not(.bb-dock--resting)` is not a restatement: it
    // keeps a rule OFF the resting dock (adh-site.css's engaged lift, which a resting dock
    // must never get) and styles nothing bitbag's resting rules style, so negations are
    // taken out before the match.
    const restated = [...site, ...components]
      .flatMap((r) => r.selectors)
      .filter((s) => s.replace(/:not\([^()]*\)/g, '').includes('bb-dock--resting'))
    expect(restated).toEqual([])
  })
})

describe('footer menus', () => {
  it("keep each menu's anchor inside its own host", () => {
    // The theme editor shows a second footer beside the page's own, and an anchor name that
    // two carets declare resolves to the LAST one: the page's menus opened at the specimen's
    // carets. Scoped to the host that holds both the caret and its panel, a panel can only
    // ever see its own caret, whatever the ids.
    const host = components.filter((r) => r.at.length === 0 && r.selectors.includes('.adh-footer__menu-host'))
    expect(host.map((r) => r.get('anchor-scope'))).toContain('all')
  })
})
