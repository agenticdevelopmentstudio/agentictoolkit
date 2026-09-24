/**
 * A stylesheet as the platform's own CSS parser reads it, for tests that pin a rule.
 *
 * vitest hands a CSS import back as an empty string, so a test that pins a rule has to read
 * the file's source. This package's other tests match that source with regexes, which holds
 * for one declaration in one known rule and is blind to structure: which at-rule a rule sits
 * in, which selectors one rule lists, whether a declaration is in the block or in a comment
 * quoting it. jsdom's CSSOM answers all three, so the footer's contract tests read it here.
 *
 * A CONSTRUCTED sheet rather than a `<style>` in the document: nothing is inserted into the
 * page under test, and the file's `@import`s are kept as rules instead of being fetched.
 */
import { readFileSync, realpathSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, resolve } from 'node:path'

export type StyleRule = {
  /** The conditions of the at-rules this rule sits in, outermost first — a `@supports`
   *  block's `not selector(:popover-open)`, a `@media` block's `(pointer: coarse)`. */
  at: string[]
  /** The rule's selector list, one entry per selector. */
  selectors: string[]
  /** Every property the rule declares, custom properties included. */
  properties: string[]
  /** One declaration's value in a canonical spelling ({@link canonicalValue}); '' when the
   *  rule does not declare it. */
  get(property: string): string
}

/** A value with the parser's spacing taken out, so a test can compare it with the source's:
 *  jsdom stores `var(--x, 0px)` as `var(--x,0px)`. Runs of whitespace become one space, and
 *  none is kept beside a parenthesis or a comma. */
export function canonicalValue(value: string): string {
  return value
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/\s*([(),])\s*/g, '$1')
}

/** Split a selector list on its top-level commas only: `:is(a, b), c` is two selectors. */
function selectorList(text: string): string[] {
  const out: string[] = []
  let depth = 0
  let start = 0
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '(' || c === '[') depth++
    else if (c === ')' || c === ']') depth--
    else if (c === ',' && depth === 0) {
      out.push(text.slice(start, i).trim())
      start = i + 1
    }
  }
  out.push(text.slice(start).trim())
  return out
}

type GroupRule = CSSRule & { cssRules: CSSRuleList; conditionText?: string; media?: MediaList }

/** Every style rule in the stylesheet at `path`, in source order, each with the at-rules it
 *  sits in. Rules without a selector (`@font-face`, keyframes) are left out. */
export function styleRules(path: string): StyleRule[] {
  const sheet = new CSSStyleSheet()
  sheet.replaceSync(readFileSync(path, 'utf8'))
  const out: StyleRule[] = []
  const walk = (rules: CSSRuleList, at: string[]): void => {
    for (const rule of Array.from(rules)) {
      if (rule.type === CSSRule.STYLE_RULE) {
        const { style, selectorText } = rule as CSSStyleRule
        out.push({
          at,
          selectors: selectorList(selectorText),
          properties: Array.from({ length: style.length }, (_, i) => style[i]!),
          get: (property) => canonicalValue(style.getPropertyValue(property)),
        })
      } else if ('cssRules' in rule) {
        const group = rule as GroupRule
        walk(group.cssRules, [...at, group.conditionText ?? group.media?.mediaText ?? ''])
      }
    }
  }
  walk(sheet.cssRules, [])
  return out
}

/** The `@import`s a browser honors in the stylesheet at `path`, as written: the ones before
 *  its first rule of any other kind. jsdom keeps a misplaced `@import` as a rule; a browser
 *  drops it, and so does this. */
function honoredImports(path: string): string[] {
  const sheet = new CSSStyleSheet()
  sheet.replaceSync(readFileSync(path, 'utf8'))
  const out: string[] = []
  for (const rule of Array.from(sheet.cssRules)) {
    if (rule.type !== CSSRule.IMPORT_RULE) break
    out.push((rule as CSSImportRule).href)
  }
  return out
}

/** Every stylesheet `path` brings in, itself last, in the order their rules reach the cascade:
 *  each honored `@import` with its own imports first, then the sheet's own rules. A sheet
 *  imported twice is listed twice, as a browser applies it twice. Bare specifiers resolve from
 *  the importing file through `node_modules` and the target's `exports`, as the build resolves
 *  them. A cycle, or an import that resolves to anything but a stylesheet, throws rather than
 *  being walked past. */
export function cascadeOrder(path: string, importers: readonly string[] = []): string[] {
  const sheet = realpathSync(path)
  if (importers.includes(sheet)) throw new Error(`@import cycle: ${[...importers, sheet].join(' → ')}`)
  const out: string[] = []
  for (const href of honoredImports(sheet)) {
    const target = href.startsWith('.') ? resolve(dirname(sheet), href) : createRequire(sheet).resolve(href)
    if (!target.endsWith('.css')) throw new Error(`${sheet} imports ${href}, which resolves to ${target}, not a stylesheet`)
    out.push(...cascadeOrder(target, [...importers, sheet]))
  }
  out.push(sheet)
  return out
}

