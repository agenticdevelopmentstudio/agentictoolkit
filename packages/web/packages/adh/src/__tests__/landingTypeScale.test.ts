/**
 * The shared LANDING type scale, and the first-load font contract it rides on.
 *
 * Both halves of this file pin failures that are SILENT — the page renders, the build is
 * green, and the only symptom is type that is the wrong size or arrives late:
 *
 *  1. THE SCALE EXISTS IN EVERY THEME. Landing pages consume the scale two ways: a
 *     `.text-landing-<role>` class (files that already use classes) or
 *     `var(--type-landing-<role>-<prop>, <literal>)` (files that use inline styles or plain
 *     CSS). The var form carries a fallback — which is the point of the fallback and also the
 *     trap: if a theme stops emitting the scale, every one of those consumers silently
 *     reverts to its own literal, i.e. back to the per-site drift this scale replaced, with
 *     nothing failing anywhere. `.text-landing-*` classes fail the other way (they'd size
 *     nothing at all), which is just as invisible in a build.
 *
 *  1b. AND EVERY FALLBACK IS THE DEFAULT THEME'S OWN VALUE. That is what makes the fallback
 *     a safety net rather than a second scale: the unthemed render is the themed one. The
 *     convention it replaces — "the literal is whatever this file used to hard-code" — reads
 *     as harmless bookkeeping and is the drift, re-entered through the back door, and it is
 *     unverifiable besides (nothing can check a value against a deleted one). See the note
 *     in SiteLanding.tsx; `-font` is the one exemption, for the reason recorded below.
 *
 *  2. THE CLASSES MUST READ THE VARS. `buildTypeClasses` emits `.text-landing-title { font-size:
 *     var(--type-landing-title-size) }`. If a regenerated theme ever baked the literal into the
 *     class instead, the class and the var form would drift apart the moment a theme retuned
 *     the scale — two consumers of "the same" role rendering at two sizes.
 *
 *  3. NO CONSUMER MAY LAYER ANYTHING ON A LANDING CLASS. `.text-landing-title` and `text-3xl`
 *     are both (0,1,0), so the winner is decided by which stylesheet the browser parsed last
 *     — the theme <style> today, but that is an ordering accident, not a contract. An inline
 *     `style={{ fontFamily: … }}` is worse: it does not tie, it wins outright, so an element
 *     wearing both looks like it is on the scale and is not. The rule is REPLACE, never
 *     layer, and it is checked per ELEMENT rather than per file — the same component
 *     legitimately styles other elements inline.
 *
 *  4. THE FONT MUST BE PRELOADABLE AND SAME-ORIGIN. This is the "font changes size after the
 *     initial load" bug: with the faces behind a third-party stylesheet, the browser can't
 *     discover them until that stylesheet is fetched AND parsed, so the page paints in the
 *     fallback and reflows into Iosevka afterwards. The fix is structural — same-origin
 *     faces, `@font-face` in the theme css we inline, and a `preload` in the first pass over
 *     `<head>` — and each of those three is a thing a future change can quietly undo.
 */
import { describe, it, expect } from 'vitest'
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, relative, resolve } from 'node:path'
import { themes } from '@agenticdevelopertoolkit/themes/manifest'
import { THEME_FONT_PRELOADS } from '@agenticdevelopertoolkit/themes/fonts'
import { DEFAULT_ADH_THEME } from '../themes/adh-themes'

/** The six tiers a landing page distinguishes. Adding a seventh means adding it here. */
const ROLES = ['title', 'subtitle', 'heading', 'lede', 'body', 'eyebrow'] as const

/** Emitted for every role by scripts/build-tokens.mjs; `transform` only where declared. */
const PROPS = ['font', 'size', 'line-height', 'weight', 'tracking'] as const

/**
 * The themes that carry TYPE, as opposed to only colour. Only the DTCG-generated `adh*`
 * family emits `--type-*` (scripts/build-tokens.mjs); the other ~27 entries in the manifest
 * are palettes — they override colour roles on `html:root` and inherit every type var from
 * the always-on base block `AdhThemeStyle` emits. Deriving the set rather than listing it
 * keeps a newly generated theme in scope automatically, and keeps a palette out of it
 * without an exemption anyone has to remember to add.
 */
const typographicThemes = Object.entries(themes).filter(([, e]) =>
  e.css.includes('--type-landing-'),
)

