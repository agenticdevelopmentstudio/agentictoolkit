// @vitest-environment jsdom
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'
import { ClientAuthSettingsPane } from './ClientAuthSettingsPane'
import { clientAuthApi, type EcosystemClientAuth } from '@agentic-toolkit/data/ecosystem-config'

vi.mock('@agentic-toolkit/data/ecosystem-config', () => ({
  clientAuthApi: {
    ecosystem: vi.fn(),
    updateEcosystem: vi.fn(),
  },
}))

const PROVIDERS = [
  { slug: 'github', name: 'GitHub' },
  { slug: 'google', name: 'Google' },
]

function config(over: Partial<EcosystemClientAuth['settings']> = {}): EcosystemClientAuth {
  return {
    settings: {
      signupMode: 'invite_only',
      loginEnabled: true,
      passwordEnabled: true,
      allowedProviders: null,
      ...over,
    },
    registration: null,
    providers: PROVIDERS,
  }
}

// Each test reads a different ecosystem: the item cache is shared across tests in this file.
let n = 0
async function renderPane(loaded: EcosystemClientAuth) {
  const id = `eco${++n}`
  vi.mocked(clientAuthApi.ecosystem).mockResolvedValue(loaded)
  vi.mocked(clientAuthApi.updateEcosystem).mockImplementation(async (_id, update) => ({
    ...loaded,
    settings: { ...loaded.settings, ...update.settings },
  }))
  render(<ClientAuthSettingsPane ecosystemId={id} />)
  await screen.findByRole('switch', { name: 'Email and password' })
  return id
}

const save = () => fireEvent.click(screen.getByRole('button', { name: 'Save' }))
const putBody = () => vi.mocked(clientAuthApi.updateEcosystem).mock.calls[0]?.[1]

// A base-ui Switch labels both its role="switch" span and a hidden checkbox, so it is found by role.
const sw = (name: string) => screen.getByRole('switch', { name })

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('ClientAuthSettingsPane', () => {
  it('sends only the policy fields that changed', async () => {
    const id = await renderPane(config())
    fireEvent.click(sw('Email and password'))
    fireEvent.change(screen.getByLabelText('Sign-up mode'), { target: { value: 'closed' } })
    save()
    await waitFor(() => expect(clientAuthApi.updateEcosystem).toHaveBeenCalledTimes(1))
    expect(vi.mocked(clientAuthApi.updateEcosystem).mock.calls[0]?.[0]).toBe(id)
    expect(putBody()).toEqual({ settings: { passwordEnabled: false, signupMode: 'closed' } })
  })

  it('turns one provider off into the list of the rest', async () => {
    await renderPane(config())
    fireEvent.click(sw('Google'))
    save()
    await waitFor(() => expect(clientAuthApi.updateEcosystem).toHaveBeenCalled())
    expect(putBody()?.settings).toEqual({ allowedProviders: ['github'] })
  })

  it('sends null, not the full list, when every provider is on', async () => {
    await renderPane(config({ allowedProviders: ['github'] }))
    fireEvent.click(sw('Google'))
    save()
    await waitFor(() => expect(clientAuthApi.updateEcosystem).toHaveBeenCalled())
    expect(putBody()?.settings).toEqual({ allowedProviders: null })
  })

  it('will not turn the last provider off', async () => {
    await renderPane(config({ allowedProviders: ['github'] }))
    expect(sw('GitHub')).toHaveAttribute('data-disabled')
    expect(sw('Google')).not.toHaveAttribute('data-disabled')
  })

  // Each application has its own login registration: the ecosystem's is neither shown nor sent.
  it('shows no login registration, even when the ecosystem still has one', async () => {
    await renderPane({
      ...config(),
      registration: { clientId: 'cid_1', allowedReturnOrigins: ['https://a.com'], redirectUris: [] },
    })
    expect(screen.queryByText('Login registration')).toBeNull()
    expect(screen.queryByDisplayValue('cid_1')).toBeNull()
    fireEvent.click(sw('Email and password'))
    save()
    await waitFor(() => expect(clientAuthApi.updateEcosystem).toHaveBeenCalled())
    expect(putBody()).not.toHaveProperty('registration')
  })
})
