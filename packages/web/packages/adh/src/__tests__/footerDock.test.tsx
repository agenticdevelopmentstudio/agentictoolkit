/**
 * The footer dock, rendered FOR REAL.
 *
 * footerBitbag.test.tsx stubs `../footer/FooterChat` down to a marker, which is right for what
 * it asserts (bitbag is not gated — the assertion is about him being MOUNTED, not about his
 * internals). The cost is that nothing anywhere mounted him: he now ships in the footer of
 * every site, and the things the footer itself owns were untested. All are pinned here,
 * against the real `BitbagDock`:
 *
 *   1. the PORTAL — the dock is `position: fixed` and rendered into `document.body`, because
 *      `.adh-footer` is sticky WITH a z-index and therefore a stacking context its descendants
 *      cannot paint out of. Left inside it, bitbag was trapped under the header;
 *   2. the positioning class riding on the dock column itself, which is what the `z-index` in
 *      adh-components.css attaches to;
 *   3. the chat theme arriving as a PROP — the hub's Debug console writes a key into the
 *      shared store, and it has to reach the component that owns the theme scope. A host
 *      <ThemeStyle> around the dock sets the same custom properties on a FARTHER ancestor and
 *      silently loses, which is exactly how the picker spent a while looking wired and
 *      theming nothing (see footer/chat-theme-store.ts);
 *   4. his resting box FITTING the slot the bar keeps for it. The box's width is bitbag's
 *      (an inline style, from his `size`) and the slot's is adh-site.css's, so neither file
 *      can see the other; only the real dock beside the real stylesheet can.
 *
 * `FooterChatInner` is rendered directly rather than through `FooterChat`: the loader is a
 * three-line `next/dynamic` wrapper whose import resolves to the package's built dist, so
 * going through it would test the last build instead of the source.
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
// Type-side too, not just the runtime setup — see footerBitbag.test.tsx.
import '@testing-library/jest-dom/vitest'
import { render, cleanup } from '@testing-library/react'
import { ThemeStyle, type ThemeKey } from '@agenticdevelopertoolkit/themes'
import { DEFAULT_THEME } from '@agentic-toolkit/bitbag'
import { REST_DOCK_SELECTOR } from '../footer/useFooterRestOffset'

/** Mirrors footer/chat-theme-store.ts — the localStorage key the Debug console writes. */
const STORAGE_KEY = 'adh-chat-theme'
/** bitbag scopes his own theme block to `.pc-theme-scope` (BitbagChat). */
const THEME_SCOPE = '.pc-theme-scope'
/** The envs `THEME_SWITCH_ENABLED` allows the stored key to be READ in — stated as
 *  data so every one of them is actually exercised. Dropping a tier from the store
 *  without dropping it here fails the enabled test below; the disabled test covers
 *  the other direction. */
const DEV_ENVS = ['local', 'testing', 'staging'] as const

/**
 * The dock as a build for `env` would render it.
 *
 * ALWAYS through here, never a static import, even where the env looks irrelevant.
 * `THEME_SWITCH_ENABLED` folds from `NEXT_PUBLIC_DEPLOYMENT_ENV` at module load, so
 * a statically-imported dock is skinned by whatever the runner's shell happened to
 * export — and `local` is one plausible export away from turning the production
 * assertion below into a statement about an empty localStorage. Stubbing the env
 * makes each test say which build it is about. Same pattern as
 * header/__tests__/devToolsEntries.test.ts.
 */
const dockIn = async (env: string | undefined) => {
  vi.resetModules()
  vi.stubEnv('NEXT_PUBLIC_DEPLOYMENT_ENV', env)
  const { default: Inner } = await import('../footer/FooterChatInner')
  return render(<Inner />)
}

/** The one <style> scoped to bitbag's theme root, picked by CONTENT rather than by id or
 *  position — the dock is free to emit other style tags, and the id is the toolkit's
 *  business. Empty string if he emitted no theme block at all, so a miss reads as a
 *  mismatch instead of a crash. */
function themeCss(root: HTMLElement): string {
  const marker = `@scope (${THEME_SCOPE})`
  return (
    [...root.querySelectorAll('style')]
      .map((s) => s.textContent ?? '')
      .find((css) => css.includes(marker)) ?? ''
  )
}

/** The CSS `ThemeStyle` emits for a theme at bitbag's scope — used as an ORACLE, so these
 *  assertions say "the dock is wearing theme X" rather than restating X's stylesheet. Read
 *  from its own `container` rather than the shared body, so it can be called while a dock is
 *  mounted without picking the dock's block up instead of its own. */
function cssFor(theme: ThemeKey): string {
  const { container, unmount } = render(<ThemeStyle theme={theme} scope={THEME_SCOPE} />)
  const css = themeCss(container)
  unmount()
  return css
}

beforeEach(() => {
  window.localStorage.removeItem(STORAGE_KEY)
})
afterEach(() => {
  cleanup()
  window.localStorage.removeItem(STORAGE_KEY)
  vi.unstubAllEnvs()
  vi.resetModules()
})

