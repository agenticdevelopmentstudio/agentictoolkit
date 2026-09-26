---
id: da6524ff-4def-461c-a885-d385a118e596
title: Deploy Engine
domain: agentictoolkit://cookbook/deploy-platform
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure planners plus injected-I/O runners that match deploy projects to monitored
  sites/endpoints, wire and create them, and retire stale monitors.
platforms:
- typescript
- web
tags:
- deploy
- provisioning
- auto-configure
- vercel
- railway
- cloudflare
- rate-limiting
- reconciliation
depends-on: []
related: []
references:
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts
- packages/web/packages/deploy-platform/src/engine/builder-match.ts
- packages/web/packages/deploy-platform/src/engine/classify.ts
- packages/web/packages/deploy-platform/src/engine/plan.ts
- packages/web/packages/deploy-platform/src/engine/run.ts
- packages/web/packages/deploy-platform/src/providers/cloudflare.ts
- packages/web/packages/deploy-platform/src/providers/host-pick.ts
- packages/web/packages/deploy-platform/src/providers/railway.ts
- packages/web/packages/deploy-platform/src/providers/vercel.ts
- packages/web/packages/deploy-platform/src/util/cached-single-flight.ts
- packages/web/packages/deploy-platform/src/util/map-limit.ts
- packages/web/packages/deploy-platform/src/util/with-timeout.ts
- packages/web/packages/deploy-platform/src/canon/index.ts
approved-by: ''
approved-date: ''
---

# Deploy Engine

## Overview

Deploy Engine is the headless logic that keeps a monitoring board's endpoints
and sites in sync with what actually exists on Vercel, Railway and
Cloudflare. It has no UI of its own; a status app and a builder app both sit
on top of it. Three concerns are split into files that each stay pure where
possible:

- **Canonicalization** (`canon/index.ts`) — the one definition of a platform
  name, a correlation key, a host's environment label, a site's "apex", a
  registrable domain family, and a slug. Every other file in this component
  imports these rather than re-deriving them, so two files can never disagree
  about what host belongs to what site.
- **Classification** (`classify.ts`) — the one "configured or not?" model,
  computed on two axes (endpoints that need wiring, deploy projects that need
  a monitor) so every UI surface that renders a badge or a banner counts the
  same thing.
- **Planning** (`plan.ts`, `builder-match.ts`) — pure functions from
  "one deploy project + current endpoints/sites" to a plan (`AddPlan`,
  `BuilderSitePlan`). No I/O; trivially unit-testable.
- **Running** (`run.ts`, `builder-match.ts`'s `runBuilderAutoConfigure`) —
  injected-I/O orchestration that applies a plan sequentially, sharing one
  `applySequentially` loop between the status-project runner and the
  builder-site runner so their sequencing and skip-collection semantics can
  never drift apart.
- **Provider adapters** (`providers/vercel.ts`, `providers/railway.ts`,
  `providers/cloudflare.ts`, `providers/host-pick.ts`) — the network calls
  each provider's API needs, each returning a `live`/provenance-tagged
  result so a caller can tell "genuinely empty" from "could not read".
- **Cross-thread rate limiting** (`cooldown/provider-cooldown.ts`) — a
  `SharedArrayBuffer`-backed per-provider cooldown registry read
  synchronously on the hot path of every fetch, shared between the worker
  thread that polls and the API thread that enumerates.
- **Shared utilities** (`util/cached-single-flight.ts`, `util/map-limit.ts`,
  `util/with-timeout.ts`) — a TTL + single-flight cache, a bounded-concurrency
  mapper, and an abort-based timeout, each with exactly one implementation
  reused across the component.

## Behavioral Requirements

### Canonicalization (`canon/index.ts`)

- **platform-name-canonicalization**: `platformCanon` MUST map the literal
  string `"cloudflare-pages"` to `"cloudflare"` and MUST return any other
  input string unchanged, and MUST return `""` when given `null` or
  `undefined`.
- **deploy-target-key-shape**: `deployTargetKey` MUST return `null` when
  `platformCanon(platform)` is empty or `project` is falsy, and otherwise
  MUST return the string `${canonicalPlatform}|${project}|${envSegment}`,
  where `envSegment` is `environment` lowercased (or `""` if `environment` is
  null/undefined) when the canonical platform is `"railway"`, and `""` for
  every other platform.
- **deploy-project-key-shape**: `deployProjectKey` MUST return
  `${platformCanon(platform)}|${project}` and MUST NOT incorporate an
  environment segment, so the key identifies a project's existence
  independent of which environment is being matched.
- **env-from-project-name**: `envFromProject` MUST return `"staging"` when
  `projectName` starts with `"staging."` or ends with `"-staging"`, MUST
  return `"testing"` when it starts with `"testing."` or ends with
  `"-testing"`, and MUST return `"production"` for every other input,
  including a project name that carries neither marker.
- **host-env-label**: `hostEnv` MUST strip one leading `www.` label from
  `host` before matching, MUST then match a leading label against
  `staging`, `testing`, `preview`, `prod`, or `production` followed by a
  dot, MUST normalize a `prod`/`production` match and a no-match result to
  `"production"`, MUST normalize a `preview` match to `"staging"`, and MUST
  otherwise return the matched label verbatim (`"staging"` or `"testing"`).
- **site-apex-collapsing**: `siteApex` MUST repeatedly strip a leading
  `www.` label and/or a leading env-marker label (`staging.`, `testing.`,
  `preview.`, `prod.`, `production.`) from `host`, in either order, until no
  further label of either kind can be stripped, and MUST stop stripping
  before the result would have fewer than two dot-separated labels (so
  `"staging.io"` returns `"staging.io"` and `"www.com"` returns `"www.com"`
  unchanged).
- **domain-family-provider-exclusion**: `domainFamily` MUST return `null`
  when `host` (case-folded, with one trailing dot stripped) contains no dot
  at all, and MUST also return `null` when `host` equals or ends with a dot
  followed by any of the fifteen fixed provider suffixes (`vercel.app`,
  `railway.app`, `pages.dev`, `workers.dev`, `netlify.app`, `onrender.com`,
  `fly.dev`, `herokuapp.com`, `github.io`, `web.app`, `firebaseapp.com`,
  `azurestaticapps.net`, `ondigitalocean.app`, `deno.dev`, `surge.sh`).
- **domain-family-registrable-domain**: For a `host` that is not excluded by
  **domain-family-provider-exclusion**, `domainFamily` MUST return the last
  three dot-separated labels when the host's last two labels form one of the
  seven fixed two-part TLDs (`co.uk`, `org.uk`, `ac.uk`, `com.au`, `co.nz`,
  `co.jp`, `com.br`), MUST otherwise return the last two labels, and MUST
  return the whole (lowercased) host unchanged when it has fewer labels than
  that count.
- **project-base-name-stripping**: `projectBaseName` MUST strip a leading
  `staging.` or `testing.` label and MUST strip a trailing `-production`,
  `-staging`, or `-testing` suffix from `projectName` (applying both strips
  in sequence; either, both, or neither may match), and MUST return the
  input unchanged when no marker of either spelling matches — the same two
  spellings `envFromProject` reads.
- **ep-host-normalization**: `epHost` MUST return the URL's `host` (hostname
  plus any port) when `url` parses as a URL, MUST fall back to the raw input
  string when it does not parse, and in both cases MUST lowercase the result
  and MUST strip a trailing `:<port>` suffix.
