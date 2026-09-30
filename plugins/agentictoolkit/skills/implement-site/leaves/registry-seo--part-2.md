<!-- leaf: implement-site/registry-seo--part-2 · source: site-registry-seo.md -->

# Site Registry SEO — continued (part 2)

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
