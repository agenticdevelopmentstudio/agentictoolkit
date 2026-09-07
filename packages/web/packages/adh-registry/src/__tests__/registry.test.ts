import { describe, it, expect } from 'vitest'
import { readdirSync, statSync, existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
// isHubWorkspacePath / hubWorkspaceSlug are NOT here any more — they moved to
// @agentic-toolkit/adh/site, whose reserved-slug list is what now answers them, and their cases
// went with them (`adh/src/site/__tests__/hubWorkspacePath.test.ts`).
// `hubFeatureSegment` rather than `HUB_FEATURE_SEGMENT[id]`: the map is `as const`, so it
// carries only the sites it names and indexing it with an arbitrary SiteId is a type error
// (TS7053) even though "does the hub route this site?" is exactly what these cases ask. The
// accessor is where that widening is supposed to live — see its doc comment in registry.ts.
import type { SiteId } from '../sites/registry'
import { SITES, LISTED_SITES, FOOTER_SITES, MAIN_SITE_IDS, MARKETING_SITE_IDS, SITE_CATEGORIES, groupSitesByCategory, getSite, detectEnv, buildSiteHref, ssoReturnOrigins, HUB_FEATURE_SEGMENT, hubFeatureSegment, SITE_FOR_HUB_SEGMENT, HUB_WORKSPACE_SEGMENTS, siteWorkspaceHref, siteWorkspaceSlug, SITE_LANDING_SEGMENTS, HUB_ROUTE_SEGMENTS, siteIdForDir } from '../sites/registry'
// The generated route map — imported ONLY here. `registry.ts` keeps its landing-segment
// set as a hand-written literal so the always-loaded header never pulls the family's
// whole route inventory into its bundle; this is the oracle that keeps the two equal.
import { SITE_ROUTES } from '../sites/routes.generated'

const hub = getSite('hub')!
const cookbook = getSite('cookbook')!
const admin = getSite('admin')!
const hubHelp = getSite('hub-help')! // help.adh.com; hasHome: false
const mcp = getSite('mcp')! // a still-staging-only site (hasTesting: false)

describe('siteIdForDir', () => {
  // The folder is named for the domain the site serves, minus the TLD. Three shapes,
  // because the obvious shortcut (strip a leading `agenticdeveloper`) gets two of them
  // wrong and they are the ones nobody checks.
  it('maps a domain-shaped folder to its id', () => {
    expect(siteIdForDir('agenticdeveloperbilling')).toBe('billing')
    expect(siteIdForDir('agenticpersonaregistry')).toBe('personaregistry')
    expect(siteIdForDir('help.agenticdeveloperhub')).toBe('hub-help')
  })
  it('still answers for a bare id', () => {
    // A checkout can predate the rename; answering for both costs one comparison.
    expect(siteIdForDir('hub')).toBe('hub')
    expect(siteIdForDir('billing')).toBe('billing')
  })
  it('is undefined for anything that is not a site', () => {
    expect(siteIdForDir('node_modules')).toBeUndefined()
    expect(siteIdForDir('agenticdeveloperhub-lint')).toBeUndefined()
    expect(siteIdForDir('')).toBeUndefined()
  })
  it('cannot tell the shared toolchain folder from the site that shares its name', () => {
    // `<websites>/tools/` is the shared ESLint toolchain package, and `tools` is ALSO a
    // registry site (agenticdevelopertools.com). A name is not enough to separate them,
    // and this function has only the name — so it answers with the site, and every
    // directory walk excludes that folder by PATH before asking. Pinned here so the
    // collision is a stated fact rather than a surprise the next walk rediscovers.
    expect(siteIdForDir('tools')).toBe('tools')
  })
  it('answers for every site in the registry', () => {
    // Non-vacuity, and the property that makes it usable as a build-time lookup: no
    // registry row may be unreachable from its own folder name.
    for (const site of SITES) {
      expect(siteIdForDir(site.prodHost.replace(/\.[a-z]+$/, '')), site.id).toBe(site.id)
    }
  })
})

describe('detectEnv', () => {
  it('classifies production hosts', () => {
    expect(detectEnv('agenticdeveloperhub.com')).toBe('production')
    expect(detectEnv('admin.agenticdeveloperhub.com')).toBe('production')
  })
  it('classifies testing / staging by leading label', () => {
    expect(detectEnv('testing.agenticdeveloperhub.com')).toBe('testing')
    expect(detectEnv('staging.admin.agenticdeveloperhub.com')).toBe('staging')
  })
  it('classifies local hosts (localhost, 127.*, *.local, *.test, *.localhost, ports)', () => {
    expect(detectEnv('localhost')).toBe('local')
    expect(detectEnv('localhost:3000')).toBe('local')
    expect(detectEnv('127.0.0.1')).toBe('local')
    // The suite's domain today, and the two it was served under before that.
    // RFC 6761 reserves `.localhost`, `.test` and `.local` outright, so each
    // whole suffix is local by rule and this classifier never has to know which
    // suite domain is current.
    expect(detectEnv('projects.hub.sites.localhost')).toBe('local')
    expect(detectEnv('projects.dev.test')).toBe('local')
    expect(detectEnv('projects.dev.local')).toBe('local')
    // *.localhost subdomains — used by single-site `next dev` for cross-site local routing
    expect(detectEnv('admin.localhost')).toBe('local')
    expect(detectEnv('cookbook.localhost:5171')).toBe('local')
    expect(detectEnv('hub.localhost:5171')).toBe('local')
  })
})

describe('buildSiteHref', () => {
  it('carries /home to the target in the same env', () => {
    expect(buildSiteHref(hub, 'agenticdeveloperhub.com', '/home')).toBe(
      'https://agenticdeveloperhub.com/home',
    )
  })
  it('falls back testing → staging when the target lacks a testing env', () => {
    // mcp has no testing env (hasTesting: false), so from testing.* it resolves to staging.*
    expect(buildSiteHref(mcp, 'testing.agenticdeveloperhub.com', '/')).toBe(
      'https://staging.mcp.agenticdeveloperhub.com/',
    )
  })
  it('keeps the staging env when the target supports it', () => {
    expect(buildSiteHref(admin, 'staging.agenticdeveloperhub.com', '/')).toBe(
      'https://staging.admin.agenticdeveloperhub.com/',
    )
  })
  it('carries deep /home routes with the up-walk marker', () => {
    expect(buildSiteHref(hub, 'agenticdeveloperhub.com', '/home/foo')).toBe(
      'https://agenticdeveloperhub.com/home/foo#site-switch',
    )
  })
  it('sends /home to root for sites without a /home route', () => {
    expect(buildSiteHref(hubHelp, 'agenticdeveloperhub.com', '/home')).toBe(
      'https://help.agenticdeveloperhub.com/',
    )
  })
  it('carries /home to marketing feature sites — the fleet is hasHome now', () => {
    // Every marketing satellite exposes the gated /home feature surface
    // (docs/platform/feature-sites-redesign.md), so the switcher carries /home across.
    const academy = getSite('academy')!
    expect(buildSiteHref(academy, 'agenticdeveloperhub.com', '/home')).toBe(
      'https://agenticdeveloperacademy.com/home',
    )
  })
  it('sends site-specific deep routes to the target landing', () => {
    expect(buildSiteHref(hub, 'agenticdevelopercookbook.com', '/recipes/x')).toBe(
      'https://agenticdeveloperhub.com/',
    )
  })
  it('resolves to a local origin from local dev (bare localhost, no port)', () => {
    expect(buildSiteHref(cookbook, 'localhost', '/home')).toBe('http://cookbook.localhost/home')
  })
})

describe('local cross-site origins', () => {
  it('routes hub to the bare localhost apex on the current port', () => {
    const hub = getSite('hub')!
    expect(buildSiteHref(hub, 'admin.localhost:5171', '/')).toBe('http://localhost:5171/')
  })

  it('routes a non-hub site to <id>.localhost on the current port', () => {
    expect(buildSiteHref(cookbook, 'localhost:5171', '/')).toBe('http://cookbook.localhost:5171/')
  })

  // Suite scheme: apex is `<suite>.<domain>`, others `<id>.<suite>.<domain>`,
  // for every domain in LOCAL_SUITE_DOMAINS.
  it('routes hub to the bare suite apex from a sites.localhost child host', () => {
    expect(buildSiteHref(hub, 'admin.hub.sites.localhost', '/')).toBe('https://hub.sites.localhost/')
  })

  // Also the case that keeps the two local schemes apart: the served domain is
  // itself under `.localhost` now, so a suite host is only read as a suite host
  // because LOCAL_SUITE_DOMAINS is consulted before the bare-localhost branch.
  // Without the entry this answers `http://cookbook.localhost/`.
  it('routes a non-hub site to <id>.<suite>.sites.localhost from the apex', () => {
    expect(buildSiteHref(cookbook, 'hub.sites.localhost', '/')).toBe(
      'https://cookbook.hub.sites.localhost/',
    )
  })

  it('preserves a per-worktree suite suffix across the switch', () => {
    // from a child on the `hub-mybranch` suite, hub → the suite apex, cookbook → its child
    expect(buildSiteHref(hub, 'admin.hub-mybranch.sites.localhost', '/')).toBe(
      'https://hub-mybranch.sites.localhost/',
    )
    expect(buildSiteHref(cookbook, 'hub-mybranch.sites.localhost', '/home')).toBe(
      'https://cookbook.hub-mybranch.sites.localhost/home',
    )
  })

  // A superseded suite domain still routes, and routes to ITSELF: a tab left
  // open on `dev.test` or `dev.local` keeps switching sites instead of falling
  // through to the bare-localhost branch (which would send every link to
  // `http://<id>.localhost`) or bouncing the session onto a domain the running
  // install may not serve.
  it('keeps a legacy dev.test host on dev.test', () => {
    expect(buildSiteHref(hub, 'admin.hub.dev.test', '/')).toBe('https://hub.dev.test/')
    expect(buildSiteHref(cookbook, 'hub-mybranch.dev.test', '/home')).toBe('https://cookbook.hub-mybranch.dev.test/home')
  })

  it('keeps a legacy dev.local host on dev.local', () => {
    expect(buildSiteHref(hub, 'admin.hub.dev.local', '/')).toBe('https://hub.dev.local/')
    expect(buildSiteHref(cookbook, 'hub-mybranch.dev.local', '/home')).toBe('https://cookbook.hub-mybranch.dev.local/home')
  })

  it('still uses https prod hosts when not local', () => {
    expect(buildSiteHref(cookbook, 'agenticdeveloperhub.com', '/')).toBe(
      'https://agenticdevelopercookbook.com/',
    )
  })

  it('routes the persona registry to its <id>.<suite>.sites.localhost subdomain', () => {
    const registry = getSite('personaregistry')!
    // The site id matches the suite's leaf dir (`personaregistry`), so the local
    // cross-site link resolves to where the suite actually serves the app.
    // The path is `/home` and the answer is `/`, unlike every other case here: this
    // site spends its root segment on public handles, so it has no workspace route and
    // no `/home` to carry one to, and `carryPath` degrades to the root for exactly that
    // (`hasHome: false`). So what this case still pins is the HOST derivation.
    expect(buildSiteHref(registry, 'hub-personas-move.sites.localhost', '/home')).toBe(
      'https://personaregistry.hub-personas-move.sites.localhost/',
    )
    // Local-only subdomain; testing/prod derive from prodHost (agenticpersonaregistry.com).
    expect(buildSiteHref(registry, 'testing.agenticdeveloperhub.com', '/home')).toBe(
      'https://testing.agenticpersonaregistry.com/',
    )
  })
})

describe('ssoReturnOrigins (central adh SSO client allowlist, per env)', () => {
  it('production = every non-external site as a bare-host origin (no env prefix)', () => {
    const origins = ssoReturnOrigins('production')
    expect(origins.length).toBe(SITES.filter((s) => !s.external).length)
    // one origin per site, scheme + bare prod host, no path
    expect(origins).toContain('https://agenticdeveloperhub.com')
    expect(origins).toContain('https://agenticdevelopercookbook.com')
    expect(origins).toContain('https://bitbag.ai')
    expect(origins.every((o) => /^https:\/\/[^/]+$/.test(o))).toBe(true)
    // No env PREFIX — a leading `staging.`/`testing.` label, anchored at the host's
    // head rather than matched anywhere in the string. `agenticdevelopertesting.com`
    // is a production host that contains "testing.", and a substring test calls it a
    // testing origin.
    expect(origins.some((o) => /^https:\/\/(staging|testing)\./.test(o))).toBe(false)
  })

  it('never allows an external link-out origin, in any env', () => {
    // FishLamp Design is a site we own but not an ADH app: it has no
    // /auth/callback and never begins an ADH login, so it must never be a legal
    // OAuth `return` target. Guarding all three envs keeps the redirect surface
    // tied to apps that can actually complete a login.
    const externals = SITES.filter((s) => s.external)
    expect(externals.map((s) => s.id).sort()).toEqual(['fishlamp', 'fishlampdesign'])
    for (const env of ['production', 'staging', 'testing'] as const) {
      const origins = ssoReturnOrigins(env)
      for (const s of externals) {
        expect(origins.some((o) => o.includes(s.prodHost)), `${s.id} in ${env}`).toBe(false)
      }
    }
  })

  it('testing = only sites with a testing deploy, prefixed testing.', () => {
    const origins = ssoReturnOrigins('testing')
    const testingSites = SITES.filter((s) => s.hasTesting && !s.external)
    expect(origins.length).toBe(testingSites.length)
    expect(new Set(origins)).toEqual(
      new Set(testingSites.map((s) => `https://testing.${s.prodHost}`)),
    )
    // a site without a testing env (mcp) never reaches the testing backend
    expect(origins).not.toContain('https://testing.mcp.agenticdeveloperhub.com')
    expect(origins.every((o) => o.startsWith('https://testing.'))).toBe(true)
  })

  it('staging = every staging-deploy site, prefixed staging.', () => {
    const origins = ssoReturnOrigins('staging')
    const stagingSites = SITES.filter((s) => s.hasStaging && !s.external)
    expect(origins.length).toBe(stagingSites.length)
    expect(origins).toContain('https://staging.agenticdevelopercookbook.com')
    expect(origins).toContain('https://staging.agenticdeveloperhub.com')
    expect(origins.every((o) => o.startsWith('https://staging.'))).toBe(true)
  })
})

describe('SITES registry', () => {
  it('has unique ids and excludes the backend', () => {
    const ids = SITES.map((s) => s.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids).not.toContain('backend')
  })
  it('every site has a label and a production host', () => {
    for (const s of SITES) {
      expect(s.label.length).toBeGreaterThan(0)
      expect(s.prodHost).toMatch(/\./)
    }
  })
})

describe('LISTED_SITES (the family roster)', () => {
  it('pins the full roster order (the authoritative sequence)', () => {
    expect(LISTED_SITES.map((s) => s.id)).toEqual([
      'bitbag',
      'hub',
      'cookbook',
      'projects',
      'narratives',
      'personaregistry',
      'devteam',
      'toolkit',
      'myagenticteams',
      'mcp',
      // <gen:order> managed by scaffold-sites.py — do not edit by hand
      'community',
      'support',
      'hub-help',
      'news',
      'academy',
      'dashboards',
      'personas',
      'communities',
      'ecosystems',
      'registries',
      'storage',
      'customers',
      'products',
      'billing',
      'domains',
      'authentication',
      'sites',
      'devices',
      'notifications',
      'knowledgebases',
      'tools',
      'teamregistry',
      'teambuilder',
      'codereviews',
      'personabuilder',
      'research',
      'consultants',
      'orgs',
      'notebook',
      'integrations',
      'games',
      'gamification',
      'store',
      'stores',
      'testing',
      'registry',
      'docs',
      'messaging',
      'messages',
      'shipr',
      // </gen:order>
      'fishlamp',
      'fishlampdesign',
      'status',
      'admin',
      'builds',
    ])
  })
  it('lists admin + status but still hides the unlisted registry entries', () => {
    const ids = LISTED_SITES.map((s) => s.id)
    expect(ids).toContain('admin')
    expect(ids).toContain('status')
    // `consulting`, not `messaging`: this named messaging until 2026-08-22, when it
    // stopped being an in-hub-only feature and became a deck with a domain. The
    // assertion is about `listed: false` being honoured at all, so it needs an id that
    // still IS one — the folded sites are the lasting example.
    expect(ids).not.toContain('consulting')
  })
  it('includes the new mcp entry', () => {
    expect(LISTED_SITES.map((s) => s.id)).toContain('mcp')
    expect(getSite('mcp')?.prodHost).toBe('mcp.agenticdeveloperhub.com')
  })
  it('puts bitbag first, set apart as its own top section', () => {
    const first = LISTED_SITES[0]!
    expect(first.id).toBe('bitbag')
    expect(first.prodHost).toBe('bitbag.ai')
    // the family entry after bitbag opens a new section with a divider
    expect(LISTED_SITES[1]!.dividerBefore).toBe(true)
  })
  it('keeps the folded sites registered but out of the switcher', () => {
    // education → academy, recipes → cookbook, consulting → the studio brand
    // (portfolio pruning): still registered (headers resolve, /details serve, SSO
    // origins unchanged), but delisted from the switcher + footer. Contrast the
    // retired Agentic Developer Studio, which was DELETED outright rather than
    // folded — see the dead-domain test below.
    const ids = LISTED_SITES.map((s) => s.id)
    for (const folded of ['education', 'recipes', 'consulting'] as const) {
      expect(getSite(folded), `${folded} stays registered`).toBeDefined()
      expect(getSite(folded)!.listed).toBe(false)
      expect(ids).not.toContain(folded)
    }
  })
  it('has no trace of the retired studio site, on either dead domain', () => {
    // Agentic Developer Studio was not folded like the sites above — the app was
    // deleted and the brand replaced by FishLamp Design, so nothing in the family
    // should still know either host. Both domains are dead: nothing redirects
    // them at fishlamp.com. Pinned because the registry is what drives the
    // generated route map, the switcher, the footer interlinks AND the OAuth
    // return-origin allowlist — a leftover entry would quietly re-add a dead
    // origin to all four.
    for (const dead of ['agenticdeveloper.studio', 'agenticdevelopmentstudio.com'] as const) {
      expect(SITES.map((s) => s.prodHost), dead).not.toContain(dead)
      for (const env of ['production', 'staging', 'testing'] as const) {
        expect(ssoReturnOrigins(env).join('|'), `${dead} in ${env}`).not.toContain(dead)
      }
    }
  })
  it('resolves consulting per-env: prod/staging/testing all direct, no env leak', () => {
    const consulting = getSite('consulting')!
    expect(buildSiteHref(consulting, 'agenticdeveloperhub.com', '/')).toBe(
      'https://agenticdeveloperconsulting.com/',
    )
    expect(buildSiteHref(consulting, 'staging.agenticdeveloperhub.com', '/')).toBe(
      'https://staging.agenticdeveloperconsulting.com/',
    )
    // consulting now has a testing env → testing resolves directly (no staging fallback)
    expect(buildSiteHref(consulting, 'testing.agenticdeveloperhub.com', '/')).toBe(
      'https://testing.agenticdeveloperconsulting.com/',
    )
  })
  it('features FishLamp Design (name-only, divider) ahead of the status + admin section', () => {
    const ids = LISTED_SITES.map((s) => s.id)
    const fishlamp = ids.indexOf('fishlamp')
    const admin = ids.indexOf('admin')
    const status = ids.indexOf('status')
    // the studio brand comes before the trailing console section, which the one
    // PUBLIC console heads (see the comment on its registry entry)
    expect(fishlamp).toBeLessThan(status)
    expect(status).toBeLessThan(admin)
    const fishlampDef = getSite('fishlamp')!
    expect(fishlampDef.dividerBefore).toBe(true)
    // `featured` marks it as the brand the family sits under. Nothing renders it
    // yet (see SiteDef.featured), so this pins the marker's location, not any
    // visual behavior.
    expect(fishlampDef.featured).toBe(true)
    // FishLamp carries a description — the overview popover shows one per row.
    expect(fishlampDef.description).toBeTruthy()
    expect(getSite('status')?.dividerBefore).toBe(true)
  })
  it('resolves the external FishLamp domains directly in every env (no env prefix)', () => {
    // fishlamp.com has no staging/testing tier, so hostForEnv falls all the way
    // back to the production host — a testing build must still link the real site,
    // never an invented testing.fishlamp.com.
    for (const id of ['fishlamp', 'fishlampdesign'] as const) {
      const site = getSite(id)!
      expect(site.external).toBe(true)
      for (const host of [
        'agenticdeveloperhub.com',
        'staging.agenticdeveloperhub.com',
        'testing.agenticdeveloperhub.com',
      ]) {
        expect(buildSiteHref(site, host, '/')).toBe(`https://${site.prodHost}/`)
      }
    }
  })
  it('ends with the status + admin + builds console section', () => {
    const ids = LISTED_SITES.map((s) => s.id)
    // status heads the block, not admin: it is the one console anyone may read, and
    // it carries the section's `dividerBefore`/`sectionLabel`. The two below it are
    // `adminOnly`, so they are absent from FOOTER_SITES entirely — a section head
    // that disappears from the overview would leave the rest of the block unlabelled.
    expect(ids[ids.length - 1]).toBe('builds')
    expect(ids[ids.length - 2]).toBe('admin')
    expect(ids[ids.length - 3]).toBe('status')
  })
})

describe('MAIN_SITE_IDS / MARKETING_SITE_IDS (dev site-menu families)', () => {
  // The Next app folders under frontend/src/sites/ are the source of truth for the two
  // families TAKEN TOGETHER; the arrays must cover them exactly so a newly-scaffolded
  // site can't silently drop out of the dev site menu.
  //
  // Until 2026-08-04 the families were two DIRECTORIES (frontend/src/main/ and
  // frontend/src/marketing/), so each array could be held against its own folder. The
  // sites now share one directory, and which family a site belongs to is a fact about
  // the registry alone — nothing on disk can confirm it, so the scan is checked against
  // the union. Neither array can drop a site or invent one; which of the two holds it
  // is pinned by the no-dupes/no-overlap test below.
  //
  // Finding frontend/src is not a counted hop, and the previous `../../../..` is why:
  // this package moved into the agentictoolkit submodule, and four levels up from its
  // new home is `<toolkit>/packages/web`, which holds none of adh's site folders.
  // It did not fail loudly at first glance either — the sibling siteRoutes.test.ts hit
  // the identical anchor and passed VACUOUSLY over an empty scan (349d1db); these two
  // only went red because readdirSync throws where that one's walk shrugged.
  //
  // Walking up to the marker, and skipping when it is absent, is the same shape
  // landingTypeScale.test.ts uses in @agentic-toolkit/adh — deliberately re-stated here
  // rather than shared, because a test-only helper is not worth adding to either
  // package's public surface to reach across the boundary between them.
  //
  // Absent means one thing only: the toolkit checked out standalone, which is what its
  // own web-tests.yml does. adh's ci.yml runs this suite from inside the adh checkout
  // ("Toolkit unit tests"), where the families are present and both assertions run — so
  // the guard still fires in the repository whose folders it is about.
  //
  // The marker is frontend/src's OWN manifest, identified by name. It was
  // `next-config-base.mjs` until that file was split into `@agentic-toolkit/adh-next-config`
  // and deleted — at which point this walk returned null in an adh checkout too, and the
  // whole assertion self-skipped GREEN in the one repository it is about. That is the
  // failure this marker has to be chosen against: a sentinel that is deleted takes the
  // test with it silently. `frontend/src/package.json` is the pnpm workspace root every
  // site installs from, so it cannot be deleted without the fleet ceasing to build, and
  // the `name` check is what stops the walk stopping early at the toolkit's own
  // `packages/web/package.json` on the way up.
  const adhFrontendSrc = (): string | null => {
    let dir = dirname(fileURLToPath(import.meta.url))
    for (;;) {
      const manifest = resolve(dir, 'package.json')
      if (existsSync(manifest)) {
        try {
          // Two repos hold site folders now — adh's `adh-websites` and adhmarketing's
          // `adhmarketing-websites` — and this suite runs from inside both. The suffix
          // is the marker, not a repo name, so a third checkout needs no edit here.
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
  const websitesDir = adhFrontendSrc()
  const STANDALONE = websitesDir === null
  /** Does this checkout's sites workspace DECLARE that it holds no site at all?
   *
   *  Read from the same manifest the walk above anchors on, so the claim lives with
   *  the workspace it is about rather than in a list of repo names here.
   *
   *  This exists because since 2026-08-31 an empty walk has two meanings and the
   *  tree cannot tell them apart. `registry` was the last site to leave adh, so
   *  `frontend/websites/` is a real sites workspace holding a tools package and no
   *  app — while an empty walk is also exactly what a moved layout or a
   *  `siteIdForDir` that stopped answering looks like, which is the failure the
   *  `> 0` guards below were written against. A blanket floor cannot keep the second
   *  meaning without failing the first, and dropping the floor loses the guard
   *  entirely, so the repo says which one it is.
   *
   *  It is asserted EXACTLY, not merely tolerated: a workspace that declares no
   *  sites and then walks up some is either a repo that has gained a site (delete
   *  the declaration) or a walk that has started answering for something it should
   *  not, and both need saying out loud. */
  const declaresNoSites = (): boolean => {
    if (websitesDir === null) return false
    try {
      const manifest = JSON.parse(
        readFileSync(resolve(websitesDir, 'package.json'), 'utf8'),
      )
      return manifest?.adhFleet?.sites === 'none'
    } catch {
      return false // unreadable manifest is not a declaration
    }
  }
  const NO_SITES = declaresNoSites()
  // Build/tooling directories that can sit beside the real site apps — excluded so
  // the guard tracks site folders, not filesystem noise (a stray `.next` or
  // `node_modules` must not false-fail a test about the site registry).
  // `external` holds the submodule checkouts — including this toolkit's own demo app
  // (`websites/site/`), which is a Next app and is not a fleet site; `tools` is the
  // shared ESLint toolchain package. Both would otherwise be walked into.
  const NON_SITE_DIRS = new Set([
    'node_modules', 'dist', 'build', '.next', '.turbo', 'external', 'tools',
  ])
  //
  // Two things about the layout this walks, both new since the folders were renamed:
  // sites sit at TWO depths (adh groups most of its under `marketing/`, `adh/`,
  // `placeholder/`, with eight directly under the workspace; adhmarketing has no group
  // tier at all), and a folder is named for the DOMAIN its site serves, not for the id
  // — `agenticdeveloperbilling/` builds `billing`. `siteIdForDir` owns that join.
  const siteDirs = (root: string): string[] =>
    readdirSync(root)
      .filter((name) => !name.startsWith('.') && !NON_SITE_DIRS.has(name))
      .filter((name) => statSync(resolve(root, name)).isDirectory())
      // A real site folder is a Next app (has app/). Excludes data-only dirs and the
      // shared `tools/` toolchain package, and makes a GROUP directory recognisable:
      // it has no app/ of its own, so it is descended into instead.
      .flatMap((name) =>
        existsSync(resolve(root, name, 'app'))
          ? [name]
          : siteDirs(resolve(root, name)),
      )

  const siteFolders = (): SiteId[] => {
    const found = siteDirs(websitesDir as string)
    // A folder that resolves to no registry id is the defect this guard exists for:
    // a scaffolded site that never joined the fleet. Named individually, because
    // dropping it silently is how the whole scan goes vacuous.
    for (const name of found) {
      expect(siteIdForDir(name), `${name}/ is a Next app with no registry entry`).toBeTruthy()
    }
    return found.map((name) => siteIdForDir(name)!).sort()
  }

  // Family sites whose Next app is in ITS OWN REPO rather than under adh's
  // `frontend/src/sites/`. Both left on 2026-08-15 and neither left the fleet: their
  // registry rows, `MAIN_SITE_IDS` membership, story tiers, menu rows and SSO are all
  // unchanged, and only the source tree moved (agenticdevelopmentstudio/bitbagwebsite,
  // agenticdevelopmentstudio/myagenticteamswebsite).
  //
  // Listed HERE and not in registry.ts on purpose. "Where the source is checked out" is
  // a fact about adh's directory layout, not about the fleet — from inside either of
  // those two repos the same site IS local — so putting it in the registry would ship a
  // claim that is false in two of the three repos that consume it. This constant exists
  // only to keep the guard below honest, and it goes away with the guard on the day
  // adh's last site folder leaves.
  //
  // ONE DIRECTION, and the loss is worth stating. This used to be an equality: the two
  // family arrays had to equal the folders on disk plus a two-name list of sites built
  // in their own repos. That held while one checkout could see every folder. It cannot
  // now — the marketing sites moved to adhmarketing, so from adh 31 ids have no folder
  // and from adhmarketing the other 27 don't, and the "built elsewhere" list would have
  // to be a different 30-odd names per repo. A list like that is exactly `union minus
  // what I can see`, which asserts nothing.
  //
  // So the half that survives is the half a single checkout can prove: every folder it
  // CAN see is a registered site (in `siteFolders`, per folder). The half that left —
  // a registry entry whose app is built nowhere at all — needs both trees at once, and
  // belongs to CI, which is the only place that has them.
  it.skipIf(STANDALONE)(
    'every site folder in this checkout is a registered family site',
    () => {
      const found = siteFolders()
      // Non-vacuity: an empty scan is what a wrong anchor looks like, and it is exactly
      // how the sibling test passed while checking nothing — unless the workspace says
      // it holds no site, in which case empty is the answer and is asserted as one.
      if (NO_SITES) {
        expect(
          found.length,
          `${websitesDir}'s manifest declares adhFleet.sites "none"`,
        ).toBe(0)
        return
      }
      expect(found.length).toBeGreaterThan(0)
      const family = new Set<string>([...MAIN_SITE_IDS, ...MARKETING_SITE_IDS])
      for (const id of found) {
        expect(family.has(id), `${id} has a folder here but is in neither family array`).toBe(true)
      }
    },
  )
  it('every family id is a real registry site, with no dupes or cross-family overlap', () => {
    const all = [...MAIN_SITE_IDS, ...MARKETING_SITE_IDS]
    expect(new Set(all).size).toBe(all.length) // no dupes within or across the two lists
    for (const id of all) expect(getSite(id), `${id} must be a registry site`).toBeTruthy()
  })

  // `workspaceRoute` says the site menu has somewhere to carry a workspace TO, and a
  // wrong value is a 404 the menu serves confidently. So it is held to the ROUTE TREE,
  // the only thing that actually decides whether the path resolves. Same anchor + skip
  // as the family-folder guard above: absent marker ⇒ standalone toolkit checkout.
  //
  // There is one shape on disk now — `app/[workspace]` — so the walk is a presence test
  // rather than a shape test. `'hub'` vs `'root'` is NOT visible here and must not be
  // guessed from the tree: both mount the same directory, and the value distinguishes
  // who can read a slug back out of a path (see the field's own doc). It is asserted
  // literally below.
  it.skipIf(STANDALONE)('workspaceRoute matches the route tree for every site folder', () => {
    const root = websitesDir as string
    // Keyed by id, since that is what `siteFolders` returns — the folder it came from
    // is recovered here rather than re-derived, because the walk already knows it.
    const dirOf = new Map(siteDirs(root).map((d) => [siteIdForDir(d), d] as const))
    const hasWorkspaceOnDisk = (id: string): boolean => {
      const dir = dirOf.get(id as SiteId)
      if (dir === undefined) return false
      const inGroup = readdirSync(root).find((g) =>
        existsSync(resolve(root, g, dir, 'app')),
      )
      const base = inGroup ? resolve(root, inGroup, dir) : resolve(root, dir)
      return existsSync(resolve(base, 'app', '[workspace]'))
    }
    const folders = siteFolders()
    if (NO_SITES) {
      expect(
        folders.length,
        `${websitesDir}'s manifest declares adhFleet.sites "none"`,
      ).toBe(0)
      return
    }
    expect(folders.length).toBeGreaterThan(0) // non-vacuity, as above
    // Non-vacuity for the assertion itself: if NO folder had a workspace route the
    // loop below would pass while proving nothing. Conditional for the same reason
    // its mirror below is -- a repo whose sites are ALL workspace-less has no
    // positive example to offer, and agenticpersonaregistrywebsite is the first:
    // its one site's first segment is a persona handle, so there is nowhere to
    // carry a workspace to. Demanding one there would be demanding a route the
    // site is defined by not having.
    if (folders.some((id) => getSite(id)!.workspaceRoute !== undefined)) {
      expect(folders.filter(hasWorkspaceOnDisk).length).toBeGreaterThan(0)
    }
    // …and the other way: a run where EVERY folder had one would equally pass while
    // proving the absent case nothing. `status` and `admin` are the sites without —
    // both in adh, and adhmarketing's 31 all carry a workspace, so this half is only
    // exercisable in a checkout that holds one. Asserted where it exists rather than
    // demanding every repo contain a counterexample it has no reason to have.
    if (folders.some((id) => getSite(id)!.workspaceRoute === undefined)) {
      expect(folders.filter((n) => !hasWorkspaceOnDisk(n)).length).toBeGreaterThan(0)
    }

    for (const id of folders) {
      const site = getSite(id)
      if (!site) continue // covered by the family-folder guard above
      expect(
        site.workspaceRoute !== undefined,
        `${id}: registry vs route tree`,
      ).toBe(hasWorkspaceOnDisk(id))
    }

    // The hub is the one site whose value is not 'root', and the reason is not its route
    // — it is that its non-slug first segments are its own. Stated literally so a change
    // is a deliberate edit here, not a silent re-derivation from a tree that cannot see it.
    expect(hub.workspaceRoute).toBe('hub')
    expect(SITES.filter((s) => s.workspaceRoute === 'hub').map((s) => s.id)).toEqual(['hub'])
    // The trap this field exists to avoid: a /home is not a workspace route. `hub-help`
    // has neither, and `bitbag` has a workspace-less site with no /home either — keying
    // the carry off `hasHome` would send a switch to a 404 on any site with one and no
    // `[workspace]`, which is why this is stamped from the tree above rather than derived.
    expect(getSite('hub-help')!.hasHome).toBe(false)
    expect(getSite('hub-help')!.workspaceRoute).toBeUndefined()
    expect(getSite('status')!.workspaceRoute).toBeUndefined()
    // personaregistry is workspace-less for a DIFFERENT reason than the three above, and
    // it is the only site where the reason is structural: Next allows one dynamic name per
    // level, and this site's root is spent on `[slug]` — the public persona handle that is
    // the whole point of the site — so `app/[workspace]` cannot also live there. Named
    // literally because the walk above sees only the absent directory, not the collision
    // that forces it, and re-adding a workspace here is a route the framework refuses.
    expect(getSite('personaregistry')!.workspaceRoute).toBeUndefined()
    expect(getSite('personaregistry')!.hasHome).toBe(false)

    // Two sites the walk above cannot reach in ANY checkout. It enumerates FOLDERS, so
    // when bitbag and myagenticteams moved to their own repos they stopped being
    // subjects of this test — silently, with no failure and no note. That shrink is now
    // the normal case rather than the exception: since the marketing split, no single
    // checkout holds every folder, and these two are simply the pair that predates it. Their `workspaceRoute` values are still
    // shipped by this registry and still consumed by hub and fleet routing, so a wrong
    // one would ship green from here and surface as a broken route on the other repo's
    // deploy. Asserted LITERALLY, like `hub` above and for the same reason: the tree
    // that would otherwise decide is not in this checkout.
    for (const id of ['bitbag', 'myagenticteams'] as const) {
      expect(getSite(id), `${id} must still be a registry site`).toBeTruthy()
    }
    expect(getSite('myagenticteams')!.workspaceRoute).toBe('root')
    expect(getSite('myagenticteams')!.hasHome).toBe(true)
    expect(getSite('bitbag')!.workspaceRoute).toBeUndefined()
    expect(getSite('bitbag')!.hasHome).toBe(false)
  })

})

describe('siteWorkspaceHref (cross-site workspace destination)', () => {
  // The convergence, asserted as ONE shape rather than three: the two sites that used to
  // differ are named here on purpose, because `/home/acme` and `/acme/home` are what this
  // returned for them and each is still a live path on the site — a wrong answer would be
  // a plausible one, not a 404 that shows up on the first click.
  it('builds `/<slug>` for every site with a workspace, including the two that once differed', () => {
    expect(siteWorkspaceHref(getSite('storage')!, 'acme')).toBe('/acme')
    expect(siteWorkspaceHref(cookbook, 'acme')).toBe('/acme')
    expect(siteWorkspaceHref(hub, 'acme')).toBe('/acme')
  })
  it('returns undefined when the site has no workspace route, so the caller falls back', () => {
    expect(siteWorkspaceHref(getSite('bitbag')!, 'acme')).toBeUndefined()
    expect(siteWorkspaceHref(getSite('status')!, 'acme')).toBeUndefined()
    expect(siteWorkspaceHref(hubHelp, 'acme')).toBeUndefined()
  })
  it('returns undefined for an empty slug rather than minting `//`', () => {
    expect(siteWorkspaceHref(getSite('storage')!, '')).toBeUndefined()
    expect(siteWorkspaceHref(cookbook, '')).toBeUndefined()
  })
})

describe('siteWorkspaceSlug (the inverse: which workspace a path names)', () => {
  it('reads the slug back out of the path siteWorkspaceHref built', () => {
    for (const id of ['storage', 'cookbook'] as const) {
      const site = getSite(id)!
      expect(siteWorkspaceSlug(site, siteWorkspaceHref(site, 'acme')!), id).toBe('acme')
    }
  })
  it('reads a deeper path inside the workspace, not just its root', () => {
    expect(siteWorkspaceSlug(getSite('storage')!, '/acme/buckets/logs')).toBe('acme')
    expect(siteWorkspaceSlug(cookbook, '/acme/recipes')).toBe('acme')
  })
  // Not an oversight and not a shape difference — the hub builds `/acme` like everyone
  // else. Reading one back needs the set of first segments that AREN'T slugs, and the hub's
  // is its own (HUB_ROUTE_SEGMENTS): answering from SITE_LANDING_SEGMENTS would read
  // `/login` and `/explore` as workspaces. It refuses rather than switching on the set
  // because a hub path needs more than one — `/home` and `/settings` carry no slug and
  // resolve to the visitor's own — so hubWorkspaceSlug owns the whole answer and useSiteMenu
  // asks it directly.
  it('refuses the hub rather than parsing it with the template’s landing set', () => {
    expect(siteWorkspaceSlug(hub, '/acme/knowledgebases/facts')).toBeNull()
    expect(siteWorkspaceSlug(hub, '/login')).toBeNull()
  })
  it('returns null on a landing path, so nothing public is carried as a workspace', () => {
    const storage = getSite('storage')!
    expect(siteWorkspaceSlug(storage, '/')).toBeNull()
    for (const seg of SITE_LANDING_SEGMENTS) {
      expect(siteWorkspaceSlug(storage, `/${seg}`), seg).toBeNull()
      // …and everything below it: `/details/topic` is a details page, not workspace
      // `details` — the first segment is what decides.
      expect(siteWorkspaceSlug(storage, `/${seg}/anything`), seg).toBeNull()
    }
  })
  it('returns null on `/home`, which is the redirect signal and carries no slug', () => {
    expect(siteWorkspaceSlug(cookbook, '/home')).toBeNull()
    expect(siteWorkspaceSlug(getSite('research')!, '/home')).toBeNull()
  })
  it('returns null for a site with no workspace route at all', () => {
    expect(siteWorkspaceSlug(getSite('bitbag')!, '/acme')).toBeNull()
    expect(siteWorkspaceSlug(getSite('status')!, '/acme')).toBeNull()
  })
  // The deliberate one: an unknown first segment on a 'root' site READS as a slug,
  // because only the static routes can be listed. It is no longer repaired on arrival —
  // useWorkspaceRoute used to swap an unresolvable slug for the visitor's real workspace,
  // and the shared shell now 404s a settled list with no match instead, because landing
  // silently in a DIFFERENT workspace is a worse answer than being told the address is
  // wrong. `/not-a-real-page` was already a wrong address either way; what this costs is
  // paid by a segment that is a real page and missing from the set, which is precisely
  // what the lockstep case below refuses to let happen.
  it('reads an unknown segment as a slug rather than refusing', () => {
    expect(siteWorkspaceSlug(getSite('storage')!, '/not-a-real-page')).toBe('not-a-real-page')
  })

  // LOCKSTEP. `SITE_LANDING_SEGMENTS` is a hand-written literal in registry.ts (see the
  // bundle reason at the import above), so nothing but this stops it drifting from the
  // routes it claims to name. `gen-site-routes.py --check` holds SITE_ROUTES to the app
  // trees in CI, which makes it a real oracle rather than a second copy of the same guess:
  // a page added at a 'root' site's top level fails HERE until it is listed there.
  //
  // No standalone skip, unlike the route-tree walks above: both sides are committed
  // files inside this package, so nothing here reaches for adh's `frontend/src/sites`.
  it("covers every static top-level route of every 'root' site", () => {
    const roots = SITES.filter((s) => s.workspaceRoute === 'root')
    expect(roots.length).toBeGreaterThan(0) // non-vacuity
    const seen = new Set<string>()
    for (const site of roots) {
      for (const route of SITE_ROUTES[site.id] ?? []) {
        const seg = route.split('/').filter(Boolean)[0]
        // `/` has no segment, and the workspace's own `[workspace]` IS the slug.
        if (!seg || seg.startsWith('[')) continue
        seen.add(seg)
        expect(
          SITE_LANDING_SEGMENTS.has(seg),
          `${site.id} serves /${seg}, so SITE_LANDING_SEGMENTS must list it — otherwise ` +
            `the site menu carries "${seg}" to the next site as a workspace slug`,
        ).toBe(true)
      }
    }
    // …and the other way, so a retired page doesn't leave a segment listed here
    // forever, quietly refusing to carry a workspace whose slug happens to match it.
    expect([...SITE_LANDING_SEGMENTS].sort()).toEqual([...seen].sort())
  })
})

describe('HUB_ROUTE_SEGMENTS (the same question, asked about the other root)', () => {
  // LOCKSTEP, the same shape as the case above and for the same reason: a hand-written
  // literal, so `gen-site-routes.py --check` holding SITE_ROUTES to the app trees is the only
  // thing that can keep it honest. What it guards is the header's in-hub mode — this set is
  // what `hubWorkspacePath.ts` reads to tell a hub PAGE from a workspace slug.
  it("equals the hub's static top-level routes, in both directions", () => {
    const seen = new Set<string>()
    for (const route of SITE_ROUTES['hub'] ?? []) {
      const seg = route.split('/').filter(Boolean)[0]
      // `/` has no segment, and `[workspace]` IS the slug.
      if (!seg || seg.startsWith('[')) continue
      seen.add(seg)
      expect(
        HUB_ROUTE_SEGMENTS.has(seg),
        `the hub serves /${seg}, so HUB_ROUTE_SEGMENTS must list it — otherwise the header ` +
          `reads that page as a workspace and puts the signed-in workspace menu on it`,
      ).toBe(true)
    }
    expect(seen.size).toBeGreaterThan(0) // non-vacuity
    // …and the other way, which is the direction the mint-time list got wrong: a word listed
    // here that the hub does not route is a slug somebody may legitimately hold, read as a
    // page — the header then swaps the visitor's own slug into every feature link, silently.
    expect([...HUB_ROUTE_SEGMENTS].sort()).toEqual([...seen].sort())
  })
})

describe('SITE_CATEGORIES (menu + overview grouping)', () => {
  it('covers every overview site exactly once (no orphans, no dupes)', () => {
    const inCats = SITE_CATEGORIES.flatMap((c) => c.ids)
    expect(new Set(inCats).size).toBe(inCats.length) // no dupes
    const listed = new Set(LISTED_SITES.map((s) => s.id))
    // every categorized id is a real listed site
    for (const id of inCats) expect(listed.has(id)).toBe(true)
    // FOOTER_SITES, not LISTED_SITES: the overview renders that roster, and the
    // admin-only consoles are filtered out of it upstream, so categorizing them
    // would declare membership of a group that can never render.
    const grouped = groupSitesByCategory(FOOTER_SITES)
    expect(grouped.some((g) => g.label === 'More')).toBe(false)
    expect(grouped.flatMap((g) => g.sites).length).toBe(FOOTER_SITES.length)
  })
  it('leaves the admin-only consoles uncategorized', () => {
    const inCats = new Set(SITE_CATEGORIES.flatMap((c) => c.ids))
    for (const s of SITES.filter((s) => s.adminOnly)) expect(inCats.has(s.id)).toBe(false)
  })
  it('mirrors the site menu: same labels, same order, Hire last', () => {
    const labels = groupSitesByCategory(FOOTER_SITES).map((g) => g.label)
    expect(labels).toEqual(['Hub', 'Learn', 'Plan', 'Build', 'Personas', 'Products', 'Hire'])
  })
})

describe('FOOTER_SITES (SEO interlinks)', () => {
  it('pins the full footer order (roster order minus non-crawlable mcp)', () => {
    expect(FOOTER_SITES.map((s) => s.id)).toEqual([
      'bitbag',
      'hub',
      'cookbook',
      'projects',
      // narratives' prod domain is live, so it is a footer interlink now
      'narratives',
      'personaregistry',
      'devteam',
      'toolkit',
      'myagenticteams',
      // <gen:order> managed by scaffold-sites.py — do not edit by hand
      'community',
      'support',
      'hub-help',
      'news',
      'academy',
      'dashboards',
      'personas',
      'communities',
      'ecosystems',
      'registries',
      'storage',
      'customers',
      'products',
      'billing',
      'domains',
      'authentication',
      'sites',
      'devices',
      'notifications',
      'knowledgebases',
      'tools',
      'teamregistry',
      'teambuilder',
      'codereviews',
      'personabuilder',
      'research',
      'consultants',
      'orgs',
      'notebook',
      'integrations',
      'games',
      'gamification',
      'store',
      'stores',
      'testing',
      'registry',
      'docs',
      'messaging',
      'messages',
      'shipr',
      // </gen:order>
      'fishlamp',
      'fishlampdesign',
      // admin and builds are adminOnly — registry sites, and on the roster, but
      // never in this one.
      'status',
    ])
  })
  it('excludes the non-HTML mcp endpoint and the delisted sites, but keeps the content sites', () => {
    const ids = FOOTER_SITES.map((s) => s.id)
    expect(ids).not.toContain('mcp')
    expect(ids).toContain('hub')
    expect(ids).toContain('cookbook')
    expect(ids).toContain('narratives')
    // both FishLamp Design domains are interlinked from every footer
    expect(ids).toContain('fishlamp')
    expect(ids).toContain('fishlampdesign')
  })
  it('leads with bitbag and ends with FishLamp, then status', () => {
    const ids = FOOTER_SITES.map((s) => s.id)
    expect(ids[0]).toBe('bitbag')
    expect(ids.indexOf('fishlamp')).toBeLessThan(ids.indexOf('status'))
    expect(ids[ids.length - 1]).toBe('status')
  })
  it('drops the admin-only consoles, which stay on the roster', () => {
    const ids = FOOTER_SITES.map((s) => s.id)
    expect(ids).not.toContain('admin')
    expect(ids).not.toContain('builds')
    expect(LISTED_SITES.map((s) => s.id)).toContain('admin')
    expect(LISTED_SITES.map((s) => s.id)).toContain('builds')
  })
  it('every footer site has a non-empty description for the overview popover', () => {
    for (const s of FOOTER_SITES) {
      expect(s.description, `${s.id} needs a description`).toBeTruthy()
    }
  })
  it('sectionLabels partition the overview into contiguous groups, first entry labelled', () => {
    // The first footer entry must open a group (no unlabelled lead), and each
    // labelled entry starts a new group — so the overview is fully grouped.
    expect(FOOTER_SITES[0]!.sectionLabel).toBeTruthy()
    const labels = FOOTER_SITES.filter((s) => s.sectionLabel).map((s) => s.sectionLabel)
    expect(labels).toEqual([
      'Core platform',
      'Developer platform',
      'Studio & consulting',
      'Operations',
    ])
  })
})

describe('HUB_FEATURE_SEGMENT (in-hub workspace switching)', () => {
  it('maps only real registry sites, to bare feature segments (one site per segment, except the documented products alias)', () => {
    const ids = new Set(SITES.map((s) => s.id))
    for (const id of Object.keys(HUB_FEATURE_SEGMENT)) {
      expect(ids.has(id as (typeof SITES)[number]['id']), `${id} must be a registry site`).toBe(true)
    }
    // Segments are unique per site, with exactly TWO documented aliases — both cases of one
    // hub pane genuinely being two sites' implementation:
    //   products — ecosystems are managed as PRODUCTS in the hub, so the ecosystems and products
    //              sites resolve to the same view;
    //   integrations — the `messaging` site is email & SMS integrations, whose hub surface has
    //              always been the integrations feature (a placeholder on its own domain).
    // The rail is keyed by SEGMENT, so an alias draws one row rather than two. Any OTHER
    // duplicate is a drift bug: two different features would be claiming one URL.
    const ALIASES: Record<string, string[]> = {
      products: ['ecosystems', 'products'],
      integrations: ['integrations', 'messaging'],
    }
    const bySegment = new Map<string, string[]>()
    for (const [id, seg] of Object.entries(HUB_FEATURE_SEGMENT)) {
      bySegment.set(seg!, [...(bySegment.get(seg!) ?? []), id])
    }
    for (const [seg, sites] of bySegment) {
      if (ALIASES[seg]) {
        expect(sites.sort()).toEqual(ALIASES[seg])
      } else {
        expect(sites, `segment '${seg}' must map exactly one site`).toHaveLength(1)
      }
      // a bare single segment, e.g. 'storage' — no leading slash, never nested
      expect(seg).toMatch(/^[a-z-]+$/)
    }
  })
  // The two aliases above are the reason SITE_FOR_HUB_SEGMENT needs a RULE, and a rule that is
  // only stated in a docstring is a rule that drifts. The map decides which of two sites a shared
  // segment is named after, and every rail row, glyph and blurb for that segment reads the
  // answer — so a silent flip (a re-ordered registry, a third site joining a segment) would
  // rename a live row with nothing failing. Pinned here, where the collisions themselves are.
  it('names the documented winner for each shared segment, and the site itself for the rest', () => {
    expect(SITE_FOR_HUB_SEGMENT.products).toBe('products')
    expect(SITE_FOR_HUB_SEGMENT.integrations).toBe('integrations')
    // The general rule the two above are instances of, stated over the whole map: when one of
    // the sites mapping to a segment is NAMED after it, that site wins; otherwise the segment
    // has no rightful owner and first-mapping-wins decides. Either way the winner must be a
    // site that actually maps there — resolving a segment to a site that renders somewhere
    // else is the drift this catches.
    //
    // Being a site id is NOT enough on its own, and `messaging` is why: the `messages` site
    // owns the `messaging` segment, while the site literally called `messaging` (email & SMS)
    // maps to `integrations`. The rule reads the mapping, never the name alone.
    const bySeg = new Map<string, string[]>()
    for (const [id, seg] of Object.entries(HUB_FEATURE_SEGMENT)) {
      bySeg.set(seg!, [...(bySeg.get(seg!) ?? []), id])
    }
    for (const [segment, siteId] of Object.entries(SITE_FOR_HUB_SEGMENT)) {
      const claimants = bySeg.get(segment) ?? []
      expect(claimants, `segment '${segment}' must resolve to a site that maps to it`).toContain(
        siteId,
      )
      if (claimants.includes(segment)) {
        expect(siteId, `'${segment}' is claimed by the site named after it`).toBe(segment)
      }
      expect(hubFeatureSegment(siteId), `${siteId} must map back to '${segment}'`).toBe(segment)
    }
  })
  // The fleet came home, so this is a CLASS assertion rather than a spot check: a site with a
  // workspace route of its own has an implementation the hub can mount, and the hub mounts all of
  // them. Written both ways so neither adding a site nor retiring one can leave the table behind.
  it('maps every site that has a workspace route, and only those', () => {
    // Two exclusions, both structural rather than editorial:
    //   hub — it IS the host; its own workspace is `/<slug>`, not a segment under it.
    //   myagenticteams — a full family member with a workspace route, built from its OWN repo
    //     since 2026-08-15 (see MAIN_SITE_IDS' note). Its model is not in
    //     @agentic-toolkit/adh-site-homes, so there is nothing here for the hub to import. Named
    //     rather than derived for the same reason that list names it: where a site's source sits
    //     is a fact about one checkout, and this file is shared by all of them.
    const NOT_MOUNTED: string[] = ['hub', 'myagenticteams']
    for (const s of SITES) {
      const expected = s.workspaceRoute !== undefined && !NOT_MOUNTED.includes(s.id)
      expect(
        hubFeatureSegment(s.id) !== undefined,
        `${s.id}: workspaceRoute=${String(s.workspaceRoute)} should${expected ? '' : ' not'} be mapped`,
      ).toBe(expected)
    }
  })
  it('does not map sites whose workspace is not a hub feature route', () => {
    // `cookbook` used to be in this list and is not any more — it has a workspace route, so its
    // workspace is now a hub route too. What is left is the sites that genuinely have none.
    // `api` was in this list and is dropped, not migrated: no site carries that id, so the
    // case asserted `undefined` about a site that does not exist and could never have failed.
    // Typing the ids as SiteId is what surfaced it — a phantom id is now a compile error.
    for (const id of ['hub', 'admin', 'status', 'bitbag', 'personaregistry'] as const satisfies readonly SiteId[]) {
      expect(hubFeatureSegment(id)).toBeUndefined()
    }
  })
  // What the table is FOR, now that nothing switches into a hub view: every segment
  // it names has to be recognized as a workspace segment, because that recognition is
  // how the menu knows a hub path has a slug to carry.
  it('contributes every segment to HUB_WORKSPACE_SEGMENTS', () => {
    const segs: string[] = Object.values(HUB_FEATURE_SEGMENT)
    expect(segs.length).toBeGreaterThan(0) // non-vacuity
    // Asserted against the SET, not `isHubWorkspacePath`: that predicate answers from
    // @agentic-toolkit/adh/site now, which this package cannot import (adh depends on
    // adh-registry, not the other way round). The set is what it reads anyway.
    for (const seg of segs) expect(HUB_WORKSPACE_SEGMENTS.has(seg), seg).toBe(true)
  })
})

describe('HUB_WORKSPACE_SEGMENTS', () => {
  it('holds no `home`: a workspace landing is the bare /<workspace>', () => {
    // The set is what useSiteMenu's routeHref prefixes with the active slug, so a `home` member
    // minted `/<slug>/home` — a URL the hub answers only by redirecting it back to `/<slug>`.
    // The hub's own reverse-lockstep test used to have to exempt this one entry by name.
    expect(HUB_WORKSPACE_SEGMENTS.has('home')).toBe(false)
    expect(HUB_WORKSPACE_SEGMENTS.has('products')).toBe(true)
  })
})