- **slugify-form**: `slugify` MUST lowercase and trim `s`, MUST collapse every
  run of characters outside `[a-z0-9]` to a single hyphen, and MUST trim any
  leading or trailing hyphen from the result.

### Cross-thread rate limiting (`cooldown/provider-cooldown.ts`)

- **cooldown-shared-buffer**: The cooldown registry MUST store one cooldown
  expiry per entry of the fixed `PROVIDERS` tuple (`vercel`, `railway`,
  `cloudflare`, `crunchy`) in a `BigInt64Array` backed by a
  `SharedArrayBuffer`, and `cooldownState` MUST return that buffer so a
  worker thread can be handed the same registry via `workerData` rather than
  starting an empty one of its own.
- **cooldown-worker-attach**: `attachCooldownState` MUST replace the
  module's live registry with a `BigInt64Array` view over a supplied
  `SharedArrayBuffer` when one is given, and MUST leave the existing
  registry untouched when the argument is `undefined`.
- **cooldown-retry-after-parsing**: `noteRateLimited`'s Retry-After parsing
  MUST treat a header that parses as a positive, finite number of seconds as
  that many milliseconds, MUST otherwise treat a header that parses as an
  HTTP date strictly after `now` as the millisecond delta to that date, and
  MUST treat every other value (absent, non-numeric non-date, a past or
  invalid date, zero or negative seconds) as unusable.
- **cooldown-default-and-cap**: `noteRateLimited` MUST use
  `DEFAULT_COOLDOWN_MS` (60000) as the cooldown length when Retry-After is
  unusable, and in every case MUST clamp the chosen length to at most
  `MAX_COOLDOWN_MS` (900000).
- **cooldown-unknown-provider-degrades**: `noteRateLimited` MUST NOT throw
  when `provider` is not one of the four fixed `PROVIDERS` entries; it MUST
  log via `console.error` and MUST return `now + ms` without writing to the
  shared registry.
- **cooldown-never-shortens**: `noteRateLimited` MUST compare the computed
  expiry against the slot's current value via `Atomics.load` and MUST write
  the new expiry via `Atomics.store` only when it is strictly later than the
  existing one, so a shorter cooldown computed after a longer one (from a
  burst of 429s, or a race with the other thread) never shortens the
  effective cooldown.
- **note-if-rate-limited-gate**: `noteIfRateLimited` MUST return `false`
  and MUST NOT call `noteRateLimited` when `res.status` is not exactly 429,
  and MUST return `true` after recording the cooldown (reading the
  `retry-after` response header) when it is 429.
- **rate-limited-until-lapse-clear**: `rateLimitedUntil` MUST return `null`
  for an unknown provider name, MUST return `null` when the stored expiry is
  `0`, MUST return `null` and MUST clear the slot to `0n` via `Atomics.store`
  when the stored expiry is at or before `now`, and MUST otherwise return
  the stored expiry.
- **cooldown-slot-scoped-by-provider**: Every read and write of the cooldown
  registry MUST be scoped to the single slot `PROVIDERS.indexOf(provider)`
  and MUST NOT read or mutate any other provider's slot.

### Configuration classification (`classify.ts`)

- **non-deploy-kind-set**: `endpointNeedsWiring` MUST return `false` for
  exactly the three kinds in `NON_DEPLOY_KINDS` (`health`, `custom`, `dns`)
  and MUST return `true` for every other kind string.
- **endpoint-config-status-precedence**: `endpointConfigStatus` MUST return
  `"configured"` when `endpointNeedsWiring(e.kind)` is `false`, MUST
  otherwise return `"configured"` when both `e.platform` and
  `e.deployProject` are truthy, MUST otherwise return `"ignored"` when
  `e.ignoreProjectWarning` is `true`, and MUST otherwise return
  `"unconfigured"` — in that precedence order, so a fully wired endpoint
  reads `"configured"` even when `ignoreProjectWarning` is also `true`.
- **endpoint-unconfigured-delegates**: `endpointUnconfigured` MUST return
  exactly `endpointConfigStatus(e) === "unconfigured"` and MUST NOT
  duplicate the classification logic.
- **project-status-precedence**: `projectStatus` MUST return `"monitored"`
  when `p.wired` is `true`, MUST otherwise return `"ignored"` when
  `p.ignored` is `true`, and MUST otherwise return `"unmonitored"`.
- **project-unconfigured-delegates**: `projectUnconfigured` MUST return
  exactly `projectStatus(p) === "unmonitored"`.
- **partition-pending-split**: `partitionPending` MUST place every project
  for which `projectUnconfigured` is `true` into `pending`, MUST further
  place the subset of `pending` with a truthy `domain` into `addable`, and
  MUST set `noDomain` to `pending.length - addable.length`.
- **compute-config-status-independent-axes**: `computeConfigStatus` MUST
  derive `unconfiguredSites` from `endpoints` via `endpointUnconfigured` and
  `unmonitoredProjects`/`addableProjects`/`noDomainProjects` from `projects`
  via `partitionPending`, independently of each other, and MUST set
  `counts.total` to exactly `counts.sites + counts.projects` where
  `counts.sites = unconfiguredSites.length` and
  `counts.projects = unmonitoredProjects.length`.
- **unmonitored-by-platform-keying**: `computeConfigStatus` MUST key
  `unmonitoredByPlatform` by `platformCanon(p.platform)` for each pending
  project `p`, incrementing the count for that canonical key, so a
  `cloudflare-pages` and a `cloudflare` project increment the same entry.

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

### Removal / claim axis (`run.ts`)

- **hostOmittedFromDomainLists-suffix-set**: `hostOmittedFromDomainLists`
  MUST return `true` for a host ending in `.vercel.app`, `.workers.dev`, or
  `.pages.dev` (the three `UNLISTED_PROVIDER_SUFFIXES`), and MUST return
  `false` for every other host, including a `*.up.railway.app` host.
- **claimed-by-nothing-requires-configured-platform**: `endpointsClaimedByNothing`
  MUST return an empty `doomed` list with a single `withheld` entry stating
  no deploy platform is configured when `evidence.configuredPlatforms` is
  empty, and MUST NOT examine any endpoint in that case.
- **claimed-by-nothing-candidate-filter**: `endpointsClaimedByNothing` MUST
  restrict removal candidates to endpoints for which `endpointNeedsWiring`
  is `true`, `e.ignoreProjectWarning` is not `true`, the URL parses to a
  non-empty host, and that host is not excluded by
  **hostOmittedFromDomainLists-suffix-set**.
- **claimed-by-nothing-fleet-overlap-guard**: `endpointsClaimedByNothing`
  MUST return an empty `doomed` list with a `withheld` entry describing a
  credential/scope change, rather than any doomed endpoints, when none of
  the candidate hosts appears (claimed or ambiguous) in the index built from
  `projects`.
- **claimed-by-nothing-wired-authority**: For a wired candidate,
  `endpointsClaimedByNothing` MUST judge it doomed only when its own
  canonical platform is in `evidence.verifiedPlatforms` and
  `deployProjectKey(platform, e.deployProject)` is absent from the live-
  project index built from `projects`; a platform absent from
  `verifiedPlatforms` MUST withhold judgement for every wired candidate on
  that platform rather than mark any of them doomed.
