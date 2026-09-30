<!-- leaf: implement-status-server/storage--part-2 · source: status-server-storage.md -->

# Status Server Storage Boundary — continued (part 2)

**Rules** (cite as `implement-status-server/storage--part-2#<slug>`):

- `list-site-groups` MUST
- `create-group` MUST
- `update-group` MUST
- `delete-group` MUST
- `list-sites` MUST
- `create-site` MUST
- `update-site` MUST
- `delete-site` MUST
- `list-endpoints` MUST
- `create-endpoint` MUST
- `update-endpoint` MUST
- `delete-endpoint` MUST
- `purge-endpoint-history` MUST
- `list-active-endpoints` MUST
- `reconcile-orphaned-endpoints` MUST
- `retire-endpoint` MUST
- `list-integrations` MUST
- `create-integration` MUST
- `update-integration` MUST
- `delete-integration` MUST
- `list-ignored-projects` MUST
- `add-ignored-project` MUST
- `add-ignored-projects` MUST
- `remove-ignored-project` MUST
- `list-peers` MUST
- `create-peer` MUST
- `update-peer` MUST
- `delete-peer` MUST
- `find-user-by-email` MUST
- `find-user-by-github-id` MUST
- `get-user-by-id` MUST
- `create-user` MUST
- `attach-github-id` MUST
- `list-users` MUST
- `set-user-role-guarded` MUST
- `delete-user-guarded` MUST
- `count-admins` MUST
- `create-session` MUST
- `resolve-session` MUST
- `revoke-session` MUST
- `mint-api-token` MUST
- `validate-api-token` MUST
- `list-api-tokens` MUST
- `revoke-api-token` MUST
- `delete-api-token` MUST
- `latest-checks` MUST
- `bad-run-onsets` MUST
- `record-checks` MUST
- `checks-summary` MUST
- `last-checked-at-ms` MUST

## Behavioral Requirements

### Config Store

- **list-site-groups**: MUST return all `GroupRow` objects with no filtering.
- **create-group**: MUST accept `{ name, slug, retentionDays? }`, persist as a `GroupRow` with server-generated `id`, `createdAt`, `updatedAt`, and MUST return the persisted row.
- **update-group**: MUST accept `id` and a partial patch, MUST return the updated `GroupRow` or null if no row exists.
- **delete-group**: MUST accept `id` and remove the row. The libSQL adapter cascades in application code (libSQL over HTTP does not enforce ON DELETE CASCADE): it collects every endpoint of the group's sites, purges their history via `purgeEndpointHistory`, then deletes those endpoints, the sites, and finally the group.
- **list-sites**: MUST return all `SiteRow` objects with no filtering.
- **create-site**: MUST accept `{ name, slug, siteGroupId }`, MUST return a persisted `SiteRow` with server-generated `id`, `createdAt`, `updatedAt`.
- **update-site**: MUST accept `id` and a partial patch, MUST return updated `SiteRow` or null.
- **delete-site**: MUST accept `id` and remove the row. The adapter cascades in application code: it purges the site's endpoints' history, deletes those endpoints, then deletes the site.
- **list-endpoints**: MUST return all `EndpointRow` objects; if `siteId` is provided, MUST filter by `siteId`.
- **create-endpoint**: MUST accept required `siteId`, `url` and optional fields (kind, environment, platform, deployProject, deployProjectId, ignoreProjectWarning, expectedStatus, expectBody, dnsCheckA, dnsCheckAaaa, dnsCheckCname, checkIntervalSeconds, isActive, monitorHttp, monitorDeploys), MUST return persisted `EndpointRow` with defaults applied.
- **update-endpoint**: MUST accept `id` and a partial patch of the mutable endpoint fields (every `createEndpoint` field except `siteId`; `id`, `siteId` and the timestamps are not patchable), MUST stamp `updatedAt`, MUST return updated row or null.
- **delete-endpoint**: MUST accept `id` and remove the row only; it does not purge the endpoint's history or resolve its issues (`retireEndpoint` does).
- **purge-endpoint-history**: MUST accept array of endpoint ids, MUST delete all `health_checks` and `metrics_hourly` rows for those ids and MUST resolve (not delete) every still-open issue targeting those ids with reason 'unmonitored'; already-resolved issues keep their original `resolvedAt`. It is a no-op on an empty list. The three statements run sequentially, not in one transaction.
- **list-active-endpoints**: MUST return only `ConfiguredEndpoint` rows with `isActive: true`, flattened with site and group names via an inner join (an endpoint whose site or group is gone is dropped); each row's `slug` is the endpoint's row id, and a null `ignoreProjectWarning` reads as false.
- **reconcile-orphaned-endpoints**: MUST delete endpoints not owned by a configured site (a site joined to an existing group) and sites whose group is gone, and MUST return `{ endpoints: number, sites: number, prunedEndpointIds: string[] }` counted from the rows actually deleted. It MUST do nothing (return zero counts) when no orphans exist or when there are zero configured sites. A failure during the deletes is logged with `console.error` and the counts gathered so far are returned rather than thrown.
- **retire-endpoint**: MUST delete the endpoint, purge its history, then delete its parent site if and only if the site has no endpoints left (one conditional delete on fresh state), and MUST return `{ endpointDeleted: boolean, siteDeleted: boolean }`; an unknown id returns both false. The statements are not one transaction; the endpoint row is deleted first so a later failure leaves only orphaned history for the reconcile and retention prune to clean.
- **list-integrations**: MUST return all `IntegrationRow` objects.
- **create-integration**: MUST accept `{ platform, label, config?, tokenEnvVar?, secretRef?, isActive? }`, MUST return persisted `IntegrationRow`.
- **update-integration**: MUST accept `id` and partial patch, MUST return updated row or null.
- **delete-integration**: MUST accept `id` and remove the row. When the deleted row was the last active integration speaking for its platform-health source, the adapter also sets that source's `platform_health_state.configured` to false in the same `db.batch`, without touching `updatedAt`.
- **list-ignored-projects**: MUST return all `IgnoredProject` entries (platform, projectName); a missing table (error text matching no such table / does not exist / not found) reads as an empty list, and any other error is rethrown.
- **add-ignored-project**: MUST accept `platform` and `projectName`, MUST persist the entry; an existing entry is left as is (insert-or-ignore).
- **add-ignored-projects**: MUST accept array of `IgnoredProject` entries and persist all in one insert-or-ignore statement; a no-op on an empty array.
- **remove-ignored-project**: MUST accept `platform` and `projectName`, MUST remove the matching entry.
- **list-peers**: MUST return all `PeerRow` objects.
- **create-peer**: MUST accept `{ label, baseUrl, token?, isActive? }`, MUST store `baseUrl` normalized through `normalizePeerBaseUrl`, MUST return persisted `PeerRow`.
- **update-peer**: MUST accept `id` and partial patch (a supplied `baseUrl` is normalized through `normalizePeerBaseUrl`), MUST return updated row or null.
- **delete-peer**: MUST accept `id` and remove the row.

