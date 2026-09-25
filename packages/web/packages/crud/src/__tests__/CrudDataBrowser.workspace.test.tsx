import '@testing-library/jest-dom/vitest'
import { beforeEach, describe, it, expect, vi } from 'vitest'
import { act, render, screen, waitFor, within } from '@testing-library/react'
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
// The has-rows probe: every table in EMPTY answers no rows, a table in FAIL rejects with its
// error, and every other answers one. Records each probe URL, and the signal it was sent with, so
// a test can see what the probe asked. A probe for a table in HOLD waits until it is aborted.
const EMPTY = new Set<string>()
const FAIL = new Map<string, unknown>()
const HOLD = new Set<string>()
const probes: string[] = []
const signals: AbortSignal[] = []
vi.mock('@agentic-toolkit/auth/client', async (importOriginal) => ({
  // The real module underneath, for its AuthHttpError (the probe tells a refusal from a failure
  // by it) and for the session watch that forgets remembered answers.
  ...(await importOriginal<typeof import('@agentic-toolkit/auth/client')>()),
  authedJson: async (url: string, init?: RequestInit) => {
    probes.push(url)
    if (init?.signal) signals.push(init.signal)
    const path = url.replace(/^\/api/, '').split('?')[0] ?? ''
    if (HOLD.has(path)) {
      await new Promise((_, reject) =>
        init?.signal?.addEventListener('abort', () => reject(new Error('aborted'))),
      )
    }
    if (FAIL.has(path)) throw FAIL.get(path)
    return EMPTY.has(path) ? [] : [{ id: 'r1' }]
  },
}))
beforeEach(() => {
  EMPTY.clear()
  FAIL.clear()
  HOLD.clear()
  probes.length = 0
  signals.length = 0
  localStorage.removeItem('auth_tokens')
})
// Reports the list filter the view was handed — the one thing the browser decides for it — and
// records every render, so a test can see a view that mounted and was gone again inside one act().
const opened: string[] = []
beforeEach(() => {
  opened.length = 0
})
vi.mock('../CrudDataView', () => ({
  CrudDataView: ({ meta, filter }: { meta: CrudTableMeta; filter?: Record<string, string> }) => {
    const view = `${meta.key} ${JSON.stringify(filter ?? null)}`
    opened.push(view)
    return <div data-testid="open">{view}</div>
  },
}))

const { CrudDataBrowser } = await import('../CrudDataBrowser')
const { AuthHttpError } = await import('@agentic-toolkit/auth/client')
const { resetTablesWithRows } = await import('../useTablesWithRows')
// Answers are remembered at module scope, which outlives a render(), and most tests here share one
// filter and one set of tables: without this they would read each other's answer.
beforeEach(() => resetTablesWithRows())

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
          {level.items.length === 0 && <li>{level.emptyLabel}</li>}
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

  // Leaving mid-sweep used to leave every worker draining the queue for an answer nobody would
  // read, overlapping the next mount's sweep.
  it('aborts the probes in flight on unmount, and sends none of the queued ones', async () => {
    const many = Array.from({ length: 12 }, (_, i) => table('bucket', `t${i}`, ['ecosystemId']))
    for (const t of many) HOLD.add(t.basePath)
    const { unmount } = render(
      <CrudDataBrowser basePath="/w/all-data" tables={many} shell={RailProbe} workspace="w" />,
    )
    // The concurrency bound: 8 in flight, 4 queued.
    await waitFor(() => expect(probes).toHaveLength(8))
    expect(signals).toHaveLength(8)
    unmount()
    expect(signals.every((s) => s.aborted)).toBe(true)
    // Let the aborted workers settle: none of them picks up another table.
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(probes).toHaveLength(8)
  })

  // A scope change re-renders the browser rather than remounting it, and the has-rows answer used
  // to be cleared inside the sweep's effect, one render too late: that render listed the previous
  // scope's tables under the new filter, and mounted the open table's view on a list for the new
  // scope that no probe had confirmed.
  it('never shows the previous scope’s tables under a new one', async () => {
    const at = (workspace: string) => (
      <CrudDataBrowser
        basePath={`/${workspace}/all-data`}
        tables={TABLES}
        shell={RailProbe}
        workspace={workspace}
        activeSchema="bucket"
        activeTable="buckets"
      />
    )
    const { rerender } = render(at('w'))
    await screen.findByText('persona')
    expect(opened).toContain('bucket/buckets {"workspace":"w"}')
    // The new scope's probes have not answered yet.
    HOLD.add('/bucket/buckets')
    HOLD.add('/persona/personas')
    rerender(at('x'))
    expect(opened).not.toContain('bucket/buckets {"workspace":"x"}')
    expect(schemaRows()).toEqual(['Loading…'])
  })
})

