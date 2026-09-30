import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'

// The react-query hooks are the dialog's only reads and its only write; replacing them is what
// lets each test set their states directly. The dialog reads them through the feature manager
// (`useEcosystemFeatures`), which calls them inside its own module where a barrel mock cannot
// reach — so the manager is rebuilt here over the mocked reads, with its real pure rules.
vi.mock('@agentic-toolkit/data/ecosystems', async (importOriginal) => {
  const real = await importOriginal<typeof import('@agentic-toolkit/data/ecosystems')>()
  const useFeatureCatalog = vi.fn()
  const useProvisionedFeatures = vi.fn()
  const useApplyFeatureChange = vi.fn()
  const useFeatureAvailability = vi.fn(() => ({ data: [], isPending: false, isError: false }))
  return {
    ...real,
    useFeatureCatalog,
    useProvisionedFeatures,
    useApplyFeatureChange,
    useFeatureAvailability,
    useEcosystemFeatures: (ecosystemId: string) => {
      const catalog = useFeatureCatalog()
      const provisioned = useProvisionedFeatures(ecosystemId)
      const availability = useFeatureAvailability(ecosystemId) as { data?: { key: string; reason: string }[] }
      const all = (catalog.data ?? []) as Parameters<typeof real.listedCatalog>[0]
      return {
        catalog,
        listed: catalog.data ? real.listedCatalog(all) : undefined,
        listedKeyOf: (key: string) => real.listedFeatureKey(key, all),
        provisioned,
        apply: useApplyFeatureChange(ecosystemId),
        holdings: real.featureHoldings(provisioned.data ?? []),
        unavailable: new Map((availability.data ?? []).map((f) => [f.key, f.reason])),
      }
    },
  }
})

import {
  useApplyFeatureChange,
  useFeatureAvailability,
  useFeatureCatalog,
  useProvisionedFeatures,
  FeatureRequiredError,
} from '@agentic-toolkit/data/ecosystems'
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

