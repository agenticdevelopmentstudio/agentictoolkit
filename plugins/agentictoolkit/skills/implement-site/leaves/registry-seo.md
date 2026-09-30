<!-- leaf: implement-site/registry-seo · source: site-registry-seo.md -->

**Rules** (cite as `implement-site/registry-seo#<slug>`):

- `site-metadata-brand` MUST
- `site-metadata-origin` MUST
- `site-metadata-title-description` MUST
- `site-metadata-keywords` MUST
- `site-metadata-canonical` MUST
- `site-metadata-og-url` MUST
- `site-metadata-og-block` MUST
- `site-metadata-card` MUST
- `site-metadata-twitter` MUST
- `site-metadata-robots-gate` MUST
- `canonical-only-scope` MUST
- `site-robots-non-production` MUST
- `site-robots-production` MUST
- `site-robots-disallow-option` MUST
- `site-sitemap-origin` MUST
- `site-sitemap-mapping` MUST
- `site-sitemap-last-modified` MUST
- `site-sitemap-change-frequency` MUST
- `site-sitemap-priority` MUST
- `og-image-size-export` MUST
- `noindex-build-evaluation` MUST
- `functions-are-pure` MUST
- `seo-path-scope` MUST
- `seo-path-is-a-path` MUST
- `bespoke-card-override` SHOULD
- `extra-disallow-paths` MAY

# Site Registry SEO

## Overview

`metadata.ts` (`@agentic-toolkit/adh-registry`, `src/seo/metadata.ts`) is the shared SEO
layer for every site in the ADH family. It exposes four pure functions —
`siteMetadata`, `canonicalOnly`, `siteRobots`, `siteSitemap` — plus the `ogImageSize`
constant, all derived from a `SiteId` (looked up in the site registry via `getSite`) and
a small amount of caller-supplied copy. It exists because, per the module's own doc
comment, 46 of 47 sites had no canonical URL and most had no `openGraph`/`twitter`
block at all, which matters specifically because the family runs three public tiers of
byte-identical HTML (`fishlamp.com`, `staging.…`, `testing.…`) that a search engine
would otherwise index as competing duplicates. This recipe is the contract for a port
of that layer to another runtime.

## Behavioral Requirements

- **site-metadata-brand**: `siteMetadata` MUST set `applicationName` and
  `openGraph.siteName` to `getSite(id)`'s `fullLabel` when present, else its `label`,
  else the literal string `"Agentic Developer Hub"` when `id` resolves to no `SiteDef`.
- **site-metadata-origin**: `siteMetadata` MUST set `metadataBase` to
  `https://<prodHost>` of the resolved `SiteDef`, or to `https://agenticdeveloperhub.com`
  when `id` resolves to no `SiteDef`, regardless of which host actually served the
  request.
- **site-metadata-title-description**: `siteMetadata` MUST set the returned `Metadata`'s
  `title` and `description` to `seo.title` and `seo.description` verbatim.
- **site-metadata-keywords**: `siteMetadata` MUST set `keywords` to `seo.keywords`
  whenever `seo.keywords` is a truthy value — including an empty array — and MUST omit
  the `keywords` key entirely only when `seo.keywords` is `undefined`.
- **site-metadata-canonical**: `siteMetadata` MUST set `alternates.canonical` to
  `seo.path`, resolved against `metadataBase`, only when `seo.path` is a non-empty
  string; it MUST omit `alternates` entirely otherwise.
- **site-metadata-og-url**: `siteMetadata` MUST set `openGraph.url` to `seo.path` only
  when `seo.path` is a non-empty string; it MUST omit `openGraph.url` otherwise.
- **site-metadata-og-block**: `siteMetadata` MUST set `openGraph.type` to `"website"`,
  `openGraph.locale` to `"en_US"`, and `openGraph.images` to a single-element array
  whose entry is the resolved card URL sized 1200×630, on every call.
- **site-metadata-card**: `siteMetadata` MUST use `seo.card`, resolved against
  `metadataBase`, as the image in both `openGraph.images` and `twitter.images` when
  `seo.card` is not `null`/`undefined`, and MUST fall back to `/opengraph-image.png`
  otherwise.
- **site-metadata-twitter**: `siteMetadata` MUST set `twitter.card` to
  `"summary_large_image"` and `twitter.images` to a single-element array containing the
  same card URL used for `openGraph.images`.
- **site-metadata-robots-gate**: `siteMetadata` MUST set `robots.index`,
  `robots.follow`, `robots.googleBot.index` and `robots.googleBot.follow` to `false`
  when the build-time `NOINDEX_BUILD` value is `true`, and to `true` otherwise, and MUST
  set `robots.googleBot['max-image-preview']` to `"large"` unconditionally.
- **canonical-only-scope**: `canonicalOnly` MUST return a `Metadata` value containing
  only `alternates.canonical` set to the given path; it MUST NOT set `title`,
  `description`, or any `openGraph`/`twitter` key.
- **site-robots-non-production**: `siteRobots` MUST return
  `{ rules: [{ userAgent: '*', disallow: '/' }] }`, with no `sitemap` or `host` key,
  when `id` resolves to no `SiteDef`, when the resolved `SiteDef`'s `prodHost` is an
  empty string, or when the given `host` (lower-cased, with a trailing `:<port>`
  stripped) equals neither `prodHost` nor `www.<prodHost>`.
- **site-robots-production**: `siteRobots` MUST return
  `{ rules: [{ userAgent: '*', allow: '/' }], sitemap: '<origin>/sitemap.xml', host: '<origin>' }`
  (`origin` = `https://<prodHost>`) when `host` is the production host or its `www.`
  form.
- **site-robots-disallow-option**: `siteRobots` MUST add a `disallow` key to the
  production rule set to `options.disallow` verbatim only when `options.disallow` is a
  non-empty array; it MUST omit `disallow` when `options.disallow` is `undefined` or an
  empty array.
