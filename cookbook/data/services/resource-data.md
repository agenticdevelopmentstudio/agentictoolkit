---
id: ec6e6ca5-8780-4ce2-8b3a-087adc50ed35
title: Resource Data
domain: agentictoolkit://cookbook/data/services/resource-data
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Cross-cutting data substrate: tenant-scoped resource-list/resource-item
  caching, last-id/view-mode (FTD) persistence, workspace-preference caching, and
  workspace listing/slug-availability, built on a shared authenticated request layer.'
platforms:
- typescript
- web
tags:
- data
- cache
- tenant
- persistence
- workspace
- http
depends-on:
- agentictoolkit://cookbook/data/services/auth/auth-client
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

# Resource Data

## Overview

This ingredient is the app's cross-cutting data substrate: nine
dependency-light modules that together give every per-domain feature area a
shared tenant-scoped resource cache, persisted last-shown/view-mode state
(FTD: which id a collection last showed, and whether it renders as cards or a
list), a cached workspace-preferences round-trip, and workspace
listing/switching. It builds directly on the shared authenticated request
layer, token/subject reading, and base64url decoding documented separately as
the Auth Client recipe (`depends-on`), and re-exports several of those
operations unchanged rather than re-implementing them. It has no visual
surface of its own: every list, detail pane, and workspace switcher in the
app is a consumer of this contract, not part of it.

## Behavioral Requirements

- **percent-encodes-uri-components**: The shared URI-component encoding
  helper MUST behave like standard percent-encoding of a URI component (for
  example, encoding a space as `%20`).
- **compact-drops-undefined-preserves-null**: The object-compacting helper,
  given an object, MUST return a new object containing every key whose value
  is not absent, and MUST preserve any key whose value is explicitly `null`.
- **compact-non-mutating**: The object-compacting helper MUST NOT mutate its
  input object.
- **narrow-fallback**: The allowed-value narrowing helper, given a value, a
  set of allowed values, and a fallback, MUST return the value when it is
  among the allowed values, and MUST return the fallback otherwise.
- **scope-by-owner-filters**: The owner-scoping filter, given a list of
  rows, an owner id, and an owner-extracting function, MUST return exactly
  the rows for which the extracted owner matches the given owner id.
- **sort-by-text-non-mutating**: The text-sorting helper, given a list of
  rows and a field name, MUST return a new array ordered by that field using
  locale-aware comparison, and MUST NOT mutate the input array.
- **workspace-query-encodes**: The workspace query-string builder, given a
  workspace slug, MUST return the query string `?workspace=<percent-encoded
  slug>` when a non-empty workspace is supplied, and MUST return an empty
  string when it is absent or empty.
- **data-config-default**: The data-configuration reader MUST return a
  storage-key prefix of `'adh'` before any configuration has been set.
- **configure-data-merges**: The data-configuration setter, given a partial
  configuration, MUST shallow-merge it onto the current configuration,
  leaving any field it omits unchanged.
- **ftd-key-shape**: Every FTD storage key MUST be built as
  `<prefix>:ftd:<basePath>:<name>`, where `<prefix>` is the configured
  storage-key prefix.
- **read-last-id-null-safe**: Reading the last-shown id for a collection
  MUST return the stored id, and MUST return no value when nothing is stored
  or when reading storage fails.
- **write-last-id-swallow**: Writing the last-shown id MUST swallow any
  failure raised while writing storage.
- **clear-last-id-swallow**: Clearing the last-shown id MUST remove the
  stored id and MUST swallow any failure raised while doing so.
- **read-view-mode-safe-without-storage**: Reading the view mode MUST return
  `'cards'` when no persisted-storage environment is available yet.
- **read-view-mode-validates**: Reading the view mode MUST return the stored
  value only when it is exactly `'list'` or `'cards'`, and MUST return
  `'cards'` for any other stored value, including absence or a reading
  error.
- **write-view-mode-swallow**: Writing the view mode MUST swallow any
  failure raised while writing storage.
- **http-re-exports-auth**: This module MUST re-export, unchanged, the
  shared authenticated-request operations, error-message extraction,
  token/subject reading, and base64url-decoding operations documented by the
  Auth Client recipe — their contract is documented there, not restated
  here.
