/** Per-site SEO metadata, derived from the site registry.
 *
 *  Every site in the family hand-rolled its own `metadata` export, and they
 *  drifted: of 47 apps, 46 had no canonical URL, 42 had no `openGraph` block at
 *  all, and 43 had no `twitter` block. That is not cosmetic — the family runs
 *  THREE public tiers of every site (`fishlamp.com`, `staging.…`, `testing.…`)
 *  serving byte-identical HTML, and with no `<link rel="canonical">` a search
 *  engine sees three competing copies and picks the winner itself. `og:url`
 *  does not help: it is not a canonicalization signal.
 *
 *  The registry already knows each site's production host and brand name, so
 *  the whole block is derivable from `SiteId` plus the two strings only a human
 *  can write (title and description). That is what `siteMetadata` does.
 *
 *  Framework-free apart from `import type` — same rule the rest of this package
 *  follows, so the backend's typecheck (no dom lib, no next runtime) still sees
 *  it. Anything needing the live request (the tier's hostname) is passed IN by
 *  the caller rather than read here; see `siteRobots`.
 */
import type { Metadata, MetadataRoute } from 'next'

import { getSite, type SiteId } from '../sites/registry'
import { DEV_BUILD } from '../deployment-env'

/** The one size every unfurler accepts, and the size `assets/logo/generate.py`
 *  emits into each site's `app/opengraph-image.png`. */
const OG_IMAGE_SIZE = { width: 1200, height: 630 } as const

/** The route Next serves `app/opengraph-image.png` from.
 *
 *  Named explicitly rather than left to Next's file convention, because that
 *  convention only fills in where a route declares no `openGraph` of its own.
 *  Any page that sets one — every page calling `siteMetadata` — would otherwise
 *  emit an Open Graph block with NO image and unfurl as a bare text link. The
 *  real route carries a cache-busting query (`?opengraph-image.<hash>.png`);
 *  this bare path serves the same bytes. */
const DEFAULT_CARD = '/opengraph-image.png'

export interface SiteSeo {
  /** The `<title>`. Long form is fine and preferred — "Brand — what it does". */
  title: string
  /** The meta description. Aim for 120–160 characters: shorter wastes the
   *  snippet, longer is truncated mid-sentence in results. */
  description: string
  /** The ONE route this metadata describes, enabling `<link rel="canonical">`
   *  and `og:url` for it. Always a PATH, never an absolute URL — it is resolved
   *  against `metadataBase`, which is what makes the canonical point at
   *  production even when the page is served from `staging.` or `testing.`.
   *
   *  Set this ONLY from a `page.tsx`, never from a `layout.tsx`. Next merges
   *  metadata down the route tree, so a canonical set in a root layout is
   *  inherited by every descendant: `/privacy` and `/terms` would each declare
   *  themselves a duplicate of `/` and ask to be dropped from the index. That is
   *  worse than no canonical at all, so a layout must leave this unset — hence
   *  no default. See `canonicalOnly` for the one-line page-level companion. */
  path?: string
  keywords?: string[]
  /** A bespoke social card served from `public/`, as a PATH (e.g. `/site/og.png`),
   *  for the few sites that have one designed. Resolved against `metadataBase`
   *  like everything else here, so the emitted URL is the production one.
   *
   *  Leave unset for the family mark, which every site has at
   *  `app/opengraph-image.png` (synced by deployment/sync-site-icons.py) and
   *  which is what `DEFAULT_CARD` below points at. */
  card?: string
}

/** Is this build allowed to say `index` in its robots meta tag?
 *
 *  Deliberately an explicit allowlist of the NON-production tiers rather than
 *  `=== 'production'`. `NEXT_PUBLIC_DEPLOYMENT_ENV` is inlined at build time and
 *  a site that forgets to set it would, under the inverted test, silently ship
 *  `noindex` to production and vanish from search — a failure nobody notices
 *  until traffic is already gone. Failing toward "indexable" is the recoverable
 *  direction; `siteRobots` below is host-based and cannot misfire, so the tiers
 *  are still covered if this var is unset.
 */
const NOINDEX_BUILD = DEV_BUILD

/** The full metadata block for a site, given only its id and its own copy.
 *
 *  Sites that ship a bespoke social card (devteam, myagenticteams,
 *  personaregistry) should keep their hand-written `openGraph.images` — spread
 *  this and override, rather than dropping the designed card:
 *
 *      export const metadata: Metadata = {
 *        ...siteMetadata('devteam', { title: TITLE, description: DESCRIPTION }),
 *        openGraph: { ...customOg },
 *      }
 */
