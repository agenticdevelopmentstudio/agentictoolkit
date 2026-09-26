import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'

// The three react-query hooks are the dialog's only reads and its only write; replacing them is
// what lets each test set their states directly. The mappers and types stay real.
vi.mock('@agentic-toolkit/data/ecosystems', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@agentic-toolkit/data/ecosystems')>()),
  useFeatureCatalog: vi.fn(),
  useProvisionedFeatures: vi.fn(),
  useApplyFeatureChange: vi.fn(),
}))

import { useApplyFeatureChange, useFeatureCatalog, useProvisionedFeatures } from '@agentic-toolkit/data/ecosystems'
import { ManageFeaturesDialog } from './ManageFeaturesDialog'

/** A read with no answer yet — react-query's `pending`, which a hung or offline request never leaves. */
const PENDING_READ = { data: undefined, isPending: true, isError: false }
/** A read that has answered: nothing in the catalog, nothing provisioned. */
const EMPTY_READ = { data: [], isPending: false, isError: false }

function stub(reads: object, apply: { isPending: boolean }) {
  vi.mocked(useFeatureCatalog).mockReturnValue(reads as never)
  vi.mocked(useProvisionedFeatures).mockReturnValue(reads as never)
  vi.mocked(useApplyFeatureChange).mockReturnValue({ ...apply, isError: false, mutate: vi.fn() } as never)
}

// The dialog used to count its two READS as `busy`, and the picker draws busy as a spinner in place
// of Cancel, with the × hidden and Escape ignored. authedFetch has no timeout, so a read that hung
// (or sat paused offline) held the user in the dialog until a reload. Only the apply is busy now.
describe('ManageFeaturesDialog — what counts as busy', () => {
  it('can still be cancelled while its lists are loading', () => {
    stub(PENDING_READ, { isPending: false })
    const onClose = vi.fn()
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={onClose} />)
    expect(screen.getByText('Loading…')).toBeInTheDocument()
    expect(screen.queryByRole('status', { name: 'Working…' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('is busy while the change itself is in flight', () => {
    stub(EMPTY_READ, { isPending: true })
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByRole('status', { name: 'Working…' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Cancel' })).toBeNull()
  })
})

/** A read that has answered with `data`. */
const read = (data: object[]) => ({ data, isPending: false, isError: false })

const PERSONAS = {
  key: 'personas',
  label: 'Personas',
  description: 'Personas does things.',
  subscriptionTier: 'Free',
  featureSite: false,
}

const held = (featureKey: string, state = 'active') => ({ featureKey, state, provisionedAt: '', provisionedBy: null })

/** Stubs the two reads separately, and hands back the apply's `mutate` to assert on. */
function stubReads(catalog: object, provisioned: object) {
  const mutate = vi.fn()
  vi.mocked(useFeatureCatalog).mockReturnValue(catalog as never)
  vi.mocked(useProvisionedFeatures).mockReturnValue(provisioned as never)
  vi.mocked(useApplyFeatureChange).mockReturnValue({ isPending: false, isError: false, mutate } as never)
  return mutate
}

// The picker draws its rows from the catalog alone, and it is the only way left to take a feature
// off — the old features pane, which listed a held key with a Remove of its own, is gone. So a held
// key the catalog stopped listing would stay on with no way to switch it off.
describe('ManageFeaturesDialog — a held feature the catalog no longer lists', () => {
  const PROVISIONED = read([held('personas'), held('retired'), held('gone', 'removed')])

  it('gets a ticked row of its own that says it is no longer offered', () => {
    stubReads(read([PERSONAS]), PROVISIONED)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByRole('checkbox', { name: 'retired' })).toBeChecked()
    // Removed is not held, so a removed key the catalog dropped gets no row.
    expect(screen.queryByRole('checkbox', { name: 'gone' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /retired/ }))
    expect(screen.getByText('No longer offered.')).toBeInTheDocument()
    // It has no tier, and "Subscription Level Required:" over nothing would say less than no line.
    expect(screen.queryByText(/Subscription Level Required/)).toBeNull()
  })

  it('can be taken off', () => {
    const mutate = stubReads(read([PERSONAS]), PROVISIONED)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'retired' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(mutate).toHaveBeenCalledWith({ add: [], remove: ['retired'] }, expect.anything())
  })

  // Before the catalog lands every held key is missing from it: stand-ins then would fill the
  // loading list with rows the real ones replace a moment later.
  it('adds none while the catalog is still loading', () => {
    stubReads(PENDING_READ, PROVISIONED)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByText('Loading…')).toBeInTheDocument()
    expect(screen.queryByRole('checkbox', { name: 'retired' })).toBeNull()
  })
})

// A feature stuck in `provisioning` used to be a ticked box exactly like one that works.
describe('ManageFeaturesDialog — a feature still provisioning', () => {
  it('is ticked and badged, and its details say it is still being set up', () => {
    stubReads(read([PERSONAS]), read([held('personas', 'provisioning')]))
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByRole('checkbox', { name: 'Personas' })).toBeChecked()
    // The row's badge and the detail pane's (the row is the cursor) both say it.
    expect(screen.getAllByText('Provisioning').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText(/Still being set up/)).toBeInTheDocument()
  })

  it('badges nothing for an active feature', () => {
    stubReads(read([PERSONAS]), read([held('personas')]))
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.queryByText('Provisioning')).toBeNull()
    expect(screen.queryByText(/Still being set up/)).toBeNull()
  })
})

// A failed FIRST read of what the ecosystem holds left `alreadyProvisioned` empty with the ticks
// live: every held feature looked absent, and Apply would have queued it again.
describe('ManageFeaturesDialog — the provisioned read failed', () => {
  const FAILED_FIRST = { data: undefined, isPending: false, isError: true }

  it('keeps the ticks and Apply disabled while there is no baseline', () => {
    const mutate = stubReads(read([PERSONAS]), FAILED_FIRST)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    const box = screen.getByRole('checkbox', { name: 'Personas' })
    fireEvent.click(box)
    expect(box).not.toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
    expect(screen.getByText(/Couldn't load which features are already on/)).toBeInTheDocument()
    expect(mutate).not.toHaveBeenCalled()
  })

  it('still offers Cancel', () => {
    const onClose = vi.fn()
    stubReads(read([PERSONAS]), FAILED_FIRST)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={onClose} />)
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  // A failed REFRESH keeps its last answer, which is still a baseline: the picker works, and says
  // the list may be out of date.
  it('keeps working on the last answer when only a refresh failed', () => {
    stubReads(read([PERSONAS]), { data: [], isPending: false, isError: true })
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Personas' }))
    expect(screen.getByRole('checkbox', { name: 'Personas' })).toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeEnabled()
    expect(screen.getByText(/Couldn't refresh which features are already on/)).toBeInTheDocument()
  })

  // One error slot for both hid the apply failure behind the read failure.
  it('shows the load error AND the apply error together', () => {
    vi.mocked(useFeatureCatalog).mockReturnValue(read([PERSONAS]) as never)
    vi.mocked(useProvisionedFeatures).mockReturnValue({ data: [], isPending: false, isError: true } as never)
    vi.mocked(useApplyFeatureChange).mockReturnValue({ isPending: false, isError: true, mutate: vi.fn() } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByText(/Couldn't refresh which features are already on/)).toBeInTheDocument()
    expect(screen.getByText(/Failed to change the features/)).toBeInTheDocument()
  })
})
