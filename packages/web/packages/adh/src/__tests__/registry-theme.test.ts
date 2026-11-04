import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

/**
 * The bridge under test, and the two package stylesheets whose token contract it
 * completes: `--rp-*` from the registry profile renderer, `--rf-*` from the
 * registry field editors.
 *
 * Read from each package's `src/` rather than through `require.resolve`, for
 * `landing-bridge.test.ts`'s reason: `src/` is what a person edits, and `dist`
 * is a verbatim copy made by `build:css`, so resolving the dependency would only
 * put a build step between the edit and the failing test. `registry-profile`
 * lives in the `agenticdevelopertoolkit` submodule and adh does not depend on it
 * — but `@agentic-toolkit/registry`'s own `profile.css` is a bare passthrough
 * (`@import '@agenticdevelopertoolkit/registry-profile/css/profile.css'`), so
 * the tokens exist in exactly one file and this is it. Nothing here imports it;
 * it is read as text.
 */
const CSS = readFileSync(join(__dirname, '../styles/adh-registry-theme.css'), 'utf8')
const SOURCES = {
  '--rp-': join(
    __dirname,
    '../../../../../../external/adhsdk/packages/web/packages/registry-profile/src/css/profile.css',
  ),
  '--rf-': join(__dirname, '../../../features/registry/src/css/editor.css'),
} as const

/** One `selector { body }` rule at a time, comments already gone — see landing-bridge.test.ts. */
const RULE = /([^{}]*)\{([^{}]*)\}/g

const strip = (css: string) => css.replace(/\/\*[\s\S]*?\*\//g, '')

/** Selector parts, split on commas and sorted, so `.rf-field, .rf-def` and `.rf-def,.rf-field` are one selector. */
const parts = (selector: string) =>
  selector
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .sort()
    .join(', ')

/** Every `--<prefix>*` token a stylesheet READS, and the selector each one is DECLARED on. */
function scan(css: string, prefix: string) {
  const read = new Set<string>()
  const declaredOn = new Map<string, string[]>()
  const text = strip(css)
  for (const [, t] of text.matchAll(new RegExp(`var\\(\\s*(${prefix}[\\w-]+)`, 'g'))) read.add(t!)
  for (const [, selector, body] of text.matchAll(RULE)) {
    for (const [, t] of body!.matchAll(new RegExp(`(${prefix}[\\w-]+)\\s*:`, 'g'))) {
      const at = declaredOn.get(t!) ?? []
      at.push(parts(selector!))
      declaredOn.set(t!, at)
    }
  }
  return { read: [...read].sort(), declaredOn }
}

const PACKAGES = Object.entries(SOURCES).map(([prefix, path]) => {
  const css = readFileSync(path, 'utf8')
  return { prefix, css, ...scan(css, prefix), bridge: scan(CSS, prefix) }
})

describe.each(PACKAGES)('registry theme bridge: $prefix', ({ prefix, css, read, declaredOn, bridge }) => {
  it('reads a token contract that is neither empty nor a stub', () => {
    // Guard the derivation: a path that moved, or a regex that matched nothing,
    // would make every assertion below pass vacuously.
    expect(read.length).toBeGreaterThan(2)
  })

  it.each(read)('assigns %s', (token) => {
    expect(bridge.declaredOn.get(token) ?? []).toHaveLength(1)
  })

  it('assigns nothing the package does not read', () => {
    // A token assigned here and read nowhere is dead weight that reads as coverage.
    expect([...bridge.declaredOn.keys()].filter((n) => !read.includes(n)).sort()).toEqual([])
  })

  it('declares each token on the same selector the package declares it on', () => {
    // THE assertion this file exists for. Unlike landing, these packages assign
    // their tokens ON the block root rather than reading them as
    // `var(--x, fallback)`, and a custom property declared directly on an
    // element beats one inherited from an ancestor whatever the specificity. So
    // a bridge on any other selector — `:root` above all — loses silently and
    // completely, with every other assertion here still green. If the package
    // ever moves its tokens to a different block, this is what says so.
    const packageSide = Object.fromEntries(read.map((t) => [t, declaredOn.get(t)]))
    const bridgeSide = Object.fromEntries(read.map((t) => [t, bridge.declaredOn.get(t)]))
    expect(bridgeSide).toEqual(packageSide)
  })

  it('hands `color-scheme` back to the document on every block the package sets it on', () => {
    // The packages declare `color-scheme: light dark` so an unthemed host follows
    // the OS. Left standing inside an adh document — which has already declared
    // its scheme — the UA paints this subtree's native controls, scrollbars and
    // canvas in whichever mode the OS is in, against the page around them. Both
    // halves of the seam contain real `<select>`/`<input>`, so this is visible.
    for (const [, selector, body] of strip(css).matchAll(RULE)) {
      if (!/(^|;|\{|\s)color-scheme\s*:/.test(body!)) continue
      const here = [...strip(CSS).matchAll(RULE)].filter(
        ([, s, b]) => parts(s!) === parts(selector!) && /(^|;|\s)color-scheme\s*:\s*inherit\b/.test(b!),
      )
      expect(here, `no color-scheme reset for \`${parts(selector!)}\``).toHaveLength(1)
    }
  })
})

describe('registry theme bridge', () => {
  it('sources colour from role vars, never raw hex', () => {
    // --color-apt-* would read better here and cannot be used: those live in a
    // `@theme` block, and Tailwind v4 tree-shakes theme variables down to the
    // ones its generated utilities reference — a token consumed through `var()`
    // rather than a utility class is invisible to that pass. Hex is the other
    // way to get it wrong, and the one a diff shows.
    const decls = strip(CSS).split('\n').filter((l) => /^\s*--r[pf]-/.test(l))
    const hex = decls.filter((l) => /#[0-9a-fA-F]{3,8}\b/.test(l))
    expect(hex, `raw hex in: ${hex.join(' | ')}`).toEqual([])
    for (const line of decls) expect(line).toMatch(/var\(--color-/)
  })

  it('wins on source order alone — no !important, no specificity inflation', () => {
    // Stripped, because the header comment explains why there is no `!important`
    // here — and a rule that cannot tell an explanation from a declaration is a
    // rule nobody can write the explanation under.
    expect(strip(CSS)).not.toMatch(/!important/)
    // Every selector is exactly one class, matching the package's. A descendant
    // or compound selector would still win, and would hide the day the package
    // moves its own tokens somewhere this file no longer reaches.
    for (const [, selector] of strip(CSS).matchAll(RULE)) {
      for (const part of selector!.split(',')) expect(part.trim()).toMatch(/^\.[\w-]+$/)
    }
  })
})