- **claimed-by-nothing-mass-deletion-guard**: `endpointsClaimedByNothing`
  MUST withhold judgement for an entire platform's wired candidates (marking
  none doomed) when every one of that platform's wired candidates would
  otherwise be judged gone, rather than doom all of them.
- **claimed-by-nothing-unwired-authority**: For an unwired candidate,
  `endpointsClaimedByNothing` MUST judge it doomed only when every
  canonical platform in `evidence.configuredPlatforms` also appears in
  `evidence.verifiedDomains`, and its host is absent (not merely ambiguous)
  from the wiring index; any configured platform missing from
  `verifiedDomains` MUST withhold judgement for every unwired candidate.
- **claimed-by-nothing-withheld-is-mandatory-signal**: `endpointsClaimedBynothing`'s
  callers MUST log every entry of the returned `withheld` array, because an
  empty `doomed` from a withheld pass and an empty `doomed` from a healthy
  fleet are opposite facts that the return shape alone does not distinguish
  without also inspecting `withheld`.

### Summarization (`run.ts`)

- **summarize-auto-configure-pluralization**: `summarizeAutoConfigure` MUST
  use the singular noun/verb form (`"its site"`, `"1 project"`) when the
  relevant count is exactly 1 and the plural form otherwise, for `added`,
  `created`, and `wired` independently.
- **summarize-auto-configure-nothing-vs-no-new-matches**: `summarizeAutoConfigure`
  MUST return the fixed sentence
  `"Nothing to match — every monitored site is already wired to its deploy project."`
  when `added`, `created`, and `wired` are all zero and `noDomain + skipped`
  is also zero, and MUST otherwise (still nothing added/created/wired, but
  some leftover) return a `"No new matches — …"` sentence naming the
  leftover count and its `noDomain`/`skipped` breakdown.
- **summarize-auto-configure-manual-detail**: `summarizeAutoConfigure` MUST
  append a parenthetical breaking out `noDomain` and `skipped` counts only
  when at least one of them is nonzero, and MUST omit the parenthetical
  entirely when both are zero.

### Builder site matching (`builder-match.ts`)

- **repo-tail-extraction**: `repoTail` MUST strip a trailing `.git` suffix
  from `gitRepo`, MUST split on `/` or `:`, MUST drop empty segments, and
  MUST return the last remaining segment, falling back to the `.git`-
  stripped string unchanged when no segment remains.
- **prod-domain-of-environment-gate**: `prodDomainOf` MUST return
  `project.domain` when `project.environment` is `null` or the literal
  string `"production"`, and MUST return `null` for any other environment
  value (a staging/testing entry never supplies a site's `prodUrl`).
- **plan-builder-site-match-order**: `planBuilderSite` MUST attempt, in
  order, a match by `rootDirectory === repoDir`, then by
  `epHost("https://" + domain) === epHost(site.prodUrl)`, then by
  `site.slug === slugify(projectBaseName(projectName))`, taking the first
  matching site and ignoring the rest.
- **plan-builder-site-fill-vs-skip**: For a matched site,
  `planBuilderSite` MUST return `"skip"` with reason `"already configured"`
  when the site already has a `prodUrl`, MUST return `"fill-prod-url"` when
  it does not and `prodDomainOf(project)` is non-null, and MUST return
  `"skip"` with reason `"no production domain to fill"` otherwise.
- **plan-builder-site-new-site-identity**: For an unmatched project with at
  least one of `rootDirectory`, `domain`, or `gitRepo` set, `planBuilderSite`
  MUST return a `"new-site"` plan whose `repoDir` is `rootDirectory`, else
  the `repoTail` of `gitRepo`, else `project.projectName`, whose `platform`
  is `platformCanon(project.platform)`, and whose `name`/`slug` are
  `projectBaseName(projectName)` and its `slugify`, respectively.
- **plan-builder-site-no-identity-skip**: `planBuilderSite` MUST return
  `"skip"` with reason `"no identity"` when `rootDirectory`, `domain`, and
  `gitRepo` are all absent.
- **run-builder-auto-configure-working-snapshot**: `runBuilderAutoConfigure`
  MUST carry a mutable `working` copy of `sites` forward through the
  sequential run (via the shared `applySequentially`) so a site created or
  updated for one project entry is visible to a later entry's match.
- **run-builder-auto-configure-creation-opt-in**: `runBuilderAutoConfigure`
  MUST return a `"skipped"` outcome with reason
  `"no group to create the site in"` for a `"new-site"` plan when `opts
  .create` is not supplied, and MUST NOT call `api.createSite` in that case.

### Cloudflare adapter (`providers/cloudflare.ts`)

- **cf-worker-scripts-error-shape**: `listWorkerScripts` MUST return
  `{ scripts: [...] }` on a successful, `success: true` response, and MUST
  otherwise return `{ error, unreachable }` where `unreachable` is `true`
  only when the `fetch` call itself threw (network/timeout/abort) and
  `false` for a non-OK HTTP response or a `success: false` body.
- **cf-worker-scripts-429-cooldown**: `listWorkerScripts` MUST call
  `noteRateLimited("cloudflare", ...)` with the response's `retry-after`
  header when the response status is 429, before returning its error
  result.
- **cf-custom-domains-null-on-any-failure**: `listWorkerCustomDomains` MUST
  return `null` — with no further signal to the caller — for a non-OK HTTP
  response of any status (including 429), a `success: false` body, or a
  thrown error, and MUST log via `console.error` only in the thrown-error
  case.
- **cf-custom-domains-hostname-lowercased**: `listWorkerCustomDomains` MUST
  lowercase every hostname key of the returned map and MUST omit any result
  entry whose `hostname` or `service` is missing or empty.
- **cf-canonical-host-by-worker**: `canonicalHostByWorker` MUST group the
  input host→service map by service (worker), MUST pick one host per worker
  via `pickCanonicalHost`, and MUST omit a worker from the output entirely
  when it has no hosts (which cannot occur for a worker present in the
  input map, since every entry has at least one host).
- **cf-account-resolution-order**: `resolveCfAccountId` MUST return, in
  order of preference, a non-empty trimmed `configuredId`; else a non-empty
  trimmed `CLOUDFLARE_ACCOUNT_ID` environment variable; else a cached
  discovered id for `token`; else, when the token's `/accounts` listing
  succeeds with exactly one account, that account's id (which it also
  caches); else `null`.
- **cf-account-cache-success-only**: `resolveCfAccountId` MUST cache a
  discovered account id in the process-lifetime `discoveredAccountByToken`
  map only on a successful, unambiguous (exactly one account) discovery, and
  MUST re-probe `/accounts` on every call following a `null`, zero-account,
  or multi-account result rather than caching that outcome.
- **cf-account-call-independent-timeouts**: `resolveCfAccountForConn` and
  `withResolvedCfAccount` MUST each create and dispose (via `.done()`) a
  fresh, independent `withTimeout(6_000)` window for the account-resolution
  step and, in `withResolvedCfAccount`, a second fresh 6-second window for
  the subsequent `onAccount` call, so a slow account probe cannot consume
  the downstream call's time budget.

### Host selection (`providers/host-pick.ts`)

