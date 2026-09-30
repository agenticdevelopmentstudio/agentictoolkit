<!-- leaf: implement-hub-domain-1/data--test-vectors-part-3 · source: hub-domain-data.md -->

# Hub Domain Data — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-data-062 | resource-list-reload-identity-guard | a new `load` function identity is passed with the same `cacheKey`/tenant | the in-flight request is cancelled and refetched (`use-resource-list.test.tsx`) |
| hub-domain-data-063 | resource-list-reload-rethrows | `reload()` when the underlying `refetch()` resolves with an error | `reload()`'s returned promise rejects with that error |
| hub-domain-data-064 | resource-list-set-items-writes-through | `setItems(newRows)` | `client.setQueryData(resourceListKey(...), newRows)` is called |
| hub-domain-data-065 | resource-list-is-fetching-derivation | query state `{ isFetching: false, isPending: true }` | `isFetching === true` |
| hub-domain-data-066 | resource-list-error-status-derivation | `load` rejects with a 409-shaped error | `errorStatus === 409` |
| hub-domain-data-067 | resource-list-error-message-fallback | `load` rejects with a plain object (not an `Error`) | `error === 'Failed to load.'` |
| hub-domain-data-068 | make-entity-delete-handler-sequence | `del` resolves, `readLastId(basePath) === id` | `clearLastId` is called, then `router.push` to `${basePath}/all` with `{ scroll: false }`, then `reload()` is attempted (`use-resource-list.test.tsx`) |
| hub-domain-data-069 | make-entity-delete-handler-sequence | `del` resolves, `readLastId(basePath) !== id` | `clearLastId` is NOT called; `router.push` and `reload()` still run |
| hub-domain-data-070 | make-entity-delete-handler-del-not-caught | `del` rejects | the handler's returned promise rejects; `router.push` is never called |
| hub-domain-data-071 | make-entity-delete-handler-del-not-caught | `del` resolves but the subsequent `reload()` rejects | the handler's returned promise still resolves (the `reload()` rejection is swallowed) |
| hub-domain-data-072 | workspace-prefs-cache-key | `writeCachedWorkspace('acme')` with `storageKeyPrefix: 'adh'` | writes `localStorage['adh:home:workspace']` (`workspace-prefs.test.ts`) |
| hub-domain-data-073 | read-cached-workspace-ssr-safe | `readCachedWorkspace()` with `window` undefined | returns a safe empty result, no throw |
| hub-domain-data-074 | write-cached-workspace-swallow | `writeCachedWorkspace('acme')` when storage throws | resolves without throwing |
| hub-domain-data-075 | workspace-prefs-get-unwraps | `workspacePrefsApi.get()` when the server returns `404` | resolves to `{}`, never throws (`workspace-prefs.test.ts`) |
| hub-domain-data-076 | workspace-prefs-get-unwraps | `workspacePrefsApi.get()` when the server returns `{ prefs: { slug: 'acme' } }` | resolves to `{ slug: 'acme' }` |
| hub-domain-data-077 | workspace-prefs-put-full-replace | `workspacePrefsApi.put({ slug: 'acme' })` | issues `PUT /api/me/workspace-prefs` with body `{ slug: 'acme' }` (`workspace-prefs.test.ts`) |
| hub-domain-data-078 | workspaces-query-key-constant | `WORKSPACES_QUERY_KEY` | `['workspaces']` |
| hub-domain-data-079 | notify-workspaces-changed-dual-invalidate | `notifyWorkspacesChanged()` | `invalidateQueries({ queryKey: ['workspaces'] })` is called, AND a predicate-based `invalidateQueries` call accepts `['resource-list', null, 'workspaces']` and rejects `['resource-list', null, 'organizations']` (`workspaces-changed.test.ts`) |
| hub-domain-data-080 | notify-workspaces-changed-swallows | `notifyWorkspacesChanged()` when `client.invalidateQueries` rejects | does not throw or produce an unhandled rejection |
| hub-domain-data-081 | notify-workspaces-changed-dispatches-event | `onWorkspacesChanged(listener)` then `notifyWorkspacesChanged()` | `listener` is called exactly once (`workspaces-changed.test.ts`) |
| hub-domain-data-082 | on-workspaces-changed-subscribe | subscribe, then call the returned unsubscribe, then `notifyWorkspacesChanged()` again | `listener` is not called again (`workspaces-changed.test.ts`) |
| hub-domain-data-083 | check-workspace-slug-available | `checkWorkspaceSlugAvailable('a b')` | issues `GET /api/auth/slug-available/a%20b` |
| hub-domain-data-084 | workspaces-api-list-drops-team-rows | `workspacesApi.list()` over rows including one with `type: 'team'` | the `'team'` row is excluded from the result |
| hub-domain-data-085 | workspaces-api-list-ordering | `workspacesApi.list()` over one individual row and two organization rows named `'Zeta'` and `'Acme'` | order is `[individual, 'Acme', 'Zeta']` |