describe('the landing scale is in every theme that carries type', () => {
  it('covers the whole generated family, including the base', () => {
    expect(typographicThemes.length).toBeGreaterThan(0)
    expect(typographicThemes.map(([k]) => k)).toContain(DEFAULT_ADH_THEME)
  })

  for (const [key, entry] of typographicThemes) {
    it(`${key} declares all six roles as --type-landing-* vars`, () => {
      const missing = ROLES.flatMap((role) =>
        PROPS.filter((prop) => !entry.css.includes(`--type-landing-${role}-${prop}:`)).map(
          (prop) => `--type-landing-${role}-${prop}`,
        ),
      )
      expect(missing).toEqual([])
    })

    it(`${key} emits all six .text-landing-* classes`, () => {
      const missing = ROLES.filter((role) => !entry.css.includes(`.text-landing-${role} {`))
      expect(missing).toEqual([])
    })

    it(`${key}'s .text-landing-* classes read the vars, never a baked literal`, () => {
      for (const role of ROLES) {
        const block = entry.css.match(
          new RegExp(`\\.text-landing-${role}\\s*\\{([^}]*)\\}`),
        )?.[1]
        expect(block, `.text-landing-${role} missing from ${key}`).toBeTruthy()
        for (const decl of (block ?? '').split(';')) {
          const [prop, value] = decl.split(':').map((s) => s.trim())
          if (!prop || !value) continue
          // text-transform is a keyword the token carries verbatim (`uppercase`), so it is
          // the one declaration that legitimately has no var().
          if (prop === 'text-transform') continue
          expect(value, `${key} .text-landing-${role} { ${prop} }`).toContain(
            `var(--type-landing-${role}-`,
          )
        }
      }
    })
  }

  it('is a self-consistent pair of routes: every var a class reads is declared', () => {
    const css = themes[DEFAULT_ADH_THEME].css
    for (const role of ROLES) {
      const block = css.match(new RegExp(`\\.text-landing-${role}\\s*\\{([^}]*)\\}`))?.[1] ?? ''
      for (const name of block.match(/--type-landing-[a-z-]+/g) ?? []) {
        expect(css, `${name} read by .text-landing-${role} but never declared`).toContain(
          `${name}:`,
        )
      }
    }
  })
})

/**
 * The pnpm workspace this package lives in (`packages/web`), found by its own marker
 * rather than by counting `..` segments — the package has already moved once.
 *
 * Always present, in either checkout, and it can never resolve to something OUTSIDE this
 * repository. That is the whole difference from sitesWorkspaceRoot() below, and the reason the
 * two are separate functions instead of one with a flag.
 */
function workspaceRoot(): string {
  let dir = dirname(fileURLToPath(import.meta.url))
  for (;;) {
    if (existsSync(resolve(dir, 'pnpm-workspace.yaml'))) return dir
    const up = dirname(dir)
    if (up === dir) throw new Error('pnpm-workspace.yaml not found above this test')
    dir = up
  }
}

/**
 * The sites workspace of the checkout this submodule is sitting inside — or null when the
 * toolkit is checked out on its own.
 *
 * This repository is a submodule with more than one host, and it is CI'd twice: adh's
 * `ci.yml` runs these very suites from `frontend/src/external/agentictoolkit/packages/web`
 * (the "Toolkit unit tests" step), where frontend/src is right there; the toolkit's own
 * `web-tests.yml` checks this repo out ALONE, where it does not exist at any depth. So a
 * walk-up that throws when the marker is missing — which is what this was — turns the
 * toolkit's own gate red on a file it cannot possibly satisfy, and takes the whole suite
 * down with it, since both scans below evaluate it in a describe body.
 *
 * Returning null instead is not a shrug. It is the same shape adh's CI already uses for the
 * other toolkit test that needs its consumer's tree (`ADH_OPENAPI_SPEC`, and the help-corpus
 * check, whose comment calls that "the toolkit's one documented dependency on its
 * consumer"): the dependency is named out loud, and the checkout that cannot satisfy it
 * says so rather than pretending. What keeps the null branch honest is the
 * `no consumer of this scale has landed inside the toolkit itself` test — the skip is
 * allowed only for as long as there is provably nothing here to skip.
 */
