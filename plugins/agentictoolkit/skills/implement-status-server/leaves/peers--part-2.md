<!-- leaf: implement-status-server/peers--part-2 · source: status-server-peers.md -->

# Status Server Peers — continued (part 2)

## Platform Notes

- **React/Web** (source platform): all three files live under `packages/web/packages/status-server/src/peers/`, depending only on the package's own `../storage/ports` types (`Storage`, `PeerStore`, `PeerRow`, `PeerSnapshotRow`) and `../config/port`'s `StatusConfig`, plus Node/Web-standard `fetch`, `AbortSignal.timeout`, and `URL`; no ORM or framework import crosses into these three files — the drizzle-backed implementation lives in `libsql/stores/peer-store.ts`, external to this recipe.
- **SwiftUI**: model `PeerRow`/`PeerSnapshotRow`/`FleetMember` as `Sendable` structs with the same optional fields; `normalizePeerBaseUrl`/`isValidPeerBaseUrl`/`isSamePeerBaseUrl`/`isSelfPeerUrl` become pure functions over Foundation's `URLComponents` (needed for the lower-casing and default-port folding that bare `URL` does not do); `fetchPeers` becomes an `async` function over `URLSession` using `URLRequest.timeoutInterval` in place of `AbortSignal.timeout`, dispatching every peer concurrently via `withThrowingTaskGroup` in place of `Promise.all`; `assembleFleet` stays a pure `async` function over an injected storage protocol.
- **Compose**: the same structural mapping as SwiftUI — Kotlin `data class`es for `PeerRow`/`PeerSnapshotRow`/`FleetMember`, `java.net.URI` for the base-URL folding, `coroutineScope { peers.map { async { ... } } }.awaitAll()` in place of `Promise.all`, and `withTimeout(10_000)` in place of `AbortSignal.timeout(10_000)`.
- **AppKit/UIKit**: the identical mapping to SwiftUI's; `URLSession`'s `data(for:)` with a per-request `URLSessionConfiguration.timeoutIntervalForRequest` is the direct analogue of `fetchPeers`'s per-peer 10-second bound.
- **WinUI 3**: a .NET port models `PeerRow`/`PeerSnapshotRow`/`FleetMember` as `record` types with nullable properties; `normalizePeerBaseUrl`/`isValidPeerBaseUrl`/`isSamePeerBaseUrl` become static methods over `System.Uri` (`Uri.TryCreate` plus explicit lower-casing of `Uri.Scheme`/`Uri.Host`, since `Uri` does not fold case the way `new URL()` does); `fetchPeers` becomes an `async Task` using `HttpClient` with a per-call `CancellationTokenSource.CancelAfter(TimeSpan.FromSeconds(10))` as the `AbortSignal.timeout` analogue, and `Task.WhenAll(peers.Select(FetchOneAsync))` in place of `Promise.all`; `System.Text.Json` replaces `res.json()` for the peer's `/snapshot` body; `assembleFleet`'s equivalent is a plain `async Task<IReadOnlyList<FleetMember>>` composing an injected storage abstraction — no `ObservableCollection`/`INotifyPropertyChanged` counterpart applies, since neither function exposes a live-bound collection, only a one-shot result; `Windows.Storage` has no role either, since persistence is the external `PeerStore`'s concern.

## Design Decisions

- **Decision**: `normalizePeerBaseUrl` folds case, the default port, and any query/fragment away, but preserves a non-default port and a path.
  **Rationale**: the `uniq_peer_base_url` index is byte-exact, so anything that varies without naming a different endpoint must fold out before insert or the same monitor could be added twice; a non-default port or a path does name a different endpoint, so those are kept (source comment, `base-url.ts`).
  **Approved**: pending

- **Decision**: an unparseable base-URL string is normalized by trim-and-strip-trailing-slash rather than rejected or thrown.
  **Rationale**: callers normalize before they know whether validation has passed — `isValidPeerBaseUrl` runs as a separate step — so `normalizePeerBaseUrl` is total by design and never blocks that later validation (source comment, `base-url.ts`).
  **Approved**: pending

- **Decision**: `isSelfPeerUrl` treats an empty `config.publicBaseUrl` as "this host's own URL is unknown," never flagging any value as self.
  **Rationale**: stated directly in the source comment; `publicBaseUrl`'s own primary purpose, per `StatusConfig`'s doc comment, is the browser-facing origin for OAuth callbacks, and it defaults to `""` when unset, so treating "unknown" as "cannot self-match" avoids a false-positive self-guard on a monitor that has never had `publicBaseUrl` configured.
  **Approved**: pending

- **Decision**: `fetchPeers` never retries a failed or timed-out peer request within one call, and treats a non-`ok` response, a thrown request, and a timeout identically — one `reachable: false` upsert.
  **Rationale**: this is a plain fact about the code's behavior, recorded here per source fidelity rather than an invented justification; the effect is that a peer failing one poll is retried only by the next scheduled full-sync cycle (`monitor/cycle-runner.ts`, external), never within `fetchPeers` itself.
  **Approved**: pending

- **Decision**: `assembleFleet` reports a never-polled peer's `fetchedAt` as `new Date(0).toISOString()` (the Unix epoch) rather than `null` or the current time.
  **Rationale**: a plain fact about the code, noted only briefly in-source; recorded here because a naive reader might expect `null` — a board rendering `fetchedAt` as "time since last seen" must recognize the epoch sentinel to distinguish "never polled" from a normal, if old, timestamp.
  **Approved**: pending

- **Decision**: this recipe's `related` field links to `status-server-config`, `status-server-mcp`, and `status-server-monitor-cycle-runner` one-directionally; the reverse links on those three recipes were not added.
  **Rationale**: authored under an explicit constraint to write only this one file and touch no other; cross-recipe-consistency's own text allows a unidirectional reference ("acceptable but bidirectional is preferred"), so this is a known, intentional gap in the preferred state rather than an oversight, mirroring the same documented choice already made in `status-server-config.md`.
  **Approved**: pending

- **Decision**: the separate `status-web` package deliberately duplicates `normalizePeerBaseUrl`/`isValidPeerBaseUrl` in its own `src/lib/peer-url.ts` (external to these three files) for client-side dirty-checking.
  **Rationale**: that file's own header comment states the mirror is deliberate — the board is a separate Next app that cannot import the backend's module, and "the backend stays the authority" — recorded here as a known, intentional duplication that must be kept in step by hand, not an accidental drift within this recipe's scope to fix.
  **Approved**: pending
