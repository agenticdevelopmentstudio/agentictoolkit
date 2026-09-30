<!-- leaf: implement-hub-domain-2/query · source: hub-domain-query.md -->

**Rules** (cite as `implement-hub-domain-2/query#<slug>`):

- `resource-gc-time-constant` MUST
- `query-defaults-stale-and-retry` MUST
- `resource-key-gc-time-pinned` MUST
- `server-client-per-call` MUST
- `browser-client-singleton` MUST
- `browser-client-lazy-construction` MUST
- `provider-uses-singleton` MUST
- `provider-nesting-is-idempotent` MUST
- `provider-siblings-share-client` MUST
- `hook-ignores-ancestor-context` MUST
- `hook-usable-without-provider` MUST
- `session-watch-registered-once` MUST
- `session-watch-initial-subject` MUST
- `session-change-clears-on-subject-change` MUST
- `session-refresh-does-not-clear` MUST
- `cross-tab-session-watch` MUST
- `winui-3` MUST — A cache service — Microsoft.Extensions.Caching.Memory's IMemoryCache, or a hand-rolled ConcurrentDictionary-backed …

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

