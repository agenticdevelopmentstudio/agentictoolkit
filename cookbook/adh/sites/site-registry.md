---
id: 9069ccf9-0357-4311-9671-91ee2793adae
title: Site Registry
domain: agentictoolkit://cookbook/adh/sites/site-registry
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Single source of truth for the ADH site family: every site's identity, hosts,\
  \ environments, workspace/hub routing, build-side data, reserved slugs, generated\
  \ route map, and brand-story graph."
platforms:
- web
tags:
- site-registry
- adh-registry
- multi-site
- routing
- sso
- brand-story
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Site Registry

## Overview

The site registry is the single source of truth for the Agentic Developer Hub (ADH)
site family: roughly seventy independently deployed sites (`hub`, `cookbook`,
`projects`, `billing`, …) that share a header, a cross-site switcher, and a central
OAuth client. It comprises:

- **The site roster** — a closed set of every site identifier the family currently
  knows about, and one definition per site (display names, production host, which
  deploy environments exist, whether the site exposes the shared landing route,
  whether it mounts an authenticated workspace route); environment/host resolution
  for cross-site navigation; the hub's in-workspace feature-segment map; the
  workspace-slug round trip (plus the two disjoint landing-segment sets that tell a
  slug apart from a static page); a per-site build-configuration side table kept
  deliberately outside the mechanically generated part of the roster; and the
  cross-site single-sign-on (SSO) OAuth redirect allowlist.
- **The reserved-slug table** — which top-level path segments a registrant cannot
  claim as a public handle, per site.
- **The generated route map** — per-region generated route shares merged into one
  route table, feeding a "Routes" review surface and, downstream, a sitemap's
  static-segment exclusion list.
- **The brand story and guided tour** — a hand-authored brand-story map (brand tier,
  message-house pillar, funnel stage, and a brand-judgment "next step" per site)
  plus a separately generated, three-ring guided-tour graph merged into one
  next-step map.

All of it is pure, synchronous data and functions with no I/O beyond in-memory
lookups, read by the header, the site switcher, the footer, the hub's workspace
router, and a downstream OAuth-return-origin sync process.

## Behavioral Requirements

### Site identity and roster

- **site-id-closed-union**: The site identifier type MUST be closed, naming every
  site the family currently knows about; a value obtained from outside that closed
  set (a directory name, a command-line argument, a database column) MUST be
  validated by identifier validation or by directory-based identification before it
  can index the site roster or any table keyed by site identifier.
- **unique-site-ids**: Every entry in the site roster MUST have a unique identifier,
  and the roster MUST NOT contain an entry for the backend service itself.
- **site-def-minimum-fields**: Every site definition MUST declare `id`, `label`, and
  `prodHost`, and MUST declare `hasStaging`, `hasTesting`, and `hasHome` as explicit
  booleans (never omitted, since environment host resolution, the OAuth
  return-origin allowlist, and cross-site link construction's home-carry all branch
  on their literal `true`/`false` value).
- **workspace-route-not-derived-from-has-home**: A site definition's workspace-route
  field MUST NOT be inferred from `hasHome`; the two are independent facts about a
  site's route tree (`bitbag`, `status`, and `admin` have `hasHome: false` and no
  workspace route, while `hub-help` and `personaregistry` have `hasHome` true or
  false independently of having no workspace route at all), and a caller deriving
  one from the other risks sending a workspace switch to a route that 404s.
- **external-site-excluded-from-sso**: A site definition marked `external` MUST be
  excluded from the OAuth return-origin allowlist in every environment, because such
  a site (FishLamp Design) has no auth-callback route and never begins an ADH login.
- **admin-only-derives-admin-ids-and-drops-footer**: The admin-only id set MUST be
  exactly the identifiers of every site definition marked `adminOnly`, and every such
  entry MUST be excluded from the footer site list.
- **listed-sites-filter**: The listed-sites set MUST be exactly the roster entries
  whose `listed` field is not literally `false`; a `listed: false` entry MUST remain
  resolvable by site lookup and identifier validation and MUST only be excluded from
  the roster display, never from the registry itself.
- **footer-sites-filter**: The footer site list MUST be exactly the listed-sites
  entries whose `crawlable` is not `false` and whose `adminOnly` is not `true`, in
  the same order as the listed-sites set.

### Lookup and identification

- **get-site-lookup**: Site lookup by identifier MUST return the roster entry whose
  identifier equals the argument, or nothing when no such entry exists.
- **is-site-id-derived-from-sites**: Identifier validation MUST return true if and
  only if some roster entry has that identifier; it MUST be derived from the roster
  directly rather than from a second, separately maintained list, so it can never
  diverge from the identifiers the registry actually declares.
- **dir-name-strips-tld**: The directory-name derivation (used internally by
  directory-based identification) MUST derive a site's build-tree directory name by
  stripping the trailing `.<tld>` from `prodHost` (e.g. `help.agenticdeveloperhub.com`
  → `help.agenticdeveloperhub`).
- **site-id-for-dir-bare-id-first**: Directory-based identification MUST return the
  given name unchanged (as a valid site identifier) when that name is already a
  valid site identifier, before falling back to a `prodHost`-derived directory-name
  match; it MUST return nothing when the name matches neither a site identifier nor
  any site's derived directory name.

### Family groupings

