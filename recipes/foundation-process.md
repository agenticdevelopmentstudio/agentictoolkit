---
id: 705082e9-8fad-4c20-95a3-4cf843cc6b97
title: CommandRunner
domain: agentictoolkit://recipes/foundation-process
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: CommandRunner drains a helper process's stdout and stderr while it runs and
  enforces a deadline or watchdog condition, escalating to SIGTERM then SIGKILL.
platforms:
- swift
- macos
tags:
- process
- foundation
- subprocess
- timeout
- watchdog
- sendable
depends-on: []
related:
- agentictoolkit://recipes/foundation-concurrency
references:
- packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Process/CommandRunnerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a process-execution utility, not a visual component.

## States

Not applicable — this is a process-execution utility, not a visual component. Its one runtime state machine (waiting on the deadline or watchdog, then terminating, then escalating to `SIGKILL`) is captured under Behavioral Requirements above, not as a UI visual-state table.

## Accessibility

Not applicable — this is a process-execution utility, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-process-001 | stream-draining, outcome-buffers-always-populated | `CommandRunnerTests.aFloodOfStandardOutputDoesNotDeadlock`: `head -c 200000 /dev/zero \| tr '\0' 'x'`, timeout 30. | Returns without hanging; `!outcome.timedOut`; `outcome.status == 0`; `outcome.standardOutput.count == 200_000`. |
| foundation-process-002 | stream-draining, outcome-buffers-always-populated | `CommandRunnerTests.aFloodOfStandardErrorDoesNotDeadlock`: same shape, writing 200 KB to stderr instead. | `!outcome.timedOut`; `outcome.standardError.count == 200_000`. |
| foundation-process-003 | run-throw-propagation | `CommandRunnerTests.aMissingExecutableThrows`: `executableURL` set to `/usr/bin/definitely-not-a-tool`, timeout 30. | The call throws; no `Outcome` is produced. |
| foundation-process-004 | outcome-buffers-always-populated, diagnostics-trimmed-utf8 | `CommandRunnerTests.theStatusAndTheDiagnosticsComeBack`: `printf 'no such file\n' >&2; exit 3`, timeout 30. | `outcome.status == 3`; `outcome.diagnostics == "no such file"`; `!outcome.timedOut`; `outcome.standardOutput.isEmpty`. |
| foundation-process-005 | deadline-wait-without-watchdog, terminate-on-timeout-or-abort | `CommandRunnerTests.aCommandThatWillNotFinishIsGivenUpOn`: `sleep 30`, timeout 0.5. | `outcome.timedOut == true`; call returns in under 10 seconds, not 30. |
| foundation-process-006 | terminate-on-timeout-or-abort, sigkill-escalation | `CommandRunnerTests.aCommandGivenUpOnIsNoLongerRunning`: `sleep 30`, timeout 0.5. | `outcome.timedOut == true`; `process.isRunning == false` after the call returns. |
| foundation-process-007 | sigkill-escalation, outcome-buffers-always-populated | `CommandRunnerTests.aToolThatIgnoresTerminationIsKilled`: `/bin/sh -c "trap '' TERM; echo armed; while :; do sleep 1 >/dev/null 2>&1; done"`, timeout 1. | `outcome.timedOut == true`; elapsed time under 8 seconds (1s timeout + 2s grace + 2s grace budget); `outcome.diagnostics.isEmpty`; `outcome.standardOutput` decodes to a string containing `"armed"`. |
| foundation-process-008 | watchdog-polling, timedout-aborted-mutually-exclusive | `CommandRunnerTests.aWatchdogEndsTheRun`: `sleep 30`, timeout 30, `Watchdog(interval: 0.1) { calls.bump() > 2 }`. | `outcome.aborted == true`; `outcome.timedOut == false`; call returns in under 10 seconds. |
| foundation-process-009 | timedout-aborted-mutually-exclusive | `CommandRunnerTests.aTimeoutWithAWatchdogIsStillATimeout`: `sleep 30`, timeout 0.5, `Watchdog(interval: 0.1) { false }`. | `outcome.timedOut == true`; `outcome.aborted == false`. |
| foundation-process-010 | watchdog-polling, outcome-buffers-always-populated | `CommandRunnerTests.aQuietWatchdogChangesNothing`: `printf hello; exit 3`, timeout 30, `Watchdog(interval: 0.05) { false }`. | `outcome.aborted == false`; `outcome.timedOut == false`; `outcome.status == 3`; `outcome.standardOutput` decodes to `"hello"`. |
| foundation-process-011 | exit-during-poll-is-clean | `CommandRunnerTests.anExitDuringAPollIsNotAnAbort`: `exit 0`, timeout 30, `Watchdog(interval: 5) { true }`. | `outcome.aborted == false`; `outcome.status == 0`. |
| foundation-process-012 | status-sentinel-on-non-exit, watchdog-parameter-default | `CommandRunnerTests.anExitingToolReportsItsOwnStatus`: `exit 3`, timeout 10, no `watchdog` argument. | `!outcome.timedOut`; `outcome.status == 3`; `outcome.status != CommandRunner.neverExited`. |
| foundation-process-013 | watchdog-polling, terminate-on-timeout-or-abort | `VSIXArchive.expand` (`VSIXArchive.swift`), a real caller: runs `/usr/bin/ditto -x -k <archive> <destination>` through `runToCompletion` with `timeout: 120` and `Watchdog(interval: 0.5) { expandedSize(of: destination, ...) > byteCeiling }`, against an archive engineered to expand past `byteCeiling` (2 GiB default). | `outcome.aborted == true` is observed by the caller, which deletes the half-written destination and throws `VSIXArchiveError.expansionTooLarge`; the same call site treats `outcome.timedOut` and a nonzero `outcome.status` as two further, distinct failure branches. |

