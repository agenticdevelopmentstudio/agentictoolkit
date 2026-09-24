import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'

// The dialog reads the catalog and the ecosystem's features over react-query; what this asserts is
// only that the menu opens it, for the ecosystem it was given.
vi.mock('./ManageFeaturesDialog', () => ({
  ManageFeaturesDialog: ({ ecosystemId, onClose }: { ecosystemId: string; onClose: () => void }) => (
    <div role="dialog" aria-label={`manage ${ecosystemId}`}>
      <button onClick={onClose}>close</button>
    </div>
  ),
}))

import { FeaturesToolMenu } from './FeaturesToolMenu'

describe('FeaturesToolMenu', () => {
  it('opens the picker scoped to its own ecosystem from "Manage features…"', async () => {
    render(<FeaturesToolMenu ecosystemId="ecosystem.acme.widgets" label="Widgets features tools" />)

    // Nothing is fetched or shown until someone asks.
    expect(screen.queryByRole('dialog')).toBeNull()

    fireEvent.click(screen.getByRole('button', { name: 'Widgets features tools' }))
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Manage features…' }))

    expect(await screen.findByRole('dialog', { name: 'manage ecosystem.acme.widgets' })).toBeTruthy()

    fireEvent.click(screen.getByRole('button', { name: 'close' }))
    expect(screen.queryByRole('dialog', { name: 'manage ecosystem.acme.widgets' })).toBeNull()
  })
})
