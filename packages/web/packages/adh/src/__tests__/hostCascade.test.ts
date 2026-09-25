/**
 * Every place adh's sheets restyle an element that ui's or bitbag's sheet also styles, and
 * how the host's rule wins there — one named row per contest.
 *
 * An override that stops winning is not an error anywhere. The page just ships the package's
 * value: the nav popover's section headings at menu-row size, say, if their rule were a lone
 * class that tied ui's label rule and ui's sheet ever came later. So each contest is a row
 * here, in one of three tables:
 *
 * - WEIGHT: the host's selector is strictly more specific, so load order cannot matter. It
 *   is the only way to beat bitbag. Bitbag's sheets ride the lazily loaded chat chunk (see
 *   adh-site.css's note on it), so they land AFTER adh's and win every tie.
 * - ORDER: equal weight, won because ui's sheet is always read first. adh-components.css
 *   imports it ahead of its own rules, and adh-site.css imports adh-components.css ahead of
 *   its own. The first test below pins that order, because every ORDER row depends on it.
 * - PACKAGE: the package's rule is heavier and wins on purpose. Each row says why.
 *
 * Specificity is taken pessimistically. lightningcss, which the hub's CSS build runs, can
 * fold a selector list that holds a `:has()` into one `:is(…)` (1.32 does), and `:is()`
 * weighs every selector in it as the heaviest one. So the host counts at its lightest
 * selector that meets the package's rule, and the package at its heaviest selector.
 *
 * The rows are checked against what the sheets hold. Every host rule is paired with every
 * package rule whose subject can be the same element (by class, through the DOM facts in
 * COHABITANTS) and that sets any of the same properties. The pairs found must be the rows
 * named, so a contest that is added, removed or reshaped fails here until a row says how it
 * is won.
 */
import { readFileSync, realpathSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  adhStylesheet,
  bitbagStylesheet,
  cascadeOrder,
  compareSpecificity,
  maxSpecificity,
  type Specificity,
  specificity,
  type StyleRule,
  styleRules,
  subjectAttributes,
  subjectClasses,
  subjectCompound,
  subjectPseudoElement,
  uiStylesheet,
} from './stylesheetRules'

const SHEETS = {
  site: () => adhStylesheet('adh-site.css'),
  components: () => adhStylesheet('adh-components.css'),
  ui: () => uiStylesheet('components.css'),
  bitbag: () => bitbagStylesheet('bitbag-dock.css'),
}
type Sheet = keyof typeof SHEETS
const HOSTS: Sheet[] = ['site', 'components']
const PACKAGES: Sheet[] = ['ui', 'bitbag']

const parsed = new Map<Sheet, StyleRule[]>()
/** A sheet's rules, parsed on first use, inside a test, so a sheet that fails to parse fails
 *  that test instead of the whole file. */
function rulesOf(sheet: Sheet): StyleRule[] {
  let rules = parsed.get(sheet)
  if (!rules) parsed.set(sheet, (rules = styleRules(SHEETS[sheet]())))
  return rules
}

/** How a row names a rule: its selector list as the sheet writes it, after the conditions of
 *  any at-rules it sits in (`@(pointer: coarse) .adh-touch-row, …`). */
function ruleKey(rule: StyleRule): string {
  return [...rule.at.map((condition) => `@${condition}`), rule.selectors.join(', ')].join(' ')
}

/** The one rule a row names (`site .adh-nav-popover__menu`). Throws when there is not exactly
 *  one, so a rule that is deleted or reworded fails its row loudly. */
function rule(ref: string): StyleRule {
  const space = ref.indexOf(' ')
  const sheet = ref.slice(0, space) as Sheet
  const key = ref.slice(space + 1)
  const found = rulesOf(sheet).filter((r) => ruleKey(r) === key)
  if (found.length !== 1) throw new Error(`${sheet} has ${found.length} rules \`${key}\`; a row names exactly one`)
  return found[0]!
}

// ── Properties ─────────────────────────────────────────────────────────────────────────────

/** What each shorthand the four sheets declare sets, one level down. A sub-property that is a
 *  shorthand itself is expanded in turn. The sites are horizontal and left-to-right, so an
 *  inline-axis shorthand sets left and right. */
