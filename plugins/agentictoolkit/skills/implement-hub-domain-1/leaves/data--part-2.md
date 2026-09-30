<!-- leaf: implement-hub-domain-1/data--part-2 · source: hub-domain-data.md -->

# Hub Domain Data — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/data--part-2#<slug>`):

- `enc-is-encode-uri-component` MUST
- `compact-drops-undefined-preserves-null` MUST
- `compact-non-mutating` MUST
- `narrow-fallback` MUST
- `scope-by-owner-filters` MUST
- `sort-by-text-non-mutating` MUST
- `workspace-query-encodes` MUST
- `data-config-default` MUST
- `configure-data-merges` MUST
- `ftd-key-shape` MUST
- `read-last-id-null-safe` MUST
- `write-last-id-swallow` MUST
- `clear-last-id-swallow` MUST
- `read-view-mode-ssr-safe` MUST
- `read-view-mode-validates` MUST
- `write-view-mode-swallow` MUST
- `http-re-exports-auth` MUST
- `http-status-duck-typed` MUST
- `client-refusal-shape` MUST
- `is-not-found-derivation` MUST
- `is-conflict-derivation` MUST
- `is-forbidden-derivation` MUST
- `is-service-unavailable-derivation` MUST
- `err-msg-fallback` MUST
- `rethrow-conflict-friendly` MUST
- `decode-jwt-claims-shape` MUST
- `decode-jwt-claims-null-safe` MUST
- `tenant-id-priority` MUST
- `use-tenant-id-memoized` MUST
- `resource-item-key-shape` MUST
- `revalidate-resource-items-delegates` MUST
- `resource-item-query-key-includes-tenant` MUST
- `resource-item-enabled-gate` MUST
- `resource-item-error-reporting-gated` MUST
- `resource-item-no-retry` MUST
- `resource-item-gc-time` MUST
- `resource-item-placeholder-data` MUST
- `resource-item-is-settled-sticky` MUST
- `resource-item-is-missing-derivation` MUST
- `resource-item-error-message-fallback` MUST
- `resource-item-writer-write-or-evict` MUST
- `resource-item-prefetch-never-throws` MUST
- `resource-item-prefetch-no-retry` MUST
- `resource-item-prefetch-cleanup-conditional` MUST
- `resource-list-key-shape` MUST
- `revalidate-resources-delegates` MUST
- `resource-list-error-reporting-gated` MUST

## Behavioral Requirements

- **enc-is-encode-uri-component**: `enc` MUST be an alias for
  `encodeURIComponent` (`client-helpers.ts`).
- **compact-drops-undefined-preserves-null**: `compact(body)` MUST return a
  new object containing every key of `body` whose value is not `undefined`,
  and MUST preserve any key whose value is `null` (`client-helpers.ts`).
- **compact-non-mutating**: `compact` MUST NOT mutate its input `body`
  (`client-helpers.ts`).
- **narrow-fallback**: `narrow(value, allowed, fallback)` MUST return `value`
  (typed as `T`) when `allowed` includes `value`, and MUST return `fallback`
  otherwise (`client-helpers.ts`).
- **scope-by-owner-filters**: `scopeByOwner(rows, ownerId, ownerOf)` MUST
  return exactly the rows of `rows` for which `ownerOf(row) === ownerId`
  (`client-helpers.ts`).
- **sort-by-text-non-mutating**: `sortByText(rows, key)` MUST return a new
  array of `rows` ordered by `row[key]` using locale-aware comparison, and
  MUST NOT mutate `rows` (`client-helpers.ts`).
- **workspace-query-encodes**: `workspaceQuery(opts)` MUST return
  `` `?workspace=${encodeURIComponent(opts.workspace)}` `` when
  `opts?.workspace` is a non-empty string, and MUST return `''` when it is
  absent or empty (`client-helpers.ts`).
- **data-config-default**: `dataConfig()` MUST return
  `{ storageKeyPrefix: 'adh' }` before `configureData` has ever been called
  (`config.ts`).
- **configure-data-merges**: `configureData(partial)` MUST shallow-merge
  `partial` onto the current config, leaving any field `partial` omits
  unchanged (`config.ts`).
