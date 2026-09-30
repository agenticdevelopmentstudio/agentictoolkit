import { render, screen, fireEvent, within } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import type { CatalogFeature } from '@agentic-toolkit/data/ecosystems'
import { FeaturePickerDialog } from './FeaturePickerDialog'

const feature = (key: string, label: string): CatalogFeature =>
  ({ key, label, description: `${label} does things.`, subscriptionTier: 'Free', featureSite: false }) as CatalogFeature

const CATALOG = [
  feature('personas', 'Personas'),
  { ...feature('messaging', 'Messaging'), comingSoon: true },
  feature('research', 'Research'),
  { ...feature('code-reviews', 'Code Reviews'), comingSoon: true },
]

function renderPicker(onApply = vi.fn()) {
  render(
    <FeaturePickerDialog
      open
      catalog={CATALOG}
      alreadyProvisioned={new Set(['personas'])}
      onApply={onApply}
      onCancel={vi.fn()}
    />,
  )
}

describe('FeaturePickerDialog', () => {
  it('shows an added feature ticked and still ENABLED, with no "Added" mark', () => {
    renderPicker()
    const added = screen.getByRole('checkbox', { name: 'Personas' })
    expect(added).toBeChecked()
    expect(added).not.toHaveAttribute('aria-disabled', 'true')
    const fresh = screen.getByRole('checkbox', { name: 'Research' })
    expect(fresh).not.toBeChecked()
    expect(fresh).not.toHaveAttribute('aria-disabled', 'true')
    expect(screen.queryByText(/^Added$/i)).toBeNull()
  })

  it('removes an unticked feature only after a confirm that says its data is kept', () => {
    const onApply = vi.fn()
    renderPicker(onApply)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Personas' }))
    expect(screen.getByRole('checkbox', { name: 'Personas' })).not.toBeChecked()
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(onApply).not.toHaveBeenCalled()
    expect(screen.getByText('Remove 1 feature?')).toBeInTheDocument()
    expect(screen.getByText(/Its data is kept/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(onApply).toHaveBeenCalledWith({ add: [], remove: ['personas'] })
  })

  it('applies adds and removals together behind one confirm', () => {
    const onApply = vi.fn()
    renderPicker(onApply)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Personas' }))
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(screen.getByText('Add 1 feature and remove 1 feature?')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(onApply).toHaveBeenCalledWith({ add: ['research'], remove: ['personas'] })
  })

  it('re-ticking a feature before applying cancels its removal', () => {
    renderPicker()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Personas' }))
    fireEvent.click(screen.getByRole('checkbox', { name: 'Personas' }))
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })

  it("still shows an added feature's details when its row is picked", () => {
    renderPicker()
    fireEvent.click(screen.getByRole('button', { name: /Personas/ }))
    expect(screen.getByText('Personas does things.')).toBeInTheDocument()
  })

  it('gives the filter field the whole header row', () => {
    renderPicker()
    const field = screen.getByRole('searchbox', { name: 'Filter features' }).parentElement!
    expect(field.className).toContain('flex-1')
    expect(field.className).not.toContain('max-w-xs')
  })

  it('lists coming-soon features last, under a "Coming soon" divider, with their checkboxes DISABLED', () => {
    renderPicker()
    const boxes = screen.getAllByRole('checkbox').map((b) => b.getAttribute('aria-label'))
    expect(boxes).toEqual(['Personas', 'Research', 'Code Reviews', 'Messaging'])
    expect(screen.getByRole('separator', { name: 'Coming soon' })).toBeInTheDocument()
    for (const name of ['Code Reviews', 'Messaging']) {
      expect(screen.getByRole('checkbox', { name })).toHaveAttribute('aria-disabled', 'true')
    }
  })

  it('never adds a coming-soon feature, even when its checkbox is clicked', () => {
    renderPicker()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Messaging' }))
    expect(screen.getByRole('checkbox', { name: 'Messaging' })).not.toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })
})

// The picker is the only way left to take a feature off. A coming-soon feature the ecosystem
// already holds used to sit ticked behind a disabled checkbox, on for good; it can come off now,
// though it still can never be put on.
describe('FeaturePickerDialog — a held coming-soon feature', () => {
  function renderHeld(onApply = vi.fn()) {
    render(
      <FeaturePickerDialog
        open
        catalog={CATALOG}
        alreadyProvisioned={new Set(['personas', 'messaging'])}
        onApply={onApply}
        onCancel={vi.fn()}
      />,
    )
  }

  it('can be unticked, and removed behind the same confirm', () => {
    const onApply = vi.fn()
    renderHeld(onApply)
    const box = screen.getByRole('checkbox', { name: 'Messaging' })
    expect(box).toBeChecked()
    expect(box).not.toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(box)
    expect(screen.getByRole('checkbox', { name: 'Messaging' })).not.toBeChecked()
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(screen.getByText('Remove 1 feature?')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(onApply).toHaveBeenCalledWith({ add: [], remove: ['messaging'] })
  })

  it('ticking it back only cancels the removal', () => {
    renderHeld()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Messaging' }))
    fireEvent.click(screen.getByRole('checkbox', { name: 'Messaging' }))
    expect(screen.getByRole('checkbox', { name: 'Messaging' })).toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })

  it('leaves a coming-soon feature it does not hold disabled and unticked', () => {
    renderHeld()
    const box = screen.getByRole('checkbox', { name: 'Code Reviews' })
    expect(box).toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(box)
    expect(screen.getByRole('checkbox', { name: 'Code Reviews' })).not.toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })
})

// A partial `useApplyFeatureChange` failure re-triggers `useProvisionedFeatures`, which arrives
// with a DIFFERENT `alreadyProvisioned` set mid-visit. The old XOR-against-provisioned state
// inverted intent on that refetch (a key that DID get added was then shown as pending removal);
// storing the user's TARGET state per key instead must survive it untouched.
describe('FeaturePickerDialog — target state survives a provisioned-list refetch', () => {
  it('keeps an achieved add ticked, and a still-pending remove unticked, after the list changes under it', () => {
    const onApply = vi.fn()
    const { rerender } = render(
      <FeaturePickerDialog
        open
        catalog={CATALOG}
        alreadyProvisioned={new Set(['personas'])}
        onApply={onApply}
        onCancel={vi.fn()}
      />,
    )

    // The user's visit: add "research", remove "personas".
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    fireEvent.click(screen.getByRole('checkbox', { name: 'Personas' }))
    expect(screen.getByRole('checkbox', { name: 'Research' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Personas' })).not.toBeChecked()

    // Apply partially fails: "research" made it in, "personas"'s removal did not. The
    // provisioned query refetches to reflect exactly that — both keys now present.
    rerender(
      <FeaturePickerDialog
        open
        catalog={CATALOG}
        alreadyProvisioned={new Set(['personas', 'research'])}
        onApply={onApply}
        onCancel={vi.fn()}
      />,
    )

    // "research" is now actually provisioned AND that was the desired state — still ticked,
    // not reopened as a pending removal.
    expect(screen.getByRole('checkbox', { name: 'Research' })).toBeChecked()
    // "personas" is still provisioned but the desired state is still "off" — still unticked,
    // still a pending removal, not silently dropped.
    expect(screen.getByRole('checkbox', { name: 'Personas' })).not.toBeChecked()

    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    // Only the remaining, still-pending change is sent — not a re-add of "research" and
    // not a re-remove of something already handled twice.
    expect(onApply).toHaveBeenCalledWith({ add: [], remove: ['personas'] })
  })

  it('clicking a row back to its own original state drops it from the pending change entirely', () => {
    renderPicker()
    const box = screen.getByRole('checkbox', { name: 'Research' })
    fireEvent.click(box) // add
    fireEvent.click(box) // back off
    expect(box).not.toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })
})

describe('FeaturePickerDialog — Enter-to-confirm ignores IME composition', () => {
  function filterField(): HTMLElement {
    return screen.getByRole('searchbox', { name: 'Filter features' })
  }

  it('opens the confirm on a plain Enter', () => {
    renderPicker()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    fireEvent.keyDown(filterField(), { key: 'Enter' })
    expect(screen.getByText('Add 1 feature?')).toBeInTheDocument()
  })

  it('does not open the confirm on an Enter that is composing an IME candidate', () => {
    renderPicker()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    fireEvent.keyDown(filterField(), { key: 'Enter', isComposing: true })
    expect(screen.queryByText('Add 1 feature?')).toBeNull()
  })

  it('does not open the confirm on an Enter carrying the legacy IME keyCode 229', () => {
    renderPicker()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    fireEvent.keyDown(filterField(), { key: 'Enter', keyCode: 229 })
    expect(screen.queryByText('Add 1 feature?')).toBeNull()
  })
})

// ManageFeaturesDialog used to pass its two READS (the catalog, and what the ecosystem already
// holds) as `busy`, and busy removes every way out of the dialog: no ×, Escape ignored, the footer
// only a spinner. A read has no timeout, so a hung or offline one held the user in the dialog until
// a reload. The reads are `loading` now — the dialog stays dismissable and only the change waits.
describe('FeaturePickerDialog — loading', () => {
  it('says it is loading, and can still be left by Cancel or the ×', () => {
    const onCancel = vi.fn()
    render(<FeaturePickerDialog open catalog={[]} loading onApply={vi.fn()} onCancel={onCancel} />)
    expect(screen.getByText('Loading…')).toBeInTheDocument()
    expect(screen.queryByRole('status', { name: 'Working…' })).toBeNull()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    expect(onCancel).toHaveBeenCalledTimes(2)
  })

  it('takes no ticks, by click or by Space, until the lists arrive', () => {
    render(<FeaturePickerDialog open catalog={CATALOG} loading onApply={vi.fn()} onCancel={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    // Space toggles the cursor row — Personas, the first — from the filter field.
    fireEvent.keyDown(screen.getByRole('searchbox', { name: 'Filter features' }), { key: ' ' })
    expect(screen.getByRole('checkbox', { name: 'Research' })).not.toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Personas' })).not.toBeChecked()
  })

  // The picker is presentational and cannot know WHEN its caller sets `loading`, so a change the
  // user already made is held back too, from the Apply button and from Enter alike (Enter reaches
  // the confirm without going through the button's disabled state).
  it('holds back a change it already has, from Apply and from Enter', () => {
    const props = { open: true, catalog: CATALOG, onApply: vi.fn(), onCancel: vi.fn() }
    const { rerender } = render(<FeaturePickerDialog {...props} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Research' }))
    rerender(<FeaturePickerDialog {...props} loading />)
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
    fireEvent.keyDown(screen.getByRole('searchbox', { name: 'Filter features' }), { key: 'Enter' })
    expect(screen.queryByText('Add 1 feature?')).toBeNull()
  })
})

// `signin-apps` (labelled "Client Auth") requires `users`: ticking one has to tick the
// other, and `users` can't come off while `signin-apps` is still on.
describe('FeaturePickerDialog — feature requirements', () => {
  const REQ_CATALOG = [
    feature('users', 'Users'),
    { ...feature('signin-apps', 'Client Auth'), requiresFeatures: ['users'] },
  ]

  function renderReq(onApply = vi.fn()) {
    render(<FeaturePickerDialog open catalog={REQ_CATALOG} onApply={onApply} onCancel={vi.fn()} />)
  }

  it('ticking a feature also ticks what it requires', () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' }))
    expect(screen.getByRole('checkbox', { name: 'Client Auth' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Users' })).toBeChecked()
  })

  it("refuses to untick a feature still needed by an on feature, with an alert, and leaves it ticked", () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' })) // ticks Users too
    fireEvent.click(screen.getByRole('checkbox', { name: 'Users' })) // attempt to untick
    expect(
      screen.getByText('this feature is needed by Client Auth features'),
    ).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'OK' })) // dismiss the alert
    expect(screen.getByRole('checkbox', { name: 'Users' })).toBeChecked()
  })

  it('shows "Needed by 1" on the row a currently-on feature requires', () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' }))
    expect(screen.getByText('Needed by 1')).toBeInTheDocument()
  })

  it('shows no "Needed by" marker while nothing on requires the feature', () => {
    renderReq()
    expect(screen.queryByText(/^Needed by/)).toBeNull()
  })

  // A cyclic catalog: A requires B and B requires A. `requiredClosure` terminates the walk on
  // a `seen` set rather than hanging, but that walk can put a feature's OWN key in its own
  // closure that way — `neededByKey` must exclude that self-entry, the same guard `neededBy`
  // in feature-requirements.ts (data/ecosystems) already has (`f.key !== key`), or a feature would be shown as
  // needed by itself.
  it('never lists a feature as needed by itself, even in a cyclic catalog', () => {
    const CYCLIC = [
      { ...feature('feat-a', 'Feature A'), requiresFeatures: ['feat-b'] },
      { ...feature('feat-b', 'Feature B'), requiresFeatures: ['feat-a'] },
    ]
    render(<FeaturePickerDialog open catalog={CYCLIC} onApply={vi.fn()} onCancel={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Feature A' })) // cascades both on
    // Anchored: each row's OWN label starts its accessible name (concatenated with no space
    // before the needed-by text, e.g. "Feature ANeeded by Feature B"), so `/^Feature A/` picks
    // Row A even though Row B's needed-by text legitimately also contains "Feature A"
    // somewhere in its name (it is genuinely needed by A — that part is correct).
    const rowA = screen.getByRole('button', { name: /^Feature A/ })
    const rowB = screen.getByRole('button', { name: /^Feature B/ })
    expect(rowA.textContent).not.toContain('Needed by Feature A')
    expect(rowB.textContent).not.toContain('Needed by Feature B')
    expect(rowA.textContent).toContain('Needed by Feature B')
    expect(rowB.textContent).toContain('Needed by Feature A')
    // The visible count must also exclude the self-entry: 1, not 2.
    expect(within(rowA).getByText('Needed by 1')).toBeInTheDocument()
    expect(within(rowB).getByText('Needed by 1')).toBeInTheDocument()
  })

  // The marker must NOT be a second focusable element inside the row's own button (a keyboard
  // user tabbing through the list would never reach it there). Instead, what it needs to say is
  // folded into the ROW's own accessible name — the same technique the shared rail already uses
  // for `item.blocked`'s ", needs attention" text — so a screen reader announces it the moment
  // the row itself (already focusable, already reachable) gets focus. No second control, nothing
  // new to tab to.
  it("folds what needs it into the row's own accessible name, not a second focusable element", () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' }))
    const row = screen.getByRole('button', { name: /Needed by Client Auth/ })
    expect(row).toHaveAccessibleName(expect.stringContaining('Needed by Client Auth'))
    // Nothing focusable/interactive nested inside the row's own button — the marker rides along
    // as plain (non-interactive) content only.
    expect(within(row).queryAllByRole('button')).toHaveLength(0)
    expect(within(row).queryAllByRole('link')).toHaveLength(0)
    expect(within(row).queryAllByRole('tooltip')).toHaveLength(0)
  })

  // The floating hint bubble is driven by REAL focus of the row itself (the thing a keyboard
  // user actually tabs to), not a synthetic event fired at the badge — which is what the
  // previous version of this test did, proving nothing about real reachability.
  it('shows a floating hint on the row when the row itself is focused, hides it on blur', () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' }))
    const row = screen.getByRole('button', { name: /Needed by Client Auth/ })
    expect(screen.queryByText('Client Auth', { selector: '[data-slot="tooltip-content"]' })).toBeNull()
    fireEvent.focus(row)
    expect(screen.getByText('Client Auth', { selector: '[data-slot="tooltip-content"]' })).toBeInTheDocument()
    fireEvent.blur(row, { relatedTarget: document.body })
    expect(screen.queryByText('Client Auth', { selector: '[data-slot="tooltip-content"]' })).toBeNull()
  })

  // Same hint, driven by a real hover of the row (not the badge).
  it('shows the same floating hint on real hover of the row, hides it when the pointer leaves', () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' }))
    const row = screen.getByRole('button', { name: /Needed by Client Auth/ })
    expect(screen.queryByText('Client Auth', { selector: '[data-slot="tooltip-content"]' })).toBeNull()
    fireEvent.mouseOver(row)
    expect(screen.getByText('Client Auth', { selector: '[data-slot="tooltip-content"]' })).toBeInTheDocument()
    fireEvent.mouseOut(row, { relatedTarget: document.body })
    expect(screen.queryByText('Client Auth', { selector: '[data-slot="tooltip-content"]' })).toBeNull()
  })

  it('ticking the requiring feature applies both, in catalog order', () => {
    const onApply = vi.fn()
    renderReq(onApply)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' })) // add both
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    fireEvent.click(screen.getByRole('button', { name: 'Add' }))
    expect(onApply).toHaveBeenCalledWith({ add: ['users', 'signin-apps'], remove: [] })
  })

  it('once the requiring feature is off, the requirement can be unticked too', () => {
    renderReq()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' })) // ticks both
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client Auth' })) // back off
    fireEvent.click(screen.getByRole('checkbox', { name: 'Users' })) // now unblocked
    expect(screen.getByRole('checkbox', { name: 'Users' })).not.toBeChecked()
    expect(screen.queryByText('this feature is needed by Client Auth features')).toBeNull()
  })

  it('never ticks a comingSoon requirement it cannot provision', () => {
    const catalog = [
      { ...feature('coming', 'Coming Feature'), comingSoon: true },
      { ...feature('needs-coming', 'Needs Coming'), requiresFeatures: ['coming'] },
    ]
    render(<FeaturePickerDialog open catalog={catalog} onApply={vi.fn()} onCancel={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Needs Coming' }))
    expect(screen.getByRole('checkbox', { name: 'Needs Coming' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Coming Feature' })).not.toBeChecked()
  })
})

// A feature this ecosystem may not add (a client ecosystem and Organizations), as the feature
// manager reports it: disabled like a coming-soon row, never brought in as a requirement.
describe('FeaturePickerDialog — unavailable to this ecosystem', () => {
  const REASON = "Only a user's or an organization's own ecosystem can have Organizations."
  const unavailable = new Map([['organizations', REASON]])
  const catalog = [feature('organizations', 'Organizations'), feature('personas', 'Personas')]

  it('disables the tick, refuses a click, and says why in the details', () => {
    const onApply = vi.fn()
    render(<FeaturePickerDialog open catalog={catalog} unavailable={unavailable} onApply={onApply} onCancel={vi.fn()} />)
    const box = screen.getByRole('checkbox', { name: 'Organizations' })
    expect(box).toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(box)
    expect(box).not.toBeChecked()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: /Organizations/ }))
    expect(screen.getByText(REASON)).toBeInTheDocument()
  })

  it('never ticks one as another feature\'s requirement', () => {
    const withTeams = [...catalog, { ...feature('teams', 'Teams'), requiresFeatures: ['organizations'] }]
    render(<FeaturePickerDialog open catalog={withTeams} unavailable={unavailable} onApply={vi.fn()} onCancel={vi.fn()} />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Teams' }))
    expect(screen.getByRole('checkbox', { name: 'Teams' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Organizations' })).not.toBeChecked()
  })

  it('keeps a held one live for unticking, with no reason shown', () => {
    render(
      <FeaturePickerDialog
        open
        catalog={catalog}
        alreadyProvisioned={new Set(['organizations'])}
        unavailable={unavailable}
        onApply={vi.fn()}
        onCancel={vi.fn()}
      />,
    )
    const box = screen.getByRole('checkbox', { name: 'Organizations' })
    expect(box).not.toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(box)
    expect(box).not.toBeChecked()
    expect(screen.queryByText(REASON)).toBeNull()
  })
})
