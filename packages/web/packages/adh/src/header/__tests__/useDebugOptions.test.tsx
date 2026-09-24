import { describe, it, expect, vi, afterEach } from 'vitest'
import { act, cleanup, renderHook } from '@testing-library/react'

// The Debug Options door: whether it exists for this visitor, and whether the console
// it opened survives the door being withdrawn. Both halves are about the one door the
// header has left since the bug-glyph dev-tools dropdown went — the avatar menu's last
// row signed in, a Debug Options button signed out — and AdhHeader draws either from
// exactly what this hook returns.
//
// The negative cases are the load-bearing ones. A door that leaked into production
// would look correct in every screenshot a developer ever takes: they are, by
// definition, always on the unlocked side of this gate.

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn() }),
}))

// The console itself is a heavy lazy chunk, and nothing here renders it: the hook's
// `window` is asserted as present-or-null, which is the whole contract a caller mounts.
vi.mock('@agentic-toolkit/adh/debug-console', () => ({
  DebugConsoleWindow: () => null,
}))

afterEach(() => {
  cleanup()
  vi.unstubAllEnvs()
  vi.resetModules()
})

// DEV_TOOLS_BUILD_ENABLED folds at MODULE LOAD from NEXT_PUBLIC_DEPLOYMENT_ENV, so each
// build needs a fresh module registry under a freshly-stubbed env — the same dance
// devToolsEntries.test.ts does for the flag itself, one layer up. jsdom's host is
// `localhost`, i.e. the REAL env here is `local`: a production BUILD on a dev host,
// which is exactly the case where only the build flag stands between an ordinary
// visitor and the console.
async function hookIn(env: string | undefined) {
  vi.resetModules()
  vi.stubEnv('NEXT_PUBLIC_DEPLOYMENT_ENV', env)
  const { useDebugOptions } = await import('../useDebugOptions')
  return (userIsAdmin: boolean | undefined) =>
    renderHook(({ admin }) => useDebugOptions(admin), { initialProps: { admin: userIsAdmin } })
}

describe('useDebugOptions — who is offered the door', () => {
  it('offers nothing to an ordinary visitor in a production build', async () => {
    const { result } = (await hookIn('production'))(false)
    expect(result.current.onOpen).toBeUndefined()
    expect(result.current.hint).toBeUndefined()
    expect(result.current.window).toBeNull()
  })

  it('offers nothing while userIsAdmin is merely unresolved', async () => {
    // The auth source settles AFTER first paint, so `undefined` is the state every
    // production page starts in. Only an explicit `true` may open the door — a truthy
    // check on a still-loading source would flash it for everyone.
    const { result } = (await hookIn('production'))(undefined)
    expect(result.current.onOpen).toBeUndefined()
  })

  it('offers it to a SIGNED-OUT visitor in each dev build — nothing here reads a session', async () => {
    // `false` is what SiteHeader passes with nobody signed in. The signed-out door
    // (AdhHeader's Debug Options button) exists only because this answer is yes.
    for (const env of ['local', 'testing', 'staging']) {
      const { result } = (await hookIn(env))(false)
      expect(result.current.onOpen, env).toBeTypeOf('function')
      cleanup()
    }
  })

  it('offers it to a signed-in adh admin in a production build', async () => {
    const { result } = (await hookIn('production'))(true)
    expect(result.current.onOpen).toBeTypeOf('function')
  })
})

describe('useDebugOptions — the console goes when the door does', () => {
  // A cached admin is restored at page load and can open the console at once; the
  // background /api/auth/me check can then sign them out in place (a 401) or apply a
  // user who is no longer an admin. The dropdown this door replaced unmounted the
  // console when that happened, and a console left open past its own gate is a door
  // that was never really withdrawn.
  it('closes an open console when the admin unlock is lost', async () => {
    const { result, rerender } = (await hookIn('production'))(true)
    act(() => result.current.onOpen?.())
    expect(result.current.window).not.toBeNull()

    rerender({ admin: false })
    expect(result.current.onOpen).toBeUndefined()
    expect(result.current.window).toBeNull()
  })

  it('does not reopen it when the unlock comes back', async () => {
    // Masking the window on `offered` alone would pass the test above and fail this
    // one: the stale `open` would put the console back on screen, unasked, the moment
    // the same admin signed in again.
    const { result, rerender } = (await hookIn('production'))(true)
    act(() => result.current.onOpen?.())
    rerender({ admin: false })
    rerender({ admin: true })
    expect(result.current.onOpen).toBeTypeOf('function')
    expect(result.current.window).toBeNull()
  })

  it('leaves an open console alone while the door stays offered', async () => {
    const { result, rerender } = (await hookIn('production'))(true)
    act(() => result.current.onOpen?.())
    rerender({ admin: true })
    expect(result.current.window).not.toBeNull()
  })
})
