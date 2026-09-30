<!-- leaf: implement-status-server-monitor-2/refresh-project-meta--edge-cases · source: status-server-monitor-refresh-project-meta.md -->

# Status Server Monitor Refresh Project Meta

## Edge Cases

- **Null/empty input**: an empty `meta` array on an `ok: true, configured: true`
  snapshot is valid and evicts every stored Vercel row (vector 5); an empty
  `meta` array on any other `ok`/`configured` combination performs neither an
  upsert nor an eviction attempt (vectors 4 and 8).
- **Boundary values**: a `meta` array crossing the storage layer's chunk sizes
  (`UPSERT_CHUNK_PROJECTS = 200`, `DELETE_CHUNK_NAMES = 500` in
  `deploy-store.ts`) is upserted and pruned across multiple chunked statements
  rather than one — the 400-project test vector exists specifically to cross
  the 200-row upsert chunk boundary twice over.
- **Concurrent access**: this file provides no mutual exclusion between
  overlapping calls to `syncVercelProjectMeta`/`refreshVercelProjectMeta`; see
  the open question on concurrent-invocation-not-guarded above.
- **Error states**: a rejected `Promise` from `storage.deploy.upsertProjectMeta`,
  `storage.deploy.listProjectMetaNames`, or `storage.deploy.deleteProjectMeta`
  is never caught inside this file — none of its three exported functions
  contains a `try`/`catch` — so the rejection propagates unchanged to the
  caller. This is a fact about this file, not a swallowed error: what the
  monitor cycle or the request route does with that rejection is decided by
  that external caller, not by this module.
- **Offline/disconnected state**: with no `VERCEL_API_TOKEN`,
  `refreshVercelProjectMeta` reports `{ ok: false, configured: false, pruned:
  [] }` and makes zero network attempts (fail-closed) rather than attempting a
  fetch that would fail; a caller distinguishes this `configured: false` case
  from a `configured: true` fetch that failed, since only the latter should be
  surfaced as an integration problem.