- **main-marketing-ids-are-disjoint-curated-lists**: The main-family roster and the
  marketing-family roster MUST each be a hand-curated, non-overlapping list of site
  identifiers; an identifier present in one MUST NOT appear in the other, and `mcp`
  and `builds` (which have no build-tree directory anywhere) MUST appear in neither.
- **site-categories-exactly-one-membership**: Every identifier appearing in any
  category grouping's member list MUST appear in exactly one grouping's member list,
  never zero and never more than one.
- **group-by-category-preserves-order-and-collects-leftovers**: Category grouping
  MUST emit groups in the categories' declared order, with members in each group's
  declared order, MUST omit any group with no matching member among the sites being
  grouped, and MUST collect every site that matches no category into a single
  trailing group labelled "More", so that a newly scaffolded site can never be
  silently dropped from a menu built on this grouping.

### Display title

- **header-title-explicit-fulllabel-wins**: Header-title derivation MUST return a
  site's `fullLabel` when it is set, taking priority over any derivation from
  `prodHost`.
- **header-title-derives-from-apex-pattern**: When `fullLabel` is absent and
  `prodHost` matches `agenticdeveloper<x>.com`, header-title derivation MUST return
  `"Agentic Developer <X>"` with `<x>` capitalized, and MUST fall back to the site's
  `label` when `prodHost` matches neither an explicit `fullLabel` nor that pattern.
- **split-title-prefix-detection**: Header-title splitting MUST split the derived
  header title into a lead of `"Agentic Developer"` and an accent of the rest when
  the header title begins with `"Agentic Developer "`, and MUST return an empty lead
  with the whole title as accent for an off-pattern brand name (for example the
  Persona Registry).

### Environment and cross-site navigation

- **detect-env-classification**: Environment detection MUST lower-case and strip any
  trailing `:<port>` before classifying a hostname, MUST classify a hostname as
  `'local'` when it is exactly `localhost`, starts with `127.`, is `::1`, or ends in
  `.local`, `.test`, or `.localhost`; MUST classify a hostname starting with
  `testing.` as `'testing'` and one starting with `staging.` as `'staging'`; and MUST
  classify every other hostname as `'production'`.
- **host-for-env-fallback**: Environment host resolution MUST resolve
  `testing.<prodHost>` when the target environment is `'testing'` and the site has a
  testing deploy; otherwise for `'testing'` it MUST fall back to `staging.<prodHost>`
  when the site has a staging deploy, and otherwise to the bare `prodHost`. For
  `'staging'` it MUST resolve `staging.<prodHost>` when the site has a staging
  deploy and otherwise the bare `prodHost`. For `'production'` it MUST always
  resolve the bare `prodHost`.
- **local-origin-suite-domain-priority**: Local-origin resolution MUST first check
  whether the lower-cased, port-stripped current host ends in one of the recognized
  local suite domains (`sites.localhost`, `dev.test`, `dev.local`, checked in that
  order for readability only); when it does, the target's local origin MUST be
  `https://<sub>.<suite>.<domain>` (no subdomain for `hub`) reusing the current
  host's own `<suite>` label. When the current host matches none of the recognized
  suite domains, local-origin resolution MUST fall back to
  `http://<sub>localhost<:port>`, carrying the current port when one is present.
- **carry-path-home-only**: Path carry-over MUST return the target's landing path
  (`/`) for any path other than `/home` or a path starting with `/home/`; for the
  path `/home` it MUST return `/home` when the target exposes a home route and `/`
  otherwise; for a deeper `/home/*` path it MUST return the same path with a
  `#site-switch` marker appended (so the target's not-found page knows to walk the
  path up), or `/` when the target has no home route at all.
- **build-site-href-env-aware**: Cross-site link construction MUST classify the
  current environment via environment detection; for `'local'` it MUST return the
  local origin concatenated with the carried path; for every other environment it
  MUST return `https://<resolved environment host>` concatenated with the carried
  path.

### Cross-Site SSO Origin Allowlist (security-relevant)

- **sso-return-origins-partitioned-by-env**: The OAuth return-origin allowlist MUST
  return, for `env === 'production'`, the bare `https://<prodHost>` origin of every
  roster entry that is not marked external; for `env === 'staging'`, only the
  `https://staging.<prodHost>` origin of every non-external entry with a staging
  deploy; for `env === 'testing'`, only the `https://testing.<prodHost>` origin of
  every non-external entry with a testing deploy.
- **sso-flag-flip-is-a-one-way-door**: The staging-deploy and testing-deploy flags
  are the OAuth redirect surface the allowlist names, and flipping either from
  `false` to `true` MUST be treated as permanently widening that environment's
  allowlist: the deploy-time sync process that reads the allowlist's output into the
  enforcing database column is additive-only and never prunes a row that a later
  flag flip back to `false` would otherwise remove. A caller changing an existing
  entry's flag back to `false` MUST NOT assume the corresponding origin stops being
  a valid OAuth `return` target without a separate, deliberate, hand-run pruning
  pass against that environment.
- **sso-external-exclusion-fail-closed**: An origin belonging to a site marked
  external MUST NOT appear in the OAuth return-origin allowlist's result for any
  environment, on a fail-closed basis: an origin that cannot complete an ADH login
  has no legitimate reason to be a legal `return` target, so the absence is
  deliberate rather than an oversight to fill in.

### Hub in-workspace feature routing

