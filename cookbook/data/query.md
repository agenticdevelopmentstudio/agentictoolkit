---
id: 0fcd16c1-a8da-4184-b63f-97b68ed6378d
title: Hub Domain Query
domain: agentictoolkit://cookbook/data/query
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Web SPA''s shared TanStack Query runtime: a module-scope singleton QueryClient,
  provider, and consumer hook every toolkit react-query hook fetches through, with
  whole-cache clearing when the signed-in principal changes.'
platforms:
- typescript
- web
tags:
- cache
- react-query
- session
- web
depends-on:
- agentictoolkit://cookbook/auth/auth-client
related:
- agentictoolkit://cookbook/data
- agentictoolkit://cookbook/data/ecosystems
references:
- packages/web/packages/data/src/query/index.tsx (agentictoolkit)
- packages/web/packages/data/src/query/__tests__/toolkit-query-provider.test.tsx (agentictoolkit)
- packages/web/packages/data/src/__tests__/query-client.test.tsx (agentictoolkit)
- packages/web/packages/auth/src/tokens.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Query

## Overview

The `hub-domain-query` ingredient is `@agentic-toolkit/data`'s own TanStack
Query runtime: the single file `packages/web/packages/data/src/query/index.tsx`
that every `@agentic-toolkit/*` react-query hook — including this package's
own `use-resource-item.ts`/`use-resource-list.ts` (see `hub-domain-data`) and
`use-workspace-default-ecosystem.ts` (see `hub-domain-ecosystems`) — reads
through, rather than any `QueryClient` a host application mounts for its own
code. It owns exactly one browser-side `QueryClient` per tab, held at module
scope specifically so it survives a Next.js App Router remount that would
otherwise reset a component-state client to an empty cache on every
same-segment navigation; a `ToolkitQueryProvider` for mounting that client
declaratively, where nesting or mounting it more than once is a no-op rather
than a second cache; a `useToolkitQueryClient()` hook that resolves to the
same client whether or not a provider is mounted above the caller, and even
when a host's own `QueryClientProvider` (from the same physical copy of
`@tanstack/react-query`) is mounted above it instead; and a `watchSession()`
guard that empties the whole cache the instant the signed-in principal
changes, so a second user on a shared machine is never served the first
user's cached rows. It has no visual surface of its own.

## Behavioral Requirements

- **resource-gc-time-constant**: The exported constant `RESOURCE_GC_TIME`
  MUST equal `30 * 60 * 1000` (1,800,000 ms) (`query/index.tsx`).
- **query-defaults-stale-and-retry**: `makeQueryClient()` MUST construct a
  `QueryClient` whose `defaultOptions.queries` sets `staleTime` to
  `5 * 60 * 1000` (300,000 ms) and `retry` to `1` (`query/index.tsx`).
- **resource-key-gc-time-pinned**: `makeQueryClient()` MUST call
  `client.setQueryDefaults(['resource-list'], { gcTime: RESOURCE_GC_TIME })`
  and `client.setQueryDefaults(['resource-item'], { gcTime: RESOURCE_GC_TIME })`
  before returning the client, so every query keyed under either prefix —
  including one minted by a prefetch or a `setQueryData` call with no
  observer of its own — uses `RESOURCE_GC_TIME` rather than the client-wide
  `gcTime` default (`query/index.tsx`).
- **server-client-per-call**: `getToolkitQueryClient()` MUST return a newly
  constructed `QueryClient` from `makeQueryClient()` on every call for which
  `typeof window === 'undefined'`, and MUST NOT reuse a client across such
  calls (`query/index.tsx`).
- **browser-client-singleton**: `getToolkitQueryClient()` MUST return the
  identical `QueryClient` instance on every call for which
  `typeof window !== 'undefined'`, for the lifetime of the module
  (`query/index.tsx`; `query-client.test.tsx`).
