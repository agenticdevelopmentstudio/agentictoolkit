<!-- leaf: implement-site/wordmark--edge-cases · source: site-wordmark.md -->

# SiteWordmark

## Edge Cases

- A site whose `fullLabel` does not start with the shared `Agentic Developer`
  prefix yields an empty lead and the whole label as the accent (via
  `splitSiteTitle`).
- An unknown `siteId` (defensive; the prop is typed to `SiteId`) renders the id as
  the accent and omits the identity line.
- `tagline` accepts any `ReactNode`, so a consumer may pass a link or styled span;
  `undefined` means "use the description", `null` means "omit".
- `tagline=""` also omits the identity line, the same as `null`: the render
  check (`identity ? … : null`) is truthy-based, not a strict `!== null`
  comparison, so an empty string is treated as "omit" too.
