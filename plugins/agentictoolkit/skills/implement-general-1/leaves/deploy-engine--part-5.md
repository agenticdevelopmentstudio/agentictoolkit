<!-- leaf: implement-general-1/deploy-engine--part-5 · source: deploy-engine.md -->

# Deploy Engine — continued (part 5)

**Rules** (cite as `implement-general-1/deploy-engine--part-5#<slug>`):

- `railway-gql-variables-not-interpolated` MUST
- `railway-gql-429-cooldown` MUST
- `railway-list-projects-null-vs-empty` MUST
- `railway-project-domains-per-environment-split` MUST
- `railway-env-rank-ordering` MUST
- `vercel-domain-cache-ttl` MUST
- `vercel-domain-provenance-shape` MUST
- `vercel-domain-filtering` MUST
- `vercel-domain-fetch-self-timeout` MUST
- `cached-single-flight-ttl-reuse` MUST
- `cached-single-flight-dedup` MUST
- `cached-single-flight-failure-not-cached` MUST
- `map-limit-order-preserving` MUST
- `map-limit-bounded-concurrency` MUST
- `with-timeout-abort-and-clear` MUST

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

