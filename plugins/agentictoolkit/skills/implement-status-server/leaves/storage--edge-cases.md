<!-- leaf: implement-status-server/storage--edge-cases · source: status-server-storage.md -->

# Status Server Storage Boundary

**Rules** (cite as `implement-status-server/storage--edge-cases#<slug>`):

- `null-or-empty-inputs` MUST — Empty array inputs (list-active-endpoints with no active endpoints, record-observations with empty array, …
- `concurrent-writes-to-same-row` MUST — Database schema enforces uniqueness (e.g., the partial unique index allowing one open issue per target). The adapter's …
- `expired-sessions-and-tokens` MUST — resolveSession and validateApiToken with expired credentials MUST return null (not throw).
- `last-admin-protection` MUST — setUserRoleGuarded demoting the last admin and deleteUserGuarded deleting the last admin MUST return 'blocked' and MUST …
- `webhook-regression-guard` MUST — upsertDeployments from 'webhook' source MUST never roll back phases; see libsql implementation for COALESCE details.

## Edge Cases

- **Null or empty inputs**: Empty array inputs (list-active-endpoints with no active endpoints, record-observations with empty array, record-vercel-prod-states) MUST return empty result or be a no-op without error.
- **Nonexistent ids**: update methods return null, find/get user methods return undefined, delete methods returning void do nothing, `deleteUserGuarded`/`revokeApiToken`/`deleteApiToken` return false, and `retireEndpoint` returns both flags false — none throw.
- **Concurrent writes to same row**: Database schema enforces uniqueness (e.g., the partial unique index allowing one open issue per target). The adapter's own transaction handling governs atomicity; this interface does not expose transaction objects. Clients MUST NOT assume any ordering of concurrent writes.
- **Expired sessions and tokens**: resolveSession and validateApiToken with expired credentials MUST return null (not throw).
- **Last admin protection**: setUserRoleGuarded demoting the last admin and deleteUserGuarded deleting the last admin MUST return 'blocked' and MUST not proceed.
- **Cascading deletes**: deleteGroup and deleteSite cascade in application code and purge endpoint history; deleteEndpoint deletes only its own row; deleteUserGuarded deletes that user's sessions after the guarded delete succeeds.
- **Missing deploy project on endpoint**: An endpoint with a wired deployProject but no corresponding deploy row is a valid state; the adapter makes no automatic backfill.
- **Webhook regression guard**: upsertDeployments from 'webhook' source MUST never roll back phases; see libsql implementation for COALESCE details.
- **Pagination with stalled cursor**: a `PageCursor` with `strict: true` (the empty-id sentinel a stalled page mints) reads strictly before `beforeMs`, an ordinary cursor reads at-or-before it; when a page's LIMIT cuts through a group of rows sharing one timestamp, the page readers re-read that tie group in full, and `floorMs` is null when the page exhausted the source.
