---
id: 21cbbc1c-38a0-4e7a-8ca0-06e2f29429f5
title: Site Wordmark
domain: agentictoolkit://cookbook/adh/sites/site-wordmark
type: ingredient
version: 1.3.0
status: review
language: en
created: '2026-06-26'
modified: '2026-09-27'
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

# Site Wordmark

## Overview

A compact brand wordmark for marketing sites in the site family. Given a site
identifier, it renders the site's full name (resolved from the shared site
registry) with its trailing accent word rendered in the gold accent color role
and italic — the same lead/accent split used by the marketing landing hero, via
the shared title-split logic (the single source of truth for the brand split) —
over an optional identity line (the site's registry description by default).

Reuse it to brand a marketing site's sub-pages — e.g. the public research author
index at `/<userSlug>` — so they read as part of the site rather than orphan
pages, instead of hand-rolling a bespoke header. It is a pure, static
presentational element with no client-only state, styled entirely with theme
tokens, so it renders correctly whether the surrounding page is server-rendered
or client-rendered.

It belongs with the site family's own vocabulary rather than a generic shared UI
library, because it resolves the site registry: site lookup plus the shared
title-split logic turn a site identifier into this family's brand string. The
placement rule is mechanism → the generic libraries, vocabulary → the site
family's own package. (Only the hub-mark glyph inside it is registry-free, so
that one piece comes from a separate header-vocabulary module.) It ships on its
own importable entry point, importing only the pure registry, so a consumer that
needs just the wordmark is not forced to pull in the marketing landing page's
content prose alongside it.

## Behavioral Requirements

- **render-registry-brand**: The wordmark MUST render the site's full
  brand name for the given site identifier, resolved from the shared site
  registry.
- **accent-trailing-word**: The wordmark MUST split the brand via the
  shared title-split logic and render the trailing accent segment in the gold
  accent color role and italic, with the lead segment in the primary text
  color role.
- **default-identity-to-description**: The wordmark MUST render the site's
  registry description as the identity line when no tagline is provided.
- **honor-explicit-tagline**: The wordmark MUST render a provided
  tagline as the identity line in place of the description.
- **omit-identity-when-null**: The wordmark MUST render no identity line
  when the tagline is null or an empty string, or when neither a tagline nor a
  description exists — the identity line is omitted whenever its resolved
  value is falsy, so null, absent, and empty string are all treated as "omit".
- **fall-back-on-unknown-site**: The wordmark MUST still render — accenting
  the site identifier value itself, since there is no registry entry to derive
  a label from — when the site identifier resolves to no registry entry, never
  throwing.

## Appearance

```
Agentic Developer Research        <- serif family; "Research" in the gold accent role, italic
STORE & REVIEW RESEARCH           <- monospace family, uppercase, letter-spaced, dimmed text role
```

- Root: a container carrying any additional styling the consumer supplies (the
  consumer owns outer spacing / dividers).
- Wordmark line: serif family, small-to-medium size, tight line height and
  tracking, medium weight, in the primary text color role, scaling up slightly
  on wider viewports, with the accent word set in the gold accent color role and
  italic.
- Identity line: set below the wordmark line, monospace family, very small
  size, uppercase, wide letter-spacing, in the dimmed text color role.
- Colors come from theme token roles only — no raw hex values, no style
  overrides that bypass the theme. The serif/mono families come from the shared
  theme's font roles, so the wordmark matches the marketing landing hero's
  typography.

## States

| State | Appearance change |
|---|---|
| Known site, default | Brand name (gold-italic accent) + description identity line |
| Known site, explicit tagline | Identity line shows the provided content |
| Identity omitted (tagline is null, tagline is empty, or no description) | Wordmark line only |
| Unknown site identifier | The site identifier value itself is rendered as the accent, with no lead segment |

## Accessibility

- Text-only and non-interactive; the brand and identity are read in document
  order by assistive tech.
