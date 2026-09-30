<!-- leaf: implement-foundation/process · source: foundation-process.md -->

**Rules** (cite as `implement-foundation/process#<slug>`):

- `stream-draining` MUST
- `concurrent-drain-collection` MUST
- `termination-handler-before-run` MUST
- `run-throw-propagation` MUST
- `deadline-wait-without-watchdog` MUST
- `watchdog-polling` MUST
- `exit-during-poll-is-clean` MUST
- `terminate-on-timeout-or-abort` MUST
- `sigkill-escalation` MUST
- `status-sentinel-on-non-exit` MUST
- `bounded-post-exit-drain-wait` MUST
- `readability-handlers-cleared` MUST
- `outcome-buffers-always-populated` MUST
- `diagnostics-trimmed-utf8` MUST
- `timedout-aborted-mutually-exclusive` MUST
- `watchdog-parameter-default` MUST
- `termination-grace-fixed` MUST
- `outcome-and-watchdog-sendable` MUST
- `watchdog-callback-serialized` MUST
- `synchronous-blocking-call` MUST

# CommandRunner

## Overview

`CommandRunner` (`packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift`, part of the `AgenticToolkitCore` framework target, `platform: macOS` only) is a case-less `public enum` namespace holding one entry point, `runToCompletion(_:timeout:watchdog:)`, that runs a `Foundation.Process` to completion and comes back with everything it wrote. Per its own doc comment, it exists to close two ways a synchronous run-and-wait would hang forever: a `Pipe` nobody drains stops the child the moment the kernel's 64 KB buffer fills, and a tool that never exits holds the calling thread indefinitely. `runToCompletion` installs its own `Pipe` on both `standardOutput` and `standardError`, drains each as it is written via a readability handler, and waits against a `timeout` deadline (or an optional `Watchdog` that can end the run earlier for a reason of the caller's own). A run that reaches its deadline or its watchdog's condition is terminated — `SIGTERM`, then `SIGKILL` after a fixed grace period if the process ignores it — and reported back as an `Outcome` rather than thrown away. It is the whole-output, one-shot shape; a tool meant to hold an ongoing conversation is `SubprocessChannel` (`packages/apple/AgenticToolkit/Core/RPC/SubprocessChannel.swift`), which this recipe does not cover.

## Behavioral Requirements