describe('footer dock', () => {
  it('portals the real dock to the body, under the footer positioning class', async () => {
    const { container, baseElement } = await dockIn(undefined)
    // Nothing in the host's own subtree: the whole rig is portalled to document.body, which
    // is the only way it can paint above the sticky, z-indexed footer bar it belongs to.
    expect(container.querySelector('.bb-dock')).toBeNull()
    const dock = baseElement.querySelector('.bb-dock')
    expect(dock).not.toBeNull()
    // The host's wrapper class rides on the dock column itself, not on some div around it —
    // adh-components.css layers `.adh-footer__chat` directly.
    expect(dock).toHaveClass('adh-footer__chat')
    // His face, his chat and his `i`, the three parts of the fixture.
    expect(baseElement.querySelector('.bb-dock__avatar')).not.toBeNull()
    expect(baseElement.querySelector('.bb-dock__chat')).not.toBeNull()
    expect(baseElement.querySelector('.bb-info')).not.toBeNull()
  })

  it('wears bitbag’s own default skin when nothing is stored', async () => {
    const { baseElement } = await dockIn(undefined)
    // Pinned by NAME as well as by CSS: he is one creature, and the skin he ships in
    // everywhere is the lamp — fishlamp's, which is the source of truth for how he looks.
    expect(DEFAULT_THEME).toBe('fishlamp')
    expect(themeCss(baseElement)).toBe(cssFor(DEFAULT_THEME))
  })
})

describe('his resting box and the slot the bar keeps for it', () => {
  it('is the element `useFooterRestOffset` writes his offset on', async () => {
    // The hook finds the dock by selector. Were that to stop matching the real root, the
    // offset would land nowhere and he would rest at the centre, over the bar's links.
    const { baseElement } = await dockIn(undefined)
    expect(baseElement.querySelector(REST_DOCK_SELECTOR)).toBe(baseElement.querySelector('.bb-dock'))
  })

  it('is never wider than the slot, in the same unit', async () => {
    const { baseElement } = await dockIn(undefined)
    expect(baseElement.querySelector('.bb-dock')).toHaveClass('bb-dock--resting')
    const box = baseElement.querySelector<HTMLElement>('.bb-dock__avatar')!.style.width
    expect(box).toMatch(/^\d+(\.\d+)?px$/)

    // Source text, comments stripped: vitest hands a CSS import back as an empty string.
    const css = readFileSync(resolve(import.meta.dirname, '../styles/adh-site.css'), 'utf8').replace(
      /\/\*[\s\S]*?\*\//g,
      '',
    )
    const slot = css.match(/--adh-footer-rest-slot:\s*([^;]+);/)
    expect(slot, 'no --adh-footer-rest-slot in adh-site.css — did it move?').not.toBeNull()
    // In px, the unit his box is laid out in. The slot was 4.25rem, and the Text size
    // setting's Small root (14px) made it 59.5px against his 66px box, which then covered
    // the left edge of Legal and took its clicks.
    expect(slot![1]!.trim()).toMatch(/^\d+(\.\d+)?px$/)
    expect(parseFloat(slot![1]!)).toBeGreaterThanOrEqual(parseFloat(box))
  })
})

describe('the stored chat theme is a DEV affordance', () => {
  it.each(DEV_ENVS)('wears the theme the Debug console stored, in %s', async (env) => {
    window.localStorage.setItem(STORAGE_KEY, 'terminal')
    const { baseElement } = await dockIn(env)
    const css = themeCss(baseElement)
    expect(css).toBe(cssFor('terminal'))
    // Stated as a difference too: an assertion that only matched the oracle would also pass
    // if the store were ignored and both keys happened to build the same block.
    expect(css).not.toBe(cssFor(DEFAULT_THEME))
  })

  it('ignores a stored key that is not a theme', async () => {
    // The store validates against the toolkit's manifest, so a stale or hand-edited value
    // falls back to his default instead of reaching `themes[key]` and throwing on undefined.
    window.localStorage.setItem(STORAGE_KEY, 'not-a-theme')
    const { baseElement } = await dockIn('local')
    expect(themeCss(baseElement)).toBe(cssFor(DEFAULT_THEME))
  })

  it('ignores a perfectly valid stored theme in production, and when the env is unset', async () => {
    // The safety property, and the reason the gate is on the READ: trying skins on is fine
    // while building, but a key left behind by a dev session — or typed into the console by a
    // visitor — must not re-skin the public site, and an unset or unknown env has to fail the
    // same closed way production does.
    window.localStorage.setItem(STORAGE_KEY, 'terminal')
    for (const env of ['production', 'preview', undefined]) {
      const { baseElement } = await dockIn(env)
      expect(themeCss(baseElement)).toBe(cssFor(DEFAULT_THEME))
      cleanup()
    }
  })
})
