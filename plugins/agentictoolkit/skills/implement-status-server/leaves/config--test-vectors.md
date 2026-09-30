<!-- leaf: implement-status-server/config--test-vectors · source: status-server-config.md -->

# Status Server Config

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