- **http-status-duck-typed**: The status-code extractor, given an error,
  MUST return its numeric status property when the error carries one, and
  MUST return no value otherwise, without ever checking the error's specific
  class.
- **client-refusal-shape**: The client-refusal error constructor, given a
  message and an optional status (default 400), MUST return an error whose
  message is that message and whose status is that status.
- **is-not-found-derivation**: The not-found predicate MUST return true
  exactly when the status-code extractor reports 404.
- **is-conflict-derivation**: The conflict predicate MUST return true
  exactly when the status-code extractor reports 409.
- **is-forbidden-derivation**: The forbidden predicate MUST return true
  exactly when the status-code extractor reports 403.
- **is-service-unavailable-derivation**: The service-unavailable predicate
  MUST return true exactly when the status-code extractor reports 503.
- **err-msg-fallback**: The error-message-with-fallback helper, given an
  error and a fallback string, MUST return a message derived from the error
  when one can be extracted, and MUST return the fallback otherwise.
- **rethrow-conflict-friendly**: The friendly-conflict rethrow helper, given
  an error and a friendly message, MUST raise a new error with the friendly
  message when the original error's message matches an "already exists"
  pattern (case-insensitive), and MUST rethrow the original error unchanged
  otherwise.
- **decode-jwt-claims-shape**: The token-claims decoder, given a token
  string, MUST split it on `.` and return no value unless the result has
  exactly 3 parts with a non-empty second part; otherwise it MUST return the
  base64url-JSON decoding of that second part.
- **decode-jwt-claims-null-safe**: The token-claims decoder MUST return no
  value when the base64url-JSON decoding of the payload segment fails —
  handled entirely by that decoding operation's own no-value-on-any-failure
  contract (see the Auth Client recipe), not re-implemented here.
- **tenant-id-priority**: The tenant-id derivation, given decoded token
  claims, MUST return, in order, the ecosystem id, else the tenant id, else
  the project id, else no value, and MUST return no value when the token
  itself is absent.
- **use-tenant-id-memoized**: The tenant-id read state MUST read the current
  access token once per render and MUST memoize the derived tenant id on the
  token's own identity.
- **resource-item-key-shape**: The resource-item cache-key builder, given a
  cache key, a tenant id, and an item id, MUST return the ordered tuple
  `('resource-item', tenantId, cacheKey, id)`.
- **revalidate-resource-items-delegates**: The resource-item cache
  invalidation operation, given a match predicate, MUST invalidate every
  resource-item cache entry whose key the predicate accepts.
- **resource-item-cache-key-includes-tenant**: The resource-item read
  state's cache key MUST be the resource-item cache key built from the cache
  key, item id (or an empty id when absent), and the tenant id derived from
  the tenant-id read state.
- **resource-item-enabled-gate**: The resource-item read state MUST NOT
  invoke its load operation when the item id is absent — the read is gated
  off entirely in that case.
- **resource-item-error-reporting-gated**: When the underlying read fails,
  the resource-item read state MUST report the failure (naming the
  resource-item feature, the load step, and the cache key) when error
  reporting is enabled (the default), and MUST rethrow the failure
  regardless of that setting.
- **resource-item-no-retry**: The resource-item read state MUST NOT
  automatically retry a failed read.
- **resource-item-cache-retention**: The resource-item read state's cache
  entries MUST be retained for the configured resource cache-retention
  period (30 minutes) after their last observer goes away.
- **resource-item-placeholder-data**: The resource-item read state MUST use
  a caller-supplied seed value, when given, only as a placeholder shown
  while the real read is pending — never treated as though it were already
  the settled answer.
- **resource-item-is-settled-sticky**: The returned settled indicator MUST
  become true the first time the read settles a real answer for the current
  item id (not a placeholder, not pending, not in flight), and MUST remain
  true for that same id afterward even during a background refresh; it MUST
  reset to unsettled only when the item id itself changes.
- **resource-item-is-missing-derivation**: The returned missing indicator
  MUST equal the not-found predicate applied to the read's error.
- **resource-item-error-message-fallback**: The returned error message MUST
  be absent when there is no error, MUST be the error's own message when it
  carries one, and MUST be the literal string `'Failed to load.'` otherwise.
