import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

const CSS = readFileSync(join(__dirname, '../styles/adh-landing-bridge.css'), 'utf8')

/**
 * Every `--lp-*` token `@agenticdevelopertoolkit/landing`'s stylesheets READ, derived
 * from those stylesheets on every run.
 *
 * This list used to be kept by hand here, "measured from those files", and it
 * drifted the moment the package grew a token: `--lp-font-serif` — the tour's
 * closing promise, the one non-mono line in the deck — was read by
 * `blocks.css` and missing from the list, so the bridge never assigned it and
 * three tour pages shipped in the package's `Georgia, serif` fallback while
 * every assertion here passed. A hand-kept vocabulary drifts silently by
 * construction; the only fix is not to keep one.
 *
 * Read from the linked package's `src/` rather than through `require.resolve`
 * because `src/` is what a person edits — `dist/css` is a verbatim copy made
 * by `build:css`, so resolving the dependency would only add a build step
 * between the edit and the failing test.
 *
 * Reached through this package's own `node_modules` link rather than by counting
 * `..` hops: landing is no longer a sibling in this workspace — it lives in the
 * `external/adhsdk` submodule, which is a different depth and a
 * different repo. The link is the same one the import statements use, so it cannot
 * point somewhere the code does not.
 */
const LANDING_CSS = join(
  __dirname,
  '../../node_modules/@agenticdevelopertoolkit/landing/src/css',
)

/**
 * One `selector { body }` rule at a time, with comments already gone.
 *
 * `[^{}]*` on both halves is what skips an at-rule wrapper rather than
 * mis-reading it: inside `@media (...) { .x { ... } }` the outer `{` cannot be
 * followed by a brace-free body, so the scan slides forward and matches the
 * inner rule, whose selector is everything since the last brace. Nesting deeper
 * than a wrapper is not something these stylesheets do.
 */
const RULE = /([^{}]*)\{([^{}]*)\}/g

function landingTokens(): { read: string[]; assigned: string[] } {
  const read = new Set<string>()
  const assigned = new Set<string>()
  for (const name of readdirSync(LANDING_CSS).filter((f) => f.endsWith('.css'))) {
    // Comments out first. These stylesheets carry long prose comments that
    // quote the very tokens they explain — `var(--lp-bar-pad-*`, and braces in
    // sample rules — and read literally that prose adds tokens to the contract
    // that no declaration anywhere reads.
    const css = readFileSync(join(LANDING_CSS, name), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')
    // `!` on every group here: each pattern has ONE group and it is not optional, so a match
    // implies it. `noUncheckedIndexedAccess` types it `string | undefined` regardless.
    for (const [, t] of css.matchAll(/var\(\s*(--lp-[\w-]+)/g)) read.add(t!)
    for (const [, selector, body] of css.matchAll(RULE)) {
      if (!/(^|,)\s*:root\b/.test(selector!.trim())) continue
      for (const [, t] of body!.matchAll(/(--lp-[\w-]+)\s*:/g)) assigned.add(t!)
    }
  }
  return { read: [...read].sort(), assigned: [...assigned].sort() }
}

const { read: TOKENS, assigned: SELF_ASSIGNED } = landingTokens()

describe('landing bridge', () => {
  it('reads a token contract that is neither empty nor a stub', () => {
    // Guard the derivation: a glob that found no files, or a regex that
    // matched nothing, would make every assertion below pass vacuously.
    expect(TOKENS.length).toBeGreaterThan(40)
  })

  it('is the only place the contract is assigned', () => {
    // The package's half of the deal: it never assigns `:root`, so every token
    // is read as `var(--lp-x, <neutral fallback>)` and a host override always
    // wins. A token the package rooted itself would be one this bridge could
    // not reach, and it would not belong in the list above either.
    //
    // `:root` and not "anywhere", which is what this once read. The flow layout
    // re-points tokens INSIDE a rule on purpose — `.lp-band--paper` sets
    // `--lp-ink` from `--lp-paper-ink` for the length of one light band, and
    // `.lp-site-drawer-only` sets the two bar tokens for the one bar it wraps.
    // Neither takes anything away from this bridge: both are downstream of a
    // `:root` value it assigns, and both are the cascade working. Counting them
    // as a broken contract failed the deal's actual terms — that the ROOT is
    // the host's — for doing the thing scoped custom properties are for.
    expect(SELF_ASSIGNED).toEqual([])
  })

  it.each(TOKENS)('assigns %s', (token) => {
    expect(CSS).toMatch(new RegExp(`^\\s*${token}\\s*:`, 'm'))
  })

  it('assigns nothing the package does not read', () => {
    // The other direction, and not symmetric with it: a token assigned here
    // and read nowhere is dead weight that reads as coverage.
    const names = [...CSS.matchAll(/^\s*(--lp-[\w-]+)\s*:/gm)].map((m) => m[1]!)
    expect(names.filter((n) => !TOKENS.includes(n))).toEqual([])
  })

  it('sources colour from role vars, never raw hex', () => {
    const decls = CSS.split('\n').filter((l) => l.trim().startsWith('--lp-'))
    const hex = decls.filter((l) => /#[0-9a-fA-F]{3,8}\b/.test(l))
    expect(hex, `raw hex in: ${hex.join(' | ')}`).toEqual([])
  })

  it('assigns each token exactly once', () => {
    const names = [...CSS.matchAll(/^\s*(--lp-[\w-]+)\s*:/gm)].map((m) => m[1])
    expect(new Set(names).size).toBe(names.length)
  })
})