- **compare-monitor-host-order**: `compareMonitorHost` MUST order two hosts
  first by ascending label count (`a.split(".").length`), then, for equal
  label counts, by whether the host has a `www.` prefix (unprefixed first),
  then by ascending string length, then alphabetically — in that fixed
  precedence — and MUST be a total order independent of input order.
- **pick-canonical-host-normalization**: `pickCanonicalHost` MUST trim and
  lowercase every candidate, MUST drop blank candidates before comparing,
  MUST return `null` when no non-blank candidate remains, and MUST
  otherwise return the least element under `compareMonitorHost`.

### Railway adapter (`providers/railway.ts`)

- **railway-gql-variables-not-interpolated**: `gqlPost` MUST pass every
  GraphQL variable through the request body's `variables` field and MUST
  NOT string-interpolate a caller-supplied value into the `query` text.
- **railway-gql-429-cooldown**: `gqlPost` MUST call
  `noteRateLimited("railway", ...)` with the response's `retry-after`
  header whenever the response status is 429, regardless of which GraphQL
  operation was being sent, before returning the response to its caller.
- **railway-list-projects-null-vs-empty**: `listRailwayProjects` MUST
  return `null` when the HTTP response is not OK, when the GraphQL response
  carries a non-empty `errors` array, or when the request throws (except
  that it MUST NOT log via `console.error` when the thrown error's
  associated `signal.aborted` is `true`), and MUST return `[]` (not `null`)
  when the request succeeds with zero projects.
- **railway-project-domains-per-environment-split**: `railwayProjectEnvironments`
  MUST group service-instance domains by lowercased environment name,
  MUST include both custom domains and `*.up.railway.app` provider domains
  in each environment's `domains` list (deduplicated and sorted), MUST omit
  an environment whose combined domain list is empty, and MUST pick each
  environment's representative `domain` by preferring a custom domain (via
  `pickCanonicalHost`) over a provider domain.
- **railway-env-rank-ordering**: `railwayProjectEnvironments`'s output MUST
  be sorted by `railwayEnvRank` (production = 0, staging = 1, testing = 2,
  anything else = 3) ascending, with entries of equal rank ordered
  alphabetically by environment name.

### Vercel adapter (`providers/vercel.ts`)

- **vercel-domain-cache-ttl**: `fetchProjectDomainList` MUST reuse a cached
  entry for `projectName` without a network call when the cached entry is
  less than `DOMAIN_CACHE_TTL_MS` (one hour) old, and MUST otherwise issue a
  fresh request.
- **vercel-domain-provenance-shape**: `fetchProjectDomains` MUST return
  `live: true` with the freshly fetched (and newly cached) domain list on a
  successful request, MUST return `live: false` with the STALE cached list
  (or `[]` when there is no prior cache) on a non-OK response or a thrown
  error, and MUST NOT let a stale-but-successful-looking cached list report
  `live: true` after a refresh attempt has failed.
- **vercel-domain-filtering**: `fetchProjectDomainList` MUST include a
  domain in the cached/returned list only when the API marked it `verified`
  and its name does not end in `.vercel.app`.
- **vercel-domain-fetch-self-timeout**: `fetchProjectDomainList` MUST bound
  its own fetch call with a 5-second `AbortSignal.timeout(5_000)`
  independent of any timeout the caller applies.

### Shared utilities

- **cached-single-flight-ttl-reuse**: `cachedSingleFlight`'s returned
  function MUST return the last cached value without calling `build` again
  when called with `fresh` falsy and the cache is younger than `ttlMs`.
- **cached-single-flight-dedup**: `cachedSingleFlight`'s returned function
  MUST route every concurrent call that misses the cache (or passes
  `fresh: true`) into the SAME in-flight `build()` promise while one is
  outstanding, rather than starting a second `build()` call.
- **cached-single-flight-failure-not-cached**: `cachedSingleFlight` MUST
  clear its in-flight reference when `build()` rejects (via `.finally`)
  without writing a `cached` entry, so the next call retries `build` rather
  than replaying the rejection or a stale value.
- **map-limit-order-preserving**: `mapLimit` MUST place each `fn(items[i])`
  result at index `i` of the returned array regardless of the order in
  which the bounded workers complete.
- **map-limit-bounded-concurrency**: `mapLimit` MUST run at most
  `Math.min(limit, items.length)` concurrent invocations of `fn` at any
  time.
- **with-timeout-abort-and-clear**: `withTimeout` MUST return an
  `AbortSignal` that fires after `ms` milliseconds via an internal
  `setTimeout`, and MUST expose a `done()` that clears that timer, for a
  caller to invoke once the operation it is timing completes (whether it
  finished or was aborted).

## Appearance

Not applicable — this is a headless deploy-configuration engine (planners,
an I/O runner, provider adapters, and shared utilities), not a visual
component.

## States

Not applicable — this is a headless deploy-configuration engine, not a
visual component. Its runtime state machines (cooldown-active vs. clear,
cache-fresh vs. stale vs. in-flight, plan kinds) are documented under
Behavioral Requirements.

## Accessibility

