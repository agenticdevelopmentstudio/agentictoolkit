<!-- leaf: implement-site/wordmark · source: site-wordmark.md -->

**Rules** (cite as `implement-site/wordmark#<slug>`):

- `render-registry-brand` MUST
- `accent-trailing-word` MUST
- `default-identity-to-description` MUST
- `honor-explicit-tagline` MUST
- `omit-identity-when-null` MUST
- `fall-back-on-unknown-site` MUST
- `color-come-from-theme-token` MUST — Color MUST come from theme token roles (text-apt-gold, text-apt-text, text-apt-text-dim), never a hardcoded value, so …

# SiteWordmark

## Overview

A compact brand wordmark in `@agentic-toolkit/adh` for ADH marketing sites. Given a
`siteId`, it renders the site's full name (from the site registry) with its
trailing accent word in gold italic — the **same** lead/accent split that the
`MarketingLanding` hero uses, via `splitSiteTitle` (the single source of truth for
the brand split) — over an optional mono identity line (the site's `description`
by default).

Reuse it to brand a marketing site's sub-pages — e.g. the public research author
index at `/<userSlug>` — so they read as part of the site rather than orphan
pages, instead of hand-rolling a bespoke header. It is pure presentational (no
hooks, no client state) and styled entirely with `apt-*` tokens, so it renders
correctly inside both server and client trees.

It lives in `@agentic-toolkit/adh` — the **vocabulary** package — not in a generic
toolkit package, because it resolves the ADH site registry: `getSite` +
`splitSiteTitle` from `@agentic-toolkit/adh-registry` turn a `siteId` into this
family's brand string. The placement rule is mechanism → the generic packages
(`@agenticdevelopertoolkit/ui`, `@agenticdevelopertoolkit/themes`,
`@agenticdevelopertoolkit/controls`, …), vocabulary → `@agentic-toolkit/adh`. (Only the
`HubMark` glyph inside it is registry-free, so that one piece comes from
`@agentic-toolkit/adh/header`.) It ships on its OWN subpath
(`@agentic-toolkit/adh/marketing/SiteWordmark`), importing only the pure registry,
so a `'use client'` consumer can pull just the wordmark without co-bundling
`MarketingLanding`'s content prose.

## Behavioral Requirements

- **render-registry-brand**: The SiteWordmark MUST render the site's full
  brand name for the given `siteId`, resolved from the shared site registry.
- **accent-trailing-word**: The SiteWordmark MUST split the brand via
  `splitSiteTitle` and render the trailing accent segment in gold italic
  (`text-apt-gold italic`) and the lead segment in plain `apt-text`.
- **default-identity-to-description**: The SiteWordmark MUST render the site's
  registry `description` as the identity line when `tagline` is not provided.
- **honor-explicit-tagline**: The SiteWordmark MUST render a provided
  `tagline` node as the identity line in place of the description.
- **omit-identity-when-null**: The SiteWordmark MUST render no identity line
  when `tagline` is `null` or an empty string, or when neither a tagline nor a
  description exists — the render check (`identity ? … : null`) is truthy-based,
  so `null`, `undefined` and `''` are all treated as "omit".
- **fall-back-on-unknown-site**: The SiteWordmark MUST still render — accenting
  the `siteId` value itself, since there is no registry entry to derive a label
  from — when the `siteId` resolves to no registry entry, never throwing.

## Appearance

```
Agentic Developer Research        <- font-serif; "Research" in gold italic
STORE & REVIEW RESEARCH           <- font-mono, uppercase, tracked, apt-text-dim
```

- Root: a `<div>` carrying any `className` (the consumer owns outer spacing /
  dividers).
- Wordmark line: `font-serif text-lg leading-tight font-medium tracking-tight
  text-apt-text sm:text-xl`, with the accent word wrapped in
  `<span className="text-apt-gold italic">`.
- Identity line: `mt-1 font-mono text-[0.65rem] uppercase tracking-[0.18em]
  text-apt-text-dim`.