- **resource-item-reload-null-id-behavior**: NEEDS REVIEW: Not implemented
  in source. The returned reload operation's own documentation states it is
  a no-op when there is no item id, but the implementation re-runs the read
  unconditionally regardless of the id, and the underlying load call is
  invoked with the id even when it is actually absent, asserted rather than
  guarded at runtime — evidence needed is whether the documented no-op is
  authoritative.
- **resource-item-writer-write-or-evict**: The resource-item cache writer's
  returned function MUST write the given value into the cache when it is
  not null, and MUST evict the cache entry (never writing a null
  placeholder) when the given value is null.
- **resource-item-prefetch-never-throws**: The resource-item prefetch
  operation's returned function MUST never raise.
- **resource-item-prefetch-no-retry**: The prefetch MUST issue its
  underlying read with no automatic retry.
- **resource-item-prefetch-cleanup-conditional**: After the prefetch
  settles, its cleanup MUST remove the cache entry only if the entry's state
  is still an error at that time, and MUST leave the entry alone if a
  concurrent successful read has since replaced it.
- **resource-list-key-shape**: The resource-list cache-key builder, given a
  cache key and a tenant id, MUST return the ordered tuple `('resource-list',
  tenantId, cacheKey)`.
- **revalidate-resources-delegates**: The resource-list cache invalidation
  operation, given a match predicate, MUST invalidate every resource-list
  cache entry whose key the predicate accepts.
- **resource-list-error-reporting-gated**: When the underlying read fails,
  the resource-list read state MUST report the failure (naming the
  resource-list feature, the load step, and the cache key) when error
  reporting is enabled (the default), and MUST rethrow the failure
  regardless of that setting.
- **resource-list-no-retry**: The resource-list read state MUST NOT
  automatically retry a failed read.
- **resource-list-cache-retention**: The resource-list read state's cache
  entries MUST be retained for the configured resource cache-retention
  period (30 minutes) after their last observer goes away.
- **resource-list-reload-identity-guard**: The resource-list read state's
  refresh behavior MUST cancel the in-flight request and re-fetch only when
  the caller's load-function identity has changed AND the cache
  key/tenant have stayed the same.
- **resource-list-reload-rethrows**: The returned reload operation MUST
  trigger a refresh and MUST rethrow whatever error that refresh resolves
  with.
- **resource-list-set-items-writes-through**: The returned setItems
  operation MUST write the given rows directly into the cache.
- **resource-list-is-fetching-derivation**: The returned loading indicator
  MUST be true whenever the read is either actively fetching or still
  pending its first result.
- **resource-list-error-status-derivation**: The returned error status MUST
  be the status-code extractor's result for the read's error, or absent when
  there is none.
- **resource-list-error-message-fallback**: The returned error message MUST
  be absent when there is no error, MUST be the error's own message when it
  carries one, and MUST be the literal string `'Failed to load.'` otherwise.
- **make-entity-delete-handler-sequence**: The entity-delete handler
  factory's returned handler MUST, in order: await the delete operation for
  the given id; when the last-shown id for the base path equals that id,
  clear the last-shown id; navigate to the base path's `all` view without
  scrolling; then trigger a reload, swallowing any error the reload raises.
- **make-entity-delete-handler-del-not-caught**: A failure from the delete
  operation itself MUST NOT be caught by this handler — only the subsequent
  reload's failure is swallowed.
- **workspace-prefs-cache-key**: The cached workspace slug MUST be stored
  under the key `<prefix>:home:workspace`.
- **read-cached-workspace-safe-without-storage**: Reading the cached
  workspace MUST return a safe empty result (no raised failure) both when no
  persisted-storage environment is available and when reading storage fails.
- **write-cached-workspace-swallow**: Caching a workspace slug MUST swallow
  any failure raised while writing storage.
- **workspace-prefs-get-unwraps**: The workspace-preferences read operation
  MUST issue a GET request to `/api/me/workspace-prefs`, unwrap the
  response's `prefs` field, and MUST default to an empty object rather than
  surface a not-found result.
- **workspace-prefs-put-full-replace**: The workspace-preferences write
  operation MUST issue a PUT request to `/api/me/workspace-prefs` with the
  full preferences object, replacing the stored preferences rather than
  merging into them.
