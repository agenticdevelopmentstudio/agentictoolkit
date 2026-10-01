---
id: 0fcd16c1-a8da-4184-b63f-97b68ed6378d
title: Query Cache
domain: agentictoolkit://cookbook/data/services/query-cache
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Shared query-cache runtime: a singleton cache client, provider, and
  consumer accessor every toolkit data hook fetches through, with whole-cache
  clearing when the signed-in principal changes.'
platforms:
- typescript
- web
tags:
- cache
- session
depends-on:
- agentictoolkit://cookbook/data/services/auth/auth-client
related:
- agentictoolkit://cookbook/data/services/resource-data
- agentictoolkit://cookbook/adh/hub/ecosystems/ecosystems
references:
- packages/web/packages/data/src/query/index.tsx (agentictoolkit)
- packages/web/packages/data/src/query/__tests__/toolkit-query-provider.test.tsx (agentictoolkit)
- packages/web/packages/data/src/__tests__/query-client.test.tsx (agentictoolkit)
- packages/web/packages/auth/src/tokens.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Query Cache

## Overview

This recipe is the shared query-cache runtime that every toolkit
data-fetching hook reads through, rather than any cache client a host
application mounts for its own code. It owns exactly one client-side cache
instance per tab, held at module scope specifically so it survives a
same-segment route remount that would otherwise reset a component-state
cache to empty on every navigation; a provider component for mounting that
cache declaratively, where nesting it inside another instance of itself, or
mounting it more than once, is a no-op rather than a second cache; a
consumer accessor that resolves to the same cache whether or not a provider
is mounted above the caller, and even when a host's own, differently
configured cache-provider component (built on the same underlying cache
library) is mounted above it instead; and a session-watch guard that empties
the whole cache the instant the signed-in principal changes, so a second
user on a shared machine is never served the first user's cached rows. It
has no visual surface of its own.

## Behavioral Requirements

- **resource-gc-time-constant**: The exported resource-cache retention
  constant MUST equal `30 * 60 * 1000` (1,800,000 ms).
- **query-defaults-stale-and-retry**: The cache-client factory MUST
  construct a cache client whose default query options set the staleness
  window to `5 * 60 * 1000` (300,000 ms) and the retry count to `1`.
- **resource-key-gc-time-pinned**: The cache-client factory MUST pin a
  retention time equal to the resource-cache retention constant for every
  query keyed under the `resource-list` prefix and for every query keyed
  under the `resource-item` prefix, before returning the client, so every
  query keyed under either prefix — including one minted by a prefetch or a
  direct cache write with no observer of its own — uses that retention time
  rather than the client-wide retention default.
- **server-client-per-call**: The singleton cache accessor MUST return a
  newly constructed cache client from the cache-client factory on every call
  made with no interactive host environment present, and MUST NOT reuse a
  client across such calls.
- **browser-client-singleton**: The singleton cache accessor MUST return the
  identical cache-client instance on every call made with an interactive
  host environment present, for the lifetime of the module.
- **browser-client-lazy-construction**: The browser-side singleton MUST be
  constructed on the first such call to the singleton cache accessor — via
  the cache-client factory immediately followed by the session-watch guard —
  and MUST NOT be reconstructed by any later call.
- **provider-uses-singleton**: The cache provider component MUST render its
  underlying cache-provider wrapper with the singleton cache accessor's
  return value as the client it publishes.
- **provider-nesting-is-idempotent**: Rendering one instance of the cache
  provider component inside another MUST publish the identical cache-client
  instance to both levels, never two distinct clients.
- **provider-siblings-share-client**: Two independently mounted, non-nested
  trees each rendering the cache provider component MUST also resolve to the
  identical cache-client instance.
- **hook-ignores-ancestor-context**: The consumer accessor MUST return the
  toolkit singleton from the singleton cache accessor regardless of any
  cache-provider component mounted above the calling component — including
  one supplying a different cache-client instance built on the same
  underlying cache library.
- **hook-usable-without-provider**: The consumer accessor MUST return a
  usable cache client when called with no cache provider component of any
  kind mounted above the caller at all.
- **session-watch-registered-once**: The session-watch guard MUST run
  exactly once per browser-side client construction, bound at the point the
  browser singleton is created, and MUST NOT be re-bound by any later call
  to the singleton cache accessor.
- **session-watch-initial-subject**: The session-watch guard MUST
  initialize its last-seen-subject value to the result of reading the
  token's subject claim at the moment it runs.
- **session-change-clears-on-subject-change**: On every session-change
  notification, the guard's comparison callback MUST compare the current
  result of reading the token's subject claim against the last-seen
  subject, and, only when the two differ, MUST clear the browser singleton's
  entire cache and update the last-seen subject to the new value.
- **session-refresh-does-not-clear**: A session-change notification whose
  subject-claim value is unchanged from the last-seen subject — the case a
  token refresh for the same signed-in principal produces, per session-change
  subscription's own contract (see the authentication client recipe) — MUST
  NOT clear the cache.