- **ftd-key-shape**: every FTD storage key MUST be built as
  `` `${dataConfig().storageKeyPrefix}:ftd:${basePath}:${name}` ``
  (`ftd-storage.ts`).
- **read-last-id-null-safe**: `readLastId(basePath)` MUST return the stored
  id, and MUST return `null` when unset or when reading storage throws
  (`ftd-storage.ts`).
- **write-last-id-swallow**: `writeLastId(basePath, id)` MUST swallow any
  exception thrown while writing storage (`ftd-storage.ts`).
- **clear-last-id-swallow**: `clearLastId(basePath)` MUST remove the stored
  id and MUST swallow any exception thrown while doing so (`ftd-storage.ts`).
- **read-view-mode-ssr-safe**: `readViewMode(basePath, name)` MUST return
  `'cards'` when `window` is `undefined` (`ftd-storage.ts`).
- **read-view-mode-validates**: `readViewMode` MUST return the stored value
  only when it is exactly `'list'` or `'cards'`, and MUST return `'cards'`
  for any other stored value, including absence or a reading error
  (`ftd-storage.ts`).
- **write-view-mode-swallow**: `writeViewMode(basePath, name, mode)` MUST
  swallow any exception thrown while writing storage (`ftd-storage.ts`).
- **http-re-exports-auth**: `http.ts` MUST re-export `authedJson`,
  `authedRequest`, `extractErrorMessage`, `readErrorMessage`,
  `tokensFromResponse`, `readAccessToken`, `readTokenSubject`,
  `decodeBase64UrlJson`, and the type `BackendTokenFields` unchanged from
  `@agentic-toolkit/auth/client` (`http.ts`) — their contract is documented
  by the `auth-client` recipe, not restated here.
- **http-status-duck-typed**: `httpStatus(err)` MUST return `err.status`
  when `err` is an `Error` carrying a numeric `status` property, and MUST
  return `undefined` otherwise, without ever checking `instanceof` against a
  specific error class (`http.ts`).
- **client-refusal-shape**: `clientRefusal(message, status = 400)` MUST
  return an `Error` whose `message` is `message` and whose `status` property
  is `status` (`http.ts`).
- **is-not-found-derivation**: `isNotFound(err)` MUST return
  `httpStatus(err) === 404` (`http.ts`).
- **is-conflict-derivation**: `isConflict(err)` MUST return
  `httpStatus(err) === 409` (`http.ts`).
- **is-forbidden-derivation**: `isForbidden(err)` MUST return
  `httpStatus(err) === 403` (`http.ts`).
- **is-service-unavailable-derivation**: `isServiceUnavailable(err)` MUST
  return `httpStatus(err) === 503` (`http.ts`).
- **err-msg-fallback**: `errMsg(err, fallback)` MUST return a message
  derived from `err` when one can be extracted, and MUST return `fallback`
  otherwise (`http.ts`).
- **rethrow-conflict-friendly**: `rethrowConflict(err, friendly)` MUST throw
  a new `Error(friendly)` when `errMsg(err, '')` matches `/already exists/i`,
  and MUST rethrow `err` unchanged otherwise (`http.ts`).
- **decode-jwt-claims-shape**: `decodeJwtClaims(token)` MUST split `token`
  on `.` and return `null` unless the result has exactly 3 parts with a
  non-empty second part, and otherwise MUST return `decodeBase64UrlJson` of
  that second part (`tenant.ts`).
- **decode-jwt-claims-null-safe**: `decodeJwtClaims` MUST return `null` when
  `decodeBase64UrlJson` fails to decode the payload segment — this case is
  handled entirely by `decodeBase64UrlJson`'s own null-on-any-failure
  contract (see the `auth-client` recipe), not re-implemented here
  (`tenant.ts`).
- **tenant-id-priority**: `tenantIdFromToken(token)` MUST return, in order,
  `ecosystem_id`, else `tenant_id`, else `project_id`, else `null`, and MUST
  return `null` when `token` is `null` (`tenant.ts`).
- **use-tenant-id-memoized**: `useTenantId()` MUST call `readAccessToken()`
  once per render and MUST memoize `tenantIdFromToken` of that token on the
  token's own identity (`tenant.ts`).
- **resource-item-key-shape**: `resourceItemKey(cacheKey, tenantId, id)`
  MUST return `['resource-item', tenantId, cacheKey, id]`
  (`use-resource-item.ts`).