- **workspace-list-cache-key-constant**: The workspace-list cache key MUST
  be the constant `('workspaces')`.
- **notify-workspaces-changed-dual-invalidate**: The
  workspace-list-changed announcement operation MUST invalidate the
  workspace-list cache entry directly, AND MUST invalidate, via the
  resource-list cache invalidation operation, every resource-list cache
  entry whose cache key is `'workspaces'`.
- **notify-workspaces-changed-swallows**: Both invalidations the
  workspace-list-changed announcement performs MUST swallow any failure
  they produce.
- **notify-workspaces-changed-dispatches-event**: The
  workspace-list-changed announcement operation MUST broadcast an event
  named by the workspaces-changed event name (`'adh:workspaces-changed'`),
  and MUST be a no-op when no environment capable of receiving it is
  available.
- **on-workspaces-changed-subscribe**: The workspace-list-changed
  subscription operation, given a listener, MUST subscribe it to that event
  and MUST return an unsubscribe function; both MUST be no-ops when no
  environment capable of delivering the event is available.
- **check-workspace-slug-available**: The workspace-slug availability
  check, given a slug, MUST issue a GET request to
  `/api/auth/slug-available/<percent-encoded slug>` and return a
  slug-availability result.
- **workspace-list-drops-team-rows**: The workspace-list operation MUST
  exclude any row whose type is `'team'`.
