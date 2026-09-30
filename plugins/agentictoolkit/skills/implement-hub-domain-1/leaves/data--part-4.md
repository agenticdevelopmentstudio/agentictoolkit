<!-- leaf: implement-hub-domain-1/data--part-4 · source: hub-domain-data.md -->

# Hub Domain Data — continued (part 4)

**Rules** (cite as `implement-hub-domain-1/data--part-4#<slug>`):

- `winui-3` MUST — Microsoft.Extensions.Caching.Memory's IMemoryCache (or a hand-rolled Dictionary<(string tenantId, string cacheKey, …
- `decision` MUST — This recipe records reload()'s no-op-when-no-id doc-comment discrepancy as an open question rather than restating the …

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
