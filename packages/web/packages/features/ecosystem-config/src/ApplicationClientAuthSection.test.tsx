// @vitest-environment jsdom
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'
import { ApplicationClientAuthSection, useApplicationClientAuth } from './ApplicationClientAuthSection'
import { clientAuthApi, type ApplicationClientAuth } from '@agentic-toolkit/data/ecosystem-config'

vi.mock('@agentic-toolkit/data/ecosystem-config', () => ({
  clientAuthApi: {
    application: vi.fn(),
    updateApplication: vi.fn(),
  },
}))

/** The pane's side of the section: its dirty flag, blocked reason, and a Save that runs the section's save. */
function Harness({ appId }: { appId: string }) {
  const state = useApplicationClientAuth(appId)
  return (
    <>
      <span data-testid="dirty">{String(state.dirty)}</span>
      <span data-testid="blocked">{state.blockedReason ?? ''}</span>
      <button type="button" onClick={() => void state.save()}>
        Save
      </button>
      <button type="button" onClick={state.reset}>
        Cancel
      </button>
      <ApplicationClientAuthSection state={state} />
    </>
  )
}

let n = 0
async function renderSection(loaded: ApplicationClientAuth) {
  const appId = `app.acme.web${++n}`
  vi.mocked(clientAuthApi.application).mockResolvedValue(loaded)
  vi.mocked(clientAuthApi.updateApplication).mockImplementation(async (_id, update) => ({
    platform: loaded.platform,
    registration: update.registration && {
      clientId: 'c-1',
      allowedReturnOrigins: update.registration.allowedReturnOrigins ?? [],
      redirectUris: update.registration.redirectUris,
    },
  }))
  render(<Harness appId={appId} />)
  await screen.findByRole('button', {
    name: loaded.registration ? 'Remove login registration' : 'Create login registration',
  })
  return appId
}

const putBody = () => vi.mocked(clientAuthApi.updateApplication).mock.calls[0]?.[1]
const dirty = () => screen.getByTestId('dirty').textContent
const blocked = () => screen.getByTestId('blocked').textContent

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe("an application's client auth", () => {
  it('has no policy controls of its own', async () => {
    await renderSection({ platform: 'web', registration: null })
    expect(screen.queryByRole('switch')).toBeNull()
    expect(dirty()).toBe('false')
  })

  it('gives a web application a registration with return origins', async () => {
    const appId = await renderSection({ platform: 'web', registration: null })
    fireEvent.click(screen.getByRole('button', { name: 'Create login registration' }))
    fireEvent.change(screen.getByPlaceholderText('https://myapp.com'), { target: { value: 'https://web.acme.dev' } })
    expect(dirty()).toBe('true')
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(clientAuthApi.updateApplication).toHaveBeenCalled())
    expect(vi.mocked(clientAuthApi.updateApplication).mock.calls[0]?.[0]).toBe(appId)
    expect(putBody()).toEqual({
      registration: { allowedReturnOrigins: ['https://web.acme.dev'], redirectUris: [] },
    })
    await waitFor(() => expect(dirty()).toBe('false'))
  })

  it('gives a native application redirect URIs only, custom schemes included', async () => {
    await renderSection({ platform: 'native', registration: null })
    fireEvent.click(screen.getByRole('button', { name: 'Create login registration' }))
    expect(screen.queryByPlaceholderText('https://myapp.com')).toBeNull()
    fireEvent.change(screen.getByPlaceholderText('com.example.app:/callback'), {
      target: { value: 'com.acme.app:/callback' },
    })
    expect(blocked()).toBe('')
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(clientAuthApi.updateApplication).toHaveBeenCalled())
    expect(putBody()).toEqual({
      registration: { allowedReturnOrigins: [], redirectUris: ['com.acme.app:/callback'] },
    })
  })

  it("refuses a custom-scheme redirect on a web application", async () => {
    await renderSection({
      platform: 'web',
      registration: { clientId: 'c-1', allowedReturnOrigins: ['https://web.acme.dev'], redirectUris: [] },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Add redirect URI' }))
    fireEvent.change(screen.getByPlaceholderText('https://myapp.com/callback'), {
      target: { value: 'com.acme.app:/callback' },
    })
    expect(blocked()).toMatch(/for a web application/)
  })

  it('refuses plain http off localhost', async () => {
    await renderSection({ platform: 'native', registration: null })
    fireEvent.click(screen.getByRole('button', { name: 'Create login registration' }))
    fireEvent.change(screen.getByPlaceholderText('com.example.app:/callback'), {
      target: { value: 'http://acme.dev/callback' },
    })
    expect(blocked()).toMatch(/http only on localhost/)
  })

  it('removes the registration by sending null', async () => {
    await renderSection({
      platform: 'web',
      registration: { clientId: 'c-1', allowedReturnOrigins: ['https://web.acme.dev'], redirectUris: [] },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Remove login registration' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(clientAuthApi.updateApplication).toHaveBeenCalled())
    expect(putBody()).toEqual({ registration: null })
  })

  it('throws the edits away on Cancel', async () => {
    await renderSection({ platform: 'web', registration: null })
    fireEvent.click(screen.getByRole('button', { name: 'Create login registration' }))
    expect(dirty()).toBe('true')
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(dirty()).toBe('false')
    expect(screen.queryByRole('button', { name: 'Create login registration' })).not.toBeNull()
  })
})