/** One of this package's own stylesheets, by file name. */
export function adhStylesheet(name: string): string {
  return resolve(import.meta.dirname, '../styles', name)
}

/** One of bitbag's stylesheets, by file name — through this package's own dependency link, so
 *  the file read is the one this package builds against. */
export function bitbagStylesheet(name: string): string {
  const bitbag = realpathSync(resolve(import.meta.dirname, '../../node_modules/@agentic-toolkit/bitbag'))
  return resolve(bitbag, 'src/styles', name)
}

/** One of ui's stylesheets, by its export name (`components.css`), resolved the way
 *  adh-components.css's own `@import "@agenticdevelopertoolkit/ui/styles/…"` is: from that
 *  file, through this package's dependency link and ui's `exports` map. The link leads into
 *  the ADT submodule of THIS package's repo, not the sibling copy a site checkout also holds
 *  (see agentictoolkit's CLAUDE.md), so the rules read are the ones this package builds
 *  against. */
export function uiStylesheet(name: string): string {
  return createRequire(adhStylesheet('adh-components.css')).resolve(`@agenticdevelopertoolkit/ui/styles/${name}`)
}

// ── Selectors ───────────────────────────────────────────────────────────────────────────────
// Hand-written because no selector engine is a dependency of this package (the one the
// cascade tests would reach for, @bramus/specificity, is not resolvable from it), and the
// sheets these tests read are hand-written too. Anything it has no rule for THROWS rather
// than guessing, so a new construct in a sheet fails a test loudly instead of being scored
// as nothing.

/** Specificity as (ids, classes + attributes + pseudo-classes, types + pseudo-elements). */
export type Specificity = readonly [number, number, number]

/** Negative, zero or positive as `x` is less specific than, as specific as, or more
 *  specific than `y`. */
export function compareSpecificity(x: Specificity, y: Specificity): number {
  return x[0] - y[0] || x[1] - y[1] || x[2] - y[2]
}

function mostSpecific(list: Specificity[]): Specificity {
  return list.reduce<Specificity>((top, s) => (compareSpecificity(s, top) > 0 ? s : top), [0, 0, 0])
}

/** Where the identifier starting at `i` ends; a backslash escapes the character after it. */
function identEnd(text: string, i: number): number {
  while (i < text.length) {
    const ch = text[i]!
    if (ch === '\\') i += 2
    else if (/[\w-]/.test(ch) || ch > '\u007f') i++
    else break
  }
  return i
}

/** The index of the bracket that closes the `(` or `[` at `open`, strings skipped. */
function closing(text: string, open: number): number {
  let depth = 0
  for (let i = open; i < text.length; i++) {
    const ch = text[i]!
    if (ch === '\\') i++
    else if (ch === '"' || ch === "'") i = text.indexOf(ch, i + 1)
    else if (ch === '(' || ch === '[') depth++
    else if ((ch === ')' || ch === ']') && --depth === 0) return i
    if (i < 0) break
  }
  throw new Error(`unbalanced bracket at ${open} in: ${text}`)
}

/** Pseudo-elements that CSS2 spelled with one colon, and that still score as elements. */
const LEGACY_PSEUDO_ELEMENTS = new Set(['before', 'after', 'first-line', 'first-letter'])
/** Pseudo-classes that score as their most specific argument. */
const MOST_SPECIFIC_ARGUMENT = new Set(['is', 'not', 'has', 'matches'])
/** Functional pseudo-classes that score one class, whatever their argument. */
const ONE_CLASS = new Set(['nth-child', 'nth-last-child', 'nth-of-type', 'nth-last-of-type', 'lang', 'dir'])

/** The specificity of ONE complex selector (no top-level comma), per Selectors 4: `:where()`
 *  scores nothing, `:is()` / `:not()` / `:has()` score their most specific argument, and a
 *  pseudo-element scores as a type whether it is spelled `::before` or `:before`. A rule's
 *  selector LIST has no specificity of its own — each element is matched by one of its
 *  selectors, and it is that one's that counts. */
export function specificity(selector: string): Specificity {
  let [a, b, c] = [0, 0, 0]
  const text = selector.trim()
  for (let i = 0; i < text.length; ) {
    const ch = text[i]!
    if (/[\s>+~*]/.test(ch)) i++
    else if (ch === '#') {
      a++
      i = identEnd(text, i + 1)
    } else if (ch === '.') {
      b++
      i = identEnd(text, i + 1)
    } else if (ch === '[') {
      b++
      i = closing(text, i) + 1
    } else if (ch === ':' && text[i + 1] === ':') {
      const end = identEnd(text, i + 2)
      const name = text.slice(i + 2, end)
      c++
      i = end
      if (text[i] === '(') {
        // `::view-transition-group(adh-dock)`'s argument is a name, and adds nothing. A
        // `::slotted()` argument would add its own score: no rule here, so no guess.
        if (!name.startsWith('view-transition-')) throw new Error(`specificity: no rule for ::${name}() in: ${selector}`)
        i = closing(text, i) + 1
      }
    } else if (ch === ':') {
      const end = identEnd(text, i + 1)
      const name = text.slice(i + 1, end).toLowerCase()
      i = end
      if (text[i] !== '(') {
        if (LEGACY_PSEUDO_ELEMENTS.has(name)) c++
        else b++
        continue
      }
      const close = closing(text, i)
      const argument = text.slice(i + 1, close)
      i = close + 1
      if (name === 'where') continue
      if (MOST_SPECIFIC_ARGUMENT.has(name)) {
        const top = mostSpecific(selectorList(argument).map(specificity))
        a += top[0]
        b += top[1]
        c += top[2]
      } else if (ONE_CLASS.has(name) && !/\bof\b/i.test(argument)) b++
      else throw new Error(`specificity: no rule for :${name}(${argument}) in: ${selector}`)
    } else if (/[A-Za-z_-]/.test(ch) || ch > '\u007f') {
      c++
      i = identEnd(text, i)
    } else throw new Error(`specificity: no rule for "${ch}" at ${i} in: ${selector}`)
  }
  return [a, b, c]
}

