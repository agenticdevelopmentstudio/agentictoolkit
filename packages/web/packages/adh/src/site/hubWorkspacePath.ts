import { HUB_ROUTE_SEGMENTS } from '@agentic-toolkit/adh-registry'

/**
 * The hub's workspace routes that carry NO slug.
 *
 * `/home` is the redirect that resolves one — the family's signal, identical on all 38 sites.
 * `/settings` is the account (not a workspace): it used to be `/home/settings` and moved off
 * when `/home` stopped being a page. Both are signed-in surfaces, so the switcher stays in its
 * in-hub mode there; `useSiteMenu` fills the slug the feature links need from the signed-in
 * user's own (`personalSlug`), which is what those links pointed at anyway.
 *
 * `/admin` is the hub's Admin workspace — the operations console, listed in the workspace menu
 * for an admin. Its data is platform-wide, so it belongs to no backend workspace and carries no
 * slug, but it IS a workspace in the switcher, so the switcher must stay in in-hub mode there.
 */
const SLUGLESS_APP_SEGMENTS: ReadonlySet<string> = new Set(['home', 'settings', 'admin'])

/** Is this first path segment one the HUB's own routes have spoken for? */
function isRouteSegment(segment: string): boolean {
  return HUB_ROUTE_SEGMENTS.has(segment.toLowerCase())
}

/** The first path segment of `pathname`, or undefined at the root. */
function firstSegment(pathname: string): string | undefined {
  return (pathname || '/').split('/').filter(Boolean)[0]
}

/**
 * True when `pathname` is inside the hub's authenticated workspace — `/<workspace>` or anything
 * under it — or on one of the two slug-less app routes above. Drives the switcher's in-hub mode;
 * only meaningful on the hub itself.
 *
 * ONE segment decides it, and that is the route convergence's doing. The hub's root used to be
 * `[slug]`, a public user profile, with the workspace hanging off it at `/<slug>/home` — so the
 * only way to tell a workspace URL from a profile was to look at the SECOND segment and ask
 * whether it named a known feature. The root is `[workspace]` now and nothing else is dynamic
 * there, so everything under a first segment that is not one of the site's own routes is the
 * workspace tree by construction. `/acme/about` is a 404 INSIDE that tree, and the second-segment
 * test called it marketing.
 *
 * The set it asks is `HUB_ROUTE_SEGMENTS` — the hub's OWN top-level routes, held to
 * `SITE_ROUTES['hub']` in both directions by adh-registry's lockstep case. It used to ask
 * `reservedWorkspaceSlugs()`, the union every slug MINT form refuses, on the reasoning that a
 * wider list can only err toward "not a workspace" and that the dangerous direction is a route
 * missing from a hand-written list: that is how `/features/projects` (a marketing page whose id
 * collides with a feature segment) wore the signed-in menu the moment those pages moved under a
 * prefix. The lockstep is what closes that direction, and it closes it better than width did —
 * it fails on the commit that adds the route, rather than relying on somebody having reserved
 * the word for an unrelated reason.
 *
 * What width could not do is be right in the other direction. The mint list is 41 words wider
 * than what the API refuses (`RESERVED_PRINCIPAL_SLUGS`: the rdid type prefixes plus the route
 * words — `teams`, `support`, `research`, `me` and 37 more are held back by the two forms on
 * taste alone), and both lists refuse only at MINT time, so every one of those is a slug a
 * principal can be holding right now. A workspace slugged any of them read as a hub route here:
 * `hubWorkspaceSlug` returned null, and `useSiteMenu` substituted the visitor's OWN slug into
 * every feature link while they were looking at someone else's workspace — a wrong destination
 * that resolves, which is worse than the 404 the other direction gives. "Is this segment a hub
 * route" is a question about the hub's route tree, and only the hub's route tree can answer it.
 *
 * It answers TRUE for a slug that resolves to nothing — `/typo` is a workspace address whose
 * workspace the caller is not in, and it renders the shared not-found. That is not the
 * "test by exclusion" trap: the claim here is about what the URL ADDRESSES, not about a route
 * existing, and the family's rule is that the root segment addresses a principal. A page that
 * needs to know whether the workspace resolves asks the workspace list, which is what the route's
 * own gate does.
 */
export function isHubWorkspacePath(pathname: string): boolean {
  const first = firstSegment(pathname)
  if (first === undefined) return false
  return SLUGLESS_APP_SEGMENTS.has(first) || !isRouteSegment(first)
}

/**
 * The workspace slug `pathname` addresses, or null when it addresses none.
 *
 * Null on the slug-less pair above as well as off the workspace entirely, and that is the whole
 * distinction {@link isHubWorkspacePath} does not draw: `/home` and `/settings` ARE workspace
 * chrome, they just carry no slug, so the caller falls back to the signed-in user's own.
 */
export function hubWorkspaceSlug(pathname: string): string | null {
  const first = firstSegment(pathname)
  return first !== undefined && !isRouteSegment(first) ? first : null
}
