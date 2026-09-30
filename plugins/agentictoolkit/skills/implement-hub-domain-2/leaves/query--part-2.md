<!-- leaf: implement-hub-domain-2/query--part-2 · source: hub-domain-query.md -->

# Hub Domain Query — continued (part 2)

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
