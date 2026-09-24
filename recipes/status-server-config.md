---
id: 31fe479f-e95e-4f03-b957-faa2314a03be
title: Status Server Config
domain: agentictoolkit://recipes/status-server-config
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status backend's configuration contract (StatusConfig), its envConfig
  environment adapter, and the seed-roster port consumed by POST /config/seed.
platforms:
- typescript
- web
tags:
- configuration
- server
- security
- secrets
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
- agenticdevelopercookbook://guidelines/implementing/security/secure-storage
- agenticdevelopercookbook://guidelines/implementing/security/cors
related:
- agentictoolkit://recipes/status-server-auth
references:
- packages/web/packages/status-server/src/config/env.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/seed.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/index.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/config.ts (agentictoolkit)
- packages/web/packages/status-server/test/config-env.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/config-cadence.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/config-clone.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/config.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Config

## Overview

This is the status backend's configuration layer: three files under
`src/config/` (barreled through `index.ts`) that together define what the
rest of the package is allowed to know about the host it runs in.
`port.ts` is the configuration port: the `StatusConfig` interface every
other module reads, the `STATUS_CREDENTIAL_NAMES` registry of provider
credentials looked up by name, and three small pure functions derived from
a `StatusConfig` (`deploySyncIntervalMs`, `glitchtipConfigured`,
`posthogConfigured`). `env.ts` is `envConfig`, the one shipped adapter that
builds a `StatusConfig` from `process.env`-shaped input using the variable
names the host's `.env.example` documents; nothing else in this package
reads the environment directly. `seed.ts` is the seed-roster port: the
types (`SeedEnvironment`, `SeedEndpoint`, `SeedRoster`) describing the
host-supplied list of sites `POST /config/seed` turns into groups, sites,
and endpoints.

