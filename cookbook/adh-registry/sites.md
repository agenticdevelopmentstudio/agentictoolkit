---
id: 9069ccf9-0357-4311-9671-91ee2793adae
title: Site Registry
domain: agentictoolkit://cookbook/adh-registry/sites
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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

`registry.ts`, `reserved-slugs.ts`, the thirteen `routes.*.generated.ts` shares plus the hand-written `routes.generated.ts`, and `story.ts` (all under `packages/web/packages/adh-registry/src/sites/`) together are the single source of truth for the Agentic Developer Hub (ADH) site family: roughly seventy independently deployed sites (`hub`, `cookbook`, `projects`, `billing`, …) that share a header, a cross-site switcher, and a central OAuth client. `registry.ts` declares the `SiteId` union and the `SiteDef` shape (display names, production host, which deploy environments exist, whether the site exposes the shared `/home` route, whether it mounts an authenticated `[workspace]` route), the `SITES` array of every site's data, environment/host resolution for cross-site navigation (`detectEnv`, `hostForEnv`, `localOrigin`, `buildSiteHref`), the hub's in-workspace feature-segment map (`HUB_FEATURE_SEGMENT`, `SITE_FOR_HUB_SEGMENT`, `HUB_WORKSPACE_SEGMENTS`), the workspace-slug round-trip (`siteWorkspaceHref`/`siteWorkspaceSlug` plus the two disjoint landing-segment sets `SITE_LANDING_SEGMENTS`/`HUB_ROUTE_SEGMENTS`), a per-site build-config side table (`SITE_BUILD`/`siteBuildConfig`) deliberately kept outside the scaffolded region of the file, and the cross-site-SSO OAuth redirect allowlist (`ssoReturnOrigins`). `reserved-slugs.ts` lists, per site, which top-level path segments a registrant cannot claim as a public handle. The `routes.*.generated.ts` shares are per-repo generated route maps merged by the hand-written `routes.generated.ts` into `SITE_ROUTE_SHARES`/`SITE_ROUTES`, feeding the dev "Routes" flyout and, in a downstream repo, a sitemap's static-segment exclusion list. `story.ts` is the brand-story data spine behind every logged-out landing page: a hand-authored `SITE_STORIES` record (brand tier, message-house pillar, funnel stage, and a brand-judgment "next step" per site) plus a separately generated, three-ring guided-tour graph (`TOUR_MAIN`/`TOUR_MARKETING`/`TOUR_PLACEHOLDER` merged into `SITE_TOUR_NEXT`). All of it is pure TypeScript data and functions — no React, no I/O beyond synchronous in-memory lookups — read by the header, the site switcher, the footer, the hub's workspace router, and the backend's OAuth-return-origin sync job.

## Behavioral Requirements

### Site identity and roster (`SiteId`, `SiteDef`, `SITES`)

