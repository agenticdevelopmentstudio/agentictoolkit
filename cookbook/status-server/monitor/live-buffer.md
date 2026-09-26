---
id: fdfdaf38-95de-4475-98f4-e09fb998bb57
title: Status Server Monitor Live Buffer
domain: agentictoolkit://cookbook/status-server/monitor/live-buffer
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: In-memory ring buffer of webhook-received deploy events, capped at 200, merged into live reads so a webhook shows up before the next provider poll.
platforms:
- typescript
- web
tags:
- monitor
- buffer
- webhook
- deploy
- server
depends-on: []
related:
- agentictoolkit://cookbook/status-server/monitor/provider-deploy
references:
- packages/web/packages/status-server/src/monitor/live-buffer.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/hooks.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/test/hooks.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/hooks-alerting.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/live-deploy-targets.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Live Buffer

## Overview

`live-buffer.ts` (`packages/web/packages/status-server/src/monitor/live-buffer.ts`) is a small, module-scope in-memory ring buffer that holds the deploy events the status server's webhook handlers (`hooks.ts`) receive between provider polls. Its own top-of-file comment states the reason it exists: webhook receipt is faster than the periodic provider poll, and merging buffered events into `/api/live`-style reads (`reads.ts`'s `deploymentDtos`) lets a webhook-reported deploy show up immediately instead of waiting for the next poll cycle. The same comment states the module's own durability tradeoff directly: on a long-running server (local dev, Railway) the buffer is exact, but on Vercel serverless it is BEST-EFFORT, because each warm instance holds its own private buffer and a webhook event may land on an instance that a given `/api/live` read never reaches. That tradeoff is accepted by design — the file's comment says the 60-second poll independently re-reads provider truth, so the buffer only ever shortens latency and never carries information the poll cannot recover on its own. The module exports three functions: `pushDeployEvent` (called from `hooks.ts` after a webhook event is mapped and persisted), `deployEventsSince` (called from `reads.ts` to overlay buffered events onto persisted rows), and `clearDeployEvents` (a test-only hook, per its own doc comment, to reset the shared module state between test cases).

## Behavioral Requirements

### Constant and Type Shape

