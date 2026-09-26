---
id: 0a627830-a764-4f44-8300-faf4279089a1
title: Site Registry SEO
domain: agentictoolkit://cookbook/adh-registry/seo/metadata
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Per-site canonical, Open Graph, Twitter card, robots and sitemap metadata
  derived from the ADH site registry, framework-free apart from Next's Metadata types.
platforms:
- typescript
- web
tags:
- seo
- metadata
- site-registry
- web
depends-on: []
related:
- site-wordmark
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a server-side SEO metadata generator, not a visual component.

## States

Not applicable — this is a server-side SEO metadata generator, not a visual component.

## Accessibility

Not applicable — this is a server-side SEO metadata generator, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| site-registry-seo-001 | site-metadata-title-description, site-metadata-brand, site-metadata-origin | `siteMetadata('hub', { title: 'T', description: 'D' })` | `title === 'T'`, `description === 'D'`, `openGraph` is truthy (per `registry-characterisation.test.ts`); `applicationName === 'Agentic Developer Hub'`, `metadataBase.origin === 'https://agenticdeveloperhub.com'` |
| site-registry-seo-002 | canonical-only-scope | `canonicalOnly('/')` | Deep-equals `{ alternates: { canonical: '/' } }` exactly, per `registry-characterisation.test.ts` |
| site-registry-seo-003 | og-image-size-export | `ogImageSize` | Deep-equals `{ width: 1200, height: 630 }`, per `registry-characterisation.test.ts` |
| site-registry-seo-004 | site-metadata-canonical, site-metadata-og-url | `siteMetadata('cookbook', { title: 'T', description: 'D', path: '/pricing' })` | `alternates.canonical === '/pricing'`; `openGraph.url === '/pricing'`; `metadataBase.origin === 'https://agenticdevelopercookbook.com'` |
| site-registry-seo-005 | site-metadata-canonical, site-metadata-og-url, seo-path-is-a-path | `siteMetadata('hub', { title: 'T', description: 'D', path: '' })` | `alternates` key is absent from the result; `openGraph.url` is absent — an empty string is treated the same as an omitted `path` |
| site-registry-seo-006 | site-metadata-keywords | `siteMetadata('hub', { title: 'T', description: 'D', keywords: [] })` | Result's `keywords` deep-equals `[]` — present, not omitted |
| site-registry-seo-007 | site-metadata-card, site-metadata-og-block, site-metadata-twitter | `siteMetadata('hub', { title: 'T', description: 'D' })` (no `card`) | `openGraph.images[0]` deep-equals `{ url: '/opengraph-image.png', width: 1200, height: 630 }`; `twitter.images[0] === '/opengraph-image.png'` |
| site-registry-seo-008 | site-metadata-card | `siteMetadata('devteam', { title: 'T', description: 'D', card: '/devteam/og.png' })` | `openGraph.images[0].url === '/devteam/og.png'`; `twitter.images[0] === '/devteam/og.png'` |
| site-registry-seo-009 | site-metadata-brand, site-metadata-origin | `siteMetadata('nope' as SiteId, { title: 'T', description: 'D' })` | `applicationName === 'Agentic Developer Hub'`; `metadataBase.origin === 'https://agenticdeveloperhub.com'` |
| site-registry-seo-010 | site-metadata-robots-gate | `siteMetadata('hub', { title: 'T', description: 'D' })` built with `NEXT_PUBLIC_DEPLOYMENT_ENV=testing` | `robots.index === false`, `robots.follow === false`, `robots.googleBot.index === false`, `robots.googleBot.follow === false`, `robots.googleBot['max-image-preview'] === 'large'` |
| site-registry-seo-011 | site-metadata-robots-gate | Same call built with `NEXT_PUBLIC_DEPLOYMENT_ENV` unset | `robots.index === true`, `robots.follow === true`, `robots.googleBot.index === true`, `robots.googleBot.follow === true`, `robots.googleBot['max-image-preview'] === 'large'` |
| site-registry-seo-012 | site-robots-production | `siteRobots('hub', 'agenticdeveloperhub.com')` | Deep-equals `{ rules: [{ userAgent: '*', allow: '/' }], sitemap: 'https://agenticdeveloperhub.com/sitemap.xml', host: 'https://agenticdeveloperhub.com' }` |
| site-registry-seo-013 | site-robots-production | `siteRobots('hub', 'www.agenticdeveloperhub.com')` and `siteRobots('hub', 'agenticdeveloperhub.com:3000')` | Both equal the site-registry-seo-012 result — the `www.` form and a stripped `:<port>` suffix both count as the production host |
| site-registry-seo-014 | site-robots-non-production | `siteRobots('hub', 'staging.agenticdeveloperhub.com')` | Deep-equals `{ rules: [{ userAgent: '*', disallow: '/' }] }` — no `sitemap`/`host` key |
| site-registry-seo-015 | site-robots-non-production | `siteRobots('nope' as SiteId, 'agenticdeveloperhub.com')` | Deep-equals `{ rules: [{ userAgent: '*', disallow: '/' }] }` regardless of `host`, because the resolved `prodHost` is empty |
| site-registry-seo-016 | site-robots-disallow-option | `siteRobots('hub', 'agenticdeveloperhub.com', { disallow: ['/admin'] })` then with `{ disallow: [] }` | First call's rule deep-equals `{ userAgent: '*', allow: '/', disallow: ['/admin'] }`; second call's rule has no `disallow` key at all |
| site-registry-seo-017 | site-sitemap-mapping, site-sitemap-change-frequency, site-sitemap-priority | `siteSitemap('cookbook', [{ path: '/' }, { path: '/pricing', priority: 0.9, changeFrequency: 'weekly' }])` | Entry 0: `{ url: 'https://agenticdevelopercookbook.com/', changeFrequency: 'monthly', priority: 1 }` plus a `lastModified`; entry 1: `{ url: '.../pricing', changeFrequency: 'weekly', priority: 0.9 }` sharing the same `lastModified` value as entry 0 |
| site-registry-seo-018 | site-sitemap-mapping | `siteSitemap('hub', [])` | Returns `[]` |
| site-registry-seo-019 | site-sitemap-priority | `siteSitemap('hub', [{ path: '/x', priority: 0 }])` | Entry's `priority === 0`, not replaced by the `0.5` default |

