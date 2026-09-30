<!-- leaf: implement-status-server/libsql--part-2 · source: status-server-libsql.md -->

# Status Server Libsql — continued (part 2)

**Rules** (cite as `implement-status-server/libsql--part-2#<slug>`):

- `site-group-uniqueness` MUST
- `monitored-site-uniqueness` MUST
- `monitored-endpoint-fk` MUST
- `fk-cascade-not-enforced-over-http` MUST
- `endpoint-check-defaults` MUST
- `endpoint-per-signal-toggles` MUST
- `endpoint-deploy-project-id-write-once` MUST
- `deploy-platform-tables-reexported` MUST
- `platform-health-state-shape` MUST
- `vercel-prod-state-shape` MUST
- `peer-uniqueness` MUST
- `peer-snapshot-fk` MUST
- `error-row-uniqueness` MUST
- `analytics-metrics-indexing` MUST
- `user-uniqueness` MUST
- `session-token-hash-only` MUST
- `api-token-hash-only` MUST
- `api-token-created-at-app-default` MUST
- `device-auth-hash-only-except-raw` MUST
- `device-auth-status` MUST
- `exported-row-types` MUST

### Schema — monitoring config

- **site-group-uniqueness**: `siteGroups.slug` MUST be unique
  (`uniq_site_group_slug`); `retentionDays` MUST default to `14`.
- **monitored-site-uniqueness**: `monitoredSites` MUST enforce uniqueness
  of `(siteGroupId, slug)` via `uniq_site_group_site_slug`, and MUST
  declare a foreign key to `siteGroups.id` with `onDelete: 'cascade'`.
- **monitored-endpoint-fk**: `monitoredEndpoints.siteId` MUST declare a
  foreign key to `monitoredSites.id` with `onDelete: 'cascade'`, and MUST
  be indexed (`idx_endpoint_site`) for per-site lookup.
- **fk-cascade-not-enforced-over-http**: the `onDelete: 'cascade'`
  declarations on `monitoredSites` and `monitoredEndpoints` MUST be
  understood as documentation of intent only — the source's own comment
  states libSQL accessed over HTTP does not enforce foreign-key
  constraints, so `deleteGroup`/`deleteSite` (external to these two files)
  cascade in application code, never by relying on the database to do it.
- **endpoint-check-defaults**: `monitoredEndpoints` MUST default `kind` to
  `'http'`, `expectedStatus` to `200`, `checkIntervalSeconds` to `60`,
  `dnsCheckA`/`dnsCheckAaaa`/`dnsCheckCname` to `true`, `isActive` to
  `true`, `monitorHttp` to `true`, `monitorDeploys` to `true`, and
  `ignoreProjectWarning` to `false`.
- **endpoint-per-signal-toggles**: `monitoredEndpoints.monitorHttp` and
  `monitoredEndpoints.monitorDeploys` MUST be independent of `isActive` and
  of each other — per the column comment, turning one signal off removes
  only that signal's problems from the board while the master switch and
  the other signal remain unaffected.
- **endpoint-deploy-project-id-write-once**: `monitoredEndpoints.deployProjectId`
  MUST be nullable, with `null` meaning not yet learned; the column's own
  comment states that once a value is learned it is never overwritten
  automatically, so an operator-entered value always wins. `schema.ts`
  itself declares no trigger or default enforcing this — it is a documented
  invariant of the column's meaning that the calling code (external to
  these two files) is responsible for upholding, the same way
  fk-cascade-not-enforced-over-http is.
- **deploy-platform-tables-reexported**: `deployIntegrations`,
  `deployProjectMeta`, and `ignoredDeployProjects` MUST be re-exported from
  `@agentic-toolkit/deploy-platform/schema` rather than declared locally,
  so every existing importer's `../db/schema` path continues to resolve
  them.

### Schema — platform and peer state

- **platform-health-state-shape**: `platformHealthState` MUST key one row
  per `source` (platform identifier), tracking `consecutiveFailures`
  (default `0`), `configured` (default `true`), and `reachable` (default
  `true`); the column comments document both boolean defaults as
  deliberate, benign guesses about pre-existing rows, not facts.
- **vercel-prod-state-shape**: `vercelProdState` MUST key one row per
  `projectName`, with `stale` defaulting to `false`; per the table's
  comment, the row is replaced wholesale on every complete read, never
  merged field-by-field.
- **peer-uniqueness**: `peers.baseUrl` MUST be unique
  (`uniq_peer_base_url`); `peers.token` MUST be nullable, with `null`
  meaning the peer's own reads are public (no bearer required), per the
  column comment.
- **peer-snapshot-fk**: `peerSnapshots.peerId` MUST be the primary key and
  MUST declare a foreign key to `peers.id` with `onDelete: 'cascade'`;
  `peerSnapshots.reachable` MUST default to `false`.

### Schema — errors and analytics

- **error-row-uniqueness**: `errors.issueKey` MUST be unique
  (`uniq_error_issue`) — one row per GlitchTip issue id, upserted by
  callers external to this file; `errors` MUST be indexed on `lastSeen`
  (`idx_error_last_seen`); `count` and `userCount` MUST each default to
  `0`, and `resolved` MUST default to `false`.
- **analytics-metrics-indexing**: `analyticsMetrics` MUST be indexed on the
  composite `(metric, window, scope, capturedAt)`
  (`idx_analytics_metric_time`) for the dashboard's latest-value/trend
  reads, and independently on `capturedAt` alone
  (`idx_analytics_captured`) for the same age-only retention-prune reason
  as `healthChecks`; `scope` MUST default to `'all'`.