- Color MUST come from theme token roles (the gold accent role, the primary
  text role, the dimmed text role), never a hardcoded value, so contrast tracks
  the active theme's semantic color roles rather than a value this component
  owns; the accent word carries meaning through text, not color alone (it is
  the site name).
- Carries no landmark role of its own — the consumer places it within its own
  heading structure (e.g. above the page's main heading).
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The wordmark and tagline text color resolves from the active theme's gold/text/dimmed-text roles against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this component alone; this would be settled by a theme-level contrast audit of those roles against the backgrounds they sit on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | render-registry-brand, accent-trailing-word | Site identifier `"research"` | Renders `Agentic Developer` + a gold-italic `Research`; full text reads "Agentic Developer Research" |
| T2 | default-identity-to-description | Site identifier `"research"` (no tagline) | Identity line reads "Store & review research" (the registry description) |
| T3 | honor-explicit-tagline | Site identifier `"research"`, tagline `"Published research"` | Identity line reads "Published research" |
| T4 | omit-identity-when-null | Site identifier `"research"`, tagline explicitly null | No identity line is rendered |
| T5 | fall-back-on-unknown-site | An unknown site identifier `"not-a-real-site"` | No lead segment; renders `not-a-real-site` as the accent; no identity line; does not throw |
| T6 | accent-trailing-word | Site identifier `"bitbag"` | Full label "Bitbag" does not start with "Agentic Developer "; no lead segment, whole label "Bitbag" is the accent; identity line reads "The Agentic Developer persona" |
| T7 | omit-identity-when-null | Site identifier `"research"`, tagline as empty string | No identity line is rendered (empty string is falsy, same as null) |

## Edge Cases

- A site whose full label does not start with the shared "Agentic Developer"
  prefix yields an empty lead and the whole label as the accent (via the
  shared title-split logic).
- An unknown site identifier (defensive, since the input is expected to be a
  valid site identifier) renders the identifier as the accent and omits the
  identity line.
- The tagline accepts arbitrary renderable content, so a consumer may pass a
  link or styled text; leaving it unset means "use the description," setting
  it explicitly to null means "omit."
- An empty-string tagline also omits the identity line, the same as null: the
  identity line is omitted whenever its resolved value is falsy, not only on a
  strict null comparison, so an empty string is treated as "omit" too.

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `siteId` | site identifier | — (required) | The marketing site whose brand to render |
| `tagline` | renderable content | site description | Identity line; set explicitly to null to omit it |
| `className` | string | — | Extra styling on the root element |

## Logging

Presentational and static; emits no log events.

## Platform Notes

- **SwiftUI**: Not applicable — web-only shared component.
- **Compose**: Not applicable — web-only shared component.
- **React / Web (TypeScript):** Component at
  `packages/web/packages/adh/src/marketing/SiteWordmark.tsx`, exported on its own
  subpath `@agentic-toolkit/adh/marketing/SiteWordmark` (with a dedicated `tsup`
  entry + `exports` key). Reuses `getSite` + `splitSiteTitle` from
  `@agentic-toolkit/adh-registry`. It lives in `@agentic-toolkit/adh` — the
  vocabulary package — rather than a generic package such as
  `@agenticdevelopertoolkit/ui` or `@agenticdevelopertoolkit/themes`, since it
  resolves the ADH site registry; the `HubMark` glyph inside it comes from
  `@agentic-toolkit/adh/header` because that one piece is registry-free. Root
  element is a `<div>` carrying any `className`; the wordmark line is
  `font-serif text-lg leading-tight font-medium tracking-tight text-apt-text
  sm:text-xl`, with the accent word wrapped in `<span
  className="text-apt-gold italic">`; the identity line is `mt-1 font-mono
  text-[0.65rem] uppercase tracking-[0.18em] text-apt-text-dim`. Uses `apt-*`
  tokens only — no raw hex, no `!important`. Pure presentational component (no
  hooks, no client state), so it renders correctly inside both server and
  client trees; is `'use client'`-safe to co-locate with client consumers since
  it imports only the pure registry, not `MarketingLanding`'s content prose.
  Props:
  ```ts
  interface SiteWordmarkProps {
    siteId: SiteId
    tagline?: React.ReactNode   // undefined → site description; null → omit
    className?: string
  }
  export function SiteWordmark(props: SiteWordmarkProps): React.ReactElement
  ```
  Demoed in `ui-showcase` (Chrome group); first consumer is the research site's
  `AuthorPapersIndex`.
- **AppKit / UIKit**: Not applicable — web-only shared component.
- **WinUI 3**: Not applicable — web-only shared component.

## Reference Implementations

| Platform | Path |
|----------|------|

## Design Decisions

**Decision**: Reuse the shared title-split logic for the lead/accent split rather than re-deriving it.
**Rationale**: dry — the brand split has one authoritative representation (shared with the
landing hero and the concept graph), so the wordmark can never drift from the rest of the
brand system. Applies to the web implementation, where the split logic is `splitSiteTitle`.
**Approved**: pending

**Decision**: Place the component in the site family's own vocabulary package rather than a
generic toolkit package.
**Rationale**: separation-of-concerns — it resolves the ADH site registry to produce the
brand string, and the boundary is mechanism → the generic packages, vocabulary →
the site family's own package; a registry-bound component in a generic UI or theme
package would make a generic package depend on one consumer's site list. On the web
this means `@agentic-toolkit/adh` rather than `@agenticdevelopertoolkit/ui` or
`@agenticdevelopertoolkit/themes`.
**Approved**: pending

*History*: two namespaces ago this component sat in `@adh-shared/adh` for a Tailwind
reason — marketing apps `@source`d the `adh` package but not `ui`, so a ui-package
wordmark rendered unstyled. That reason has since expired: those apps `@source`
`@agentic-toolkit/adh` too, and `@agenticdevelopertoolkit/ui` self-registers its own
sources. The vocabulary rule above is what governs now.

**Decision**: Ship on its own importable entry point, importing only the pure registry.
**Rationale**: separation-of-concerns — keeps the marketing landing page's heavy
concepts/content-prose graph out of a consumer's bundle when only the wordmark is
needed. On the web this is a dedicated subpath export.
**Approved**: pending

**Decision**: The tagline distinguishes "not provided" from "explicitly cleared".
**Rationale**: explicit-over-implicit — "use the default" and "omit entirely"
are different intents and get different values. On the web this is a `ReactNode`
prop with `undefined` vs. `null` distinguished.
**Approved**: pending

## Compliance

| Check | Status | Category |
|---|---|---|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

These statuses rest on `SiteWordmark.tsx`: the brand and identity lines are plain
`<p>`/`<span>` text nodes with no ARIA suppression, read in document order
(screen-reader-support); `text-apt-gold`/`text-apt-text`/`text-apt-text-dim` resolve to
runtime Material 3 theme roles (`@agenticdevelopertoolkit/themes`' `tailwind.css`:
`--color-apt-gold: var(--color-primary)`, …) whose actual rendered contrast is a
property of the active theme, not measured or asserted by this component (contrast-ratio).

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.3.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/sites/. |
| 1.2.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.2.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded the unknown-`siteId` fallback and the empty-tagline case for consistency across Requirements/States/Edge Cases/vectors; reworded the contrast claim in Accessibility to what the source controls (theme token roles) instead of an unverified contrast assertion; added concrete T5 input/output, an off-pattern-brand vector (T6), and an empty-`tagline` vector (T7); filled in all five Platform Notes bullets; reformatted Design Decisions to the three-line form with `Approved: pending` and moved the superseded Tailwind `@source` history into a note; named the `@agenticdevelopertoolkit/*` scope for `ui`/`themes`/`controls`; rebuilt the Compliance table onto real catalog checks (screen-reader-support, contrast-ratio); records the unverified theme-token contrast as an open question. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Renamed every requirement to subject-only kebab-case, dropping the old prefix everywhere it is cited. |
| 1.0.0 | 2026-06-26 | Mike Fullerton | Initial recipe — shared brand wordmark, first used on the research author index. |
