<!-- leaf: implement-site/wordmark--states · source: site-wordmark.md -->

# SiteWordmark

## States

| State | Appearance change |
|---|---|
| Known site, default | Brand name (gold-italic accent) + description identity line |
| Known site, explicit `tagline` | Identity line shows the provided node |
| Identity omitted (`tagline={null}`, `tagline=""`, or no description) | Wordmark line only |
| Unknown `siteId` | The `siteId` value itself is rendered as the accent, with no lead segment |