- **browser-client-lazy-construction**: The browser singleton MUST be
  constructed on the first browser call to `getToolkitQueryClient()` — via
  `makeQueryClient()` immediately followed by `watchSession()` — and MUST
  NOT be reconstructed by any later call (`query/index.tsx`, the
  `if (!browserClient)` guard).
- **provider-uses-singleton**: `ToolkitQueryProvider` MUST render a
  `QueryClientProvider` whose `client` prop is `getToolkitQueryClient()`'s
  return value (`query/index.tsx`).
- **provider-nesting-is-idempotent**: Rendering one `ToolkitQueryProvider`
  inside another MUST publish the identical `QueryClient` instance to both
  levels, never two distinct clients (`query/index.tsx`;
  `toolkit-query-provider.test.tsx`).
- **provider-siblings-share-client**: Two independently mounted,
  non-nested `ToolkitQueryProvider` trees MUST also resolve to the identical
  `QueryClient` instance (`toolkit-query-provider.test.tsx`).
- **hook-ignores-ancestor-context**: `useToolkitQueryClient()` MUST return
  the toolkit singleton from `getToolkitQueryClient()` regardless of any
  `QueryClientProvider` mounted above the calling component — including one
  supplying a different `QueryClient` instance from the same physical copy
  of `@tanstack/react-query` (`query/index.tsx`;
  `toolkit-query-provider.test.tsx`).
- **hook-usable-without-provider**: `useToolkitQueryClient()` MUST return a
  usable `QueryClient` when called with no `ToolkitQueryProvider` or
  `QueryClientProvider` mounted above the caller at all (`query/index.tsx`;
  `query-client.test.tsx`).
- **session-watch-registered-once**: `watchSession()` MUST run exactly once
  per browser client construction, bound at the point `browserClient` is
  created, and MUST NOT be re-bound by any later `getToolkitQueryClient()`
  call (`query/index.tsx`).
- **session-watch-initial-subject**: `watchSession()` MUST initialize the
  module-scope `cachedFor` value to `readTokenSubject()`'s result at the
  moment it runs (`query/index.tsx`).
- **session-change-clears-on-subject-change**: On every `onSessionChange`
  notification, the registered `check` callback MUST compare the current
  `readTokenSubject()` value against `cachedFor`, and, only when the two
  differ, MUST call `browserClient.clear()` and update `cachedFor` to the
  new value (`query/index.tsx`).
- **session-refresh-does-not-clear**: An `onSessionChange` notification
  whose `readTokenSubject()` value is unchanged from `cachedFor` — the case
  a token refresh for the same signed-in principal produces, per
  `onSessionChange`'s own contract (see `auth-client`) — MUST NOT clear the
  cache (`query/index.tsx`).
- **cross-tab-session-watch**: `watchSession()` MUST also register `check`
  as a `window` `'storage'` event listener, so the same subject comparison
  and conditional clear run when another browser tab of the same origin
  writes the session storage key (`query/index.tsx`).

## Appearance

Not applicable — this is a headless query-client runtime, not a visual
component.

## States

Not applicable — this is a headless query-client runtime, not a visual
component.

## Accessibility