/**
 * The marker is the sites workspace's OWN manifest, identified by the `-websites` SUFFIX of
 * its name. It was `next-config-base.mjs` until that file was split into
 * `@agentic-toolkit/adh-next-config` and deleted — at which point this walk returned null in
 * an adh checkout too, so SITES_SRC was null everywhere and the scale check self-skipped
 * GREEN in the one repository it is about. A sentinel that can be deleted takes the test
 * with it silently. The workspace root every site installs from cannot go without the fleet
 * ceasing to build, and the name check is what stops the walk there rather than at the
 * toolkit's own `packages/web/package.json` on the way up.
 *
 * It matched `adh-websites` exactly until 2026-08-30, which was true of one checkout and is
 * the shape the monorepo split retires: `agenticdeveloperteamwebsite-websites` and every
 * one-site satellite after it holds site source this file is entirely about, and each of
 * them returned null — so both scans below self-skipped or narrowed to the toolkit's own
 * copies, in the repositories that now own the consumers. The suffix is the same marker
 * `reserved-slugs.test.ts` in this package walks for, for the same reason and on the same
 * day; the two are deliberately re-stated rather than shared, a test-only helper not being
 * worth either file's public surface.
 */
function sitesWorkspaceRoot(): string | null {
  let dir = dirname(fileURLToPath(import.meta.url))
  for (;;) {
    const manifest = resolve(dir, 'package.json')
    if (existsSync(manifest)) {
      try {
        if (/-websites$/.test(JSON.parse(readFileSync(manifest, 'utf8')).name ?? '')) return dir
      } catch {
        // Unreadable or not JSON — not the marker; keep walking rather than throw.
      }
    }
    const up = dirname(dir)
    if (up === dir) return null
    dir = up
  }
}

/** Non-null in any fleet checkout that holds sites (worktrees included); null in the
 *  toolkit's own CI, which checks this repo out alone. */
const SITES_SRC = sitesWorkspaceRoot()

/**
 * The themes package's `src/fonts`, reached through this package's own dependency link.
 *
 * Neither a counted hop nor an upward walk survives here. A counted hop is what broke
 * first: the `../../../../external/agentictoolkit/...` written when this file lived in
 * adh's old app tier still RESOLVED after the package moved into the submodule, to a
 * doubled path that exists nowhere, so the assertion below failed on a bookkeeping error
 * rather than on the thing it guards. The upward walk that replaced it then broke in turn
 * when themes left this workspace for `external/adhsdk` — it is no longer
 * ABOVE this file at all, it is sideways and down. The `node_modules` link is neither: it
 * is the same edge the import statements at the top of this file travel, so it moves when
 * the dependency moves and fails loudly when the dependency is gone.
 */
function themeFontsDir(): string {
  const dir = resolve(
    dirname(fileURLToPath(import.meta.url)),
    '../../node_modules/@agenticdevelopertoolkit/themes/src/fonts',
  )
  if (!existsSync(resolve(dir, 'metrics.json'))) {
    throw new Error(
      `the @agenticdevelopertoolkit/themes package is not linked into this one: ${dir} ` +
        `has no metrics.json. Check the dependency in package.json and run pnpm install.`,
    )
  }
  return dir
}

/**
 * Every source file under `dir` that is neither build output nor a dependency. `dir` is
 * frontend/src or the workspace, depending on the checkout — see sitesWorkspaceRoot().
 *
 * Dot-directories are skipped wholesale, which is not cosmetic: `frontend/src/external`
 * holds pnpm's `.pnpm-deploy-link-*` trees — whole second copies of the toolkit packages
 * — so without the rule a single offender is reported twice and a BUILT copy gets policed
 * as if it were source.
 *
 * The agentictoolkit submodule is deliberately NOT skipped when scanning frontend/src. It
 * is another repository, but it is where this scale and its consumers now live
 * (`packages/web/packages/adh`, and the themes package that defines the tokens), so
 * excluding it would make the fallback scan below pass on two thirds less than it thinks.
 */
function* sourceFiles(dir: string, exts: readonly string[]): Generator<string> {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.') || e.name === 'node_modules' || e.name === 'dist') continue
    const p = resolve(dir, e.name)
    if (e.isDirectory()) yield* sourceFiles(p, exts)
    else if (exts.some((x) => e.name.endsWith(x))) yield p
  }
}

