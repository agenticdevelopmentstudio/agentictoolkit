<!-- leaf: implement-site/registry-seo--edge-cases · source: site-registry-seo.md -->

# Site Registry SEO

**Rules** (cite as `implement-site/registry-seo--edge-cases#<slug>`):

- `null-and-empty-input` MUST — seo.path === '' MUST be treated identically to an omitted path (canonical and openGraph.url both absent), because the …
- `null-and-empty-input-2` MUST — seo.card === '' MUST be used verbatim as the card URL, producing an empty-string image URL, because the fallback (??) …
- `null-and-empty-input-3` MUST — seo.keywords === [] MUST still populate keywords: [] in the output rather than omitting the key, because that guard is …
- `null-and-empty-input-4` MUST — routes === [] MUST make siteSitemap return [] (MUST).
- `null-and-empty-input-5` MUST — options.disallow === [] MUST omit the disallow key from siteRobots's production rule; this guard checks .length, so it …
- `null-and-empty-input-6` MUST — host === '' MUST be treated as non-production unless the resolved prodHost is also empty, in which case the …
- `boundary-values` MUST — route.priority === 0 MUST be honored verbatim, not replaced by the 1/0.5 default, because the default uses ??, which …
- `boundary-values-2` MUST — route.path === '/' (exact string equality) MUST get the priority default 1; any other path string — including a …
- `boundary-values-3` MUST — the Open Graph/Twitter card is fixed at exactly 1200×630 (OG_IMAGE_SIZE); these four functions never emit any other …
- `concurrent-access` MUST — all four exported functions are synchronous and read no mutable state that changes during a call; …
- `error-states` MUST — not directly applicable in the classic sense: this module makes no network, file-system, or database call for a …

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