export function siteMetadata(id: SiteId, seo: SiteSeo): Metadata {
  const site = getSite(id)
  const brand = site ? (site.fullLabel ?? site.label) : 'Agentic Developer Hub'
  const origin = `https://${site?.prodHost ?? 'agenticdeveloperhub.com'}`
  const card = seo.card ?? DEFAULT_CARD

  return {
    metadataBase: new URL(origin),
    title: seo.title,
    description: seo.description,
    applicationName: brand,
    ...(seo.keywords ? { keywords: seo.keywords } : {}),
    // Both of these name ONE route, so they appear only when the caller named
    // one. Relative, so they resolve against `metadataBase` — the PRODUCTION
    // origin — no matter which tier rendered the page.
    //
    // Omitting them is the safe default, not a compromise. An absent canonical
    // leaves a page to be indexed under its own URL, which is what we want; a
    // WRONG canonical (inherited from a layout) actively removes it. And an
    // absent `og:url` makes an unfurler use the URL it actually fetched, which
    // is right per page — better than every page claiming to be the homepage.
    ...(seo.path ? { alternates: { canonical: seo.path } } : {}),
    openGraph: {
      type: 'website',
      siteName: brand,
      title: seo.title,
      description: seo.description,
      ...(seo.path ? { url: seo.path } : {}),
      locale: 'en_US',
      images: [{ url: card, ...OG_IMAGE_SIZE }],
    },
    // The card must be declared large: without this, X and LinkedIn render the
    // image as a small square thumbnail beside the text rather than the
    // full-width banner a 1200x630 card is drawn for.
    twitter: {
      card: 'summary_large_image',
      title: seo.title,
      description: seo.description,
      images: [card],
    },
    robots: {
      index: !NOINDEX_BUILD,
      follow: !NOINDEX_BUILD,
      googleBot: {
        index: !NOINDEX_BUILD,
        follow: !NOINDEX_BUILD,
        'max-image-preview': 'large',
      },
    },
  }
}

/** Just the canonical, for a `page.tsx` whose title and description already come
 *  from its layout.
 *
 *  Next merges metadata key by key from the layout down, so this adds the one
 *  route-specific key without disturbing anything else. Deliberately does NOT
 *  set `openGraph.url`, even though the URL is known here: a page-level
 *  `openGraph` REPLACES the layout's rather than merging into it, so naming the
 *  url would silently drop the site name, locale, and card. A page that wants
 *  its own Open Graph block should call `siteMetadata(id, { …, path })` instead
 *  and get a complete one.
 *
 *      export const metadata: Metadata = canonicalOnly('/')
 */
export function canonicalOnly(path: string): Metadata {
  return { alternates: { canonical: path } }
}

/** The size to declare when a site DOES name its own card explicitly. */
export const ogImageSize = OG_IMAGE_SIZE

/** Hosts that are the real, indexable home of a site: the production host and
 *  its `www.` form. Everything else — `staging.`, `testing.`, `*.vercel.app`,
 *  `dev.test`, `localhost` — is a copy that must not be crawled. */
function isProductionHost(prodHost: string, host: string): boolean {
  const h = host.toLowerCase().replace(/:\d+$/, '')
  return h === prodHost || h === `www.${prodHost}`
}

export interface SiteRobotsOptions {
  /** Extra paths to keep out of the index on the production tier. Auth-gated
   *  and API routes belong here. */
  disallow?: string[]
}

/** robots.txt for a site, given the hostname actually serving the request.
 *
 *  Host-based rather than env-var-based on purpose: it is exact, needs no
 *  per-project configuration to be correct, and cannot be defeated by a missing
 *  environment variable. An unrecognised host is treated as non-production, so
 *  a preview deployment fails closed.
 *
 *  Callers pass the host from the request (`app/robots.ts` reads it via
 *  `headers()`), which keeps `next/headers` out of this framework-free package.
 */
export function siteRobots(
  id: SiteId,
  host: string,
  options: SiteRobotsOptions = {},
): MetadataRoute.Robots {
  const site = getSite(id)
  const prodHost = site?.prodHost ?? ''
  const origin = `https://${prodHost}`

  if (!prodHost || !isProductionHost(prodHost, host)) {
    // A non-production tier. Blocking the crawl is one of three layers that
    // keep these copies out of the index: the staging/testing BUILDS also emit
    // `robots: noindex` (see NOINDEX_BUILD), and every canonical and `og:url`
    // resolves against the production `metadataBase` rather than this host.
    return { rules: [{ userAgent: '*', disallow: '/' }] }
  }

  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        ...(options.disallow?.length ? { disallow: options.disallow } : {}),
      },
    ],
    sitemap: `${origin}/sitemap.xml`,
    host: origin,
  }
}

export interface SiteRoute {
  /** Path, not URL — resolved against the site's production origin. */
  path: string
  changeFrequency?: MetadataRoute.Sitemap[number]['changeFrequency']
  priority?: number
  /** When this specific route last changed, for the routes that KNOW.
   *
   *  A static marketing page does not know — the build time is the best answer
   *  available, which is the default below. A route backed by content with its
   *  own timestamp (a published research paper) does know, and saying so is the
   *  difference between a crawler re-fetching everything on every deploy and it
   *  re-fetching only what actually changed. */
  lastModified?: Date
}

/** sitemap.xml for a site, from a list of paths.
 *
 *  `lastModified` defaults to the BUILD time, not a literal date: static
 *  marketing pages are compiled from source, so a deploy is the modification. A
 *  hardcoded date rots the first time someone edits the copy without
 *  remembering this file exists. A route that carries its own modification date
 *  passes it per-route instead.
 *
 *  Always absolute production URLs, even when built for another tier — a
 *  sitemap listing `staging.` URLs would invite exactly the duplicate indexing
 *  the rest of this module exists to prevent.
 */
export function siteSitemap(id: SiteId, routes: SiteRoute[]): MetadataRoute.Sitemap {
  const site = getSite(id)
  const origin = `https://${site?.prodHost ?? 'agenticdeveloperhub.com'}`
  const buildTime = new Date()

  return routes.map((route) => ({
    url: `${origin}${route.path}`,
    lastModified: route.lastModified ?? buildTime,
    changeFrequency: route.changeFrequency ?? 'monthly',
    priority: route.priority ?? (route.path === '/' ? 1 : 0.5),
  }))
}
