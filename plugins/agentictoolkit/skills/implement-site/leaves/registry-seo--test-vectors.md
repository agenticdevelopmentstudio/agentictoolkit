<!-- leaf: implement-site/registry-seo--test-vectors · source: site-registry-seo.md -->

# Site Registry SEO

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
