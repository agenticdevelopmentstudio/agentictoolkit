---
id: 635cbbe4-a8e1-4ae1-a8a5-437f5bba27a6
title: Status Server Live
domain: agentictoolkit://cookbook/status-server/live/live-events
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "In-process pub/sub for the status backend's /live SSE push: fan-out, a recency cache, and a debounced, fail-soft snapshot rebuild trigger."
platforms:
- typescript
- web
tags:
- server
- live
- sse
- pub-sub
depends-on:
- agenticdevelopercookbook://principles/separation-of-concerns
- agenticdevelopercookbook://principles/fail-fast
- agenticdevelopercookbook://guidelines/implementing/networking/caching
related: []
references:
- packages/web/packages/status-server/src/live/live-events.ts (agentictoolkit)
- packages/web/packages/status-server/test/live-events.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/live-types.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/stream.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/hooks.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Live

## Overview

`live-events.ts` is the status backend's in-process pub/sub hub for `/live`
push updates. It is one module, six exported functions, no HTTP route of its
own: `subscribeLive`/`publishSnapshot` are the fan-out (one `LiveSnapshot`
object handed to every open SSE stream), `recentSnapshot` is a short-lived
cache of the last published snapshot, `liveSubscriberCount` reports the
current subscriber count for the health/observability surface,
`emitLiveUpdate` is the debounced trigger a producer (a webhook handler in
`routes/hooks.ts`, or, per the module's own doc comment, a finished poll
cycle) calls to schedule a fresh build-and-publish, and `resetLiveEvents` is a
test-only reset of all module state. The actual SSE transport
(`routes/stream.ts`, subscribing on connect and writing `event: snapshot`
frames) and the actual snapshot construction (`buildLiveSnapshot` in
`routes/reads.ts`, which reads `Storage`) are both external to this file;
this recipe specifies only what `live-events.ts` itself does with the
snapshot once one exists.

## Behavioral Requirements

### Pub/Sub Core

- **subscription-registration**: `subscribeLive` MUST add the given callback
  to the module-scope subscriber set and MUST return a function that, when
  called, removes exactly that callback from the set.
- **unsubscribe-idempotent**: Calling the function `subscribeLive` returns
  more than once MUST have no further effect after the first call, because
  removing an already-absent entry from a `Set` is a no-op.
- **duplicate-callback-reference**: Subscribing the identical callback
  function reference a second time MUST NOT increase `liveSubscriberCount`,
  because a `Set` stores each distinct reference once; either caller's
  returned unsubscribe function then removes the one shared entry.
- **publish-fanout-same-reference**: `publishSnapshot` MUST invoke every
  currently registered subscriber callback with the exact same `LiveSnapshot`
  object reference it was given, never a copy, so that N registered
  subscribers cost one built object, not N.
- **publish-subscriber-isolation**: `publishSnapshot` MUST catch any error a
  subscriber callback throws, log it via `console.error`, and continue
  delivering to the remaining subscribers; a throwing subscriber MUST NOT
  stop delivery to any other subscriber and MUST NOT cause `publishSnapshot`
  itself to throw.
- **publish-updates-cache-unconditionally**: `publishSnapshot` MUST record
  the given snapshot and the current wall-clock time as the most recently
  published snapshot regardless of whether any subscriber is currently
  registered.
- **subscriber-count**: `liveSubscriberCount` MUST return the exact current
  size of the subscriber set.

### Recency Cache

- **recent-snapshot-null-before-publish**: `recentSnapshot` MUST return
  `null` when no snapshot has ever been published, or after `resetLiveEvents`
  has run.
- **recent-snapshot-freshness-window**: `recentSnapshot(maxAgeMs)` MUST
  return the most recently published snapshot when the elapsed time since it
  was published is less than or equal to `maxAgeMs`, and MUST return `null`
  otherwise.

### Debounced Emit

- **emit-skips-when-idle**: `emitLiveUpdate` MUST return immediately, without
  scheduling a build and without calling any `Storage` method, when zero
  subscribers are registered.
- **emit-coalesces-concurrent-calls**: `emitLiveUpdate` MUST schedule at most
  one pending build at a time; a call made while a build is already scheduled
  MUST return immediately without rescheduling or extending the existing
  delay.
- **emit-fixed-coalesce-window**: The scheduled build MUST run exactly 150
  milliseconds (`COALESCE_MS`) after the first `emitLiveUpdate` call of a
  burst, never after the last call of the burst, because later calls in the
  burst are absorbed by `emit-coalesces-concurrent-calls` without touching
  the timer.
