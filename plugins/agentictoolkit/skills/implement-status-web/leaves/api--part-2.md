<!-- leaf: implement-status-web/api--part-2 · source: status-web-api.md -->

# Status Web API — continued (part 2)

## Privacy

- **Data collected**: `peers.ts`'s `PeerWrite.token` (a fleet shared secret) is
  the one sensitive value the given sources handle; `monitored-sites.ts` and
  `client.ts` carry only operational/infrastructure configuration (site,
  group, and endpoint records), never end-user personal data.
- **Storage**: none of the three files persists any value locally; every
  read returns a fresh `fetch` response, and nothing is cached or written to
  disk or `localStorage` by this module.
- **Transmission**: `peers.ts` sends `token` as a JSON request-body field
  (via `createPeer`/`updatePeer`), never in a URL or query string. The
  transport scheme is whatever `basePath` resolves through — ordinarily a
  same-origin path, so TLS is inherited from the hosting page rather than
  enforced by these files themselves.
- **Retention**: none — a call's `token` value is not retained by these
  files beyond the single outbound request; `PeerView.hasToken` is the only
  signal a subsequent read returns, per peer-view-redaction.

## Platform Notes

- **SwiftUI**: model `StatusApiClient` as a small `Sendable` struct or an
  `actor` wrapping `URLSession` (`url`/`data(for:)` in place of
  `fetch`/`json`), decoding with `JSONDecoder` in place of `res.json()`, and
  throwing a typed `Error` in place of the crafted `Error` message; expose it
  through a `@Observable` environment object or an `EnvironmentKey` as the
  analogue of `StatusApiProvider`/`useStatusApi`. `eventSource`'s SSE stream
  has no Foundation counterpart — a port needs `URLSession`'s
  `bytes(for:)` async sequence with a manual `text/event-stream` line parser,
  or a small third-party SSE client.
- **Compose**: build the same shape over Ktor's `HttpClient` (or OkHttp) with
  `kotlinx.serialization` in place of `res.json()`; expose the client through
  a `CompositionLocal` as the analogue of the React context/`Provider`. As on
  Apple, there is no native `EventSource`; a port needs OkHttp's SSE support
  or a manual chunked-response reader over the same `HttpClient`.
- **React/Web**: the source. `client.ts` uses the browser's native `fetch`
  and `EventSource` and a React `Context`/`useMemo`/`useContext` trio for
  provider/hook wiring; `monitored-sites.ts` and `peers.ts` are plain
  `async`/`Promise`-returning functions with no framework dependency beyond
  the `StatusApiClient` type they're given. Tests are colocated
  (`monitored-sites.test.ts`) and run under Vitest.
- **AppKit / UIKit**: the same `URLSession`-based client as the SwiftUI
  bullet applies unchanged — this layer has no view-framework dependency —
  but with no environment-value system, the client is typically handed to
  view controllers through a plain injected singleton or dependency-injection
  container rather than an environment key.
- **WinUI 3**: model `StatusApiClient` as a class exposing
  `Task<T> JsonAsync<T>(string path, ...)` and `Task<HttpResponseMessage>
  FetchAsync(...)` built on a shared `HttpClient` instance, with
  `System.Text.Json` in place of `res.json()` and a thrown, typed exception
  in place of the crafted `Error` message; `Task`/`async`/`await` replace
  `Promise`/`async`/`await` directly. `GroupRow`/`SiteRow`/`EndpointRow` and
  their `View` counterparts become `record` types; the `toGroup`/`toSite`/
  `toEndpoint` mappers become static methods or constructors on those
  records. A bound UI would surface results through `ObservableCollection`/
  `INotifyPropertyChanged`, which none of these three files has a
  counterpart for since they return plain arrays, not a live-bound
  collection. `Windows.Storage` has no role here either, since none of these
  files persists anything. .NET has no built-in SSE client analogous to
  `EventSource`; a port needs `HttpClient`'s streaming response with a
  manual `text/event-stream` parser, or a NuGet SSE package.

## Design Decisions

**Decision**: `useStatusApi()` falls back to a single module-level
`defaultClient` singleton, built once at import time with no `basePath` or
`fetch` override, shared by every caller that has no ancestor
`StatusApiProvider`.
**Rationale**: matches the source directly — `const defaultClient =
createStatusApiClient();` is declared at module scope, and the doc comment on
`useStatusApi` states it returns "the same-origin default when no provider is
mounted."
**Approved**: pending.

**Decision**: mounting a bare `<StatusApiProvider>` with no `client` or
`basePath` prop builds a brand-new `StatusApiClient` (via `useMemo`) rather
than reusing the module's `defaultClient`; it behaves identically (same
default `basePath`, same global `fetch`) but is a distinct object reference.
**Rationale**: `useMemo(() => client ?? createStatusApiClient({basePath}),
[client, basePath])` always calls `createStatusApiClient` when `client` is
falsy — it never falls back to the outer `defaultClient` constant, even
though the two clients are behaviorally interchangeable.
**Approved**: pending.

**Decision**: `EndpointWriteFields` is derived from `EndpointView`
(`Partial<Omit<EndpointView, "id" | "siteId">>`) instead of being hand-listed.
**Rationale**: the inline comment states this directly: "Exactly EndpointView's
writable fields (derived — adding a column to EndpointView can't silently
drop it from create/update)." A new `EndpointView` field automatically
becomes writable through `createEndpoint`/`updateEndpoint` with no second
edit required.
**Approved**: pending.

**Decision**: `ignoreProjects` fans its per-project calls out with
`Promise.all` rather than a sequential loop or a concurrency-limited batch.
**Rationale**: the doc comment states the unique `(platform, projectName)`
index makes a re-ignore idempotent, and that issuing the batch in parallel
makes ignoring a large batch cost one round-trip's latency rather than N; the
documented tradeoff is that one project's failure rejects the whole batch
immediately (`Promise.all` semantics) instead of reporting a per-project
partial result.
**Approved**: pending.

**Decision**: `peers.ts`'s `createPeer`/`updatePeer` serialize the caller's
object directly, while `monitored-sites.ts`'s group/site/endpoint functions
rebuild an explicit `fields` object before serializing.
**Rationale**: this is a genuine divergence between the two sibling files,
not a typo — `monitored-sites.ts`'s comments explain its allow-list exists
because the hub's own generated API-type package does not match the status
backend's schema for these routes, a concern `peers.ts`'s simpler
`PeerWrite` shape does not have.
**Approved**: pending.