- **cross-tab-session-watch**: The session-watch guard MUST also register
  its comparison callback against a cross-tab storage-change notification,
  so the same subject comparison and conditional clear run when another
  browser tab of the same origin writes the session storage key.

## Appearance

Not applicable — this is a headless query-cache runtime, not a visual
component.

## States

Not applicable — this is a headless query-cache runtime, not a visual
component.

## Accessibility

Not applicable — this is a headless query-cache runtime, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-query-001 | browser-client-singleton | The singleton cache accessor called twice in the browser | Both calls return the identical cache-client instance |
| hub-domain-query-002 | browser-client-singleton, provider-uses-singleton | Render the cache provider component wrapping a probe that captures the consumer accessor's result, unmount it, then render the same tree again and capture again | Both captured clients are the identical instance |
| hub-domain-query-003 | hook-usable-without-provider | Render the probe with no cache-provider component of any kind anywhere above it | The consumer accessor resolves without throwing, to the same instance the singleton cache accessor returns directly |
| hub-domain-query-004 | server-client-per-call | With no interactive host environment present, call the singleton cache accessor twice | The two returned clients are NOT the identical instance |
| hub-domain-query-005 | provider-nesting-is-idempotent | Render one instance of the cache provider component nested inside another, each with its own client-capturing probe | The inner probe's client is the identical instance as the outer probe's client |
| hub-domain-query-006 | provider-siblings-share-client | Render two separate, non-nested trees each rendering the cache provider component, each with its own probe | Both probes resolve to the identical client instance |
| hub-domain-query-007 | hook-ignores-ancestor-context | Mount a host's own cache-provider wrapper around a distinct cache client (staleness window 30,000 ms, retry count 3) wrapping the cache provider component and a probe | The probe's client is not the host's client, and its resolved staleness window is 300,000 ms, not 30,000 ms |
| hub-domain-query-008 | query-defaults-stale-and-retry | Inspect a freshly constructed client's resolved default query options | Staleness window is 300,000 ms and retry count is `1` (the staleness half is also exercised indirectly by vector 007) |
| hub-domain-query-009 | resource-gc-time-constant | Read the exported resource-cache retention constant | `1,800,000` (30 minutes) |
| hub-domain-query-010 | resource-key-gc-time-pinned | Inspect the resolved defaults for a key beginning `['resource-list', ...]` and one beginning `['resource-item', ...]` on a freshly constructed client | Both resolve their retention time to the resource-cache retention constant; a key under neither prefix resolves the client's unpinned default instead (exercised indirectly through the resource-item/resource-list recipes' own coverage — see the resource-data recipe) |
| hub-domain-query-011 | browser-client-lazy-construction | Call the singleton cache accessor a first time in the browser, then a second time | The cache-client factory and the session-watch guard each run exactly once, on the first call only (no dedicated test in this package exercises this directly) |
| hub-domain-query-012 | session-watch-initial-subject | With a valid access token for subject `'user-1'` already stored, trigger the first browser call to the singleton cache accessor | The internal last-seen subject is initialized to `'user-1'` (no test in this package exercises this today) |
| hub-domain-query-013 | session-change-clears-on-subject-change | With the singleton already constructed for subject `'user-1'`, change the stored token to subject `'user-2'` and invoke the session-change notification | The browser singleton's cache is cleared and the last-seen subject becomes `'user-2'` (no test in this package exercises this today — see Design Decisions) |
| hub-domain-query-014 | session-refresh-does-not-clear | With the singleton already constructed for subject `'user-1'`, refresh the token for the SAME subject `'user-1'` and invoke the session-change notification | The cache is NOT cleared (no test in this package exercises this today) |
| hub-domain-query-015 | cross-tab-session-watch | With the singleton constructed for subject `'user-1'`, dispatch a cross-tab storage-change notification (simulating another tab writing subject `'user-2'`'s token) without ever invoking the session-change notification directly | The same comparison runs and clears the cache exactly as vector 013 (no test in this package exercises this today) |
| hub-domain-query-016 | provider-uses-singleton | Render the cache provider component and inspect the client it passes to its underlying cache-provider wrapper | It is exactly the singleton cache accessor's current return value |

## Edge Cases

- **Null/empty input**: the session-watch guard's initial last-seen subject
  MUST be nothing when reading the token's subject claim returns nothing at
  singleton-construction time — no signed-in principal. A later sign-in (the
  subject moving from nothing to a non-null value) MUST be treated as an
  ordinary subject change by the comparison callback's equality check, which
  carries no null-special-case, and so MUST also clear the cache.
- **Boundary values**: this component exposes no caller-adjustable numeric
  input with a valid range; the resource-cache retention constant
  (1,800,000 ms), the default staleness window (300,000 ms), and the retry
  count (`1`) are hardcoded constants in the cache-client factory, not
  boundaries on a caller-supplied value.
- **Concurrent access**: every rendering shape this component's own tests
  cover — nested cache provider components, two sibling cache-provider
  trees, and the consumer accessor with no provider at all — MUST resolve to
  the SAME browser singleton, never a second independently constructed
  client. A call to the singleton cache accessor that re-enters synchronously
  while the singleton is under construction MUST see the browser singleton
  already assigned, because the assignment on the line before the
  session-watch guard runs completes, in the runtime's single-threaded
  execution model, before any re-entrant call can execute — this is a fact
  about that execution model, not a race the code guards against
  separately. Two browser tabs of the same origin changing the signed-in
  principal at overlapping times MUST each independently clear their own
  tab's cache: the tab that wrote the change via its own session-change
  path, and every other tab of that origin via the cross-tab storage-change
  notification.
- **Error states**: this component calls no network, file-system, or
  database dependency of its own — its only external calls are reading the
  token's subject claim, session-change subscription, registering the
  cross-tab storage-change listener, and cache-client construction, none of
  which this component's tests or the authentication client's own
  documented contract for reading the token's subject claim (guaranteed to
  return nothing rather than throw on a malformed token) show as failing.
  This component therefore defines no dependency-failure path of its own; a
  downstream query's network failure is documented by the recipe for that
  query (e.g. the resource-data recipe), not here.