Both `StatusConfig` and `SeedRoster` are plain data by design — no method,
because a `StatusConfig` crosses into the monitor worker via
`worker_threads`' `workerData` (`MonitorWorkerData`, in
`src/monitor/worker-client.ts`, external to these three files), and
`structuredClone` drops any function it meets. The actual fan-out from a
`SeedRoster` into database rows (`runSeed` in `src/routes/config.ts`), the
consumers of `StatusConfig.credentials`/`secrets` (the provider auto-seed in
that same route, `glitchtipConfigured`/`posthogConfigured`'s callers in
`src/board/facts.ts` and `src/telemetry/server.ts`, and
`config.authDisabled`/`cookieSecure`/`peerToken`/`github` in
`status-server-auth`'s five files), and the credential-name self-check in
`src/monitor/integrations.ts` are all external to `env.ts`, `port.ts`, and
`seed.ts`; this recipe cites them only where the contract of these three
files depends on them, and specifies their internals nowhere.

## Behavioral Requirements

### Configuration Contract (port.ts)

- **credential-name-list**: `STATUS_CREDENTIAL_NAMES` MUST be exactly the
  twelve literal names `VERCEL_API_TOKEN`, `VERCEL_TEAM_ID`,
  `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `RAILWAY_API_TOKEN`,
  `CRUNCHY_API_TOKEN`, `GLITCHTIP_URL`, `GLITCHTIP_API_TOKEN`,
  `GLITCHTIP_ORG`, `POSTHOG_HOST`, `POSTHOG_API_KEY`, `POSTHOG_PROJECT_ID`,
  in that order, per the `as const` array; `StatusCredentialName` MUST be
  exactly the union of those twelve literals.
- **credential-record-completeness**: `StatusConfig.credentials` MUST carry
  one entry for every name in `STATUS_CREDENTIAL_NAMES`, each either a
  `string` or `undefined`; it MUST NOT omit an unset name from the record's
  keys.
- **config-fields-are-plain-data**: Every field a `StatusConfig` exposes
  MUST be data (a primitive, an array, or a nested plain object), never a
  function, per the interface's own doc comment ("a method does not survive
  it").
- **config-survives-structured-clone**: A `StatusConfig` MUST retain every
  key and an equal `credentials` record after `structuredClone`, since the
  host hands the same object to the monitor worker as `workerData`.
- **secrets-field-identity**: `StatusConfig.secrets` MUST be capable of
  resolving any environment-variable name the host passes it, not only the
  twelve in `STATUS_CREDENTIAL_NAMES`, because a `deploy_integrations` row
  stores the name of its own token in `tokenEnvVar` and that name is
  resolved through `secrets`, external to these three files.
- **deploy-sync-interval-floor**: `deploySyncIntervalMs(config, probeIntervalMs)`
  MUST return `Math.max(300_000, probeIntervalMs * 5)` when
  `config.deploySyncSeconds` is `null`.
- **deploy-sync-interval-override**: `deploySyncIntervalMs` MUST return
  `config.deploySyncSeconds * 1000` when `config.deploySyncSeconds` is not
  `null` and satisfies `Number.isFinite(n) && n > 0`.
- **glitchtip-all-or-nothing**: `glitchtipConfigured(config)` MUST return
  `true` only when `config.credentials.GLITCHTIP_URL`,
  `GLITCHTIP_API_TOKEN`, and `GLITCHTIP_ORG` are all truthy; two of three
  present MUST resolve `false`, per the function's own doc comment ("All
  three or nothing").
- **posthog-all-or-nothing**: `posthogConfigured(config)` MUST return `true`
  only when `config.credentials.POSTHOG_HOST`, `POSTHOG_API_KEY`, and
  `POSTHOG_PROJECT_ID` are all truthy, following the identical shape.

### Environment Adapter (env.ts)

- **production-escape-hatch-guard**: `envConfig(env)` MUST throw an `Error`
  whose message contains `AUTH_DISABLED / COOKIE_INSECURE` when
  `env.NODE_ENV === "production"` and either `env.AUTH_DISABLED === "1"` or
  `env.COOKIE_INSECURE === "1"`, before constructing any `StatusConfig`
  field (SEC-M5).
- **production-escape-hatch-scoped-outside-production**: `envConfig(env)`
  MUST NOT throw for the same `AUTH_DISABLED`/`COOKIE_INSECURE` values when
  `env.NODE_ENV` is not exactly the literal string `"production"`.
- **port-default**: `port` MUST be `3000` when `env.PORT` is unset.
- **app-version-default**: `appVersion` MUST be the literal string
  `"0.0.0"` when `env.APP_VERSION` is unset.
- **git-commit-sha-optional**: `gitCommitSha` MUST be `null` when
  `env.RAILWAY_GIT_COMMIT_SHA` is unset or empty, else the raw string value.
- **probe-interval-default**: `probeIntervalSeconds` MUST be `60` when
  `env.PROBE_INTERVAL_SECONDS` is unset.
- **numeric-env-coercion**: `port` and `probeIntervalSeconds` MUST be
  computed as `Number(env.X ?? default)` with no further check, so any
  numeric string (including `"0"` or a negative value) passes through as
  its `Number()` result and a non-numeric string produces `NaN`; this MUST
  NOT be confused with `deploySyncSeconds` and `github.fetchTimeoutMs`,
  which instead require `Number.isFinite(n) && n > 0` via `positiveNumber`.
- **numeric-env-validation**: NEEDS REVIEW: Not implemented in source. `port` and `probeIntervalSeconds` accept a `NaN` or non-positive `Number(...)` result with no fallback, no thrown error, and no distinguishable signal, unlike `deploySyncSeconds`/`github.fetchTimeoutMs`'s `positiveNumber` guard; whether these two getters should validate the same way, or validation belongs to `envConfig`'s callers (the HTTP listen call, the probe scheduler), needs the team that owns those callers to decide.
- **deploy-sync-seconds-validated**: `deploySyncSeconds` MUST be `null`
  unless `env.DEPLOY_SYNC_SECONDS` parses via `Number()` to a value
  satisfying `Number.isFinite(n) && n > 0`; a blank, zero, negative, or
  non-numeric value MUST resolve `null`, not throw and not clamp.
- **cors-allowed-hosts-parsing**: `corsAllowedHosts` MUST be the
  comma-split, individually trimmed, non-empty entries of
  `env.CORS_ALLOWED_HOSTS`, and `[]` when it is unset.
- **mcp-allowed-hosts-parsing**: `mcpAllowedHosts` MUST follow the identical
  comma-split/trim/non-empty shape over `env.MCP_ALLOWED_HOSTS`.
- **peer-token-default-empty**: `peerToken` MUST be the empty string `""`
  when `env.PEER_TOKEN` is unset.
- **monitor-label-default**: `monitorLabel` MUST resolve its base label to
  the literal string `"this monitor"` when `env.MONITOR_LABEL` is unset or
  blank, before any environment qualification is applied.
- **monitor-label-production-unqualified**: `monitorLabel` MUST NOT append
  an environment suffix when `env.RAILWAY_ENVIRONMENT_NAME` is unset or is
  exactly `"production"` (case-insensitive after trimming).
- **monitor-label-qualified-non-production**: `monitorLabel` MUST append
  `` (<env>) `` (lower-cased, trimmed) to the base label when
  `env.RAILWAY_ENVIRONMENT_NAME` is set to any other non-empty value.
- **monitor-label-no-double-qualification**: `monitorLabel` MUST NOT append
  the suffix when the base label already contains the lower-cased
  environment name as a substring.
- **auth-disabled-flag**: `authDisabled` MUST be `true` if and only if
  `env.AUTH_DISABLED` is exactly the string `"1"`.
- **cookie-secure-flag**: `cookieSecure` MUST be `true` unless
  `env.COOKIE_INSECURE` is exactly the string `"1"`, in which case it MUST
  be `false`.
- **admin-emails-lowercased**: `adminEmails` MUST be the comma-split,
  trimmed, lower-cased, non-empty entries of `env.ADMIN_EMAILS`.
- **public-base-url-fallback**: `publicBaseUrl` MUST prefer
  `env.PUBLIC_BASE_URL` when it is truthy, else derive
  `` https://${env.RAILWAY_PUBLIC_DOMAIN} `` when that is set, else resolve
  the empty string.
- **public-base-url-trailing-slash-strip**: `publicBaseUrl` MUST strip
  exactly one trailing `/` via `raw.replace(/\/$/, "")`; a value ending in
  two or more slashes MUST retain every slash but the last one, since the
  pattern is not global and matches at most once.
- **github-config-shape**: `github.clientId` and `github.clientSecret` MUST
  each default to the empty string when their respective
  `GITHUB_OAUTH_CLIENT_ID`/`GITHUB_OAUTH_CLIENT_SECRET` env vars are unset;
  `github.fetchTimeoutMs` MUST be `null` unless
  `env.GITHUB_FETCH_TIMEOUT_MS` parses via `positiveNumber` to a finite
  value greater than zero.
- **webhook-secrets-optional**: `webhooks.vercel` and `webhooks.railway`
  MUST each independently be `null` unless their respective
  `VERCEL_WEBHOOK_SECRET`/`RAILWAY_WEBHOOK_SECRET` env var is a non-empty
  string, in which case they MUST be that string.
- **heartbeat-alert-urls-optional**: `heartbeatUrl` and `alertWebhookUrl`
  MUST each independently be `null` unless their respective
  `HEARTBEAT_URL`/`ALERT_WEBHOOK_URL` env var is a non-empty string.
- **glitchtip-projects-default-null**: `glitchtipProjects` MUST be `null`
  when `env.GLITCHTIP_PROJECTS` is unset or blank after trimming, meaning
  every project the org returns.
- **glitchtip-projects-parsing**: `glitchtipProjects` MUST be the
  comma-split, trimmed, non-empty entries of a non-blank
  `env.GLITCHTIP_PROJECTS`, and MUST resolve `null` (not `[]`) when that
  split yields zero entries, so a value of `",,"` is treated the same as
  unset rather than as an empty allowlist.
- **credentials-mapping**: `credentials[name]` MUST equal
  `env[name]` for every `name` in `STATUS_CREDENTIAL_NAMES`, `undefined`
  passed through as `undefined`, never defaulted to a string.
- **secrets-full-passthrough**: `secrets` MUST expose every key present on
  the `env` object handed to `envConfig`, including a name outside
  `STATUS_CREDENTIAL_NAMES` (e.g. a per-integration `tokenEnvVar` such as
  `STATUS_TEST_VERCEL_TOKEN`).
- **lazy-field-evaluation**: Every `StatusConfig` field `envConfig` returns
  MUST be implemented as a getter that reads `env` at the moment of
  property access, not at the moment `envConfig(env)` is called, so a
  caller that mutates the same `env` object after construction MUST see the
  new value on the next read, per the function's own doc comment.
- **production-guard-environment-signal**: the SEC-M5 guard inspects only `env.NODE_ENV === "production"`, never `env.RAILWAY_ENVIRONMENT_NAME` (the signal `monitorLabel` reads to detect a non-production Railway environment), so a deployment whose `NODE_ENV` is not the exact literal `"production"` boots with `AUTH_DISABLED`/`COOKIE_INSECURE` honored. Setting `NODE_ENV` correctly is owned by the service's Railway deployment configuration.

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

## Appearance

Not applicable — this is the status backend's configuration and seed-roster contract (an environment adapter and two data ports), not a visual component.

## States

Not applicable — this is the status backend's configuration and seed-roster contract, not a visual component; its one runtime branch (the SEC-M5 production guard) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is the status backend's configuration and seed-roster contract, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-config-001 | production-escape-hatch-guard | `envConfig(process.env)` with `NODE_ENV=production`, `AUTH_DISABLED=1` | Throws an `Error` matching `/AUTH_DISABLED/` — `config-env.test.ts` › "throws when AUTH_DISABLED=1 in production" |
| status-server-config-002 | production-escape-hatch-guard | `envConfig(process.env)` with `NODE_ENV=production`, `COOKIE_INSECURE=1` | Throws an `Error` matching `/COOKIE_INSECURE/` — `config-env.test.ts` › "throws when COOKIE_INSECURE=1 in production" |
| status-server-config-003 | production-escape-hatch-scoped-outside-production | `envConfig(process.env)` with `NODE_ENV=test`, `AUTH_DISABLED=1`, `COOKIE_INSECURE=1` | Does not throw — `config-env.test.ts` › "allows either escape hatch outside production" |
| status-server-config-004 | credentials-mapping | `envConfig(process.env)` with every `STATUS_CREDENTIAL_NAMES` entry stubbed to `value-for-<name>` | `credentials[name] === 'value-for-<name>'` for all twelve — `config-env.test.ts` › "maps every STATUS_CREDENTIAL_NAMES entry..." |
| status-server-config-005 | credential-record-completeness, credentials-mapping | `envConfig(process.env)` with every `STATUS_CREDENTIAL_NAMES` entry unstubbed | `credentials[name] === undefined` for all twelve — `config-env.test.ts` › "leaves an unset credential undefined..." |
| status-server-config-006 | deploy-sync-seconds-validated | `DEPLOY_SYNC_SECONDS=0` or `-5` | `deploySyncSeconds === null` — `config-env.test.ts` › "rejects zero and negative overrides..." |
| status-server-config-007 | deploy-sync-seconds-validated | `DEPLOY_SYNC_SECONDS=900` | `deploySyncSeconds === 900` — `config-env.test.ts` › "accepts a positive override" |
| status-server-config-008 | deploy-sync-seconds-validated | `DEPLOY_SYNC_SECONDS` unset | `deploySyncSeconds === null` — `config-env.test.ts` › "is null when unset" |
| status-server-config-009 | glitchtip-projects-default-null | `GLITCHTIP_PROJECTS` unset | `glitchtipProjects === null` — `config-env.test.ts` › "is null when GLITCHTIP_PROJECTS is unset..." |
| status-server-config-010 | glitchtip-projects-parsing | `GLITCHTIP_PROJECTS=',,'` | `glitchtipProjects === null` — `config-env.test.ts` › "is null for a mistaken all-comma value..." |
| status-server-config-011 | glitchtip-projects-parsing | `GLITCHTIP_PROJECTS='proj-a, proj-b'` | `glitchtipProjects` equals `['proj-a', 'proj-b']` — `config-env.test.ts` › "splits a comma-separated value..." |
| status-server-config-012 | monitor-label-production-unqualified | `MONITOR_LABEL='adh-status'`, `RAILWAY_ENVIRONMENT_NAME='production'` | `monitorLabel === 'adh-status'` — `config-env.test.ts` › "is left alone in production" |
| status-server-config-013 | monitor-label-production-unqualified | `MONITOR_LABEL='adh-status'`, `RAILWAY_ENVIRONMENT_NAME` unset | `monitorLabel === 'adh-status'` — `config-env.test.ts` › "is left alone with no RAILWAY_ENVIRONMENT_NAME" |
| status-server-config-014 | monitor-label-qualified-non-production | `MONITOR_LABEL='adh-status'`, `RAILWAY_ENVIRONMENT_NAME='testing'` | `monitorLabel === 'adh-status (testing)'` — `config-env.test.ts` › "qualifies the label with a non-production..." |
| status-server-config-015 | monitor-label-no-double-qualification | `MONITOR_LABEL='adh-status-testing'`, `RAILWAY_ENVIRONMENT_NAME='testing'` | `monitorLabel === 'adh-status-testing'` — `config-env.test.ts` › "does not double-qualify..." |
| status-server-config-016 | monitor-label-default | `MONITOR_LABEL` unset, `RAILWAY_ENVIRONMENT_NAME` unset | `monitorLabel === 'this monitor'` — derived from the `env.MONITOR_LABEL?.trim() || 'this monitor'` fallback |
| status-server-config-017 | deploy-sync-interval-floor | `deploySyncIntervalMs(envConfig({}), 60_000)` | `300_000` — `config-cadence.test.ts` › "defaults to a 5-minute floor..." |
| status-server-config-018 | deploy-sync-interval-floor | `deploySyncIntervalMs(envConfig({}), 120_000)` | `600_000` — `config-cadence.test.ts` › "scales to 5× the probe interval..." |
| status-server-config-019 | deploy-sync-interval-override | `DEPLOY_SYNC_SECONDS=90`; `deploySyncIntervalMs(envConfig(process.env), 60_000)` | `90_000` — `config-cadence.test.ts` › "honors a positive DEPLOY_SYNC_SECONDS override" |
| status-server-config-020 | deploy-sync-interval-floor, deploy-sync-seconds-validated | `DEPLOY_SYNC_SECONDS` in `['', '0', '-5', 'abc']`; `deploySyncIntervalMs(envConfig(process.env), 60_000)` | `300_000` for every value — `config-cadence.test.ts` › "ignores a blank/zero/non-numeric override..." |
| status-server-config-021 | config-fields-are-plain-data, config-survives-structured-clone, secrets-full-passthrough | `structuredClone(envConfig({ DATABASE_URL: '...', NODE_ENV: 'test', STATUS_TEST_VERCEL_TOKEN: 'tok_from_an_integration_row' }))` | `cloned.secrets.STATUS_TEST_VERCEL_TOKEN === 'tok_from_an_integration_row'`; `cloned.credentials` equals the original; every field's `typeof` is not `'function'` — `config-clone.test.ts` |
| status-server-config-022 | port-default | `envConfig({})` | `port === 3000` |
| status-server-config-023 | app-version-default | `envConfig({})` | `appVersion === '0.0.0'` |
| status-server-config-024 | git-commit-sha-optional | `envConfig({ RAILWAY_GIT_COMMIT_SHA: 'abc123' })` vs `envConfig({})` | `gitCommitSha === 'abc123'` vs `gitCommitSha === null` |
| status-server-config-025 | probe-interval-default | `envConfig({})` | `probeIntervalSeconds === 60` |
| status-server-config-026 | numeric-env-coercion | `envConfig({ PORT: 'abc' })` | `port` is `NaN` (`Number('abc')`), no error thrown |
| status-server-config-027 | cors-allowed-hosts-parsing | `envConfig({ CORS_ALLOWED_HOSTS: ' a.com, b.com ,' })` | `corsAllowedHosts` equals `['a.com', 'b.com']` |
| status-server-config-028 | cors-allowed-hosts-parsing | `envConfig({})` | `corsAllowedHosts` equals `[]` |
| status-server-config-029 | mcp-allowed-hosts-parsing | `envConfig({ MCP_ALLOWED_HOSTS: 'x.com' })` | `mcpAllowedHosts` equals `['x.com']` |
| status-server-config-030 | peer-token-default-empty | `envConfig({})` | `peerToken === ''` |
| status-server-config-031 | auth-disabled-flag | `envConfig({ AUTH_DISABLED: '1' })` vs `envConfig({ AUTH_DISABLED: 'true' })` | `authDisabled === true` vs `authDisabled === false` |
| status-server-config-032 | cookie-secure-flag | `envConfig({ COOKIE_INSECURE: '1' })` vs `envConfig({})` | `cookieSecure === false` vs `cookieSecure === true` |
| status-server-config-033 | admin-emails-lowercased | `envConfig({ ADMIN_EMAILS: 'A@B.com, C@D.com' })` | `adminEmails` equals `['a@b.com', 'c@d.com']` |
| status-server-config-034 | public-base-url-fallback | `envConfig({ PUBLIC_BASE_URL: 'https://x.com' })` vs `envConfig({ RAILWAY_PUBLIC_DOMAIN: 'y.up.railway.app' })` vs `envConfig({})` | `'https://x.com'` vs `'https://y.up.railway.app'` vs `''` |
| status-server-config-035 | public-base-url-trailing-slash-strip | `envConfig({ PUBLIC_BASE_URL: 'https://x.com//' })` | `publicBaseUrl === 'https://x.com/'` (one trailing slash remains) |
| status-server-config-036 | github-config-shape | `envConfig({ GITHUB_OAUTH_CLIENT_ID: 'id1', GITHUB_FETCH_TIMEOUT_MS: '5000' })` | `github` equals `{ clientId: 'id1', clientSecret: '', fetchTimeoutMs: 5000 }` |
| status-server-config-037 | webhook-secrets-optional | `envConfig({ VERCEL_WEBHOOK_SECRET: 's1' })` | `webhooks` equals `{ vercel: 's1', railway: null }` |
| status-server-config-038 | heartbeat-alert-urls-optional | `envConfig({ HEARTBEAT_URL: 'https://h.example' })` | `heartbeatUrl === 'https://h.example'`, `alertWebhookUrl === null` |
| status-server-config-039 | glitchtip-all-or-nothing | `glitchtipConfigured(envConfig({ GLITCHTIP_URL: 'u', GLITCHTIP_API_TOKEN: 't' }))` (org missing) | `false` |
| status-server-config-040 | glitchtip-all-or-nothing | `glitchtipConfigured(envConfig({ GLITCHTIP_URL: 'u', GLITCHTIP_API_TOKEN: 't', GLITCHTIP_ORG: 'o' }))` | `true` |
| status-server-config-041 | posthog-all-or-nothing | `posthogConfigured(envConfig({ POSTHOG_HOST: 'h', POSTHOG_API_KEY: 'k', POSTHOG_PROJECT_ID: 'p' }))` | `true` |
| status-server-config-042 | seed-roster-empty-semantics | `POST /config/seed` on an app created with no `seed` option | `{ ok: true, groups: 0, sites: 0, endpoints: 0 }` — `config.int.test.ts` › "with no host roster creates no groups, sites or endpoints" |
| status-server-config-043 | seed-fan-out-contract, seed-endpoint-url-construction | `POST /config/seed` with a fixture `SeedRoster` of 3 endpoints (2 groups, one spanning `production`+`staging`) | `{ ok: true, groups: 2, sites: 3, endpoints: 4 }`; endpoint URLs include `https://staging.app.example.com` and `https://backend.example.com/health` — `config.int.test.ts` › "POST /config/seed populates groups, sites, and endpoints from the host roster" |
| status-server-config-044 | seed-endpoint-optional-fields-default | A fixture `SeedEndpoint` with no `expectedStatus`, fanned out via `POST /config/seed` | The created endpoint's `expectedStatus` is `200` — same fixture, `config.ts`'s `?? 200` |
| status-server-config-045 | lazy-field-evaluation | Build `const config = envConfig(env)`, then set `env.PORT = '9000'`, then read `config.port` | `config.port === 9000` (the getter re-reads `env` on this access, not the value captured at construction) |

## Edge Cases

- **Null and empty input**: an unset `PEER_TOKEN`, `CORS_ALLOWED_HOSTS`,
  `MCP_ALLOWED_HOSTS`, or `ADMIN_EMAILS` all resolve to a defined empty
  value (`''` or `[]`) rather than `undefined` or a thrown error, per
  peer-token-default-empty, cors-allowed-hosts-parsing,
  mcp-allowed-hosts-parsing, and admin-emails-lowercased. MUST behave this
  way; an empty `SeedRoster` MUST likewise resolve to zero created rows per
  seed-roster-empty-semantics, not an error.
- **Boundary values**: `DEPLOY_SYNC_SECONDS='0'` and
  `GITHUB_FETCH_TIMEOUT_MS='0'` MUST both resolve `null`, because
  `positiveNumber` requires strictly `n > 0`; `GLITCHTIP_PROJECTS=',,'`
  (every entry blank) MUST resolve `null`, not `[]`, per
  glitchtip-projects-parsing. By contrast, `PORT='0'` and
  `PROBE_INTERVAL_SECONDS='0'` MUST resolve the number `0` unchanged — this
  is the numeric-env-coercion/numeric-env-validation asymmetry: only the
  `positiveNumber`-routed fields reject a zero or negative boundary.
- **Concurrent access**: `envConfig` and every function in `port.ts` are
  pure with respect to their arguments and hold no module-level mutable
  state; two concurrent calls to `envConfig` with different `env` objects
  MUST NOT observe or affect each other. Because JavaScript is
  single-threaded, two logical callers sharing the *same* live `env`
  object (e.g. `process.env`) cannot interleave a read and a write —
  lazy-field-evaluation's re-read on every access is a documented,
  deterministic ordering fact, not an unordered race.
- **Error states — a dependency being unavailable**: none of `env.ts`,
  `port.ts`, or `seed.ts` performs file I/O, a database call, or a network
  request, so there is no "dependency unavailable" failure mode within
  these three files to handle; the sole failure path any of them defines
  is the synchronous, deterministic production-escape-hatch-guard throw.
- **Offline / disconnected state**: not applicable for the same reason —
  these three files never hold a network connection to lose. Their fields
  configure timeouts and URLs (`github.fetchTimeoutMs`, `heartbeatUrl`,
  `alertWebhookUrl`, the webhook secrets) that other, external modules use
  to make and retry network calls; that retry/timeout behavior is
  specified in those modules, not here.
- **A malformed numeric env value**: `PORT` or `PROBE_INTERVAL_SECONDS` set
  to a non-numeric string (e.g. `"abc"`) MUST resolve `NaN` with no thrown
  error and no fallback to the documented default — see the open question
  on numeric-env-validation.
- **A production deploy whose `NODE_ENV` is not the literal `"production"`**:
  the SEC-M5 guard MUST NOT fire, even if `RAILWAY_ENVIRONMENT_NAME` says
  otherwise — see production-guard-environment-signal.

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

## Deep Linking

Not applicable: none of `env.ts`, `port.ts`, or `seed.ts` defines an application URL scheme or an HTTP route; `StatusConfig` and `SeedRoster` are data other modules' routes consume, external to these three files.

## Localization

None of these three files uses a localization mechanism. `envConfig` throws
exactly one user-facing string, always in English, and everything else
these files produce is either numeric/boolean data or a passthrough of a
host-supplied value. Per this recipe's authoring rules, a hardcoded string
is a fact to record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — thrown `Error` message | `refusing to boot: AUTH_DISABLED / COOKIE_INSECURE must not be set when NODE_ENV=production` | `envConfig`'s SEC-M5 guard |

## Accessibility Options

Not applicable: these three files have no UI and respond to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of these three files consults a feature-flag system; `authDisabled` and the other boolean/derived fields are plain `StatusConfig` fields, already documented under Configuration and the Behavioral Requirements above, not a flag-service lookup.

## Analytics

Not applicable: none of `env.ts`, `port.ts`, or `seed.ts` emits an analytics or telemetry event of any kind.

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

## Logging

Not applicable: none of `env.ts`, `port.ts`, or `seed.ts` contains a logging call at any level.

## Platform Notes

- **React/Web** (source platform): the three files live under
  `packages/web/packages/status-server/src/config/`, barreled through
  `index.ts`. `env.ts` reads a plain `Readonly<Record<string, string | undefined>>`
  (`EnvSource`) rather than importing `process` directly, so it also runs
  against a test fixture object; `port.ts` and `seed.ts` import nothing
  outside this package. The monitor-worker boundary these files are shaped
  for (`workerData`/`structuredClone`) is Node's `worker_threads`, in
  `src/monitor/worker-client.ts` and `worker.ts`, external to this recipe's
  three files.
- **SwiftUI / AppKit / UIKit**: no UI surface to port. A Swift
  re-implementation of this CONFIG PORT for a companion backend (Vapor or
  Hummingbird) would model `EnvSource` as `[String: String]` read from
  `ProcessInfo.processInfo.environment`, `StatusConfig` as a `Sendable`
  `struct` whose fields are plain stored properties resolved once at
  construction — Swift has no cheap analogue to a JS getter closing over a
  captured dictionary, so lazy-field-evaluation's "read at access, not at
  build" behavior would need to be reproduced explicitly (e.g. a computed
  property reading a stored `[String: String]`) if that semantics is
  required. `STATUS_CREDENTIAL_NAMES` maps to a `static let` array of an
  enum with a `String` raw value.
