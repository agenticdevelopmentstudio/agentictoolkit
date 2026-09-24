// EnvironmentPanel against the two debug-env endpoints it fetches on mount.
//
// The regression this guards: a body OFF the `{ entries }` contract took the whole page
// down. A bare `[]` — what the hub's e2e catch-all answers for every /api/ GET, the signed-
// out wrench test in site-menu.spec.ts included — has an inherited `entries`, the function
// `Array.prototype.entries`. The panel cast the body and handed that to a state setter;
// React CALLS a function passed to a setter as an updater, so it ran `entries` with no
// receiver, threw inside render, and the app's error boundary replaced the page.
//
// `fetch` is stubbed with the minimal shape the panel reads (ok + json) rather than a real
// Response, so the test does not depend on which fetch globals the jsdom environment keeps.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { EnvironmentPanel } from '../debug-env/EnvironmentPanel'

function answer(bodies: Record<string, unknown>) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => ({ ok: true, status: 200, json: async () => bodies[url] })),
  )
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('EnvironmentPanel', () => {
  it('reads a bare-array answer as unavailable instead of crashing the page', async () => {
    answer({ '/api/public/debug-env': [], '/api/system/debug-env': [] })
    render(<EnvironmentPanel />)
    expect(await screen.findByText('Backend env unavailable.')).toBeTruthy()
  })

  it('reads a row off the contract as unavailable too, so no non-string reaches the list', async () => {
    const body = { entries: [{ name: 'API_BACKEND_URL', value: { url: 'x' }, secret: false }] }
    answer({ '/api/public/debug-env': body, '/api/system/debug-env': body })
    render(<EnvironmentPanel />)
    expect(await screen.findByText('Backend env unavailable.')).toBeTruthy()
  })

  it('lists the entries of a body on the contract, site and backend alike', async () => {
    const body = {
      entries: [{ name: 'API_BACKEND_URL', value: 'http://localhost:8080', secret: false }],
    }
    answer({ '/api/public/debug-env': body, '/api/system/debug-env': body })
    render(<EnvironmentPanel />)
    expect(await screen.findAllByText('API_BACKEND_URL')).toHaveLength(2)
  })
})
