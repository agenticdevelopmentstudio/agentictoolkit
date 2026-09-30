<!-- leaf: implement-general-1/deploy-engine--test-vectors · source: deploy-engine.md -->

# Deploy Engine

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