- **Compose**: same non-UI relationship. A Kotlin backend (Ktor) would model
  `EnvSource` as `Map<String, String?>` from `System.getenv()`, and
  `StatusConfig` as a `data class` whose numeric fields use `String?.toIntOrNull()`
  / `toDoubleOrNull()` — which, unlike the source's bare `Number()`, already
  returns `null` on a malformed string, closing the numeric-env-validation
  gap for free in a Kotlin port.
- **WinUI 3**: a WinUI 3 desktop app is a client of this backend and does
  not reimplement this config port; if a future product needed a .NET
  companion backend (ASP.NET Core Minimal API) that DID reimplement it, the
  mapping is concrete: `EnvSource` becomes an `IConfiguration`
  (`Microsoft.Extensions.Configuration`, or plain
  `Environment.GetEnvironmentVariable`); `StatusConfig` becomes an immutable
  `record` whose numeric properties are expression-bodied
  (`public int Port => int.TryParse(Env("PORT"), out var p) ? p : 3000;`),
  which both preserves the source's per-access laziness AND gets
  `int.TryParse`/`double.TryParse`'s built-in validation for free — the
  exact gap flagged by numeric-env-validation does not reproduce in a
  faithful C# port unless someone deliberately drops the `TryParse` guard.
  `STATUS_CREDENTIAL_NAMES` becomes a `static readonly ImmutableArray<string>`;
  `SeedEnvironment` becomes an `enum { Production, Staging, Testing }`;
  `SeedRoster` becomes `IReadOnlyList<SeedEndpoint>` of an immutable
  `record SeedEndpoint(string Group, string Name, string BaseSlug, string Host, IReadOnlyList<SeedEnvironment> Envs, string Kind, string? Path = null, int? ExpectedStatus = null)`.
  Because a `StatusConfig` here would likewise need to cross a background
  `Task`/`AppService` boundary, it should stay `System.Text.Json`-serializable
  with no delegate members — the same "no method survives the boundary"
  constraint the source states for `structuredClone`.