- **site-id-closed-union**: `SiteId` MUST be a closed TypeScript string-literal union naming every site the family currently knows about; a string value obtained from outside the type system (a directory name, a CLI argument, a DB column) MUST be narrowed through `isSiteId` or `siteIdForDir` before it can index `SITES` or any table keyed by `SiteId`.
- **unique-site-ids**: Every entry in `SITES` MUST have a unique `id`, and `SITES` MUST NOT contain an entry for the backend service itself.
- **site-def-minimum-fields**: Every `SITES` entry MUST declare `id`, `label`, and `prodHost`, and MUST declare `hasStaging`, `hasTesting`, and `hasHome` as explicit booleans (never omitted, since `hostForEnv`, `ssoReturnOrigins`, and `buildSiteHref`'s home-carry all branch on their literal `true`/`false` value).
- **workspace-route-not-derived-from-has-home**: `SiteDef.workspaceRoute` MUST NOT be inferred from `SiteDef.hasHome`; the two are independent facts about a site's route tree (`bitbag`, `status`, and `admin` have `hasHome: false` and no `workspaceRoute`, while `hub-help` and `personaregistry` have `hasHome` true or false independently of having no `workspaceRoute` at all), and a caller deriving one from the other risks sending a workspace switch to a route that 404s.
- **external-site-excluded-from-sso**: A `SITES` entry with `external: true` MUST be excluded from `ssoReturnOrigins`'s allowlist in every environment, because such a site (FishLamp Design) has no `/auth/callback` and never begins an ADH login.
- **admin-only-derives-admin-ids-and-drops-footer**: `ADMIN_SITE_IDS` MUST be exactly the `id`s of every `SITES` entry with `adminOnly: true`, and every such entry MUST be excluded from `FOOTER_SITES`.
- **listed-sites-filter**: `LISTED_SITES` MUST be exactly the `SITES` entries whose `listed` field is not literally `false`; a `listed: false` entry MUST remain resolvable by `getSite`/`isSiteId` and MUST only be excluded from the roster, never from the registry itself.
- **footer-sites-filter**: `FOOTER_SITES` MUST be exactly the `LISTED_SITES` entries whose `crawlable` is not `false` and whose `adminOnly` is not `true`, in the same order as `LISTED_SITES`.

### Lookup and identification (`getSite`, `isSiteId`, `siteIdForDir`)

- **get-site-lookup**: `getSite(id)` MUST return the `SITES` entry whose `id` equals the argument, or `undefined` when no such entry exists.
- **is-site-id-derived-from-sites**: `isSiteId(value)` MUST return `true` if and only if some entry in `SITES` has that `id`; it MUST be derived from `SITES` directly rather than from a second, separately maintained list, so it can never diverge from the ids the registry actually declares.
- **dir-name-strips-tld**: `dirNameOf` (the folder-name convention used internally by `siteIdForDir`) MUST derive a site's Next.js app-folder name by stripping the trailing `.<tld>` from `prodHost` (e.g. `help.agenticdeveloperhub.com` → `help.agenticdeveloperhub`).
- **site-id-for-dir-bare-id-first**: `siteIdForDir(name)` MUST return `name` unchanged (narrowed to `SiteId`) when `name` is already a valid site id, before falling back to a `prodHost`-derived folder-name match; it MUST return `undefined` when `name` matches neither a site id nor any site's derived folder name.

### Family groupings (`MAIN_SITE_IDS`, `MARKETING_SITE_IDS`, `SITE_CATEGORIES`, `groupSitesByCategory`)

- **main-marketing-ids-are-disjoint-curated-lists**: `MAIN_SITE_IDS` and `MARKETING_SITE_IDS` MUST each be a hand-curated, non-overlapping array of site ids; an id present in one MUST NOT appear in the other, and `mcp` and `builds` (which have no Next.js app folder anywhere) MUST appear in neither.
- **site-categories-exactly-one-membership**: Every id appearing in any `SITE_CATEGORIES` group's `ids` MUST appear in exactly one group's `ids`, never zero and never more than one.
- **group-by-category-preserves-order-and-collects-leftovers**: `groupSitesByCategory(sites)` MUST emit groups in `SITE_CATEGORIES` order, with members in each group's declared `ids` order, MUST omit any group with no matching member in `sites`, and MUST collect every site in `sites` that matches no category's `ids` into a single trailing group labelled `"More"`, so that a newly scaffolded site can never be silently dropped from a menu built on this function.

### Display title (`siteHeaderTitle`, `splitSiteTitle`)

- **header-title-explicit-fulllabel-wins**: `siteHeaderTitle(site)` MUST return `site.fullLabel` when it is set, taking priority over any derivation from `prodHost`.
- **header-title-derives-from-apex-pattern**: When `fullLabel` is absent and `prodHost` matches `agenticdeveloper<x>.com`, `siteHeaderTitle(site)` MUST return `"Agentic Developer <X>"` with `<x>` capitalized, and MUST fall back to `site.label` when `prodHost` matches neither an explicit `fullLabel` nor that pattern.
- **split-title-prefix-detection**: `splitSiteTitle(site)` MUST split `siteHeaderTitle(site)` into `{ titleLead: "Agentic Developer", titleAccent: <rest> }` when the header title begins with `"Agentic Developer "`, and MUST return `{ titleLead: "", titleAccent: <whole title> }` for an off-pattern brand name (for example the Persona Registry).

### Environment and cross-site navigation (`detectEnv`, `hostForEnv`, `localOrigin`, `carryPath`, `buildSiteHref`)

- **detect-env-classification**: `detectEnv(hostname)` MUST lower-case and strip any trailing `:<port>` before classifying, MUST classify a hostname as `'local'` when it is exactly `localhost`, starts with `127.`, is `::1`, or ends in `.local`, `.test`, or `.localhost`; MUST classify a hostname starting with `testing.` as `'testing'` and one starting with `staging.` as `'staging'`; and MUST classify every other hostname as `'production'`.
- **host-for-env-fallback**: `hostForEnv(site, env)` MUST resolve `testing.<prodHost>` when `env === 'testing'` and `site.hasTesting`; otherwise for `'testing'` it MUST fall back to `staging.<prodHost>` when `site.hasStaging`, and otherwise to the bare `prodHost`. For `env === 'staging'` it MUST resolve `staging.<prodHost>` when `site.hasStaging` and otherwise the bare `prodHost`. For `'production'` it MUST always resolve the bare `prodHost`.
- **local-origin-suite-domain-priority**: `localOrigin(target, currentHost)` MUST first check whether the lower-cased, port-stripped `currentHost` ends in one of `LOCAL_SUITE_DOMAINS` (`sites.localhost`, `dev.test`, `dev.local`, checked in that order for readability only); when it does, the target's local origin MUST be `https://<sub>.<suite>.<domain>` (no subdomain for `hub`) reusing the current host's own `<suite>` label. When `currentHost` matches none of `LOCAL_SUITE_DOMAINS`, `localOrigin` MUST fall back to `http://<sub>localhost<:port>`, carrying the current port when one is present.
- **carry-path-home-only**: `carryPath(target, pathname)` MUST return the target's landing path (`/`) for any `pathname` other than `/home` or a path starting with `/home/`; for `pathname === '/home'` it MUST return `/home` when `target.hasHome` and `/` otherwise; for a deeper `/home/*` path it MUST return the same path with the `#site-switch` hash appended (so the target's not-found page knows to walk the path up), or `/` when the target has no `/home` route at all.
- **build-site-href-env-aware**: `buildSiteHref(target, currentHostname, pathname)` MUST classify the current environment via `detectEnv(currentHostname)`; for `'local'` it MUST return `localOrigin(target, currentHostname)` concatenated with `carryPath(target, pathname)`; for every other environment it MUST return `https://<hostForEnv(target, env)>` concatenated with `carryPath(target, pathname)`.

### Cross-Site SSO Origin Allowlist (security-relevant)