## Edge Cases

- **Null and empty input** — `seo.path === ''` MUST be treated identically to an
  omitted `path` (canonical and `openGraph.url` both absent), because the guard is a
  truthiness check, not a null check (MUST).
- **Null and empty input** — `seo.card === ''` MUST be used verbatim as the card URL,
  producing an empty-string image URL, because the fallback (`??`) replaces only
  `null`/`undefined`, not an empty string (MUST).
- **Null and empty input** — `seo.keywords === []` MUST still populate `keywords: []`
  in the output rather than omitting the key, because that guard is a truthiness check
  on the whole array, not a length check (MUST).
- **Null and empty input** — `routes === []` MUST make `siteSitemap` return `[]` (MUST).
- **Null and empty input** — `options.disallow === []` MUST omit the `disallow` key
  from `siteRobots`'s production rule; this guard checks `.length`, so it behaves
  differently from the `seo.keywords` truthiness guard above (MUST).
- **Null and empty input** — `host === ''` MUST be treated as non-production unless the
  resolved `prodHost` is also empty, in which case the non-production branch is already
  forced before the host comparison runs (MUST).
- **Boundary values** — `route.priority === 0` MUST be honored verbatim, not replaced
  by the `1`/`0.5` default, because the default uses `??`, which tests only
  `null`/`undefined` (MUST).
- **Boundary values** — `route.path === '/'` (exact string equality) MUST get the
  priority default `1`; any other path string — including a trailing-slash variant such
  as `'/home/'` — MUST get `0.5`; there is no path normalization (MUST).
- **Boundary values** — the Open Graph/Twitter card is fixed at exactly 1200×630
  (`OG_IMAGE_SIZE`); these four functions never emit any other image dimension for the
  card they construct (MUST).
