<!-- leaf: implement-general-1/deploy-engine--part-2 · source: deploy-engine.md -->

# Deploy Engine — continued (part 2)

**Rules** (cite as `implement-general-1/deploy-engine--part-2#<slug>`):

- `platform-name-canonicalization` MUST
- `deploy-target-key-shape` MUST
- `deploy-project-key-shape` MUST
- `env-from-project-name` MUST
- `host-env-label` MUST
- `site-apex-collapsing` MUST
- `domain-family-provider-exclusion` MUST
- `domain-family-registrable-domain` MUST
- `project-base-name-stripping` MUST
- `ep-host-normalization` MUST
- `slugify-form` MUST
- `cooldown-shared-buffer` MUST
- `cooldown-worker-attach` MUST
- `cooldown-retry-after-parsing` MUST
- `cooldown-default-and-cap` MUST
- `cooldown-unknown-provider-degrades` MUST
- `cooldown-never-shortens` MUST
- `note-if-rate-limited-gate` MUST
- `rate-limited-until-lapse-clear` MUST
- `cooldown-slot-scoped-by-provider` MUST
- `non-deploy-kind-set` MUST
- `endpoint-config-status-precedence` MUST
- `endpoint-unconfigured-delegates` MUST
- `project-status-precedence` MUST
- `project-unconfigured-delegates` MUST
- `partition-pending-split` MUST
- `compute-config-status-independent-axes` MUST
- `unmonitored-by-platform-keying` MUST

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