- **site-sitemap-origin**: `siteSitemap` MUST resolve every entry's URL against
  `https://<prodHost>` of the resolved `SiteDef`, or against
  `https://agenticdeveloperhub.com` when `id` resolves to no `SiteDef`.
- **site-sitemap-mapping**: `siteSitemap` MUST map each element of `routes` to one
  `MetadataRoute.Sitemap` entry whose `url` is the resolved origin concatenated directly
  with `route.path`.
- **site-sitemap-last-modified**: `siteSitemap` MUST set `lastModified` to
  `route.lastModified` when it is provided, and otherwise to one `Date` value captured
  once at the start of the `siteSitemap` call and shared by every route in that call
  that omits `lastModified`.
- **site-sitemap-change-frequency**: `siteSitemap` MUST set `changeFrequency` to
  `route.changeFrequency` when provided and MUST default to `"monthly"` otherwise.
- **site-sitemap-priority**: `siteSitemap` MUST set `priority` to `route.priority` when
  it is not `null`/`undefined`, and MUST otherwise default to `1` when `route.path` is
  exactly the string `"/"` and to `0.5` for every other path string.
- **og-image-size-export**: The module MUST export `ogImageSize` as the constant
  `{ width: 1200, height: 630 }`, the size `assets/logo/generate.py` emits into every
  site's `app/opengraph-image.png`.
- **noindex-build-evaluation**: The `NOINDEX_BUILD` value MUST be computed once, from
  `DEV_BUILD` (itself computed once at module load, from three `===` comparisons against
  `process.env.NEXT_PUBLIC_DEPLOYMENT_ENV`), and MUST NOT be re-read or recomputed per
  call to `siteMetadata`.
- **functions-are-pure**: `siteMetadata`, `canonicalOnly`, `siteRobots` and `siteSitemap`
  MUST be synchronous and MUST NOT read or write any module-level mutable state; the only
  module-level values they read (`OG_IMAGE_SIZE`, `DEFAULT_CARD`, `NOINDEX_BUILD`) are
  assigned once at module load and never reassigned.
- **seo-path-scope**: Callers MUST set `seo.path` only from a `page.tsx`-level metadata
  export, never from a `layout.tsx`, because Next merges metadata down the route tree
  and a canonical inherited from a layout would mark every descendant route a duplicate
  of it.
- **seo-path-is-a-path**: `seo.path` and `route.path` MUST be site-relative paths, never
  absolute URLs; neither `siteMetadata` nor `siteSitemap` validates a leading slash or
  otherwise normalizes the value before using it.
- **bespoke-card-override**: A caller whose site has a designed social card SHOULD
  spread `siteMetadata`'s result and override only `openGraph.images`, rather than
  hand-rolling the whole `Metadata` object, so that title, description, robots and the
  Twitter block stay in sync with the shared contract. Rationale: three sites (devteam,
  myagenticteams, personaregistry) do this today per the function's own doc comment, and
  duplicating the whole object risks the fields drifting out of sync when this module
  changes.
- **extra-disallow-paths**: Callers MAY pass `options.disallow` to `siteRobots` to keep
  auth-gated or API routes out of the production `allow` rule.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | `SiteId` | required | Registry key resolved via `getSite`; drives brand, `applicationName` and origin/`prodHost` for all four functions |
| `seo.title` | `string` | required | Verbatim `title`/`openGraph.title`/`twitter.title` |
| `seo.description` | `string` | required | Verbatim `description`/`openGraph.description`/`twitter.description` |
| `seo.path` | `string \| undefined` | `undefined` | Page-level-only canonical/`og:url` source path; a falsy value (including `''`) is treated as omitted |
| `seo.keywords` | `string[] \| undefined` | `undefined` | Included verbatim (even `[]`) whenever set to a truthy value |
| `seo.card` | `string \| undefined` | `/opengraph-image.png` | Social card path used for `openGraph.images`/`twitter.images`; only `null`/`undefined` triggers the default |
| `host` | `string` | required (`siteRobots` only) | Request hostname compared against `prodHost`/`www.<prodHost>` (port-stripped, lower-cased) to choose allow vs. disallow |
| `options.disallow` | `string[] \| undefined` | `undefined` (no extra disallow) | Extra paths appended to the production `allow` rule when non-empty |
| `routes[].path` | `string` | required | Site-relative path concatenated directly onto the resolved production origin |
| `routes[].changeFrequency` | `MetadataRoute.Sitemap[number]['changeFrequency'] \| undefined` | `monthly` | Sitemap `changeFrequency` |
| `routes[].priority` | `number \| undefined` | `1` for `/`, else `0.5` | Sitemap `priority`; an explicit `0` is honored |
| `routes[].lastModified` | `Date \| undefined` | one `Date` shared by every route in the same `siteSitemap` call that omits it | Sitemap `lastmod` |
| `NEXT_PUBLIC_DEPLOYMENT_ENV` | build-time-inlined env var | unset | Folded into `DEV_BUILD`/`NOINDEX_BUILD` once at module load; `'local'`/`'testing'`/`'staging'` produce a noindex build |

## Localization

This module hardcodes two user-facing strings rather than sourcing them from any
localization system:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no i18n key) | `en_US` | `openGraph.locale`, set unconditionally regardless of any per-site or per-caller locale |
| (none — no i18n key) | `Agentic Developer Hub` | `applicationName`/`openGraph.siteName` fallback used whenever `id` resolves to no `SiteDef` |

`seo.title` and `seo.description` themselves are not hardcoded — they are supplied by
the caller per call — but the module has no locale parameter and applies the same
`en_US` Open Graph locale no matter what language the caller's copy is written in.