- **sso-return-origins-partitioned-by-env**: `ssoReturnOrigins(env)` MUST return, for `env === 'production'`, the bare `https://<prodHost>` origin of every `SITES` entry that is not `external`; for `env === 'staging'`, only the `https://staging.<prodHost>` origin of every non-`external` entry with `hasStaging: true`; for `env === 'testing'`, only the `https://testing.<prodHost>` origin of every non-`external` entry with `hasTesting: true`.
- **sso-flag-flip-is-a-one-way-door**: `hasStaging` and `hasTesting` are the OAuth redirect surface this function names, and flipping either from `false` to `true` MUST be treated as permanently widening that environment's allowlist: the deploy-time sync job (`backend/src/adh/src/lib/sync-return-origins.ts`) that reads this function's output into the enforcing DB column is additive-only and never prunes a row that a later flag flip back to `false` would otherwise remove. A caller changing an existing row's flag back to `false` MUST NOT assume the corresponding origin stops being a valid OAuth `return` target without a separate, deliberate, hand-run pruning pass against that environment.
- **sso-external-exclusion-fail-closed**: An origin belonging to a `SITES` entry with `external: true` MUST NOT appear in `ssoReturnOrigins`'s result for any environment, on a fail-closed basis: an origin that cannot complete an ADH login has no legitimate reason to be a legal `return` target, so the absence is deliberate rather than an oversight to fill in.

### Hub in-workspace feature routing (`HUB_FEATURE_SEGMENT`, `SITE_FOR_HUB_SEGMENT`, `HUB_EXTRA_FEATURE_SEGMENTS`, `HUB_WORKSPACE_SEGMENTS`)

- **hub-feature-segment-default-is-site-id**: `HUB_FEATURE_SEGMENT` MUST map a routed site's `id` to the hub's own `/<slug>/<segment>` feature segment for that site's implementation; the default mapping is a site's own id, and every entry that maps to a different segment MUST do so because the hub already routed that feature under a different name before the site existed.
- **hub-feature-segment-many-to-one-allowed**: Two or more site ids MAY map to the same `HUB_FEATURE_SEGMENT` value (for example `ecosystems` and `products` both mapping to `'products'`) when the hub renders one pane for both; `hubFeatureSegment(id)` MUST return that shared segment for either id.
- **site-for-hub-segment-tiebreak**: `SITE_FOR_HUB_SEGMENT`, the reverse of `HUB_FEATURE_SEGMENT`, MUST resolve a segment shared by more than one site to the site whose own `id` equals that segment when one exists (for example `'products'` resolves to the `products` site, not `ecosystems`); when no site's id equals the segment, it MUST resolve to whichever site's mapping was declared first in `HUB_FEATURE_SEGMENT`.
- **hub-workspace-segments-is-the-full-union**: `HUB_WORKSPACE_SEGMENTS` MUST be exactly the union of every value in `HUB_FEATURE_SEGMENT` and every entry in `HUB_EXTRA_FEATURE_SEGMENTS`, so a caller answering "is this second path segment a hub workspace feature?" never has to consult the two source lists separately.
- **hub-extra-segments-have-no-registry-site**: An entry in `HUB_EXTRA_FEATURE_SEGMENTS` MUST name a hub workspace feature with no corresponding registry site (a hub-only knob, such as an ecosystem's member list, or the persona-data CRUD surface); a feature that is some site's own implementation MUST be keyed in `HUB_FEATURE_SEGMENT` by that site's id instead.

### Workspace routing (`siteWorkspaceHref`, `siteWorkspaceSlug`, `SITE_LANDING_SEGMENTS`, `HUB_ROUTE_SEGMENTS`)

- **workspace-href-single-shape**: `siteWorkspaceHref(target, slug)` MUST return `undefined` when `slug` is falsy (including the empty string) or when `target.workspaceRoute` is absent; otherwise it MUST return exactly `/<slug>`, the one route shape every site with a `workspaceRoute` mounts today.
- **workspace-slug-root-sites-only**: `siteWorkspaceSlug(site, pathname)` MUST return `null` immediately when `site.workspaceRoute !== 'root'` (which includes every hub-shaped site, i.e. `workspaceRoute === 'hub'`, and every site with no `workspaceRoute` at all); it MUST NOT attempt to parse a slug out of a hub-shaped site's path using the root site's landing-segment set.
- **workspace-slug-excludes-landing-segments**: For a `workspaceRoute: 'root'` site, `siteWorkspaceSlug(site, pathname)` MUST take the first non-empty path segment of `pathname` and return it as the slug unless that segment is a member of `SITE_LANDING_SEGMENTS`, in which case it MUST return `null` — including for the empty-path case, which resolves to no first segment and therefore also `null`.
- **landing-and-hub-segment-sets-are-answer-specific**: `SITE_LANDING_SEGMENTS` MUST be consulted only for a `workspaceRoute: 'root'` site's first path segment, and `HUB_ROUTE_SEGMENTS` MUST be consulted only for the hub's own first path segment; a caller MUST NOT answer one site's question from the other set, since the two sets name different words (the hub serves `/login`, `/explore`, `/settings`, which no template site does, and does not serve a template site's own words such as `/guidelines` or `/forum`).

### Per-site build configuration (`SiteBuildConfig`, `SITE_BUILD`, `siteBuildConfig`)

