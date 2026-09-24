import { describe, it, expect, vi, afterEach } from 'vitest'
import { debugOptionsAvailable, debugOptionsHint, isDevEnv } from '../devToolsEntries'
import { type SiteEnv } from '@agentic-toolkit/adh-registry'

// The gate behind the header's "Debug Options" door. The safety property under test
// is that it cannot leak to an ordinary production visitor — while a signed-in adh
// admin (adminUnlocked) gets it in every env, production included. It reads the REAL
// env, not the simulated one, so simulating production can always be undone. How the
// pieces combine into the door is useDebugOptions.test.tsx's.

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

describe('DEV_TOOLS_BUILD_ENABLED build gate', () => {
  // The flag is evaluated ONCE at module load from NEXT_PUBLIC_DEPLOYMENT_ENV, so to
  // exercise both branches we reset the module registry and re-import the module under
  // a freshly-stubbed env. This is the everyone-gate's safety property: Debug Options
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