// A failed probe is not an empty table: a 5xx or a dropped connection says nothing about the
// rows, and counting it as "none" told a scope full of data "No data yet.".
describe('CrudDataBrowser when a has-rows probe fails', () => {
  it('says it couldn’t load, not "No data yet.", when the probes fail', async () => {
    FAIL.set('/bucket/buckets', new AuthHttpError(500, 'boom'))
    FAIL.set('/persona/personas', new TypeError('Failed to fetch'))
    render(<CrudDataBrowser basePath="/w/all-data" tables={TABLES} shell={RailProbe} workspace="w" />)
    expect(await screen.findByText("Couldn't load this data. Try again.")).toBeInTheDocument()
    expect(screen.queryByText('No data yet.')).not.toBeInTheDocument()
  })

  it('still lists only the tables a probe confirmed, never every candidate', async () => {
    FAIL.set('/persona/personas', new AuthHttpError(502, 'bad gateway'))
    render(<CrudDataBrowser basePath="/w/all-data" tables={TABLES} shell={RailProbe} workspace="w" />)
    await screen.findByText('bucket')
    expect(schemaRows()).toEqual(['bucket'])
  })

  it('counts a 403 or a 404 as no rows', async () => {
    FAIL.set('/bucket/buckets', new AuthHttpError(403, 'forbidden'))
    FAIL.set('/persona/personas', new AuthHttpError(404, 'not found'))
    render(<CrudDataBrowser basePath="/w/all-data" tables={TABLES} shell={RailProbe} workspace="w" />)
    expect(await screen.findByText('No data yet.')).toBeInTheDocument()
  })
})

// Every schema or table click on the standalone route remounts the browser, and each mount used to
// blank the rail and the pane to "Loading…" and probe every table again — 61 probes for a
// workspace — before the open table's own list could start.
describe('CrudDataBrowser across remounts', () => {
  const browser = (open: { activeSchema?: string; activeTable?: string } = {}) => (
    <CrudDataBrowser
      basePath="/w/all-data"
      tables={TABLES}
      shell={RailProbe}
      workspace="w"
      {...open}
    />
  )

  it('opens the open table on its own probe, without waiting on the rest', async () => {
    HOLD.add('/bucket/buckets')
    render(browser({ activeSchema: 'persona', activeTable: 'personas' }))
    expect(await screen.findByTestId('open')).toHaveTextContent(
      'persona/personas {"workspace":"w"}',
    )
    expect(probes[0]).toBe('/api/persona/personas?workspace=w&limit=1')
    // Nothing unprobed is listed: bucket has not answered, so the rail holds persona alone.
    expect(schemaRows()).toEqual(['persona'])
  })

  it('shows the remembered answer on a remount at once, then asks again quietly', async () => {
    EMPTY.add('/persona/personas')
    const first = render(browser())
    await screen.findByText('bucket')
    first.unmount()
    // The persona table gains its first row elsewhere — someone added a persona in its feature.
    EMPTY.clear()
    probes.length = 0
    render(browser())
    // From memory, in the first render: no Loading…, no blank rail.
    expect(schemaRows()).toEqual(['bucket'])
    expect(screen.queryByText('Loading…')).not.toBeInTheDocument()
    // Then the quiet sweep lists the table that was just filled, instead of hiding it until the
    // page reloads.
    await screen.findByText('persona')
    expect(schemaRows()).toEqual(['bucket', 'persona'])
    expect(probes).toHaveLength(2)
  })

  it('keeps the remembered answer when asking again fails', async () => {
    const first = render(browser())
    await screen.findByText('persona')
    first.unmount()
    FAIL.set('/persona/personas', new AuthHttpError(502, 'bad gateway'))
    probes.length = 0
    render(browser())
    await waitFor(() => expect(probes).toHaveLength(2))
    // One macrotask: every settled probe's continuation, and the sweep's own, runs before it.
    await act(() => new Promise((resolve) => setTimeout(resolve, 0)))
    // The failed sweep's partial answer (bucket alone) is not put on screen over the good one.
    expect(schemaRows()).toEqual(['bucket', 'persona'])
    expect(screen.queryByText("Couldn't load this data. Try again.")).not.toBeInTheDocument()
  })

  it('asks again after a sweep that failed', async () => {
    FAIL.set('/persona/personas', new AuthHttpError(502, 'bad gateway'))
    const first = render(browser())
    await screen.findByText('bucket')
    first.unmount()
    FAIL.clear()
    render(browser())
    await screen.findByText('persona')
    expect(schemaRows()).toEqual(['bucket', 'persona'])
  })

  it('forgets every answer when someone else signs in', async () => {
    const first = render(browser())
    await screen.findByText('persona')
    first.unmount()
    // Another tab signs in as someone else, so the tokens change under this one.
    localStorage.setItem(
      'auth_tokens',
      JSON.stringify({ accessToken: 'h.eyJzdWIiOiJ1MiJ9.s', refreshToken: 'r' }),
    )
    window.dispatchEvent(new StorageEvent('storage'))
    render(browser())
    // Nothing is remembered for the new principal, so the rail waits on its own sweep rather than
    // showing the previous person's tables.
    expect(within(screen.getByLabelText('schema rail')).getByText('Loading…')).toBeInTheDocument()
    await screen.findByText('persona')
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
