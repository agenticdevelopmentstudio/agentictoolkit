import '@testing-library/jest-dom/vitest'
import { beforeEach, describe, it, expect, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import type { AuthUser } from '@agentic-toolkit/auth'
import type { CrudColumn, CrudTableMeta } from '../types'
import type { CrudShellProps } from '../CrudDataBrowser'

// "All data literally shows all data, it should only show data owned by the workspace"
// (Mike, 2026-09-24): a workspace-scoped browser lists only the tables the backend can narrow to
// one workspace, and sends every list `?workspace=<slug>`.

const admin = { id: 'u1', email: 'u@example.com', capabilities: ['admin'] } as AuthUser
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: vi.fn() }) }))
vi.mock('@agentic-toolkit/auth', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@agentic-toolkit/auth')>()),
  useOptionalAuth: () => ({ user: admin, isLoading: false }),
  useAuth: () => ({ user: admin, isLoading: false }),
}))
// The has-rows probe: every table in EMPTY answers no rows, every other answers one. Records each
// probe URL so a test can see what the probe asked.
const EMPTY = new Set<string>()
const probes: string[] = []
vi.mock('@agentic-toolkit/auth/client', () => ({
  authedJson: async (url: string) => {
    probes.push(url)
    const path = url.replace(/^\/api/, '').split('?')[0] ?? ''
    return EMPTY.has(path) ? [] : [{ id: 'r1' }]
  },
}))
beforeEach(() => {
  EMPTY.clear()
  probes.length = 0
})
// Reports the list filter the view was handed — the one thing the browser decides for it.
vi.mock('../CrudDataView', () => ({
  CrudDataView: ({ meta, filter }: { meta: CrudTableMeta; filter?: Record<string, string> }) => (
    <div data-testid="open">{`${meta.key} ${JSON.stringify(filter ?? null)}`}</div>
  ),
}))

const { CrudDataBrowser } = await import('../CrudDataBrowser')

const col = (name: string): CrudColumn =>
  ({ name, type: 'string', required: false, nullable: false, serverManaged: false }) as CrudColumn
const table = (schema: string, name: string, columns: string[]): CrudTableMeta => ({
  key: `${schema}/${name}`,
  schema,
  table: name,
  basePath: `/${schema}/${name}`,
  itemPath: `/${schema}/${name}/{id}`,
  pkParams: ['id'],
  exposure: 'owner',
  columns: ['id', ...columns].map(col),
})

const TABLES = [
  table('bucket', 'buckets', ['ecosystemId']),
  table('persona', 'personas', ['ownerKind', 'ownerId']),
  // A global catalog: no workspace owns its rows, so the backend cannot narrow it.
  table('usage', 'rate-limit-tiers', ['name']),
  // Half an owner pair is not one.
  table('usage', 'counters', ['ownerId']),
]

function RailProbe({ levels, children }: CrudShellProps) {
  return (
    <div>
      {levels.map((level) => (
        <ul key={level.id} aria-label={`${level.id} rail`}>
          {level.items.map((item) => (
            <li key={item.id}>{item.label}</li>
          ))}
        </ul>
      ))}
      {children}
    </div>
  )
}

const schemaRows = () =>
  within(screen.getByLabelText('schema rail'))
    .getAllByRole('listitem')
    .map((li) => li.textContent)

describe('CrudDataBrowser scoped to a workspace', () => {
  it('lists only the tables a workspace can own', async () => {
    render(<CrudDataBrowser basePath="/w/all-data" tables={TABLES} shell={RailProbe} workspace="w" />)
    await screen.findByText('bucket')
    expect(schemaRows()).toEqual(['bucket', 'persona'])
  })

  it('sends the workspace as the open table’s list filter', async () => {
    render(
      <CrudDataBrowser
        basePath="/w/all-data"
        tables={TABLES}
        shell={RailProbe}
        workspace="w"
        activeSchema="bucket"
        activeTable="buckets"
      />,
    )
    expect(await screen.findByTestId('open')).toHaveTextContent('bucket/buckets {"workspace":"w"}')
  })

  // "in All Data only show tables and schemas in the list with data in them" (Mike, 2026-09-24).
  it('drops tables with no rows, and a schema left with none', async () => {
    EMPTY.add('/persona/personas')
    render(<CrudDataBrowser basePath="/w/all-data" tables={TABLES} shell={RailProbe} workspace="w" />)
    await screen.findByText('bucket')
    expect(schemaRows()).toEqual(['bucket'])
    // Each probe is the table's own list, under the view's filter, for one row.
    expect(probes).toContain('/api/bucket/buckets?workspace=w&limit=1')
  })
})

// "ONLY THE ECOSYSTEMS TABLES SHOULD SHOW - this is a huge huge huge data leak" (Mike, 2026-09-24).
describe('CrudDataBrowser scoped to an ecosystem', () => {
  it('lists only ecosystem tables and filters every list to that ecosystem', async () => {
    render(
      <CrudDataBrowser
        basePath="/w/all-data"
        tables={TABLES}
        shell={RailProbe}
        workspace="w"
        ecosystemId="ecosystem.ads.ape"
        activeSchema="bucket"
        activeTable="buckets"
      />,
    )
    expect(await screen.findByTestId('open')).toHaveTextContent(
      'bucket/buckets {"workspace":"w","ecosystemId":"ecosystem.ads.ape"}',
    )
    // The owner-pair table cannot be narrowed to one ecosystem, so it is not offered.
    expect(schemaRows()).toEqual(['bucket'])
  })

  it('stays the unscoped browser without a workspace', () => {
    render(
      <CrudDataBrowser
        basePath="/all-data"
        tables={TABLES}
        shell={RailProbe}
        activeSchema="usage"
        activeTable="rate-limit-tiers"
      />,
    )
    expect(schemaRows()).toEqual(['bucket', 'persona', 'usage'])
    expect(screen.getByTestId('open')).toHaveTextContent('usage/rate-limit-tiers null')
  })
})