### Auth Store

- **find-user-by-email**: MUST accept an email string, MUST lowercase it before the lookup, MUST return `UserRecord` if found or undefined.
- **find-user-by-github-id**: MUST accept a GitHub id string, MUST return `UserRecord` if found or undefined.
- **get-user-by-id**: MUST accept a user id, MUST return `UserRecord` if found or undefined.
- **create-user**: MUST accept `{ email, displayName, role, passwordHash?, githubId? }`, MUST store the email lowercased, MUST return persisted `UserRecord` with server-generated `id`, `createdAt`. Role is typed as `UserRole` ('pending', 'viewer', 'admin'). A duplicate email or GitHub id raises the driver's unique-index error, which `isUniqueViolation` recognizes.
- **attach-github-id**: MUST accept `userId` and `githubId`, MUST return updated `UserRecord` or undefined if no such user.
- **list-users**: MUST return all users mapped to public `AuthUser` (no password hash).
- **set-user-role-guarded**: MUST accept `id` and new `role`, MUST atomically prevent demotion of the last admin, MUST return updated `AuthUser` or 'blocked' or undefined.
- **delete-user-guarded**: MUST accept `id`, MUST atomically prevent deletion of the last admin, MUST delete that user's sessions only after the guarded delete succeeded, MUST return true on success, 'blocked' if last admin, or false if no such user.
- **count-admins**: MUST return the number of users with role 'admin'.
- **create-session**: MUST accept `userId` and optional `ttlMs` (time-to-live milliseconds, default 30 days in the adapter), MUST return the raw opaque cookie token (32 random bytes as hex), MUST persist only its SHA256 hash.
- **resolve-session**: MUST accept an optional token string, MUST return the live `AuthUser` if valid and not expired, or null if the token is undefined/empty, unknown, expired, or its user no longer exists; an expired session row is deleted when encountered.
- **revoke-session**: MUST accept an optional token, MUST delete the session row so `resolveSession` returns null thereafter; a no-op on an undefined or empty token.

### Token Store

- **mint-api-token**: MUST accept `{ name, role, kind?, createdBy, expiresAt? }` where `role` is 'admin' or 'user' and `kind` is 'minted' or 'device', MUST return `{ meta: ApiTokenMeta, raw: string }` with the raw value shown exactly once; MUST persist only the SHA256 hash. Raw value MUST be `TOKEN_PREFIX` ('sts_') followed by 32 random bytes as hex; the first `PREFIX_LEN` (12) characters are stored as the display `prefix`; `kind` defaults to 'minted' and `expiresAt` to null.
- **validate-api-token**: MUST accept raw bearer token string, MUST return null without a lookup when it does not start with `TOKEN_PREFIX`, MUST return `TokenPrincipal` if found, not revoked, and not expired (`expiresAt` at or before now counts as expired), MUST bump `lastUsedAt` on success, MUST return null on validation failure.
- **list-api-tokens**: MUST return all `ApiTokenMeta` entries, newest first (no raw values or hashes).
- **revoke-api-token**: MUST accept token `id`, MUST soft-revoke by setting `revokedAt`, MUST return false if no such token; re-revoking an already-revoked token returns true and restamps `revokedAt`.
- **delete-api-token**: MUST accept token `id`, MUST hard-delete the row, MUST return false if no such token.

### Health Store

- **latest-checks**: MUST accept array of endpoint slugs, MUST return the most recent `LatestCheckRow` per slug (with `checked_at` in epoch SECONDS, `dns_ok` as 0 or 1).
- **bad-run-onsets**: MUST accept array of slugs, MUST return one `BadRunOnsetRow` per slug that has a current unbroken bad run, `since` being the epoch-SECONDS timestamp of the oldest check newer than the slug's last healthy check (a slug never healthy starts at its first check). A slug with no bad run, or no checks, contributes no row.
- **record-checks**: MUST accept array of `HealthCheckInput` objects, MUST persist each as one `health_checks` row; a no-op on an empty array.
- **checks-summary**: MUST return `{ samples: number, services: number }` — total checks recorded and distinct services ever checked.
- **last-checked-at-ms**: MUST return epoch milliseconds of the most recent check's `checked_at`, or null if no checks exist.

