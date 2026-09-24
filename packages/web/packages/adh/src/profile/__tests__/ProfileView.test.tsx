import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { principalFromOrgCard, principalFromUserCard, type OrgCardBody, type UserCardBody } from '../normalize'
import { ProfileSkeleton, ProfileView } from '../ProfileView'
import type { ProfilePrincipal } from '../types'

/**
 * ProfileView is rendered with NO AuthProvider above it, which is the point rather than a
 * convenience: the component ships on 41 sites and its `useViewerPrincipal` reads
 * `useOptionalAuth`, so "no provider" must mean "anonymous viewer, no upgrade" and must not
 * throw. Every assertion below is therefore about the ANONYMOUS render — the seed principal
 * exactly as the server resolved it.
 */
function principal(over: Partial<ProfilePrincipal> = {}): ProfilePrincipal {
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
    kind: 'user',
    ...over,
  }
}

describe('ProfileView', () => {
  it('renders the shared header for the principal it was handed', () => {
    render(<ProfileView principal={principal()} siteId="projects" />)
    // UserCard labels its <article> with the display name, so this asserts the HEADER is the
    // card rather than merely that the name appears somewhere on the page.
    expect(screen.getByRole('article', { name: "Fish Lamp's profile" })).toBeInTheDocument()
    expect(screen.getByText('@fishlamp')).toBeInTheDocument()
  })

  it("renders an organization's blurb, which a user card has no field for", () => {
    // `description` is the one field that runs org → user rather than the other way. A user
    // principal carries none, so this is also what distinguishes the two renders.
    render(
      <ProfileView
        principal={principal({ kind: 'organization', description: 'We make lamps for fish.' })}
        siteId="projects"
      />,
    )
    expect(screen.getByText('We make lamps for fish.')).toBeInTheDocument()
  })

  it('renders the passed child section between the header and the footer link', () => {
    render(
      <ProfileView principal={principal()} siteId="projects">
        <section aria-label="Projects">Three public projects</section>
      </ProfileView>,
    )
    expect(screen.getByRole('region', { name: 'Projects' })).toBeInTheDocument()
  })

  it('links to the hub from a site that is not the hub', () => {
    render(<ProfileView principal={principal()} siteId="projects" />)
    const link = screen.getByRole('link', { name: 'Full Profile' })
    // Not asserting the host: `siteUrl` resolves it from the environment, and pinning it here
    // would make this test a second copy of the registry's env detection rather than a check
    // that the profile links to the right PATH.
    expect(link.getAttribute('href')).toContain('/fishlamp')
  })

  it('renders NO Full Profile link on the hub, because that link would point at this page', () => {
    render(<ProfileView principal={principal()} siteId="hub" />)
    expect(screen.queryByRole('link', { name: 'Full Profile' })).toBeNull()
  })
})

/**
 * The hub's `/<slug>/profile` loading boundary renders ProfileSkeleton, and the page streams
 * ProfileView into the same spot when the fetch lands. The boundary used to draw its own copy
 * of the frame; these pin the one thing that copy existed to get right.
 */
describe('ProfileSkeleton', () => {
  it("announces the card as loading, inside the page's main landmark", () => {
    render(<ProfileSkeleton />)
    expect(screen.getByRole('main')).toContainElement(
      screen.getByRole('status', { name: 'Loading profile…' }),
    )
  })

  it("draws in ProfileView's own frame, so the profile replaces it in place instead of jumping", () => {
    const skeleton = render(<ProfileSkeleton />)
    const frame = skeleton.container.querySelector('main')!.className
    skeleton.unmount()
    // Non-empty first: two frames that both lost their class would also be "equal".
    expect(frame).not.toBe('')
    render(<ProfileView principal={principal()} siteId="hub" />)
    expect(screen.getByRole('main').className).toBe(frame)
  })
})

/**
 * The other test in this file renders an organization, but its fixture (via `principal()`)
 * supplies all five collections as `[]` already, so it never actually exercises
 * `principalFromOrgCard` — it would pass unchanged if `normalize.ts` were deleted. These tests
 * feed the normalizers the REAL wire shapes directly: `OrgCardBody` carries none of the five
 * collections, which is exactly the defect `normalize.ts` fixes — those fields arriving
 * `undefined` is what makes `UserCard` throw on `.length`.
 */
describe('normalize', () => {
  it('principalFromOrgCard fills the five missing collections with [] and stamps organization', () => {
    const body: OrgCardBody = {
      slug: 'fishlamp',
      displayName: 'Fish Lamp',
      description: 'We make lamps for fish.',
      createdAt: '2026-01-02T03:04:05.000Z',
      personas: [],
    }
    const result = principalFromOrgCard(body)
    expect(result.socialLinks).toEqual([])
    expect(result.emails).toEqual([])
    expect(result.phones).toEqual([])
    expect(result.addresses).toEqual([])
    expect(result.kind).toBe('organization')
    expect(result.description).toBe('We make lamps for fish.')
  })

  it('principalFromUserCard stamps user and passes a populated collection through untouched', () => {
    const body: UserCardBody = {
      slug: 'fishlamp',
      displayName: 'Fish Lamp',
      avatarUrl: null,
      createdAt: '2026-01-02T03:04:05.000Z',
      socialLinks: [{ platform: 'bluesky', url: 'https://bsky.app/fishlamp', handle: '@fishlamp' }],
      emails: [],
      phones: [],
      addresses: [],
      personas: [],
    }
    const result = principalFromUserCard(body)
    expect(result.kind).toBe('user')
    expect(result.socialLinks).toBe(body.socialLinks)
  })
})
