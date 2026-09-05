import dynamic from 'next/dynamic'
import { preload } from 'react-dom'
import { themes } from '@agenticdevelopertoolkit/themes/manifest'
import { splitImports, parseRootProps } from '@agenticdevelopertoolkit/themes/tokens'
import { APPEARANCE_PREPAINT_SCRIPT } from '@agenticdevelopertoolkit/themes/appearance'
import { THEME_FONT_PRELOADS } from '@agenticdevelopertoolkit/themes/fonts'
import {
  DEFAULT_ADH_THEME,
  DEFAULT_SITE_THEME,
  isFullPaletteTheme,
  usesBaseThemeFonts,
  type SwitcherThemeKey,
} from './adh-themes'
import { switcherThemeKeys } from './theme-keys'
import { themePrePaintScript } from './theme-preview'
import { isDevDeploymentEnv } from '@agentic-toolkit/adh-registry/deployment-env'

// Theme switching is gated to non-production (local/testing/staging) so production
// routes stay exactly as they are (one static theme, no extra payload, no client
// switcher). The env allowlist lives in adh-registry's deployment-env — one home shared with the
// site menu's dev tail, so the two gates cannot drift apart. It is a plain array there,
// never `new Set(...)`: this module is inlined into both dist/server.js and
// dist/themes/index.js (see AdhThemeStyle's two exports in tsup.config.ts), and a
// top-level `const X = new Set(...)` is exactly the module-state-fork shape
// <adh-tools>/sites/scripts/verify-bundle-boundaries.py's Check B flags.
const switcherEnv = () => isDevDeploymentEnv(process.env.DEPLOYMENT_ENV)

/**
 * The persisted-DB-theme applier, loaded on demand and only in a build that carries dev
 * tooling. Follows the chunk-gate contract in adh-registry's deployment-env: comparisons written out so
 * webpack folds them while parsing, package subpath so the boundary survives tsup.
 *
 * Keeping it behind that boundary is what makes this file SERVER-ONLY, and that is the
 * bigger prize. It is the only 'use client' module in this graph, and tsup bundles the
 * whole `themes` entry into one file with one hoisted directive — so a plain
 * `import { DbThemeApplier } from './DbThemeApplier'` marked AdhThemeStyle itself as client
 * code, shipping the switcher-payload builder below (every switchable theme key, the
 * pre-paint script source, the alt-block JSX) into the browser bundle of every page of
 * every site, in every env, where none of it is ever used. Nothing about that was visible:
 * the server render is identical either way.
 *
 * The static package-path import this replaces was already load-bearing for a second
 * reason, and the dynamic one keeps it: server.ts's bundle must never inline this leaf, or
 * `getAdhTheme`'s next/headers import comes with it. See the matching `external` entry in
 * tsup.config.ts.
 */
const DbThemeApplier =
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'local' ||
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'testing' ||
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'staging'
    ? dynamic(() =>
        import('@agentic-toolkit/adh/themes/DbThemeApplier').then((m) => m.DbThemeApplier),
      )
    : null

/**
 * Builds the local/staging/testing-only theme-switcher payload: each switchable theme
 * as an INACTIVE `<style data-adh-theme-alt>`. adh-family themes share the base palette,
 * so their block is just a `:root` delta of the props that differ (a few font vars — the
 * rest comes from the always-on default block); full-palette themes carry their WHOLE
 * `html:root`-scoped stylesheet (own M3 roles + legacy tokens + structural CSS), since
 * they replace the base rather than tweak it. Flipping one to media="all" re-themes the
 * page with no fetch/FOUC. Plus each theme's fonts and a pre-paint script (see
 * themePrePaintScript) that applies the stored/carried choice before first paint. Returns
 * null in production — DEPLOYMENT_ENV is read on the server only and never shipped (the
 * switcher keys off the presence of these <style> nodes instead).
 */