- **hub-feature-segment-default-is-site-id**: The hub feature-segment map MUST map a
  routed site's identifier to the hub's own feature segment for that site's
  implementation; the default mapping is a site's own identifier, and every entry
  that maps to a different segment MUST do so because the hub already routed that
  feature under a different name before the site existed.
- **hub-feature-segment-many-to-one-allowed**: Two or more site identifiers MAY map
  to the same feature-segment value (for example `ecosystems` and `products` both
  mapping to `'products'`) when the hub renders one pane for both; segment lookup by
  site identifier MUST return that shared segment for either identifier.
- **site-for-hub-segment-tiebreak**: The reverse feature-segment lookup MUST resolve
  a segment shared by more than one site to the site whose own identifier equals
  that segment when one exists (for example `'products'` resolves to the `products`
  site, not `ecosystems`); when no site's identifier equals the segment, it MUST
  resolve to whichever site's mapping was declared first in the feature-segment map.
- **hub-workspace-segments-is-the-full-union**: The full workspace-segment set MUST
  be exactly the union of every value in the feature-segment map and every entry in
  the hub-only extra segments, so a caller answering "is this second path segment a
  hub workspace feature?" never has to consult the two source lists separately.
- **hub-extra-segments-have-no-registry-site**: An entry in the hub-only extra
  segments MUST name a hub workspace feature with no corresponding registry site (a
  hub-only knob, such as an ecosystem's member list, or the persona-data management
  surface); a feature that is some site's own implementation MUST be keyed in the
  feature-segment map by that site's identifier instead.

### Workspace routing

- **workspace-href-single-shape**: Workspace-link construction MUST return nothing
  when the slug is falsy (including the empty string) or when the target has no
  workspace route; otherwise it MUST return exactly `/<slug>`, the one route shape
  every site with a workspace route mounts today.
- **workspace-slug-root-sites-only**: Workspace-slug parsing MUST return nothing
  immediately when the site's workspace root is not the template root (which
  includes every hub-shaped site, i.e. the hub's own workspace root, and every site
  with no workspace route at all); it MUST NOT attempt to parse a slug out of a
  hub-shaped site's path using the template root's landing-segment set.
- **workspace-slug-excludes-landing-segments**: For a site whose workspace root is
  the template root, workspace-slug parsing MUST take the first non-empty path
  segment and return it as the slug unless that segment is a member of the
  landing-segment set, in which case it MUST return nothing — including for the
  empty-path case, which resolves to no first segment and therefore also nothing.
- **landing-and-hub-segment-sets-are-answer-specific**: The landing-segment set MUST
  be consulted only for a template-root site's first path segment, and the hub's own
  route-segment set MUST be consulted only for the hub's own first path segment; a
  caller MUST NOT answer one site's question from the other set, since the two sets
  name different words (the hub serves `/login`, `/explore`, `/settings`, which no
  template site does, and does not serve a template site's own words such as
  `/guidelines` or `/forum`).

### Per-site build configuration

- **build-fields-outside-scaffold-region**: None of the per-site build
  configuration's field names (`legacyHomePaths`, `extraRedirects`,
  `requiresBackendUrl`, `handRolledConfig`) MUST ever appear inside the roster's
  mechanically generated region; they MUST live only in the hand-written build
  configuration table outside that region, because a field written inside the
  generated region is silently dropped the next time the region is regenerated.
- **site-build-config-default-empty**: Build-configuration lookup MUST return a
  site's build configuration entry when one exists, and MUST return an empty
  result — never nothing and never a thrown error — for any site with no entry,
  since most sites need no per-site build behavior at all.
- **cookbook-and-hub-excluded-from-site-build**: `cookbook` and `hub` MUST NOT carry
  `legacyHomePaths`, `extraRedirects`, or `requiresBackendUrl` entries in the build
  configuration table; their redirect data derives from site-local modules this
  registry cannot import, and stamping a frozen copy here would recreate the drift
  those modules exist to prevent.

### Reserved slugs

- **reserved-slug-per-site-lookup**: Reserved-slug lookup MUST look up the given
  site's entry in the reserved-slug table and return true when the normalized slug
  (trimmed and lower-cased) is a member of that site's list, and false when it is
  not.
- **reserved-slug-unknown-site-fail-open**: Reserved-slug lookup MUST return false,
  never true and never throw, when the given site has no entry in the reserved-slug
  table; this fail-open behavior is a documented precondition, not a gap — at least
  one real caller passes a raw, unvalidated database column value that cannot be
  statically confirmed as a known site identifier, and that caller's own validation
  is pinned to fail open rather than reject a write for a site this registry has
  never heard of.
- **reserved-slug-normalization**: Both reserved-slug lookup and the cross-site
  reserved-slug check MUST normalize their slug argument by trimming whitespace and
  lower-casing before comparing against a reserved list, so `" Admin "` and `"admin"`
  are treated identically.
- **reserved-slug-anywhere-is-a-cross-site-or**: The cross-site reserved-slug check
  MUST return true when ANY site named in the reserved-slug table reserves the
  normalized slug, computed as the logical OR across every site's list; it MUST NOT
  answer from a single site's list alone, even on the day every list happens to be
  textually identical, because the lists are declared per-site specifically so they
  can diverge later.

### Generated route map