/** The most specific selector in a rule's list: the most a rule can weigh against another
 *  on some element. */
export function maxSpecificity(selectors: string[]): Specificity {
  return mostSpecific(selectors.map(specificity))
}

/** The last compound of a complex selector — the SUBJECT, the element the rule styles:
 *  `a.x` in `.list > a.x`, `.y::before` in `.dock .y::before`. */
export function subjectCompound(selector: string): string {
  let current = ''
  let last = ''
  const text = selector.trim()
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]!
    if (ch === '(' || ch === '[') {
      const close = closing(text, i)
      current += text.slice(i, close + 1)
      i = close
    } else if (ch === '\\') {
      current += text.slice(i, i + 2)
      i++
    } else if (/[\s>+~]/.test(ch)) {
      if (current) last = current
      current = ''
    } else current += ch
  }
  return current || last
}

/** Walk a compound's own simple selectors, calling `visit` with each pseudo's name and
 *  argument (undefined when it takes none), each class's name and each attribute's name. */
function eachSimple(
  compound: string,
  visit: {
    cls?(name: string): void
    attr?(name: string): void
    pseudo?(name: string, argument: string | undefined, element: boolean): void
  },
): void {
  for (let i = 0; i < compound.length; ) {
    const ch = compound[i]!
    if (ch === '.') {
      const end = identEnd(compound, i + 1)
      visit.cls?.(compound.slice(i + 1, end))
      i = end
    } else if (ch === '[') {
      const start = i + 1 + (compound.slice(i + 1).match(/^\s*/)?.[0].length ?? 0)
      visit.attr?.(compound.slice(start, identEnd(compound, start)))
      i = closing(compound, i) + 1
    } else if (ch === ':') {
      const element = compound[i + 1] === ':'
      const start = i + (element ? 2 : 1)
      const end = identEnd(compound, start)
      const name = compound.slice(start, end).toLowerCase()
      let argument: string | undefined
      i = end
      if (compound[i] === '(') {
        const close = closing(compound, i)
        argument = compound.slice(i + 1, close)
        i = close + 1
      }
      visit.pseudo?.(name, argument, element || (!argument && LEGACY_PSEUDO_ELEMENTS.has(name)))
    } else if (ch === '\\') i += 2
    else i++
  }
}

/** The classes a selector's subject names — its own, and those in any branch of an `:is()`
 *  or `:where()` in it. Never those inside `:not()` or `:has()`: they name an element the
 *  rule does NOT style, or one it styles only through a relation. */
export function subjectClasses(selector: string): string[] {
  const out: string[] = []
  eachSimple(subjectCompound(selector), {
    cls: (name) => out.push(name),
    pseudo: (name, argument) => {
      if (argument !== undefined && (name === 'is' || name === 'where' || name === 'matches'))
        for (const branch of selectorList(argument)) out.push(...subjectClasses(branch))
    },
  })
  return out
}

/** The attributes a selector's subject tests, by name — `data-htd-row` for
 *  `[data-htd-row="collapsed"]` — found where {@link subjectClasses} finds classes. What
 *  keys a subject that names no class at all, such as ui's `:where([data-htd-row])`. */
export function subjectAttributes(selector: string): string[] {
  const out: string[] = []
  eachSimple(subjectCompound(selector), {
    attr: (name) => out.push(name),
    pseudo: (name, argument) => {
      if (argument !== undefined && (name === 'is' || name === 'where' || name === 'matches'))
        for (const branch of selectorList(argument)) out.push(...subjectAttributes(branch))
    },
  })
  return out
}

/** The pseudo-element a selector's subject styles, spelled with two colons whichever way the
 *  sheet wrote it (`::before` for `.x:before` too), or '' when the rule styles the element
 *  itself. A `::before` is a different box from its element: a rule on one never contests a
 *  rule on the other. */
export function subjectPseudoElement(selector: string): string {
  let found = ''
  eachSimple(subjectCompound(selector), {
    pseudo: (name, argument, element) => {
      if (element) found = `::${name}${argument === undefined ? '' : `(${argument})`}`
    },
  })
  return found
}