const SHORTHANDS: Record<string, readonly string[]> = {
  animation: [
    'animation-name',
    'animation-duration',
    'animation-timing-function',
    'animation-delay',
    'animation-iteration-count',
    'animation-direction',
    'animation-fill-mode',
    'animation-play-state',
    'animation-timeline',
  ],
  background: [
    'background-image',
    'background-position',
    'background-size',
    'background-repeat',
    'background-origin',
    'background-clip',
    'background-attachment',
    'background-color',
  ],
  'background-position': ['background-position-x', 'background-position-y'],
  border: [
    'border-top',
    'border-right',
    'border-bottom',
    'border-left',
    'border-width',
    'border-style',
    'border-color',
    'border-image',
  ],
  ...Object.fromEntries(
    ['top', 'right', 'bottom', 'left'].map((side) => [
      `border-${side}`,
      [`border-${side}-width`, `border-${side}-style`, `border-${side}-color`],
    ]),
  ),
  ...Object.fromEntries(
    ['width', 'style', 'color'].map((aspect) => [
      `border-${aspect}`,
      ['top', 'right', 'bottom', 'left'].map((side) => `border-${side}-${aspect}`),
    ]),
  ),
  'border-image': [
    'border-image-source',
    'border-image-slice',
    'border-image-width',
    'border-image-outset',
    'border-image-repeat',
  ],
  'border-radius': [
    'border-top-left-radius',
    'border-top-right-radius',
    'border-bottom-right-radius',
    'border-bottom-left-radius',
  ],
  flex: ['flex-grow', 'flex-shrink', 'flex-basis'],
  font: ['font-style', 'font-variant', 'font-weight', 'font-stretch', 'font-size', 'line-height', 'font-family'],
  'font-variant': [
    'font-variant-caps',
    'font-variant-ligatures',
    'font-variant-numeric',
    'font-variant-east-asian',
    'font-variant-alternates',
    'font-variant-position',
    'font-variant-emoji',
  ],
  gap: ['row-gap', 'column-gap'],
  // Added for the header's 3-column grid (G47, Mike, 2026-09-25) — the header sheet is now
  // the first of the four to place an item with `grid-column` rather than flex order/gap.
  'grid-column': ['grid-column-start', 'grid-column-end'],
  inset: ['top', 'right', 'bottom', 'left'],
  'list-style': ['list-style-position', 'list-style-image', 'list-style-type'],
  margin: ['margin-top', 'margin-right', 'margin-bottom', 'margin-left'],
  'margin-inline': ['margin-left', 'margin-right'],
  outline: ['outline-color', 'outline-style', 'outline-width'],
  overflow: ['overflow-x', 'overflow-y'],
  padding: ['padding-top', 'padding-right', 'padding-bottom', 'padding-left'],
  'place-items': ['align-items', 'justify-items'],
  'text-decoration': [
    'text-decoration-line',
    'text-decoration-style',
    'text-decoration-color',
    'text-decoration-thickness',
  ],
  transition: [
    'transition-property',
    'transition-duration',
    'transition-timing-function',
    'transition-delay',
    'transition-behavior',
  ],
  'white-space': ['white-space-collapse', 'text-wrap-mode'],
}

/** Every shorthand property the browsers ship. A sheet that starts declaring one SHORTHANDS
 *  has no entry for fails the first test, instead of hiding a contest behind a name nothing
 *  expands. */
const CSS_SHORTHANDS = new Set(
  `all animation animation-range background background-position border border-block
   border-block-color border-block-end border-block-start border-block-style border-block-width
   border-bottom border-color border-image border-inline border-inline-color border-inline-end
   border-inline-start border-inline-style border-inline-width border-left border-radius
   border-right border-style border-top border-width column-rule columns contain-intrinsic-size
   container flex flex-flow font font-synthesis font-variant gap grid grid-area grid-column
   grid-gap grid-row grid-template inset inset-block inset-inline list-style margin margin-block
   margin-inline mask mask-border offset outline overflow overscroll-behavior padding
   padding-block padding-inline place-content place-items place-self position-try scroll-margin
   scroll-margin-block scroll-margin-inline scroll-padding scroll-padding-block
   scroll-padding-inline scroll-timeline text-box text-decoration text-emphasis text-wrap
   transition view-timeline white-space -webkit-text-stroke`.split(/\s+/),
)