- **stream-draining**: `runToCompletion` MUST install a `Pipe` on both `process.standardOutput` and `process.standardError`, replacing anything a caller already set on either property (per the doc comment), and MUST begin draining each via a `readabilityHandler` installed before `process.run()` is called, so that output written by the process is read as it arrives rather than after the process exits.
- **concurrent-drain-collection**: Both streams' drained chunks MUST be appended into one lock-protected `Collector` so that Foundation delivering both streams' readability callbacks "at once" (per the doc comment on `Collector`) never races or drops a chunk.
- **termination-handler-before-run**: `process.terminationHandler` MUST be assigned before `process.run()` is called, so the exit signal cannot be missed between starting the process and beginning to wait for it.
- **run-throw-propagation**: If `process.run()` throws, `runToCompletion` MUST rethrow that error to the caller unchanged, and MUST first clear both pipes' `readabilityHandler` and `process.terminationHandler`; it MUST NOT wait, drain, or return an `Outcome` on this path.
- **deadline-wait-without-watchdog**: When `watchdog` is `nil`, `runToCompletion` MUST wait for the process to exit for up to `timeout` seconds and MUST set `timedOut = true` if that wait itself expires without the process exiting.
- **watchdog-polling**: When a `watchdog` is supplied, `runToCompletion` MUST poll `watchdog.shouldAbort()` on the calling thread at an interval no larger than `watchdog.interval`, and never larger than the deadline's remaining time (`min(watchdog.interval, remaining)`), MUST set `aborted = true` and stop polling the first time `shouldAbort()` returns `true`, and MUST set `timedOut = true` instead, without ever calling `shouldAbort()` again, if the overall `timeout` deadline is reached first.
- **exit-during-poll-is-clean**: If the process exits during a watchdog poll interval, `runToCompletion` MUST leave both `timedOut` and `aborted` `false` (the semaphore wait succeeding breaks the loop before either flag is set).
- **terminate-on-timeout-or-abort**: `runToCompletion` MUST call `process.terminate()` if and only if `timedOut` or `aborted` is `true`; it MUST NOT call `terminate()` on a process that exited on its own.
- **sigkill-escalation**: After calling `process.terminate()`, `runToCompletion` MUST wait up to `terminationGrace` (2 seconds) for the process to exit, and if that wait itself expires, MUST send `SIGKILL` to `process.processIdentifier` and then wait up to another `terminationGrace` for exit.
- **status-sentinel-on-non-exit**: `Outcome.status` MUST be `CommandRunner.neverExited` (`-1`) when the process still has not exited after the `SIGKILL` wait, and MUST be `process.terminationStatus` in every other case.
- **bounded-post-exit-drain-wait**: Once the process has exited, been killed, or given up on, `runToCompletion` MUST bound each stream's drain-completion wait to `terminationGrace` rather than waiting unboundedly for an EOF that the doc comment notes "has already been posted" in the ordinary case.
- **readability-handlers-cleared**: Both pipes' `readabilityHandler` MUST be set to `nil` before `runToCompletion` returns, on every return path — the throw path and the normal return path.
- **outcome-buffers-always-populated**: `Outcome.standardOutput` and `Outcome.standardError` MUST be exactly the bytes the `Collector` accumulated for each stream, returned regardless of `status`, `timedOut`, or `aborted` — a killed or timed-out run's partial output MUST still be returned, not discarded.
- **diagnostics-trimmed-utf8**: `Outcome.diagnostics` MUST decode `standardError` as UTF-8, MUST fall back to an empty string when the bytes are not valid UTF-8, and MUST trim leading and trailing whitespace and newline characters from the result.
- **timedout-aborted-mutually-exclusive**: For a single call to `runToCompletion`, at most one of `Outcome.timedOut` and `Outcome.aborted` MUST be `true` — the watchdog branch sets at most one of the two before breaking its loop, and the non-watchdog branch can set only `timedOut`; no code path sets both.
- **watchdog-parameter-default**: The `watchdog` parameter to `runToCompletion` MUST default to `nil` when the caller omits it.
- **termination-grace-fixed**: The grace period between `SIGTERM` and `SIGKILL`, and the bound on the post-exit drain wait, MUST be exactly 2 seconds (`terminationGrace`) and is not a parameter `runToCompletion` exposes to callers.
- **outcome-and-watchdog-sendable**: `Outcome` MUST be declared `Sendable` and `Equatable`, and `Watchdog` MUST be declared `Sendable` with its `shouldAbort` closure typed `@Sendable`, so both MAY be passed across concurrency-domain boundaries; `Collector` MUST be `@unchecked Sendable` because Foundation delivers both streams' readability callbacks on its own queue, off the calling thread, and the type's own `NSLock` is the manual synchronization that makes the unchecked claim correct — the compiler does not verify it.
- **watchdog-callback-serialized**: `watchdog.shouldAbort` MUST be called only from the one thread running the polling loop inside `runToCompletion`, and MUST NOT be called concurrently with itself, per the type's own doc comment.
- **synchronous-blocking-call**: `runToCompletion` MUST run synchronously on the thread that calls it — it declares no `async` and contains no cooperative suspension point, only `DispatchSemaphore.wait` calls — so a caller MUST expect that calling thread (including the main thread or a `@MainActor`-isolated caller's queue) to be occupied for the entire run, up to `timeout` plus as much as two `terminationGrace` periods.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `process` (parameter to `runToCompletion`) | `Process` | none — required | The already-configured `Process` to run; `standardOutput` and `standardError` are overwritten with `CommandRunner`'s own pipes. |
| `timeout` (parameter to `runToCompletion`) | `TimeInterval` | none — required | How long the run is given before it is terminated and reported as timed out. |
| `watchdog` (parameter to `runToCompletion`) | `Watchdog?` | `nil` | An optional condition, polled while the process runs, that ends the run early for a reason other than the clock. |
| `interval` (parameter to `Watchdog.init`) | `TimeInterval` | none — required | How often `shouldAbort` is polled; the run ends within one interval of the condition becoming true. |
| `shouldAbort` (parameter to `Watchdog.init`) | `@Sendable () -> Bool` | none — required | Called on the waiting thread, never concurrently with itself; the first `true` ends the run. |

`terminationGrace` (2 seconds, the wait between `SIGTERM` and `SIGKILL`, and the bound on the post-exit drain wait) is a private, fixed constant — it is not exposed as a parameter, environment variable, or settings key anywhere in the source.