## Design Decisions

- **Decision**: implement every `StatusConfig` field `envConfig` returns
  as a getter over the captured `env` reference, rather than snapshotting
  each value into a plain field at construction time.
  **Rationale**: the source's own doc comment states this directly — a
  host constructs one `StatusConfig` at module load, and a test that
  mutates `process.env` afterward (a common pattern in this test suite)
  still needs the config to see the new value; only a getter that reads
  `env` on each access can do that.
  **Approved**: pending
- **Decision**: strip at most one trailing slash from `publicBaseUrl`
  (`/\/$/`, not a global pattern), instead of normalizing away every
  trailing slash.
  **Rationale**: not stated in source; this is a plain fact about the
  code's actual behavior (see public-base-url-trailing-slash-strip), not
  an idealized rationale invented for this recipe. It differs from the
  fuller slash/case/port canonicalization `routes/config.ts` applies to a
  peer's `baseUrl` (external to these three files), which strips every
  trailing slash — the two call sites simply solve different problems.
  **Approved**: pending
- **Decision**: default `glitchtipProjects` to "every project the org
  returns" rather than "no project" when `GLITCHTIP_PROJECTS` is unset.
  **Rationale**: the source comment states this directly — a fleet with
  one GlitchTip project needs no configuration to work, and the allowlist
  exists for the second project to *require*, not for the first to wait on;
  an all-comma value (`",,"`) is treated as a mistake, not an instruction
  to silence the feature, for the same reason.
  **Approved**: pending
