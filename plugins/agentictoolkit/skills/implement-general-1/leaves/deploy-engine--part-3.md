<!-- leaf: implement-general-1/deploy-engine--part-3 · source: deploy-engine.md -->

# Deploy Engine — continued (part 3)

**Rules** (cite as `implement-general-1/deploy-engine--part-3#<slug>`):

- `explicit-environment-precedence` MUST
- `placeholder-url-for-domainless` MUST
- `exact-host-wiring` MUST
- `exact-host-conflict-vs-stale-repair` MUST
- `exact-host-excludes-non-deploy-kinds` MUST
- `apex-ownership-add-endpoint` MUST
- `apex-ownership-excluded-for-domainless` MUST
- `sibling-match-same-platform-and-base` MUST
- `sibling-match-cross-platform-excluded` MUST
- `sibling-env-conflict` MUST
- `new-site-fallback` MUST
- `live-project-index-canonicalization` MUST
- `stale-wiring-requires-verified-platform` MUST
- `apply-sequentially-order` MUST
- `apply-sequentially-resilience` MUST
- `apply-sequentially-progress` MUST
- `family-group-immutability` MUST
- `family-group-split-is-null` MUST
- `group-for-new-site-fallback` MUST
- `unique-site-identity-order` MUST
- `execute-add-conflict-and-env-conflict-skip` MUST
- `execute-add-wire-endpoint-reports-replacement` MUST
- `execute-add-match-only-skips-creation` MUST
- `execute-add-new-site-rollback` MUST
- `execute-add-new-site-group-note` MUST
- `run-auto-configure-snapshot-build` MUST
- `index-endpoint-wiring-ambiguous-is-null` MUST
- `index-endpoint-wiring-defensive-domains` MUST
- `wire-matching-endpoints-idempotent-target-selection` MUST
- `wire-matching-endpoints-per-target-resilience` MUST

### Add planning (`plan.ts`)

- **explicit-environment-precedence**: `planAddProject` MUST use
  `project.environment` (trimmed; empty treated as absent) as the
  endpoint's environment when it is present, and MUST fall back to
  `hostEnv(domain)` when there is a domain or `envFromProject(projectName)`
  when there is none, only when no explicit environment was supplied.
- **placeholder-url-for-domainless**: `planAddProject` MUST use the fixed
  string `PLACEHOLDER_URL` (`"https://"`) as the plan's `url` when
  `project.domain` is absent, and MUST use `https://${domain}` otherwise.
- **exact-host-wiring**: When an endpoint exists whose `epHost` equals the
  project's domain, `endpointNeedsWiring(e.kind)` is `true`, and no such
  endpoint is currently wired to a different, still-live deploy project,
  `planAddProject` MUST return a `wire-endpoint` plan for that endpoint,
  preserving the endpoint's own `environment` over the derived one when the
  endpoint already has one set.
- **exact-host-conflict-vs-stale-repair**: When the exact-host endpoint is
  wired to a different deploy project, `planAddProject` MUST return a
  `conflict` plan when that other project is still live (per `opts
  .liveProjects`, or when no live-project index was supplied at all), and
  MUST otherwise (the named project is verified absent on its own platform)
  return a `wire-endpoint` plan carrying `replaces` (the retired project
  name) and `replacesPlatform` (that project's own canonical platform, not
  necessarily the platform being added).
- **exact-host-excludes-non-deploy-kinds**: A `health`/`custom`/`dns`
  endpoint sharing the exact host MUST NOT be treated as an exact-host match
  by **exact-host-wiring**; it falls through to apex/sibling matching.
- **apex-ownership-add-endpoint**: When no exact-host match exists but a
  wireable endpoint's `siteApex(epHost(...))` equals `siteApex(domain)`,
  `planAddProject` MUST return an `add-endpoint` plan onto that endpoint's
  site, preferring a wireable endpoint over a non-wireable one that also
  shares the apex.
- **apex-ownership-excluded-for-domainless**: `planAddProject` MUST NOT
  apply apex-ownership matching when the project has no domain (an empty
  apex must not "own" every endpoint whose URL fails to parse).
- **sibling-match-same-platform-and-base**: When no exact-host or apex match
  exists, `planAddProject` MUST match a project to a sibling site via an
  existing wireable endpoint whose `deployProject`'s `projectBaseName`
  equals this project's `projectBaseName` and whose canonical platform
  equals this project's canonical platform.
- **sibling-match-cross-platform-excluded**: A same-base-name project on a
  different canonical platform MUST NOT be matched as a sibling; it falls
  through to `new-site`.
- **sibling-env-conflict**: When a sibling site match is found but that
  site already has a different, wireable, still-relevant endpoint whose
  `environment` equals this project's derived environment and whose
  `deployProject` differs from this project's, `planAddProject` MUST return
  an `env-conflict` plan naming that endpoint and its project, MUST NOT
  relax this guard for a retired rival project (unlike the exact-host case),
  and MUST otherwise return an `add-endpoint` plan onto the sibling site.
- **new-site-fallback**: When none of exact-host, apex, or sibling matching
  applies, `planAddProject` MUST return a `new-site` plan whose `siteName`
  is `projectBaseName(deployProject)` and whose `siteSlug` is
  `slugify(siteName)` — the same base the sibling rule matches future
  projects against.
- **live-project-index-canonicalization**: `indexLiveProjects` MUST key
  `keys` by `deployProjectKey(platform, projectName)` for every supplied
  project and MUST canonicalize every entry of `verifiedPlatforms` via
  `platformCanon` before storing it in `platforms`.
