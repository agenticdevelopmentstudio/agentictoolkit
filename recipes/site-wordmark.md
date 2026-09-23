---
id: 21cbbc1c-38a0-4e7a-8ca0-06e2f29429f5
title: SiteWordmark
domain: agentictoolkit://recipes/site-wordmark
type: ingredient
version: 1.0.0
status: draft
language: en
created: '2026-06-26'
modified: '2026-06-26'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The compact ADH marketing-site brand wordmark: the site's full name with its trailing accent word in gold italic over an optional mono identity line."
platforms:
- typescript
- web
tags:
- branding
- wordmark
- chrome
- marketing
depends-on: []
related: []
references: []
---

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
(`ui`, `themes`, `controls`, …), vocabulary → `@agentic-toolkit/adh`. (Only the
`HubMark` glyph inside it is registry-free, so that one piece comes from
`@agentic-toolkit/adh/header`.) It ships on its OWN subpath
(`@agentic-toolkit/adh/marketing/SiteWordmark`), importing only the pure registry,
so a `'use client'` consumer can pull just the wordmark without co-bundling
`MarketingLanding`'s content prose.

## Behavioral Requirements

- **must-render-registry-brand**: The SiteWordmark MUST render the site's full
  brand name for the given `siteId`, resolved from the shared site registry.
- **must-accent-trailing-word**: The SiteWordmark MUST split the brand via
  `splitSiteTitle` and render the trailing accent segment in gold italic
  (`text-apt-gold italic`) and the lead segment in plain `apt-text`.
- **must-default-identity-to-description**: The SiteWordmark MUST render the site's
  registry `description` as the identity line when `tagline` is not provided.
- **must-honor-explicit-tagline**: The SiteWordmark MUST render a provided
  `tagline` node as the identity line in place of the description.
- **must-omit-identity-when-null**: The SiteWordmark MUST render no identity line
  when `tagline` is `null` (or when neither a tagline nor a description exists).
- **must-fall-back-on-unknown-site**: The SiteWordmark MUST still render
  (accenting the whole label) when the `siteId` resolves to no registry entry,
  never throwing.

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

## States

| State | Appearance change |
|---|---|
| Known site, default | Brand name (gold-italic accent) + description identity line |
| Known site, explicit `tagline` | Identity line shows the provided node |
| Identity omitted (`tagline={null}` or no description) | Wordmark line only |
| Unknown `siteId` | Whole label rendered as the accent; no identity line if no description |

## Accessibility

- Text-only and non-interactive; the brand and identity are read in document
  order by assistive tech.
- Color is conveyed by token classes that meet the theme's contrast; the accent
  word carries meaning through text, not color alone (it is the site name).
- Carries no landmark role of its own — the consumer places it within its own
  `<header>` / heading structure (e.g. above the page `<h1>`).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | must-render-registry-brand, must-accent-trailing-word | `siteId="research"` | Renders `Agentic Developer` + a gold-italic `Research`; full text reads "Agentic Developer Research" |
| T2 | must-default-identity-to-description | `siteId="research"` (no `tagline`) | Identity line reads "Store & review research" (the registry description) |
| T3 | must-honor-explicit-tagline | `siteId="research" tagline="Published research"` | Identity line reads "Published research" |
| T4 | must-omit-identity-when-null | `siteId="research" tagline={null}` | No identity line is rendered |
| T5 | must-fall-back-on-unknown-site | `siteId` not in the registry | Component renders the label as the accent without throwing |

## Edge Cases

- A site whose `fullLabel` does not start with the shared `Agentic Developer`
  prefix yields an empty lead and the whole label as the accent (via
  `splitSiteTitle`).
- An unknown `siteId` (defensive; the prop is typed to `SiteId`) renders the id as
  the accent and omits the identity line.
- `tagline` accepts any `ReactNode`, so a consumer may pass a link or styled span;
  `undefined` means "use the description", `null` means "omit".

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

## Logging

Presentational and static; emits no log events.

## Platform Notes

- **React / Web (TypeScript):** Component at
  `packages/web/packages/adh/src/marketing/SiteWordmark.tsx`, exported on its own subpath
  `@agentic-toolkit/adh/marketing/SiteWordmark` (with a dedicated `tsup` entry +
  `exports` key). Reuses `getSite` + `splitSiteTitle` from the registry. Demoed in
  `ui-showcase` (Chrome group); first consumer is the research site's
  `AuthorPapersIndex`.
- **SwiftUI / Compose:** Not applicable — web-only shared component.

## Design Decisions

- **Decision**: Reuse `splitSiteTitle` for the lead/accent split rather than
  re-deriving it. **Rationale**: dry — the brand split has one authoritative
  representation (shared with the landing hero and the concept graph), so the
  wordmark can never drift from the rest of the brand system.
- **Decision**: Place the component in `@agentic-toolkit/adh` — the vocabulary
  package — not in a generic toolkit package. **Rationale**: separation-of-concerns —
  it resolves the ADH site registry to produce the brand string, and the boundary is
  mechanism → the generic packages, vocabulary → `@agentic-toolkit/adh`; a
  registry-bound component in `ui` or `themes` would make a generic package depend on
  one consumer's site list. (Two namespaces ago it sat in `@adh-shared/adh` for a
  Tailwind reason — marketing apps `@source`d the `adh` package but not `ui`, so a
  ui-package wordmark rendered unstyled. That reason has since expired: those apps
  `@source` `@agentic-toolkit/adh` too, and `@agenticdevelopertoolkit/ui` self-registers its
  own sources. The vocabulary rule is what governs now.)
- **Decision**: Ship on its own subpath, importing only the pure registry.
  **Rationale**: separation-of-concerns — keeps `MarketingLanding`'s heavy
  concepts/content-prose graph out of a `'use client'` consumer's bundle.
- **Decision**: `tagline` is a `ReactNode` with `undefined`/`null` distinguished.
  **Rationale**: explicit-over-implicit — "use the default" and "omit entirely"
  are different intents and get different values.

## Compliance

| Check | Status | Category |
|---|---|---|
| Artifact formatting (ingredient) | passed | artifact-formatting |
| UI guidelines — apt-* tokens only, no raw hex, no `!important` | passed | adh-ui-guidelines |
| Accessibility — text-only, meaning not color-only | passed | a11y |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-06-26 | Mike Fullerton | Initial recipe — shared brand wordmark, first used on the research author index. |
