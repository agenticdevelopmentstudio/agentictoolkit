<!-- leaf: implement-status-server-monitor-1/live-buffer · source: status-server-monitor-live-buffer.md -->

**Rules** (cite as `implement-status-server-monitor-1/live-buffer#<slug>`):

- `buffer-capacity-constant` MUST
- `buffered-deploy-shape` MUST
- `module-scope-singleton` MUST
- `push-appends-with-receipt-time` MUST
- `push-evicts-oldest-beyond-capacity` MUST
- `push-returns-void` MUST
- `filter-inclusive-lower-bound` MUST
- `filter-preserves-insertion-order` MUST
- `filter-is-read-only` MUST
- `clear-empties-buffer` MUST
- `clear-is-idempotent` MUST
- `buffer-is-in-memory-only` MUST
- `per-instance-scope-on-multi-instance-deployment` MUST
- `synchronous-single-threaded-execution` MUST
- `no-external-side-effects` MUST
- `winui-3` MUST — a .NET port models the buffer as a small class wrapping a System.Collections.Generic.List<BufferedDeploy> (or a …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deploy` (parameter to `pushDeployEvent`) | `ProviderDeploy` | none — required on every call | The deploy event to buffer, already mapped from a webhook payload and typed by the caller (`hooks.ts`'s `mapVercelDeployEvent`/`mapRailwayDeployEvent`); this module performs no validation of its shape. |
| `sinceMs` (parameter to `deployEventsSince`) | `number` | none — required on every call | The inclusive lower bound, in milliseconds, on `receivedAt`. The module's one production caller (`reads.ts`'s `deploymentDtos`) always passes `0`, so in the shipped system every buffered entry is returned on every read (see Design Decisions). |
| `CAP` (module constant) | `number` | `200` | The ring buffer's maximum length. Not caller- or environment-configurable — it is a hardcoded, unexported module constant with no override parameter of any kind. |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion process embedding this ring-buffer pattern would model the buffer as a `struct` or small `final class` (`Sendable`, or isolated to an `actor` if shared across concurrency domains) wrapping a `[BufferedDeploy]` array, with `push`, `since(_:)`, and `clear()` methods; Swift's value semantics make eviction (`removeFirst(_:)` in place of `splice`) a one-line operation, and an `actor` gives the "no interleaved read/write" guarantee (`synchronous-single-threaded-execution`) for free across Swift's cooperative concurrency, where this TypeScript file gets it for free from being single-threaded JavaScript.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the buffer as a class holding a `MutableList<BufferedDeploy>` (or an `ArrayDeque` for cheap front-eviction in place of `Array.prototype.splice`), guarded by a `Mutex` or confined to a single coroutine dispatcher if more than one coroutine can call into it — a guarantee this TypeScript file gets for free from JavaScript's single thread but a JVM/Kotlin port cannot assume.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/live-buffer.ts` as a plain module with no framework dependency of its own; its two callers, `hooks.ts` (write side, inside the Vercel/Railway webhook route handlers) and `reads.ts` (read side, inside `deploymentDtos`), are both plain Hono route handlers in the same Node process, so the "module-scope singleton" design (`module-scope-singleton`) resolves at the level of the Node process, not a browser tab or request.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no additional concern beyond SwiftUI's bullet; there is no per-view-controller duplication risk the way there can be for view-layer state, because this is backend-process logic with a single shared instance by construction.
- **WinUI 3**: a .NET port models the buffer as a small class wrapping a `System.Collections.Generic.List<BufferedDeploy>` (or a `System.Collections.Generic.Queue<BufferedDeploy>` if only front-eviction and back-append are ever needed, which matches this file's own usage exactly), exposing `void Push(ProviderDeploy deploy)`, `IReadOnlyList<BufferedDeploy> Since(long sinceMs)`, and `void Clear()`. Unlike the source's single-threaded JavaScript, a WinUI 3 host's webhook receiver and its `/live`-equivalent read path can run on different threads (ASP.NET Core request threads, or a background `Task` polling loop), so the `synchronous-single-threaded-execution` guarantee this file gets for free does NOT carry over — the port MUST add its own synchronization (a `lock` around the list, or `System.Collections.Concurrent.ConcurrentQueue<BufferedDeploy>` in place of `List<T>`) to preserve `filter-is-read-only`'s "no interleaved read/write" property. The capacity eviction (`push-evicts-oldest-beyond-capacity`) maps to `Queue<T>.Dequeue()` in a loop while `Count > Cap`, and the inclusive-lower-bound filter (`filter-inclusive-lower-bound`) is a straightforward LINQ `.Where(b => b.ReceivedAt >= sinceMs)` over a snapshot taken under the same lock.

