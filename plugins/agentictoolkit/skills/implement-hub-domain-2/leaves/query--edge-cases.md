<!-- leaf: implement-hub-domain-2/query--edge-cases · source: hub-domain-query.md -->

# Hub Domain Query

**Rules** (cite as `implement-hub-domain-2/query--edge-cases#<slug>`):

- `null-empty-input` MUST — watchSession()'s initial cachedFor MUST be null when readTokenSubject() returns null at singleton-construction time — …
- `concurrent-access` MUST — Every rendering shape this file's own tests cover — nested ToolkitQueryProviders, two sibling ToolkitQueryProvider …
- `offline-disconnected-state` MUST — makeQueryClient() sets one default retry policy (retry: 1) applied to every query built on getToolkitQueryClient(), but …

## Edge Cases

- **Null/empty input**: `watchSession()`'s initial `cachedFor` MUST be
  `null` when `readTokenSubject()` returns `null` at singleton-construction
  time — no signed-in principal (`query/index.tsx`). A later sign-in (the
  subject moving from `null` to a non-null value) MUST be treated as an
  ordinary subject change by `check`'s `subject === cachedFor` comparison,
  which carries no null-special-case, and so MUST also clear the cache
  (`query/index.tsx`).
- **Boundary values**: This file exposes no caller-adjustable numeric input
  with a valid range; `RESOURCE_GC_TIME` (1,800,000 ms), the default
  `staleTime` (300,000 ms), and `retry` (`1`) are hardcoded constants in
  `makeQueryClient`, not boundaries on a caller-supplied value
  (`query/index.tsx`).
- **Concurrent access**: Every rendering shape this file's own tests cover —
  nested `ToolkitQueryProvider`s, two sibling `ToolkitQueryProvider` trees,
  and `useToolkitQueryClient()` with no provider at all — MUST resolve to
  the SAME browser singleton, never a second independently constructed
  `QueryClient` (`query-client.test.tsx`; `toolkit-query-provider.test.tsx`).
  A `getToolkitQueryClient()` call that re-enters synchronously while the
  singleton is under construction MUST see `browserClient` already
  assigned, because the assignment on the line before `watchSession()` runs
  completes, in JavaScript's single-threaded execution model, before any
  re-entrant call can execute (`query/index.tsx`) — this is a fact about
  that execution model, not a race the code guards against separately. Two
  browser tabs of the same origin changing the signed-in principal at
  overlapping times MUST each independently clear their own tab's cache:
  the tab that wrote the change via its own `onSessionChange` path, and
  every other tab of that origin via the `'storage'` event
  (`query/index.tsx`).
- **Error states**: `query/index.tsx` calls no network, file-system, or
  database dependency of its own — its only external calls are
  `readTokenSubject()`, `onSessionChange()`, `window.addEventListener()`,
  and `QueryClient` construction, none of which this component's tests or
  `auth-client`'s own documented contract for `readTokenSubject`
  (guaranteed to return `null` rather than throw on a malformed token) show
  as failing. This component therefore defines no dependency-failure path
  of its own; a downstream query's network failure is documented by the
  recipe for that query (e.g. `hub-domain-data`), not here.
- **Offline/disconnected state**: `makeQueryClient()` sets one default
  retry policy (`retry: 1`) applied to every query built on
  `getToolkitQueryClient()`, but this file implements no network-reachability
  detection, reconnect listener, or offline queue of its own, and leaves
  TanStack Query's own default reconnect-triggered refetch behavior
  unmodified (`query/index.tsx`). A caller needing offline resilience beyond
  one retry MUST layer it on its own query function, not on this shared
  client.
