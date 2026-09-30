<!-- leaf: implement-status-server/config--part-2 · source: status-server-config.md -->

# Status Server Config — continued (part 2)

**Rules** (cite as `implement-status-server/config--part-2#<slug>`):

- `credential-name-list` MUST
- `credential-record-completeness` MUST
- `config-fields-are-plain-data` MUST
- `config-survives-structured-clone` MUST
- `secrets-field-identity` MUST
- `deploy-sync-interval-floor` MUST
- `deploy-sync-interval-override` MUST
- `glitchtip-all-or-nothing` MUST
- `posthog-all-or-nothing` MUST
- `production-escape-hatch-guard` MUST
- `production-escape-hatch-scoped-outside-production` MUST
- `port-default` MUST
- `app-version-default` MUST
- `git-commit-sha-optional` MUST
- `probe-interval-default` MUST
- `numeric-env-coercion` MUST
- `deploy-sync-seconds-validated` MUST
- `cors-allowed-hosts-parsing` MUST
- `mcp-allowed-hosts-parsing` MUST
- `peer-token-default-empty` MUST
- `monitor-label-default` MUST
- `monitor-label-production-unqualified` MUST
- `monitor-label-qualified-non-production` MUST
- `monitor-label-no-double-qualification` MUST
- `auth-disabled-flag` MUST
- `cookie-secure-flag` MUST
- `admin-emails-lowercased` MUST
- `public-base-url-fallback` MUST
- `public-base-url-trailing-slash-strip` MUST
- `github-config-shape` MUST
- `webhook-secrets-optional` MUST
- `heartbeat-alert-urls-optional` MUST
- `glitchtip-projects-default-null` MUST
- `glitchtip-projects-parsing` MUST
- `credentials-mapping` MUST
- `secrets-full-passthrough` MUST
- `lazy-field-evaluation` MUST

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

