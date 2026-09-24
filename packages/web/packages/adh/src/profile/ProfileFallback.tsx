'use client'

import { useEffect, useMemo, useState, type ReactElement, type ReactNode } from 'react'
import type { SiteId } from '@agentic-toolkit/adh-registry'
import { principalFromOrgCard, principalFromUserCard, type OrgCardBody, type UserCardBody } from './normalize'
import { ProfileNotFound } from './ProfileNotFound'
import { PROFILE_FRAME_CLASS } from './frame'
import { ProfileView } from './ProfileView'
import type { ProfilePrincipal } from './types'
import { useViewerPrincipal } from './useViewerPrincipal'

type State =
  | { status: 'loading' }
  | { status: 'found'; principal: ProfilePrincipal }
  | { status: 'missing' }
  | { status: 'error' }

export interface ProfileFallbackProps {
  slug: string
  siteId: SiteId
  /**
   * The site's own addition to the profile, as a RENDER PROP rather than a node.
   *
   * It has to be a function because the principal it describes is not known when this component is
   * mounted — that is the entire difference between this component and `ProfileClient`'s seeded
   * branch. A caller with no principal in hand cannot call `site.home.profileSection(principal)`
   * itself, so it hands over the function and this calls it once the lookup lands.
   *
   * Deliberately NOT applied to the `ProfileNotFound` or error renders: there is no principal to
   * pass, and a site section rendered under "no such profile" would be describing nobody.
   */
  section?: (principal: ProfilePrincipal) => ReactNode
}

/**
 * The profile, fetched on the CLIENT for a slug the caller could not open as a workspace.
 *
 * This is the `/<slug>` half of the feature, and it is client-side for a reason the server half
 * is not: whether a caller can reach a workspace is only known after the workspace list resolves
 * in the browser, so the decision to show a profile instead happens well after the server
 * response has been sent.
 *
 * It is ALSO the un-seeded half of `/<slug>/profile`. That route does fetch on the server, but only
 * the ANONYMOUS layer is reachable from there — a `hub` profile, or any principal whose visibility
 * excludes the anonymous public, comes back empty for a viewer who is nonetheless entitled to see
 * it, and a backend that is down comes back empty for everybody. Neither is a verdict, so the
 * route treats its server fetch as a SEED: a hit renders straight through, a miss hands the slug to
 * this component and the two-layer lookup below decides. What the server fetch is still solely
 * responsible for is `generateMetadata`, which has no second chance in the browser (see the route's
 * page.tsx).
 *
 * Three outcomes on the anonymous layer, and they are deliberately not two:
 *   - 404 → the not-found page with its search. "No such principal" and "not visible to you" are
 *     the same answer on purpose; telling an anonymous caller that a slug exists but is hidden is
 *     itself the disclosure the visibility switch exists to prevent.
 *   - any other failure → an error, NOT the not-found page. A not-found page invites a search
 *     that would fail exactly the same way, which reads as "you typed it wrong" when the truth is
 *     "we are down".
 *
 * The signed-in layer sits ABOVE all three. `useViewerPrincipal(slug, null)` asks the authed
 * twins the same question with the viewer's own token, and its answer wins whenever it arrives —
 * that is the path a `hub` profile takes for the people it is meant for, and without it this
 * component would render "Profile not found" to exactly the audience the `hub` setting exists to
 * admit. The public 404 is only final for a viewer the authed twin also refuses.
 *
 * That "only final" is why the render order below holds `missing` and `error` back with
 * `viewerPending`: the anonymous pair and the authed pair are two independent requests racing
 * each other, the authed one usually slower (it may need a token refresh first), so a `hub`
 * profile's expected FIRST answer is the public miss — for exactly the viewers the setting exists
 * to admit. Rendering that miss before the authed pair settles is the flash this component exists
 * to avoid. A resolved `found` state does not wait: it is already a correct render, and holding it
 * back for a widening that may only add fields would delay a page that is already right.
 *
 * `ProfileView` runs the same hook internally (it is where the widening lives for all six
 * consumers), so a `hub` profile reached through here costs one duplicate GET to the authed twin.
 * That is the price of keeping the widening a property of the view rather than of every caller;
 * it happens on one code path, for signed-in viewers only, and never on the anonymous render.
 */
export function ProfileFallback({ slug, siteId, section }: ProfileFallbackProps): ReactElement | null {
  const [state, setState] = useState<State>({ status: 'loading' })
  const { principal: viewer, pending: viewerPending } = useViewerPrincipal(slug, null)
  // Memoized on `viewer` (not recomputed on every render): the anonymous pair keeps racing in
  // the background after the viewer branch has already won, and each of its settlements is a
  // `setState` — a render this component must survive without calling `section` again for the
  // SAME principal. Recomputing here on every render would call it once per background
  // settlement, defeating "even while the anonymous pair is still 404ing" (profileFallback.test.tsx).
  const viewerSection = useMemo(() => (viewer ? section?.(viewer) : undefined), [viewer, section])

  useEffect(() => {
    let cancelled = false
    setState({ status: 'loading' })
    void (async () => {
      try {
        const encoded = encodeURIComponent(slug)
        const users = await fetch(`/api/public/users/${encoded}`)
        if (cancelled) return
        if (users.ok) {
          const body = (await users.json()) as UserCardBody
          if (!cancelled) setState({ status: 'found', principal: principalFromUserCard(body) })
          return
        }
        if (users.status !== 404) return setState({ status: 'error' })

        const orgs = await fetch(`/api/public/orgs/${encoded}`)
        if (cancelled) return
        if (orgs.ok) {
          const body = (await orgs.json()) as OrgCardBody
          if (!cancelled) setState({ status: 'found', principal: principalFromOrgCard(body) })
          return
        }
        if (orgs.status === 404) return setState({ status: 'missing' })
        setState({ status: 'error' })
      } catch {
        if (!cancelled) setState({ status: 'error' })
      }
    })()
    return () => {
      cancelled = true
    }
  }, [slug])

  // The entitled viewer's answer supersedes every anonymous outcome, including the error one:
  // if the authed twin resolved the principal, the page is not broken for this visitor. This
  // component already ran useViewerPrincipal to decide THAT, so ProfileView is told not to run
  // it again with upgrade={false} — a second identical lookup would be pure waste.
  if (viewer)
    return (
      <ProfileView principal={viewer} siteId={siteId} upgrade={false}>
        {viewerSection}
      </ProfileView>
    )
  if (state.status === 'loading') return null
  if (state.status === 'found')
    return (
      <ProfileView principal={state.principal} siteId={siteId} upgrade={false}>
        {section?.(state.principal)}
      </ProfileView>
    )
  // Neither "not found" nor "we are down" is final while the viewer's own lookup is still
  // running: a `hub` profile is a 404 on the anonymous route BY DESIGN, so the public miss
  // is the expected first answer for the very viewers the setting exists to admit.
  if (viewerPending) return null
  if (state.status === 'missing') return <ProfileNotFound />
  return (
    <main className={PROFILE_FRAME_CLASS}>
      <p className="text-apt-text-muted">
        Couldn&apos;t load this profile. Reload the page to try again.
      </p>
    </main>
  )
}
