import { describe, it, expect, vi, afterEach } from 'vitest'
import {
  buildDevToolsEntries,
  debugOptionsAvailable,
  debugOptionsHint,
  isDevEnv,
} from '../devToolsEntries'
import { type PopoverEntry, type RouteSection } from '@agentic-toolkit/adh/header'
import { type SiteEnv } from '@agentic-toolkit/adh-registry'

// The second half of the dev-tools dropdown: the "Routes" flyout + the "Debug
// Options" row. The safety property under test is that NEITHER can leak to an ordinary
// production visitor — while a signed-in adh admin (adminUnlocked) gets BOTH in
// every env, production included. Separately: the two rows read DIFFERENT envs
// on purpose (see devToolsEntries.ts): Routes follows the EFFECTIVE env, Debug
// the REAL one; the admin unlock bypasses both reads.

const routes: RouteSection[] = [
  { label: 'App', routes: [{ path: '/home' }, { path: '/' }] },
]

const build = (o: {
  effectiveEnv: SiteEnv | null
  realEnv: SiteEnv | null
  adminUnlocked?: boolean
  override?: SiteEnv | null
  routes?: RouteSection[]
  onOpenDebug?: () => void
}): PopoverEntry[] =>
  buildDevToolsEntries({
    routes: 'routes' in o ? o.routes : routes,
    effectiveEnv: o.effectiveEnv,
    realEnv: o.realEnv,
    adminUnlocked: o.adminUnlocked ?? false,
    override: o.override ?? null,
    pathname: '/home',
    onOpenDebug: o.onOpenDebug ?? (() => {}),
  })

const labels = (entries: PopoverEntry[]): string[] =>
  entries.map((e) => (e.kind === 'topic' ? e.label : e.item.label))

const debugLeaf = (entries: PopoverEntry[]) =>
  entries.find((e): e is Extract<PopoverEntry, { kind: 'leaf' }> => e.kind === 'leaf')

const debugRow = (entries: PopoverEntry[]) => debugLeaf(entries)?.item

describe('isDevEnv', () => {
  it('allowlists the three dev envs and nothing else', () => {
    expect(['local', 'testing', 'staging'].every((e) => isDevEnv(e as SiteEnv))).toBe(true)
    expect(isDevEnv('production')).toBe(false)
    // Unknown/absent env is fail-safe — hidden, never shown by accident.
    expect(isDevEnv(null)).toBe(false)
  })
})

describe('debugOptionsAvailable — the gate both Debug Options doors read', () => {
  it('offers it in each dev env, and to an admin anywhere', () => {
    for (const env of ['local', 'testing', 'staging'] as SiteEnv[]) {
      expect(debugOptionsAvailable({ realEnv: env, adminUnlocked: false })).toBe(true)
    }
    expect(debugOptionsAvailable({ realEnv: 'production', adminUnlocked: true })).toBe(true)
  })

  it('withholds it from a non-admin in production, and when the env is unknown', () => {
    expect(debugOptionsAvailable({ realEnv: 'production', adminUnlocked: false })).toBe(false)
    expect(debugOptionsAvailable({ realEnv: null, adminUnlocked: false })).toBe(false)
  })
})

describe('debugOptionsHint', () => {
  it('reads "Sim: prod" only while production is being simulated', () => {
    expect(debugOptionsHint('production')).toBe('Sim: prod')
    expect(debugOptionsHint('staging')).toBeUndefined()
    expect(debugOptionsHint(null)).toBeUndefined()
  })
})