function ThemeSwitcherAssets({ defaultImports }: { defaultImports: string[] }) {
  if (!switcherEnv()) return null

  const already = new Set(defaultImports)
  const fonts = new Set<string>()
  const baseProps = parseRootProps(themes[DEFAULT_ADH_THEME].css)
  const blocks: { key: SwitcherThemeKey; label: string; css: string }[] = []
  for (const key of switcherThemeKeys()) {
    const { imports, rest } = splitImports(themes[key].css)
    imports.forEach((u) => !already.has(u) && fonts.add(u))
    const label = themes[key].label
    if (isFullPaletteTheme(key)) {
      // Full-palette themes carry their WHOLE stylesheet (own M3 roles + legacy tokens
      // + structural CSS), self-scoped via html:root / html:root[data-color-mode] so an
      // active one outranks the base theme AND color-mode-light. No delta over the base.
      blocks.push({ key, label, css: rest })
    } else {
      // adh family shares the base palette, so ship only the props that differ (fonts).
      const delta = [...parseRootProps(rest)].filter(([k, v]) => baseProps.get(k) !== v)
      blocks.push({ key, label, css: `:root{${delta.map(([k, v]) => `${k}:${v}`).join(';')}}` })
    }
  }

  const prePaint = themePrePaintScript()

  // Warm the connections these switcher stylesheets live on. Every family site's layout
  // used to carry this pair of preconnects hand-written into its own <head>, back when the
  // default theme @import'ed Iosevka from a CDN. The default self-hosts now, so in
  // production those preconnects opened a TLS connection to an origin the page never
  // contacted; here — the only place a Google-hosted font is still fetched — they are live.
  // Derived from the URLs actually emitted, so a switcher theme on a new host is covered
  // and a removed one stops being preconnected.
  //
  // `cors` per origin, because a preconnect only warms the connection the real request
  // then uses: an anonymous (CORS) preconnect and a plain one land in DIFFERENT connection
  // pool entries, so getting it backwards costs an extra handshake rather than saving one.
  // A stylesheet is fetched no-CORS; a webfont is ALWAYS fetched in CORS mode. Google
  // splits those across two hosts, which is what makes the distinction visible here: the
  // css comes from fonts.googleapis.com and the woff2 from fonts.gstatic.com, and only the
  // first is discoverable from the markup while the second is the slow one.
  const origins = new Map<string, boolean>()
  for (const href of fonts) {
    let origin: string
    try {
      ;({ origin } = new URL(href))
    } catch {
      // `href` is whatever a theme's `@import url(...)` names — the token source is ours,
      // but nothing between there and here parses it, so a relative or malformed url must
      // not take out the render of every <head> in the family. It stays in `fonts` and is
      // still emitted as a stylesheet link; it just gets no preconnect.
      continue
    }
    origins.set(origin, origins.get(origin) ?? false)
    if (origin === 'https://fonts.googleapis.com') origins.set('https://fonts.gstatic.com', true)
  }

  return (
    <>
      {[...origins].map(([origin, cors]) => (
        <link
          key={`pc:${origin}`}
          rel="preconnect"
          href={origin}
          {...(cors ? { crossOrigin: 'anonymous' as const } : {})}
        />
      ))}
      {[...fonts].map((href) => (
        <link key={`sw:${href}`} rel="stylesheet" href={href} data-adh-theme-switch-font="" />
      ))}
      {/* Every switchable theme as an INACTIVE block (adh-family: a `:root` delta;
          full-palette: its whole `html:root` stylesheet); the pre-paint (and the
          ThemeSwitcher) activate exactly one via `media`. suppressHydrationWarning
          because that flip happens before hydration on these very nodes.

          The human-readable label rides along on the node. A client picker needs
          {key, label} pairs, and the only other source is the theme MANIFEST — whose
          entries each carry a whole stylesheet as a string, so importing it from a
          client component would ship every theme's CSS text into the JS bundle a
          second time. Reading the labels back off these nodes costs nothing, and
          keeps the picker's menu derived from the blocks it actually switches
          rather than from a parallel list that can drift. */}
      {blocks.map(({ key, label, css }) => (
        <style
          key={`alt:${key}`}
          data-adh-theme-alt={key}
          data-adh-theme-label={label}
          media="not all"
          suppressHydrationWarning
          dangerouslySetInnerHTML={{ __html: css }}
        />
      ))}
      {/* Trusted, static bootstrap (no user input). */}
      <script dangerouslySetInnerHTML={{ __html: prePaint }} />
      {/* Applies a persisted DB theme on load (seeds ride the pre-paint above). Absent from
          a production BUILD entirely — see the gate above; this branch only ever runs in a
          dev env, where the gate is true. */}
      {DbThemeApplier ? <DbThemeApplier /> : null}
    </>
  )
}

/**
 * The site's default theme (DEFAULT_SITE_THEME), emitted ALWAYS-ON over the base block —
 * this is what a visitor sees with no stored choice. Only rendered OUTSIDE the switcher
 * envs: where the switcher exists, the default is instead applied by the pre-paint
 * flipping its alt-block (same result, before first paint), which keeps it a single
 * flippable node so selecting another theme can deactivate it. Emitting it here too
 * would make that block un-deactivatable and pin production's theme past the switcher.
 *
 * Nothing is emitted when the site theme IS the base theme — the base block already is it.
 */
