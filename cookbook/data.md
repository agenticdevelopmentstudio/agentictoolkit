---
id: ec6e6ca5-8780-4ce2-8b3a-087adc50ed35
title: Hub Domain Data
domain: agentictoolkit://cookbook/data
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Web SPA cross-cutting data substrate: tenant-scoped resource-list/resource-item
  caching over TanStack Query, FTD (last-id/view-mode) persistence, workspace-prefs
  caching, and workspace listing/slug-availability.'
platforms:
- typescript
- web
tags:
- data
- cache
- react-query
- tenant
- persistence
- workspace
- http
- web
depends-on:
- agentictoolkit://cookbook/auth/auth-client
related: []
references:
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/data/src/config.ts (agentictoolkit)
- packages/web/packages/data/src/ftd-storage.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/tenant.ts (agentictoolkit)
- packages/web/packages/data/src/use-resource-item.ts (agentictoolkit)
- packages/web/packages/data/src/use-resource-list.ts (agentictoolkit)
- packages/web/packages/data/src/workspace-prefs.ts (agentictoolkit)
- packages/web/packages/data/src/workspaces.ts (agentictoolkit)
- packages/web/packages/data/src/__tests__/ftd-storage.test.ts (agentictoolkit)
- packages/web/packages/data/src/__tests__/http.test.ts (agentictoolkit)
- packages/web/packages/data/src/__tests__/tenant.test.ts (agentictoolkit)
- packages/web/packages/data/src/__tests__/workspace-prefs.test.ts (agentictoolkit)
- packages/web/packages/data/src/__tests__/workspaces-changed.test.ts (agentictoolkit)
- packages/web/packages/data/src/__tests__/use-resource-item.test.tsx (agentictoolkit)
- packages/web/packages/data/src/__tests__/use-resource-list.test.tsx (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Data

## Overview

The `hub-domain-data` ingredient is the web SPA's cross-cutting data
substrate: nine dependency-light TypeScript modules at
`@agentic-toolkit/data`'s package root
(`packages/web/packages/data/src/client-helpers.ts`, `config.ts`,
`ftd-storage.ts`, `http.ts`, `tenant.ts`, `use-resource-item.ts`,
`use-resource-list.ts`, `workspace-prefs.ts`, `workspaces.ts`) that together
give every per-domain feature module in the package (the subpath exports the
package's own root file describes as the hub's per-domain modules, not part
of this contract) a shared tenant-scoped resource cache built on
`@tanstack/react-query`, browser-persisted FTD state (which id a collection
last showed, and whether it renders as cards or a list), a cached
workspace-prefs round-trip, and workspace listing/switching. It builds
directly on the Bearer-authed fetch layer, token/subject reading, and
base64url decoding that `@agentic-toolkit/auth/client` exports — documented
separately as the `auth-client` recipe (`depends-on`) — and re-exports
several of those functions unchanged rather than re-implementing them. It has
no visual surface of its own: every list, detail pane, and workspace switcher
in the app is a consumer of this contract, not part of it.

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
- **resource-list-no-retry**: `useResourceList`'s query MUST set `retry:
  false` (`use-resource-list.ts`).
- **resource-list-gc-time**: `useResourceList`'s query MUST set `gcTime:
  RESOURCE_GC_TIME` (30 minutes) (`use-resource-list.ts`).
- **resource-list-reload-identity-guard**: `useResourceList`'s effect MUST
  cancel the in-flight request and refetch only when `load`'s identity has
  changed AND `cacheKey`/`tenantId` have stayed the same
  (`use-resource-list.ts`).
- **resource-list-reload-rethrows**: the returned `reload()` MUST call
  `refetch()` and MUST rethrow whatever error that resolves with
  (`use-resource-list.ts`).
- **resource-list-set-items-writes-through**: the returned `setItems` MUST
  write through `client.setQueryData` (`use-resource-list.ts`).
- **resource-list-is-fetching-derivation**: the returned `isFetching` MUST
  be `query.isFetching || query.isPending` (`use-resource-list.ts`).
- **resource-list-error-status-derivation**: the returned `errorStatus` MUST
  be `httpStatus(err) ?? null` (`use-resource-list.ts`).
- **resource-list-error-message-fallback**: the returned `error` MUST be
  `null` when there is no error, `err.message` when the error is an
  `Error`, and the literal string `'Failed to load.'` otherwise
  (`use-resource-list.ts`).
- **make-entity-delete-handler-sequence**: `makeEntityDeleteHandler(opts)`'s
  returned handler MUST, in order: await `del(id)`; when `readLastId(basePath)
  === id`, call `clearLastId(basePath)`; call `router.push(\`${basePath}/all\`,
  { scroll: false })`; then call `reload()`, swallowing any error `reload()`
  throws (`use-resource-list.ts`).
- **make-entity-delete-handler-del-not-caught**: a rejection thrown by
  `del(id)` itself MUST NOT be caught by this handler — only the subsequent
  `reload()` call's rejection is swallowed (`use-resource-list.ts`).
- **workspace-prefs-cache-key**: the cached workspace slug MUST be stored
  under `` `${dataConfig().storageKeyPrefix}:home:workspace` ``
  (`workspace-prefs.ts`).
- **read-cached-workspace-ssr-safe**: `readCachedWorkspace()` MUST return a
  safe empty result (no thrown exception) both off-browser and when reading
  storage throws (`workspace-prefs.ts`).
- **write-cached-workspace-swallow**: `writeCachedWorkspace(slug)` MUST
  swallow any exception thrown while writing storage (`workspace-prefs.ts`).
- **workspace-prefs-get-unwraps**: `workspacePrefsApi.get()` MUST issue `GET
  /api/me/workspace-prefs`, unwrap the response's `{ prefs }` field, and MUST
  default to `{}` rather than surface a 404 (`workspace-prefs.ts`).
- **workspace-prefs-put-full-replace**: `workspacePrefsApi.put(prefs)` MUST
  issue `PUT /api/me/workspace-prefs` with the full `prefs` object,
  replacing the stored preferences rather than merging into them
  (`workspace-prefs.ts`).
- **workspaces-query-key-constant**: `WORKSPACES_QUERY_KEY` MUST be
  `['workspaces']` (`workspaces.ts`).
- **notify-workspaces-changed-dual-invalidate**:
  `notifyWorkspacesChanged()` MUST invalidate the `WORKSPACES_QUERY_KEY`
  cache entry directly, AND MUST invalidate, via `revalidateResources`,
  every `resource-list` cache entry whose cache key is `'workspaces'`
  (`workspaces.ts`).
- **notify-workspaces-changed-swallows**: both invalidations
  `notifyWorkspacesChanged()` performs MUST swallow any rejection they
  produce (`workspaces.ts`).
- **notify-workspaces-changed-dispatches-event**:
  `notifyWorkspacesChanged()` MUST dispatch a `CustomEvent` named by
  `WORKSPACES_CHANGED_EVENT` (`'adh:workspaces-changed'`) on `window`, and
  MUST be a no-op off-browser (`workspaces.ts`).
- **on-workspaces-changed-subscribe**: `onWorkspacesChanged(listener)` MUST
  subscribe `listener` to that event and MUST return an unsubscribe
  function; both MUST be no-ops off-browser (`workspaces.ts`).
- **check-workspace-slug-available**: `checkWorkspaceSlugAvailable(slug)`
  MUST issue `GET` to
  `` `/api/auth/slug-available/${encodeURIComponent(slug)}` `` and return a
  `SlugAvailability` (`workspaces.ts`).
- **workspaces-api-list-drops-team-rows**: `workspacesApi.list()` MUST
  exclude any row whose `type` is `'team'` (`workspaces.ts`).
- **workspaces-api-list-ordering**: `workspacesApi.list()` MUST order its
  caller's own individual workspace first, followed by every organization
  sorted by name via `sortByText` (`workspaces.ts`).

## Appearance

Not applicable — this is a headless data/caching layer, not a visual
component.

## States

Not applicable — this is a headless data/caching layer, not a visual
component.

## Accessibility

Not applicable — this is a headless data/caching layer, not a visual
component.

## Conformance Test Vectors

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

## Edge Cases

- **Null/empty input**: `tenantIdFromToken(null)` and `decodeJwtClaims('')`
  MUST return `null` (hub-domain-data-032, hub-domain-data-037).
  `workspaceQuery(undefined)` MUST return `''` (hub-domain-data-008).
  `readLastId(basePath)` with nothing stored MUST return `null`
  (hub-domain-data-012).
- **Boundary/malformed values**: A JWT with no dot, one dot, or a payload
  that is not valid base64url/JSON MUST all decode to `null` via
  `decodeJwtClaims` (hub-domain-data-032, hub-domain-data-034), relying
  entirely on `decodeBase64UrlJson`'s own contract (see `auth-client`) —
  this component adds no additional payload validation of its own. A stored
  FTD view-mode value that is neither `'cards'` nor `'list'` MUST be
  rejected back to the `'cards'` default rather than passed through
  (hub-domain-data-017).
- **Concurrent access**: A prefetch (`useResourceItemPrefetch`) racing a
  mount's own read of the same item MUST NOT let the prefetch's failure
  cleanup remove data a concurrent success has since written
  (hub-domain-data-055). Two renders of `useResourceList` with the same
  `load` identity MUST NOT cancel/refetch, but a changed `load` identity
  (with `cacheKey`/tenant unchanged) MUST (hub-domain-data-061,
  hub-domain-data-062) — this guard exists specifically because a naive
  effect keyed only on mount would otherwise refetch on every render.
- **Error states**: Every hook's query function (`useResourceItemQuery`,
  `useResourceList`) MUST rethrow whatever its `load`/`del` callback throws
  after optionally reporting it, never swallowing a primary read/write
  failure (resource-item-error-reporting-gated,
  resource-list-error-reporting-gated); the one deliberate exception is
  `makeEntityDeleteHandler`'s post-delete `reload()`, whose failure is
  swallowed because the delete itself already succeeded (see Design
  Decisions).
- **Offline/disconnected state**: Neither `use-resource-item.ts` nor
  `use-resource-list.ts` defines its own retry policy for a network-level
  failure — both explicitly set `retry: false` (resource-item-no-retry,
  resource-list-no-retry), so a caller that wants offline resilience must
  layer it on `load`/`del` itself; this component's own contract is to
  surface the failure promptly, not to mask it behind hidden retries.
- **Storage unavailable** (private browsing, disabled storage — a
  web-specific edge case with no native-platform analog): every FTD
  function (`readLastId`, `writeLastId`, `clearLastId`, `readViewMode`,
  `writeViewMode`) and the workspace-slug cache (`readCachedWorkspace`,
  `writeCachedWorkspace`) MUST swallow a thrown storage exception rather
  than propagate it, degrading to the documented default (`null`/`'cards'`)
  rather than crashing a render.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storageKeyPrefix` | `string` (via `configureData`) | `'adh'` | Prefix for every FTD key (`` `${prefix}:ftd:...` ``) and the cached-workspace key (`` `${prefix}:home:workspace` ``) |
| `WORKSPACES_QUERY_KEY` | exported constant | `['workspaces']` | react-query key the workspace switcher's own list is cached under |
| `WORKSPACES_CHANGED_EVENT` | exported constant | `'adh:workspaces-changed'` | Name of the `CustomEvent` `notifyWorkspacesChanged` dispatches on `window` |
| `RESOURCE_GC_TIME` | imported constant (`query/index.tsx`, not one of this component's own files) | `1,800,000` ms (30 min) | `gcTime` every `resource-list`/`resource-item` entry this component mints uses |
| `opts.reportErrors` | caller-supplied option, per call to `useResourceItemQuery`/`useResourceList` | `true` | Gates whether a load failure is sent to `reportUnexpectedAuthError` |
| `opts.seedFrom` | caller-supplied option, per call to `useResourceItemQuery` | `undefined` | Supplies `placeholderData` (never `initialData`) while the real read is in flight |

## Deep Linking

Not applicable: `hub-domain-data` defines no app URL scheme, Android intent
filter, or platform deep-link registration of its own, and parses no inbound
URL itself. `makeEntityDeleteHandler`'s `router.push` is a caller-supplied
`PushRouter`, not a link scheme this component owns.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `resourceItem.loadFailedFallback` | Failed to load. | `useResourceItemQuery`'s returned `error` when the underlying rejection is not an `Error` instance (`use-resource-item.ts`) |
| `resourceList.loadFailedFallback` | Failed to load. | `useResourceList`'s returned `error` when the underlying rejection is not an `Error` instance (`use-resource-list.ts`) |

Both occurrences are the same hardcoded English literal, with no lookup
table, ICU message, or locale parameter anywhere in these nine files — there
is no localization mechanism in this component at all. This is a plain fact
about the source, not a gap: a port to a platform with an i18n layer MUST
decide, as a design choice outside this contract, whether and how to route
this string through it.

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior of its own. Those
display options act on whatever list or detail UI a host renders around
`useResourceList`/`useResourceItemQuery`, not on this headless module.

## Feature Flags

Not applicable: no file in this component defines or reads a feature-flag
key. Every conditional path (whether an id is present, whether `reportErrors`
is set, whether a stored view-mode value is valid) is derived from a caller
argument or stored state, never from a flag this module owns.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
product-telemetry event. The `reportUnexpectedAuthError` calls in
`use-resource-item.ts`/`use-resource-list.ts` send operational error
diagnostics to the same injected sink `auth-client`'s `report.ts` defines
(see that recipe) — failure telemetry, not product-analytics events.

## Privacy

- **Data collected**: This component collects no new personal data of its
  own. It caches, in memory (react-query) or `localStorage`, whatever rows
  and preference objects its callers already fetched: resource lists/items
  keyed by an opaque `tenantId` (`ecosystem_id`/`tenant_id`/`project_id`,
  read via `useTenantId`, never re-derived or stored separately by this
  module), a last-selected id and view-mode string per collection (FTD), and
  a cached workspace slug.
- **Storage**: The FTD last-id/view-mode values and the cached workspace
  slug live in `localStorage` under `` `${storageKeyPrefix}:ftd:...` `` and
  `` `${storageKeyPrefix}:home:workspace` `` as plaintext — readable by any
  script running on the page, the same SPA localStorage tradeoff
  `auth-client`'s own Privacy section documents for the access token; none
  of these values is itself a credential. Resource lists/items live only in
  the in-memory `@tanstack/react-query` cache (`getToolkitQueryClient()`),
  never written to `localStorage`.
- **Transmission**: Every network call this component makes (`authedJson`,
  `authedRequest`, and the plain `fetch` calls in `workspace-prefs.ts`/
  `workspaces.ts`) goes through the Bearer-authed fetch layer `http.ts`
  re-exports from `auth-client`; this module adds no transmission channel
  of its own.
- **Retention**: `resource-list`/`resource-item` cache entries persist in
  memory for `RESOURCE_GC_TIME` (30 minutes) after their last observer
  unmounts, and the whole cache is cleared the moment the signed-in
  principal changes (`watchSession()` in `query/index.tsx`, not one of this
  component's own files, but the mechanism that keeps a tenant-keyed cache
  entry from surviving a sign-out/sign-in on a shared machine). FTD and
  workspace-slug `localStorage` entries persist until explicitly overwritten
  or the browser's own storage is cleared; this component enforces no TTL
  on them.

## Logging

Not applicable: no file in this component calls `console.log`,
`console.warn`, `console.info`, or `console.error` directly. The only
diagnostic path is the `reportUnexpectedAuthError` call inside
`useResourceItemQuery`/`useResourceList`'s query functions, which delegates
to `auth-client`'s `report.ts` — documented under that recipe's own Logging
section, not duplicated here.

## Platform Notes

- **React/Web**: This is the reference implementation. `@tanstack/react-query`
  v5 (via the toolkit's own module-scope `QueryClient`, see `query/index.tsx`)
  backs the resource-list/resource-item cache; `window.localStorage` backs
  FTD and the cached workspace slug; `window.CustomEvent`/
  `window.addEventListener`/`window.dispatchEvent` back the
  `workspaces-changed` cross-module announcement; `String.prototype
  .localeCompare` (via `sortByText`) provides locale-aware ordering.
- **SwiftUI / AppKit / UIKit**: An `ObservableObject`/actor-backed
  dictionary cache keyed identically (tenant, then cache key, then id) is
  the idiomatic replacement for the react-query cache; `UserDefaults`
  (namespaced by the same `storageKeyPrefix` convention) replaces
  `localStorage` for FTD and the workspace-slug cache;
  `NotificationCenter.default.post`/`.addObserver` replaces the
  `workspaces-changed` `CustomEvent` pair; `String.localizedStandardCompare`
  replaces `sortByText`'s comparator.
- **Compose / Android**: A `MutableStateFlow`-backed map cache keyed
  identically is the idiomatic cache substitute; Android `DataStore` (or
  `SharedPreferences` for the simplest case) replaces `localStorage` for
  FTD and the workspace-slug cache; a `SharedFlow` replaces the
  `workspaces-changed` event pair; `java.text.Collator` replaces
  `sortByText`'s comparator.
- **WinUI 3**: `Microsoft.Extensions.Caching.Memory`'s `IMemoryCache` (or a
  hand-rolled `Dictionary<(string tenantId, string cacheKey, string? id),
  CacheEntry<T>>`) is the idiomatic replacement for the react-query cache —
  a native port MUST keep `tenantId` as the FIRST key segment exactly as
  `resourceListKey`/`resourceItemKey` do, not as a secondary filter applied
  after a shared read, to preserve the same hard cross-account isolation on
  a machine shared between signed-in users.
  `Windows.Storage.ApplicationData.Current.LocalSettings` replaces
  `localStorage` for the FTD (`readLastId`/`writeLastId`/`readViewMode`/
  `writeViewMode`) and cached-workspace-slug values, using the same
  `{prefix}:ftd:{basePath}:{name}` / `{prefix}:home:workspace` key shape so
  the `storageKeyPrefix` convention (default `"adh"`) still disambiguates
  multiple apps sharing one settings container. A C# `event` (or a
  `WeakEventManager` to avoid the listener-leak `onWorkspacesChanged`'s
  unsubscribe function exists to prevent) replaces the `workspaces-changed`
  `CustomEvent`/`onWorkspacesChanged` pair. `string.Compare(a, b,
  StringComparison.CurrentCulture)` replaces `sortByText`'s
  `localeCompare`-based ordering. `System.Text.Json`'s `JsonSerializer`
  replaces every inline JSON parse/serialize this component does for its
  own cached values (not the JWT/token parsing itself, which `auth-client`'s
  own Platform Notes already cover).

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/client-helpers.ts` |
| web | `packages/web/packages/data/src/config.ts` |
| web | `packages/web/packages/data/src/ftd-storage.ts` |
| web | `packages/web/packages/data/src/http.ts` |
| web | `packages/web/packages/data/src/tenant.ts` |
| web | `packages/web/packages/data/src/use-resource-item.ts` |
| web | `packages/web/packages/data/src/use-resource-list.ts` |
| web | `packages/web/packages/data/src/workspace-prefs.ts` |
| web | `packages/web/packages/data/src/workspaces.ts` |

## Design Decisions

**Decision**: Tenant-scoped resource cache keys embed `tenantId` as a KEY
SEGMENT (`['resource-list', tenantId, cacheKey]` /
`['resource-item', tenantId, cacheKey, id]`), never as a filter applied
after a shared read.
**Rationale**: Two users signed into the same browser tab in sequence — or
two ecosystems on one account — must never be served one another's cached
rows even for the instant before a filter would run; keying by tenant makes
cross-tenant leakage structurally impossible rather than merely policed
after the fact. `watchSession()`'s cache-clear-on-subject-change in
`query/index.tsx` is a second, independent layer against the same threat,
not a substitute for this one.
**Approved**: pending

**Decision**: `useResourceItemWriter`'s `next === null` case removes the
query entry (`client.removeQueries`) rather than writing a `null` tombstone
via `setQueryData`.
**Rationale**: A tombstoned `null` is itself a cached "answer" a later
reader would treat as settled-and-empty; eviction instead forces the next
reader to ask the server, rather than trust a locally invented negative
that could go stale the moment the row is recreated.
**Approved**: pending

**Decision**: `useResourceItemPrefetch`'s post-settle cleanup removes the
entry only if its state is still `'error'` at that time, not unconditionally.
**Rationale**: A hover-triggered prefetch and the item's own mount can race
against the same cache entry; if the mount's successful read has already
replaced the failed prefetch's entry by the time the prefetch's own cleanup
runs, an unconditional removal would throw away good data the prefetch
itself never touched.
**Approved**: pending

**Decision**: `makeEntityDeleteHandler` lets a rejection from `del(id)`
propagate uncaught, but swallows a rejection from the subsequent `reload()`.
**Rationale**: A failed delete is the very operation the caller asked for
and must surface. Once the delete has already succeeded, though, a failure
to refresh the list afterward is a staleness problem, not a correctness
one — the row has already left the server-side list — so leaving it to a
later revalidation is preferable to reporting a phantom failure for an
operation that in fact succeeded.
**Approved**: pending

**Decision**: `notifyWorkspacesChanged()` invalidates the toolkit's own
`['workspaces']` cache entry directly, revalidates the
`resource-list`-keyed `'workspaces'` entry via a predicate, AND dispatches a
`CustomEvent` on `window` — three mechanisms to announce one fact.
**Rationale**: The workspace list is read through at least two distinct
react-query cache entries inside this package (the switcher's key-only
entry and a consumer's `useResourceList('workspaces')` entry), and, per
`query/index.tsx`'s own documented trap, may also be re-read by a host's
entirely separate react-query copy that this module's `invalidateQueries`
call cannot reach at all — the window event is the only channel that
crosses that physical-module boundary.
**Approved**: pending

**Decision**: `httpStatus`/`isNotFound`/`isConflict`/`isForbidden`/
`isServiceUnavailable` duck-type a numeric `.status` off any thrown `Error`
rather than checking `instanceof` against a specific error class.
**Rationale**: Mirrors `auth-client`'s own `reportUnexpectedAuthError`
duck-typing decision for the identical reason — a host may layer its own
distinctly-classed `AuthHttpError`-shaped error on top of this fetch layer,
and an `instanceof` check would fail to recognize its 404/409/403/503 as
the very condition these predicates exist to detect.
**Approved**: pending

**Decision**: Every FTD function and the workspace-slug cache
(`readLastId`, `writeLastId`, `clearLastId`, `readViewMode`, `writeViewMode`,
`readCachedWorkspace`, `writeCachedWorkspace`) swallows a thrown storage
exception rather than propagating it.
**Rationale**: These are cosmetic UI-continuity conveniences (which id a
collection last showed, whether it renders as cards or a list, which
workspace to preselect) whose failure should degrade to the documented
default rather than crash a page render; a private-browsing session or a
full storage quota must not turn a persistence nicety into a hard error.
**Approved**: pending

**Decision**: `RESOURCE_GC_TIME` (30 minutes) is deliberately far longer
than react-query's shared 5-minute `staleTime` default, and is set once, by
key prefix, in `query/index.tsx` rather than in each of this component's own
hooks.
**Rationale**: Cited here because it directly governs how long a
`resource-list`/`resource-item` entry this component's hooks mint survives
with no observer; the long `gcTime` is what lets a stale seed still repaint
instantly on a return visit while a background revalidation settles behind
it — pinned by prefix so a prefetch or a post-write `setQueryData`, both of
which mint an entry with no observer at all, get the same lifetime as the
reading hooks.
**Approved**: pending

**Decision**: This recipe records `reload()`'s no-op-when-no-id doc-comment
discrepancy as an open question rather than restating the doc comment as a
MUST.
**Rationale**: Reading the call site shows `refetch()` is invoked
unconditionally regardless of `id`, and TanStack Query v5's documented
`refetch` behavior executes a query's `queryFn` even when that query is
`enabled: false` — so the doc comment and the implementation disagree, and
no test in `use-resource-item.test.tsx` exercises `id === null` through
`reload()` to settle which one is authoritative. See Behavioral
Requirements.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`secure-storage` is **partial**: the FTD last-id/view-mode values and the
cached workspace slug sit in plaintext `localStorage` with no encryption —
an accepted SPA tradeoff (see Privacy), though none of these values is
itself a credential, unlike the access token `auth-client`'s own
`secure-storage` row covers. `input-sanitization` **passed**: every dynamic
path segment this component builds into a URL
(`workspaceQuery`, `checkWorkspaceSlugAvailable`'s slug) is passed through
`enc`/`encodeURIComponent` before interpolation. `explicit-error-handling`
**passed**: every read/write path in these nine files either rethrows a
caller-visible error or falls back to a documented default — the two
deliberate swallow paths (storage exceptions; `makeEntityDeleteHandler`'s
post-delete `reload()`) are each covered by their own Design Decisions
entry, not silent omissions. `fault-tolerance` **passed**: `retry: false`
plus the long `RESOURCE_GC_TIME`, the storage-exception swallowing, and the
del-not-caught/reload-swallowed split in `makeEntityDeleteHandler`
collectively keep a transient or permission failure from corrupting cache
state or crashing a render. `data-integrity` **passed**: tenant-keyed cache
segments make cross-tenant leakage structurally impossible rather than
merely policed, and `useResourceItemWriter`'s evict-not-tombstone choice
means a deleted row can never be misread back as a cached empty answer.
`data-minimization` **passed**: this component collects no personal data of
its own beyond the opaque `tenantId` it reads via `useTenantId()`.
`no-hardcoded-strings` **failed**: the `'Failed to load.'` fallback in
`use-resource-item.ts`/`use-resource-list.ts` is hardcoded English with no
lookup table or locale parameter anywhere in this component (see
Localization) — a plain, honestly-reported gap in the source, not a hidden
one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe. |