/**
 * Each JSX opening tag in a source file, as raw text.
 *
 * Both layering rules below are about ONE element carrying two competing declarations, so
 * the unit has to be the tag — not the file, and not a `className="…"` match, which sees
 * neither `className={cn('a', 'b')}` nor a template literal nor a sibling `style` prop.
 * Brace depth is tracked so a `>` inside an expression doesn't end the tag early. It is a
 * scanner, not a parser: a `{` or `}` inside a string literal skews the depth, which can
 * only truncate or extend a tag's text — never mask the pairing across two elements, since
 * a `<` at depth 0 abandons the candidate.
 */
function* jsxOpenTags(text: string): Generator<string> {
  for (let i = text.indexOf('<'); i !== -1; i = text.indexOf('<', i + 1)) {
    if (!/[A-Za-z]/.test(text[i + 1] ?? '')) continue
    let depth = 0
    for (let j = i + 1; j < text.length; j++) {
      const c = text[j]
      if (c === '{') depth += 1
      else if (c === '}') depth -= 1
      else if (depth === 0 && c === '>') {
        yield text.slice(i, j + 1)
        break
      } else if (depth === 0 && c === '<') break
    }
  }
}

describe('the layering scan is skipped only where there is nothing to scan', () => {
  it('no consumer of this scale has landed inside the toolkit itself', () => {
    // This runs in BOTH checkouts and is the counterweight to the skipIf below. Every
    // `.text-landing-*` consumer lives in adh's sites — measured, 27 elements across 12
    // files, and zero here — which is why the toolkit's own CI can honestly skip the scan.
    // The moment that stops being true (a landing component moves INTO this package, which
    // is exactly the direction things have been moving), the skip starts hiding real
    // consumers and this fails, in the repo that owns them, naming the file to re-root.
    //
    // The unit is the TAG, not the file, for the same reason landingTags() uses it and not
    // just because it mirrors it: SiteLanding.tsx names `.text-landing-*` in a comment while
    // consuming the scale through inline `var()`s, so a file-level match reports the one
    // file in this package that is explaining the rule as if it were breaking it.
    const root = workspaceRoot()
    const local: string[] = []
    for (const file of sourceFiles(root, ['.tsx'])) {
      const text = readFileSync(file, 'utf8')
      if (!text.includes('text-landing-')) continue
      for (const tag of jsxOpenTags(text)) {
        if (tag.includes('text-landing-')) local.push(relative(root, file))
      }
    }
    expect(local, 'root the layering scan here too — these are no longer adh-only').toEqual(
      [],
    )
  })
})

describe.skipIf(SITES_SRC === null)('consumers replace their size utility, never layer over it', () => {
  const srcDir = SITES_SRC as string
  // Tailwind's font-size utilities. Deliberately NOT `text-[...]`: an arbitrary value is
  // almost always a colour (`text-[var(--color-text-dim)]`), which never conflicts.
  const SIZE_UTILITY = /\btext-(xs|sm|base|lg|xl|[2-9]xl)\b/
  // The inline-style properties the scale sets. An inline style beats BOTH a utility and
  // a class, at any specificity, so this is the layering violation that always wins.
  const TYPE_STYLE = /\b(fontFamily|fontSize|lineHeight|letterSpacing|fontWeight)\s*:/

  function landingTags(): { file: string; tag: string }[] {
    const found: { file: string; tag: string }[] = []
    for (const file of sourceFiles(srcDir, ['.tsx'])) {
      const text = readFileSync(file, 'utf8')
      if (!text.includes('text-landing-')) continue
      for (const tag of jsxOpenTags(text)) {
        if (tag.includes('text-landing-')) found.push({ file: relative(srcDir, file), tag })
      }
    }
    return found
  }

  /** Is `file` one of the toolkit's own, rather than a site's? */
  const inThisRepo = (file: string) => !relative(workspaceRoot(), file).startsWith('..')

  it('finds the elements it is meant to police', () => {
    // Without this the two assertions below pass on an empty scan — which is exactly what
    // a broken srcDir, a skipped directory or a scanner that no longer matches looks like.
    // Two halves, because the split fleet made them two different questions.
    //
    // The scan REACHED the source. Answerable in every checkout that gets this far: this
    // file's own package is INSIDE srcDir in all of them (the toolkit is a submodule of
    // every sites workspace) and SiteLanding.tsx names the scale, so a walk that cannot
    // see it is not looking at a sites workspace at all. This is the half that catches the
    // broken srcDir, and it is unconditional.
    const marked = [...sourceFiles(srcDir, ['.tsx'])].filter((file) =>
      readFileSync(file, 'utf8').includes('text-landing-'),
    )
    const witness = resolve(dirname(fileURLToPath(import.meta.url)), '../layout/SiteLanding.tsx')
    expect(marked, `the scan of ${srcDir} never reached this package`).toContain(witness)

    // The ELEMENTS. Conditional, because a repo whose sites name the scale in no .tsx has
    // none to find: agenticpersonaregistrywebsite is the first, one site whose landing
    // page consumes the scale entirely through the shared SiteLanding component. `> 10`
    // was adh's own count, and it only ever ran there — every satellite named itself
    // `<repo>-websites`, so the walk (`adh-websites`, exactly) returned null and this
    // whole describe self-skipped until 87acf3fa widened it to the suffix. Kept as
    // written it would not police a satellite, it would demand adh's sites of it.
    if (marked.some((file) => !inThisRepo(file))) {
      expect(landingTags().length).toBeGreaterThan(0)
    }
  })

  it('no element carries both a .text-landing-* class and a Tailwind size utility', () => {
    const offenders = landingTags()
      .filter(({ tag }) => SIZE_UTILITY.test(tag))
      .map(({ file, tag }) => `${file}: ${tag.replace(/\s+/g, ' ')}`)
    expect(offenders).toEqual([])
  })

  it('no element carries both a .text-landing-* class and an inline type style', () => {
    const offenders = landingTags()
      .filter(({ tag }) => tag.includes('style={{') && TYPE_STYLE.test(tag))
      .map(({ file, tag }) => `${file}: ${tag.replace(/\s+/g, ' ')}`)
    expect(offenders).toEqual([])
  })
})