Not applicable — this is a headless query-client runtime, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-query-001 | browser-client-singleton | `getToolkitQueryClient()` called twice in the browser | both calls return the identical `QueryClient` instance (`query-client.test.tsx`: "is ONE instance in the browser") |
| hub-domain-query-002 | browser-client-singleton, provider-uses-singleton | Render `ToolkitQueryProvider` wrapping a probe that captures `useToolkitQueryClient()`, `unmount()`, then render the same tree again and capture again | both captured clients are the identical instance (`query-client.test.tsx`: "survives a provider that is unmounted and mounted again") |
| hub-domain-query-003 | hook-usable-without-provider | Render the probe with no `ToolkitQueryProvider`/`QueryClientProvider` anywhere above it | `useToolkitQueryClient()` resolves without throwing, to the same instance `getToolkitQueryClient()` returns directly (`query-client.test.tsx`: "hands a consumer the same client with NO provider above it") |
| hub-domain-query-004 | server-client-per-call | Stub `window` to `undefined`, call `getToolkitQueryClient()` twice | the two returned clients are NOT the identical instance (`query-client.test.tsx`: "makes a FRESH client per call on the server") |
| hub-domain-query-005 | provider-nesting-is-idempotent | Render one `ToolkitQueryProvider` nested inside another, each with its own client-capturing probe | the inner probe's client is the identical instance as the outer probe's client (`toolkit-query-provider.test.tsx`: "hands a nested provider the SAME QueryClient instance as the outer one") |
| hub-domain-query-006 | provider-siblings-share-client | Render two separate, non-nested `ToolkitQueryProvider` trees, each with its own probe | both probes resolve to the identical client instance (`toolkit-query-provider.test.tsx`: "gives two separate, non-nested mounts that same one client") |
| hub-domain-query-007 | hook-ignores-ancestor-context | Mount a host `QueryClientProvider` around a distinct `QueryClient` (`staleTime` 30,000 ms, `retry` 3) wrapping a `ToolkitQueryProvider` and a probe | the probe's client is not the host client, and its resolved `staleTime` is 300,000 ms, not 30,000 ms (`toolkit-query-provider.test.tsx`: "does NOT adopt a host-mounted QueryClient from the same react-query copy") |
| hub-domain-query-008 | query-defaults-stale-and-retry | Inspect a freshly constructed client's `getDefaultOptions().queries` | `staleTime` is 300,000 ms and `retry` is `1` (traced to `makeQueryClient` in `query/index.tsx`; the `staleTime` half is also exercised indirectly by vector 007) |
| hub-domain-query-009 | resource-gc-time-constant | Read the exported `RESOURCE_GC_TIME` value | `1,800,000` (30 minutes) (`query/index.tsx`) |
| hub-domain-query-010 | resource-key-gc-time-pinned | Inspect the resolved query defaults for a key beginning `['resource-list', ...]` and one beginning `['resource-item', ...]` on a freshly constructed client | both resolve `gcTime` to `RESOURCE_GC_TIME`; a key under neither prefix resolves the client's unpinned default instead (traced to the two `setQueryDefaults` calls in `query/index.tsx`; exercised indirectly through `use-resource-item.test.tsx`/`use-resource-list.test.tsx` — see `hub-domain-data`) |
| hub-domain-query-011 | browser-client-lazy-construction | Call `getToolkitQueryClient()` a first time in the browser, then a second time | `makeQueryClient()` and `watchSession()` each run exactly once, on the first call only (traced to the `if (!browserClient)` guard in `query/index.tsx`; no test in this package spies on this directly) |
| hub-domain-query-012 | session-watch-initial-subject | With a valid access token for subject `'user-1'` already stored, trigger the first browser `getToolkitQueryClient()` call | the internal `cachedFor` value is initialized to `'user-1'` (traced to `watchSession`'s `cachedFor = readTokenSubject()` in `query/index.tsx`; no test in this package exercises this today) |
| hub-domain-query-013 | session-change-clears-on-subject-change | With the singleton already constructed for subject `'user-1'`, change the stored token to subject `'user-2'` and invoke the `onSessionChange` listener | `browserClient.clear()` is called and `cachedFor` becomes `'user-2'` (traced to `watchSession`'s `check` function in `query/index.tsx`; no test in this package exercises this today — see Design Decisions) |
| hub-domain-query-014 | session-refresh-does-not-clear | With the singleton already constructed for subject `'user-1'`, refresh the token for the SAME subject `'user-1'` and invoke the `onSessionChange` listener | `browserClient.clear()` is NOT called (traced to the `subject === cachedFor` early return in `query/index.tsx`; no test in this package exercises this today) |
| hub-domain-query-015 | cross-tab-session-watch | With the singleton constructed for subject `'user-1'`, dispatch a `window` `'storage'` event (simulating another tab writing subject `'user-2'`'s token) without ever invoking the `onSessionChange` listener directly | the same comparison runs and clears the cache exactly as vector 013 (traced to `window.addEventListener("storage", check)` in `query/index.tsx`; no test in this package exercises this today) |
| hub-domain-query-016 | provider-uses-singleton | Render `ToolkitQueryProvider` and inspect the `client` prop it passes to the underlying `QueryClientProvider` | it is exactly `getToolkitQueryClient()`'s current return value (`query/index.tsx`) |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RESOURCE_GC_TIME` | exported constant | `1,800,000` ms (30 min) | `gcTime` every `resource-list`/`resource-item`-prefixed query entry uses, pinned by `makeQueryClient` (`query/index.tsx`) |
| `defaultOptions.queries.staleTime` | hardcoded in `makeQueryClient` | `300,000` ms (5 min) | Client-wide default staleness for every query built on this client |
| `defaultOptions.queries.retry` | hardcoded in `makeQueryClient` | `1` | Client-wide default retry count for every query built on this client |
| `children` | `ReactNode`, `ToolkitQueryProvider` prop | none (required) | Subtree the provider mounts `QueryClientProvider` around |

None of these values is exposed through a caller-facing setter (no
`configureQuery`-style function exists in this file, unlike `configureData`
in `hub-domain-data`); changing any of them requires editing
`query/index.tsx` itself.

## Deep Linking

Not applicable: `query/index.tsx` defines no app URL scheme, Android intent
filter, or platform deep-link registration, and parses no inbound URL.

## Localization

Not applicable: `query/index.tsx` renders no user-facing text. Its only
string literals are internal cache-key segments (`'resource-list'`,
`'resource-item'`) and the `'storage'` DOM event name, none of which is
user-facing.

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior.

## Feature Flags

Not applicable: no file in this component defines or reads a feature-flag
key; every conditional path (`typeof window`, whether `browserClient` is
already set, whether the subject changed) is derived from the runtime
environment or stored session state, never from a flag this module owns.

## Analytics

Not applicable: `query/index.tsx` emits no client-side analytics or
product-telemetry event, and calls no reporting sink of its own.

## Privacy

- **Data collected**: This component collects no new personal data. It
  reads the already-stored access token's `sub` claim, via
  `readTokenSubject()` (documented by `auth-client`), solely to compare it
  against the previously seen value; it never displays, re-derives, or
  persists that claim itself.
- **Storage**: The last-seen subject (`cachedFor`) lives in an in-memory,
  module-scope JavaScript variable — never written to `localStorage`,
  `sessionStorage`, or a cookie, and gone the moment the page/module is
  reloaded. The `resource-list`/`resource-item` cache entries this client
  governs live only in the in-memory `@tanstack/react-query` cache.
- **Transmission**: `query/index.tsx` makes no network call of its own.
- **Retention**: `cachedFor` persists only for the life of the browser tab
  holding the module; the entire query cache it guards is discarded outright
  (`browserClient.clear()`) the instant the signed-in principal changes —
  the mechanism that keeps a second principal on a shared machine from ever
  reading rows cached under the first (`query/index.tsx`).

## Logging

Not applicable: `query/index.tsx` contains no `console.log`, `console.warn`,
`console.info`, or `console.error` call.

## Platform Notes

- **React/Web**: This is the reference implementation. `@tanstack/react-query`
  v5's `QueryClient`/`QueryClientProvider`/`useQueryClient` back the cache
  and its React binding; a module-scope `let` binding backs the one-per-tab
  singleton; `window.addEventListener('storage', ...)` backs the cross-tab
  session watch; `@agentic-toolkit/auth/client`'s `onSessionChange`/
  `readTokenSubject` supply the same-tab session signal and the principal
  comparison value.
- **SwiftUI / AppKit / UIKit**: A `final class` or `actor`-isolated cache
  object (an `NSCache`- or `Dictionary`-backed store keyed the same way the
  react-query keys are) held as a singleton (a static property, or an
  `EnvironmentObject`/`ObservableObject` injected once at the app's root)
  replaces the module-scope `QueryClient`; `NotificationCenter.default`
  (posting and observing a custom notification name) or a Combine
  `PassthroughSubject` replaces `onSessionChange`; there is no
  same-origin-other-tab analog to port, since an Apple app is a single
  process — a second window of the same app sharing the cache singleton
  in-process already covers that case without any storage-event equivalent.
- **Compose / Android**: A Kotlin `object` (Kotlin's own module-scope
  singleton) holding a `MutableStateFlow`- or coroutine-`Deferred`-backed
  cache map replaces the `QueryClient` singleton; a `SharedFlow`/`Channel`
  emitted on sign-in/sign-out/refresh replaces `onSessionChange`; as with
  Apple, there is no cross-tab analog to port on a single-process Android
  app.
- **WinUI 3**: A cache service — `Microsoft.Extensions.Caching.Memory`'s
  `IMemoryCache`, or a hand-rolled `ConcurrentDictionary`-backed store keyed
  identically to the react-query keys — registered as a DI `Singleton` (via
  `IServiceCollection.AddSingleton`) is the idiomatic replacement for the
  module-scope `QueryClient`, constructed once at app startup rather than
  lazily on "first browser call" (a WinUI 3 app has no server/browser split
  to distinguish; every launch is the "browser" case). A C# `event` (or an
  `IObservable<Unit>` via `System.Reactive`, to avoid the listener-leak a
  `WeakEventManager` exists to prevent) raised by the same code that writes
  or clears the stored tokens replaces `onSessionChange`; the handler MUST
  apply the identical "compare the subject, only clear on an actual change"
  guard `check` implements here, so a token refresh for the same signed-in
  user does not needlessly discard the cache. There is no `window`
  `'storage'`-event equivalent for a single-process WinUI 3 app; if the app
  supports multiple top-level windows in one process, they already share
  the one DI-scoped singleton in-process, so no cross-window signal is
  needed at all — a genuinely separate-process scenario (e.g. a companion
  process) would instead need an explicit IPC channel, which has no
  counterpart in this source.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/query/index.tsx` |

## Design Decisions

**Decision**: The browser `QueryClient` is held in a module-scope `let`
binding rather than component state, and is constructed lazily on the first
browser call to `getToolkitQueryClient()` rather than eagerly at module
load.
**Rationale**: The Next.js App Router folds a dynamic route segment's value
into React's remount key, so a component-state client is destroyed and
rebuilt — with an empty cache — on every same-segment navigation; a
module-scope client outlives that remount. Lazy construction means the
server bundle importing this module never allocates a browser client it
will never use.
**Approved**: pending

**Decision**: `getToolkitQueryClient()` returns a brand-new client on every
call when `typeof window === 'undefined'`, rather than a server-side
singleton.
**Rationale**: A shared server-side client would leak one request's cached
data into another request's render; a fresh client per call is the only
safe choice for a runtime that may serve concurrent requests from the same
process.
**Approved**: pending

**Decision**: `useToolkitQueryClient()` passes the toolkit singleton
explicitly to react-query's `useQueryClient(client)` rather than relying on
`useContext`/`QueryClientContext` alone.
**Rationale**: Dozens of call sites across `@agentic-toolkit/*` packages use
this hook, and requiring every one of them to be wrapped in a
`ToolkitQueryProvider` — or trusting that a host's own `QueryClientProvider`
resolves to the toolkit's physical copy of `@tanstack/react-query` rather
than the host's own — would reintroduce exactly the "No QueryClient set" and
silent-cross-copy failures the module's own header comment documents.
**Approved**: pending

**Decision**: `watchSession()` binds `check` to `onSessionChange` once, at
singleton construction, and the unsubscribe function `onSessionChange`
returns is discarded; the `window` `'storage'` listener registered
alongside it is likewise never removed via `removeEventListener`.
**Rationale**: The singleton — and the listener pair that keeps it
correctly scoped to the current principal — is meant to live for exactly as
long as the browser tab holding the module does; there is no earlier point
in that lifetime at which either listener should stop watching, so no
cleanup path exists.
**Approved**: pending

**Decision**: `check` compares `readTokenSubject()`'s value against
`cachedFor` and clears the cache only when they differ, rather than
clearing on every `onSessionChange` notification.
**Rationale**: `onSessionChange` fires identically for a sign-in, a
sign-out, and a same-user token refresh (per `auth-client`'s own documented
contract, which explicitly calls out that a listener doing something
expensive must compare first); clearing unconditionally would wipe the
entire cache — and force every mounted panel to refetch cold — on every
routine token refresh, not only on an actual principal change.
**Approved**: pending

**Decision**: The cross-tab guard subscribes the SAME `check` function to
the `window` `'storage'` event, in addition to `onSessionChange`, rather
than relying on `onSessionChange` alone.
**Rationale**: `onSessionChange` is an in-memory, same-module signal — it
never fires in a second tab of the same origin that did not itself perform
the write. A browser `'storage'` event fires only in tabs that did NOT
write the change, which is exactly the complementary set `onSessionChange`
cannot reach; together the pair cover every tab.
**Approved**: pending

**Decision**: `query/index.tsx` never dehydrates a server-rendered client's
cache into the browser singleton — there is no `dehydrate`/`HydrationBoundary`
call anywhere in this file — so any data fetched while rendering on the
server is discarded, and the browser singleton's first read of the same
key always starts from an empty cache.
**Rationale**: This is the direct, and non-obvious, consequence of the
fresh-per-request server client decision above: since a server-rendered
client is never reused, nothing exists at the point a request finishes to
hand its data to a later browser singleton that did not exist yet. A
developer reading only the browser-side singleton behavior could otherwise
expect server-fetched data to "already be there" on first paint.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | Performance |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

`separation-of-concerns` **passed**: this file is pure data-layer
infrastructure — a cache client, a provider, and a subscription guard — with
no presentation code and no domain-specific fetch logic of its own; every
concrete query lives in a sibling file (see `hub-domain-data`,
`hub-domain-ecosystems`). `unit-test-coverage` is **partial**: the
singleton, per-call-server, provider-nesting, and context-independence
behaviors are all directly asserted by `query-client.test.tsx` and
`toolkit-query-provider.test.tsx`, but `watchSession`'s entire
session-change contract — the initial subject capture, the compare-then-clear
guard, and the cross-tab `'storage'` listener — has no test exercising it
anywhere in this package (see the open question recorded against
`session-change-clears-on-subject-change` in the Conformance Test Vectors).
`caching-strategy` **passed**: this file is the single place that defines
the shared invalidation policy (5-minute `staleTime`, single retry, a
30-minute `gcTime` pinned by key prefix so a prefetch or a post-write
`setQueryData` survives as long as an observed read) every toolkit query
inherits, plus the whole-cache invalidation on principal change; the actual
remote fetches these policies govern are documented by the recipes for the
queries that make them. `fault-tolerance` **passed**: the module tolerates
every unpredictable-state shape its own tests exercise — server vs. browser
execution, a provider nested inside another, sibling providers, no provider
at all, and a host's own differently-configured `QueryClientProvider` —
without ever throwing or adopting the wrong client. `data-integrity`
**passed**: `watchSession`'s whole-cache clear on a principal change is
exactly a corrupt-data guard — it exists specifically to stop a second
signed-in principal from reading data cached under the first, and it is a
second, independent layer against that on top of the tenant-keyed cache
segments `hub-domain-data` describes. `data-minimization` **passed**: the
only identity value this file reads, `readTokenSubject()`'s `sub` claim, is
held only in an in-memory comparison variable and is never persisted,
transmitted, or exposed beyond that comparison.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe. |