/** The longhands a property sets: itself, unless it is a shorthand. */
function leaves(property: string): Set<string> {
  const parts = SHORTHANDS[property]
  return new Set(parts ? parts.flatMap((part) => [...leaves(part)]) : [property])
}

/** The properties a rule declares, less those another of them already covers. jsdom lists a
 *  shorthand's longhands beside it (`padding-top` … and `padding`), and the rule wrote only
 *  the shorthand. */
function declared(properties: string[]): string[] {
  const sets = new Map(properties.map((property) => [property, leaves(property)]))
  const covers = (big: Set<string>, small: Set<string>) =>
    big.size > small.size && [...small].every((leaf) => big.has(leaf))
  return properties.filter((p) => !properties.some((q) => covers(sets.get(q)!, sets.get(p)!)))
}

function overlaps(a: string, b: string): boolean {
  const theirs = leaves(b)
  return [...leaves(a)].some((leaf) => theirs.has(leaf))
}

// ── Elements ───────────────────────────────────────────────────────────────────────────────

const NAV = 'header/NavigationPopover.tsx'
const AVATAR = 'header/AvatarMenu.tsx'
const ITEM = 'adh-dropdown-menu__item'
const SUB_TRIGGER = 'adh-dropdown-menu__sub-trigger'
const CONTENT = 'adh-dropdown-menu__content'

/** The DOM facts the sheets cannot show: which package classes share an element with a host
 *  class. A host class goes on the element a package component renders (`className` on ui's
 *  `DropdownMenuContent` lands beside `adh-dropdown-menu__content`), or on a raw element of
 *  adh's that spells the package class itself. `on` maps each tag that carries the host class
 *  in `source` (under src/) to the package classes that element has. */
const COHABITANTS: Record<string, { source: string; on: Record<string, string[]> }> = {
  'adh-nav-popover__menu': { source: NAV, on: { DropdownMenuContent: [CONTENT] } },
  'adh-nav-popover__submenu': { source: NAV, on: { DropdownMenuSubContent: [CONTENT] } },
  'adh-nav-popover__section-label': { source: NAV, on: { DropdownMenuLabel: ['adh-dropdown-menu__label'] } },
  'adh-nav-popover__topic': { source: NAV, on: { DropdownMenuSubTrigger: [ITEM, SUB_TRIGGER] } },
  'adh-nav-popover__help-row': { source: NAV, on: { button: [ITEM] } },
  'adh-nav-popover__match': { source: NAV, on: { a: [ITEM] } },
  'adh-nav-popover__item--active': {
    source: NAV,
    on: { DropdownMenuSubTrigger: [ITEM, SUB_TRIGGER], a: [ITEM], button: [ITEM] },
  },
  'adh-nav-popover__item--current': { source: NAV, on: { DropdownMenuSubTrigger: [ITEM, SUB_TRIGGER], a: [ITEM] } },
  'adh-nav-popover__item--indent': { source: NAV, on: { DropdownMenuSubTrigger: [ITEM, SUB_TRIGGER], a: [ITEM] } },
  'adh-nav-popover__icon': { source: NAV, on: { Icon: ['adh-dropdown-menu__item-icon'] } },
  'adh-avatar-menu': { source: AVATAR, on: { DropdownMenuContent: [CONTENT] } },
  'adh-avatar-menu__item': { source: AVATAR, on: { DropdownMenuItem: [ITEM], DropdownMenuLinkItem: [ITEM] } },
  'adh-avatar-menu-trigger__avatar': { source: AVATAR, on: { Avatar: ['adh-avatar'] } },
  'adh-footer__chat': {
    source: 'footer/FooterChatInner.tsx',
    on: { BitbagDock: ['bb-dock', 'bb-dock--rest-avatar', 'bb-dock--resting'] },
  },
}

/** Selectors whose subject names no class, attribute or root, so nothing here can say which
 *  elements they reach. Each is named with what it styles, and why no package rule is there. */
