<!-- leaf: implement-status-server-monitor-fetch/railway--part-2 · source: status-server-monitor-fetch-railway.md -->

# Status Server Monitor Fetch Railway — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-fetch/railway--part-2#<slug>`):

- `deployments-query-first-20` MUST
- `deployments-fetch-failure-is-project-error` MUST
- `row-created-at-validated` MUST
- `row-environment-name-required` MUST
- `row-id-prefix` MUST
- `row-platform-literal` MUST
- `row-project-name-from-config` MUST
- `row-provider-project-id` MUST
- `row-phases-from-status` MUST
- `row-commit-hash-shortened` MUST
- `row-commit-message-full` MUST
- `row-branch-passthrough` MUST
- `row-commit-repo-conditional` MUST
- `row-url-dashboard-link` MUST
- `deploys-flattened` MUST
- `ok-composition` MUST
- `build-log-tail-signature` MUST
- `build-log-tail-trims-and-filters` MUST
- `build-log-tail-keeps-last-40` MUST
- `build-log-tail-caps-chars` MUST
- `build-log-tail-null-when-empty` MUST
- `build-log-full-keeps-all` MUST
- `no-build-permanent-sentinel` MUST
- `fetch-build-log-tail-contract` MUST
- `fetch-build-log-full-contract` MUST
- `no-build-text-constant` MUST

### Deployment Fetch and Row Mapping

- **deployments-query-first-20**: For each project, `fetchRailwayDeployments` MUST request `deployments(first: 20, input: { projectId })`.
- **deployments-fetch-failure-is-project-error**: A non-ok deployments HTTP response MUST be logged (`` Railway <projectId> <status> ``) and MUST cause that project's poll to return `{ rows: [], error: true, aborted: false }`. A response body carrying GraphQL `errors` MUST be logged (`` Railway <projectId> GraphQL errors: <messages> ``) and MUST produce the same `{ rows: [], error: true, aborted: false }` result.
- **row-created-at-validated**: Each mapped row's `createdAt` MUST be the result of `toValidDate(node.createdAt)` (`./provider-deploy`, external); when that call returns `null`, `fetchRailwayDeployments` MUST log `` Railway deployment <id> has unparseable createdAt <JSON-stringified value> — skipping `` and MUST exclude only that one deployment from the project's rows (via `flatMap` returning `[]` for it), without failing the rest of the project's deployments.
- **row-environment-name-required**: Each mapped row's `environment` MUST be the environment-name map's resolved name for `node.environmentId`; when that id is absent from the map, `fetchRailwayDeployments` MUST log `` Railway deployment <id> references unknown environment <JSON-stringified environmentId> — skipping `` and MUST exclude only that one deployment from the project's rows. A row's `environment` MUST NEVER be the raw `environmentId` UUID or an empty string — either would mint a board target (`railway|<project>|<env>`, external) that matches no roster entry, or collides with an environment-less roster entry.
- **row-id-prefix**: Each mapped row's `id` MUST be the literal string `ry_` concatenated with the Railway deployment's `id` field.
- **row-platform-literal**: Each mapped row's `platform` MUST be the literal string `railway`.
- **row-project-name-from-config**: Each mapped row's `projectName` MUST be the Railway project's configured or enumerated `name` (the value the poll was called with for that project), never a value read from the deployment or its `meta`.
- **row-provider-project-id**: Each mapped row's `providerProjectId` MUST be the polled project's `id`.
- **row-phases-from-status**: Each mapped row's `buildPhase` and `deployPhase` MUST be the two fields of `railwayPhases(node.status)` (`./deploy-status`, external), spread directly onto the row.
- **row-commit-hash-shortened**: When `meta?.commitHash` is a `string`, the mapped row's `commitHash` MUST be `shortSha(meta.commitHash)` (`./format`, external, a 7-character truncation); otherwise it MUST be `null`.
- **row-commit-message-full**: When `meta?.commitMessage` is a `string`, the mapped row's `commitMessage` MUST be `commitFullMessage(meta.commitMessage)` (`./format`, external, the whole message capped at 4,000 characters with trailing whitespace stripped); otherwise it MUST be `null`.
- **row-branch-passthrough**: When `meta?.branch` is a `string`, the mapped row's `branch` MUST be that string unchanged; otherwise it MUST be `null`.
- **row-commit-repo-conditional**: When `meta?.repo` is a `string` AND contains a `/` character, the mapped row's `commitRepo` MUST be that string unchanged; otherwise it MUST be `null`.
- **row-url-dashboard-link**: Each mapped row's `url` MUST be the literal string `https://railway.com/project/` concatenated with the project id — the Railway dashboard link for that project — and MUST NOT be `node.staticUrl` or any other per-deployment live URL.

### Return Value

- **deploys-flattened**: `fetchRailwayDeployments` MUST return every successfully mapped row from every polled project's poll, concatenated into one flat `deploys` array, regardless of whether `ok` is `true` or `false` for the overall call.
- **ok-composition**: For the branch where at least one project was listed and polled, the returned `ok` MUST be `!anyError && !skipped` — `true` only when every polled project's poll succeeded with no unresolved error and no project was left unpolled for lack of remaining budget.

### Build Log Shaping (network-free)