- **build-fields-outside-scaffold-region**: None of `SiteBuildConfig`'s field names (`legacyHomePaths`, `extraRedirects`, `requiresBackendUrl`, `handRolledConfig`) MUST ever appear inside the file's `<gen:sites>`…`</gen:sites>` scaffolded region; they MUST live only in the hand-written `SITE_BUILD` table below the region's close marker, because a field written inside the scaffolded region is silently dropped the next time the scaffolding tool regenerates it.
- **site-build-config-default-empty**: `siteBuildConfig(id)` MUST return the site's `SITE_BUILD` entry when one exists, and MUST return an empty object (`{}`) — never `undefined` and never a thrown error — for any site with no entry, since most sites need no per-site build behavior at all.
- **cookbook-and-hub-excluded-from-site-build**: `cookbook` and `hub` MUST NOT carry `legacyHomePaths`, `extraRedirects`, or `requiresBackendUrl` entries in `SITE_BUILD`; their redirect data derives from site-local modules this package cannot import, and stamping a frozen copy here would recreate the drift those modules exist to prevent.

### Reserved slugs (`reserved-slugs.ts`)

- **reserved-slug-per-site-lookup**: `isReservedSlug(siteId, slug)` MUST look up `RESERVED_SLUGS[siteId]` and return `true` when the normalized `slug` (trimmed and lower-cased) is a member of that site's list, and `false` when it is not.
- **reserved-slug-unknown-site-fail-open**: `isReservedSlug(siteId, slug)` MUST return `false`, never `true` and never throw, when `siteId` has no entry in `RESERVED_SLUGS`; this fail-open behavior is a documented precondition, not a gap — the module names it explicitly because at least one real caller passes a raw, unnarrowed database column value that cannot be statically confirmed as a known `SiteId`, and that caller's own validation is pinned to fail open rather than reject a write for a site this module has never heard of.
- **reserved-slug-normalization**: Both `isReservedSlug` and `isReservedSlugAnywhere` MUST normalize their `slug` argument by trimming whitespace and lower-casing before comparing against a reserved list, so `" Admin "` and `"admin"` are treated identically.
- **reserved-slug-anywhere-is-a-cross-site-or**: `isReservedSlugAnywhere(slug)` MUST return `true` when ANY site named in `RESERVED_SLUGS` reserves the normalized `slug`, computed as the logical OR across every site's list; it MUST NOT answer from a single site's list alone, even on the day every list happens to be textually identical, because the lists are declared per-site specifically so they can diverge later.

### Generated route map (`SITE_ROUTE_SHARES`, `SITE_ROUTES`)

- **site-route-shares-is-the-sole-roster**: `SITE_ROUTE_SHARES` MUST be the only place a route share is registered; adding a new region MUST be done by adding one key to this object, and no other file may add a share `SITE_ROUTES` merges.
- **site-routes-merges-all-shares**: `SITE_ROUTES` MUST be the shallow merge (`Object.assign`) of every value in `SITE_ROUTE_SHARES`, in `SITE_ROUTE_SHARES`'s own key order.
- **route-shares-keyed-only-to-family-sites**: Every key present across all of `SITE_ROUTE_SHARES`'s values MUST be a valid `SiteId` that is a member of `MAIN_SITE_IDS` or `MARKETING_SITE_IDS`; a route map MUST NOT name a site outside that union.
- **route-shares-are-pairwise-disjoint**: No `SiteId` MUST appear as a key in more than one of `SITE_ROUTE_SHARES`'s values; each site's routes are owned by exactly one region's generator.
- **route-list-per-site-is-normalized**: Every non-empty route list inside a share MUST consist of absolute paths (each beginning with `/`), sorted, and free of duplicates.

### Brand story and guided tour (`story.ts`)