const UNKEYED: Record<string, string> = {
  'site .adh-modal__body--legal .adh-legal-doc h2': 'Headings of the legal text. They carry no class of ui or bitbag.',
  'site .adh-modal__body--legal .adh-legal-doc h3': 'Headings of the legal text. They carry no class of ui or bitbag.',
  'site .adh-about__build dd': "A value in About's build list, a plain <dl> of adh's own.",
  'components .adh-header__icon-button > svg':
    "The glyph in one of the header's own icon buttons. ui's one rule on a bare svg is ColorModeToggle's, and adh does not render ColorModeToggle.",
  'components .adh-header__lead .adh-nav-popover__trigger > span': "The label inside adh's own nav trigger.",
  'components .adh-home__toolbar > *':
    "The home toolbar's children. The only package rule that sets min-width is ui's menu content, which is portaled to the body and is never a child here.",
  'ui .adh-color-mode-toggle > svg': "ColorModeToggle's glyph. adh does not render ColorModeToggle.",
}

const ROOT = /^html(?![\w-])|:root(?![\w-])/i

/** What a host selector's subject can be: its classes and every package class COHABITANTS
 *  puts beside them, its attributes, and the root. */
function hostKeys(selector: string): string[] {
  const keys = new Set<string>()
  for (const cls of subjectClasses(selector)) {
    keys.add(`.${cls}`)
    for (const shared of Object.values(COHABITANTS[cls]?.on ?? {}).flat()) keys.add(`.${shared}`)
  }
  for (const attribute of subjectAttributes(selector)) keys.add(`[${attribute}]`)
  if (ROOT.test(subjectCompound(selector))) keys.add(':root')
  return [...keys]
}

/** What a package selector's subject is: its classes when it names any. An attribute beside a
 *  class is a state of that element (`[data-highlighted]`), not what it is, so attributes and
 *  the root count only for a subject with no class, like `:where([data-htd-row])`. */
function packageKeys(selector: string): string[] {
  const classes = subjectClasses(selector).map((cls) => `.${cls}`)
  if (classes.length) return classes
  const keys = subjectAttributes(selector).map((attribute) => `[${attribute}]`)
  if (ROOT.test(subjectCompound(selector))) keys.push(':root')
  return keys
}

/** Whether a host selector and a package selector can style the same box. */
function meets(host: string, pkg: string): boolean {
  if (subjectPseudoElement(host) !== subjectPseudoElement(pkg)) return false
  const keys = new Set(hostKeys(host))
  return packageKeys(pkg).some((key) => keys.has(key))
}

// ── Contests ───────────────────────────────────────────────────────────────────────────────

type Row = { host: string; pkg: string; properties: string[] }

/** Every contest the sheets hold, and every selector nothing can key. */
function discover(): { rows: Row[]; unkeyed: string[] } {
  const rows: Row[] = []
  const unkeyed = new Set<string>()
  for (const sheet of HOSTS)
    for (const r of rulesOf(sheet))
      for (const s of r.selectors) if (!hostKeys(s).length) unkeyed.add(`${sheet} ${s}`)
  for (const sheet of PACKAGES)
    for (const r of rulesOf(sheet))
      for (const s of r.selectors) if (!packageKeys(s).length) unkeyed.add(`${sheet} ${s}`)
  for (const hostSheet of HOSTS) {
    for (const host of rulesOf(hostSheet)) {
      const own = declared(host.properties)
      for (const pkgSheet of PACKAGES) {
        for (const pkg of rulesOf(pkgSheet)) {
          if (!host.selectors.some((h) => pkg.selectors.some((p) => meets(h, p)))) continue
          const properties = own.filter((property) => pkg.properties.some((theirs) => overlaps(property, theirs)))
          if (properties.length)
            rows.push({ host: `${hostSheet} ${ruleKey(host)}`, pkg: `${pkgSheet} ${ruleKey(pkg)}`, properties })
        }
      }
    }
  }
  return { rows, unkeyed: [...unkeyed] }
}

/** A row as one line, so a mismatch reads as the contests added and lost. */
function line({ host, pkg, properties }: Row): string {
  return `${host}  ×  ${pkg}  [${[...properties].sort().join(', ')}]`
}

/** Each row beside its {@link line}, for a test table titled by `%s`. */
function named<R extends Row>(rows: R[]): [string, R][] {
  return rows.map((row) => [line(row), row])
}