- **build-log-tail-signature**: `buildLogTail` MUST accept an array of `string | null | undefined` and MUST return `string | null`.
- **build-log-tail-trims-and-filters**: `buildLogTail` MUST call `trimEnd()` on each message and MUST drop any message that is `null`, `undefined`, or empty after trimming, before joining the rest.
- **build-log-tail-keeps-last-40**: `buildLogTail` MUST keep only the last `RAILWAY_LOG_TAIL_LINES` (40) surviving lines, joined with `\n`.
- **build-log-tail-caps-chars**: `buildLogTail` MUST cap the joined tail at `RAILWAY_LOG_MAX_CHARS` (4,000) characters, keeping the END of the string and prefixing it with a single `…` character when truncation occurs.
- **build-log-tail-null-when-empty**: `buildLogTail` MUST return `null` when no non-blank lines remain after filtering.
- **build-log-full-keeps-all**: `buildLogFull` MUST accept the same input shape as `buildLogTail`, MUST apply the same trim-and-drop-blank filtering, but MUST keep every surviving line — with no line-count cap and no character cap — joined with `\n`, or `null` when none remain.

### Build Log Retrieval (network)

- **no-build-permanent-sentinel**: The internal `railwayBuildLogMessages` helper, shared by both `fetchRailwayBuildLogTail` and `fetchRailwayBuildLog`, MUST return the internal `NO_BUILD` symbol when the `buildLogs` query's GraphQL `errors` include a message matching `does not have an associated build` (case-insensitive), and MUST return `null` for any other GraphQL error, any non-ok HTTP response, or a thrown fetch — each logged with a distinguishing message (`` Railway buildLogs <deploymentId> <status> ``, `` Railway buildLogs <deploymentId> GraphQL errors: <messages> ``, or `` Railway buildLogs <deploymentId> fetch failed <err> ``).
- **fetch-build-log-tail-contract**: `fetchRailwayBuildLogTail(deploymentId, token, signal)` MUST request `buildLogs` with `limit: 200`, MUST return `RAILWAY_NO_BUILD_TEXT` when the shared helper reports the permanent sentinel, and otherwise MUST return `buildLogTail(messages)` when messages were retrieved or `null` when the helper itself failed.
- **fetch-build-log-full-contract**: `fetchRailwayBuildLog(deploymentId, token, signal)` MUST request `buildLogs` with `limit: RAILWAY_LOG_FULL_LINES` (10,000), MUST return `RAILWAY_NO_BUILD_TEXT` when the shared helper reports the permanent sentinel, and otherwise MUST return `buildLogFull(messages)` when messages were retrieved or `null` when the helper itself failed.
- **no-build-text-constant**: The exported `RAILWAY_NO_BUILD_TEXT` MUST be the literal string `(no build logs — the deployment has no associated build)`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RAILWAY_API_TOKEN` | `string \| undefined` (field of `env`) | none — required for a non-no-op poll | The Railway API Bearer token, sent by the vendored `gqlPost` as `Authorization: Bearer <token>` on every GraphQL call. Absent or empty triggers the no-op branch (noop-missing-token). This file reads it only from the `env` object passed in, not from `process.env`. |
| `projects` | `readonly RailwayProject[] \| undefined` (field of `env`) | `[]` (via `env.projects ?? []`) | The configured fallback project list (`{ id, name }` pairs), used only when `listRailwayProjects` fails to enumerate live (fallback-to-configured-projects). The caller (`sync.ts`, external) passes `conn.railway.projects`, sourced from the DB integration config. |
| `overallBudgetMs` | `number \| undefined` (field of `env`) | `18_000` | The overall poll budget in milliseconds, counted from before the project-listing call starts (deadline-starts-before-listing). Per the source's own comment, deliberately shorter than the caller's `PROVIDER_POLL_TIMEOUT_MS` (20,000ms, `sync.ts`, external), and overridable "for tests/tuning." |
| `callTimeoutMs` | `number \| undefined` (field of `env`) | `6_000` (`RAILWAY_CALL_TIMEOUT_MS`) | The per-GraphQL-call time box, overridable so a test can exercise the retry "in milliseconds instead of waiting out a 6s box," per the source's own comment. |
| `RAILWAY_CALL_ATTEMPTS` (module constant) | `number` | `2` | Total attempts (one original plus one retry) for the project listing and for each project's poll, on our own timeout only. Not exposed on `env`. |
| `RAILWAY_PROJECT_CONCURRENCY` (module constant) | `number` | `5` | Fixed fan-out limit for per-project polls via `mapLimit`. Not exposed on `env`. |
| `RAILWAY_ENV_PAGE_SIZE` (module constant) | `number` | `200` | Pinned page size (the `first` variable) for the per-project `environments` query. Not exposed on `env`. |
| `RAILWAY_LOG_TAIL_LINES` (module constant) | `number` | `40` | Trailing line count `buildLogTail` keeps. Not exposed on `env`. |
| `RAILWAY_LOG_MAX_CHARS` (module constant) | `number` | `4_000` | Character cap `buildLogTail` applies to its joined tail. Not exposed on `env`. |
| `RAILWAY_LOG_FULL_LINES` (module constant) | `number` | `10_000` | The `limit` argument `fetchRailwayBuildLog` sends to the `buildLogs` query for the on-demand full read. Not exposed on `env`. |
| `RAILWAY_NO_BUILD_TEXT` (exported constant) | `string` | `(no build logs — the deployment has no associated build)` | The permanent placeholder both build-log fetchers return for a deployment Railway reports as never having had a build. |

## Localization

- **Data collected**: this file introduces one user-facing (details-pane-visible) hardcoded English string, `RAILWAY_NO_BUILD_TEXT`, persisted as a deploy's `error_text` by its caller (`enrich-deploy-errors.ts`, external) and surfaced to whoever views that deploy's details. It is not routed through any localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string, no key) | `(no build logs — the deployment has no associated build)` | Persisted `error_text` / returned build-log text for a Railway deployment with no associated build, shown in the details pane and the `GET /deployments/:id/log` response. |

Every other string this file emits (`console.error` diagnostic lines) is developer/operator-facing in server logs, not end-user-facing, and is documented under Logging rather than here.