// The picker refuses a feature-required tick-off in-dialog, but a second session can remove the
// requiring feature's dependency BETWEEN the picker's own confirm and the DELETE landing — the
// picker never saw that window, so the backend catches it instead. It gets the same copy anyway
// (`neededByMessage`, mapping `neededBy` keys to catalog labels) rather than the generic failure.
describe('ManageFeaturesDialog — a feature-required race from the backend', () => {
  const SIGNIN_APPS = {
    key: 'signin-apps',
    label: 'Client Auth',
    description: 'Client Auth does things.',
    subscriptionTier: 'Free',
    featureSite: false,
  }

  it("shows the picker's own copy, naming the blocker by its catalog label", () => {
    stubReads(read([PERSONAS, SIGNIN_APPS]), read([held('personas')]))
    vi.mocked(useApplyFeatureChange).mockReturnValue({
      isPending: false,
      isError: true,
      error: new FeatureRequiredError('this feature is needed by Client Auth', ['signin-apps']),
      mutate: vi.fn(),
    } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByText('this feature is needed by Client Auth features')).toBeInTheDocument()
    expect(screen.queryByText(/Failed to change the features/)).toBeNull()
  })

  it('names a blocker that comes with another by the feature it comes with', () => {
    const APPLICATIONS = { ...SIGNIN_APPS, key: 'applications', label: 'Applications' }
    stubReads(
      read([PERSONAS, APPLICATIONS, { ...SIGNIN_APPS, includedWith: 'applications' }]),
      read([held('personas')]),
    )
    vi.mocked(useApplyFeatureChange).mockReturnValue({
      isPending: false,
      isError: true,
      error: new FeatureRequiredError('this feature is needed by Client Auth', ['signin-apps']),
      mutate: vi.fn(),
    } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByText('this feature is needed by Applications features')).toBeInTheDocument()
  })

  it('falls back to the raw key when the catalog has no label for it', () => {
    stubReads(read([PERSONAS]), read([held('personas')]))
    vi.mocked(useApplyFeatureChange).mockReturnValue({
      isPending: false,
      isError: true,
      error: new FeatureRequiredError('this feature is needed by signin-apps', ['signin-apps']),
      mutate: vi.fn(),
    } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByText('this feature is needed by signin-apps features')).toBeInTheDocument()
  })

  // Two removals failed in the same batch: one because of this race, one for an unrelated reason.
  // The old code threw only the FeatureRequiredError and dropped the other key entirely — this
  // dialog is the last place that failure could still be surfaced, so it must say so rather than
  // implying the whole apply failed for exactly one reason.
  it('also says when other removals in the same batch failed too', () => {
    stubReads(read([PERSONAS, SIGNIN_APPS]), read([held('personas')]))
    vi.mocked(useApplyFeatureChange).mockReturnValue({
      isPending: false,
      isError: true,
      error: new FeatureRequiredError('this feature is needed by Client Auth', ['signin-apps'], ['other-feature']),
      mutate: vi.fn(),
    } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(
      screen.getByText('this feature is needed by Client Auth features (and 1 other removal failed)'),
    ).toBeInTheDocument()
  })

  it('pluralises when more than one other removal failed', () => {
    stubReads(read([PERSONAS, SIGNIN_APPS]), read([held('personas')]))
    vi.mocked(useApplyFeatureChange).mockReturnValue({
      isPending: false,
      isError: true,
      error: new FeatureRequiredError('this feature is needed by Client Auth', ['signin-apps'], ['a', 'b']),
      mutate: vi.fn(),
    } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(
      screen.getByText('this feature is needed by Client Auth features (and 2 other removals failed)'),
    ).toBeInTheDocument()
  })
})

// Only users and organizations own organizations, so a client ecosystem cannot hold one. The
// server says which features this ecosystem may not add; the dialog disables exactly those.
describe('ManageFeaturesDialog — a feature this ecosystem may not add', () => {
  const ORGS = {
    key: 'organizations',
    label: 'Organizations',
    description: 'Organizations as owner principals.',
    subscriptionTier: 'Free',
    featureSite: false,
  }
  const REASON = "Only a user's or an organization's own ecosystem can have Organizations."

  it('is disabled, and its details say why', () => {
    stubReads(read([PERSONAS, ORGS]), read([]))
    vi.mocked(useFeatureAvailability).mockReturnValue({ data: [{ key: 'organizations', reason: REASON }] } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByRole('checkbox', { name: 'Organizations' })).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByRole('checkbox', { name: 'Personas' })).not.toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(screen.getByRole('button', { name: /Organizations/ }))
    expect(screen.getByText(REASON)).toBeInTheDocument()
  })

  it('can still be taken off an ecosystem that already holds it', () => {
    const mutate = stubReads(read([ORGS]), read([held('organizations')]))
    vi.mocked(useFeatureAvailability).mockReturnValue({ data: [{ key: 'organizations', reason: REASON }] } as never)
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Organizations' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(mutate).toHaveBeenCalledWith({ add: [], remove: ['organizations'] }, expect.anything())
  })
})

// User Authentication and Email Signup come with Users, Client Auth with Applications (Mike,
// 2026-09-29): the owner never picks them, so the dialog has no row for them — even held.
describe('ManageFeaturesDialog — a feature that comes with another', () => {
  const USERS = { ...PERSONAS, key: 'users', label: 'Users' }
  const USER_AUTH = {
    ...PERSONAS,
    key: 'user-authentication',
    label: 'User Authentication',
    includedWith: 'users',
  }

  it('has no row, and is not a stand-in while held', () => {
    stubReads(read([USERS, USER_AUTH]), read([held('users'), held('user-authentication')]))
    render(<ManageFeaturesDialog ecosystemId="ecosystem.acme.widgets" onClose={vi.fn()} />)
    expect(screen.getByRole('checkbox', { name: 'Users' })).toBeInTheDocument()
    expect(screen.queryByRole('checkbox', { name: 'User Authentication' })).toBeNull()
    expect(screen.queryByRole('checkbox', { name: 'user-authentication' })).toBeNull()
  })
})