- **site-route-shares-is-the-sole-roster**: The route shares MUST be the only place
  a route share is registered; adding a new region MUST be done by adding one
  share, and no other source may add a share the merged route map draws from.
- **site-routes-merges-all-shares**: The merged route map MUST be the shallow merge
  of every route share, in the shares' own declared order.
- **route-shares-keyed-only-to-family-sites**: Every identifier present across all
  route shares MUST be a valid site identifier that is a member of the main-family
  roster or the marketing-family roster; a route map MUST NOT name a site outside
  that union.
- **route-shares-are-pairwise-disjoint**: No site identifier MUST appear as a key in
  more than one route share; each site's routes are owned by exactly one region's
  generator.
- **route-list-per-site-is-normalized**: Every non-empty route list inside a share
  MUST consist of absolute paths (each beginning with `/`), sorted, and free of
  duplicates.

### Brand story and guided tour

- **site-stories-total-map**: The brand-story map MUST assign exactly one brand
  story (a `tier`, a `pillar`, a `funnelStage`, and a `nextStep`) to every site
  identifier, and to no identifier outside that set; the mapping's own type MUST
  make omitting a newly scaffolded site's story a build-time error rather than a
  silent gap.
- **exactly-one-masterbrand**: Exactly one brand-story entry MUST have
  `tier: 'masterbrand'`, and it MUST be `hub`.
- **next-step-never-self-referential**: No brand-story entry's `nextStep` MUST equal
  its own site identifier.
- **next-step-chains-converge-on-hub**: Following any site's `nextStep` chain
  repeatedly MUST eventually reach `hub`, for every site in the brand-story map —
  whatever door a visitor entered the family through, the brand story MUST lead back
  to the platform.
- **funnel-stage-never-empty**: Every funnel-stage value (`discover`, `learn`,
  `build`, `ship`, `adopt`) MUST be the `funnelStage` of at least one brand-story
  entry.
- **next-step-distinct-from-tour-graph**: A brand story's `nextStep` MUST be read as
  the hand-authored brand-story cross-link only; it MUST NOT be treated as
  interchangeable with an edge in the merged guided-tour graph, since the two are
  separate, independently maintained edge sets over the same site identifiers that
  happen to agree for many sites but are not guaranteed to.
- **tour-rings-are-separately-generated-and-merged**: Each of the three tour rings
  MUST be generated and maintained independently (each owned by a different region's
  own manifest), and the merged guided-tour graph MUST be their merge in a fixed
  order; a site identifier MUST NOT be declared as a key in more than one ring,
  since a collision is absorbed silently by the merge rather than caught at build
  time.
- **tour-ring-may-be-empty**: A tour ring (for example the main ring, which has
  carried no entries since 2026-08-31) legitimately being empty MUST be treated as a
  real, renderable state — "this region's generator has not populated its ring
  yet" — not as an error condition.
- **get-site-story-direct-lookup**: Brand-story lookup MUST return a site's
  brand-story entry directly, with no fallback and no transformation, for any valid
  site identifier.

### Persona and cross-site URL helpers

- **persona-and-registry-paths-percent-encode-slugs**: The persona and registry path
  builders MUST percent-encode every slug segment they place into a path, since a
  slug is untrusted, registrant-supplied text placed directly into a URL path.
- **persona-profile-url-resolves-current-env**: The persona profile URL builder MUST
  resolve the persona registry's current-environment absolute URL via the cross-site
  URL builder, using the current environment's hostname when one is available and an
  empty string otherwise (this concept is also evaluated in a context with no
  ambient page/window, so it MUST NOT read that hostname from any global page state
  directly).
- **site-url-falls-back-to-bare-path**: The cross-site URL builder MUST return the
  path unchanged when the given site identifier resolves to no known site (via site
  lookup), rather than throwing or returning a malformed URL.
- **site-prod-url-ignores-current-environment**: The production URL builder MUST
  always resolve `https://<prodHost><path>` regardless of the caller's current
  environment, since it exists specifically as the deterministic server-rendered
  default computed before the client's own hostname is known.
- **site-home-path-fallback**: The home-path fallback MUST return `/home` when the
  site's `hasHome` is `true`, and `/` otherwise.

## Appearance

Not applicable — this is the site family's data registry and routing-resolution
module, not a visual component.

## States

Not applicable — this is the site family's data registry and routing-resolution
module, not a visual component. Its only stateful concept — the additive, one-way-door
growth of the SSO return-origin allowlist as the staging-deploy/testing-deploy flags
are set over time — is covered under Behavioral Requirements above (the Cross-Site SSO
Origin Allowlist subsection), not as a visual-state table.

## Accessibility

