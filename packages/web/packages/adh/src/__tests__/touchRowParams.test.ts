/**
 * The site's own menu rows grow on a touch screen through ui's ONE touch-row rule, and a
 * host feeds that rule by setting its PARAMETERS — never by setting `padding`.
 *
 * ui's components.css ("Touch rows") makes every tappable row 30% taller on a coarse
 * pointer: its base `.adh-dropdown-menu__item` rule reads the row's block padding from
 * `--adh-touch-row-pt` / `-pb`, and one `@media (pointer: coarse)` rule adds the growth to
 * them. A host rule that sets `padding` on a row beats that rule instead — the nav popover's
 * compact rows on specificity, the avatar menu's on order — and switches the growth off. So
 * both sheets here once carried their own copy of the formula, as rem literals frozen at a
 * hand-multiplied line height, which is exactly the drift ui's own Touch rows note retired
 * on its side. These tests hold the host side: no block padding on a menu row, no copy of
 * the factor, and the two compact paddings expressed as the parameters.
 *
 * jsdom evaluates no media query and computes no calc(), so no rendered row can show its
 * touch height here; what is held is the rule text that decides it.
 */
import { describe, expect, it } from 'vitest'

import {
  adhStylesheet,
  canonicalValue,
  styleRules,
  subjectClasses,
  subjectPseudoElement,
  uiStylesheet,
} from './stylesheetRules'

const SHEETS = ['adh-site.css', 'adh-components.css'] as const

/** Every class that marks a menu ROW in these sheets: ui's own item class, which every
 *  DropdownMenuItem, DropdownMenuLinkItem and DropdownMenuSubTrigger carries, and the host
 *  classes NavigationPopover.tsx and AvatarMenu.tsx put on those same elements — so a block
 *  padding on any of them lands on a row ui's coarse rule grows. */
const ROW_CLASSES = new Set([
  'adh-dropdown-menu__item',
  'adh-avatar-menu__item',
  'adh-nav-popover__topic',
  'adh-nav-popover__help-row',
  'adh-nav-popover__match',
  'adh-nav-popover__item--active',
  'adh-nav-popover__item--current',
  'adh-nav-popover__item--indent',
])

/** The block-axis padding spellings: any one of them on a row replaces the growth. */
const BLOCK_PADDING = [
  'padding',
  'padding-top',
  'padding-bottom',
  'padding-block',
  'padding-block-start',
  'padding-block-end',
]

/** Every rule in `sheet` with a selector whose subject is a menu row (the row itself, not a
 *  pseudo-element of it). */
function rowRules(sheet: string) {
  return styleRules(adhStylesheet(sheet)).filter((rule) =>
    rule.selectors.some(
      (selector) =>
        !subjectPseudoElement(selector) && subjectClasses(selector).some((name) => ROW_CLASSES.has(name)),
    ),
  )
}

function describeRule(sheet: string, rule: { at: string[]; selectors: string[] }): string {
  return `${sheet}: ${rule.at.map((at) => `@${at} `).join('')}${rule.selectors.join(', ')}`
}

describe('menu rows feed ui\'s touch-row rule its parameters', () => {
  it('finds the row rules it guards (a renamed class must not leave nothing to check)', () => {
    for (const sheet of SHEETS) expect(rowRules(sheet).length, sheet).toBeGreaterThan(0)
  })

  it('no rule on a menu row sets block padding', () => {
    const offenders = SHEETS.flatMap((sheet) =>
      rowRules(sheet)
        .filter((rule) => rule.properties.some((property) => BLOCK_PADDING.includes(property)))
        .map(
          (rule) =>
            `${describeRule(sheet, rule)} { ${rule.properties
              .filter((property) => BLOCK_PADDING.includes(property))
              .join(', ')} }`,
        ),
    )
    expect(offenders).toEqual([])
  })

  it('neither sheet reads or restates the growth factor — ui writes it once, on :root', () => {
    const copies = SHEETS.flatMap((sheet) =>
      styleRules(adhStylesheet(sheet)).flatMap((rule) =>
        rule.properties
          .filter(
            (property) =>
              property === '--adh-touch-row-grow' || rule.get(property).includes('--adh-touch-row-grow'),
          )
          .map((property) => `${describeRule(sheet, rule)} { ${property}: ${rule.get(property)} }`),
      ),
    )
    expect(copies).toEqual([])
  })

  it('the nav popover\'s compact rows set 0.35rem as the parameters', () => {
    const [nav, ...more] = styleRules(adhStylesheet('adh-site.css')).filter(
      (rule) =>
        rule.at.length === 0 &&
        rule.selectors.join(', ') ===
          '.adh-nav-popover__list .adh-dropdown-menu__item, .adh-nav-popover__submenu .adh-dropdown-menu__item',
    )
    expect(more).toEqual([])
    expect(nav?.get('--adh-touch-row-pt')).toBe('0.35rem')
    expect(nav?.get('--adh-touch-row-pb')).toBe('0.35rem')
  })

  it('the avatar menu\'s rows set 0.55rem as the parameters', () => {
    const [avatar, ...more] = styleRules(adhStylesheet('adh-components.css')).filter(
      (rule) => rule.at.length === 0 && rule.selectors.join(', ') === '.adh-avatar-menu__item',
    )
    expect(more).toEqual([])
    expect(avatar?.get('--adh-touch-row-pt')).toBe('0.55rem')
    expect(avatar?.get('--adh-touch-row-pb')).toBe('0.55rem')
  })

  // What the parameters above are worth depends on ui reading them. If ui's item ever took
  // its padding back as a literal, the host values would silently style nothing — and the
  // avatar rows, which no longer set their own inline padding, would lose ui's 0.75rem too.
  it('ui\'s item reads them for its padding, and its coarse rule grows them', () => {
    const ui = styleRules(uiStylesheet('components.css'))
    const [base, ...moreBase] = ui.filter(
      (rule) => rule.at.length === 0 && rule.selectors.join(', ') === '.adh-dropdown-menu__item',
    )
    expect(moreBase).toEqual([])
    expect(base?.get('padding')).toBe(canonicalValue('var(--adh-touch-row-pt) 0.75rem var(--adh-touch-row-pb)'))

    const [coarse, ...moreCoarse] = ui.filter(
      (rule) =>
        rule.at.join(' ') === '(pointer: coarse)' && rule.selectors.includes('.adh-dropdown-menu__item'),
    )
    expect(moreCoarse).toEqual([])
    expect(coarse?.get('padding-top')).toBe(canonicalValue('calc(var(--adh-touch-row-pt) + var(--adh-touch-row-extra))'))
    expect(coarse?.get('padding-bottom')).toBe(
      canonicalValue('calc(var(--adh-touch-row-pb) + var(--adh-touch-row-extra))'),
    )
    expect(coarse?.get('--adh-touch-row-extra')).toContain('var(--adh-touch-row-grow)')
  })
})