- **site-stories-total-map**: `SITE_STORIES` MUST assign exactly one `SiteStory` (a `tier`, a `pillar`, a `funnelStage`, and a `nextStep`) to every `SiteId`, and to no id outside that union; the type system (`Record<SiteId, SiteStory>`) MUST make omitting a newly scaffolded site's story a compile error rather than a silent gap.
- **exactly-one-masterbrand**: Exactly one `SITE_STORIES` entry MUST have `tier: 'masterbrand'`, and it MUST be `hub`.
- **next-step-never-self-referential**: No `SITE_STORIES` entry's `nextStep` MUST equal its own site id.
- **next-step-chains-converge-on-hub**: Following any site's `nextStep` chain repeatedly MUST eventually reach `hub`, for every site in `SITE_STORIES` — whatever door a visitor entered the family through, the brand story MUST lead back to the platform.
- **funnel-stage-never-empty**: Every `FunnelStage` value (`discover`, `learn`, `build`, `ship`, `adopt`) MUST be the `funnelStage` of at least one `SITE_STORIES` entry.
- **next-step-distinct-from-tour-graph**: `SiteStory.nextStep` MUST be read as the hand-authored brand-story cross-link only; it MUST NOT be treated as interchangeable with an edge in `SITE_TOUR_NEXT`, since the two are separate, independently maintained edge sets over the same site ids that happen to agree for many sites but are not guaranteed to.
- **tour-rings-are-separately-generated-and-merged**: `TOUR_MAIN`, `TOUR_MARKETING`, and `TOUR_PLACEHOLDER` MUST each be generated and maintained independently (each owned by a different repo's own manifest), and `SITE_TOUR_NEXT` MUST be their object-spread merge in that fixed order; a site id MUST NOT be declared as a key in more than one of the three rings, since a collision is absorbed silently by the spread rather than caught by the compiler.
- **tour-ring-may-be-empty**: A tour ring (for example `TOUR_MAIN`, which has carried no entries since 2026-08-31) legitimately being empty MUST be treated as a real, renderable state — "this repo's generator has not populated its ring yet" — not as an error condition.
- **get-site-story-direct-lookup**: `getSiteStory(id)` MUST return `SITE_STORIES[id]` directly, with no fallback and no transformation, for any valid `SiteId`.

### Persona and cross-site URL helpers

- **persona-and-registry-paths-percent-encode-slugs**: `personaProfilePath`, `registryUserPath`, `registryUserPersonaPath`, and `registryOrgPath` MUST percent-encode every slug segment they place into a path via `encodeURIComponent`, since a slug is untrusted, registrant-supplied text placed directly into a URL path.
- **persona-profile-url-resolves-current-env**: `personaProfileUrl(slug)` MUST resolve the persona registry's current-environment absolute URL via `siteUrl('personaregistry', personaProfilePath(slug), hostname)`, using the current global `location.hostname` when one is available and an empty string otherwise (this file is also type-checked in a backend build with no DOM library, so it MUST NOT reference `window` directly).
- **site-url-falls-back-to-bare-path**: `siteUrl(id, path, currentHostname)` MUST return `path` unchanged when `id` resolves to no known site (via `getSite`), rather than throwing or returning a malformed URL.
- **site-prod-url-ignores-current-environment**: `siteProdUrl(id, path)` MUST always resolve `https://<prodHost><path>` regardless of the caller's current environment, since it exists specifically as the deterministic server-side-rendered default computed before the client's own hostname is known.
- **site-home-path-fallback**: `siteHomePath(id)` MUST return `/home` when the site's `hasHome` is `true`, and `/` otherwise.

## Appearance

Not applicable — this is the site family's data registry and routing-resolution module, not a visual component.

## States

Not applicable — this is the site family's data registry and routing-resolution module, not a visual component. Its only stateful concept — the additive, one-way-door growth of the SSO return-origin allowlist as `hasStaging`/`hasTesting` flags are set over time — is covered under Behavioral Requirements above (the Cross-Site SSO Origin Allowlist subsection), not as a visual-state table.

## Accessibility

Not applicable — this is the site family's data registry and routing-resolution module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| site-registry-001 | detect-env-classification | `detectEnv('agenticdeveloperhub.com')`, `detectEnv('testing.agenticdeveloperhub.com')`, `detectEnv('staging.admin.agenticdeveloperhub.com')`, `detectEnv('admin.localhost')` (traced to `registry.test.ts`'s "classifies production hosts", "classifies testing / staging by leading label", and "classifies local hosts") | `'production'`, `'testing'`, `'staging'`, `'local'` respectively |
| site-registry-002 | host-for-env-fallback, build-site-href-env-aware | `buildSiteHref(mcp, 'testing.agenticdeveloperhub.com', '/')` where `mcp.hasTesting === false` (traced to "falls back testing → staging when the target lacks a testing env") | `'https://staging.mcp.agenticdeveloperhub.com/'` |
| site-registry-003 | carry-path-home-only | `buildSiteHref(hub, 'agenticdeveloperhub.com', '/home/foo')` (traced to "carries deep /home routes with the up-walk marker") | `'https://agenticdeveloperhub.com/home/foo#site-switch'` |
| site-registry-004 | carry-path-home-only | `buildSiteHref(hubHelp, 'agenticdeveloperhub.com', '/home')` where `hubHelp.hasHome === false` (traced to "sends /home to root for sites without a /home route") | `'https://help.agenticdeveloperhub.com/'` |
| site-registry-005 | local-origin-suite-domain-priority | `buildSiteHref(cookbook, 'localhost', '/home')` (traced to "resolves to a local origin from local dev (bare localhost, no port)") | `'http://cookbook.localhost/home'` |
| site-registry-006 | sso-return-origins-partitioned-by-env, sso-external-exclusion-fail-closed | `ssoReturnOrigins('production')` (traced to "production = every non-external site as a bare-host origin (no env prefix)" and "never allows an external link-out origin, in any env") | Includes `https://<prodHost>` for every non-`external` site; never includes `fishlamp`'s or `fishlampdesign`'s origin |
| site-registry-007 | sso-return-origins-partitioned-by-env | `ssoReturnOrigins('testing')` (traced to "testing = only sites with a testing deploy, prefixed testing.") | Includes exactly the `https://testing.<prodHost>` origin of every site with `hasTesting: true`, and no others |
| site-registry-008 | sso-return-origins-partitioned-by-env | `ssoReturnOrigins('staging')` (traced to "staging = every staging-deploy site, prefixed staging.") | Includes exactly the `https://staging.<prodHost>` origin of every site with `hasStaging: true`, and no others |
| site-registry-009 | workspace-href-single-shape | `siteWorkspaceHref(target, 'acme')` for every site with a `workspaceRoute` set, including the two sites whose workspace once nested under a different shape (traced to "builds `/<slug>` for every site with a workspace, including the two that once differed") | `'/acme'` for every one of them |
| site-registry-010 | workspace-href-single-shape | `siteWorkspaceHref(target, '')` (traced to "returns undefined for an empty slug rather than minting `//`") | `undefined` |
| site-registry-011 | workspace-slug-root-sites-only | `siteWorkspaceSlug(hub, '/acme')` where `hub.workspaceRoute === 'hub'` (traced to "refuses the hub rather than parsing it with the template's landing set") | `null` |
| site-registry-012 | workspace-slug-excludes-landing-segments | `siteWorkspaceSlug(cookbook, '/guidelines')` where `'guidelines'` is a member of `SITE_LANDING_SEGMENTS` (traced to "returns null on a landing path, so nothing public is carried as a workspace") | `null` |
| site-registry-013 | workspace-slug-excludes-landing-segments | `siteWorkspaceSlug(cookbook, '/home')` (traced to "returns null on `/home`, which is the redirect signal and carries no slug") | `null` |
| site-registry-014 | landing-and-hub-segment-sets-are-answer-specific | Every real static top-level route of every `workspaceRoute: 'root'` site, compared against `SITE_LANDING_SEGMENTS`; the hub's own static top-level routes compared against `HUB_ROUTE_SEGMENTS` (traced to "covers every static top-level route of every 'root' site" and "equals the hub's static top-level routes, in both directions") | Both comparisons match exactly, in both directions |
| site-registry-015 | site-for-hub-segment-tiebreak | `SITE_FOR_HUB_SEGMENT['products']` where both `ecosystems` and `products` map to `'products'` in `HUB_FEATURE_SEGMENT` (traced to "names the documented winner for each shared segment, and the site itself for the rest") | The `products` site (not `ecosystems`) |
| site-registry-016 | build-fields-outside-scaffold-region | The raw `registry.ts` source text between its `<gen:sites>` and `</gen:sites>` markers (traced to `build-fields.test.ts`'s "keeps build fields out of the scaffold-managed region") | Contains none of `legacyHomePaths`, `extraRedirects`, `requiresBackendUrl`, `handRolledConfig` |
| site-registry-017 | site-build-config-default-empty | `Object.entries(SITE_BUILD)` filtered by `requiresBackendUrl` (traced to "marks exactly the five backend-fronting sites as requiring a backend url") | Exactly `['billing', 'bitbag', 'narratives', 'personaregistry', 'projects']` |
| site-registry-018 | reserved-slug-unknown-site-fail-open | `isReservedSlug('hub', 'anything')` where `hub` has no entry in `RESERVED_SLUGS` (traced to `reserved-slugs.test.ts`'s documented unknown-site case) | `false` |
| site-registry-019 | reserved-slug-anywhere-is-a-cross-site-or | `isReservedSlugAnywhere(slug)` with a temporarily injected reservation on one site only, removed afterward (traced to "is the OR across sites, not one site's list") | `true` while the injected reservation exists |
| site-registry-020 | route-shares-keyed-only-to-family-sites, route-shares-are-pairwise-disjoint | The key set across all of `SITE_ROUTE_SHARES`'s values (traced to `siteRoutes.test.ts`'s "keys only registry family sites, so the SiteId typing stays honest" and "gives every site to exactly one share") | Equals `MAIN_SITE_IDS ∪ MARKETING_SITE_IDS` exactly; no id repeated across two shares |
| site-registry-021 | route-list-per-site-is-normalized | Every non-empty route list in every share (traced to "lists absolute, sorted, deduplicated paths per site") | Every path begins with `/`; each site's list is sorted and contains no duplicate |
| site-registry-022 | site-stories-total-map, next-step-never-self-referential | `SITE_STORIES` keys vs. `SiteId`, and every entry's `nextStep` vs. its own id (traced to `story.test.ts`'s "covers every registered site (and nothing else)" and "never points a next step at the site itself") | Key sets match exactly; no entry's `nextStep` equals its own id |
| site-registry-023 | next-step-chains-converge-on-hub | Every site's `nextStep` chain, followed repeatedly (traced to "every next-step chain converges on the hub") | Every chain reaches `hub` |
| site-registry-024 | tour-rings-are-separately-generated-and-merged | `TOUR_MAIN`, `TOUR_MARKETING`, `TOUR_PLACEHOLDER` key sets (traced to `tour-region.test.ts`'s ring-disjointness assertions) | Pairwise disjoint; every edge names a real `SiteId` on both ends; no self-pointing edge |

## Edge Cases

- **Null and empty input**: `siteWorkspaceHref(target, '')` returns `undefined` rather than minting `//` (workspace-href-single-shape). `siteWorkspaceSlug(site, '')` resolves `pathname || '/'` to `/`, whose first segment is empty, and therefore returns `null`. `siteUrl(id, path, currentHostname)` for an `id` not present in `SITES` returns `path` unmodified rather than throwing.
- **Boundary values**: A site with `hasTesting: false` and `hasStaging: false` (a production-only site) resolves to its bare `prodHost` from every non-local environment (`hostForEnv`'s two-level fallback ends on the bare host, never on `undefined`). A `SITES` entry with neither `workspaceRoute` nor `hasHome` is a valid, fully supported shape (an operations console such as `admin`, `status`, or `bitbag`) — the absence of both is not itself an inconsistency to flag.
- **Concurrent access**: This module is synchronous, single-threaded TypeScript with no `async` function, no `Promise`, and no shared mutable state written at runtime — every export is either a `const` computed once at module load or a pure function over that data — so there is no interleaving for two callers reading `SITES`, `SITE_ROUTES`, or `SITE_TOUR_NEXT` at once to race against.
- **Error states — a shared hub feature segment with no clear owner**: `SITE_FOR_HUB_SEGMENT`'s tie-break (site-for-hub-segment-tiebreak) resolves deterministically by "does the site's own id equal the segment," but a future segment shared by two sites where NEITHER site's id equals the segment resolves silently to whichever site's `HUB_FEATURE_SEGMENT` entry was declared first in source order; the source's own comment names this as an intentional, documented convention rather than an oversight.
- **Error states — a route share whose generator has not run yet in this checkout**: A `routes.<region>.generated.ts` file's share can legitimately be empty in a checkout that is a submodule of a repo whose own generator has not run — `siteRoutes.test.ts`'s `EXPECTED_FILL` table names `main` as the one region currently expected to be empty, and any other region going empty without an entry in that table is what the "has every share filled in" test exists to catch.
- **Error states — the additive OAuth allowlist widening unintentionally**: Flipping `hasStaging`/`hasTesting` to `true` on a site claimed but not yet actually deployed on that tier allowlists a redirect target for a host nothing is serving; `ssoReturnOrigins`'s own documentation names the historical precedent (the `messaging` site, 2026-08-22) where a flag flip that looked like a listing change permanently widened two environments' allowlists, and states that a caller wanting to narrow the allowlist back down must run a separate, deliberate pruning tool against the DB column this function's output feeds — this module itself performs no pruning.
- **Offline or disconnected state**: Not applicable — every file in this component performs only synchronous, local computation over in-memory constants; none of it makes a network request.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SITES` | `SiteDef[]` | fixed at build time | The whole family roster; not caller-configurable at runtime — a new site is added by editing `registry.ts` (its scaffolded `<gen:sites>` region for the mechanically-added fields, or the file directly for a hand-authored one). |
| `hostname` (`detectEnv`, `siteUrl`, `personaProfileUrl`) | `string` | caller-supplied; `personaProfileUrl` defaults to `globalThis.location?.hostname ?? ''` | The current request/browser host, used to resolve which deploy environment and, for local dev, which suite the caller is on. |
| `currentHostname` / `pathname` (`buildSiteHref`) | `string` | caller-supplied; required | The visitor's current host and path, used to resolve the target site's href in the same environment and to decide whether `/home` is carried. |
| `LOCAL_SUITE_DOMAINS` | `readonly string[]` (module-internal constant) | `['sites.localhost', 'dev.test', 'dev.local']` | The domain suffixes recognized as a `dev.local`-suite host; not caller-configurable. |
| `env` (`ssoReturnOrigins`) | `'production' \| 'staging' \| 'testing'` | caller-supplied; required | Which deploy environment's OAuth-return-origin allowlist to compute. |
| `SITE_BUILD` | `Partial<Record<SiteId, SiteBuildConfig>>` | fixed at build time | Per-site build behavior flags read by the shared Next.js config package; not caller-configurable at runtime. |

## Deep Linking

Not applicable: this component defines no URL scheme, route handler, or navigation target of its own; it is the data other code reads to build one.

## Localization

`registry.ts`'s `SiteDef` entries carry hardcoded English `label`, `fullLabel`, `shortLabel`, and `description` strings for every site (for example `"The Agentic Developer Hub"`, `"Recipes & patterns"`), and `siteHeaderTitle`'s derived `"Agentic Developer <X>"` title is built from the same hardcoded English convention. None of these strings is routed through any localization or string-catalog layer in this file; a translated build of the switcher, footer, or header would need its own separate string source, since this registry supplies only the one, English, copy.

## Accessibility Options

Not applicable: this file has no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: no file in this component declares or reads a feature-flag key; `SiteDef.featured` is a display-order marker for the switcher, not a feature gate, and the source's own comment on it states that nothing reads it today.

## Analytics

Not applicable: no file in this component emits an analytics or event-tracking call.

## Privacy

- **Data collected**: This component reads and returns only site metadata (ids, labels, hosts, environment flags, route lists, brand-story classifications) that is itself source-controlled configuration, not user data. `personaProfilePath`/`registryUserPath`/`registryOrgPath` accept a caller-supplied slug (a public handle a registrant chose) and percent-encode it into a path; no credential, token, or other secret value is read or handled anywhere in this component.
- **Storage**: This component persists nothing at runtime; every export is either a module-level constant computed once at load or a pure function with no side effect.
- **Transmission**: Not applicable — this component performs no networking of its own. `ssoReturnOrigins`'s output is consumed by a separate deploy-time sync job in another repo, which is the one that actually transmits it to a database column; that transmission is outside this component.
- **Retention**: Not applicable — nothing here is retained beyond the lifetime of the process that imported the module.

## Logging

Not applicable: no file in this component makes a `console.*` call, an `OSLog`/`Logger`-equivalent call, or any other logging call; every function either returns a computed value or returns a documented fallback (`undefined`, `null`, `{}`, or the input path unchanged) with no side channel.

## Platform Notes

- **AppKit / UIKit**: These are TypeScript/web sources with no Apple-framework dependency; a macOS/iOS reader of this recipe would model `SiteDef`/`SiteStory` as `Codable` `struct`s, `SITES`/`SITE_STORIES` as `static let` constants (loaded from a bundled JSON or a generated Swift file rather than re-typed by hand), and `detectEnv`/`buildSiteHref`/`ssoReturnOrigins` as pure functions over `URLComponents`/`String` with no `NSObject` subclassing needed anywhere.
- **SwiftUI**: No SwiftUI dependency exists in the source. A SwiftUI consumer would typically expose the registry's derived collections (`LISTED_SITES`, `FOOTER_SITES`, `groupSitesByCategory`'s output) as plain `let` properties on an `@Observable` view model computed once at init, since none of the underlying data ever changes during a running process.
- **Compose**: A Kotlin port would model `SiteId` as a `sealed interface`/`enum class` rather than a string-literal union (closer to `isSiteId`'s narrowing contract than TypeScript's own union erasure), `SiteDef`/`SiteStory` as `data class`es, and the various derived `Set`/`Map` constants (`SITE_LANDING_SEGMENTS`, `HUB_WORKSPACE_SEGMENTS`, `SITE_TOUR_NEXT`) as `kotlinx.collections.immutable` structures built once at object-initialization time, mirroring this module's compute-once-at-load pattern.
- **React/Web**: This is the source. The files are pure TypeScript with no React import, consumed by React components (the header, switcher, and footer) that live elsewhere in the same web packages; a caller re-implementing this in another JS/TS codebase should keep the same pure-data/pure-function shape rather than folding any of it into a component or a hook, since several of the exports (`ssoReturnOrigins`, the route shares) are consumed by non-React code (a backend sync job, a sitemap generator) that would break if the logic moved into a component.
- **WinUI 3**: A .NET port would model `SiteId` as an `enum`, `SiteDef`/`SiteStory` as `record`s (immutable by default, matching this module's `readonly`-everywhere shape), the various `Set<string>`/`Record<SiteId, X>` constants as `FrozenSet<string>`/`FrozenDictionary<SiteId, X>` computed once in a static constructor, `detectEnv`/`hostForEnv`/`localOrigin` as pure `static` methods over `Uri`/`string`, and `System.Text.Json` for deserializing any of this data if it were instead shipped as a generated JSON asset rather than compiled Swift/Kotlin/C# source; no `HttpClient`, `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or `INotifyPropertyChanged` is needed anywhere, since nothing in this component performs I/O, runs asynchronously, or changes after process start.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-registry/src/sites/` |

## Design Decisions

**Decision**: `SiteBuildConfig` fields (`legacyHomePaths`, `extraRedirects`, `requiresBackendUrl`, `handRolledConfig`) live in a separate `SITE_BUILD` side table below the `<gen:sites>` region's close marker, rather than as optional fields on `SiteDef` inside that region.
**Rationale**: Most `SITES` entries live inside the scaffolded `<gen:sites>` region, which the scaffolding tool regenerates wholesale from a fixed template blind to any field not in that template. A hand-authored field written on a `SITES` entry inside the region would be silently dropped, with no error and no failing test, the next time the tool regenerates it. Keeping the data in a table physically outside the region makes that impossible rather than merely discouraged.
**Approved**: pending

**Decision**: `workspaceRoute` records only whether a site mounts an `app/[workspace]` route and, for the two roots that exist (`'root'` and `'hub'`), which root — not the historical per-site nested shape (`/home/<slug>`, `/<slug>/home`) that PR #197's rollout once required.
**Rationale**: Every site that mounts a workspace route now mounts the identical `/<slug>` shape; the remaining distinction is not the URL shape but which set of static top-level segments (`SITE_LANDING_SEGMENTS` vs. `HUB_ROUTE_SEGMENTS`) tells a slug apart from a page on that root, which is exactly what the two-valued field, plus the two segment sets, needs to express.
**Approved**: pending

**Decision**: `ssoReturnOrigins`'s allowlist is computed fresh from `hasStaging`/`hasTesting`/`external` on every call rather than cached, but the deploy-time job that persists its output into the enforcing DB column is deliberately additive-only and never prunes.
**Rationale**: The enforcement point for an OAuth redirect allowlist is a security control; the function itself can safely recompute (it has no side effect), but automatically shrinking a persisted allowlist whenever a flag flips back to `false` risks silently revoking a redirect target that some other, unrelated part of the system still depends on being live during a migration. Un-widening is deliberately made a separate, hand-run, auditable action instead.
**Approved**: pending

**Decision**: `SITE_TOUR_NEXT`'s three rings (`TOUR_MAIN`, `TOUR_MARKETING`, `TOUR_PLACEHOLDER`) are three separately generated `const`s merged by a plain object spread, rather than one map with regions spliced in place.
**Rationale**: Each ring is generated by a different repo's own tooling, and those repos cannot see each other's site trees. A single generated map would be overwritten wholesale by whichever repo's generator ran last, silently deleting every other repo's entries — a failure mode that still compiles, still satisfies every test assertion about the entries it kept, and simply drops the other rings out of the guided tour with nothing anywhere reporting it. Three separately-owned `const`s, each with its own generated-region markers, make that specific failure structurally impossible; the cost is that the compiler's own duplicate-key check cannot see a site claimed by two rings at once, which is why a dedicated test asserts the three key sets are pairwise disjoint.
**Approved**: pending

**Decision**: `SITE_ROUTE_SHARES` — the roster of generated per-repo route shares merged into `SITE_ROUTES` — is stated exactly once, as the constant's own key list, with no restating of the repo names or the share count in prose comments above it.
**Rationale**: A prose paragraph restating "there are N shares, owned by these repos" drifts from the constant it describes every time a share is added or removed, because nothing forces the two to change together; the source's own comment records that this specific paragraph was rewritten at five consecutive splits and was still wrong at the sixth. Deriving every test case from the constant itself, and saying nothing else in prose, removes the second copy that could drift.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