/** The value of a `var(--x, fallback)`, split on the first TOP-LEVEL comma. */
function splitVar(body: string): [string, string | null] {
  let depth = 0
  for (let i = 0; i < body.length; i++) {
    if (body[i] === '(') depth += 1
    else if (body[i] === ')') depth -= 1
    else if (body[i] === ',' && depth === 0) {
      return [body.slice(0, i).trim(), body.slice(i + 1).trim()]
    }
  }
  return [body.trim(), null]
}

/** Every `var(--type-landing-…, fallback)` in a file, with balanced-paren fallbacks. */
function* landingVars(text: string): Generator<[string, string | null]> {
  const open = /var\(\s*(--type-landing-[a-z-]+)\s*[,)]/g
  for (let m = open.exec(text); m; m = open.exec(text)) {
    let depth = 0
    let j = m.index + 3
    for (; j < text.length; j++) {
      if (text[j] === '(') depth += 1
      else if (text[j] === ')' && --depth === 0) break
    }
    yield splitVar(text.slice(m.index + 4, j))
  }
}

describe('every fallback literal is the value the default theme sets', () => {
  // Unlike the layering scan above, this one has plenty to do in EITHER checkout: the var
  // form is what CSS files and inline-style components use, and this repo has three of
  // them (SiteLanding.tsx, adh-concepts.css, adh-legal.css). So it widens to frontend/src
  // when that is there and falls back to the workspace when it is not — never skipping.
  const srcDir = SITES_SRC ?? workspaceRoot()
  const tokens = new Map<string, string>()
  for (const m of themes[DEFAULT_ADH_THEME].css.matchAll(/(--type-landing-[a-z-]+):([^;]+);/g)) {
    // Both groups are matched by the pattern that produced `m`, so they exist; TS types
    // every capture as optional under noUncheckedIndexedAccess.
    tokens.set(m[1]!, m[2]!.trim().replace(/\s+/g, ' '))
  }

  // `-font` is the one exemption, and it is structural rather than a grandfathered
  // violation: the token's own value is a nested `var(--font-serif)`, while a consumer's
  // fallback exists for the case where NO theme is present, so it has to be a real family
  // stack. The two can never be equal, so requiring it would only teach people to opt out.
  const CHECKED = ['size', 'line-height', 'weight', 'tracking']
  const propOf = (name: string) =>
    CHECKED.find((p) => name.endsWith(`-${p}`)) ?? name.split('-').pop()!

  it('reads a scale to compare against', () => {
    expect(tokens.size).toBeGreaterThan(20)
  })

  it('no consumer falls back to a size, leading, weight or tracking of its own', () => {
    const offenders: string[] = []
    let checked = 0
    for (const file of sourceFiles(srcDir, ['.tsx', '.ts', '.css', '.mjs'])) {
      const text = readFileSync(file, 'utf8')
      if (!text.includes('--type-landing-')) continue
      for (const [name, fallback] of landingVars(text)) {
        if (fallback === null || !CHECKED.includes(propOf(name))) continue
        const want = tokens.get(name)
        if (want === undefined) continue
        checked += 1
        const got = fallback.replace(/\s+/g, ' ')
        if (got !== want) {
          offenders.push(`${relative(srcDir, file)}: var(${name}, ${got}) — theme says ${want}`)
        }
      }
    }
    // A scan that found nothing to check is the failure this whole describe exists for, and
    // this floor is what says so. It is one number now, and the history of the pair it
    // replaced is the argument for why it has to be.
    //
    // It was 50/30 when frontend/src held every site in the fleet and the adh root checked
    // 109 against the workspace's 40. The 2026-08 splits took the sites out to their own
    // repositories, leaving 44/47 — 44 from THIS package (SiteLanding.tsx 12,
    // adh-concepts.css 25, adh-legal.css 7) and 3 from the one site adh still held,
    // `agenticdeveloperteam/src/site.css`. The floors became 44 and 40, and the comment
    // then said: 44 fails the moment adh's last in-repo consumer goes (47 -> 44), and the
    // number to move is the one the consumer went to.
    //
    // That is exactly what happened, on 2026-08-30: `devteam` left for
    // agenticdeveloperteamwebsite and took site.css with it, so the adh root measures 44 —
    // the same 44 the workspace root does, because adh's remaining seven sites consume this
    // scale through `.text-landing-*` classes and name no var at all. The pair had stopped
    // discriminating between the two roots, and a pair that names one number twice is worse
    // than one number: it reads as though the roots were still being told apart.
    //
    // 43 is the floor for what is now invariant — those three files, in every checkout, in
    // both roots. What it deliberately does NOT bound is a satellite's own consumers: the
    // walk above reaches them (`-websites`), so agenticdeveloperteamwebsite measures 47, but
    // no single number can be below 44 for adh and above 46 for that repo. Per-repo
    // consumers are guarded by `offenders` instead — the assertion that actually matters,
    // and the one that does not weaken as the fleet comes apart. Moving 43 down is a
    // finding about the three files, not a fix.
    expect(checked).toBeGreaterThan(43)
    expect(offenders).toEqual([])
  })
})