describe('buildDevToolsEntries', () => {
  it('shows both rows in each dev env', () => {
    for (const env of ['local', 'testing', 'staging'] as SiteEnv[]) {
      expect(labels(build({ effectiveEnv: env, realEnv: env }))).toEqual(['Routes', 'Debug Options'])
    }
  })

  it('shows NOTHING in production to a non-admin — the safety property', () => {
    expect(build({ effectiveEnv: 'production', realEnv: 'production' })).toEqual([])
  })

  it('shows nothing before the host is known (SSR / first render)', () => {
    expect(build({ effectiveEnv: null, realEnv: null })).toEqual([])
  })

  it('shows BOTH rows to an admin in production — the admin unlock', () => {
    expect(
      labels(build({ effectiveEnv: 'production', realEnv: 'production', adminUnlocked: true })),
    ).toEqual(['Routes', 'Debug Options'])
  })

  it('shows both rows to an admin even before the host is known', () => {
    // The admin unlock reads no env at all, so it needn't wait for the client host.
    expect(labels(build({ effectiveEnv: null, realEnv: null, adminUnlocked: true }))).toEqual([
      'Routes',
      'Debug Options',
    ])
  })

  it('keeps Routes for an admin while SIMULATING production', () => {
    // Simulating production previews what visitors get; an admin never stops being
    // an admin, so the unlock outranks the effective-env read.
    const entries = build({
      effectiveEnv: 'production',
      realEnv: 'local',
      override: 'production',
      adminUnlocked: true,
    })
    expect(labels(entries)).toEqual(['Routes', 'Debug Options'])
    expect(debugRow(entries)?.description).toBe('Sim: prod')
  })

  it('while SIMULATING production, hides Routes but KEEPS Debug Options reachable', () => {
    // The asymmetry that makes the simulation reversible: Routes follows the
    // effective env (so the preview is honest), Debug follows the real one (so the
    // developer can always get back out).
    const entries = build({ effectiveEnv: 'production', realEnv: 'local', override: 'production' })
    expect(labels(entries)).toEqual(['Debug Options'])
    // ...and the row advertises the simulation, as the old header pill did. `blurb` is
    // what makes a leaf's description actually render (NavigationPopover only shows it
    // when set), so assert BOTH — a description without it would be silently invisible.
    expect(debugRow(entries)?.description).toBe('Sim: prod')
    expect(debugLeaf(entries)?.blurb).toBe(true)
  })

  it('leaves the Debug row unadorned when not simulating', () => {
    const entries = build({ effectiveEnv: 'local', realEnv: 'local' })
    // The label stays exactly "Debug Options" either way — only the hint changes.
    expect(debugRow(entries)?.label).toBe('Debug Options')
    expect(debugRow(entries)?.description).toBeUndefined()
  })

  it('omits Routes when the site supplied none (or an empty map)', () => {
    expect(labels(build({ effectiveEnv: 'local', realEnv: 'local', routes: undefined }))).toEqual([
      'Debug Options',
    ])
    expect(labels(build({ effectiveEnv: 'local', realEnv: 'local', routes: [] }))).toEqual([
      'Debug Options',
    ])
  })

  it('puts both rows in ONE section, so no divider splits the dev tail', () => {
    const entries = build({ effectiveEnv: 'local', realEnv: 'local' })
    expect(new Set(entries.map((e) => e.section)).size).toBe(1)
  })

  it('makes Debug Options an ACTION row — it runs onOpenDebug, and never navigates', () => {
    const onOpenDebug = vi.fn()
    const row = debugRow(build({ effectiveEnv: 'local', realEnv: 'local', onOpenDebug }))
    expect(row?.href).toBeUndefined() // not a destination
    row?.onSelect?.()
    expect(onOpenDebug).toHaveBeenCalledOnce()
  })

  it('fills the Routes flyout with the site\'s routes, marking the current one', () => {
    const topic = build({ effectiveEnv: 'local', realEnv: 'local' }).find(
      (e): e is Extract<PopoverEntry, { kind: 'topic' }> => e.kind === 'topic',
    )
    expect(topic?.items.map((i) => i.label)).toEqual(['/', '/home'])
    expect(topic?.items.find((i) => i.label === '/home')?.current).toBe(true)
  })
})

describe('DEV_TOOLS_BUILD_ENABLED build gate', () => {
  // The flag is evaluated ONCE at module load from NEXT_PUBLIC_DEPLOYMENT_ENV, so to
  // exercise both branches we reset the module registry and re-import the module under
  // a freshly-stubbed env. This is the everyone-gate's safety property: the dev tail
  // must stay locked for ordinary visitors anywhere but the three dev envs — above
  // all, in production, where only the runtime admin unlock may open it.
  afterEach(() => {
    vi.unstubAllEnvs()
    vi.resetModules()
  })
  const gateFor = async (env: string | undefined): Promise<boolean> => {
    vi.resetModules()
    vi.stubEnv('NEXT_PUBLIC_DEPLOYMENT_ENV', env)
    const mod = await import('../devToolsEntries')
    return mod.DEV_TOOLS_BUILD_ENABLED
  }

  it('is off in production, in an unknown env, and when unset', async () => {
    for (const env of ['production', 'preview', undefined]) {
      expect(await gateFor(env)).toBe(false)
    }
  })

  it('is on in local / testing / staging', async () => {
    for (const env of ['local', 'testing', 'staging']) {
      expect(await gateFor(env)).toBe(true)
    }
  })
})
