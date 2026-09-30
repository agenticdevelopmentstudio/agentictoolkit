<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-inference-guard--part-2 · source: ai-plugin-runtime-ai-plugin-kit-local-inference-guard.md -->

# LocalInferenceGuard — continued (part 2)

## Localization

`LocalInferenceGuard.swift` defines no string-key or localization-table
lookup; every string it produces is a hardcoded English literal composed
inline, with no key system to reference:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Local model \(model) is warn-tier: \(footprint) est.` | `verdict(model:baseURL:settings:)`'s `Logger.notice` call when the computed tier is `.warn`. |
| (none — literal, no key) | `local inference exceeded its \(Int(deadline))s deadline; deferring` | `withDeadline`'s timer branch, surfaced to callers as `AIGuardError.deferred`'s `errorDescription`. |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift`,
  alongside its collaborators `ModelFitPolicy.swift`,
  `LocalModelCatalog.swift`, and `SystemMemoryMonitor.swift`, and its
  consumer `DaemonAIChat.swift`/`DaemonProviderResolver.swift` (the source of
  `ProviderSettingsReader`). It uses `actor` isolation plus
  `CheckedContinuation` and `withThrowingTaskGroup` for the mutex and
  deadline race, `os.Logger` for logging, and `DispatchSourceMemoryPressure`
  (via `SystemMemoryMonitor`) for live pressure. Nothing here is
  SwiftUI-specific — any host consumes `LocalInferenceGuard` identically.
- **Compose**: Kotlin has a ready FIFO-fair primitive
  (`kotlinx.coroutines.sync.Mutex`) to stand in for the hand-rolled
  continuation queue, and `withTimeoutOrNull`/`withTimeout` from
  kotlinx-coroutines in place of the manual `TaskGroup` deadline race.
  `ActivityManager.MemoryInfo`/`ComponentCallbacks2.onTrimMemory` is the
  Android analogue of `SystemMemoryMonitoring`'s latched pressure level; a
  plain `object`/singleton class stands in for `LocalInferenceGuard.shared`.
- **React/Web**: Neither Node.js nor the browser exposes an OS-level
  memory-pressure signal analogous to `DispatchSourceMemoryPressure`; a Node
  host can approximate available headroom with `os.totalmem()` /
  `process.memoryUsage()` but has no `.warning`/`.critical` latch to read. Use
  an async mutex library (e.g. `async-mutex`'s `Mutex`, which is FIFO by
  default) for the exclusive lock, `AbortController` plus `Promise.race`
  against a `setTimeout` for the deadline race in place of
  `withThrowingTaskGroup`, and `fetch` with `AbortSignal.timeout(5000)` for
  the model-size lookup analogous to `LocalModelCatalog.liveFetcher`.
- **AppKit / UIKit**: Identical to the SwiftUI note — this actor is
  UI-framework-agnostic; only the host application embedding `AIPluginKit`
  differs, never this contract.
- **WinUI 3**: Model `LocalInferenceGuard` as a plain C# class wrapping a
  `SemaphoreSlim(1, 1)` (FIFO-fair by default) in place of the hand-rolled
  `CheckedContinuation` waiter queue, exposing an `async Task<T>
  RunExclusiveAsync<T>(TimeSpan deadline, Func<Task<T>> operation)` method.
  Race the deadline with `Task.WhenAny(operationTask,
  Task.Delay(deadline, cts.Token))` and a `CancellationTokenSource` in place
  of `withThrowingTaskGroup`, cancelling the loser exactly as the source
  does. Represent `AIGuardError` as two distinct exception types (e.g.
  `AiGuardBlockedException` / `AiGuardDeferredException`), never a subtype or
  wrapper of whatever exception carries transport failures, so a `catch`
  block for the CLI-style fallback path structurally cannot also catch a
  guard refusal. Use `GlobalMemoryStatusEx` (via P/Invoke) or
  `Windows.System.MemoryManager.AppMemoryUsageLevel` for the RAM/pressure
  analogue of `SystemMemoryMonitoring`, and `HttpClient` with a 5-second
  `Timeout` for the model-size fetch analogous to
  `LocalModelCatalog.liveFetcher`.

## Design Decisions

**Decision**: `runExclusive`'s `deadline` bounds only the operation's own
execution once the lock is granted, not the time spent waiting to acquire
it.
**Rationale**: The doc comment states this explicitly — "`deadline` bounds
the operation's wall-clock run." Because the raw `acquire`/`release`/
`cancelWaiter` primitives are private, every caller reaches the lock only
through `runExclusive`, so every current holder is itself deadline-bound;
this gives every waiter an implicit, transitive bound on total wait time
without needing an explicit per-waiter timeout.
**Approved**: pending

**Decision**: The mutex is not reentrant, and `runExclusive` performs no
recursion or owner-task detection.
**Rationale**: This matches the semantics of a plain `NSLock`/
`DispatchSemaphore`; adding owner-task bookkeeping was not implemented, and
every current call site (`DaemonAIChat.complete`/`completeViaPlugin`) calls
`runExclusive` exactly once per request, so a self-deadlock from reentrant
use is a documented caller obligation (see `no-reentrant-acquisition`) rather
than a runtime-enforced one.
**Approved**: pending

**Decision**: `release()` hands ownership directly to the next waiter,
keeping `busy` `true` across the handoff rather than briefly setting it
`false` and letting a new caller re-acquire.
**Rationale**: Per the source comment: "Direct handoff: the head waiter
becomes the owner; `busy` never dips to false in between, so no arrival can
slip past the queue." A false-then-true toggle would open a race window in
which a brand-new, uncontended caller could acquire ahead of an
already-waiting FIFO queue.
**Approved**: pending

**Decision**: The deferred-reason message composes the deadline with
`Int(deadline)`, which truncates toward zero.
**Rationale**: This is a direct, unremarked consequence of Swift's
`Int(Double)` conversion at the message-formatting call site; the guard does
not round or special-case sub-second deadlines (e.g. the test suite's
`deadline: 0.1` reads as `"...its 0s deadline..."`), and no production host
currently configures a sub-second deadline.
**Approved**: pending