- **stale-wiring-requires-verified-platform**: `planAddProject`'s
  `stillLive` check MUST treat an existing endpoint's wiring as live
  (conservative) whenever no `liveProjects` index was supplied, the endpoint
  has no `deployProject`, or the endpoint's own canonical platform is not a
  member of `liveProjects.platforms`; only when the platform IS verified
  MUST it check `liveProjects.keys` for that project's key.

### Auto-configure orchestration (`run.ts`)

- **apply-sequentially-order**: `applySequentially` MUST invoke `applyOne`
  for each item of `items` one at a time, in array order, and MUST NOT start
  the next item's `applyOne` call before the previous one has settled.
- **apply-sequentially-resilience**: `applySequentially` MUST catch any
  error thrown or rejection from `applyOne` for a given item, MUST push that
  item into `skipped` with the error's `message` (or its `String()` form
  when it is not an `Error`) as `reason`, and MUST proceed to the next item
  rather than rethrowing.
- **apply-sequentially-progress**: `applySequentially` MUST invoke
  `onProgress(done, total)`, when supplied, exactly once per item after that
  item's outcome (success or catch) has been recorded, with `total` fixed
  at `items.length` for the whole run.
- **family-group-immutability**: `Working.familyGroup`, once built by
  `indexFamilyGroups` at the start of `runAutoConfigure`, MUST NOT be
  mutated for the remainder of that run; a site created mid-run is filed
  using the map as it stood at the run's start.
- **family-group-split-is-null**: `indexFamilyGroups` MUST map a domain
  family to `null` when two different sites' groups both claim endpoints in
  that family, and MUST leave a family mapped to the single group when only
  one group's sites claim it.
- **group-for-new-site-fallback**: `groupForNewSite` MUST return
  `fallbackGroupId` when `domainFamily(host)` is `null` or when the family
  is present in `working.familyGroup` mapped to `null` or is absent from the
  map, and MUST otherwise return the mapped group id.
- **unique-site-identity-order**: `uniqueSiteIdentity` MUST try, in order,
  the base slug, then `slugify(host)` (only when `host` is non-empty), then
  `${base.slug}-2` through `${base.slug}-99`, returning the first candidate
  whose `${groupId}|${slug}` key is not in `taken` and whose slug is
  non-empty, and MUST return `base` unchanged (untried against any further
  variant) when `base.slug` is itself empty.
- **execute-add-conflict-and-env-conflict-skip**: `executeAdd` MUST turn a
  `conflict` or `env-conflict` plan into a `skipped` outcome carrying a
  human-readable, project-name-prefix-free reason string, and MUST NOT write
  to the API for either plan kind.
- **execute-add-wire-endpoint-reports-replacement**: `executeAdd` MUST call
  `api.updateEndpoint` for a `wire-endpoint` plan with the plan's `platform`,
  `deployProject`, and `environment`, MUST update the in-memory
  `working.endpoints` snapshot to match, and MUST attach a `note`
  describing what was replaced (naming `plan.replaces` and
  `plan.replacesPlatform`) exactly when the plan carried a `replaces` value.
- **execute-add-match-only-skips-creation**: `executeAdd` MUST return a
  `skipped` outcome with reason `"no site monitors this domain yet"` for an
  `add-endpoint` or `new-site` plan when `create` was not supplied, and MUST
  NOT call any creation API in that case.
- **execute-add-new-site-rollback**: When `create` is supplied and a
  `new-site` plan's `api.createEndpoint` call rejects after `api.createSite`
  already succeeded, `executeAdd` MUST call `api.deleteSite` for the
  just-created site as a best-effort rollback, MUST rethrow the original
  `createEndpoint` error (never the rollback's own outcome) regardless of
  whether the rollback itself succeeds or fails, and MUST remove the site's
  slug key from `working.takenSlugs` only when the rollback delete did not
  itself throw.
- **execute-add-new-site-group-note**: `executeAdd` MUST attach a `note` to
  a successful `new-site` creation naming the domain family and stating the
  site was filed under the family's existing group instead of the selected
  one, exactly when `groupForNewSite`'s result differs from
  `create.groupId`, and MUST attach no note when `create.forceGroup` is set
  or when the resolved group equals the selected one.
- **run-auto-configure-snapshot-build**: `runAutoConfigure` MUST fetch
  `api.listAllEndpoints()` and `api.listSites()` (in parallel, via
  `Promise.all`) exactly once at the start of the run and MUST seed
  `working.takenSlugs` from every fetched site's `${groupId}|${slug}`
  before applying any project.

### Endpoint-axis wiring (`run.ts`)

- **index-endpoint-wiring-ambiguous-is-null**: `indexEndpointWiring` MUST
  map a host to `null` when two different projects' domain lists both claim
  it (differing in canonical platform or project name), and MUST otherwise
  map it to that one project's `{ platform, deployProject }`.
- **index-endpoint-wiring-defensive-domains**: `indexEndpointWiring` MUST
  treat a project whose `domains` field is missing or nullish as
  contributing no host to the index rather than throwing.
- **wire-matching-endpoints-idempotent-target-selection**: `wireMatchingEndpoints`
  MUST select as targets only endpoints for which `endpointUnconfigured` is
  `true` and whose `epHost(e.url)` maps to a non-null entry in the index
  built by `indexEndpointWiring`, excluding already-wired, operator-ignored,
  infra-kind, and ambiguous-host endpoints.
- **wire-matching-endpoints-per-target-resilience**: `wireMatchingEndpoints`
  MUST call `api.updateEndpoint` once per target sequentially, MUST record a
  failure for one target in `skipped` without aborting the remaining
  targets, and MUST report `wired` as the count of calls that did not throw.