- **revalidate-resource-items-delegates**: `revalidateResourceItems(match)`
  MUST invalidate every `resource-item`-prefixed cache entry whose key
  `match` accepts (`use-resource-item.ts`).
- **resource-item-query-key-includes-tenant**: `useResourceItemQuery`'s
  query key MUST be `resourceItemKey(cacheKey, tenantId, id ?? '')`, where
  `tenantId` comes from `useTenantId()` (`use-resource-item.ts`).
- **resource-item-enabled-gate**: `useResourceItemQuery`'s query MUST set
  `enabled: id != null` (`use-resource-item.ts`).
- **resource-item-error-reporting-gated**: the query function MUST call
  `reportUnexpectedAuthError(e, { feature: 'resource-item', step: 'load',
  basePath: cacheKey })` when `opts.reportErrors ?? true` is `true`, and MUST
  rethrow `e` regardless of that flag (`use-resource-item.ts`).
- **resource-item-no-retry**: `useResourceItemQuery`'s query MUST set
  `retry: false` (`use-resource-item.ts`).
- **resource-item-gc-time**: `useResourceItemQuery`'s query MUST set
  `gcTime: RESOURCE_GC_TIME` (30 minutes) (`use-resource-item.ts`).
- **resource-item-placeholder-data**: `useResourceItemQuery` MUST use
  `opts.seedFrom`, when supplied, as `placeholderData` — never as
  `initialData` (`use-resource-item.ts`).
- **resource-item-is-settled-sticky**: the returned `isSettled` MUST become
  `true` the first time the query settles a real answer for the current
  `id` (not a placeholder, not pending, not fetching), and MUST remain
  `true` for that same `id` afterward even during a background refetch; it
  MUST reset to unsettled only when `id` itself changes
  (`use-resource-item.ts`).
- **resource-item-is-missing-derivation**: the returned `isMissing` MUST be
  `isNotFound(query.error)` (`use-resource-item.ts`).
- **resource-item-error-message-fallback**: the returned `error` MUST be
  `null` when there is no error, `err.message` when the error is an
  `Error`, and the literal string `'Failed to load.'` otherwise
  (`use-resource-item.ts`).
- **resource-item-reload-null-id-behavior**: NEEDS REVIEW: Not implemented in source. The returned `reload()`'s own doc comment states it is "a no-op when there is no id", but the implementation calls `refetch()` unconditionally regardless of `id`, and the query's `queryFn` calls `load(id as string)` with no runtime guard — the type cast asserts a string even when `id` is actually `null` (`use-resource-item.ts`).
- **resource-item-writer-write-or-evict**: `useResourceItemWriter(cacheKey)`'s
  returned function MUST call `client.setQueryData` when `next !== null`,
  and MUST call `client.removeQueries` (evicting the entry, never writing a
  `null` tombstone) when `next === null` (`use-resource-item.ts`).
- **resource-item-prefetch-never-throws**:
  `useResourceItemPrefetch(cacheKey, load)`'s returned function MUST never
  throw (`use-resource-item.ts`).
- **resource-item-prefetch-no-retry**: the prefetch MUST call
  `client.prefetchQuery` with `retry: false` (`use-resource-item.ts`).
- **resource-item-prefetch-cleanup-conditional**: after the prefetch
  settles, its cleanup MUST remove the entry only if the entry's state is
  still `'error'` at that time, and MUST leave the entry alone if a
  concurrent successful read has already replaced it
  (`use-resource-item.ts`).
- **resource-list-key-shape**: `resourceListKey(cacheKey, tenantId)` MUST
  return `['resource-list', tenantId, cacheKey]` (`use-resource-list.ts`).
- **revalidate-resources-delegates**: `revalidateResources(match)` MUST
  invalidate every `resource-list`-prefixed cache entry whose key `match`
  accepts (`use-resource-list.ts`).
- **resource-list-error-reporting-gated**: `useResourceList`'s query
  function MUST call `reportUnexpectedAuthError(e, { feature:
  'resource-list', step: 'load', basePath: cacheKey })` when
  `opts.reportErrors ?? true` is `true`, and MUST rethrow `e` regardless of
  that flag (`use-resource-list.ts`).
