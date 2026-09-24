import '@testing-library/jest-dom/vitest'
import { describe, it, expect, vi } from 'vitest'
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
  it('lists only the tables a workspace can own', () => {
    render(<CrudDataBrowser basePath="/w/all-data" tables={TABLES} shell={RailProbe} workspace="w" />)
    expect(schemaRows()).toEqual(['bucket', 'persona'])
  })

  it('sends the workspace as the open table’s list filter', () => {
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
    expect(screen.getByTestId('open')).toHaveTextContent('bucket/buckets {"workspace":"w"}')
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