- **workspace-list-ordering**: The workspace-list operation MUST order the
  caller's own individual workspace first, followed by every organization
  sorted by name via the text-sorting helper.

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
| hub-domain-data-001 | percent-encodes-uri-components | the string `a b` | `a%20b` |
| hub-domain-data-002 | compact-drops-undefined-preserves-null | an object with one key set to `1`, one key absent, one key set to `null` | `{ that key: 1, the null key: null }`, the absent key dropped |
| hub-domain-data-003 | compact-non-mutating | an object with one key left absent, passed through the compacting helper | the original object still carries that key with an absent value afterward |
| hub-domain-data-004 | narrow-fallback | value `'x'`, allowed values `['a', 'b']`, fallback `'a'` | `'a'` (fallback, since `'x'` is not allowed) |
| hub-domain-data-005 | scope-by-owner-filters | rows `[{owner:1},{owner:2}]`, owner id `1` | `[{owner:1}]` |
| hub-domain-data-006 | sort-by-text-non-mutating | rows `[{name:'b'},{name:'a'}]` sorted by name | returned array is `[{name:'a'},{name:'b'}]`; the original array is unchanged |
| hub-domain-data-007 | workspace-query-encodes | workspace `'a b'` | `'?workspace=a%20b'` |
| hub-domain-data-008 | workspace-query-encodes | no workspace supplied | `''` |
| hub-domain-data-009 | data-config-default | the configuration reader called with no prior configuration set | storage-key prefix `'adh'` |
| hub-domain-data-010 | configure-data-merges | setting the storage-key prefix to `'x'`, then reading configuration | storage-key prefix `'x'` |
| hub-domain-data-011 | ftd-key-shape | writing last-shown id `'p-1'` for collection `'projects'` with prefix `'adh'` | writes under storage key `'adh:ftd:projects:lastId'` |
| hub-domain-data-012 | read-last-id-null-safe | reading the last-shown id for `'projects'` with nothing stored | no value |
| hub-domain-data-013 | read-last-id-null-safe | reading the last-shown id for `'projects'` when reading storage fails | no value, no failure propagates |
| hub-domain-data-014 | write-last-id-swallow | writing last-shown id `'p-1'` for `'projects'` when writing storage fails | resolves without raising |
| hub-domain-data-015 | clear-last-id-swallow | clearing the last-shown id for `'projects'` when removing storage fails | resolves without raising |
| hub-domain-data-016 | read-view-mode-safe-without-storage | reading the view mode for `'projects'`/`'root'` with no persisted-storage environment available | `'cards'` |
| hub-domain-data-017 | read-view-mode-validates | reading the view mode for `'projects'`/`'root'` with `'grid'` stored | `'cards'` (invalid value rejected) |
| hub-domain-data-018 | read-view-mode-validates | reading the view mode for `'projects'`/`'root'` with `'list'` stored | `'list'` |
| hub-domain-data-019 | write-view-mode-swallow | writing view mode `'list'` for `'projects'`/`'root'` when storage fails | resolves without raising |
| hub-domain-data-020 | http-re-exports-auth | importing the shared authenticated-request operation from this module | resolves to the same operation the Auth Client recipe exports |
| hub-domain-data-021 | http-status-duck-typed | the status-code extractor given an error carrying status `404` | `404` |
| hub-domain-data-022 | http-status-duck-typed | the status-code extractor given a plain error with no status | no value |
| hub-domain-data-023 | client-refusal-shape | the client-refusal constructor given message `'bad input'` | an error with message `'bad input'` and status `400` |
| hub-domain-data-024 | is-not-found-derivation | the not-found predicate given an error with status `404` | `true` |
| hub-domain-data-025 | is-conflict-derivation | given status `409` | `true` |
| hub-domain-data-026 | is-forbidden-derivation | given status `403` | `true` |
| hub-domain-data-027 | is-service-unavailable-derivation | given status `503` | `true` |
| hub-domain-data-028 | err-msg-fallback | given an error with message `'boom'`, fallback `'fallback'` | `'boom'` |
| hub-domain-data-029 | err-msg-fallback | given a non-error value `'not an error'`, fallback `'fallback'` | `'fallback'` |
| hub-domain-data-030 | rethrow-conflict-friendly | given an error whose message is `'a project with this name already exists'`, friendly message `'Pick another name'` | raises an error with message `'Pick another name'` |
| hub-domain-data-031 | rethrow-conflict-friendly | given an error with message `'network down'` | rethrows the original error unchanged |
| hub-domain-data-032 | decode-jwt-claims-shape | decoding the token-claims of `'not-a-jwt'` (no dots) | no value |
| hub-domain-data-033 | decode-jwt-claims-shape | decoding a well-formed three-part token whose middle part is valid base64url JSON | the decoded claims object |
| hub-domain-data-034 | decode-jwt-claims-null-safe | decoding a three-part token whose middle part is not valid base64url | no value |
| hub-domain-data-035 | tenant-id-priority | claims containing both an ecosystem id `'e1'` and a tenant id `'t1'` | `'e1'` |
| hub-domain-data-036 | tenant-id-priority | claims containing a tenant id `'t1'` and a project id `'p1'` | `'t1'` |
| hub-domain-data-037 | tenant-id-priority | no token present | no value |
| hub-domain-data-038 | use-tenant-id-memoized | the tenant-id read state rendered twice against the same underlying token | returns the same tenant id both times without re-decoding |
| hub-domain-data-039 | resource-item-key-shape | cache key `'projects'`, tenant `'t1'`, item id `'p-1'` | `('resource-item', 't1', 'projects', 'p-1')` |
| hub-domain-data-040 | revalidate-resource-items-delegates | invalidating every resource-item entry whose cache key matches `'projects'` | every matching entry is invalidated |
| hub-domain-data-041 | resource-item-cache-key-includes-tenant | the resource-item read state for cache key `'projects'`, item `'p-1'`, under tenant `'t1'` | cache key `('resource-item', 't1', 'projects', 'p-1')` |
| hub-domain-data-042 | resource-item-enabled-gate | the resource-item read state with no item id supplied | the load operation is never invoked |
| hub-domain-data-043 | resource-item-error-reporting-gated | the load operation fails with error reporting left at its default | the failure is reported naming the resource-item feature, the load step, and cache key `'projects'`, before the failure propagates |
| hub-domain-data-044 | resource-item-error-reporting-gated | the load operation fails with error reporting explicitly disabled | the failure is not reported; it still propagates |
| hub-domain-data-045 | resource-item-no-retry | the load operation fails once | no retry occurs; the error is set after the first failure |
| hub-domain-data-046 | resource-item-cache-retention | inspecting the read state's resolved cache settings | the retention period equals the configured 30-minute value (1,800,000 ms) |
| hub-domain-data-047 | resource-item-placeholder-data | a seed value is supplied before the load settles | the seed value is shown and the settled indicator is `false` |
| hub-domain-data-048 | resource-item-is-settled-sticky | the load resolves, then a background refresh begins for the same item id | the settled indicator remains `true` throughout the refresh |
| hub-domain-data-049 | resource-item-is-missing-derivation | the load fails with a not-found-shaped error | the missing indicator is `true` |
| hub-domain-data-050 | resource-item-error-message-fallback | the load fails with a plain string value rather than an error | the error message is `'Failed to load.'` |
| hub-domain-data-051 | resource-item-reload-null-id-behavior | calling reload with no item id | open question — see Behavioral Requirements; not exercised by the reference tests |
| hub-domain-data-052 | resource-item-writer-write-or-evict | writing a non-null row through the cache writer | the row is written into the cache |
| hub-domain-data-053 | resource-item-writer-write-or-evict | writing a null value through the cache writer | the cache entry is evicted, not written as a null placeholder |
| hub-domain-data-054 | resource-item-prefetch-never-throws | prefetching an item whose load fails | the prefetch call never raises |
| hub-domain-data-055 | resource-item-prefetch-cleanup-conditional | a prefetch's load fails, then a concurrent mount's load for the same id succeeds before the prefetch's cleanup runs | the entry is left holding the successful data, not removed |
| hub-domain-data-056 | resource-list-key-shape | cache key `'projects'`, tenant `'t1'` | `('resource-list', 't1', 'projects')` |
| hub-domain-data-057 | revalidate-resources-delegates | invalidating every resource-list entry whose cache key is `'workspaces'` | every matching entry is invalidated |
| hub-domain-data-058 | resource-list-error-reporting-gated | the load fails with error reporting left at its default | the failure is reported naming the resource-list feature, the load step, and cache key `'projects'` |
| hub-domain-data-059 | resource-list-no-retry | the load fails once | no retry occurs |
| hub-domain-data-060 | resource-list-cache-retention | inspecting the read state's resolved cache settings | the retention period equals the configured 30-minute value |
| hub-domain-data-061 | resource-list-reload-identity-guard | the same load-function identity passed across two renders | no cancel/refresh occurs |
| hub-domain-data-062 | resource-list-reload-identity-guard | a new load-function identity passed with the same cache key/tenant | the in-flight request is cancelled and refreshed |
| hub-domain-data-063 | resource-list-reload-rethrows | calling reload when the underlying refresh resolves with an error | reload's returned outcome carries that same error |
| hub-domain-data-064 | resource-list-set-items-writes-through | setting new rows through setItems | the rows are written directly into the cache |
| hub-domain-data-065 | resource-list-is-fetching-derivation | a read state actively fetching and still pending its first result | the loading indicator is `true` |
| hub-domain-data-066 | resource-list-error-status-derivation | the load fails with a conflict-shaped (409) error | the error status is `409` |
| hub-domain-data-067 | resource-list-error-message-fallback | the load fails with a plain object rather than an error | the error message is `'Failed to load.'` |
| hub-domain-data-068 | make-entity-delete-handler-sequence | the delete resolves, and the last-shown id for the base path equals the deleted id | the last-shown id is cleared, then navigation to the base path's `all` view occurs, then a reload is attempted |
| hub-domain-data-069 | make-entity-delete-handler-sequence | the delete resolves, and the last-shown id differs from the deleted id | the last-shown id is not cleared; navigation and reload still occur |
| hub-domain-data-070 | make-entity-delete-handler-del-not-caught | the delete itself fails | the handler's outcome carries that failure; navigation never occurs |
| hub-domain-data-071 | make-entity-delete-handler-del-not-caught | the delete resolves but the subsequent reload fails | the handler's outcome still resolves successfully (the reload failure is swallowed) |
| hub-domain-data-072 | workspace-prefs-cache-key | caching workspace `'acme'` with prefix `'adh'` | writes under storage key `'adh:home:workspace'` |
| hub-domain-data-073 | read-cached-workspace-safe-without-storage | reading the cached workspace with no persisted-storage environment available | returns a safe empty result, no failure raised |
| hub-domain-data-074 | write-cached-workspace-swallow | caching workspace `'acme'` when storage fails | resolves without raising |
| hub-domain-data-075 | workspace-prefs-get-unwraps | reading workspace preferences when the server reports not-found | resolves to an empty object, never raises |
| hub-domain-data-076 | workspace-prefs-get-unwraps | reading workspace preferences when the server returns preferences containing slug `'acme'` | resolves to `{ slug: 'acme' }` |
| hub-domain-data-077 | workspace-prefs-put-full-replace | writing preferences `{ slug: 'acme' }` | issues a PUT request to `/api/me/workspace-prefs` with body `{ slug: 'acme' }` |
| hub-domain-data-078 | workspace-list-cache-key-constant | the workspace-list cache key | `('workspaces')` |
| hub-domain-data-079 | notify-workspaces-changed-dual-invalidate | announcing that the workspace list changed | the workspace-list cache entry is invalidated directly, and a matching invalidation accepts a resource-list entry keyed `'workspaces'` while rejecting one keyed `'organizations'` |
| hub-domain-data-080 | notify-workspaces-changed-swallows | announcing a change when the underlying invalidation fails | does not raise or produce an unhandled failure |
| hub-domain-data-081 | notify-workspaces-changed-dispatches-event | subscribing a listener, then announcing a change | the listener is called exactly once |
| hub-domain-data-082 | on-workspaces-changed-subscribe | subscribing, unsubscribing, then announcing a change again | the listener is not called again |
| hub-domain-data-083 | check-workspace-slug-available | checking availability of slug `'a b'` | issues a GET request to `/api/auth/slug-available/a%20b` |
| hub-domain-data-084 | workspace-list-drops-team-rows | the workspace list includes one row of type `'team'` | that row is excluded from the result |
| hub-domain-data-085 | workspace-list-ordering | the workspace list has one individual row and two organization rows named `'Zeta'` and `'Acme'` | order is `[individual, 'Acme', 'Zeta']` |

