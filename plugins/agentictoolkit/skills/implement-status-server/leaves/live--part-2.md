<!-- leaf: implement-status-server/live--part-2 · source: status-server-live.md -->

# Status Server Live — continued (part 2)

**Rules** (cite as `implement-status-server/live--part-2#<slug>`):

- `winui-3` MUST — this is the reason this recipe exists. A .NET reimplementation of this SERVER-side broadcaster (an ASP.NET Core Minimal …

## Platform Notes

- **React/Web** (source platform): `live-events.ts` lives under
  `packages/web/packages/status-server/src/live/`; it uses only a plain
  JavaScript `Set`, `Date.now()`, and Node's global `setTimeout`/`clearTimeout`
  — no external pub/sub library. Its two type-only imports
  (`StatusConfig`, `Storage`, `LiveSnapshot`) and its one value import
  (`buildLiveSnapshot`) all resolve within the same `status-server` package;
  the Hono SSE route that turns a delivered snapshot into
  `event: snapshot` bytes (`routes/stream.ts`) is a separate file, external
  to this recipe's source.
- **SwiftUI / AppKit / UIKit**: a Swift port of this exact broadcaster (not
  merely a client of the existing Node backend) models the subscriber set as
  an `actor`-isolated `[UUID: (LiveSnapshot) -> Void]` (a dictionary keyed by
  a generated id stands in for JS's reference-identity `Set`, since Swift
  closures are not `Equatable`/`Hashable`), publish as an `async` method on
  that actor so mutation is serialized the way the single-threaded event loop
  serializes it here, and the debounce timer as a stored `Task` that sleeps
  `150_000_000` nanoseconds via `Task.sleep(nanoseconds:)`, cancelled in the
  reset path with `Task.cancel()` — which, unlike this source's
  `clearTimeout`, also cancels a build already in flight if `buildLiveSnapshot`
  checks `Task.isCancelled` cooperatively, directly resolving the open
  question on in-flight-build-cancellation that Node's `setTimeout` cannot.
- **Compose**: the Kotlin equivalent is a `MutableSharedFlow<LiveSnapshot>`
  (replay = 1, so a late collector immediately sees the last value, mirroring
  `recentSnapshot`) with `subscribeLive`/`publishSnapshot` becoming
  `flow.collect { }` and `flow.emit(...)`; the debounce maps to Kotlin
  coroutines' `.debounce(150)` operator on an upstream trigger flow, and
  `resetLiveEvents` to resetting the `SharedFlow`'s backing state and
  cancelling the collecting `CoroutineScope`.
- **WinUI 3**: this is the reason this recipe exists. A .NET reimplementation
  of this SERVER-side broadcaster (an ASP.NET Core Minimal API backend, not a
  WinUI client) models subscribers as a
  `ConcurrentDictionary<Guid, Action<LiveSnapshot>>` — a real
  `lock`/concurrent collection is required here, unlike this source, because
  ASP.NET Core request handling is thread-pool-based, not single-threaded
  like Node's event loop, so `single-threaded-mutation` does NOT hold for a
  WinUI 3/.NET port and MUST be replaced with explicit synchronization. The
  coalesce timer maps to a single `System.Threading.Timer` (or
  `Task.Delay(150)` awaited from a guarded `Interlocked.CompareExchange` on a
  "build pending" flag, replacing the plain `if (pending) return;` check),
  the cache to a `volatile` `(LiveSnapshot Snapshot, DateTimeOffset At)?`
  field read under the same lock, and the SSE-equivalent transport to
  ASP.NET Core's `IAsyncEnumerable<T>`-based Server-Sent Events support (or a
  SignalR hub, if bidirectional push is ever needed) rather than Hono's
  `ReadableStream`. `CancellationToken`, threaded from the timer's callback
  into the build call, is the natural place to resolve
  in-flight-build-cancellation on this platform — a capability Node's
  `setTimeout`/`Promise` pairing in the actual source does not have.

## Design Decisions

- **Decision**: anchor the 150ms coalesce window to the *first*
  `emitLiveUpdate` call in a burst, and let every later call in that burst
  return immediately without resetting or extending the timer, rather than
  implementing a conventional trailing-edge debounce that restarts on every
  call.
  **Rationale**: the source comment describes this as "bursts coalesce into
  a single trailing build," meaning the one build that eventually runs
  trails the burst of calls, not that its delay is reset by each new call;
  anchoring to the first call bounds the worst-case added push latency for
  any caller in a burst to exactly 150ms, at the cost that the build reflects
  the `storage`/`config` values captured from the first call, not a later
  one, which is unobserved in this codebase because every call site passes
  the same singleton `storage`/`config`.
  **Approved**: pending
- **Decision**: let `recentSnapshot`'s staleness window (`maxAgeMs`) be
  supplied by the caller on every call rather than fixed as a module
  constant.
  **Rationale**: not stated verbatim in the source comment, but evidenced
  directly by the one real call site in this package — `routes/stream.ts`'s
  `OPENING_CACHE_MS` (1500ms) — which needs a different tolerance than a
  hypothetical stricter consumer; a per-call parameter lets each caller
  choose its own window with no change to this module.
  **Approved**: pending
- **Decision**: never surface a failed build to the code that called
  `emitLiveUpdate`, whether by throwing, rejecting a returned promise (there
  is none — `emitLiveUpdate` returns `void`), or any other signal.
  **Rationale**: the source comment states this directly: a failed build is
  "logged and dropped ... never thrown into the cycle/webhook that called
  us," because `emitLiveUpdate`'s two real callers (a webhook handler in
  `routes/hooks.ts`) already have their own successful side effect to
  respond with (a `200` to the webhook provider), and failing that response
  over a live-push failure would be strictly worse than a delayed push, since
  the next successful build (the next cycle, webhook, or the client's own
  polling fallback) recovers the data anyway.
  **Approved**: pending
- **Decision**: this recipe is intentionally shallower than its sibling
  `Status Server Auth` (7 exported behaviors and roughly 20 requirements here
  versus five files and roughly 40 requirements there).
  **Rationale**: the disparity tracks the components' actual surface area,
  not a difference in authoring effort — `live-events.ts` is one 66-line
  module with six exported functions and no HTTP route or security surface
  of its own, while the auth family spans cookies, an OAuth flow, and
  password hashing across five files; per the Cross-Recipe Consistency
  guideline, a depth disparity this size is warranted by genuinely different
  functional complexity, not a completeness gap in either recipe.
  **Approved**: pending
- **Decision**: record, rather than resolve, a naming mismatch between this
  module's own doc comment and the shared `LiveSnapshot` type it hands
  around.
  **Rationale**: the doc comment describes a client-side reducer advancing
  "count-based provider streaks only when `cycleAt` strictly increases," but
  the field `LiveSnapshot` actually exposes (`monitor/live-types.ts`) is
  named `lastCycleAt`. `live-events.ts` itself never reads or writes that
  field — it hands the whole snapshot through opaquely — so this is a
  terminology drift in a comment describing external client behavior, not a
  defect in this file's own behavior; recorded here per this cookbook's
  Source Fidelity guideline on documenting quirks rather than smoothing them
  over.
  **Approved**: pending
