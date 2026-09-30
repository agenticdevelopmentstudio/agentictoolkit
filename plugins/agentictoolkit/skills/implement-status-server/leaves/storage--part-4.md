<!-- leaf: implement-status-server/storage--part-4 · source: status-server-storage.md -->

# Status Server Storage Boundary — continued (part 4)

**Rules** (cite as `implement-status-server/storage--part-4#<slug>`):

- `redact-peer` MUST
- `is-unique-violation` MUST
- `to-auth-user` MUST
- `role-for-email` MUST
- `token-constants` MUST
- `errors` MUST
- `analytics` MUST
- `sensitive-fields` MUST — UserRecord.passwordHash (never read back to clients), PeerRow.token (redacted by redactPeer helper; MUST NOT leave the …

### Pure Helpers

- **redact-peer**: `redactPeer(peer)` MUST return the peer without `token` plus `hasToken`, true only when `token` is a non-empty string.
- **is-unique-violation**: `isUniqueViolation(err)` MUST walk the Error `.cause` chain and return true when any message matches UNIQUE constraint failed (case-insensitive); a non-Error returns false.
- **to-auth-user**: `toAuthUser(record)` MUST project `UserRecord` to `{ id, email, displayName, role }`, dropping `passwordHash`, `githubId` and `createdAt`; an unknown role string coerces to 'pending' (fail safe).
- **role-for-email**: `roleForEmail(email, config)` MUST return 'admin' when the lowercased email is in `config.adminEmails`, else 'pending'.
- **token-constants**: `TOKEN_PREFIX` MUST be 'sts_' and `PREFIX_LEN` MUST be 12.

### Telemetry Store

- **errors**: MUST be a `Store<ErrorDTO>` for persisted GlitchTip error streams.
- **analytics**: MUST be a `Store<AnalyticsMetricDTO>` for persisted PostHog analytics streams.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| db connection url | string | (required) | libSQL connection string held by the adapter; only `SnapshotOptions.dbUrl` (tests) overrides it |
| session TTL | number (ms) | 30 days | `createSession` default when `ttlMs` is omitted |
| `TOKEN_PREFIX` | string | 'sts_' | Prefix of every raw API token |
| `PREFIX_LEN` | number | 12 | Leading characters stored as the token display prefix |
| admin emails | string[] | from ADMIN_EMAILS | `StatusConfig.adminEmails`; `roleForEmail` makes a matching email 'admin' on first account |

## Privacy

- **Sensitive fields**: `UserRecord.passwordHash` (never read back to clients), `PeerRow.token` (redacted by `redactPeer` helper; MUST NOT leave the process), `ApiTokenMeta` (never includes hash or raw value), the `raw` value returned by `mintApiToken` (shown to caller exactly once), and `DeviceGrantRow` (omits `deviceCodeHash`, `userCodeHash`, `tokenRaw`).
- **Token storage**: Session tokens and API tokens are persisted as SHA256 hashes only. The one exception is a device grant: `approve` stashes the minted token's raw value (`tokenRaw`) on the grant row until `consumeApproved` deletes it.
- **Credential redaction**: The `redactPeer` helper projects `PeerRow` to omit `token` and add `hasToken: boolean`; per its doc comment, whether a token is set is all any read surface (REST GET/POST/PATCH, MCP `list_peers`/`add_peer`) may know.

## Platform Notes

- **TypeScript/Web (libSQL)**: Storage is implemented via `createLibsqlStorage` in `../libsql/stores/`. It is the sole adapter permitted to speak to the libSQL driver and to query objects. Types like `GroupRow`, `UserRecord`, `DeploymentRow` are domain types that never reference the driver, connection handle, or generated row-inference aliases. Schema enforcement, unique-index guards, and retention pruning are adapter responsibilities. The adapter does not use `db.transaction` (unavailable over the HTTP connection mode); multi-statement operations rely on statement order or `db.batch`, and the last-admin and device-approve guards live inside single conditional statements. WAL checkpointing happens inside `runMaintenance` and is not exposed by this interface.
- **Swift**: Not implemented in source; this component is web-only (status-server is Node.js/libSQL).
- **Kotlin**: Not implemented in source; this component is web-only.
- **C#/WinUI 3**: Not implemented in source. Port via Windows App SDK `HttpClient` for any peer polling, `System.Text.Json` for serialization, `Windows.Storage` for local snapshots (if needed), `ObservableCollection` and `INotifyPropertyChanged` for reactive stores if binding to UI (not required by this interface). Use SqlClient or Entity Framework Core for SQL Server or SQLite; map domain types onto EF entities; expose stores as properties/methods on a composed class. Unlike libSQL's schema-as-contract approach, EF migrations govern schema change; ensure all domain-type fields have corresponding columns.

## Design Decisions

**Decision**: Stores are named for the concern the existing code expresses (Config, Auth, Token, Health, etc.) rather than an invented grouping.

**Rationale**: Each store is a discrete concern with its own contract; naming by concern makes the interface self-documenting and helps porting teams map their own persistence layer.

**Approved**: pending

---

**Decision**: Token and session storage is hash-only; raw values are shown to callers exactly once and never persisted, except the device grant's `tokenRaw`, held on the grant row only until the single-use consume.

**Rationale**: Hashing by default prevents accidental logging or leakage of secrets in error messages, logs, or database dumps. The caller is responsible for storing the raw value (e.g., as an Authorization header) immediately after mint.

**Approved**: pending

---

**Decision**: Page readers (readDeployActivityPage, readIssueOpenedPage) return `SourcePage<T>` with `floorMs` to handle pagination boundaries that cross multiple rows with the same timestamp.

**Rationale**: A LIMIT cut may split a tie group; the reader re-reads that group in full so a partial instant is never returned, and `floorMs` (null when the source is exhausted) informs the next cursor. This is a storage concern, not a caller concern.

**Approved**: pending

---

**Decision**: Last-admin protection is atomic; setUserRoleGuarded and deleteUserGuarded return 'blocked' rather than throwing.

**Rationale**: Race-free protection without requiring callers to catch exceptions; the return value signals the guard was hit.

**Approved**: pending

---

**Decision**: ConfiguredEndpoint is a flattened type combining endpoint, site, and group data; callers do not reconstruct it.

**Rationale**: Probes and the /api/live endpoint read this shape; the adapter performs the endpoint-site-group inner join once in `listActiveEndpoints`, so no caller repeats it.

**Approved**: pending