Not applicable — this is the site family's data registry and routing-resolution
module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| site-registry-001 | detect-env-classification | Classifying hosts `agenticdeveloperhub.com`, `testing.agenticdeveloperhub.com`, `staging.admin.agenticdeveloperhub.com`, `admin.localhost` (traced to `registry.test.ts`'s "classifies production hosts", "classifies testing / staging by leading label", and "classifies local hosts") | `'production'`, `'testing'`, `'staging'`, `'local'` respectively |
| site-registry-002 | host-for-env-fallback, build-site-href-env-aware | Building a cross-site link to the `mcp` site (no testing deploy) from host `testing.agenticdeveloperhub.com`, path `/` (traced to "falls back testing → staging when the target lacks a testing env") | `'https://staging.mcp.agenticdeveloperhub.com/'` |
| site-registry-003 | carry-path-home-only | Building a cross-site link to `hub` from host `agenticdeveloperhub.com`, path `/home/foo` (traced to "carries deep /home routes with the up-walk marker") | `'https://agenticdeveloperhub.com/home/foo#site-switch'` |
| site-registry-004 | carry-path-home-only | Building a cross-site link to `hub-help` (no home route) from host `agenticdeveloperhub.com`, path `/home` (traced to "sends /home to root for sites without a /home route") | `'https://help.agenticdeveloperhub.com/'` |
| site-registry-005 | local-origin-suite-domain-priority | Building a cross-site link to `cookbook` from host `localhost`, path `/home` (traced to "resolves to a local origin from local dev (bare localhost, no port)") | `'http://cookbook.localhost/home'` |
| site-registry-006 | sso-return-origins-partitioned-by-env, sso-external-exclusion-fail-closed | Computing the OAuth return-origin allowlist for `'production'` (traced to "production = every non-external site as a bare-host origin (no env prefix)" and "never allows an external link-out origin, in any env") | Includes `https://<prodHost>` for every non-external site; never includes `fishlamp`'s or `fishlampdesign`'s origin |
| site-registry-007 | sso-return-origins-partitioned-by-env | Computing the OAuth return-origin allowlist for `'testing'` (traced to "testing = only sites with a testing deploy, prefixed testing.") | Includes exactly the `https://testing.<prodHost>` origin of every site with a testing deploy, and no others |
| site-registry-008 | sso-return-origins-partitioned-by-env | Computing the OAuth return-origin allowlist for `'staging'` (traced to "staging = every staging-deploy site, prefixed staging.") | Includes exactly the `https://staging.<prodHost>` origin of every site with a staging deploy, and no others |
| site-registry-009 | workspace-href-single-shape | Building the workspace link for slug `'acme'`, for every site with a workspace route, including the two sites whose workspace once nested under a different shape (traced to "builds `/<slug>` for every site with a workspace, including the two that once differed") | `'/acme'` for every one of them |
| site-registry-010 | workspace-href-single-shape | Building the workspace link for an empty slug (traced to "returns undefined for an empty slug rather than minting `//`") | Nothing |
| site-registry-011 | workspace-slug-root-sites-only | Parsing a workspace slug from path `/acme` on the hub, whose workspace root is the hub shape (traced to "refuses the hub rather than parsing it with the template's landing set") | Nothing |
| site-registry-012 | workspace-slug-excludes-landing-segments | Parsing a workspace slug from path `/guidelines` on `cookbook`, where `'guidelines'` is a member of the landing-segment set (traced to "returns null on a landing path, so nothing public is carried as a workspace") | Nothing |
| site-registry-013 | workspace-slug-excludes-landing-segments | Parsing a workspace slug from path `/home` on `cookbook` (traced to "returns null on `/home`, which is the redirect signal and carries no slug") | Nothing |
| site-registry-014 | landing-and-hub-segment-sets-are-answer-specific | Every real static top-level route of every template-root site, compared against the landing-segment set; the hub's own static top-level routes compared against the hub's own route-segment set (traced to "covers every static top-level route of every 'root' site" and "equals the hub's static top-level routes, in both directions") | Both comparisons match exactly, in both directions |
| site-registry-015 | site-for-hub-segment-tiebreak | Resolving the site owning hub segment `'products'`, which both `ecosystems` and `products` map to in the feature-segment map (traced to "names the documented winner for each shared segment, and the site itself for the rest") | The `products` site (not `ecosystems`) |
| site-registry-016 | build-fields-outside-scaffold-region | The raw roster source text inside its mechanically generated region (traced to `build-fields.test.ts`'s "keeps build fields out of the scaffold-managed region") | Contains none of `legacyHomePaths`, `extraRedirects`, `requiresBackendUrl`, `handRolledConfig` |
| site-registry-017 | site-build-config-default-empty | Sites in the build configuration table with `requiresBackendUrl` set (traced to "marks exactly the five backend-fronting sites as requiring a backend url") | Exactly `['billing', 'bitbag', 'narratives', 'personaregistry', 'projects']` |
| site-registry-018 | reserved-slug-unknown-site-fail-open | Checking whether `'anything'` is reserved for `hub`, which has no entry in the reserved-slug table (traced to `reserved-slugs.test.ts`'s documented unknown-site case) | `false` |
| site-registry-019 | reserved-slug-anywhere-is-a-cross-site-or | Checking whether a slug is reserved anywhere, with a reservation temporarily injected on one site only, then removed (traced to "is the OR across sites, not one site's list") | `true` while the injected reservation exists |
| site-registry-020 | route-shares-keyed-only-to-family-sites, route-shares-are-pairwise-disjoint | The identifier set across all route shares (traced to `siteRoutes.test.ts`'s "keys only registry family sites, so the SiteId typing stays honest" and "gives every site to exactly one share") | Equals the main-family roster union the marketing-family roster exactly; no identifier repeated across two shares |
| site-registry-021 | route-list-per-site-is-normalized | Every non-empty route list in every share (traced to "lists absolute, sorted, deduplicated paths per site") | Every path begins with `/`; each site's list is sorted and contains no duplicate |
| site-registry-022 | site-stories-total-map, next-step-never-self-referential | The brand-story map's keys against the site identifier set, and every entry's `nextStep` against its own identifier (traced to `story.test.ts`'s "covers every registered site (and nothing else)" and "never points a next step at the site itself") | Key sets match exactly; no entry's `nextStep` equals its own identifier |
| site-registry-023 | next-step-chains-converge-on-hub | Every site's `nextStep` chain, followed repeatedly (traced to "every next-step chain converges on the hub") | Every chain reaches `hub` |
| site-registry-024 | tour-rings-are-separately-generated-and-merged | The three tour rings' key sets (traced to `tour-region.test.ts`'s ring-disjointness assertions) | Pairwise disjoint; every edge names a real site identifier on both ends; no self-pointing edge |

## Edge Cases

- **Null and empty input**: Building the workspace link for an empty slug returns
  nothing rather than minting `//` (workspace-href-single-shape). Parsing a
  workspace slug for an empty path resolves the path to `/`, whose first segment is
  empty, and therefore returns nothing. The cross-site URL builder, for a site
  identifier not present in the roster, returns the given path unmodified rather
  than throwing.
- **Boundary values**: A site with no testing deploy and no staging deploy
  (a production-only site) resolves to its bare `prodHost` from every non-local
  environment (environment host resolution's two-level fallback ends on the bare
  host, never on nothing). A site definition with neither a workspace route nor a
  home route is a valid, fully supported shape (an operations console such as
  `admin`, `status`, or `bitbag`) — the absence of both is not itself an
  inconsistency to flag.
- **Concurrent access**: This registry is synchronous and stateless — every value is
  computed once when the registry loads and every operation is a pure function over
  that data, with no shared mutable state written at runtime — so there is no
  interleaving for two callers reading the site roster, the merged route map, or the
  merged guided-tour graph at once to race against.
- **Error states — a shared hub feature segment with no clear owner**: The reverse
  feature-segment lookup's tie-break (site-for-hub-segment-tiebreak) resolves
  deterministically by "does the site's own identifier equal the segment," but a
  future segment shared by two sites where NEITHER site's identifier equals the
  segment resolves silently to whichever site's feature-segment entry was declared
  first in source order; this is documented as an intentional, documented convention
  rather than an oversight.
- **Error states — a route share whose generator has not run yet in this checkout**:
  A region's generated route share can legitimately be empty in a checkout whose own
  region generator has not run yet — a dedicated check's own fill-expectation table
  names `main` as the one region currently expected to be empty, and any other
  region going empty without an entry in that table is what the "has every share
  filled in" check exists to catch.
- **Error states — the additive OAuth allowlist widening unintentionally**: Flipping
  a staging-deploy or testing-deploy flag to `true` on a site claimed but not yet
  actually deployed on that tier allowlists a redirect target for a host nothing is
  serving; the OAuth return-origin allowlist's own documentation names the
  historical precedent (the `messaging` site, 2026-08-22) where a flag flip that
  looked like a listing change permanently widened two environments' allowlists, and
  states that a caller wanting to narrow the allowlist back down must run a
  separate, deliberate pruning tool against the database column this allowlist's
  output feeds — this registry itself performs no pruning.
- **Offline or disconnected state**: Not applicable — every part of this component
  performs only synchronous, local computation over in-memory constants; none of it
  makes a network request.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| The site roster | list of site definitions | fixed at build time | The whole family roster; not caller-configurable at runtime — a new site is added by editing the registry (its mechanically generated region for the mechanically-added fields, or the hand-authored part directly). |
| The hostname (environment detection, the cross-site URL builder, the persona profile URL builder) | string | caller-supplied; the persona profile URL builder defaults to the current environment's hostname when available, else an empty string | The current request/browser host, used to resolve which deploy environment and, for local dev, which suite the caller is on. |
| The current hostname / path (cross-site link construction) | string | caller-supplied; required | The visitor's current host and path, used to resolve the target site's href in the same environment and to decide whether `/home` is carried. |
| The recognized local suite domains | fixed list of strings (internal constant) | `['sites.localhost', 'dev.test', 'dev.local']` | The domain suffixes recognized as a local-suite host; not caller-configurable. |
| The environment (the OAuth return-origin allowlist) | one of `'production'`, `'staging'`, `'testing'` | caller-supplied; required | Which deploy environment's OAuth-return-origin allowlist to compute. |
| The build configuration table | optional build configuration entry per site identifier | fixed at build time | Per-site build behavior flags read by the shared build-configuration package; not caller-configurable at runtime. |

## Deep Linking

Not applicable: this component defines no URL scheme, route handler, or navigation
target of its own; it is the data other code reads to build one.

## Localization

Each site definition carries hardcoded English `label`, `fullLabel`, `shortLabel`,
and `description` strings for every site (for example `"The Agentic Developer Hub"`,
`"Recipes & patterns"`), and header-title derivation's `"Agentic Developer <X>"`
title is built from the same hardcoded English convention. None of these strings is
routed through any localization or string-catalog layer in this component; a
translated build of the switcher, footer, or header would need its own separate
string source, since this registry supplies only the one, English, copy.

## Accessibility Options

Not applicable: this component has no UI of its own, so it responds to no Reduce
Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: no part of this component declares or reads a feature-flag key; a
site definition's `featured` field is a display-order marker for the switcher, not
a feature gate, and nothing reads it today.

## Analytics

Not applicable: no part of this component emits an analytics or event-tracking call.

## Privacy

- **Data collected**: This component reads and returns only site metadata (ids,
  labels, hosts, environment flags, route lists, brand-story classifications) that
  is itself source-controlled configuration, not user data. The persona and registry
  path builders accept a caller-supplied slug (a public handle a registrant chose)
  and percent-encode it into a path; no credential, token, or other secret value is
  read or handled anywhere in this component.
- **Storage**: This component persists nothing at runtime; every value is either a
  constant computed once at load or the result of a pure function with no side
  effect.
- **Transmission**: Not applicable — this component performs no networking of its
  own. The OAuth return-origin allowlist's output is consumed by a separate
  deploy-time sync process elsewhere, which is the one that actually transmits it to
  a database column; that transmission is outside this component.
- **Retention**: Not applicable — nothing here is retained beyond the lifetime of
  the process that loaded the registry.

## Logging

Not applicable: no part of this component makes a logging call of any kind; every
function either returns a computed value or returns a documented fallback (nothing,
an empty result, or the input path unchanged) with no side channel.

## Platform Notes

- **AppKit / UIKit**: These are TypeScript/web sources with no Apple-framework
  dependency; a macOS/iOS reader of this recipe would model a site definition and a
  brand story as `Codable` `struct`s, the site roster and the brand-story map as
  `static let` constants (loaded from a bundled JSON or a generated Swift file
  rather than re-typed by hand), and environment detection/cross-site link
  construction/the OAuth return-origin allowlist as pure functions over
  `URLComponents`/`String` with no `NSObject` subclassing needed anywhere.
- **SwiftUI**: No SwiftUI dependency exists in the source. A SwiftUI consumer would
  typically expose the registry's derived collections (the listed-sites set, the
  footer site list, category grouping's output) as plain `let` properties on an
  `@Observable` view model computed once at init, since none of the underlying data
  ever changes during a running process.
- **Compose**: A Kotlin port would model the site identifier type as a `sealed
  interface`/`enum class` rather than a string-literal union (closer to identifier
  validation's narrowing contract than TypeScript's own union erasure), a site
  definition/brand story as `data class`es, and the various derived `Set`/`Map`
  constants (the landing-segment set, the full workspace-segment set, the merged
  guided-tour graph) as `kotlinx.collections.immutable` structures built once at
  object-initialization time, mirroring this module's compute-once-at-load pattern.
- **React/Web**: This is the source. The implementation lives in `registry.ts`,
  `reserved-slugs.ts`, the thirteen `routes.*.generated.ts` shares plus the
  hand-written `routes.generated.ts`, and `story.ts`, all under
  `packages/web/packages/adh-registry/src/sites/`. `registry.ts` declares the
  `SiteId` union and the `SiteDef` shape, the `SITES` array, environment/host
  resolution (`detectEnv`, `hostForEnv`, `localOrigin`, `buildSiteHref`), the hub's
  feature-segment map (`HUB_FEATURE_SEGMENT`, `SITE_FOR_HUB_SEGMENT`,
  `HUB_WORKSPACE_SEGMENTS`), the workspace-slug round trip (`siteWorkspaceHref`/
  `siteWorkspaceSlug` plus `SITE_LANDING_SEGMENTS`/`HUB_ROUTE_SEGMENTS`), the
  per-site build-config side table (`SITE_BUILD`/`siteBuildConfig`) kept outside the
  file's `<gen:sites>`…`</gen:sites>` scaffolded region, and the SSO allowlist
  (`ssoReturnOrigins`). `reserved-slugs.ts` holds `RESERVED_SLUGS`,
  `isReservedSlug`, and `isReservedSlugAnywhere`. The route shares merge via
  `Object.assign` into `SITE_ROUTE_SHARES`/`SITE_ROUTES`. `story.ts` holds
  `SITE_STORIES`, `getSiteStory`, and the three generated rings `TOUR_MAIN`/
  `TOUR_MARKETING`/`TOUR_PLACEHOLDER` merged by object spread into
  `SITE_TOUR_NEXT`. A site's build-tree directory name is a Next.js app-router
  folder derived by `dirNameOf`; a site's workspace route is a Next.js
  `app/[workspace]` dynamic route. `personaProfileUrl` reads the current hostname
  from `globalThis.location?.hostname ?? ''` rather than `window` directly, because
  this file is also type-checked in a backend build with no DOM library. The files
  are pure TypeScript with no React import, consumed by React components (the
  header, switcher, and footer) that live elsewhere in the same web packages; a
  caller re-implementing this in another JS/TS codebase should keep the same
  pure-data/pure-function shape rather than folding any of it into a component or a
  hook, since several of the exports (`ssoReturnOrigins`, the route shares) are
  consumed by non-React code (a backend sync job, a sitemap generator) that would
  break if the logic moved into a component. Nothing in the module uses `async`,
  `Promise`, or any mutable module-level state — every export is a `const` computed
  once at module load or a pure function over that data.
- **WinUI 3**: A .NET port would model the site identifier type as an `enum`, a
  site definition/brand story as `record`s (immutable by default, matching this
  module's `readonly`-everywhere shape), the various derived set/map constants as
  `FrozenSet<string>`/`FrozenDictionary<TKey, TValue>` computed once in a static
  constructor, environment detection/environment host resolution/local-origin
  resolution as pure `static` methods over `Uri`/`string`, and `System.Text.Json`
  for deserializing any of this data if it were instead shipped as a generated JSON
  asset rather than compiled Swift/Kotlin/C# source; no `HttpClient`,
  `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or
  `INotifyPropertyChanged` is needed anywhere, since nothing in this component
  performs I/O, runs asynchronously, or changes after process start.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-registry/src/sites/` |

## Design Decisions

**Decision**: The per-site build configuration fields (`legacyHomePaths`,
`extraRedirects`, `requiresBackendUrl`, `handRolledConfig`) live in a separate build
configuration table below the roster's mechanically generated region, rather than as
optional fields on a site definition inside that region.
**Rationale**: Most roster entries live inside the scaffolded region, which the
scaffolding tool regenerates wholesale from a fixed template blind to any field not
in that template. A hand-authored field written on a roster entry inside the region
would be silently dropped, with no error and no failing test, the next time the tool
regenerates it. Keeping the data in a table physically outside the region makes that
impossible rather than merely discouraged. Applies to the web implementation, where
the roster has a scaffolded region at all.
**Approved**: pending

**Decision**: A site's workspace-route field records only whether a site mounts a
workspace route and, for the two roots that exist ("root" and "hub"), which root —
not the historical per-site nested shape (`/home/<slug>`, `/<slug>/home`) that an
earlier rollout once required.
**Rationale**: Every site that mounts a workspace route now mounts the identical
`/<slug>` shape; the remaining distinction is not the URL shape but which set of
static top-level segments (the landing-segment set vs. the hub's own route-segment
set) tells a slug apart from a page on that root, which is exactly what the
two-valued field, plus the two segment sets, needs to express.
**Approved**: pending

**Decision**: The OAuth return-origin allowlist is computed fresh from the
staging-deploy/testing-deploy/external flags on every call rather than cached, but
the deploy-time job that persists its output into the enforcing database column is
deliberately additive-only and never prunes.
**Rationale**: The enforcement point for an OAuth redirect allowlist is a security
control; the computation itself can safely recompute (it has no side effect), but
automatically shrinking a persisted allowlist whenever a flag flips back to `false`
risks silently revoking a redirect target that some other, unrelated part of the
system still depends on being live during a migration. Un-widening is deliberately
made a separate, hand-run, auditable action instead.
**Approved**: pending

**Decision**: The merged guided-tour graph's three rings (the main ring, the
marketing ring, the placeholder ring) are three separately generated constants
merged by a plain object spread, rather than one map with regions spliced in place.
**Rationale**: Each ring is generated by a different region's own tooling, and those
regions cannot see each other's site trees. A single generated map would be
overwritten wholesale by whichever region's generator ran last, silently deleting
every other region's entries — a failure mode that still compiles, still satisfies
every test assertion about the entries it kept, and simply drops the other rings out
of the guided tour with nothing anywhere reporting it. Three separately-owned
constants, each with its own generated-region markers, make that specific failure
structurally impossible; the cost is that a compile-time duplicate-key check cannot
see a site claimed by two rings at once, which is why a dedicated test asserts the
three key sets are pairwise disjoint. Applies to the web implementation's
generated-constant mechanism specifically; any implementation adopting per-region
generation inherits the same trade-off.
**Approved**: pending

**Decision**: The route shares — the roster of generated per-region route shares
merged into the route map — is stated exactly once, as the shares' own key list,
with no restating of the region names or the share count in prose comments above it.
**Rationale**: A prose paragraph restating "there are N shares, owned by these
regions" drifts from the list it describes every time a share is added or removed,
because nothing forces the two to change together; this specific paragraph was
rewritten at five consecutive splits and was still wrong at the sixth. Deriving
every test case from the list itself, and saying nothing else in prose, removes the
second copy that could drift.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this component keeps its five concerns in five separately-owned files (site identity and routing in `registry.ts`, slug reservation in `reserved-slugs.ts`, the generated per-repo route map in the thirteen `routes.*.generated.ts` shares plus the hand-written merge in `routes.generated.ts`, and brand-story/tour data in `story.ts`), with per-site build-only data deliberately isolated in its own `SITE_BUILD` side table outside the scaffolded region so scaffolding, build configuration, and routing data cannot be clobbered by each other's regeneration. `unit-test-coverage` passes: `registry.test.ts`, `registry-characterisation.test.ts`, `siteRoutes.test.ts`, `story.test.ts`, `tour-region.test.ts`, `sites/__tests__/reserved-slugs.test.ts`, and `sites/__tests__/build-fields.test.ts` together exercise every exported function's branches, including environment classification and fallback, the workspace-slug round trip in both directions, the additive SSO allowlist's per-environment partitioning, the scaffold-region isolation invariant, the reserved-slug fail-open contract, the route-share disjointness and normalization invariants, and the brand-story/tour-graph convergence and disjointness invariants. `no-hardcoded-strings` fails: every `SiteDef`'s `label`, `fullLabel`, `shortLabel`, and `description` is a literal English string with no localization or string-catalog indirection (see Localization above), and `siteHeaderTitle`'s `"Agentic Developer <X>"` derivation is built from the same hardcoded convention; a translated presentation of the switcher, footer, or header cannot be produced from this file alone.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/sites/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