## Edge Cases

- **Null/empty input**: The tenant-id derivation and the token-claims
  decoder MUST return no value for an absent token or an empty string,
  respectively (hub-domain-data-032, hub-domain-data-037). The workspace
  query-string builder MUST return an empty string when no workspace is
  supplied (hub-domain-data-008). Reading the last-shown id with nothing
  stored MUST return no value (hub-domain-data-012).
- **Boundary/malformed values**: A token with no dot, one dot, or a payload
  that is not valid base64url/JSON MUST all decode to no value via the
  token-claims decoder (hub-domain-data-032, hub-domain-data-034), relying
  entirely on the base64url-JSON decoding operation's own contract (see the
  Auth Client recipe) — this component adds no additional payload
  validation of its own. A stored view-mode value that is neither `'cards'`
  nor `'list'` MUST be rejected back to the `'cards'` default rather than
  passed through (hub-domain-data-017).
- **Concurrent access**: A prefetch racing a mount's own read of the same
  item MUST NOT let the prefetch's failure cleanup remove data a concurrent
  success has since written (hub-domain-data-055). Two renders of the
  resource-list read state with the same load-function identity MUST NOT
  cancel/refetch, but a changed load-function identity (with cache
  key/tenant unchanged) MUST (hub-domain-data-061, hub-domain-data-062) —
  this guard exists specifically because a naive effect keyed only on mount
  would otherwise refetch on every render.
