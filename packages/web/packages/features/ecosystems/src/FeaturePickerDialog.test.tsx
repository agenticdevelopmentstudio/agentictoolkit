import { render, screen, fireEvent } from '@testing-library/react'
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
