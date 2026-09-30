<!-- leaf: implement-hub-domain-1/data--test-vectors-part-2 · source: hub-domain-data.md -->

# Hub Domain Data — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-data-001 | enc-is-encode-uri-component | `enc('a b')` | `'a%20b'` |
| hub-domain-data-002 | compact-drops-undefined-preserves-null | `compact({ a: 1, b: undefined, c: null })` | `{ a: 1, c: null }` |
| hub-domain-data-003 | compact-non-mutating | `const body = { a: undefined }; compact(body); body` | `body` still has key `a` with value `undefined` |
| hub-domain-data-004 | narrow-fallback | `narrow('x', ['a', 'b'] as const, 'a')` | `'a'` (fallback, since `'x'` is not allowed) |
| hub-domain-data-005 | scope-by-owner-filters | `scopeByOwner([{o:1},{o:2}], 1, r => r.o)` | `[{o:1}]` |
| hub-domain-data-006 | sort-by-text-non-mutating | `const rows = [{n:'b'},{n:'a'}]; sortByText(rows, 'n'); rows` | returned array is `[{n:'a'},{n:'b'}]`; `rows` itself is unchanged |
| hub-domain-data-007 | workspace-query-encodes | `workspaceQuery({ workspace: 'a b' })` | `'?workspace=a%20b'` |
| hub-domain-data-008 | workspace-query-encodes | `workspaceQuery(undefined)` | `''` |
| hub-domain-data-009 | data-config-default | `dataConfig()` called with no prior `configureData` | `{ storageKeyPrefix: 'adh' }` |
| hub-domain-data-010 | configure-data-merges | `configureData({ storageKeyPrefix: 'x' })` then `dataConfig()` | `{ storageKeyPrefix: 'x' }` |
| hub-domain-data-011 | ftd-key-shape | `writeLastId('projects', 'p-1')` with `storageKeyPrefix: 'adh'` | writes `localStorage['adh:ftd:projects:lastId']` (`ftd-storage.test.ts`) |
| hub-domain-data-012 | read-last-id-null-safe | `readLastId('projects')` with nothing stored | `null` |
| hub-domain-data-013 | read-last-id-null-safe | `readLastId('projects')` when `localStorage.getItem` throws | `null`, no exception propagates |
| hub-domain-data-014 | write-last-id-swallow | `writeLastId('projects', 'p-1')` when `localStorage.setItem` throws | resolves without throwing |
| hub-domain-data-015 | clear-last-id-swallow | `clearLastId('projects')` when `localStorage.removeItem` throws | resolves without throwing |
| hub-domain-data-016 | read-view-mode-ssr-safe | `readViewMode('projects', 'root')` with `window` undefined | `'cards'` |
| hub-domain-data-017 | read-view-mode-validates | `readViewMode('projects', 'root')` with `'grid'` stored | `'cards'` (invalid value rejected) (`ftd-storage.test.ts`) |
| hub-domain-data-018 | read-view-mode-validates | `readViewMode('projects', 'root')` with `'list'` stored | `'list'` |
| hub-domain-data-019 | write-view-mode-swallow | `writeViewMode('projects', 'root', 'list')` when storage throws | resolves without throwing |
| hub-domain-data-020 | http-re-exports-auth | `import { authedJson } from '../http'` | resolves to the same function `@agentic-toolkit/auth/client` exports (`http.test.ts`) |
| hub-domain-data-021 | http-status-duck-typed | `httpStatus(Object.assign(new Error('x'), { status: 404 }))` | `404` |
| hub-domain-data-022 | http-status-duck-typed | `httpStatus(new Error('x'))` | `undefined` |
| hub-domain-data-023 | client-refusal-shape | `clientRefusal('bad input')` | an `Error` with `message === 'bad input'` and `status === 400` (`http.test.ts`) |
| hub-domain-data-024 | is-not-found-derivation | `isNotFound(Object.assign(new Error(), { status: 404 }))` | `true` |
| hub-domain-data-025 | is-conflict-derivation | `isConflict(Object.assign(new Error(), { status: 409 }))` | `true` |
| hub-domain-data-026 | is-forbidden-derivation | `isForbidden(Object.assign(new Error(), { status: 403 }))` | `true` |
| hub-domain-data-027 | is-service-unavailable-derivation | `isServiceUnavailable(Object.assign(new Error(), { status: 503 }))` | `true` |
| hub-domain-data-028 | err-msg-fallback | `errMsg(new Error('boom'), 'fallback')` | `'boom'` |
| hub-domain-data-029 | err-msg-fallback | `errMsg('not an error', 'fallback')` | `'fallback'` |
| hub-domain-data-030 | rethrow-conflict-friendly | `rethrowConflict(new Error('a project with this name already exists'), 'Pick another name')` | throws `Error('Pick another name')` (`http.test.ts`) |
| hub-domain-data-031 | rethrow-conflict-friendly | `rethrowConflict(new Error('network down'), 'Pick another name')` | rethrows the original `Error('network down')` |
| hub-domain-data-032 | decode-jwt-claims-shape | `decodeJwtClaims('not-a-jwt')` (no dots) | `null` (`tenant.test.ts`) |
| hub-domain-data-033 | decode-jwt-claims-shape | `decodeJwtClaims('a.b.c')` with `b` a valid base64url JSON object | the decoded object |
| hub-domain-data-034 | decode-jwt-claims-null-safe | `decodeJwtClaims('a.!!!.c')` (payload not valid base64url) | `null` |
| hub-domain-data-035 | tenant-id-priority | `tenantIdFromToken` on a token whose claims are `{ ecosystem_id: 'e1', tenant_id: 't1' }` | `'e1'` (`tenant.test.ts`) |
| hub-domain-data-036 | tenant-id-priority | `tenantIdFromToken` on a token whose claims are `{ tenant_id: 't1', project_id: 'p1' }` | `'t1'` |
| hub-domain-data-037 | tenant-id-priority | `tenantIdFromToken(null)` | `null` |
| hub-domain-data-038 | use-tenant-id-memoized | `useTenantId()` rendered twice with the same underlying token | returns the same `tenantId` value both renders without re-decoding (`tenant.test.ts`) |
| hub-domain-data-039 | resource-item-key-shape | `resourceItemKey('projects', 't1', 'p-1')` | `['resource-item', 't1', 'projects', 'p-1']` |
| hub-domain-data-040 | revalidate-resource-items-delegates | `revalidateResourceItems(k => k[2] === 'projects')` | invalidates every `['resource-item', *, 'projects', *]` entry |
| hub-domain-data-041 | resource-item-query-key-includes-tenant | `useResourceItemQuery('projects', 'p-1', load)` under tenant `'t1'` | query key `['resource-item', 't1', 'projects', 'p-1']` (`use-resource-item.test.tsx`) |
| hub-domain-data-042 | resource-item-enabled-gate | `useResourceItemQuery('projects', null, load)` | `load` is never invoked (`use-resource-item.test.tsx`) |
| hub-domain-data-043 | resource-item-error-reporting-gated | `load` rejects with `reportErrors` omitted (defaults `true`) | `reportUnexpectedAuthError` is called with `{ feature: 'resource-item', step: 'load', basePath: 'projects' }` before the rejection propagates |
| hub-domain-data-044 | resource-item-error-reporting-gated | `load` rejects with `{ reportErrors: false }` | `reportUnexpectedAuthError` is NOT called; the rejection still propagates |
| hub-domain-data-045 | resource-item-no-retry | `load` rejects once | the hook does not retry; `error` is set after the first failure |
| hub-domain-data-046 | resource-item-gc-time | inspecting the query's resolved options | `gcTime === RESOURCE_GC_TIME` (1,800,000ms) |
| hub-domain-data-047 | resource-item-placeholder-data | `useResourceItemQuery('projects', 'p-1', load, { seedFrom: () => partialRow })` before `load` settles | `item === partialRow` and `isSettled === false` (`use-resource-item.test.tsx`) |
| hub-domain-data-048 | resource-item-is-settled-sticky | `load` resolves, then a background refetch begins for the same `id` | `isSettled` remains `true` throughout the refetch (`use-resource-item.test.tsx`) |
| hub-domain-data-049 | resource-item-is-missing-derivation | `load` rejects with a 404-shaped error | `isMissing === true` |
| hub-domain-data-050 | resource-item-error-message-fallback | `load` rejects with a plain string `'x'` (not an `Error`) | `error === 'Failed to load.'` |
| hub-domain-data-051 | resource-item-reload-null-id-behavior | `useResourceItemQuery('projects', null, load).reload()` | open question — see Behavioral Requirements; not exercised by `use-resource-item.test.tsx` |
| hub-domain-data-052 | resource-item-writer-write-or-evict | `useResourceItemWriter('projects')(id, row)` | `client.setQueryData(resourceItemKey(...), row)` is called (`use-resource-item.test.tsx`) |
| hub-domain-data-053 | resource-item-writer-write-or-evict | `useResourceItemWriter('projects')(id, null)` | `client.removeQueries({ queryKey: resourceItemKey(...) })` is called, not a `setQueryData(..., null)` |
| hub-domain-data-054 | resource-item-prefetch-never-throws | `useResourceItemPrefetch('projects', load)(id)` where `load` rejects | the returned promise/call never rejects |
| hub-domain-data-055 | resource-item-prefetch-cleanup-conditional | a prefetch's `load` rejects, then a concurrent mount's `load` for the same id resolves before the prefetch's cleanup runs | the entry is left holding the successful data, not removed (`use-resource-item.test.tsx`) |
| hub-domain-data-056 | resource-list-key-shape | `resourceListKey('projects', 't1')` | `['resource-list', 't1', 'projects']` |
| hub-domain-data-057 | revalidate-resources-delegates | `revalidateResources(k => k[2] === 'workspaces')` | invalidates every `['resource-list', *, 'workspaces']` entry (`workspaces-changed.test.ts`) |
| hub-domain-data-058 | resource-list-error-reporting-gated | `load` rejects with `reportErrors` omitted | `reportUnexpectedAuthError` is called with `{ feature: 'resource-list', step: 'load', basePath: 'projects' }` |
| hub-domain-data-059 | resource-list-no-retry | `load` rejects once | the hook does not retry |
| hub-domain-data-060 | resource-list-gc-time | inspecting the query's resolved options | `gcTime === RESOURCE_GC_TIME` |
| hub-domain-data-061 | resource-list-reload-identity-guard | the same `load` function identity is passed across two renders | no cancel/refetch occurs (`use-resource-list.test.tsx`) |