/** The least specific of `selectors`, which must not be empty: a row whose two rules no
 *  longer meet is not a contest, and says so. */
function lightest(selectors: string[], row: Row): Specificity {
  if (!selectors.length) throw new Error(`no selector of ${row.host} meets ${row.pkg}`)
  return selectors.map(specificity).reduce((low, s) => (compareSpecificity(s, low) < 0 ? s : low))
}

/** The host rule's lightest selector that meets the package rule, and the package rule's
 *  heaviest: the pessimistic weights of a contest the host must win. */
function hostMustWin(row: Row): { host: Specificity; pkg: Specificity } {
  const h = rule(row.host)
  const p = rule(row.pkg)
  return {
    host: lightest(
      h.selectors.filter((s) => p.selectors.some((t) => meets(s, t))),
      row,
    ),
    pkg: maxSpecificity(p.selectors),
  }
}

const WEIGHT: Row[] = [
  {
    host: 'site .adh-dropdown-menu__label.adh-nav-popover__section-label',
    pkg: 'ui .adh-dropdown-menu__label',
    properties: ['padding', 'font-size', 'font-weight', 'color'],
  },
  {
    host: 'site .bb-dock.adh-footer__chat:not(.bb-dock--resting):has(.persona-chat:not(.pc-collapsed))',
    pkg: 'bitbag .bb-dock',
    properties: ['z-index'],
  },
  {
    host: 'site .adh-nav-popover__list .adh-dropdown-menu__item, .adh-nav-popover__submenu .adh-dropdown-menu__item',
    pkg: 'ui :where(.adh-dropdown-menu__item)',
    properties: ['--adh-touch-row-pt', '--adh-touch-row-pb'],
  },
  {
    host: 'site .adh-nav-popover__list .adh-nav-popover__topic, .adh-nav-popover__list > a.adh-dropdown-menu__item, .adh-nav-popover__submenu .adh-dropdown-menu__item',
    pkg: 'ui .adh-dropdown-menu__item',
    properties: ['font-size', 'line-height'],
  },
  {
    host: 'site .adh-nav-popover__list .adh-nav-popover__item--indent',
    pkg: 'ui .adh-dropdown-menu__item',
    properties: ['padding-left'],
  },
  {
    host: 'site .adh-nav-popover__list .adh-dropdown-menu__separator',
    pkg: 'ui .adh-dropdown-menu__separator',
    properties: ['margin-left', 'margin-right'],
  },
  {
    host: 'components .adh-avatar-menu__item',
    pkg: 'ui :where(.adh-dropdown-menu__item)',
    properties: ['--adh-touch-row-pt', '--adh-touch-row-pb'],
  },
]

/** Ties the host wins because ui's sheet precedes it. Only ui can be on the other side: a
 *  tie with bitbag goes to bitbag. */
const ORDER: Row[] = [
  {
    host: 'site .adh-nav-popover__menu',
    pkg: 'ui .adh-dropdown-menu__content',
    properties: ['min-width', 'padding-top'],
  },
  {
    host: 'site .adh-nav-popover__submenu',
    pkg: 'ui .adh-dropdown-menu__content',
    properties: ['min-width', 'overflow-x', 'overflow-y'],
  },
  { host: 'site .adh-nav-popover__topic', pkg: 'ui .adh-dropdown-menu__item', properties: ['cursor', 'font'] },
  { host: 'site .adh-nav-popover__help-row', pkg: 'ui .adh-dropdown-menu__item', properties: ['cursor', 'font'] },
  { host: 'site .adh-nav-popover__match', pkg: 'ui .adh-dropdown-menu__item', properties: ['gap'] },
  {
    host: 'components .adh-avatar-menu-trigger__avatar',
    pkg: 'ui .adh-avatar',
    properties: ['height', 'width'],
  },
  {
    host: 'components .adh-avatar-menu',
    pkg: 'ui .adh-dropdown-menu__content',
    properties: ['min-width', 'border-radius', 'background', 'border', 'padding', 'color', 'box-shadow'],
  },
  {
    host: 'components .adh-avatar-menu__item',
    pkg: 'ui .adh-dropdown-menu__item',
    properties: ['display', 'align-items', 'gap', 'font-size', 'line-height', 'border-radius', 'cursor', 'outline'],
  },
  {
    host: 'components .adh-avatar-menu__item:hover, .adh-avatar-menu__item:focus, .adh-avatar-menu__item[data-highlighted]',
    pkg: 'ui .adh-dropdown-menu__item[data-highlighted], .adh-dropdown-menu__item:focus',
    properties: ['background'],
  },
]