- **Decision**: leave `port` and `probeIntervalSeconds` as unvalidated
  `Number()` coercions while routing `deploySyncSeconds` and
  `github.fetchTimeoutMs` through the stricter `positiveNumber` helper —
  see the open question on numeric-env-validation.
  **Rationale**: not stated in source; the asymmetry is a plain fact about
  the code, not a defended design. It is flagged rather than resolved here
  because deciding whether to add validation, and where (this adapter vs.
  its HTTP-listen/probe-scheduler callers), is a call for whoever owns
  those callers, not something derivable from `env.ts`, `port.ts`, or
  `seed.ts` alone.
  **Approved**: pending
- **Decision**: gate the SEC-M5 production guard on `NODE_ENV` only, not on
  `RAILWAY_ENVIRONMENT_NAME` — see production-guard-environment-signal.
  **Rationale**: not stated in source. Recorded here rather than resolved
  because closing it requires knowing how this service's actual Railway
  deployment sets `NODE_ENV`, which is outside what these three files (or
  this recipe) can determine.
  **Approved**: pending
- **Decision**: this recipe carries roughly forty Behavioral Requirements
  against `status-server-auth`'s forty, despite `env.ts`/`port.ts`/`seed.ts`
  having far fewer conditional branches than the five auth files.
  **Rationale**: the count is comparable because most of this component's
  behavior is field-by-field derivation (one getter, one requirement) with
  only two real decision points (the SEC-M5 guard, `monitorLabel`'s
  qualification), not because the two components are equally complex; the
  per-field granularity keeps each requirement independently testable
  rather than bundling twenty getters into one compound statement.
  **Approved**: pending
