<!-- leaf: implement-status-server/config--part-3 · source: status-server-config.md -->

# Status Server Config — continued (part 3)

**Rules** (cite as `implement-status-server/config--part-3#<slug>`):

- `seed-environment-enum` MUST
- `seed-endpoint-required-fields` MUST
- `seed-endpoint-optional-fields-default` MUST
- `seed-endpoint-name-uniqueness-precondition` MUST
- `seed-roster-shape` MUST
- `seed-roster-empty-semantics` MUST
- `seed-fan-out-contract` MUST
- `seed-endpoint-url-construction` MUST
- `seed-plain-data` MUST
- `credential-values-opaque` MUST
- `cors-hosts-explicit-list-only` MUST
- `peer-token-empty-disables-peer-path` MUST

### Seed Roster Contract (seed.ts)

- **seed-environment-enum**: `SeedEnvironment` MUST be exactly the union
  `'production' | 'staging' | 'testing'`.
- **seed-endpoint-required-fields**: A `SeedEndpoint` value MUST supply
  `group`, `name`, `baseSlug`, `host`, `envs`, and `kind`; the interface
  declares none of these optional.
- **seed-endpoint-optional-fields-default**: A `SeedEndpoint`'s `path` and
  `expectedStatus` fields MUST be optional (`path?: string`,
  `expectedStatus?: number`); the type itself carries no default value for
  either — the `200` default documented on `expectedStatus` is applied by
  the external seed-route consumer, not by this type.
- **seed-endpoint-name-uniqueness-precondition**: A `SeedEndpoint`'s `name`
  MUST be unique within its `group`, per the field's own doc comment ("The
  site's display name, unique within its group"); this is a documented
  caller precondition these three files declare but do not themselves
  enforce at runtime.
- **seed-roster-shape**: `SeedRoster` MUST be `readonly SeedEndpoint[]`, a
  read-only list, never a mutable array or a keyed map.
- **seed-roster-empty-semantics**: An omitted or empty `SeedRoster` MUST
  correspond to the seed route creating no groups, sites, or endpoints —
  only the provider connections whose credentials are already present —
  per this file's own module doc comment and `app.ts`'s `AppDeps.seed` doc
  comment.
- **seed-fan-out-contract**: Per `SeedEndpoint`'s own doc comment (enforced
  by the external seed-route consumer, `runSeed` in `src/routes/config.ts`),
  one `SeedEndpoint` row MUST fan out into exactly one site-group keyed by
  `group`, one site keyed by the pair `(group, name)` with slug `baseSlug`,
  and one endpoint for every entry in `envs`.
- **seed-endpoint-url-construction**: Each fanned-out endpoint's URL MUST
  be `` https://<env-qualified host><path ?? ''> ``, where the production
  entry in `envs` leaves `host` unqualified and the staging/testing entries
  prefix it `staging.`/`testing.`, per `SeedEndpoint`'s doc comment ("The
  non-production hosts follow the `staging.<host>` / `testing.<host>`
  convention").
- **seed-plain-data**: `SeedEndpoint` and `SeedRoster` MUST hold no
  functions, matching `StatusConfig`'s "plain data, like StatusConfig" doc
  comment, so a host can keep a seed roster in a JSON file.

### Security

This module is where every credential and CORS/MCP origin allowlist the
status backend trusts is named and surfaced — twelve provider tokens by
name (`STATUS_CREDENTIAL_NAMES`), the machine `PEER_TOKEN`, the GitHub OAuth
`clientSecret`, two inbound webhook secrets, and the explicit host lists the
external CORS and MCP middleware consult. It is a security-relevant recipe
per this cookbook's Cookbook Compliance guideline, so the concerns below are
addressed explicitly.

- **credential-values-opaque**: None of `env.ts`, `port.ts`, or `seed.ts`
  MUST decode, parse, or validate the semantic content of a credential
  string; every credential and secret field is a `string | undefined`
  passthrough, meaningful only to the external code that presents it to a
  provider API.
- **cors-hosts-explicit-list-only**: `corsAllowedHosts` and
  `mcpAllowedHosts` MUST be a finite, explicit array of host names; neither
  the `EnvSource` type nor the `list()` helper produces or accepts a
  wildcard sentinel, so a wildcard-CORS decision, if ever made, happens
  entirely in the external middleware that reads this array, not in these
  three files.
- **peer-token-empty-disables-peer-path**: `peerToken` defaulting to `""`
  MUST leave the peer-authenticated read path disabled by construction, per
  `StatusConfig.peerToken`'s own doc comment ("Empty disables peer reads");
  the comparison logic that enforces this lives in `status-server-auth`'s
  `default-adapter.ts`, external to these three files.

