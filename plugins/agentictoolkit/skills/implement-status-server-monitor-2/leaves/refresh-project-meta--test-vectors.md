<!-- leaf: implement-status-server-monitor-2/refresh-project-meta--test-vectors · source: status-server-monitor-refresh-project-meta.md -->

# Status Server Monitor Refresh Project Meta

## Conformance Test Vectors

Traced to `test/refresh-project-meta.int.test.ts`'s own assertions unless noted as source-only.

1. `syncVercelProjectMeta(storage, { meta: [META('live-site','renamed.example.com'), META('new-site')], ok: true, configured: true })` against a table already holding Vercel rows `live-site` and `deleted-site` (plus an untouched Cloudflare row) → `pruned: ['deleted-site']`, `live: {'live-site','new-site'}`; `deleted-site` is gone, `live-site`'s domain is updated to `renamed.example.com`, `new-site` is inserted, and the Cloudflare row is untouched.
2. `syncVercelProjectMeta(storage, { meta: Array(400 projects), ok: true, configured: true })` → all 400 upserted in chunks and `pruned` covers the two previously-stored names (`deleted-site`, `live-site`) that are absent from the 400; a follow-up call with `meta: []` prunes all 400 in chunks, leaving only the untouched Cloudflare row.
3. `syncVercelProjectMeta(storage, { meta: [META('new-site')], ok: false, configured: true })` (a partial/budget-truncated read) → `pruned: []`, `live: null`; `new-site` is still upserted, and the previously-stored `live-site`/`deleted-site` rows are both left in place.
4. `syncVercelProjectMeta(storage, { meta: [], ok: true, configured: false })` (the exact shape `fetchVercelProductionStates` returns with no token) → `pruned: []`, `live: null`; no row is touched.
5. `syncVercelProjectMeta(storage, { meta: [], ok: true, configured: true })` (an authenticated, complete read reporting zero projects) → every stored Vercel row is pruned (`pruned` sorts to `['deleted-site','live-site']`), leaving only the untouched Cloudflare row.
6. `refreshVercelProjectMeta(storage, { VERCEL_API_TOKEN: 'tok' })` against a live fetch mock that returns only `live-site` → `{ ok: true, configured: true, pruned: ['deleted-site'] }`, the stored rows reduce to `['live-site']`, and the outgoing `/v9/projects` request URL contains `latestDeployments=1`.
7. `refreshVercelProjectMeta(storage, {})` (no `VERCEL_API_TOKEN`) against a fetch mock that throws if called at all → `{ ok: false, configured: false, pruned: [] }`, the stored row count is unchanged, and the fetch mock is never invoked.
8. (source-only) `syncVercelProjectMeta(storage, { meta: [], ok: false, configured: true })` → `pruned: []`, `live: null`, and no upsert call at all, since `meta.length` is `0`; distinguishing this from vector 5 pins that `ok` (not merely `configured`) gates the eviction attempt.
9. (source-only) `refreshVercelProjectMeta(storage, { VERCEL_API_TOKEN: 'tok' })` against a fetch that returns `{ ok: true, meta: [], states: [], deploys: [] }` → `configured: true` (token present) but the reconcile still runs and evicts every stored Vercel row, exercising the same "last project deleted" path as vector 5 but reached through the full `refreshVercelProjectMeta` fetch-then-sync composition rather than calling `syncVercelProjectMeta` directly.
10. (source-only) `refreshVercelProjectMetaFromConfig(storage, config)` where `config.secrets.VERCEL_API_TOKEN` is set but `config.credentials.VERCEL_API_TOKEN` is not → the token still resolves and the refresh proceeds, because resolution goes through `providerConn`'s `config.secrets` lookup, not `config.credentials`.
