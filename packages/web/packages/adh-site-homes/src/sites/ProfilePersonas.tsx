'use client'

import type { ReactElement } from 'react'
import type { ProfilePrincipal } from '@agentic-toolkit/adh/profile'
import { registryUserPersonaPath, siteProdUrl, siteUrl } from '@agentic-toolkit/adh-registry'
import { useClientHost } from '@agentic-toolkit/adh/header'

/**
 * This site's section of a principal's profile at `/<slug>/profile` — declared as
 * `profileSection` on `home-model.tsx` (the `SiteHomeModel` field documented in
 * `@agentic-toolkit/adh/home`).
 *
 * Lives here, in the site, rather than in `@agentic-toolkit/personas`: it imports the adh
 * vocabulary tier (`@agentic-toolkit/adh/profile`, `@agentic-toolkit/adh-registry`,
 * `@agentic-toolkit/adh/header`) directly, which a portable feature package may not do
 * (`scripts/check_boundaries.py`) — a site is a consumer of that vocabulary, not a package other
 * products reuse, and this component's whole job is rendering one site's `profileSection`.
 *
 * `ProfileView` (`packages/web/packages/adh/src/profile/ProfileView.tsx`) renders `UserCard`
 * directly above whatever this returns, and `UserCard` already draws a `Personas` section
 * (`external/adhsdk/packages/web/packages/ui/src/blocks/user-card.tsx`) listing each persona's `name`, a `Badge`
 * for its `visibility`, and its `description`. Repeating those here would be the same list twice,
 * one scroll apart, so this section renders what the card does NOT: each persona's public
 * ADDRESS — where to go and read it. That is genuinely this site's own contribution; the card
 * states attributes, this says where.
 *
 * Fetches nothing: `principal.personas` is already part of the public card both principal
 * endpoints return (`UserCardDto.personas`), and `ProfilePrincipal.personas` carries it through
 * non-optionally, so there is no data layer to add for a roster already in the prop. The roster is
 * already audience-filtered by the backend, so this renders every entry it was handed and makes no
 * visibility decision of its own — in particular it does NOT filter on `visibility` to try to
 * guess which links will resolve.
 *
 * A persona is not addressable on THIS site — agenticdeveloperpersonas.com is where personas are
 * defined (its registry entry reads `description: 'Define your personas'`,
 * `packages/web/packages/adh-registry/src/sites/registry.ts`), not where they are read. Public
 * personas are read on `personaregistry` (`agenticpersonaregistry.com`), so the link is built with
 * that package's own helpers rather than a hand-rolled host or path: `registryUserPersonaPath` is
 * "the address that says whose it is" — the owner-scoped form `/<owner>/<persona>` — and
 * `siteUrl` resolves the right host for the current environment (local suite / testing / staging /
 * prod).
 *
 * The host comes from `useClientHost` (`@agentic-toolkit/adh/header`) — `null` on the server AND
 * on the first client render, the real host once mounted — rather than a direct
 * `globalThis.location` read. This component carries `'use client'`, but a client component still
 * renders on the SERVER first, where `location` is undefined: a direct read would make the server
 * see `''` and the first client render see the real host, disagreeing on every `href` here and
 * logging a hydration error. `ProfileView`, the component that renders this one as its `children`,
 * guards its own `Full Profile` link the same way and says so. `siteProdUrl` is a correct absolute
 * URL in every environment — just not the environment-local one — so the pre-mount render is
 * never broken, only less local until the post-mount re-render.
 *
 * A link built this way is not a promise the recipient can open it — a `hub`-visibility persona
 * resolves for a signed-in viewer and 404s for an anonymous one. That is carried over from
 * `personaProfileUrl`'s own caveat and applies here verbatim; it is not corrected by filtering the
 * roster, since the backend already audience-filtered what it returned.
 */
export function ProfilePersonas({ principal }: { principal: ProfilePrincipal }): ReactElement {
  // Before the early return: a hook cannot be called conditionally.
  const hostname = useClientHost()
  const personas = principal.personas
  const subject = principal.kind === 'organization' ? 'This organization' : 'This user'
  if (personas.length === 0) {
    return (
      <section className="mt-8">
        <p className="text-sm text-apt-text-muted">{subject} has no public personas.</p>
      </section>
    )
  }
  // Deterministic prod host until mounted; see the docblock above.
  const hrefFor = (personaSlug: string): string => {
    const path = registryUserPersonaPath(principal.slug, personaSlug)
    return hostname ? siteUrl('personaregistry', path, hostname) : siteProdUrl('personaregistry', path)
  }
  return (
    <section className="mt-8">
      <h2 className="mb-3 font-mono text-[0.6rem] uppercase tracking-[0.1em] text-apt-text-dim">
        Public personas
      </h2>
      <ul className="space-y-2">
        {personas.map((p) => (
          <li
            key={p.slug}
            className="rounded-lg border border-apt-border bg-apt-surface px-4 py-3"
          >
            <div className="font-medium text-apt-text">{p.name}</div>
            <a
              href={hrefFor(p.slug)}
              className="text-sm text-apt-text-muted underline underline-offset-4 hover:text-apt-text"
            >
              View persona
            </a>
          </li>
        ))}
      </ul>
    </section>
  )
}