- **Offline/disconnected state**: the cache-client factory sets one default
  retry policy (a single retry) applied to every query built on the
  singleton cache accessor, but this component implements no
  network-reachability detection, reconnect listener, or offline queue of
  its own, and leaves the underlying cache library's own default
  reconnect-triggered refetch behavior unmodified. A caller needing offline
  resilience beyond one retry MUST layer it on its own query function, not
  on this shared client.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| The resource-cache retention constant | exported constant | `1,800,000` ms (30 min) | Retention time every `resource-list`/`resource-item`-prefixed query entry uses, pinned by the cache-client factory |
| The default staleness window | hardcoded in the cache-client factory | `300,000` ms (5 min) | Client-wide default staleness for every query built on this client |
| The default retry count | hardcoded in the cache-client factory | `1` | Client-wide default retry count for every query built on this client |
| The mounted subtree | required prop of the cache provider component | none (required) | Subtree the provider mounts its underlying cache-provider wrapper around |

None of these values is exposed through a caller-facing setter (no
configuration function exists in this component, unlike the resource-data
recipe's own configuration entry point); changing any of them requires
editing the source module itself.

## Deep Linking

Not applicable: this component defines no app URL scheme, platform
deep-link registration, or inbound-URL parsing of any kind.

## Localization

Not applicable: this component renders no user-facing text. Its only
string literals are internal cache-key segments (`'resource-list'`,
`'resource-item'`) and the name of the cross-tab storage-change event it
listens for, none of which is user-facing.

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior.

## Feature Flags

Not applicable: no part of this component defines or reads a feature-flag
key; every conditional path (whether an interactive host environment is
present, whether the browser singleton is already set, whether the subject
changed) is derived from the runtime environment or stored session state,
never from a flag this module owns.

## Analytics

Not applicable: this component emits no client-side analytics or
product-telemetry event, and calls no reporting sink of its own.

## Privacy

- **Data collected**: This component collects no new personal data. It
  reads the already-stored access token's subject claim, via reading the
  token's subject claim (documented by the authentication client recipe),
  solely to compare it against the previously seen value; it never displays,
  re-derives, or persists that claim itself.
- **Storage**: The last-seen subject lives in an in-memory, module-scope
  variable — never written to a persistent or session-scoped client-side
  store, or a cookie, and gone the moment the page/module is reloaded. The
  `resource-list`/`resource-item` cache entries this client governs live
  only in the in-memory query cache.
- **Transmission**: This component makes no network call of its own.
- **Retention**: The last-seen subject persists only for the life of the
  browser tab holding the module; the entire query cache it guards is
  discarded outright the instant the signed-in principal changes — the
  mechanism that keeps a second principal on a shared machine from ever
  reading rows cached under the first.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **React/Web**: This is the reference implementation.
  `@tanstack/react-query` v5's `QueryClient`/`QueryClientProvider`/
  `useQueryClient` back the cache and its React binding; a module-scope
  `let` binding backs the one-per-tab singleton; `window.addEventListener
  ('storage', ...)` backs the cross-tab session watch;
  `@agentic-toolkit/auth/client`'s `onSessionChange`/`readTokenSubject`
  supply the same-tab session signal and the principal comparison value.
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
  guard this recipe's comparison callback implements here, so a token
  refresh for the same signed-in user does not needlessly discard the
  cache. There is no `window` `'storage'`-event equivalent for a
  single-process WinUI 3 app; if the app supports multiple top-level
  windows in one process, they already share the one DI-scoped singleton
  in-process, so no cross-window signal is needed at all — a genuinely
  separate-process scenario (e.g. a companion process) would instead need
  an explicit IPC channel, which has no counterpart in this source.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/services/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe. |
