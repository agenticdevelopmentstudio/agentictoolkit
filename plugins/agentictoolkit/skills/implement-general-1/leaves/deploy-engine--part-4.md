<!-- leaf: implement-general-1/deploy-engine--part-4 · source: deploy-engine.md -->

# Deploy Engine — continued (part 4)

**Rules** (cite as `implement-general-1/deploy-engine--part-4#<slug>`):

- `hostomittedfromdomainlists-suffix-set` MUST — hostOmittedFromDomainLists MUST return true for a host ending in .vercel.app, .workers.dev, or .pages.dev (the three …
- `claimed-by-nothing-requires-configured-platform` MUST
- `claimed-by-nothing-candidate-filter` MUST
- `claimed-by-nothing-fleet-overlap-guard` MUST
- `claimed-by-nothing-wired-authority` MUST
- `claimed-by-nothing-mass-deletion-guard` MUST
- `claimed-by-nothing-unwired-authority` MUST
- `claimed-by-nothing-withheld-is-mandatory-signal` MUST
- `summarize-auto-configure-pluralization` MUST
- `summarize-auto-configure-nothing-vs-no-new-matches` MUST
- `summarize-auto-configure-manual-detail` MUST
- `repo-tail-extraction` MUST
- `prod-domain-of-environment-gate` MUST
- `plan-builder-site-match-order` MUST
- `plan-builder-site-fill-vs-skip` MUST
- `plan-builder-site-new-site-identity` MUST
- `plan-builder-site-no-identity-skip` MUST
- `run-builder-auto-configure-working-snapshot` MUST
- `run-builder-auto-configure-creation-opt-in` MUST
- `cf-worker-scripts-error-shape` MUST
- `cf-worker-scripts-429-cooldown` MUST
- `cf-custom-domains-null-on-any-failure` MUST
- `cf-custom-domains-hostname-lowercased` MUST
- `cf-canonical-host-by-worker` MUST
- `cf-account-resolution-order` MUST
- `cf-account-cache-success-only` MUST
- `cf-account-call-independent-timeouts` MUST
- `compare-monitor-host-order` MUST
- `pick-canonical-host-normalization` MUST

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