const HIGHLIGHT = 'ui .adh-dropdown-menu__item[data-highlighted], .adh-dropdown-menu__item:focus'

/** Contests the package's rule wins on purpose. `same` rows paint what the host would. */
const PACKAGE: (Row & { same: boolean; why: string })[] = [
  {
    host: 'site .adh-nav-popover__item--active',
    pkg: HIGHLIGHT,
    properties: ['background'],
    same: true,
    why: 'The row the keys or the search made active looks exactly like the row under the pointer.',
  },
  {
    host: 'site .adh-nav-popover__item--active',
    pkg: 'ui .adh-dropdown-menu__sub-trigger[data-popup-open]',
    properties: ['background'],
    same: true,
    why: 'A topic whose submenu is open looks like an active row, whichever rule paints it.',
  },
  {
    host: 'site .adh-nav-popover__help-row',
    pkg: HIGHLIGHT,
    properties: ['background'],
    same: false,
    why: "`transparent` only clears the native <button>'s fill. The highlight is meant to show on it as on any row.",
  },
]

const fmt = (s: Specificity) => `(${s.join(',')})`

describe('host rules against the package rules they restyle', () => {
  it("reads ui's sheet once, before any host rule", () => {
    // A tie goes to the later rule, so ORDER's rows all rest on this. The walk covers every
    // sheet adh-site.css brings in, not just the two host sheets' own @import lines: ui's
    // sheet imported again anywhere after adh-components.css — by auth's sheet, say — would
    // put ui's rules after that file's and flip every ORDER row whose host rule is in it.
    const order = cascadeOrder(SHEETS.site())
    const ui = realpathSync(SHEETS.ui())
    expect(order.filter((sheet) => sheet === ui)).toHaveLength(1)
    expect(order.indexOf(ui)).toBeLessThan(order.indexOf(realpathSync(SHEETS.components())))
  })

  it('knows what every shorthand in the four sheets sets', () => {
    const unknown = new Set<string>()
    for (const sheet of [...HOSTS, ...PACKAGES])
      for (const r of rulesOf(sheet))
        for (const property of r.properties) if (CSS_SHORTHANDS.has(property) && !SHORTHANDS[property]) unknown.add(property)
    expect([...unknown]).toEqual([])
  })

  it.each(Object.entries(COHABITANTS))('%s sits where COHABITANTS says', (cls, { source, on }) => {
    const text = readFileSync(resolve(import.meta.dirname, '..', source), 'utf8')
    const names = (tag: string, name: string) => new RegExp(`(?<![\\w-])${name}(?![\\w-])`).test(tag)
    for (const [tag, shared] of Object.entries(on)) {
      const carrying = openingTags(text, tag).filter((t) => names(t, cls))
      expect(carrying, `<${tag}> with ${cls} in ${source}`).not.toEqual([])
      // A raw element has only the classes adh spells on it; a component adds its own.
      if (/^[a-z]/.test(tag))
        expect(carrying.some((t) => shared.every((c) => names(t, c))), `<${tag}> with ${shared.join(' ')}`).toBe(true)
    }
  })

  it('names every contest the sheets hold, and every selector nothing can key', () => {
    const { rows, unkeyed } = discover()
    expect(rows.map(line).sort()).toEqual([...WEIGHT, ...ORDER, ...PACKAGE].map(line).sort())
    expect(unkeyed.sort()).toEqual(Object.keys(UNKEYED).sort())
  })

  // Each row is titled with its whole contest. A `$host` title is cut at 40 characters, which
  // gave two of WEIGHT's rows the same name.
  it.each(named(WEIGHT))('%s: the host is heavier', (_contest, row) => {
    const weights = hostMustWin(row)
    expect(compareSpecificity(weights.host, weights.pkg), `${fmt(weights.host)} vs ${fmt(weights.pkg)}`).toBeGreaterThan(0)
  })

  it.each(named(ORDER))('%s: equal weight, and ui comes first', (_contest, row) => {
    expect(row.pkg.startsWith('ui ')).toBe(true)
    const weights = hostMustWin(row)
    expect(fmt(weights.host)).toBe(fmt(weights.pkg))
  })

  it.each(named(PACKAGE))('%s: the package is heavier, on purpose', (_contest, { host, pkg, properties, same }) => {
    const h = rule(host)
    const p = rule(pkg)
    const floor = lightest(
      p.selectors.filter((s) => h.selectors.some((t) => meets(t, s))),
      { host, pkg, properties },
    )
    const ceiling = maxSpecificity(h.selectors)
    expect(compareSpecificity(floor, ceiling), `${fmt(floor)} vs ${fmt(ceiling)}`).toBeGreaterThan(0)
    if (same) for (const property of properties) expect(p.get(property)).toBe(h.get(property))
  })
})

