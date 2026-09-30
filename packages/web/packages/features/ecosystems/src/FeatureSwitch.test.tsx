// @vitest-environment jsdom
/// <reference types="@testing-library/jest-dom/vitest" />
// The Gaming / Gamification on/off switches: flipping one is an edit of the enclosing DetailsPane,
// and its Save adds or removes the FEATURE — the same write as Manage features (Mike, 2026-09-29).
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { DetailsPane } from '@agentic-toolkit/resource'

const { mutateAsync, state } = vi.hoisted(() => ({
  mutateAsync: vi.fn(),
  state: { held: [] as string[], unavailable: new Map<string, string>() },
}))
vi.mock('@agentic-toolkit/data/ecosystems', async (importOriginal) => {
  const real = await importOriginal<typeof import('@agentic-toolkit/data/ecosystems')>()
  return {
    ...real,
    useEcosystemFeatures: () => ({
      holdings: real.featureHoldings(state.held.map((key) => ({ featureKey: key, state: 'active' })) as never),
      unavailable: state.unavailable,
      apply: { mutateAsync },
    }),
  }
})

import { FeatureSwitch } from './FeatureSwitch'

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
  state.held = []
  state.unavailable = new Map()
})

function renderSwitch(props: Partial<Parameters<typeof FeatureSwitch>[0]> = {}) {
  return render(
    <DetailsPane title="Settings" hoist={false}>
      <FeatureSwitch ecosystemId="eco-1" featureKey="gaming" label="Gaming" description="Gives this product a game." {...props} />
    </DetailsPane>,
  )
}

const toggle = () => screen.getByRole('switch', { name: 'Gaming' })
const save = () => screen.getByRole('button', { name: 'Save' })

describe('FeatureSwitch', () => {
  it('shows what the ecosystem holds', () => {
    state.held = ['gaming']
    renderSwitch()
    expect(toggle()).toBeChecked()
    expect(save()).toBeDisabled()
  })

  it('turning it on is an edit; Save adds the feature and runs onApplied', async () => {
    const onApplied = vi.fn()
    mutateAsync.mockResolvedValue(undefined)
    renderSwitch({ onApplied })
    expect(toggle()).not.toBeChecked()
    fireEvent.click(toggle())
    expect(save()).toBeEnabled()
    fireEvent.click(save())
    await waitFor(() => expect(mutateAsync).toHaveBeenCalledWith({ add: ['gaming'], remove: [] }))
    await waitFor(() => expect(onApplied).toHaveBeenCalled())
    await screen.findByText('Saved.')
  })

  it('turning it off removes the feature', async () => {
    state.held = ['gaming']
    mutateAsync.mockResolvedValue(undefined)
    renderSwitch()
    fireEvent.click(toggle())
    fireEvent.click(save())
    await waitFor(() => expect(mutateAsync).toHaveBeenCalledWith({ add: [], remove: ['gaming'] }))
  })

  it('Cancel puts the switch back', () => {
    renderSwitch()
    fireEvent.click(toggle())
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(toggle()).not.toBeChecked()
    expect(save()).toBeDisabled()
  })

  it('a refused write shows on the bar', async () => {
    mutateAsync.mockRejectedValue(new Error('Gaming is not available here.'))
    renderSwitch()
    fireEvent.click(toggle())
    fireEvent.click(save())
    expect(await screen.findByText('Gaming is not available here.')).toBeInTheDocument()
  })

  it('is held on, and disabled, while the feature that brings it is held', () => {
    state.held = ['gaming', 'gamification']
    render(
      <DetailsPane title="Settings" hoist={false}>
        <FeatureSwitch
          ecosystemId="eco-1"
          featureKey="gamification"
          label="Gamification"
          description="Points and levels."
          lockedBy="gaming"
          lockedDescription="On, because this product has Gaming."
        />
      </DetailsPane>,
    )
    const sw = screen.getByRole('switch', { name: 'Gamification' })
    expect(sw).toBeChecked()
    expect(sw).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByText('On, because this product has Gaming.')).toBeInTheDocument()
  })

  it('cannot be turned on while the feature is unavailable, and says why', () => {
    state.unavailable = new Map([['gaming', 'Client ecosystems cannot have Gaming.']])
    renderSwitch()
    expect(toggle()).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByText('Client ecosystems cannot have Gaming.')).toBeInTheDocument()
  })
})