- **Error states**: Every read state's underlying load operation MUST
  rethrow whatever its load/delete callback raises after optionally
  reporting it, never swallowing a primary read/write failure
  (resource-item-error-reporting-gated,
  resource-list-error-reporting-gated); the one deliberate exception is the
  entity-delete handler's post-delete reload, whose failure is swallowed
  because the delete itself already succeeded (see Design Decisions).
- **Offline/disconnected state**: Neither the resource-item nor the
  resource-list read state defines its own retry policy for a network-level
  failure — both explicitly disable automatic retry (resource-item-no-retry,
  resource-list-no-retry), so a caller that wants offline resilience must
  layer it on the load/delete callback itself; this component's own
  contract is to surface the failure promptly, not to mask it behind hidden
  retries.
- **Storage unavailable** (private browsing, disabled storage — an edge
  case specific to browser-hosted implementations, with no analog on a
  platform with a conventional persisted-settings store): every last-shown-id
  and view-mode operation and the cached-workspace operations MUST swallow a
  thrown storage exception rather than propagate it, degrading to the
  documented default (no value/`'cards'`) rather than crashing a render.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| storage-key prefix | `string` (via the data-configuration setter) | `'adh'` | Prefix for every FTD key (`<prefix>:ftd:...`) and the cached-workspace key (`<prefix>:home:workspace`) |