- **Concurrent access** — all four exported functions are synchronous and read no
  mutable state that changes during a call; `NOINDEX_BUILD`/`DEV_BUILD` are assigned
  once at module load in single-threaded JavaScript and never reassigned afterward, so
  concurrent calls from different requests cannot interleave or race on them. This is a
  fact of the execution model, not an unordered race (MUST).
- **Error states** — not directly applicable in the classic sense: this module makes no
  network, file-system, or database call for a dependency to fail on. The only
  "unresolved input" path — an `id` for which `getSite` finds no `SiteDef` — degrades to
  the generic Agentic Developer Hub brand/origin (see `site-metadata-brand`,
  `site-metadata-origin`, `site-sitemap-origin`, `site-robots-non-production`) with no
  thrown error and no log line (MUST, as implemented).
- **Offline/disconnected** — not applicable. Per the module's own top-of-file comment,
  "anything needing the live request… is passed IN by the caller rather than read here";
  this module performs no network I/O of its own, so connectivity loss is entirely the
  caller's or Next's routing layer's concern.

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

## Deep Linking

Not applicable: `metadata.ts` emits canonical, Open Graph and sitemap URLs but performs
no incoming route parsing, path matching, or deep-link dispatch.

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

## Accessibility Options

Not applicable — this is a server-side metadata generator with no rendered UI surface
for Reduce Motion, Increase Contrast, or Differentiate Without Color to apply to.

## Feature Flags

Not applicable — the module has no flag-gated behavior; its only environment-
conditional switch is `NOINDEX_BUILD` (derived from the build's
`NEXT_PUBLIC_DEPLOYMENT_ENV`), which is a deployment-tier classification, not a feature
flag.

## Analytics

Not applicable — `metadata.ts` contains no event-tracking or analytics calls; it only
computes and returns metadata objects.

## Privacy

Not applicable — the only inputs are the compile-time site registry (`SiteId`/
`SiteDef`) and caller-supplied marketing copy (`SiteSeo`); no user data, token, or
credential is read, stored, or transmitted.

## Logging

Not applicable — `metadata.ts` contains no logging calls of any kind; every code path
returns a value instead of writing to a log.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/adh-registry/src/seo/metadata.ts`,
  alongside `src/sites/registry.ts` (`getSite`, `SiteId`, `SiteDef`) and
  `src/deployment-env.ts` (`DEV_BUILD`). The module is framework-free apart from
  `import type { Metadata, MetadataRoute } from 'next'` — the four exports are plain
  functions returning plain objects; a Next.js App Router `page.tsx`'s exported
  `metadata`, an `app/robots.ts`, and an `app/sitemap.ts` are what actually read those
  shapes. `NEXT_PUBLIC_DEPLOYMENT_ENV` is inlined by webpack at build time.
- **SwiftUI**: there is no Next.js metadata contract on Apple platforms, so a port's
  job is to build the equivalent `<head>` tags directly — a small type constructing an
  HTML-metadata document (title, canonical `<link>`, `og:*`/`twitter:*` `<meta>` tags,
  the `robots` meta content) mirrors `Metadata`; `robots.txt`/`sitemap.xml` become
  plain-text/XML string builders rather than framework route files, called from whatever
  server route serves those two paths.
- **Compose**: no native-app equivalent exists (a device app has no `<head>` or
  `robots.txt`), so a Kotlin port matters only for a Ktor- or Spring-based server
  rendering these pages; use `kotlinx.serialization` data classes for `SiteSeo`/
  `SiteRobotsOptions`/`SiteRoute` and plain functions returning a small `Metadata`-
  shaped data class, with the two text formats built by string templates or an XML
  serializer.
- **AppKit/UIKit**: same non-fit as SwiftUI — this is server/build-time HTML metadata,
  not view code. An AppKit/UIKit app that embeds one of these sites in a `WKWebView`
  consumes the already-emitted HTML/robots/sitemap and has no separate contract to
  implement.
- **WinUI 3**: same non-fit for the UI framework itself, but the concrete .NET port — an
  ASP.NET Core Minimal API host serving the same site — starts from: `System.Text.Json`
  for the `SiteSeo`/`SiteRobotsOptions`/`SiteRoute` records and the plain metadata
  object; `HttpContext.Request.Host` in place of the Next `headers()`-derived `host`
  parameter; a `Task`/`async` Minimal API endpoint returning `text/plain` for
  `robots.txt` and `application/xml` for `sitemap.xml` instead of Next's file-convention
  routes; `DateTimeOffset.UtcNow` in place of `new Date()` for the shared build-time
  `lastModified`; and `IConfiguration`/environment-variable binding (a custom
  `DEPLOYMENT_ENV` config key) in place of the build-inlined `NEXT_PUBLIC_DEPLOYMENT_ENV`
  — .NET has no bundler-level dead-code fold, so the environment check is an ordinary
  runtime `if`, not a compile-time constant.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-registry/src/seo/metadata.ts` |

