/**
 * The Debug console's production gate on the Site theme topic.
 *
 * Why this is gated on the BUILD and not on the viewer: the console's door — the site menu's
 * "Debug Options" row — opens for a signed-in adh admin in EVERY env, production included.
 * That used to hand that admin a half-working site-theme editor: production emits no
 * alt-theme `<style>` nodes, so nothing could actually be switched, but the editor opened
 * anyway and still applied live override CSS to the real site. So the door cannot be the
 * gate; the topic has to not exist.
 *
 * Both failure modes here are silent. Show the topic in production and you get a broken
 * editor, not an error. Ship its chunk and nothing misbehaves at all — the code is just
 * there, downloadable, for a surface that is supposed to be internal.
 */
import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { rootTopicsFor } from '../debug-env/DebugConsole'

const here = dirname(fileURLToPath(import.meta.url))
const ids = (o: { devBuild: boolean; hasChatTheme: boolean }) => rootTopicsFor(o).map((t) => t.id)

describe('rootTopicsFor', () => {
  it('offers Site theme in a dev build', () => {
    expect(ids({ devBuild: true, hasChatTheme: false })).toContain('site-theme')
  })

  it('does NOT offer Site theme in a production build — the safety property', () => {
    expect(ids({ devBuild: false, hasChatTheme: false })).not.toContain('site-theme')
    expect(ids({ devBuild: false, hasChatTheme: true })).not.toContain('site-theme')
  })

  it('keeps the always-available topics in every build', () => {
    // Settings and Environment are not dev-only: an admin opening the console in production
    // still gets them. Gating the whole console would have been the blunter, wronger fix.
    for (const devBuild of [true, false]) {
      expect(ids({ devBuild, hasChatTheme: false })).toEqual(
        expect.arrayContaining(['settings', 'environment']),
      )
    }
  })

  it('offers Chat theme only when the host injected a config', () => {
    expect(ids({ devBuild: true, hasChatTheme: true })).toContain('chat-theme')
    expect(ids({ devBuild: true, hasChatTheme: false })).not.toContain('chat-theme')
  })

  it('preserves the declared topic order, Settings last under a divider', () => {
    expect(ids({ devBuild: true, hasChatTheme: true })).toEqual([
      'environment',
      'site-theme',
      'chat-theme',
      'settings',
    ])
    const topics = rootTopicsFor({ devBuild: false, hasChatTheme: false })
    expect(topics.filter((t) => t.dividerAfter).map((t) => t.id)).toEqual(['environment'])
  })
})

describe('the site-theme editor module', () => {
  const src = readFileSync(resolve(here, '../debug-env/DebugConsole.tsx'), 'utf8')

  it('is reached only through an env-gated dynamic import', () => {
    // Source text, because the property is invisible at runtime: this is what keeps the
    // editor's chunk — the theme-editor state and the persistence client — out of
    // production. (Its other half, the host's taxonomy and CSS editor, is not reached from
    // here at all: it arrives through the injected `themeAreas` loader, which the HOST gates
    // the same way. In adh that is the one carrying Monaco.) Both halves below are
    // load-bearing and both are easy to "clean up" by accident:
    //   - a STATIC `import { SiteThemeConsole }` bundles it regardless of the gate, and
    //   - `dynamic()` without the folded ternary leaves the import() reachable, so the
    //     chunk is still emitted for production to serve.
    // Either way every test above still passes and the UI still looks correct.
    //
    // The gate's exact shape — comparisons written out, package subpath, tsup entry +
    // external, package export — belongs to productionBundleGates.test.ts, which owns the
    // whole four-legged mechanism. Here we only pin that the console reaches the editor
    // through a dynamic import and never through a value import.
    expect(src).toMatch(
      /const SiteThemeConsole =[\s\S]*?\?\s*dynamic\(\(\) =>\s*import\('@agentic-toolkit\/adh\/debug-env\/SiteThemeConsole'\)/,
    )
    // Only the type may be imported statically — types are erased, so they cost no bundle.
    const STATIC_IMPORT = /^import\s+(type\s+)?.*?'[^']*\/SiteThemeConsole'/gm
    const valueImports = (text: string) =>
      Array.from(text.matchAll(STATIC_IMPORT)).filter((m) => m[1] === undefined)
    // Proof the check isn't vacuous: an empty match list would satisfy the loop below either
    // way, so pin that the regex finds the import that IS there and rejects a value one.
    expect(Array.from(src.matchAll(STATIC_IMPORT)), 'regex found no import at all').not.toEqual([])
    expect(valueImports(`import { SiteThemeConsole } from './SiteThemeConsole'`)).not.toEqual([])
    expect(valueImports(src).map((m) => m[0])).toEqual([])
  })

  it('passes the real build gate at the one call site', () => {
    // rootTopicsFor is pure, so the tests above prove nothing unless production actually
    // reaches it with devBuild=false.
    expect(src).toContain('rootTopicsFor({ devBuild: DEV_BUILD')
  })
})