- **emit-build-and-publish**: The scheduled build MUST call
  `buildLiveSnapshot` with the `storage` and `config` values captured from
  the call that armed the timer, and MUST pass its resolved result to
  `publishSnapshot` on success.
- **emit-build-failure-logged-not-thrown**: When the build's promise rejects,
  the scheduled build MUST log the error via `console.error` and MUST NOT
  throw into, or otherwise notify, the code that originally called
  `emitLiveUpdate`.
- **emit-no-retry**: `emitLiveUpdate` MUST NOT itself retry a failed build;
  the next call to `emitLiveUpdate`, from the next cycle, webhook, or the
  client's own polling fallback, is the only path to a fresh attempt.

### Test Utility

- **reset-clears-subscribers-and-cache**: `resetLiveEvents` MUST clear the
  subscriber set and the cached last-published snapshot.
- **reset-cancels-armed-timer**: `resetLiveEvents` MUST cancel a debounce
  timer that `emitLiveUpdate` has armed but that has not yet fired, so its
  scheduled build never runs.
- **in-flight-build-cancellation**: NEEDS REVIEW: Not implemented in source. Once the debounce timer fires, `pending` is cleared and the build's promise is already in flight; `resetLiveEvents` has nothing left to cancel it with, so a build that started just before a reset can still resolve afterward and call `publishSnapshot`, repopulating the cache and delivering to whatever subscribers are registered at that later moment, which contradicts `resetLiveEvents`'s own doc comment "cancel any pending build"; settling this needs an abort signal threaded into `buildLiveSnapshot` or a generation counter checked before that late `publishSnapshot` call runs.

### Module Scope & Concurrency

- **single-threaded-mutation**: Every read and write of the module-scope
  subscriber set, cached snapshot, and pending-timer handle executes
  synchronously within Node's single-threaded event loop, so two
  `subscribeLive`/`publishSnapshot`/`emitLiveUpdate` calls MUST NOT interleave
  mid-mutation; this is a property of the JavaScript execution model, not a
  lock this file implements, and it does not extend across the `await`
  boundary inside the scheduled build (see the open question on
  in-flight-build-cancellation above).
- **process-wide-singleton**: All pub/sub state MUST be shared by every
  caller within one running process (module scope, not per-request or
  per-`Storage`-instance). Per the module's own doc comment this is exact on
  the single long-running container this package targets, and best-effort
  per instance on a hypothetical multi-instance deployment, where a client
  connected to one instance never observes a push raised on another; the
  client's polling fallback re-reads the database regardless, so a missed
  push only adds latency, never loses data.
- **delivery-order-undefined-across-snapshots**: This module MUST NOT
  guarantee delivery order, deduplication, or monotonicity across multiple
  published snapshots; it delivers exactly what `publishSnapshot` is called
  with, in call order, and nothing more. Reconciling out-of-order, duplicate,
  or stale deliveries is the receiving client's responsibility, external to
  this file — the module's own doc comment sketches a `cycleAt`-based
  reconciliation on the client side, though the shared `LiveSnapshot` type
  (`monitor/live-types.ts`) names that field `lastCycleAt`, not `cycleAt`
  (see Design Decisions).

## Appearance

Not applicable — this is an in-process pub/sub module, not a visual component.

## States