### Schema — auth and tokens

- **user-uniqueness**: `users.email` and `users.githubId` MUST each be
  unique (`uniq_user_email`, `uniq_user_github`); `role` MUST default to
  `'pending'`; `passwordHash` and `githubId` MUST each be independently
  nullable, supporting OAuth-only and password-only accounts respectively,
  per the table's leading comment.
- **session-token-hash-only**: `sessions` MUST persist only `tokenHash`
  (unique, `uniq_session_token`), never a raw session token, per the
  table's comment ("only its sha256 is persisted... so a DB leak can't
  reconstruct live cookies"); `sessions.userId` MUST declare a foreign key
  to `users.id` with `onDelete: 'cascade'`, and MUST be indexed
  (`idx_session_user`).
- **api-token-hash-only**: `apiTokens` MUST persist only `tokenHash`
  (unique, `uniq_api_token_hash`) plus a display-only `prefix`
  (`raw.slice(0, 12)`), never the raw bearer value, per the table's
  comment; `role` MUST be `'admin' | 'user'`; `kind` MUST default to
  `'minted'`; `createdBy` MUST declare a foreign key to `users.id` with
  `onDelete: 'cascade'`; revocation MUST be represented by setting
  `revokedAt`, never by deleting the row.
- **api-token-created-at-app-default**: `apiTokens.createdAt` and
  `deviceAuthorizations.createdAt` MUST be populated via a `$defaultFn`
  (`() => new Date()`) rather than a SQL-level `DEFAULT` — unlike every
  other timestamp column in this schema, which defaults via `.default(now)`
  (a SQL `unixepoch()` default). A row inserted through raw SQL bypassing
  Drizzle's insert path would leave these two columns `NULL`-violating,
  since both are `notNull()` with no SQL default.
- **device-auth-hash-only-except-raw**: `deviceAuthorizations` MUST persist
  only `deviceCodeHash` and `userCodeHash` (each unique, `uniq_device_code`
  and `uniq_user_code`), never the plaintext device or user code, per the
  table's comment; `tokenRaw` MUST be the one column in this schema
  documented to briefly hold a plaintext secret, and only between approval
  and the single successful poll — the comment states the row is then
  deleted (single-use) by code external to these two files, and `tokenRaw`
  is never selected in any list path.
- **device-auth-status**: `deviceAuthorizations.status` MUST default to
  `'pending'` and be one of `'pending' | 'approved' | 'denied'`; `tokenId`
  MUST declare a foreign key to `apiTokens.id` with `onDelete: 'set null'`;
  `approvedBy` MUST declare a foreign key to `users.id` with
  `onDelete: 'set null'`.
- **exported-row-types**: `schema.ts` MUST export `User`, `NewUser`, and
  `Session` type aliases inferred from `users.$inferSelect`,
  `users.$inferInsert`, and `sessions.$inferSelect` respectively.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `conn.url` | `string` (`LibsqlConnection` field) | required | `openLibsql`'s one validated input; a `file:` prefix selects the embedded-file/WAL/checkpoint code paths, anything else a remote libsql/Turso connection. |
| `conn.authToken` | `string \| undefined` (`LibsqlConnection` field) | `undefined` | Passed through unchanged to `drizzle`'s `connection.authToken`; irrelevant for an embedded file, required by a remote libsql/Turso database that enforces one. |
| `migrationsFolder` | `string` (`migrateDb` parameter) | `MIGRATIONS_FOLDER` | Overridable only for tests; production callers always take the default. |
| `MIGRATIONS_FOLDER` | module constant (`client.ts`) | `<packageRoot>/src/libsql/migrations` | The migrations this package ships, resolved via Node's own package self-reference. |

## Privacy

- **Data collected**: `users` stores an email, an optional bcrypt password
  hash, an optional GitHub id, and a display name (identity data);
  `sessions`/`apiTokens`/`deviceAuthorizations` store only the sha256 hash
  of a session token, API bearer, device code, and user code — never the
  raw secret at rest — with `deviceAuthorizations.tokenRaw` as the one
  documented, time-boxed exception (held only between approval and the
  single successful poll, then the row is deleted by code external to
  these two files). `errors` and `analyticsMetrics` store polled,
  aggregate summaries (issue titles/culprits, pageview/visitor counts),
  not raw end-user request data.
- **Storage**: everything in this recipe's scope is persisted in the same
  embedded SQLite/libSQL file (or remote libsql/Turso database) `openLibsql`
  connects to — `schema.ts`'s own comment on the errors/analytics tables
  states this explicitly ("on THIS backend they live in the same embedded
  SQLite/libSQL DB as everything else"). No table in either file writes to
  a second store.
- **Transmission**: `client.ts` performs no network calls of its own for
  an embedded-file connection; a remote libsql/Turso connection's transport
  security is the `@libsql/client` driver's responsibility, external to
  these two files. `authToken` is passed to that driver unchanged, never
  logged or persisted by `client.ts`.
- **Retention**: `healthChecks`, `metricsHourly`, `issues`, `analyticsMetrics`,
  and `deployments` are pruned/aged out by callers external to these two
  files; several of the schema's own secondary indexes
  (`idx_health_checked`, `idx_metrics_hour`, `idx_issue_opened`,
  `idx_analytics_captured`, `idx_deploy_inflight`) exist specifically to
  make that external age-based pruning cheap, per their comments.
  `deviceAuthorizations` rows are "opportunistically reaped on TTL
  (`expires_at`)" per the table's comment — also external to these two
  files. Neither file itself deletes a row.

