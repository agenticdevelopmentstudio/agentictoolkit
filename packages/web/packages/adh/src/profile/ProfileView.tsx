'use client'

import type { ReactElement, ReactNode } from 'react'
import type { SiteId } from '@agentic-toolkit/adh-registry'
import { siteUrl, siteProdUrl } from '@agentic-toolkit/adh-registry'
import { UserCard, UserCardSkeleton } from '@agenticdevelopertoolkit/ui/blocks/user-card'
import { useClientHost } from '../header/useClientHost'
import { PROFILE_FRAME_CLASS } from './frame'
import type { ProfilePrincipal } from './types'
import { useViewerPrincipal } from './useViewerPrincipal'

export interface ProfileViewProps {
  principal: ProfilePrincipal
  /** The site this profile is being viewed ON, which decides whether the Full Profile link
   *  renders. Passed as a plain string from the server page rather than read from the site config
   *  here: a config is a SERVER-graph module (`site/SiteConfig`) and importing it from this
   *  client component would drag `research`'s sitemap reads into a browser bundle. */
  siteId: SiteId
  /** This site's own public section, or nothing. */
  children?: ReactNode
  /** Whether this view runs the signed-in widening itself. Default true, which is what
   *  every server-rendered consumer wants. `ProfileFallback` passes false because it
   *  already ran the hook to decide WHICH principal to render, and a second identical
   *  lookup would be pure waste. */
  upgrade?: boolean
}

/**
 * A principal's profile, in the arrangement every site in the fleet shares:
 *
 *   [ standard header — avatar, name, general public info ]
 *   [ this site's own section, or nothing ]
 *   [ Full Profile → the hub, unless this IS the hub ]
 *
 * Lives in `@agentic-toolkit/adh` rather than `packages/ui` because it has to know site ids and
 * which one is the hub, and `ui` is the generic layer that must not.
 *
 * The header is `<UserCard>` unchanged — it already renders exactly what "general public info"
 * means here, and the backend has already removed every row the viewer may not see, so this
 * component makes no visibility decision of its own. It renders what it was handed.
 *
 * The one thing it does on its own is the second layer of the two-layer resolution: it runs
 * `useViewerPrincipal` over the principal it was given and renders the wider answer if one
 * arrives. That lives HERE, rather than in each of the six consumers, so every one of them gets
 * the signed-in widening without an API change — the prop stays "the principal you resolved",
 * and whether the viewer is entitled to more is this component's business, not theirs. The seed
 * is always a valid render, so a failed or absent upgrade simply leaves the anonymous view
 * standing. `upgrade={false}` is the one opt-out: `ProfileFallback` already ran the same hook to
 * decide which principal to render in the first place, so it passes its answer straight through
 * and tells this component not to duplicate the lookup.
 */
export function ProfileView({
  principal,
  siteId,
  children,
  upgrade = true,
}: ProfileViewProps): ReactElement {
  // Never null: `useViewerPrincipal` returns its seed until an upgrade lands, and the seed here
  // is a required prop. The `??` is for the type, not for a case that can occur. The hook cannot
  // be called conditionally, so `upgrade` is threaded through as its `enabled` parameter rather
  // than branching at the call site.
  const { principal: shown0 } = useViewerPrincipal(principal.slug, principal, upgrade)
  const shown = shown0 ?? principal

  // On the hub there is no link: the hub's profile IS the full profile, so a link back to itself
  // would be a link to the page the visitor is already on.
  //
  // The target is `/<slug>/profile`, not `/<slug>` — the hub's root segment resolves by
  // ownership (the signed-in owner's own workspace, not a profile view), so a bare slug would
  // send this component's own owner-viewing-their-own-card case somewhere other than the profile
  // it is linking to. `/<slug>/profile` is unconditional: it renders the profile no matter who is
  // looking, which is the one guarantee this link needs.
  //
  // `useClientHost` (`null` on the server AND the first client render, the real host once
  // mounted) rather than a direct `globalThis.location` read: this component carries 'use
  // client', but a client component still renders on the SERVER first, where `location` is
  // undefined. A direct read would make the server see a prod host of `''` and the first client
  // render see the real one, disagreeing on `fullProfileHref` and logging a hydration error.
  // `siteProdUrl` is a correct absolute URL in every environment — just not the environment-local
  // one — so the pre-mount render is never broken, only less local until the post-mount re-render.
  const hostname = useClientHost()
  const fullProfileHref =
    siteId === 'hub'
      ? null
      : hostname
        ? siteUrl('hub', `/${encodeURIComponent(shown.slug)}/profile`, hostname)
        : siteProdUrl('hub', `/${encodeURIComponent(shown.slug)}/profile`)

  return (
    <main className={PROFILE_FRAME_CLASS}>
      <UserCard user={shown} />
      {/* The org's own blurb. Users have no equivalent, so this renders for organizations only —
          it is the "any public facing general info" half of the standardized header, and dropping
          it would show an org's profile without the one sentence the org wrote about itself. */}
      {shown.description && (
        <p className="mt-4 text-apt-text-muted">{shown.description}</p>
      )}
      {children}
      {fullProfileHref && (
        <div className="mt-8 text-center">
          {/* A plain <a>, not next/link: the target is a different origin in every environment,
              so client-side routing cannot serve it. */}
          <a
            href={fullProfileHref}
            className="text-sm text-apt-text-muted underline underline-offset-4 hover:text-apt-text"
          >
            Full Profile
          </a>
        </div>
      )}
    </main>
  )
}

/**
 * A profile on its way: the card's own skeleton, in ProfileView's frame, so the profile
 * replaces it in place when it arrives. A route's loading boundary (the hub's
 * `/<slug>/profile/loading.tsx`) renders this rather than composing the two itself: the frame
 * and the card are this directory's to change, and a site-side copy of either would stop
 * matching the day one of them does.
 */
export function ProfileSkeleton(): ReactElement {
  return (
    <main className={PROFILE_FRAME_CLASS}>
      <UserCardSkeleton />
    </main>
  )
}