## Design Decisions

**Decision**: `canonicalOnly` sets only `alternates.canonical` and never
`openGraph.url`, even for a caller that already knows the path.
**Rationale**: a page-level `openGraph` block replaces the layout's rather than merging
into it, so setting `url` here would silently drop the inherited `siteName`, `locale`
and `images`; a caller that wants a complete Open Graph block calls
`siteMetadata(id, { …, path })` instead.
**Approved**: pending

**Decision**: `seo.path`/`route.path` are documented as paths, never absolute URLs,
and neither `siteMetadata` nor `siteSitemap` validates a leading slash or otherwise
normalizes the value.
**Rationale**: every current call site passes a literal path constant; runtime
validation was judged unnecessary until a caller actually violates the documented
contract.
**Approved**: pending

**Decision**: `NOINDEX_BUILD`'s allowlist names the three non-production environments
explicitly (`local`/`testing`/`staging`) instead of testing `=== 'production'`.
**Rationale**: an unset or misspelled `NEXT_PUBLIC_DEPLOYMENT_ENV` then fails toward
indexable — the recoverable direction — rather than silently shipping `noindex` to
production; `siteRobots`'s host check is a second, independent layer that still blocks
non-production hosts even when this env var is wrong.
**Approved**: pending

**Decision**: `siteRobots` decides allow-vs-disallow from the request's hostname rather
than from `NEXT_PUBLIC_DEPLOYMENT_ENV`/`NOINDEX_BUILD`.
**Rationale**: host-based detection needs no per-project env configuration and cannot be
defeated by a missing or misconfigured variable; an unrecognized host fails closed
(disallow), the opposite failure direction from `NOINDEX_BUILD`, so the two layers cover
each other's blind spot.
**Approved**: pending

**Decision**: `siteSitemap`'s default `lastModified` is the moment the function runs
(`new Date()`), not a hand-maintained literal date, and that one `Date` is shared by
every route in the call that omits its own.
**Rationale**: a static marketing page is compiled from source, so a fresh deploy IS
the modification event; a hardcoded date rots the first time someone edits the copy
without remembering this file exists.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | partial | Internationalization |

`separation-of-concerns` passes: `metadata.ts` contains zero DOM, fetch, or rendering
code — only `import type` reaches into `next`, and the one value that needs the live
request (the serving hostname) is passed IN by the caller rather than read here, per the
module's own top-of-file comment. `unit-test-coverage` is `partial`:
`registry-characterisation.test.ts` — whose own `describe` block is titled "seo helpers
(251 consumers, no other test)" — exercises `canonicalOnly`, `ogImageSize`, and only the
title/description/`openGraph`-truthy slice of `siteMetadata`; `siteRobots`,
`siteSitemap`, and the `NOINDEX_BUILD` robots-gate branch of `siteMetadata` have no test
at all. `explicit-error-handling` passes: the module has no `try`/`catch` and no thrown
or caught exception; its only optional-unwrapping (`site?.prodHost ?? …`) is a
deliberate, documented default for an unresolved `SiteId`, not a swallowed error.
`no-hardcoded-strings` is `partial`: `seo.title`/`seo.description` are caller-supplied,
not hardcoded, but `openGraph.locale` (`'en_US'`) and the `'Agentic Developer Hub'`
fallback brand are hardcoded English strings with no localization path, as detailed
under Localization above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