function SiteDefaultTheme({ baseImports }: { baseImports: string[] }) {
  if (switcherEnv() || DEFAULT_SITE_THEME === DEFAULT_ADH_THEME) return null
  const entry = themes[DEFAULT_SITE_THEME]
  if (!entry) return null
  const { imports, rest } = splitImports(entry.css)
  const already = new Set(baseImports)
  return (
    <>
      {imports
        .filter((href) => !already.has(href))
        .map((href) => (
          <link
            key={href}
            rel="stylesheet"
            href={href}
            data-adh-theme-import={DEFAULT_SITE_THEME}
          />
        ))}
      <style
        data-adh-site-theme={DEFAULT_SITE_THEME}
        dangerouslySetInnerHTML={{ __html: rest }}
      />
    </>
  )
}

/**
 * Injects the static ADH base theme (DEFAULT_ADH_THEME) so consumer routes stay
 * statically prerenderable (no per-request config), then the site's default theme
 * on top (DEFAULT_SITE_THEME, see SiteDefaultTheme). In staging/testing it instead
 * emits the theme-switcher payload (see ThemeSwitcherAssets), whose pre-paint applies
 * that same default.
 *
 * It also carries the APPEARANCE pre-paint script — the colour-mode (light/dark/auto) and
 * a11y bootstrap. That lives HERE, rather than in each site's layout, because this component
 * is already in the `<head>` of every site in the family: it is the one place a theming
 * concern can be added once and reach all ~45. (The hub used to inline the script itself,
 * which is exactly why no other site had a colour mode at all.)
 *
 * Consumers must set `suppressHydrationWarning` on their `<html>` — the script writes
 * `class`/`data-*` there before React hydrates, by design (the same contract next-themes has).
 */
export function AdhThemeStyle() {
  const entry = themes[DEFAULT_ADH_THEME]
  if (!entry) return null
  // Start the webfont download in the first pass over <head>, before any layout has
  // happened. The faces are same-origin (materializeThemeFonts in
  // frontend/src/next-config-base.mjs puts them in each site's public/), so this is a fetch
  // on the connection that already delivered the html — not a DNS+TLS+fetch of a
  // third-party stylesheet whose @font-face is only discoverable once it parses, which is
  // what this theme used to do and why the page settled into Iosevka well after first paint.
  //
  // React's own preload API rather than a <link>: React hoists rel="preload" links itself
  // and rendering one ALSO leaves the JSX copy behind, so each face was requested by two
  // identical tags. This emits exactly one, hoisted above the stylesheet.
  //
  // crossOrigin is REQUIRED even same-origin — fonts are always fetched in CORS mode, so a
  // preload without it does not match the css request and the face is fetched twice.
  //
  // These faces belong to the BASE theme, so the gate asks whether the theme the page
  // actually paints in draws glyphs from them: a site whose DEFAULT_SITE_THEME brings its
  // own typeface has that theme's `--font-*` layered on top, and the preload would fetch
  // ~236 KB the page never uses, on every page of that site.
  //
  // The test was `DEFAULT_SITE_THEME === DEFAULT_ADH_THEME` while those two were the same
  // key. They no longer are, and identity was the wrong question: `fishlamp` is a different
  // theme that sets the SAME Iosevka stack, so identity would have dropped the preloads
  // family-wide while the pages still painted in Iosevka — the exact latency this preload
  // exists to remove, reintroduced invisibly. usesBaseThemeFonts names the real condition.
  if (usesBaseThemeFonts(DEFAULT_SITE_THEME)) {
    for (const href of THEME_FONT_PRELOADS) {
      preload(href, { as: 'font', type: 'font/woff2', crossOrigin: 'anonymous' })
    }
  }
  const { imports, rest } = splitImports(entry.css)
  return (
    <>
      {imports.map((href) => (
        <link
          key={href}
          rel="stylesheet"
          href={href}
          data-adh-theme-import={DEFAULT_ADH_THEME}
        />
      ))}
      <style
        data-adh-theme={DEFAULT_ADH_THEME}
        dangerouslySetInnerHTML={{ __html: rest }}
      />
      {/* Applies the user's colour mode + a11y prefs to <html> BEFORE first paint, so a
          signed-in user's theme doesn't flash. Reads this browser's cached copy; the server
          is the truth and AppearanceSync (@agentic-toolkit/adh/auth) reconciles a moment
          later. With no cache — a first visit, or a signed-out visitor — colour mode is
          `auto`, i.e. the OS setting. Static, self-authored script (no user input). */}
      <script dangerouslySetInnerHTML={{ __html: APPEARANCE_PREPAINT_SCRIPT }} />
      <SiteDefaultTheme baseImports={imports} />
      <ThemeSwitcherAssets defaultImports={imports} />
    </>
  )
}