describe('what is no longer a contest', () => {
  it("ui's coarse-pointer row padding meets no host rule", () => {
    const coarse = discover().rows.filter((row) => row.pkg.startsWith('ui @(pointer: coarse)'))
    expect(coarse.map(line)).toEqual([])
  })

  it("the host places the resting dock through bitbag's hooks, not by restating its rule", () => {
    const hooks = ['--bb-dock-rest-x', '--bb-dock-rest-lift']
    expect(rule('site .bb-dock.adh-footer__chat').properties.sort()).toEqual([...hooks].sort())
    const resting = rule(
      'bitbag .bb-dock--resting .bb-dock__avatar, .bb-dock--resting:has(.persona-chat.pc-collapsed) .bb-dock__avatar',
    )
    expect(resting.get('transform')).toContain('var(--bb-dock-rest-x')
    expect(resting.get('margin-bottom')).toContain('var(--bb-dock-rest-lift')
    for (const r of rulesOf('bitbag')) expect(r.properties.filter((p) => hooks.includes(p))).toEqual([])
    for (const sheet of HOSTS)
      for (const r of rulesOf(sheet))
        for (const s of r.selectors) expect(subjectClasses(s), `${sheet} ${s}`).not.toContain('bb-dock__avatar')
  })
})

describe('the resting dock', () => {
  it("is never the engaged chat, in the host sheet or in bitbag's", () => {
    // Its panel is hidden while it rests, so a scrim (or the lift above the header) there
    // would seal the page under a wash with nothing lit above it.
    for (const sheet of ['site', 'bitbag'] as const) {
      const engaged = rulesOf(sheet)
        .flatMap((r) => r.selectors)
        .filter((s) => s.includes(':has(.persona-chat:not(.pc-collapsed))'))
      expect(engaged, sheet).not.toEqual([])
      for (const s of engaged) expect(subjectCompound(s), `${sheet} ${s}`).toContain(':not(.bb-dock--resting)')
    }
  })
})

/** Every JSX opening tag `<tag …>` in `source`, props and all. Braces are balanced, and
 *  comments and strings are skipped, so neither the `>` of an arrow function inside a prop
 *  nor a `<a>` in a comment between two props ends it. */
function openingTags(source: string, tag: string): string[] {
  const past = (needle: string, from: number): number => {
    const at = source.indexOf(needle, from)
    if (at < 0) throw new Error(`unterminated ${needle} after ${from} in a <${tag}>`)
    return at + needle.length - 1
  }
  const out: string[] = []
  for (const match of source.matchAll(new RegExp(`<${tag}(?![\\w.])`, 'g'))) {
    const start = match.index!
    let depth = 0
    for (let i = start + 1; i < source.length; i++) {
      const ch = source[i]!
      if (source.startsWith('//', i)) i = past('\n', i)
      else if (source.startsWith('/*', i)) i = past('*/', i + 2)
      else if (ch === '"' || ch === "'" || ch === '`') {
        do i = past(ch, i + 1)
        while (source[i - 1] === '\\')
      } else if (ch === '{') depth++
      else if (ch === '}') depth--
      else if (ch === '>' && depth === 0) {
        out.push(source.slice(start, i + 1))
        break
      }
    }
  }
  return out
}
