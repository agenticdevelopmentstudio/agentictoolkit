'use client'

import type { ReactElement, ReactNode } from 'react'
import type { SiteId } from '@agentic-toolkit/adh-registry'
import { makeSmartHeaderAuth } from '@agentic-toolkit/adh/header-auth'
// The package path, never a relative one, even though SiteHeader is now a sibling
// directory in this same package. `header/index` is its own tsup entry with a matching
// `external`, because it holds module-level state (`envOverride`'s listener Set); a
// relative specifier would inline a private copy of it into THIS entry. Both halves of
// that remedy are required — see the note atop layout/AppShell.tsx and
// <adh-tools>/sites/scripts/verify-bundle-boundaries.py.
import { SiteHeader } from '@agentic-toolkit/adh/header'
// `NavLink` is a GENERIC header type. It used to have two possible spellings — the
// toolkit barrel and the app tier's `@adh/chrome/header`, which deliberately did not
// re-export the generic pieces. The merge left ONE barrel publishing both halves, so
// there is one spelling, and it is the same one SiteHeader above comes from.
import type { NavLink } from '@agentic-toolkit/adh/header'

// Built ONCE at module scope: the source is a hook (it calls useAuth) and
// SiteHeader invokes it unconditionally each render, so it must be a stable
// reference — never rebuilt inline. ONE source for the whole family, which is why
// `returnTo` is omitted rather than bound per site: the shared default reads the
// `siteId` SiteHeader forwards at click time, so login/sign-up started on a site's
// landing goes on to that site's own /home and anywhere else comes back to the page
// the visitor is on (defaultReturnTo, docs/platform/login-and-return.md §2).
const useMarketingHeaderAuth = makeSmartHeaderAuth({ clientId: 'adh' })

export type MarketingSiteHeaderProps = {
  /** The marketing site this header is for — drives the header brand. */
  siteId: SiteId
  /** Optional site-owned nav items (static + serializable — this crosses the
   *  server→client boundary from a site's layout via MarketingRootHtml). */
  navLinks?: NavLink[]
  /** Optional site-owned items rendered OUTSIDE the collapsing nav, at the bar's
   *  trailing edge (an off-site link like GitHub). Same serializable constraint. */
  trailingNavLinks?: NavLink[]
  /** Site-specific controls at the start of the right-hand cluster — cookbook's
   *  reader toggles. Passed by a CLIENT caller (this component is the boundary),
   *  which is why it is a node rather than the serializable link shape above. */
  leadingActions?: ReactNode
}

/**
 * The session-aware header for the marketing/feature-site family — SiteHeader
 * bound to the shared smart source (`makeSmartHeaderAuth`, the personaregistry
 * pattern): the avatar shows when signed in, Login/Sign up run the central SSO
 * flow with the shared home-or-root returnTo, and site switches ride the
 * silent-SSO bounce. See docs/platform/feature-sites-redesign.md.
 *
 * Exists as its own client component because {@link MarketingRootHtml} is a
 * server component: a hook prop (`useAuthSource`) can't cross the server→client
 * boundary, so the source is bound here, on the client side of it.
 *
 * Home: `@agentic-toolkit/adh/marketing` — adh VOCABULARY end to end (the ADH marketing family's
 * header, bound to adh's `clientId`). It is its OWN export subpath, not just a member of
 * the `marketing` barrel: this module is `'use client'` while its barrel-mates
 * (MarketingRootHtml, MarketingLanding, StorySections) are server components, and under
 * `bundle: true, splitting: false` an inlined `'use client'` leaf hoists its directive over
 * the WHOLE entry file. Same boundary trick as marketing/LandingHeroGate.
 */
export function MarketingSiteHeader({
  siteId,
  navLinks,
  trailingNavLinks,
  leadingActions,
}: MarketingSiteHeaderProps): ReactElement {
  return (
    <SiteHeader
      siteId={siteId}
      useAuthSource={useMarketingHeaderAuth}
      navLinks={navLinks}
      trailingNavLinks={trailingNavLinks}
      leadingActions={leadingActions}
    />
  )
}
