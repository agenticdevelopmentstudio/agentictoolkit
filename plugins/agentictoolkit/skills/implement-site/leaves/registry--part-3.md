<!-- leaf: implement-site/registry--part-3 · source: site-registry.md -->

# Site Registry — continued (part 3)

**Rules** (cite as `implement-site/registry--part-3#<slug>`):

- `hub-feature-segment-default-is-site-id` MUST
- `hub-feature-segment-many-to-one-allowed` MUST
- `site-for-hub-segment-tiebreak` MUST
- `hub-workspace-segments-is-the-full-union` MUST
- `hub-extra-segments-have-no-registry-site` MUST
- `workspace-href-single-shape` MUST
- `workspace-slug-root-sites-only` MUST
- `workspace-slug-excludes-landing-segments` MUST
- `landing-and-hub-segment-sets-are-answer-specific` MUST
- `build-fields-outside-scaffold-region` MUST
- `site-build-config-default-empty` MUST
- `cookbook-and-hub-excluded-from-site-build` MUST
- `reserved-slug-per-site-lookup` MUST
- `reserved-slug-unknown-site-fail-open` MUST
- `reserved-slug-normalization` MUST
- `reserved-slug-anywhere-is-a-cross-site-or` MUST
- `site-route-shares-is-the-sole-roster` MUST
- `site-routes-merges-all-shares` MUST
- `route-shares-keyed-only-to-family-sites` MUST
- `route-shares-are-pairwise-disjoint` MUST
- `route-list-per-site-is-normalized` MUST
- `site-stories-total-map` MUST
- `exactly-one-masterbrand` MUST
- `next-step-never-self-referential` MUST
- `next-step-chains-converge-on-hub` MUST
- `funnel-stage-never-empty` MUST
- `next-step-distinct-from-tour-graph` MUST
- `tour-rings-are-separately-generated-and-merged` MUST
- `tour-ring-may-be-empty` MUST
- `get-site-story-direct-lookup` MUST

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