Not applicable — this is an in-process pub/sub module; its runtime behavior (idle, coalescing, publishing) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is an in-process pub/sub module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-live-001 | subscription-registration, subscriber-count | `subscribeLive(cbA)`, then `subscribeLive(cbB)` | `liveSubscriberCount()` returns `2` — `live-events.test.ts` "fans one published snapshot out to every subscriber" |
| status-server-live-002 | subscription-registration, unsubscribe-idempotent | Call the function `subscribeLive(cb)` returned, then `publishSnapshot(s)` | `cb` is never invoked; `liveSubscriberCount()` returns `0` — `live-events.test.ts` "stops delivering after unsubscribe" |
| status-server-live-003 | publish-fanout-same-reference | `subscribeLive` twice (pushing to arrays `a` and `b`); `publishSnapshot(s)` | `a` and `b` both equal `[s]`; `a[0]` and `b[0]` are the same object reference as `s` — `live-events.test.ts` same test, `toBe` assertions |
| status-server-live-004 | publish-subscriber-isolation | One subscriber's callback throws synchronously; a second subscriber pushes to an array; `publishSnapshot(s)` | The second subscriber still receives `s`; no exception escapes `publishSnapshot` — `live-events.test.ts` "a throwing subscriber never blocks the fan-out to the others" |
| status-server-live-005 | publish-updates-cache-unconditionally | `publishSnapshot(s)` with zero subscribers currently registered | A subsequent `recentSnapshot` call with a large enough window returns `s`; traced to source: the cache write precedes and does not depend on the subscriber loop |
| status-server-live-006 | recent-snapshot-null-before-publish | Fake timers; `recentSnapshot(1000)` called before any publish | Returns `null` — `live-events.test.ts` "recentSnapshot serves the last published snapshot within the age window, else null", first assertion |
| status-server-live-007 | recent-snapshot-freshness-window | Publish `s`, then immediately call `recentSnapshot(1000)` | Returns `s`, the same object reference — same test, second assertion |
| status-server-live-008 | recent-snapshot-freshness-window | Publish `s`, advance fake time by 1500ms, then call `recentSnapshot(1000)` | Returns `null` (aged out) — same test, third assertion |
| status-server-live-009 | reset-clears-subscribers-and-cache | Two `subscribeLive` calls, then `resetLiveEvents()` | `liveSubscriberCount()` returns `0` immediately afterward; traced to source's `subscribers.clear()` |
| status-server-live-010 | emit-skips-when-idle | Zero subscribers registered; call `emitLiveUpdate(storage, config)` where `storage`'s methods throw if invoked | None of `storage`'s methods are called and no timer is scheduled; traced to source's `if (subscribers.size === 0) return;` guard, which runs before the coalesce check or the `setTimeout` call — not exercised by any test in `test/` |
| status-server-live-011 | emit-coalesces-concurrent-calls, emit-fixed-coalesce-window | One subscriber registered; call `emitLiveUpdate(storage, config)` three times synchronously in the same tick, then advance time by 150ms | The build runs exactly once, not three times, and the subscriber receives exactly one snapshot; traced to source's `if (pending) return;` guard — not exercised by any test in `test/` |
| status-server-live-012 | emit-build-failure-logged-not-thrown, emit-no-retry | One subscriber registered; the build's promise rejects; call `emitLiveUpdate(storage, config)`; advance time by 150ms | The rejection is caught and logged via `console.error`; the subscriber's callback is never invoked; the call to `emitLiveUpdate` itself does not throw — traced to source's `.catch` clause — not exercised by any test in `test/` |
| status-server-live-013 | reset-cancels-armed-timer | Call `emitLiveUpdate` to arm the debounce timer, then call `resetLiveEvents()` before 150ms elapses, then advance time past 150ms | The build is never invoked; traced to source's `clearTimeout(pending)` inside `resetLiveEvents` — not exercised by any test in `test/` |

## Edge Cases

- **Null and empty input**: `publishSnapshot` and `emitLiveUpdate` never
  inspect the contents of a `LiveSnapshot` — a degenerate snapshot (for
  example one with `configDegraded: true` and every array empty) flows
  through identically to a healthy one, because this module treats it as an
  opaque value. `recentSnapshot` before any publish and `liveSubscriberCount`
  before any subscription both return their empty-state values (`null` and
  `0`) rather than throwing (MUST, per recent-snapshot-null-before-publish).
- **Boundary values**: `maxAgeMs` of `0` passed to `recentSnapshot` MUST
  still return the cached snapshot when the elapsed time is exactly `0`
  (the comparison is `<=`, not `<`). A fourth `emitLiveUpdate` call arriving
  at the exact instant the 150ms timer's callback begins running observes
  `pending` already set to `null` (it is cleared as the very first statement
  in that callback), so it MUST be treated as the start of a brand-new burst
  with its own fresh 150ms window, not folded into the build that is already
  running.
- **Concurrent access**: within one JavaScript task, mutation of the
  subscriber set, cache, and timer handle is single-threaded and MUST NOT
  interleave (single-threaded-mutation). Across an `await` boundary this
  guarantee does not hold — see the open question on
  in-flight-build-cancellation, which is exactly a race between a build
  already in flight and a later `resetLiveEvents` or fresh burst.
- **Error states**: a rejected `buildLiveSnapshot` promise is caught, logged,
  and dropped (emit-build-failure-logged-not-thrown); it MUST NOT reach any
  subscriber as a partial or error snapshot, and no snapshot is delivered
  for that failed attempt. A throwing subscriber is isolated
  (publish-subscriber-isolation) and MUST NOT be removed from the subscriber
  set as a consequence of throwing — it stays registered and is retried on
  the next `publishSnapshot`.