Sensitive data in scope: the twelve `STATUS_CREDENTIAL_NAMES` provider
tokens, `PEER_TOKEN`, `github.clientSecret`, `webhooks.vercel`/`.railway`,
and every other environment-variable value reachable through `secrets`.
None of these three files stores, logs, or transmits any of them — they are
read from `env` and handed to the caller by reference. Storage (the host's
own environment/secrets manager, e.g. Railway's env store), transmission
(each credential's own provider-API call, made by code outside this
recipe), and revocation (rotating the underlying provider token) are all
external to `env.ts`, `port.ts`, and `seed.ts`; what these three files
guarantee is that a credential's value is never inspected, mutated, or
duplicated on its way from `env` to `credentials`/`secrets`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `PORT` | env var | `3000` | TCP port the host serves the API on (`StatusConfig.port`). |
| `APP_VERSION` | env var | `'0.0.0'` | Reported in `/health` and the OpenAPI document. |
| `RAILWAY_GIT_COMMIT_SHA` | env var | `null` | Git commit the running build was cut from. |
| `PROBE_INTERVAL_SECONDS` | env var | `60` | Endpoint-probe cadence, seconds. |
| `DEPLOY_SYNC_SECONDS` | env var | `null` (derived: `max(300, probeIntervalSeconds × 5)`) | Explicit override of the deploy-sync cadence; must parse to a positive finite number or is ignored. |
| `CORS_ALLOWED_HOSTS` | env var, comma-separated | `[]` | Origins the external CORS middleware allows (host names, no scheme). |
| `MCP_ALLOWED_HOSTS` | env var, comma-separated | `[]` | Host names the external MCP endpoint accepts (DNS-rebinding guard). |
| `PEER_TOKEN` | env var | `''` | Shared secret a peer monitor presents to read `/snapshot`; empty disables the peer-read path. |
| `MONITOR_LABEL` | env var | `'this monitor'` | Base fleet-board label; environment-qualified unless already production or self-qualified. |
| `RAILWAY_ENVIRONMENT_NAME` | env var | `''` | Consulted only to qualify `monitorLabel`; not itself a `StatusConfig` field. |
| `AUTH_DISABLED` | env var | `false` (`'1'` enables) | Dev/e2e escape hatch; refused at boot when `NODE_ENV=production` (SEC-M5). |
| `COOKIE_INSECURE` | env var | `false` (`'1'` enables, meaning `cookieSecure=false`) | Drops the session cookie's `Secure` flag for local http; refused at boot when `NODE_ENV=production` (SEC-M5). |
| `ADMIN_EMAILS` | env var, comma-separated | `[]` | Emails auto-promoted to admin, lower-cased. |
| `PUBLIC_BASE_URL` | env var | `''` (fallback: `https://${RAILWAY_PUBLIC_DOMAIN}`) | Browser-facing origin for OAuth callbacks; one trailing slash stripped. |
| `RAILWAY_PUBLIC_DOMAIN` | env var | — | Railway-injected fallback for `PUBLIC_BASE_URL`. |
| `GITHUB_OAUTH_CLIENT_ID` / `GITHUB_OAUTH_CLIENT_SECRET` | env var | `''` / `''` | GitHub OAuth app credentials; empty means GitHub login is unconfigured (checked by `status-server-auth`, external). |
| `GITHUB_FETCH_TIMEOUT_MS` | env var | `null` (code default `8000`, applied externally) | Deadline for outbound GitHub API calls; must be a positive finite number or is ignored. |
| `VERCEL_WEBHOOK_SECRET` / `RAILWAY_WEBHOOK_SECRET` | env var | `null` / `null` | Inbound deploy-webhook secrets; `null` when that platform's webhook is not wired. |
| `HEARTBEAT_URL` | env var | `null` | Outbound heartbeat ping URL; `null` disables it. |
| `ALERT_WEBHOOK_URL` | env var | `null` | Outbound alert webhook URL; `null` disables alert posting. |
| `GLITCHTIP_PROJECTS` | env var, comma-separated | `null` (every project the org returns) | Allowlist of GlitchTip project slugs eligible to open a board Problem. |
| `STATUS_CREDENTIAL_NAMES` (12 names, listed under credential-name-list) | env vars, by name | `undefined` per name | Provider credentials looked up by name into `StatusConfig.credentials`. |
| `NODE_ENV` | env var | — | Consulted only by the SEC-M5 guard; not itself a `StatusConfig` field. |
| `seed` | injected `SeedRoster` (`AppDeps.seed`, external to these three files) | `[]` | The host's roster of sites `POST /config/seed` creates. |

## Localization

None of these three files uses a localization mechanism. `envConfig` throws
exactly one user-facing string, always in English, and everything else
these files produce is either numeric/boolean data or a passthrough of a
host-supplied value. Per this recipe's authoring rules, a hardcoded string
is a fact to record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — thrown `Error` message | `refusing to boot: AUTH_DISABLED / COOKIE_INSECURE must not be set when NODE_ENV=production` | `envConfig`'s SEC-M5 guard |

## Privacy

- **Data collected**: the twelve named provider credentials
  (`STATUS_CREDENTIAL_NAMES`), the `PEER_TOKEN` shared secret, the GitHub
  OAuth `clientId`/`clientSecret`, the two inbound webhook secrets, the
  admin-email allowlist, and — through `secrets` — any other
  environment-variable value the host exposes by name.
- **Storage**: none of these three files persists anything; the process
  environment itself (managed by the host's deployment platform, e.g.
  Railway's env store) is the storage, external to `env.ts`, `port.ts`, and
  `seed.ts`.
- **Transmission**: these three files never transmit a credential
  themselves; they hand a value by reference to whichever external caller
  presents it to a provider API (e.g. `github.clientSecret` used server-side
  by `status-server-auth`'s `exchangeCode`).
- **Retention**: no retention logic exists in these three files; a
  credential's lifetime is bounded by the host's own environment/secrets
  manager, not by anything here.