- **Decision**: this recipe's `related` field links to
  `agentictoolkit://recipes/status-server-auth` one-directionally; the
  reverse link on `status-server-auth.md` was not added.
  **Rationale**: this recipe was authored under an explicit constraint to
  write only `recipes/status-server-config.md` and touch no other file;
  cross-recipe-consistency's own text allows a unidirectional reference
  ("acceptable but bidirectional is preferred"), so this is a known,
  intentional gap in the preferred state, not an oversight.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [cors-allowlist](agenticdevelopercookbook://compliance/security#cors-allowlist) | passed | Security |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`separation-of-concerns` passes: `port.ts` defines the contract and its pure
derived helpers, `env.ts` is the one shipped adapter for a twelve-factor
host, and `seed.ts` is an independent port for a differently-shaped concern
(the host's site roster); the fan-out logic, HTTP routes, and every
consumer named in Overview live one layer up, outside all three files.
`unit-test-coverage` passes: `config-env.test.ts` exercises the guard, the
credential map, `deploySyncSeconds`, `glitchtipProjects`, and
`monitorLabel`; `config-cadence.test.ts` exercises `deploySyncIntervalMs`;
`config-clone.test.ts` exercises the structured-clone/plain-data contract;
and `config.int.test.ts` exercises the seed roster's empty and populated
fan-out counts. `explicit-error-handling` is `partial`: the SEC-M5 guard
fails fast with a specific, descriptive `Error`, but `port` and
`probeIntervalSeconds` let a malformed numeric env value become `NaN` with
no error and no distinguishable signal — see the open question on
numeric-env-validation, recorded as a fact rather than defended.
`secure-storage` passes for what these three files themselves do: none of
them writes a credential to disk, a database, or any other store; the
process environment is the storage, owned by the host's deployment
platform, external to this recipe's three files. `secure-log-output`
passes trivially — per Logging, there is no log output in these files to
leak a credential into. `cors-allowlist` passes: `corsAllowedHosts` and
`mcpAllowedHosts` are built as an explicit, finite array of host names with
no wildcard sentinel in the type or the `list()` helper; the check's
"never wildcards with credentials" concern is a decision for the external
middleware that reads this array, not something these three files could
violate on their own. `no-pii-in-logs` passes the same way
`secure-log-output` does — there is no log output in these files to carry a
credential or an admin email into.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