## Edge Cases

- **Null / empty input**: A `Process` whose command produces zero bytes on both streams MUST result in `Outcome.standardOutput == Data()` and `Outcome.standardError == Data()` (and therefore `diagnostics == ""`) — `Collector.data(for:)` falls back to `Data()` for a stream nothing was ever appended to; this is a MUST, with no special-case branch in the source for "nothing was written." An empty or all-whitespace `standardError` MUST still trim to `""` in `diagnostics`.
- **Boundary values**: A `timeout` of zero or negative MUST cause an immediate timeout — in the watchdog branch, `remaining > 0` fails on the very first check, so `watchdog.shouldAbort()` MUST NOT be called even once; in the non-watchdog branch, `exited.wait(timeout: .now() + timeout)` MUST report `.timedOut` at once for a non-positive `timeout`, per the same deadline arithmetic. A `watchdog.interval` of zero MUST cause the polling loop to call `shouldAbort()` as fast as `DispatchSemaphore.wait` permits, with no minimum interval enforced by the source.
- **Concurrent access**: Two or more concurrent calls to `runToCompletion`, each against its own `Process`, MUST run independently with no shared mutable state — the only static state in the type is `terminationGrace` and `neverExited`, both immutable `let` constants; every `Collector`, semaphore, and local flag (`timedOut`, `aborted`, `didExit`) MUST be allocated fresh per call.
- **Error states**: If `process.run()` throws (the executable is missing, or this process lacks permission to execute it), that error MUST propagate to the caller unchanged, per `run-throw-propagation`, rather than being reported as a nonzero `Outcome.status`. A process that runs and exits with a nonzero status MUST NOT be surfaced as a Swift error at all — per the doc comment, "a tool that ran and failed is not an error here; it is an `Outcome` with a non-zero `status`" — the caller is required to inspect `Outcome.status` itself.
- **Offline / disconnected state**: Not applicable — `CommandRunner.swift` performs no network access of its own; it only runs and drains an arbitrary `Process`. If the wrapped process is itself a network client (none of `CommandRunner`'s current callers are), a lost connection would surface only as whatever exit status or `standardError` bytes that tool produces, through the Error States path above — `CommandRunner` has no offline-specific behavior of its own.
- **Cancellation**: `runToCompletion` offers no cancellation token and observes no `Task` cancellation, because it is fully synchronous (`synchronous-blocking-call`) — the only ways to end a run before the process exits on its own are the `timeout` deadline and an optional `Watchdog`'s `shouldAbort`. A caller with no `watchdog` MUST wait the full `timeout` before the process is even asked to terminate; a caller that needs to cancel a run for a reason of its own MUST express that reason as a `Watchdog.shouldAbort` closure, since none is built in.
- **abandoned-pipe-write-end**: When a grandchild process has inherited a pipe's write end and is still alive past `terminationGrace` after the parent process has exited or been killed, the post-exit drain wait gives up at the bound the source comment declares ("in case a grandchild inherited one of them"), and `Outcome.standardOutput`/`standardError` hold only what was drained by then; `Outcome` carries no field distinguishing a complete capture from one cut short by that bound.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `process` (parameter to `runToCompletion`) | `Process` | none — required | The already-configured `Process` to run; `standardOutput` and `standardError` are overwritten with `CommandRunner`'s own pipes. |
| `timeout` (parameter to `runToCompletion`) | `TimeInterval` | none — required | How long the run is given before it is terminated and reported as timed out. |
| `watchdog` (parameter to `runToCompletion`) | `Watchdog?` | `nil` | An optional condition, polled while the process runs, that ends the run early for a reason other than the clock. |
| `interval` (parameter to `Watchdog.init`) | `TimeInterval` | none — required | How often `shouldAbort` is polled; the run ends within one interval of the condition becoming true. |
| `shouldAbort` (parameter to `Watchdog.init`) | `@Sendable () -> Bool` | none — required | Called on the waiting thread, never concurrently with itself; the first `true` ends the run. |

`terminationGrace` (2 seconds, the wait between `SIGTERM` and `SIGKILL`, and the bound on the post-exit drain wait) is a private, fixed constant — it is not exposed as a parameter, environment variable, or settings key anywhere in the source.

## Deep Linking

Not applicable: `CommandRunner.swift` defines no URL scheme, route, or navigation destination — it runs and drains an operating-system process, not application navigation.

## Localization

Not applicable: `CommandRunner.swift` contains no user-facing string literal of its own; every string it produces (`Outcome.diagnostics`) is whatever bytes the wrapped process happened to write to its own `standardError`, not text this file authors.

## Accessibility Options

Not applicable: `CommandRunner.swift` presents no UI, so it responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: `CommandRunner.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `CommandRunner.swift` contains no analytics or event-tracking call.

## Privacy

Not applicable: `CommandRunner.swift` defines and stores no data of its own — it relays whatever bytes `standardOutput`/`standardError` carry back to its caller, in memory, for the duration of one call, and persists nothing to disk. Whether those bytes are privacy-sensitive (a credential a wrapped tool happened to print, for instance) is a property of the process the caller chose to run, not of this file, which inspects none of the content it drains.

## Logging

Not applicable: `CommandRunner.swift` contains no logging call — nothing in the file writes to `os_log`, `Logger`, `print`, or any other logging subsystem; a caller that wants a failed run logged MUST do so itself from the returned `Outcome`.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares as `platform: macOS` only — `Foundation.Process` has no iOS/tvOS/watchOS counterpart, so this type does not port to those platforms at all. The file imports only `Foundation`; nothing in it is SwiftUI-specific.
- **Compose**: Port with `java.lang.ProcessBuilder`/`Process`, reading `inputStream`/`errorStream` on separate `Dispatchers.IO` coroutines (the analogue of the readability handler) into shared, mutex-guarded buffers (the `Collector` analogue). Use `withTimeoutOrNull(timeoutMillis) { process.awaitExit() }` for the deadline and a second coroutine polling the watchdog condition on its own interval; escalate with `process.destroy()` then `process.destroyForcibly()` after a fixed grace delay, mirroring the `SIGTERM`-then-`SIGKILL` sequence.
- **React/Web**: Port with Node's `child_process.spawn`, reading `stdout`/`stderr` via their `'data'` events into accumulator buffers — Node's own stream backpressure handling makes the 64 KB deadlock this type exists to avoid a non-issue as long as those events are subscribed to before the process starts. Use one `setTimeout` for the deadline and, when a watchdog is needed, a `setInterval` that clears itself and calls `child.kill('SIGTERM')` the first time its condition is `true`; escalate to `child.kill('SIGKILL')` from a second `setTimeout` armed at the same moment, mirroring the grace period.
- **AppKit / UIKit**: Identical to the SwiftUI note — `CommandRunner` is UI-framework-agnostic; only the macOS-only availability of `Foundation.Process` applies, never the choice of UI framework above it. It is called today from throwing, synchronous Swift call sites (`VSIXArchive.expand`) that are themselves wrapped in `BlockingWork.run` (see Design Decisions) to keep the block off the Swift concurrency cooperative pool.
- **WinUI 3**: Port with `System.Diagnostics.Process`/`ProcessStartInfo` (`RedirectStandardOutput = true`, `RedirectStandardError = true`), draining via the `OutputDataReceived`/`ErrorDataReceived` events (started with `BeginOutputReadLine`/`BeginErrorReadLine`) in place of the `Pipe` + `readabilityHandler` pair — .NET's asynchronous line-based reads are the same "drain while it writes" answer to the pipe-buffer deadlock. Use `await process.WaitForExitAsync(cancellationToken)` with a `CancellationTokenSource` armed for `timeout` as the deadline, and a separate polling `Task` for the watchdog condition; escalate with `process.Kill(entireProcessTree: true)` for `SIGTERM`'s role and a second, forceful `Kill` after a `Task.Delay` grace period if the first did not end it. Unlike `Process.terminationStatus` on an unexited process, .NET's `Process.ExitCode` throws an ordinary, catchable `InvalidOperationException` rather than an uncatchable exception, so the `didExit` guard this recipe requires (`status-sentinel-on-non-exit`) is still necessary but can be expressed with a normal `try`/`catch` instead of a pre-check.

## Design Decisions

**Decision**: The grace period between `SIGTERM` and `SIGKILL` (`terminationGrace`) is a hardcoded 2 seconds, not a parameter of `runToCompletion`.
**Rationale**: Per the constant's own doc comment, a tool that ignores `SIGTERM` is exactly the tool this second step exists for, and "two seconds is long enough for an honest cleanup handler and short enough that nobody notices." The same fixed 2 seconds also bounds the post-exit drain wait (`bounded-post-exit-drain-wait`), so every call to `runToCompletion` carries the same worst case: `timeout` plus up to two `terminationGrace` periods — the 120-second `VSIXArchive.expand` default plus this fixed grace is exactly the "124-second budget" its caller's doc comment (`VSIXInstaller.swift`) describes.
**Approved**: pending

**Decision**: `Outcome.status` is read from `process.terminationStatus` only when `didExit` is `true`; on a process that survived even `SIGKILL`, `status` is instead the `neverExited` sentinel (`-1`), and nothing further is attempted to force that process to exit.
**Rationale**: Per the doc comment on the guard, `Process.terminationStatus` is documented to raise `NSInvalidArgumentException` on a still-running process, and an Objective-C exception is not catchable from Swift — reading it unconditionally would turn the one scenario this code exists to survive (a tool stuck in an uninterruptible kernel wait, such as a read against a wedged network mount) into a crash instead of a reported failure. This is fail-fast, not fail-crash, by explicit design; the source makes no further attempt to reap or signal a process that has already survived `SIGKILL`; such a process is left running, the process-level counterpart of `abandoned-pipe-write-end`.
**Approved**: pending

**Decision**: `Outcome.timedOut` and `Outcome.aborted` are two distinct `Bool` fields rather than one combined "was terminated early" flag.
**Rationale**: Per the doc comment on `aborted`, the two "report differently: a timeout says how long the caller waited, an abort says which limit the caller set was reached" — `VSIXArchive.expand` relies on exactly this distinction to choose between throwing `expansionTimedOut` and `expansionTooLarge` (`VSIXArchive.swift`), two errors with different messages and different remediation for a user.
**Approved**: pending

**Decision**: The post-exit wait for each stream's drain-completion semaphore is bounded to `terminationGrace` rather than left unbounded.
**Rationale**: Per the comment at the wait site, both write ends are ordinarily already closed by the time this code runs, so the wait is "on an EOF that has already been posted" and the bound exists only "in case a grandchild inherited one of them." The source accepts a small, fixed risk of returning slightly truncated output in that specific, named case rather than risk `runToCompletion` itself hanging on a drain that has nothing left to signal it (see `abandoned-pipe-write-end` above).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

Notes: `separation-of-concerns` passes because `CommandRunner` owns exactly one concern — running one `Process` to completion, drained and bounded — while every policy choice (which tool to run, what `timeout` or `byteCeiling` to use, what to do with a timed-out or aborted `Outcome`) belongs to its callers, per `VSIXArchive.expand`'s use of it (`VSIXArchive.swift`). `unit-test-coverage` passes because `CommandRunnerTests.swift` carries thirteen tests with concrete, meaningful assertions covering draining, throwing, the timeout escalation, and every watchdog interaction, not just a happy path. `explicit-error-handling` is partial: the one error path the type itself can raise (`process.run()` throwing) is propagated unchanged with no swallowing, but `abandoned-pipe-write-end` means a bounded-out drain reports success indistinguishably from a complete one, which is a silent-in-the-return-value gap rather than a thrown or logged error. `timeout-handling` is partial for the same reason from the reliability angle: a normal timeout leaves the system in the well-defined state this recipe traces throughout (`Outcome.status`, cleared handlers, a killed process), but the one case where `terminationGrace`'s drain bound is actually exercised by a lingering grandchild is exactly the case this recipe cannot verify leaves `Outcome`'s buffers complete. `fault-tolerance` passes because the type explicitly guards the one input state that would otherwise crash it — reading `terminationStatus` from a process that never exited — rather than letting Foundation's uncatchable Objective-C exception propagate.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