| workspace-list cache key | exported constant | `('workspaces')` | Cache key the workspace switcher's own list is cached under |
| workspace-list-changed event name | exported constant | `'adh:workspaces-changed'` | Name of the event the workspace-list-changed announcement operation broadcasts |
| resource cache-retention period | imported constant (defined alongside the shared cache, not one of this component's own files) | `1,800,000` ms (30 min) | Retention period every resource-list/resource-item entry this component mints uses |
| `reportErrors` | caller-supplied option, per call to the resource-item/resource-list read state | `true` | Gates whether a load failure is sent to the failure-reporting sink |
| `seedFrom` | caller-supplied option, per call to the resource-item read state | `undefined` | Supplies a placeholder value (never treated as settled) while the real read is in flight |

## Deep Linking

Not applicable: this component defines no URL scheme, route, or platform
deep-link registration of its own, and parses no inbound URL itself. The
entity-delete handler's navigation call uses a caller-supplied navigation
function, not a link scheme this component owns.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `resourceItem.loadFailedFallback` | Failed to load. | The resource-item read state's returned error message when the underlying failure is not an error instance |
| `resourceList.loadFailedFallback` | Failed to load. | The resource-list read state's returned error message when the underlying failure is not an error instance |

Both occurrences are the same hardcoded English literal, with no lookup
table, message-catalog entry, or locale parameter anywhere in this
component — there is no localization mechanism in this component at all.
This is a plain fact about the source, not a gap: a port to a platform with
a localization layer MUST decide, as a design choice outside this contract,
whether and how to route this string through it.

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior of its own. Those
display options act on whatever list or detail UI a host renders around the
resource-list/resource-item read states, not on this headless module.

## Feature Flags

Not applicable: no part of this component defines or reads a feature-flag
key. Every conditional path (whether an id is present, whether error
reporting is set, whether a stored view-mode value is valid) is derived
from a caller argument or stored state, never from a flag this module owns.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
product-telemetry event. The failure-reporting calls in the
resource-item/resource-list read states send operational error diagnostics
to the same injected sink the Auth Client recipe's own Logging section
documents — failure telemetry, not product-analytics events.

## Privacy

- **Data collected**: This component collects no new personal data of its
  own. It caches, in memory or in persisted local storage, whatever rows
  and preference objects its callers already fetched: resource lists/items
  keyed by an opaque tenant id (ecosystem id/tenant id/project id, read via
  the tenant-id read state, never re-derived or stored separately by this
  module), a last-selected id and view-mode string per collection (FTD),
  and a cached workspace slug.
- **Storage**: The FTD last-id/view-mode values and the cached workspace
  slug live in persisted local storage under keys `<prefix>:ftd:...` and
  `<prefix>:home:workspace` as plaintext — readable by anything with access
  to that storage, the same tradeoff the Auth Client recipe's own Privacy
  section documents for the access token; none of these values is itself a
  credential. Resource lists/items live only in an in-memory cache, never
  written to persisted storage.
- **Transmission**: Every network call this component makes goes through
  the shared authenticated request layer the Auth Client recipe documents;
  this module adds no transmission channel of its own.
- **Retention**: Resource-list/resource-item cache entries persist in
  memory for the configured cache-retention period (30 minutes) after their
  last observer goes away, and the whole cache is cleared the moment the
  signed-in principal changes (a session-watching mechanism outside this
  component, but the reason a tenant-keyed cache entry cannot survive a
  sign-out/sign-in on a shared machine). FTD and workspace-slug
  persisted-storage entries persist until explicitly overwritten or the
  host clears its storage; this component enforces no TTL on them.

## Logging

Not applicable: no part of this component calls a console/log API directly.
The only diagnostic path is the failure-reporting call inside the
resource-item/resource-list read states, which delegates to the sink the
Auth Client recipe's own Logging section documents, not duplicated here.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/services/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe. |