- `apt-*` tokens only — no raw hex, no `!important`. The serif/mono families come
  from the shared `--font-serif` / `--font-mono` theme utilities, so the wordmark
  matches the `MarketingLanding` hero's typography.

## Accessibility

- Text-only and non-interactive; the brand and identity are read in document
  order by assistive tech.
- Color MUST come from theme token roles (`text-apt-gold`, `text-apt-text`,
  `text-apt-text-dim`), never a hardcoded value, so contrast tracks the active
  theme's Material 3 roles (`--color-primary`, `--color-on-surface`, …) rather
  than a value this component owns; the accent word carries meaning through
  text, not color alone (it is the site name).
- Carries no landmark role of its own — the consumer places it within its own
  `<header>` / heading structure (e.g. above the page `<h1>`).
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The wordmark and tagline text color resolves from the active theme's apt-gold/apt-text/apt-text-dim role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file; this would be settled by a theme-level contrast audit of apt-gold/apt-text/apt-text-dim against the backgrounds it sits on.

## Configuration

`@agentic-toolkit/adh/marketing/SiteWordmark`

| Option | Type | Default | Description |
|---|---|---|---|
| `siteId` | `SiteId` | — (required) | The marketing site whose brand to render |
| `tagline` | `ReactNode` | site `description` | Identity line; `null` omits it |
| `className` | `string` | — | Extra classes on the root element |

```ts
interface SiteWordmarkProps {
  siteId: SiteId
  tagline?: React.ReactNode   // undefined → site description; null → omit
  className?: string
}
export function SiteWordmark(props: SiteWordmarkProps): React.ReactElement
```

## Platform Notes

- **SwiftUI**: Not applicable — web-only shared component.
- **Compose**: Not applicable — web-only shared component.
- **React / Web (TypeScript):** Component at
  `packages/web/packages/adh/src/marketing/SiteWordmark.tsx`, exported on its own subpath
  `@agentic-toolkit/adh/marketing/SiteWordmark` (with a dedicated `tsup` entry +
  `exports` key). Reuses `getSite` + `splitSiteTitle` from the registry. Demoed in
  `ui-showcase` (Chrome group); first consumer is the research site's
  `AuthorPapersIndex`.
- **AppKit / UIKit**: Not applicable — web-only shared component.
- **WinUI 3**: Not applicable — web-only shared component.

## Design Decisions

**Decision**: Reuse `splitSiteTitle` for the lead/accent split rather than re-deriving it.
**Rationale**: dry — the brand split has one authoritative representation (shared with the
landing hero and the concept graph), so the wordmark can never drift from the rest of the
brand system.
**Approved**: pending

**Decision**: Place the component in `@agentic-toolkit/adh` — the vocabulary package —
not in a generic toolkit package.
**Rationale**: separation-of-concerns — it resolves the ADH site registry to produce the
brand string, and the boundary is mechanism → the generic packages, vocabulary →
`@agentic-toolkit/adh`; a registry-bound component in `@agenticdevelopertoolkit/ui` or
`@agenticdevelopertoolkit/themes` would make a generic package depend on one consumer's
site list.
**Approved**: pending

*History*: two namespaces ago this component sat in `@adh-shared/adh` for a Tailwind
reason — marketing apps `@source`d the `adh` package but not `ui`, so a ui-package
wordmark rendered unstyled. That reason has since expired: those apps `@source`
`@agentic-toolkit/adh` too, and `@agenticdevelopertoolkit/ui` self-registers its own
sources. The vocabulary rule above is what governs now.

**Decision**: Ship on its own subpath, importing only the pure registry.
**Rationale**: separation-of-concerns — keeps `MarketingLanding`'s heavy
concepts/content-prose graph out of a `'use client'` consumer's bundle.
**Approved**: pending

**Decision**: `tagline` is a `ReactNode` with `undefined`/`null` distinguished.
**Rationale**: explicit-over-implicit — "use the default" and "omit entirely"
are different intents and get different values.
**Approved**: pending
