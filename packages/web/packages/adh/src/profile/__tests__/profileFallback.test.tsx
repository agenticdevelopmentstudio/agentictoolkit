import type { ReactNode } from 'react'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import type { ProfilePrincipal } from '../types'

/**
 * `ProfileFallback` had no test file before this one: it is mocked wholesale in
 * `siteHomeShell.test.tsx` and `workspaceOrProfileGate.test.tsx`, so none of its own branches,
 * and none of the `section` render prop's two call sites, were ever asserted.
 *
 * `ProfileView` is mocked so this file is about WHICH principal `section` is invoked with and on
 * WHICH branch, not how the card itself renders (that is `ProfileView.test.tsx`'s job). The mock
 * renders `children` so a case can still see the section's own output. `useViewerPrincipal` is
 * controlled directly per case, the same way the component's own doc comment says its caller
 * never needs to run it twice. `fetch` stands in for the two anonymous `/api/public/...` calls.
 */
vi.mock('../ProfileView', () => ({
  ProfileView: ({ children }: { children?: ReactNode }) => (
    <div data-testid="profile-view">{children}</div>
  ),
  ProfileSkeleton: () => <div data-testid="profile-skeleton" />,
}))

const { viewerResult } = vi.hoisted(() => ({
  viewerResult: {
    current: { principal: null as ProfilePrincipal | null, pending: false },
  },
}))
vi.mock('../useViewerPrincipal', () => ({
  useViewerPrincipal: () => viewerResult.current,
}))

const { ProfileFallback } = await import('../ProfileFallback')

function userCardBody(over: Partial<Omit<ProfilePrincipal, 'kind' | 'description'>> = {}) {
  return {
    slug: 'fishlamp',
    displayName: 'Fish Lamp',
    avatarUrl: null,
    createdAt: '2026-01-02T03:04:05.000Z',
    socialLinks: [],
    emails: [],
    phones: [],
    addresses: [],
    personas: [],
    ...over,
  }
}

function principal(over: Partial<ProfilePrincipal> = {}): ProfilePrincipal {
  return {
    ...userCardBody(),
    kind: 'user',
    ...over,
  }
}

function jsonResponse(body: unknown, status = 200) {
  return { ok: status >= 200 && status < 300, status, json: async () => body } as Response
}

let fetchMock: ReturnType<typeof vi.fn>

beforeEach(() => {
  fetchMock = vi.fn((url: string) => {
    throw new Error(`unexpected fetch in this case: ${url}`)
  })
  vi.stubGlobal('fetch', fetchMock)
  viewerResult.current = { principal: null, pending: false }
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('ProfileFallback', () => {
  it('found: the anonymous lookup resolving a principal renders the section with THAT principal, no viewer', async () => {
    fetchMock.mockImplementation((url: string) => {
      if (url.includes('/api/public/users/')) {
        return Promise.resolve(jsonResponse(userCardBody({ slug: 'foundslug', displayName: 'Found Slug' })))
      }
      throw new Error(`unexpected fetch: ${url}`)
    })
    const section = vi.fn((p: ProfilePrincipal): ReactNode => (
      <div data-testid="section-output">{p.slug}</div>
    ))

    render(<ProfileFallback slug="foundslug" siteId="projects" section={section} />)

    await waitFor(() => expect(screen.getByTestId('section-output')).toBeInTheDocument())
    expect(screen.getByTestId('section-output')).toHaveTextContent('foundslug')
    expect(section).toHaveBeenCalledTimes(1)
    expect(section).toHaveBeenCalledWith(expect.objectContaining({ slug: 'foundslug', kind: 'user' }))
  })

  it('viewer: a signed-in viewer principal renders the section with THAT principal, even while the anonymous pair is still 404ing both endpoints — the hub-visibility path', async () => {
    fetchMock.mockImplementation((url: string) => {
      if (url.includes('/api/public/users/')) return Promise.resolve(jsonResponse({}, 404))
      if (url.includes('/api/public/orgs/')) return Promise.resolve(jsonResponse({}, 404))
      throw new Error(`unexpected fetch: ${url}`)
    })
    viewerResult.current = {
      principal: principal({ slug: 'viewerslug', displayName: 'Viewer Slug' }),
      pending: false,
    }
    const section = vi.fn((p: ProfilePrincipal): ReactNode => (
      <div data-testid="section-output">{p.slug}</div>
    ))

    render(<ProfileFallback slug="viewerslug" siteId="hub" section={section} />)

    expect(screen.getByTestId('section-output')).toHaveTextContent('viewerslug')
    expect(section).toHaveBeenCalledTimes(1)
    expect(section).toHaveBeenCalledWith(expect.objectContaining({ slug: 'viewerslug', kind: 'user' }))
    // The anonymous pair is still racing in the background; only its OUTCOME is overridden, so
    // let it settle before the case ends rather than leaving a state update outside `act`.
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
  })

  it('missing: a 404 on both anonymous endpoints with no viewer renders ProfileNotFound, and section is never called', async () => {
    fetchMock.mockImplementation((url: string) => {
      if (url.includes('/api/public/users/')) return Promise.resolve(jsonResponse({}, 404))
      if (url.includes('/api/public/orgs/')) return Promise.resolve(jsonResponse({}, 404))
      throw new Error(`unexpected fetch: ${url}`)
    })
    const section = vi.fn()

    render(<ProfileFallback slug="nobody" siteId="projects" section={section} />)

    await waitFor(() => expect(screen.getByText('Profile not found')).toBeInTheDocument())
    expect(section).not.toHaveBeenCalled()
  })

  it("error: a non-404 failure on the anonymous lookup, with no viewer, renders the reload copy — not ProfileNotFound — and section is never called", async () => {
    fetchMock.mockImplementation((url: string) => {
      if (url.includes('/api/public/users/')) return Promise.resolve(jsonResponse({}, 500))
      throw new Error(`unexpected fetch: ${url}`)
    })
    const section = vi.fn()

    render(<ProfileFallback slug="broken" siteId="projects" section={section} />)

    await waitFor(() =>
      expect(
        screen.getByText("Couldn't load this profile. Reload the page to try again."),
      ).toBeInTheDocument(),
    )
    expect(screen.queryByText('Profile not found')).toBeNull()
    expect(section).not.toHaveBeenCalled()
  })

  it('race: both anonymous endpoints settle to a 404 while the viewer lookup is still pending — renders the skeleton, not ProfileNotFound', async () => {
    fetchMock.mockImplementation((url: string) => {
      if (url.includes('/api/public/users/')) return Promise.resolve(jsonResponse({}, 404))
      if (url.includes('/api/public/orgs/')) return Promise.resolve(jsonResponse({}, 404))
      throw new Error(`unexpected fetch: ${url}`)
    })
    viewerResult.current = { principal: null, pending: true }

    const { container } = render(<ProfileFallback slug="pending" siteId="hub" />)

    // Give the anonymous pair time to settle to `missing` in the background — the point of this
    // case is that the still-pending viewer lookup holds that outcome back, not that the fetch
    // pair never ran.
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    expect(container).not.toBeEmptyDOMElement()
    expect(screen.getByTestId('profile-skeleton')).toBeInTheDocument()
    expect(screen.queryByText('Profile not found')).toBeNull()
  })

  it('loading: before the anonymous pair answers, renders the skeleton rather than a blank page', () => {
    fetchMock.mockImplementation(() => new Promise<Response>(() => {}))

    render(<ProfileFallback slug="slow" siteId="hub" />)

    expect(screen.getByTestId('profile-skeleton')).toBeInTheDocument()
    expect(screen.queryByTestId('profile-view')).toBeNull()
  })
})