Not applicable — this is a headless deploy-configuration engine, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| deploy-engine-001 | platform-name-canonicalization | `platformCanon("cloudflare-pages")` | `"cloudflare"` |
| deploy-engine-002 | site-apex-collapsing | `siteApex("www.staging.example.com")` | `"example.com"` |
| deploy-engine-003 | site-apex-collapsing | `siteApex("staging.io")` | `"staging.io"` (never below two labels) |
| deploy-engine-004 | domain-family-registrable-domain | `domainFamily("a.b.c.example.co.uk")` | `"example.co.uk"` |
| deploy-engine-005 | domain-family-provider-exclusion | `domainFamily("my-app.vercel.app")` | `null` |
| deploy-engine-006 | domain-family-provider-exclusion | `domainFamily("")` / `domainFamily("localhost")` | `null` for both |
| deploy-engine-007 | project-base-name-stripping | `projectBaseName("staging.adh")` | `"adh"` |
| deploy-engine-008 | env-from-project-name | `envFromProject("agenticcookbook")` | `"production"` (no marker present) |
| deploy-engine-009 | host-env-label | `hostEnv("www.staging.example.com")` | `"staging"` (www stripped before env match) |
| deploy-engine-010 | cooldown-never-shortens | Two `noteRateLimited("vercel", …)` calls, the second with a shorter Retry-After than the first's remaining time | The stored expiry stays at the FIRST (longer) value |
| deploy-engine-011 | cooldown-unknown-provider-degrades | `noteRateLimited("crunchy-legacy" as ProviderName, null)` | Returns `now + DEFAULT_COOLDOWN_MS`; no `RangeError`; no slot written |
| deploy-engine-012 | rate-limited-until-lapse-clear | `rateLimitedUntil("vercel")` called after the stored expiry has passed | `null`, and the slot reads `0` on the next call |
| deploy-engine-013 | endpoint-config-status-precedence | `endpointConfigStatus({kind:"frontend", platform:"vercel", deployProject:"p", ignoreProjectWarning:true})` | `"configured"` (wired beats the opt-out) |
| deploy-engine-014 | non-deploy-kind-set | `endpointConfigStatus({kind:"health", platform:null, deployProject:null})` | `"configured"` |
| deploy-engine-015 | compute-config-status-independent-axes | One unconfigured frontend endpoint + one unmonitored vercel project + one infra endpoint + one monitored railway project | `counts = {sites:1, projects:1, total:2}` |
| deploy-engine-016 | exact-host-wiring | Project `docs`/`docs.example.com`, endpoint `s1` monitoring `docs.example.com` with `deployProject:null` | `{kind:"wire-endpoint", endpointId:"s1", ...}` |
| deploy-engine-017 | apex-ownership-add-endpoint | Project domain `marketing.example.com` (apex `example.com`), endpoint `www.example.com` wired to a sibling site | `{kind:"add-endpoint", siteId: <that site>, ...}` |
| deploy-engine-018 | sibling-match-same-platform-and-base | Project `My_App` on host `my-app.other.com`, existing site with `slug:"my-app"`/`name:"My_App"`/`prodUrl:"https://myapp.example.com"` (builder matcher, no apex match) | `{kind:"skip", reason:"already configured"}` |
| deploy-engine-019 | sibling-env-conflict | A sibling site's `production` endpoint already wired to project `x`; new project wants `production` on the same site | `{kind:"env-conflict", endpointId: <x's endpoint>, existingProject:"x"}` |
| deploy-engine-020 | new-site-fallback | Project `mystery` with no domain, no rootDirectory, no gitRepo | `{kind:"skip", reason:"no identity"}` (builder matcher) / project-axis: `new-site` named `mystery` when it has neither |
| deploy-engine-021 | exact-host-conflict-vs-stale-repair | Endpoint wired to `mikefullerton-com`, which `liveProjects` marks retired on a VERIFIED platform | `{kind:"wire-endpoint", replaces:"mikefullerton-com", replacesPlatform: <that project's own platform>}` |
| deploy-engine-022 | stale-wiring-requires-verified-platform | Same endpoint, but its platform was NOT included in `verifiedPlatforms` | `{kind:"conflict", existingProject:"mikefullerton-com"}` (conservative) |
| deploy-engine-023 | apply-sequentially-resilience | Two items where the first's `applyOne` throws `"boom"` | `skipped: [{reason:"boom"}]`; the second item still runs and is recorded independently |
| deploy-engine-024 | execute-add-new-site-rollback | `createSite` succeeds, `createEndpoint` rejects with `"boom"` | `api.deleteSite` called with the new site's id; the run's `skipped` reason is `"boom"`; `created` stays empty |
| deploy-engine-025 | unique-site-identity-order | `uniqueSiteIdentity({name:"***", slug:""}, "", "g1", new Set())` | `{name:"***", slug:""}` unchanged (empty base slug is never numbered) |
| deploy-engine-026 | family-group-immutability | Two projects in one run both belonging to a newly-owned family; the first project's site creation is rolled back | The second project's `groupForNewSite` lookup is unaffected by the rollback (map built once, at run start) |
| deploy-engine-027 | index-endpoint-wiring-ambiguous-is-null | Two different projects both list `shared.com` in `domains` | `indexEndpointWiring(...).get("shared.com")` is `null` |
| deploy-engine-028 | claimed-by-nothing-mass-deletion-guard | A platform with 2 wired monitors, both naming projects absent from a verified enumeration | `doomed` excludes both; `withheld` names that platform and "ALL 2 wired monitors" |
| deploy-engine-029 | claimed-by-nothing-unwired-authority | An unwired monitor whose host no project serves, with `railway` configured but missing from `verifiedDomains` | `doomed` is empty; `withheld` names `railway` and the unjudged unwired count |
| deploy-engine-030 | hostOmittedFromDomainLists-suffix-set | `hostOmittedFromDomainLists("x.up.railway.app")` vs `hostOmittedFromDomainLists("x.workers.dev")` | `false` then `true` |
| deploy-engine-031 | summarize-auto-configure-nothing-vs-no-new-matches | `summarizeAutoConfigure({added:0,wired:0,noDomain:0,skipped:0})` | `"Nothing to match — every monitored site is already wired to its deploy project."` |
| deploy-engine-032 | summarize-auto-configure-pluralization | `summarizeAutoConfigure({added:1,wired:0,noDomain:0,skipped:0})` | `"Matched 1 project to its site."` |
| deploy-engine-033 | plan-builder-site-fill-vs-skip | Project with `rootDirectory:"apps/docs"`, `domain:"docs.example.com"`; site `s1` has matching `repoDir` and `prodUrl:null` | `{kind:"fill-prod-url", siteId:"s1", prodUrl:"https://docs.example.com"}` |
| deploy-engine-034 | prod-domain-of-environment-gate | Project with `environment:"staging"` and `domain:"staging.app.com"`, matched site has `prodUrl:null` | `{kind:"skip", reason:"no production domain to fill"}` (staging must not fill prodUrl) |
| deploy-engine-035 | cf-custom-domains-null-on-any-failure | `listWorkerCustomDomains` receiving an HTTP 429 | Returns `null` (indistinguishable from any other non-OK status; no `console.error`) |
| deploy-engine-036 | cf-account-cache-success-only | `resolveCfAccountId` called twice for a token whose `/accounts` call first returns 2 accounts, then 1 | First call returns `null` and caches nothing; second call re-probes and returns/caches the single account |
| deploy-engine-037 | compare-monitor-host-order | `pickCanonicalHost(["deep.sub.example.com", "www.example.com", "example.com"])` | `"example.com"` (fewest labels, then non-www) |
| deploy-engine-038 | railway-list-projects-null-vs-empty | GraphQL response with `errors: [...]` vs. `data.projects.edges: []` | `null` then `[]` respectively |
| deploy-engine-039 | railway-project-domains-per-environment-split | One service instance in `staging` with only a `*.up.railway.app` domain, none in `production` | Output has a `staging` entry (provider host as `domain`); no `production` entry |
| deploy-engine-040 | railway-env-rank-ordering | Environments named `testing`, `production`, `pr-123` | Ordered `production`, `testing`, `pr-123` |
| deploy-engine-041 | vercel-domain-provenance-shape | Cached list from an hour-old successful read; refresh attempt now returns HTTP 403 | `{domains: <the stale list>, live:false}` — never upgraded back to `live:true` |
| deploy-engine-042 | vercel-domain-filtering | API returns `[{name:"olylo.ai",verified:true},{name:"p.vercel.app",verified:true},{name:"not-yet.olylo.ai",verified:false}]` | Only `"olylo.ai"` is returned |
| deploy-engine-043 | cached-single-flight-dedup | `Promise.all([get(), get()])` on a cold cache | Both resolve to the SAME value; `build` called exactly once |
| deploy-engine-044 | cached-single-flight-failure-not-cached | `build` rejects on the first call, resolves on the second | First call rejects; second call succeeds and its value is now cached |
| deploy-engine-045 | map-limit-order-preserving / map-limit-bounded-concurrency | `mapLimit([a,b,c,d], 2, fn)` where `fn` durations vary | Results in input order `[fnA,fnB,fnC,fnD]`; peak concurrent `fn` calls ≤ 2 |
| deploy-engine-046 | wire-matching-endpoints-idempotent-target-selection | An endpoint already wired, and one flagged `ignoreProjectWarning:true`, both hosts matching a project's domain list | `wired: 0`; neither endpoint is touched |
| deploy-engine-047 | claimed-by-nothing-fleet-overlap-guard | Enumerated projects' domains share zero hosts with any monitored endpoint | `doomed: []`; `withheld` names a credential/scope-change explanation |
| deploy-engine-048 | apex-ownership-excluded-for-domainless | Domain-less project (a Worker) against endpoints whose URLs fail to parse (empty host) | The project does NOT match those endpoints via apex ownership |
| deploy-engine-049 | exact-host-excludes-non-deploy-kinds | A `health` endpoint on the exact host, plus a sibling frontend endpoint on the same site | `add-endpoint` (via step 2/3), never a `wire-endpoint` onto the health probe |
| deploy-engine-050 | cf-canonical-host-by-worker | Host→service map `{a.example.com: "w1", www.example.com: "w1"}` | `canonicalHostByWorker(...)` maps `"w1"` to `"example.com"` if that host is also present, else the fewer-labels/non-www winner among the given hosts |

## Edge Cases

- **Empty/null input**: `platformCanon(null)`/`platformCanon(undefined)`
  return `""`, not a thrown error; `domainFamily("")` and
  `domainFamily("localhost")` (no dot) return `null`; `uniqueSiteIdentity`
  with an empty base slug and no host to fall back on returns the base
  unchanged rather than numbering a nonsense identity like `" (2)"`.
- **Boundary values**: `siteApex` never reduces a host below two
  dot-separated labels (`"staging.io"` stays `"staging.io"`); `mapLimit`'s
  worker count is `Math.min(limit, items.length)`, so a `limit` larger than
  `items.length` degrades to one worker per item, not an over-allocation;
  `noteRateLimited`'s cooldown length is clamped to `MAX_COOLDOWN_MS`
  regardless of how large a Retry-After header demands; `uniqueSiteIdentity`
  tries at most 98 numbered variants (`-2` through `-99`) before giving up
  and returning the unmodified base for the caller's create call to reject.
- **Concurrent access**: The cooldown registry's `SharedArrayBuffer` is read
  and written from two different threads (the worker-thread monitor cycle
  and the API-thread enumeration) using `Atomics.load`/`Atomics.store`
  exclusively — no other access pattern is used anywhere in the module.
  `cachedSingleFlight` funnels every concurrent miss into one in-flight
  `build()` promise. `applySequentially` and `mapLimit` both bound
  concurrency deliberately: the former to exactly 1 (sequencing correctness,
  since later applies read earlier applies' in-memory state), the latter to
  a caller-supplied `limit`.
- **Error states**: A rejected `applyOne` inside `applySequentially` is
  caught and recorded in `skipped`, never fatal to the run. A rejected
  `createEndpoint` after a successful `createSite` triggers a best-effort
  `deleteSite` rollback and always rethrows the original error. Every
  provider adapter (`listWorkerScripts`, `listWorkerCustomDomains`,
  `listRailwayProjects`, `listRailwayProjectDomains`,
  `fetchProjectDomainList`) returns a typed failure/fallback value rather
  than letting a network or parse error propagate to its caller.
- **Offline/unreachable server**: `withTimeout` bounds an outbound call with
  an `AbortController`-driven `AbortSignal`; Cloudflare's account-resolution
  helpers each apply an independent 6-second window per network step so one
  slow call cannot consume a downstream call's budget; Vercel's domain fetch
  applies its own 5-second `AbortSignal.timeout`. A 429 response from any of
  the three providers is recorded via the shared cooldown registry so a
  polling caller backs off rather than immediately re-hitting an already
  rate-limited provider.
- **Vercel domain cache scope**: `domainListCache` in `providers/vercel.ts`
  is keyed only by `projectName`, not by `(teamId, projectName)`, so two
  Vercel teams sharing a project name, or one account switching `teamId` for
  the same project, read and overwrite each other's cached domain list for
  up to the one-hour TTL.
- **map-limit-non-positive-limit**: NEEDS REVIEW: Not implemented in source. `mapLimit` sizes its worker pool as `Math.min(limit, items.length)` with no check that `limit >= 1`; a `limit <= 0` yields zero workers, so every result stays `undefined` with no item processed and no error, and `map-limit.test.ts` has no case for it — whether a non-positive `limit` should throw, clamp to 1, or stay the caller's responsibility is undecided.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DEFAULT_COOLDOWN_MS` | `number` (module constant) | `60_000` | Cooldown length applied when a 429's Retry-After header is absent or unusable. |
| `MAX_COOLDOWN_MS` | `number` (module constant) | `900_000` | Upper clamp on any computed cooldown, including one derived from a Retry-After header. |
| `DOMAIN_CACHE_TTL_MS` | `number` (module constant, `vercel.ts`) | `3_600_000` (1 hour) | How long a Vercel project's fetched domain list is reused before a refresh is attempted. |
| `UNLISTED_PROVIDER_SUFFIXES` | `readonly string[]` (module constant, `run.ts`) | `[".vercel.app", ".workers.dev", ".pages.dev"]` | Provider-default host suffixes a removal pass must never judge absent-as-deleted. |
| `PLACEHOLDER_URL` | `string` (module constant, `plan.ts`) | `"https://"` | URL stamped on a new endpoint for a domain-less (e.g. Worker) project, pending operator fill-in. |
| `CLOUDFLARE_ACCOUNT_ID` | environment variable | none | Deploy-time fallback account id consulted by `resolveCfAccountId` when no per-connection account id is configured. |
| `conn.token` / `conn.accountId` | caller-supplied (`CfConn`) | none | Per-connection Cloudflare credential and optional configured account id. |
| `opts.create` (`CreateOpts` / `{ groupId }`) | caller-supplied | absent (match-only) | Opts a project-axis or builder-axis run into ALSO creating new sites/endpoints, and names the group new sites are filed under. |
| `opts.create.forceGroup` | `boolean` | `false` | Makes `groupId` authoritative, bypassing the domain-family group-inference rule. |
| `opts.liveProjects` (`LiveProjectIndex`) | caller-supplied | absent | This run's enumerated-project index, enabling stale-wiring repair; absent means every existing wiring is treated as live. |
| `limit` (`mapLimit`) | caller-supplied `number` | none (required) | Maximum concurrent `fn` invocations. |
| `ttlMs` (`cachedSingleFlight`) | caller-supplied `number` | none (required) | Cache lifetime in milliseconds for the wrapped `build` function. |
| `ms` (`withTimeout`) | caller-supplied `number` | none (required) | Milliseconds until the returned `AbortSignal` fires. |

## Deep Linking

Not applicable: none of the given sources construct or consume an
application deep link or universal link; every URL these files build
(`https://${domain}`, the Cloudflare/Railway/Vercel API endpoints) is either
a monitored target's own host or an upstream provider API, not a link into
this application.

## Localization

Not applicable: this component's only user-facing strings are the operator-
facing skip/conflict/note reasons and the summary sentences returned by
`summarizeAutoConfigure` and `manualDetail` (e.g. `"that domain is already
wired to ${x}"`, `"Matched 1 project to its site."`) — these are hardcoded
English string literals with no localization mechanism in any of the given
sources; a port MUST decide whether/how to localize them, since the source
itself never does.

## Accessibility Options

Not applicable — this is a headless deploy-configuration engine with no
rendered UI to which Reduce Motion, Increase Contrast, or Differentiate
Without Color could apply.

## Feature Flags

Not applicable: none of the given sources reads a feature-flag key; the only
runtime toggles are the plain function parameters documented under
Configuration (`opts.create`, `opts.create.forceGroup`, `opts.liveProjects`).

## Analytics

Not applicable: none of the given sources emits an analytics event; the
`console.error` calls documented under Logging are diagnostic output, not
an analytics pipeline.

## Privacy

- **Data collected**: Vercel, Railway, and Cloudflare API tokens (`token` /
  `conn.token` parameters) and, for Cloudflare, an account id. These are
  credentials supplied by the caller, not collected from an end user; no
  other personal data passes through any given source.
- **Storage**: No given source persists a token to disk or a database. One
  exception is process-lifetime, in-memory: Cloudflare's
  `discoveredAccountByToken` (in `providers/cloudflare.ts`) is a `Map` keyed
  by the raw token string, holding it for the life of the process once a
  successful single-account discovery has occurred (see the Design
  Decisions entry below); it is never written to persistent storage and is
  cleared only by `_resetCfAccountCache` (a test hook) or process exit.
- **Transmission**: Every provider call sends the token as an
  `Authorization: Bearer <token>` header over the provider's HTTPS endpoint
  (`api.cloudflare.com`, `backboard.railway.app`, `api.vercel.com`); no
  given source constructs a non-HTTPS URL or places a token in a query
  string or request body.
- **Retention**: No given source implements token revocation, rotation, or
  an expiry check; a token is used until the caller stops supplying it or
  the provider itself rejects it. This is an absent feature, not a marker —
  see Edge Cases and the `secure-storage`/`token-lifecycle` rows under
  Compliance.

## Logging

Subsystem: process `console` | Category: deploy-platform

| Event | Level | Message |
|-------|-------|---------|
| Unknown provider name passed to the cooldown registry | error | `` [cooldown] unknown provider "<provider>" — cooldown not recorded `` |
| A 429 recorded against a known provider | error | `` [cooldown] <provider> rate-limited — backing off <N>s `` |
| Cloudflare `/accounts` discovery threw | error | `Cloudflare /accounts discovery failed: <message>` |
| Cloudflare `workers/domains` listing threw | error | `Cloudflare workers/domains listing failed: <message>` |
| Railway project listing failed (not an aborted caller timeout) | error | `Railway project listing failed: <message>` |
| Railway project-domains fetch failed (not an aborted caller timeout) | error | `Railway project <projectId> domains failed: <message>` |

`listWorkerScripts`, `listWorkerCustomDomains`'s non-OK-but-not-thrown path,
and `fetchProjectDomainList`'s non-OK/thrown path deliberately log nothing —
each returns a typed result the caller is expected to act on instead (see
Edge Cases, including its two open questions).

## Platform Notes

- **SwiftUI**: A port keeps the planners (`plan.ts`, `builder-match.ts`) as
  pure, synchronous Swift functions over `struct`/`enum` value types (the
  `AddPlan`/`BuilderSitePlan` unions map directly to Swift `enum`s with
  associated values); the cross-thread cooldown registry maps to an `actor`
  or a `Sendable` type wrapping `os_unfair_lock`/`ManagedAtomic` rather than
  `SharedArrayBuffer` + `Atomics`, since Swift has no JS-style shared-buffer
  primitive across threads in one process.
- **Compose**: Mirrors SwiftUI's structural mapping — pure Kotlin `data
  class`/`sealed interface` planners, coroutines for the injected-I/O
  runner, and `kotlinx.atomicfu` or a `Mutex`-guarded `IntArray` in place of
  the `SharedArrayBuffer` registry for cross-thread/cross-coroutine cooldown
  state.
- **React/Web**: This is the source platform; no translation is needed. A
  browser-hosted port (as opposed to this Node-hosted one) would need a
  substitute for `SharedArrayBuffer` cross-THREAD sharing (a `Worker` plus
  `postMessage`, since browser `SharedArrayBuffer` requires cross-origin
  isolation headers this component's server context does not need).
- **AppKit/UIKit**: Same mapping as SwiftUI's controller-level equivalents;
  `URLSession` with `URLSessionConfiguration.timeoutIntervalForRequest`
  provides the `withTimeout`/`AbortSignal.timeout` equivalent, and
  `NSCache` (with an explicit last-write timestamp, since `NSCache` has no
  built-in TTL) can back the single-flight cache's storage half provided a
  separate in-flight-promise/continuation dictionary still de-duplicates
  concurrent misses.
- **WinUI 3**: `HttpClient` (with a per-call `CancellationTokenSource`
  driving a timeout, replacing `AbortSignal`/`withTimeout`) issues the
  provider requests; `System.Text.Json` replaces the `JSON.parse`/`res
  .json()` calls throughout the provider adapters; no file lives under
  `Windows.Storage` since no given source persists anything to disk;
  `Task`/`async`-`await` replaces the `Promise`-based `applySequentially`/
  `mapLimit` orchestration, with `System.Threading.Channels` or a plain
  `SemaphoreSlim` bounding `mapLimit`'s concurrency; the cross-thread
  cooldown registry maps to a shared `long[]` (or a small
  `MemoryMappedFile`) mutated only through `Interlocked.Exchange`/
  `Interlocked.CompareExchange`, the .NET equivalent of the source's
  `Atomics.store`/`Atomics.load` discipline; a port has no
  `ObservableCollection`/`INotifyPropertyChanged` counterpart to add here,
  since none of the given sources expose an observable collection — every
  result is a plain returned value or array.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/deploy-platform/src/` |

## Design Decisions

### SharedArrayBuffer for cross-thread cooldown state

**Decision**: The provider-cooldown registry stores its four provider slots
in a `BigInt64Array` backed by a `SharedArrayBuffer`, mutated only through
`Atomics.load`/`Atomics.store`, and hands that same buffer to a worker
thread via `cooldownState()`/`attachCooldownState()` rather than each thread
keeping its own registry.

**Rationale**: The monitor cycle runs on a worker thread while
`/deploy-projects` and `/integrations` enumerate on the API thread, and both
hit the same provider token; a per-thread registry left a 429 seen by one
thread invisible to the other, so the other kept hammering an
already-throttled account — the exact failure this module exists to
prevent. The reads sit on the fetchers' hot path, so they must stay
synchronous (no DB round trip), which a `SharedArrayBuffer` read satisfies
and an IPC-based alternative would not.

**Approved**: pending

### null vs. empty-array/false as provenance, not just a value

**Decision**: `listRailwayProjects` returns `null` (couldn't enumerate) as
distinct from `[]` (enumerated, genuinely empty); `fetchProjectDomains` and
`fetchProjectDomainList` return a `{ domains, live }` shape rather than a
bare array so a failed refresh is distinguishable from a genuinely
domain-less project; `EndpointLite.ignoreProjectWarning` is a REQUIRED
boolean (unlike `EndpointLike`'s optional field) precisely so an adapter
must name `false` explicitly rather than omit the field and have omission
silently misread as "not opted out."

**Rationale**: A caller that deletes a monitor for being unclaimed, or
treats an empty enumeration as "nothing exists," cannot make that decision
safely if "couldn't read" and "read, and there's nothing" produce the same
value. Each of these three shapes exists because a real regression shipped
from collapsing the distinction (documented in each file's own comments).

**Approved**: pending

### Creation is opt-in; matching is not

**Decision**: `runAutoConfigure` and `runBuilderAutoConfigure` both wire an
existing site/endpoint to a project unconditionally, but create a new
site/endpoint only when the caller supplies `opts.create` (a target group).

**Rationale**: The per-platform "Match" / "Match all" UI actions must never
graft a phantom site; only the global "Auto Configure" review flow, after
an operator has pruned the projects they don't want, passes `create`. Making
creation a separate, explicitly-supplied capability rather than a flag
on the same call keeps a match-only caller structurally incapable of
creating anything.

**Approved**: pending

### Stale-wiring repair is gated on a verified, per-platform live-project index

**Decision**: `planAddProject` re-points an endpoint's wiring away from a
project name only when the caller supplies a `LiveProjectIndex` whose
`platforms` set includes that endpoint's own canonical platform; absent
that verification, a name the platform "doesn't have" is treated as still
live and the endpoint is left alone (or reported as a `conflict`).

**Rationale**: Absence of a name from an enumeration is evidence only when
that enumeration is known to be a complete, authenticated read. A platform
whose listing failed, or that degraded to a configured fallback list, is
missing names that are perfectly alive; treating those as retired would
re-point live monitors onto whatever project happens to be added next — the
single most destructive failure mode this feature could have.

**Approved**: pending

### One `applySequentially` definition shared by both runners

**Decision**: `runAutoConfigure` (project axis) and `runBuilderAutoConfigure`
(builder axis) both call the same exported `applySequentially` from
`run.ts` rather than each implementing their own sequential-apply loop.

**Rationale**: Both runs need identical sequencing (strictly one item at a
time, because each apply may mutate shared working state a later apply must
see) and identical resilience (one item's failure recorded in `skipped`,
never fatal). Two independent implementations of that loop could drift —
one becoming parallel, or one dropping the try/catch — without any test
catching the divergence, since they are exercised by different test files.

**Approved**: pending

### `familyGroup` is immutable for the life of one run

**Decision**: `Working.familyGroup`, built once by `indexFamilyGroups` at
the start of `runAutoConfigure`, is never updated as sites are created or
rolled back during that same run; the next run rebuilds it from scratch.

**Rationale**: A site created mid-run is filed either with its domain
family's existing owning group or, for an unowned/split family, with the
operator's fallback group — and the map, as built at the run's start,
already answers both of those questions the same way a mid-run update
would. Maintaining it live would add mutation-ordering complexity (in
particular around the create/rollback path) for an answer that provably
cannot change within the run.

**Approved**: pending

### Requirement count reflects twelve bundled source files of pure logic

**Decision**: This ingredient recipe carries a substantially larger
Behavioral Requirements list than a typical UI ingredient.

**Rationale**: `deploy-engine` is not one class or view; it is twelve
source files — a canonicalization module, a cross-thread rate limiter, a
classification model, two pure planners, an I/O runner shared by two
callers, three provider adapters, a host-picker, and three single-purpose
utilities — each with its own public contract. Splitting this into several
smaller recipes would break the "one recipe, one component" convention the
brief assigns (`deploy-engine` is the named component), and would scatter
cross-file invariants (e.g. the sibling-matching key that both `plan.ts`
and `builder-match.ts` must agree on) across files that could then drift
independently.

**Approved**: pending

## Compliance

| Check | Status | Notes |
|---|---|---|
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | passed | Every provider call in `cloudflare.ts`/`railway.ts`/`vercel.ts` targets a fixed `https://` API host and sends the token only as an `Authorization: Bearer` header; no given source constructs an `http://` URL or places a token in a query string. |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | No given source writes a token to disk or a database, but Cloudflare's `discoveredAccountByToken` (`providers/cloudflare.ts`) retains the raw token string as a `Map` key for the life of the process — see Privacy. |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | failed | No given source implements token revocation, rotation, or expiry checking; a token is used until the caller stops supplying it or the provider rejects it (see Privacy: Retention). |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | The engine reads only what each plan/match needs (project name, domain, environment); the one deliberate exception is the Cloudflare account-token cache retaining the token itself indefinitely rather than a shorter-lived reference. |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Every provider adapter (`listWorkerScripts`, `listWorkerCustomDomains`, `listRailwayProjects`, `listRailwayProjectDomains`, `fetchProjectDomainList`, `resolveCfAccountId`) returns a typed failure/fallback result rather than throwing past its own boundary. |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | `noteRateLimited` never shortens an existing cooldown under a race; `executeAdd`'s new-site path rolls back an orphaned site when its endpoint create fails; `endpointsClaimedByNothing` withholds judgement rather than guessing across seven distinct evidence gaps. |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | `executeAdd`'s best-effort `deleteSite` rollback rethrows the original error either way, but a rollback whose `deleteSite` itself fails leaves an orphaned, endpoint-less site (with its slug key deliberately retained in `takenSlugs` in that case) for the operator to find — there is no automated retry of the rollback itself. |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | `wireMatchingEndpoints` re-running over an already-wired fleet wires nothing further (`endpointUnconfigured` excludes it); `endpointConfigStatus`/`projectStatus` are pure functions of current state, safely recomputed on every call. |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | partial | `withTimeout`, Cloudflare's per-step 6-second windows, and Vercel's 5-second `AbortSignal.timeout` bound most outbound calls; `gqlPost` (Railway) issues its `fetch` with no timeout at all, relying entirely on whatever signal, if any, its own caller supplies. |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | No given source retries a failed request; the cooldown registry backs a caller OFF a rate-limited provider but never itself retries — retrying is left entirely to whichever polling loop calls these adapters. |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Every provider adapter distinguishes a non-OK HTTP response, an API-level `success:false`/`errors` body, and a thrown network error, and returns a distinct, typed outcome for each. |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | `plan.ts` and `builder-match.ts`'s planners are pure functions with no I/O; every network call is isolated to `run.ts`'s `executeAdd`/`applySequentially` callers and the `providers/*` adapters. |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | `applySequentially` and `wireMatchingEndpoints` both catch and record a per-item failure explicitly rather than letting one item's rejection abort the run. |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Every given source but `host-pick.ts` and the three utilities has a sibling `*.test.ts` with concrete assertions (`plan.test.ts`, `run.test.ts`, `classify.test.ts`, `builder-match.test.ts`, `claimed-by-nothing.test.ts`, `vercel-domains.test.ts`, `canon.test.ts`, `map-limit.test.ts`, `cached-single-flight.test.ts`); no test exercises `mapLimit` with `limit <= 0` — see the open question on map-limit-non-positive-limit. |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Every operator-facing reason/note/summary string (`"that domain is already wired to…"`, `summarizeAutoConfigure`'s sentences, the cooldown/Cloudflare/Railway `console.error` messages) is a hardcoded English literal with no localization mechanism anywhere in the given sources. |


## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation, documenting the deploy-platform engine's canonicalization, cross-thread rate-limit cooldown, configuration-status classification, add/builder planners, the shared sequential-apply runner, the removal/claim axis, and the Vercel/Railway/Cloudflare provider adapters plus their shared utilities. Records the open question over the Vercel domain cache's team-scoping and the unvalidated `mapLimit` concurrency limit. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
