import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'

// The dialog reads the catalog and the ecosystem's features over react-query; what this asserts is
// only that the button opens it, for the ecosystem it was given.
vi.mock('./ManageFeaturesDialog', () => ({
  ManageFeaturesDialog: ({ ecosystemId, onClose }: { ecosystemId: string; onClose: () => void }) => (
    <div role="dialog" aria-label={`manage ${ecosystemId}`}>
      <button onClick={onClose}>close</button>
    </div>
  ),
}))

import { ManageFeaturesButton } from './ManageFeaturesButton'

describe('ManageFeaturesButton', () => {
  it('opens the picker scoped to its own ecosystem in one click — no menu in between', async () => {
    render(<ManageFeaturesButton ecosystemId="ecosystem.acme.widgets" label="Manage widget features" />)

    // Nothing is fetched or shown until someone asks.
    expect(screen.queryByRole('dialog')).toBeNull()

    fireEvent.click(screen.getByRole('button', { name: 'Manage widget features' }))
    expect(screen.queryByRole('menu')).toBeNull()
    expect(await screen.findByRole('dialog', { name: 'manage ecosystem.acme.widgets' })).toBeTruthy()

    fireEvent.click(screen.getByRole('button', { name: 'close' }))
    expect(screen.queryByRole('dialog', { name: 'manage ecosystem.acme.widgets' })).toBeNull()
  })
})
