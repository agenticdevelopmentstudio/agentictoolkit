import '@testing-library/jest-dom/vitest'
import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { AuthUser } from '@agentic-toolkit/auth'
import type { CrudColumn, CrudTableMeta } from '../types'
import type { CrudShellProps } from '../CrudDataBrowser'

// An ecosystem's Storage ▸ All Data scoped its LIST to that ecosystem but not its writes: a row
// created there was stamped with the caller's JWT ecosystem (every hub JWT is ecosystem zero), and
// the re-list, filtered to this ecosystem, dropped it. The REAL editor is mounted here, because
// the write it sends is what is under test.

const ECO = 'ecosystem.ads.ape'
/** A non-admin: an owner-tier table is theirs to write. */
const member = { id: 'u1', email: 'u@example.com', capabilities: [] as string[] } as AuthUser

vi.mock('next/navigation', () => ({ useRouter: () => ({ push: vi.fn() }) }))
vi.mock('@agentic-toolkit/auth', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@agentic-toolkit/auth')>()),
  useOptionalAuth: () => ({ user: member, isLoading: false }),
  useAuth: () => ({ user: member, isLoading: false }),
}))
// The has-rows probe and the editor both reach the network through this client. The real module
// underneath supplies AuthHttpError, which the probe tells a refusal from a failure by.
vi.mock('@agentic-toolkit/auth/client', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@agentic-toolkit/auth/client')>()),
  authedJson: vi.fn(),
  authedRequest: vi.fn(),
}))

const { authedJson } = vi.mocked(await import('@agentic-toolkit/auth/client'))
const { CrudDataBrowser } = await import('../CrudDataBrowser')

const col = (name: string, overrides: Partial<CrudColumn> = {}): CrudColumn => ({
  name,
  type: 'string',
  required: false,
  nullable: false,
  serverManaged: false,
  ...overrides,
})

const BUCKETS: CrudTableMeta = {
  key: 'bucket/buckets',
  schema: 'bucket',
  table: 'buckets',
  basePath: '/bucket/buckets',
  itemPath: '/bucket/buckets/{id}',
  pkParams: ['id'],
  exposure: 'owner',
  columns: [col('id', { serverManaged: true }), col('ecosystemId'), col('name')],
}

/** The rail is not under test here; the shell only has to render the open table's editor. */
function RailProbe({ children }: CrudShellProps) {
  return <div>{children}</div>
}

describe('CrudDataBrowser scoped to an ecosystem', () => {
  it('creates a new row in that ecosystem, not the caller’s', async () => {
    authedJson.mockImplementation(
      async (_url: string, init?: RequestInit) =>
        (init?.method === 'POST'
          ? { id: 'b2', ecosystemId: ECO, name: 'Fresh' }
          : [{ id: 'b1', ecosystemId: ECO, name: 'Existing' }]) as never,
    )
    const user = userEvent.setup()
    render(
      <CrudDataBrowser
        basePath="/w/all-data"
        tables={[BUCKETS]}
        shell={RailProbe}
        workspace="w"
        ecosystemId={ECO}
        activeSchema="bucket"
        activeTable="buckets"
      />,
    )
    await screen.findByText('Existing')
    await user.click(screen.getByRole('button', { name: 'Create' }))
    await user.type(await screen.findByLabelText('name'), 'Fresh')
    // The surface has already decided the ecosystem, so the new row's form does not offer it.
    expect(screen.queryByLabelText('ecosystemId')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Save' }))

    // Named on the URL (the scope the backend authorizes the write against) AND in the body (the
    // row's own column), so the re-list, filtered to this ecosystem, finds the row it just made.
    await waitFor(() =>
      expect(authedJson).toHaveBeenCalledWith(
        `/api/bucket/buckets?ecosystemId=${ECO}`,
        expect.objectContaining({ method: 'POST' }),
      ),
    )
    const post = authedJson.mock.calls.find(([, init]) => init?.method === 'POST')
    expect(JSON.parse(String(post?.[1]?.body))).toEqual({ ecosystemId: ECO, name: 'Fresh' })
  })
})