describe('the first-load font contract', () => {
  const css = themes[DEFAULT_ADH_THEME].css

  it('preloads at least the faces that carry a page layout', () => {
    expect(THEME_FONT_PRELOADS.length).toBeGreaterThan(0)
  })

  it('preloads only same-origin woff2 paths', () => {
    for (const href of THEME_FONT_PRELOADS) {
      expect(href, 'a preload must be a root-relative path, not a third-party URL').toMatch(
        /^\/[^/]/,
      )
      expect(href).toMatch(/\.woff2$/)
    }
  })

  it('declares an @font-face for every preloaded face, in the css we inline', () => {
    for (const href of THEME_FONT_PRELOADS) {
      expect(css, `${href} is preloaded but no @font-face uses it`).toContain(`url('${href}')`)
    }
  })

  it('fetches no font from a third-party stylesheet', () => {
    // An @import is the shape of the original bug: the faces stay undiscoverable until the
    // imported sheet has been fetched and parsed, which is after first paint.
    const imports = css.match(/@import[^;]+;/g) ?? []
    expect(imports).toEqual([])
  })

  it('ships the preloaded bytes at the path it preloads', () => {
    // `materializeThemeFonts` (the themes package's own src/materialize-fonts.mjs, called
    // from every next.config) copies these into each app's public/ at build time; the
    // source of truth is the themes package, found by walking up rather than by counting
    // `..` segments — for the same reason frontendSrc() does, and this assertion is the
    // proof it matters: the hop written here when this file lived in adh's old app tier
    // pointed OUT of the tier and into the submodule, and after the move it still
    // resolved, to a doubled path that exists nowhere.
    const fontsDir = themeFontsDir()
    for (const href of THEME_FONT_PRELOADS) {
      const file = resolve(fontsDir, href.split('/').pop() as string)
      expect(() => statSync(file), `${href} has no bytes at ${file}`).not.toThrow()
    }
  })
})