- **buffer-capacity-constant**: The module MUST bound the buffer to 200 entries via its internal `CAP` constant (`const CAP = 200`).
- **buffered-deploy-shape**: The exported `BufferedDeploy` interface MUST declare exactly two members: `deploy: ProviderDeploy` (the event as the provider/webhook reported it) and `receivedAt: number` (milliseconds, the server clock's reading at the moment the webhook arrived).
- **module-scope-singleton**: The module MUST hold exactly one buffer array (`const buffer: BufferedDeploy[]`) at module scope, shared by every caller within the same process; it MUST NOT expose a factory, constructor, or any other way to create an independent buffer instance.

### Writing (`pushDeployEvent`)

- **push-appends-with-receipt-time**: `pushDeployEvent(deploy)` MUST append a new `BufferedDeploy` to the end of the buffer, pairing the given `deploy` with a `receivedAt` value read from `Date.now()` at the moment of the call — never from any timestamp carried on `deploy` itself.
- **push-evicts-oldest-beyond-capacity**: after appending, `pushDeployEvent` MUST remove entries from the front of the buffer (the oldest first) whenever the buffer's length exceeds `CAP`, via `buffer.splice(0, buffer.length - CAP)`, so the buffer never holds more than 200 entries.
- **push-returns-void**: `pushDeployEvent` MUST return `void`; it MUST NOT return an identifier, an acknowledgment, or any success/failure signal to its caller.

### Reading (`deployEventsSince`)

- **filter-inclusive-lower-bound**: `deployEventsSince(sinceMs)` MUST return every buffered `BufferedDeploy` whose `receivedAt` is greater than or equal to `sinceMs`, and MUST exclude every entry whose `receivedAt` is strictly less than `sinceMs`; the comparison is inclusive at the boundary (`b.receivedAt >= sinceMs`).
- **filter-preserves-insertion-order**: the array `deployEventsSince` returns MUST preserve the buffer's insertion order (oldest matching entry first), since it is produced by `Array.prototype.filter` over the buffer with no additional sort.
- **filter-is-read-only**: `deployEventsSince` MUST NOT remove, mark, or otherwise mutate any buffered entry, matched or not; two calls with the same `sinceMs` and no intervening `pushDeployEvent` or `clearDeployEvents` call MUST return equal results.

### Resetting (`clearDeployEvents`)

- **clear-empties-buffer**: `clearDeployEvents()` MUST truncate the buffer to zero length (`buffer.length = 0`), discarding every currently buffered entry regardless of its `receivedAt`.
- **clear-is-idempotent**: calling `clearDeployEvents()` when the buffer is already empty MUST leave it empty and MUST NOT raise an error.

### Persistence and Multi-Instance Scope

- **buffer-is-in-memory-only**: every buffered entry MUST exist only in process memory; the module MUST NOT write to disk, a database, or any other durable store, and a process restart MUST lose every entry the buffer held. This is a deliberate durability floor, not an oversight: the module's own comment states the persisted deploy row (written separately, by `hooks.ts`, before it calls `pushDeployEvent`) is the durable copy, and this buffer only ever shortens the latency of seeing it.
- **per-instance-scope-on-multi-instance-deployment**: on a deployment topology with more than one live process instance (the module's own comment names Vercel serverless, one instance per warm lambda), each instance's buffer MUST be independent; a `pushDeployEvent` call on one instance MUST NOT become visible to a `deployEventsSince` call served by a different instance. This is BEST-EFFORT by the module's own accounting, not a documented gap — the accepted mitigation is the caller's own periodic provider poll (60 seconds, external to this file), which independently re-reads authoritative provider state and recovers anything a given instance's buffer failed to deliver.

### Ordering, Concurrency, and Side Effects

- **synchronous-single-threaded-execution**: `pushDeployEvent`, `deployEventsSince`, and `clearDeployEvents` MUST each execute to completion synchronously, with no `await` and no asynchronous step between reading and mutating the shared `buffer` array; within a single process, JavaScript's single-threaded execution model MUST make any two calls into this module run to completion one at a time, with no interleaving of one call's read/splice with another's — this is a fact of the runtime, not a lock this module implements.
- **no-external-side-effects**: none of the three exported functions MUST perform a network call, a file-system operation, a database call, or emit a process signal or notification of any kind; their only observable effect outside their own return value is mutating the shared module-scope `buffer` array.

## Appearance

Not applicable — this is an in-memory deploy-event ring buffer, not a visual component.

## States

Not applicable — this is an in-memory deploy-event ring buffer, not a visual component.

## Accessibility

Not applicable — this is an in-memory deploy-event ring buffer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-live-buffer-001 | push-appends-with-receipt-time | Buffer empty; call `pushDeployEvent(deployA)` while the clock reads `T`; then call `deployEventsSince(0)` | Returns exactly one entry, `{ deploy: deployA, receivedAt: T }` — `receivedAt` equals the clock reading at the moment of the push, not any timestamp on `deployA` |
| status-server-monitor-live-buffer-002 | push-evicts-oldest-beyond-capacity | Buffer empty; call `pushDeployEvent` 201 times in sequence with distinct `deploy.id` values `d0`..`d200` | `deployEventsSince(0)` returns exactly 200 entries, whose `deploy.id` values are `d1`..`d200` in that order — `d0`, the oldest, was evicted by the 201st push |
| status-server-monitor-live-buffer-003 | filter-inclusive-lower-bound | Buffer holds three pushed entries with `receivedAt` 100, 200, and 300 (via an injected sequence of clock readings); call `deployEventsSince(200)` | Returns exactly the entries at 200 and 300 — the entry at 100 is excluded, and the entry at exactly 200 is included (the boundary is inclusive) |
| status-server-monitor-live-buffer-004 | filter-preserves-insertion-order, filter-is-read-only | Buffer holds three pushed entries with `receivedAt` 100, 200, 300, pushed in that order; call `deployEventsSince(0)` twice in a row with no intervening push or clear | Both calls return an array of length 3 in the order `[100, 200, 300]`, and the two calls' results are equal — the first read did not remove or reorder anything |
| status-server-monitor-live-buffer-005 | clear-empties-buffer, clear-is-idempotent | Buffer holds two pushed entries; call `clearDeployEvents()`, then `deployEventsSince(0)`, then call `clearDeployEvents()` a second time with no push in between | The first `deployEventsSince(0)` after clearing returns `[]`; the second `clearDeployEvents()` call raises no error and leaves the buffer at length 0 |
| status-server-monitor-live-buffer-006 | filter-is-read-only, module-scope-singleton | `hooks.ts`-shaped call sequence from `live-deploy-targets.int.test.ts`'s "gates the WEBHOOK OVERLAY too" case: `pushDeployEvent({ ...base, id: 'vc_live', platform: 'vercel', projectName: 'docs-production' })` then `pushDeployEvent({ ...base, id: 'vc_dead', platform: 'vercel', projectName: 'studio-production' })` | `deployEventsSince(0)` returns BOTH pushed entries unfiltered by project ownership — `live-buffer.ts` itself performs no ownership filtering; that gate is applied downstream, by `reads.ts`'s `deploymentDtos`, on the array this function returns |

## Edge Cases

- **Null and empty input**: `deployEventsSince(sinceMs)` called against an empty buffer MUST return `[]`, regardless of `sinceMs`'s value. `deployEventsSince(0)` against a non-empty buffer MUST return every entry, since every `receivedAt` produced by `Date.now()` is a positive number and therefore `>= 0` — MUST. `clearDeployEvents()` called against an already-empty buffer MUST be a no-op that raises no error (see `clear-is-idempotent`) — MUST.
- **Boundary values**: pushing exactly `CAP` (200) entries MUST leave the buffer at length 200 with no eviction; pushing one more (the 201st) MUST evict exactly the single oldest entry, per the `buffer.length - CAP` argument to `splice` evaluating to exactly 1 at that point — MUST. `deployEventsSince` at the exact `receivedAt` value of an entry MUST include that entry (the `>=` comparison), while a `sinceMs` one millisecond later MUST exclude it — MUST.
- **Concurrent access**: within a single process, `pushDeployEvent`, `deployEventsSince`, and `clearDeployEvents` cannot interleave their reads and writes of the shared `buffer` array, because none of the three performs an `await` or any other yield point between reading and mutating it — this is a fact of JavaScript's single-threaded execution model, not a lock this file implements (see `synchronous-single-threaded-execution`) — MUST. Across process instances (the multi-instance serverless case the module's own comment names), there is no synchronization of any kind: each instance's `buffer` is entirely private, and the accepted mitigation is the external provider poll, not any coordination this file performs — MUST (see `per-instance-scope-on-multi-instance-deployment`).
- **Error states**: Not applicable — this file performs no network call, file I/O, or database access of any kind; it has no dependency that can fail or return an error for it to handle.
- **Offline or disconnected state**: Not applicable — this file has no network connectivity of its own to lose. It only decides what an already-in-memory buffer holds and returns; the network I/O that produces the events it buffers (the webhook HTTP request handled by `hooks.ts`) and the network I/O that the poll it defers to performs are both external to this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deploy` (parameter to `pushDeployEvent`) | `ProviderDeploy` | none — required on every call | The deploy event to buffer, already mapped from a webhook payload and typed by the caller (`hooks.ts`'s `mapVercelDeployEvent`/`mapRailwayDeployEvent`); this module performs no validation of its shape. |
| `sinceMs` (parameter to `deployEventsSince`) | `number` | none — required on every call | The inclusive lower bound, in milliseconds, on `receivedAt`. The module's one production caller (`reads.ts`'s `deploymentDtos`) always passes `0`, so in the shipped system every buffered entry is returned on every read (see Design Decisions). |
| `CAP` (module constant) | `number` | `200` | The ring buffer's maximum length. Not caller- or environment-configurable — it is a hardcoded, unexported module constant with no override parameter of any kind. |

## Deep Linking

Not applicable: this file defines no application URL scheme, route, or navigable target — it is a pure in-process data structure with no notion of a URL.

## Localization

Not applicable: this file contains no user-facing string of any kind — no rendered text, no error message, and no log line; its only values are a `ProviderDeploy` payload (opaque to this file), a numeric timestamp, and a boolean-free `void` return.

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind; its only behavioral lever is the fixed `CAP` constant, already documented under Configuration.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this file collects no data of its own. It holds, only in process memory and only until `CAP` eviction or a `clearDeployEvents()` call, the same `ProviderDeploy` values that `hooks.ts` already received over the webhook and already persisted to the database (per `pushDeployEvent`'s call site comment: "PERSIST the pushed state (not just the live buffer)"); it introduces no privacy surface of its own beyond that pass-through, and `ProviderDeploy` carries no token or credential field.

## Logging

Not applicable: this file contains no `console.*` call or structured-logger call of any kind; `pushDeployEvent`, `deployEventsSince`, and `clearDeployEvents` communicate only through their return values.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion process embedding this ring-buffer pattern would model the buffer as a `struct` or small `final class` (`Sendable`, or isolated to an `actor` if shared across concurrency domains) wrapping a `[BufferedDeploy]` array, with `push`, `since(_:)`, and `clear()` methods; Swift's value semantics make eviction (`removeFirst(_:)` in place of `splice`) a one-line operation, and an `actor` gives the "no interleaved read/write" guarantee (`synchronous-single-threaded-execution`) for free across Swift's cooperative concurrency, where this TypeScript file gets it for free from being single-threaded JavaScript.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the buffer as a class holding a `MutableList<BufferedDeploy>` (or an `ArrayDeque` for cheap front-eviction in place of `Array.prototype.splice`), guarded by a `Mutex` or confined to a single coroutine dispatcher if more than one coroutine can call into it — a guarantee this TypeScript file gets for free from JavaScript's single thread but a JVM/Kotlin port cannot assume.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/live-buffer.ts` as a plain module with no framework dependency of its own; its two callers, `hooks.ts` (write side, inside the Vercel/Railway webhook route handlers) and `reads.ts` (read side, inside `deploymentDtos`), are both plain Hono route handlers in the same Node process, so the "module-scope singleton" design (`module-scope-singleton`) resolves at the level of the Node process, not a browser tab or request.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no additional concern beyond SwiftUI's bullet; there is no per-view-controller duplication risk the way there can be for view-layer state, because this is backend-process logic with a single shared instance by construction.
- **WinUI 3**: a .NET port models the buffer as a small class wrapping a `System.Collections.Generic.List<BufferedDeploy>` (or a `System.Collections.Generic.Queue<BufferedDeploy>` if only front-eviction and back-append are ever needed, which matches this file's own usage exactly), exposing `void Push(ProviderDeploy deploy)`, `IReadOnlyList<BufferedDeploy> Since(long sinceMs)`, and `void Clear()`. Unlike the source's single-threaded JavaScript, a WinUI 3 host's webhook receiver and its `/live`-equivalent read path can run on different threads (ASP.NET Core request threads, or a background `Task` polling loop), so the `synchronous-single-threaded-execution` guarantee this file gets for free does NOT carry over — the port MUST add its own synchronization (a `lock` around the list, or `System.Collections.Concurrent.ConcurrentQueue<BufferedDeploy>` in place of `List<T>`) to preserve `filter-is-read-only`'s "no interleaved read/write" property. The capacity eviction (`push-evicts-oldest-beyond-capacity`) maps to `Queue<T>.Dequeue()` in a loop while `Count > Cap`, and the inclusive-lower-bound filter (`filter-inclusive-lower-bound`) is a straightforward LINQ `.Where(b => b.ReceivedAt >= sinceMs)` over a snapshot taken under the same lock.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/live-buffer.ts` |

## Design Decisions

- **Decision**: bound the buffer by a fixed entry count (200, via `splice`-based front-eviction of the oldest entries) rather than by a time-based expiry.
  **Rationale**: matches the module's own doc comment directly — the buffer only ever "shortens latency," it is never the source of truth (the periodic poll is), so a fixed count is a cheap, deterministic memory bound that needs no timer, no scheduled sweep, and no clock dependency of its own beyond the `Date.now()` already read on push. The risk of evicting an entry a slow reader has not yet consumed is real but accepted for the same reason: the poll this file defers to recovers anything the buffer fails to deliver.
  **Approved**: pending
- **Decision**: keep the buffer as bare module-scope state (one shared array) instead of a factory-created, explicitly-constructed instance.
  **Rationale**: the consuming server runs `hooks.ts` and `reads.ts` inside a single Node process per instance, so a module-scope singleton is the simplest shape for that topology; this also explains why `clearDeployEvents` exists purely as a test seam ("module state persists across vitest cases," per its own doc comment) rather than a general-purpose reset API a production caller would ever need.
  **Approved**: pending
- **Decision**: accept per-instance, best-effort delivery on multi-instance serverless deployments instead of centralizing the buffer in a shared store (e.g. Redis or the database).
  **Rationale**: stated directly in the module's own top-of-file comment — exact on a long-running server, best-effort on Vercel serverless because each warm instance owns a private buffer and an event may land on an instance a given read never reaches. Accepted because the 60-second poll (external to this file) independently re-reads provider truth, so the buffer can only ever shorten user-visible latency, never be relied on to carry information the poll cannot recover on its own.
  **Approved**: pending
- **Decision**: leave `deployEventsSince`'s `sinceMs` parameter general-purpose even though its one production caller (`reads.ts`'s `deploymentDtos`) always passes `0`.
  **Rationale**: not stated in a comment; observed directly at the call site. Documented here rather than treated as a gap in this file, because a constant argument at the one call site is a fact about that caller's current design, not an unmet contract in `deployEventsSince` itself, which remains free to be called with any `sinceMs` a future caller needs.
  **Approved**: pending
- **Decision**: keep both id-based deduplication (the "newest info wins an id-merge downstream" the module's own doc comment on `deployEventsSince` references) and ownership filtering out of this file, leaving `deployEventsSince` to return every buffered entry unfiltered and unmerged.
  **Rationale**: `reads.ts`'s `deploymentDtos` is the one place that folds buffer entries into a `Map` keyed by `id` and applies its `keep` ownership predicate (confirmed by test vector 006). Keeping this file's contract to exactly "store, evict, and filter by time" keeps it a single, narrow concern per `separation-of-concerns`, leaving the id-merge and ownership policy to change independently in `reads.ts` without touching this file.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | Performance |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | failed | Reliability |

`separation-of-concerns` passes: this file's only concern is storing and time-filtering deploy events in memory; it performs no network I/O, no persistence, no ownership policy, and no id-merge — those are left to `hooks.ts` and `reads.ts` respectively (see Design Decisions). `unit-test-coverage` is `partial`: no test file targets `live-buffer.ts` directly, and none of its three exported functions has a dedicated assertion of its own contract (there is no test asserting the 200-entry eviction boundary or the inclusive `receivedAt >= sinceMs` filter edge); the module IS exercised, but only indirectly, through `hooks.int.test.ts`, `hooks-alerting.int.test.ts`, and `live-deploy-targets.int.test.ts` calling `pushDeployEvent`/`clearDeployEvents` as setup/teardown for assertions about ownership and issue-derivation, not about the buffer itself. `good-test-properties` passes for the tests that do exercise it: each of the three integration suites calls `clearDeployEvents()` in `beforeEach`/`afterEach` specifically to keep the shared module state isolated between cases (the module's own doc comment on `clearDeployEvents` says as much — "module state persists across vitest cases"), and every assertion in those suites is a plain, repeatable, self-validating `expect(...)`. `resource-efficiency` passes: `push-evicts-oldest-beyond-capacity` bounds this long-lived, process-scoped structure to exactly 200 entries, so it cannot grow without bound across the process's lifetime regardless of webhook volume. `fault-tolerance` passes: neither `pushDeployEvent` nor `deployEventsSince` throws on any input reachable through their typed signatures — an out-of-range or `NaN` `sinceMs` simply produces an empty or full result via the `>=` comparison rather than a crash, and the shape of `deploy` is a caller precondition enforced upstream by `hooks.ts`'s webhook mappers, not by this file. `health-observability` fails: none of the three exported functions gives any caller a way to read the buffer's current size, its oldest or newest `receivedAt`, or a count of entries `push-evicts-oldest-beyond-capacity` has evicted — for a structure whose own doc comment flags a real, accepted data-loss mode (per-instance best-effort delivery on serverless), there is no signal a caller could use to notice how close to that mode the buffer is running.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