- **Offline / disconnected state**: this module has no client-side
  connectivity of its own to lose. Its analogue of "disconnected" is a
  subscriber's returned unsubscribe function being called — by
  `routes/stream.ts`, external to this file, when the browser's `EventSource`
  disconnects — after which `publishSnapshot` simply no longer includes that
  callback (unsubscribe-idempotent). This module has no notion of
  reconnection; a reconnecting client calls `subscribeLive` again as a fresh
  registration, and `routes/stream.ts` decides whether to serve it a cached
  `recentSnapshot` or trigger a fresh build, both external to this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cb` | `(snap: LiveSnapshot) => void` (`subscribeLive` parameter) | none, required | The subscriber callback registered for future publishes. |
| `snap` | `LiveSnapshot` (`publishSnapshot` parameter) | none, required | The snapshot handed to every subscriber unchanged. |
| `maxAgeMs` | `number` (`recentSnapshot` parameter) | none, required | Caller-chosen staleness window; `routes/stream.ts`'s `OPENING_CACHE_MS` (1500) is the one caller in this package, external to this file. |
| `storage` | `Storage` (`emitLiveUpdate` parameter, injected port) | none, required | Passed straight through to `buildLiveSnapshot` for the reads a fresh snapshot needs. |
| `config` | `StatusConfig` (`emitLiveUpdate` parameter, injected) | none, required | Passed straight through to `buildLiveSnapshot`. |
| `COALESCE_MS` | module constant | `150` | Fixed debounce/coalesce window in milliseconds; not configurable per call, by environment, or by `StatusConfig`. |

## Deep Linking

Not applicable: this module defines no application URL scheme or route of its own — it has no HTTP endpoint; the SSE route that consumes it (`routes/stream.ts`) is external to this file.

## Localization

Not applicable: `live-events.ts` produces no user-facing strings. Its two `console.error` calls are developer-facing log messages, covered under Logging below, not localized user copy.

## Accessibility Options

Not applicable: this module has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this module consults no feature-flag system; every behavior described above is unconditional code, not a flag-gated branch.

## Analytics

Not applicable: this module emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: `live-events.ts` handles no credentials, tokens, or personal data. It broadcasts already-built `LiveSnapshot` DTOs (service/deployment status) between server-side subscribers, treating the snapshot as an opaque value it never inspects; any personal-data handling happens in `Storage`/`buildLiveSnapshot`, external to this file.

## Logging

Subsystem: `status-server` | Category: `live-events`

| Event | Level | Message |
|-------|-------|---------|
| A subscriber callback throws during `publishSnapshot` | error | `[live-events] subscriber threw:` followed by the caught error |
| `buildLiveSnapshot` rejects inside a scheduled `emitLiveUpdate` build | error | `[live-events] emit build failed:` followed by the caught error |

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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/live/live-events.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | Performance |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | Performance |

`separation-of-concerns` passes: this module does exactly one thing —
in-process fan-out, a recency cache, and a debounce trigger — and delegates
snapshot construction to `buildLiveSnapshot` (external), persistence to
`Storage` (external), and HTTP/SSE transport to `routes/stream.ts` (external);
it holds no query, no route, and no rendering code. `unit-test-coverage` is
`partial`: `live-events.test.ts` directly and thoroughly exercises the
pub/sub core and the recency cache (fan-out, unsubscribe, subscriber
isolation, freshness window — vectors 001-009), but `emitLiveUpdate`'s own
behavior — the empty-subscriber skip, the coalescing window, and the
fail-soft catch (vectors 010-012) — has no direct unit test anywhere in
`test/`; the only test file that touches `emitLiveUpdate` at all
(`hooks-gate.test.ts`) replaces it entirely with `vi.fn()`, so that behavior
is presently verified only by reading the source. `explicit-error-handling`
is `partial`: both failure paths in this file are logged, never silently
dropped with no signal (`console.error` in both `publishSnapshot` and the
scheduled build), but `emitLiveUpdate`'s failure is a deliberate dead end by
design (see Design Decisions) — no caller, test, or monitoring hook in this
file learns that a specific push attempt failed, only that *something* was
logged. `fault-tolerance` passes: a throwing subscriber cannot take down
delivery to the others (publish-subscriber-isolation), and unexpected
snapshot shapes pass through untouched because this module never inspects
snapshot contents. `graceful-degradation` passes: a failed build is caught,
logged, and dropped rather than crashing the process or the caller, and the
next successful build recovers the data. `health-observability` passes:
`liveSubscriberCount` is exported, per the source's own comment, "for the
health/observability surface." `caching-strategy` passes: `recentSnapshot`
serves a freshly connecting client from the last published snapshot instead
of forcing a rebuild, with an explicit, caller-supplied `maxAgeMs`
invalidation window, avoiding a reconnect-storm stampede on the database per
the source comment. `resource-efficiency` passes: the zero-subscriber
short-circuit in `emitLiveUpdate` skips the database read entirely when
nobody is listening, and one build serves every currently open stream
instead of one build per stream.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
