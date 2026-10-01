---
id: 705082e9-8fad-4c20-95a3-4cf843cc6b97
title: Command Runner
domain: agentictoolkit://cookbook/foundation/processes/command-runner
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A command runner drains a helper process's standard output and standard
  error while it runs and enforces a deadline or watchdog condition, escalating to
  a graceful termination signal then a forceful one.
platforms:
- swift
- macos
tags:
- process
- subprocess
- timeout
- watchdog
depends-on: []
related:
- agentictoolkit://cookbook/foundation/concurrency
references:
- packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Process/CommandRunnerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Command Runner

## Overview

This component is a namespace holding one entry point — a run-to-completion
operation — that runs a helper process to completion and returns everything
it wrote. It exists to close two ways a synchronous run-and-wait would
otherwise hang forever: an unread output pipe stops the child the moment
the kernel's fixed-size buffer (64 KB) fills, and a tool that never exits
holds the calling thread indefinitely. The run-to-completion operation
installs its own pipe on both the process's standard output and standard
error, drains each continuously as it is written, and waits against a
timeout deadline (or an optional watchdog condition that can end the run
earlier for a reason of the caller's own). A run that reaches its deadline
or its watchdog's condition is terminated — a graceful termination signal,
then a forceful one after a fixed grace period if the process ignores it
— and reported back as an outcome rather than discarded. This is the
whole-output, one-shot shape; a component meant to hold an ongoing
back-and-forth conversation with a child process is a different shape (see
the RPC recipe), which this file does not cover.

## Behavioral Requirements

- **stream-draining**: The run-to-completion operation MUST install a
  dedicated pipe on both the process's standard output and standard
  error, replacing anything a caller already set on either, and MUST
  begin draining each continuously before the process starts, so that
  output written by the process is read as it arrives rather than after
  the process exits.
- **concurrent-drain-collection**: Both streams' drained chunks MUST be
  appended into one lock-protected collector so that the two streams'
  arrival callbacks — which MAY be delivered concurrently with each other
  — never race or drop a chunk.
- **termination-handler-before-run**: A callback for the process's own
  exit MUST be assigned before the process is started, so the exit signal
  cannot be missed between starting the process and beginning to wait for
  it.
- **run-throw-propagation**: If starting the process throws, the
  run-to-completion operation MUST rethrow that error to the caller
  unchanged, and MUST first clear both pipes' drain callbacks and the
  exit callback; it MUST NOT wait, drain, or return an outcome on this
  path.
- **deadline-wait-without-watchdog**: When no watchdog is supplied, the
  run-to-completion operation MUST wait for the process to exit for up to
  the timeout's number of seconds and MUST mark the run as timed out if
  that wait itself expires without the process exiting.
- **watchdog-polling**: When a watchdog is supplied, the run-to-completion
  operation MUST poll its abort condition on the calling thread at an
  interval no larger than the watchdog's configured interval, and never
  larger than the deadline's remaining time, MUST mark the run as aborted
  and stop polling the first time that condition becomes true, and MUST
  mark the run as timed out instead — without polling the condition again
  — if the overall timeout deadline is reached first.
- **exit-during-poll-is-clean**: If the process exits during a watchdog
  poll interval, the run-to-completion operation MUST leave both the
  timed-out and aborted markers false.
- **terminate-on-timeout-or-abort**: The run-to-completion operation MUST
  send the graceful termination signal if and only if the run is marked
  timed out or aborted; it MUST NOT terminate a process that exited on its
  own.
- **sigkill-escalation**: After sending the graceful termination signal,
  the run-to-completion operation MUST wait up to the fixed termination
  grace period (2 seconds) for the process to exit, and if that wait
  itself expires, MUST send the forceful termination signal to the
  process and then wait up to another termination grace period for exit.
- **status-sentinel-on-non-exit**: The outcome's status MUST be a
  dedicated never-exited sentinel value (`-1`) when the process still has
  not exited after the forceful-termination wait, and MUST be the
  process's own exit status in every other case.
- **bounded-post-exit-drain-wait**: Once the process has exited, been
  killed, or given up on, the run-to-completion operation MUST bound each
  stream's drain-completion wait to the termination grace period rather
  than waiting unboundedly for an end-of-file signal that, in the
  ordinary case, has already arrived.
- **readability-handlers-cleared**: Both pipes' drain callbacks MUST be
  cleared before the run-to-completion operation returns, on every return
  path — the throw path and the normal return path.
- **outcome-buffers-always-populated**: The outcome's standard-output and
  standard-error buffers MUST be exactly the bytes collected for each
  stream, returned regardless of status, timed-out, or aborted state — a
  killed or timed-out run's partial output MUST still be returned, not
  discarded.
- **diagnostics-trimmed-utf8**: The outcome's diagnostics field MUST
  decode the collected standard-error bytes as UTF-8, MUST fall back to
  an empty string when the bytes are not valid UTF-8, and MUST trim
  leading and trailing whitespace and newline characters from the result.
- **timedout-aborted-mutually-exclusive**: For a single run, at most one
  of the outcome's timed-out and aborted markers MUST be true — the
  watchdog branch sets at most one of the two before ending its loop, and
  the non-watchdog branch can set only timed-out; no code path sets both.
- **watchdog-parameter-default**: The watchdog parameter MUST default to
  none when the caller omits it.
- **termination-grace-fixed**: The grace period between the graceful and
  forceful termination signals, and the bound on the post-exit drain
  wait, MUST be exactly 2 seconds and is not a value the run-to-completion
  operation exposes to callers.
- **outcome-and-watchdog-thread-safe**: The outcome value and the
  watchdog value MUST both be safe to share across concurrency-domain
  boundaries, so both MAY be passed freely between concurrent callers; the
  abort condition itself MUST be safe to invoke from a concurrent
  context, and the internal collector's own synchronization (not verified
  by any compiler) is what makes sharing it across the two streams'
  arrival callbacks correct.
- **watchdog-callback-serialized**: The watchdog's abort condition MUST be
  called only from the one thread running the polling loop inside the
  run-to-completion operation, and MUST NOT be called concurrently with
  itself.
- **synchronous-blocking-call**: The run-to-completion operation MUST run
  synchronously on the thread that calls it — it offers no cooperative
  suspension point of its own, only bounded waits — so a caller MUST
  expect that calling thread (including a UI thread) to be occupied for
  the entire run, up to the timeout plus as much as two termination grace
  periods.

## Appearance

Not applicable — this is a process-execution utility, not a visual component.

## States

Not applicable — this is a process-execution utility, not a visual component. Its one runtime state machine (waiting on the deadline or watchdog, then terminating, then escalating to a forceful termination signal) is captured under Behavioral Requirements above, not as a UI visual-state table.

## Accessibility

Not applicable — this is a process-execution utility, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-process-001 | stream-draining, outcome-buffers-always-populated | A command that streams 200,000 bytes to standard output, given a 30-second timeout. | Returns without hanging; not timed out; exit status 0; standard-output buffer is exactly 200,000 bytes. |
| foundation-process-002 | stream-draining, outcome-buffers-always-populated | The same shape, writing 200,000 bytes to standard error instead. | Not timed out; standard-error buffer is exactly 200,000 bytes. |
| foundation-process-003 | run-throw-propagation | A command naming a nonexistent executable, given a 30-second timeout. | The call throws; no outcome is produced. |
| foundation-process-004 | outcome-buffers-always-populated, diagnostics-trimmed-utf8 | A command that writes `"no such file\n"` to standard error and exits with status 3, given a 30-second timeout. | Exit status 3; diagnostics equal `"no such file"`; not timed out; standard-output buffer is empty. |
| foundation-process-005 | deadline-wait-without-watchdog, terminate-on-timeout-or-abort | A command that sleeps 30 seconds, given a 0.5-second timeout. | Marked timed out; the call returns in under 10 seconds, not 30. |
| foundation-process-006 | terminate-on-timeout-or-abort, sigkill-escalation | The same sleeping command and timeout. | Marked timed out; the process is no longer running once the call returns. |
| foundation-process-007 | sigkill-escalation, outcome-buffers-always-populated | A command that writes `"armed"`, then traps and ignores the graceful termination signal and loops forever, given a 1-second timeout. | Marked timed out; elapsed time under 8 seconds (1s timeout + 2s grace + 2s grace budget); diagnostics empty; standard-output buffer decodes to a string containing `"armed"`. |
| foundation-process-008 | watchdog-polling, timedout-aborted-mutually-exclusive | A command that sleeps 30 seconds, given a 30-second timeout and a watchdog polling every 0.1 seconds whose condition becomes true after its third check. | Marked aborted, not timed out; the call returns in under 10 seconds. |
| foundation-process-009 | timedout-aborted-mutually-exclusive | A command that sleeps 30 seconds, given a 0.5-second timeout and a watchdog polling every 0.1 seconds whose condition never becomes true. | Marked timed out, not aborted. |
| foundation-process-010 | watchdog-polling, outcome-buffers-always-populated | A command that writes `"hello"` and exits with status 3, given a 30-second timeout and a watchdog polling every 0.05 seconds whose condition never becomes true. | Not aborted, not timed out; exit status 3; standard-output buffer decodes to `"hello"`. |
| foundation-process-011 | exit-during-poll-is-clean | A command that exits immediately with status 0, given a 30-second timeout and a watchdog polling every 5 seconds whose condition is always true. | Not aborted; exit status 0. |
| foundation-process-012 | status-sentinel-on-non-exit, watchdog-parameter-default | A command that exits with status 3, given a 10-second timeout and no watchdog argument. | Not timed out; exit status 3; exit status differs from the never-exited sentinel. |
| foundation-process-013 | watchdog-polling, terminate-on-timeout-or-abort | An archive-unpacking caller that runs an extraction command through the run-to-completion operation with a 120-second timeout and a watchdog whose condition compares the unpacked size on disk against a byte ceiling (2 GiB default), against an archive engineered to expand past that ceiling. | The caller observes the run marked aborted, deletes the half-written destination, and reports an expansion-too-large failure; the same call site treats a timed-out run and a nonzero exit status as two further, distinct failure branches. |

## Edge Cases

- **Null / empty input**: A command that produces zero bytes on both streams MUST result in an empty standard-output buffer and an empty standard-error buffer (and therefore empty diagnostics) — collecting a stream nothing was ever written to falls back to an empty buffer; this is a MUST, with no special-case branch for "nothing was written." An empty or all-whitespace standard-error capture MUST still trim to an empty diagnostics string.
- **Boundary values**: A timeout of zero or negative MUST cause an immediate timeout — in the watchdog branch, the remaining-time check fails on the very first check, so the watchdog's abort condition MUST NOT be called even once; in the non-watchdog branch, the exit wait MUST report an immediate expiry for a non-positive timeout, per the same deadline arithmetic. A watchdog interval of zero MUST cause the polling loop to call the abort condition as fast as the underlying wait mechanism permits, with no minimum interval enforced.
- **Concurrent access**: Two or more concurrent runs, each against its own process, MUST run independently with no shared mutable state — the only static state is the fixed grace period and the never-exited sentinel, both immutable constants; every collector, wait primitive, and local flag (timed-out, aborted, has-exited) MUST be allocated fresh per run.
- **Error states**: If starting the process throws (the executable is missing, or this process lacks permission to execute it), that error MUST propagate to the caller unchanged, per run-throw-propagation, rather than being reported as a nonzero outcome status. A process that runs and exits with a nonzero status MUST NOT be surfaced as a thrown error at all — a tool that ran and failed is not an error here; it is an outcome with a non-zero status — the caller is required to inspect the outcome's status itself.
- **Offline / disconnected state**: Not applicable — this component performs no network access of its own; it only runs and drains an arbitrary process. If the wrapped process is itself a network client, a lost connection would surface only as whatever exit status or standard-error bytes that tool produces, through the Error States path above — this component has no offline-specific behavior of its own.
- **Cancellation**: The run-to-completion operation offers no cancellation token and observes no cooperative cancellation signal, because it is fully synchronous (synchronous-blocking-call) — the only ways to end a run before the process exits on its own are the timeout deadline and an optional watchdog's abort condition. A caller with no watchdog MUST wait the full timeout before the process is even asked to terminate; a caller that needs to cancel a run for a reason of its own MUST express that reason as a watchdog condition, since none is built in.
- **abandoned-pipe-write-end**: When a grandchild process has inherited a pipe's write end and is still alive past the termination grace period after the parent process has exited or been killed, the post-exit drain wait gives up at that bound, and the outcome's standard-output/standard-error buffers hold only what was drained by then; the outcome carries no field distinguishing a complete capture from one cut short by that bound.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| process (parameter to the run-to-completion operation) | opaque process handle | none — required | The already-configured process to run; its standard output and standard error are overwritten with this component's own pipes. |
| timeout (parameter to the run-to-completion operation) | number (seconds) | none — required | How long the run is given before it is terminated and reported as timed out. |
| watchdog (parameter to the run-to-completion operation) | optional watchdog value | none | An optional condition, polled while the process runs, that ends the run early for a reason other than the clock. |
| interval (watchdog parameter) | number (seconds) | none — required | How often the abort condition is polled; the run ends within one interval of the condition becoming true. |
| abort condition (watchdog parameter) | callback returning true/false | none — required | Called on the waiting thread, never concurrently with itself; the first true ends the run. |

The fixed grace period (2 seconds — the wait between the graceful and forceful termination signals, and the bound on the post-exit drain wait) is a private, fixed constant; it is not exposed as a parameter, environment variable, or settings key anywhere.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation destination — it runs and drains an operating-system process, not application navigation.

## Localization

Not applicable: this component contains no user-facing string literal of its own; every string it produces (the outcome's diagnostics) is whatever bytes the wrapped process happened to write to its own standard error, not text this component authors.

## Accessibility Options

Not applicable: this component presents no UI, so it responds to no platform display-accessibility setting.

## Feature Flags

Not applicable: this component contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: this component contains no analytics or event-tracking call.

## Privacy

Not applicable: this component defines and stores no data of its own — it relays whatever bytes the process's standard output/standard error carry back to its caller, in memory, for the duration of one call, and persists nothing to disk. Whether those bytes are privacy-sensitive (a credential a wrapped tool happened to print, for instance) is a property of the process the caller chose to run, not of this component, which inspects none of the content it drains.

## Logging

Not applicable: this component contains no logging call of any kind — a caller that wants a failed run logged MUST do so itself from the returned outcome.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares as `platform: macOS` only — `Foundation.Process` has no iOS/tvOS/watchOS counterpart, so this type does not port to those platforms at all. The file imports only `Foundation`; nothing in it is SwiftUI-specific.
- **Compose**: Port with `java.lang.ProcessBuilder`/`Process`, reading `inputStream`/`errorStream` on separate `Dispatchers.IO` coroutines (the analogue of the readability handler) into shared, mutex-guarded buffers (the collector analogue). Use `withTimeoutOrNull(timeoutMillis) { process.awaitExit() }` for the deadline and a second coroutine polling the watchdog condition on its own interval; escalate with `process.destroy()` then `process.destroyForcibly()` after a fixed grace delay, mirroring the graceful-then-forceful termination sequence.
- **React/Web**: Port with Node's `child_process.spawn`, reading `stdout`/`stderr` via their `'data'` events into accumulator buffers — Node's own stream backpressure handling makes the 64 KB deadlock this type exists to avoid a non-issue as long as those events are subscribed to before the process starts. Use one `setTimeout` for the deadline and, when a watchdog is needed, a `setInterval` that clears itself and sends the graceful termination signal the first time its condition is true; escalate to the forceful termination signal from a second `setTimeout` armed at the same moment, mirroring the grace period.
- **AppKit / UIKit**: Identical to the SwiftUI note above — this component is UI-framework-agnostic; only the macOS-only availability of the underlying process type applies, never the choice of UI framework above it. The source is a case-less `public enum` namespace (`CommandRunner`) holding one static entry point, `runToCompletion(_:timeout:watchdog:)`, that wraps a `Foundation.Process`. It installs a `Pipe` on `process.standardOutput` and `process.standardError` and drains each via a `readabilityHandler` closure assigned before `process.run()`; `process.terminationHandler` is likewise assigned before `run()` is called. Both streams' drained chunks feed one `Collector` type guarded by an `NSLock`, declared `@unchecked Sendable` because Foundation delivers both streams' readability callbacks on its own queue, off the calling thread — the type's own lock, not the compiler, is what makes that claim correct (**outcome-and-watchdog-thread-safe**). `Outcome` is a `Sendable`, `Equatable` struct; `Watchdog` is a `Sendable` struct whose `shouldAbort` closure is typed `@Sendable`. Waiting uses `DispatchSemaphore.wait(timeout:)` throughout — for the non-watchdog deadline, for each watchdog poll interval (`min(watchdog.interval, remaining)`), and for the post-exit drain bound — which is what makes `runToCompletion` a fully synchronous, blocking call with no `async` and no cooperative suspension point (**synchronous-blocking-call**). Escalation sends `SIGTERM` via `process.terminate()`, then, after `terminationGrace` (a fixed 2-second `let` constant) elapses without exit, sends `SIGKILL` directly to `process.processIdentifier`. `Outcome.status` reads `process.terminationStatus` only when a `didExit` flag is true, because that property raises an uncatchable `NSInvalidArgumentException` on a still-running process; when `didExit` is false, `status` is instead `CommandRunner.neverExited` (`-1`) (**status-sentinel-on-non-exit** — see also Design Decisions). It is called today from throwing, synchronous Swift call sites (an archive-expansion caller) that are themselves wrapped in a dedicated blocking-work helper (see Design Decisions) to keep the block off the Swift concurrency cooperative thread pool.
- **WinUI 3**: Port with `System.Diagnostics.Process`/`ProcessStartInfo` (`RedirectStandardOutput = true`, `RedirectStandardError = true`), draining via the `OutputDataReceived`/`ErrorDataReceived` events (started with `BeginOutputReadLine`/`BeginErrorReadLine`) in place of the pipe + readability-handler pair — .NET's asynchronous line-based reads are the same "drain while it writes" answer to the pipe-buffer deadlock. Use `await process.WaitForExitAsync(cancellationToken)` with a `CancellationTokenSource` armed for `timeout` as the deadline, and a separate polling `Task` for the watchdog condition; escalate with `process.Kill(entireProcessTree: true)` for the graceful signal's role and a second, forceful `Kill` after a `Task.Delay` grace period if the first did not end it. Unlike reading the exit status of an unexited process here, .NET's `Process.ExitCode` throws an ordinary, catchable `InvalidOperationException` rather than an uncatchable exception, so the non-exit guard this recipe requires (status-sentinel-on-non-exit) is still necessary but can be expressed with a normal `try`/`catch` instead of a pre-check.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Process/CommandRunner.swift` |

## Design Decisions

**Decision**: The grace period between the graceful and forceful termination signals (`terminationGrace`) is a hardcoded 2 seconds, not a parameter of the run-to-completion operation.
**Rationale** (Swift implementation): Per the constant's own doc comment, a tool that ignores the graceful signal is exactly the tool this second step exists for, and "two seconds is long enough for an honest cleanup handler and short enough that nobody notices." The same fixed 2 seconds also bounds the post-exit drain wait (bounded-post-exit-drain-wait), so every run carries the same worst case: timeout plus up to two termination grace periods — a 120-second archive-expansion default plus this fixed grace is exactly the "124-second budget" its caller's own doc comment describes.
**Approved**: pending

**Decision**: The outcome's status is read from the process's own exit status only when a `didExit` flag is true; on a process that survived even the forceful termination signal, status is instead the never-exited sentinel (`-1`), and nothing further is attempted to force that process to exit.
**Rationale** (Swift implementation): Per the doc comment on the guard, reading a still-running process's termination status is documented to raise an uncatchable Objective-C exception — reading it unconditionally would turn the one scenario this code exists to survive (a tool stuck in an uninterruptible kernel wait, such as a read against a wedged network mount) into a crash instead of a reported failure. This is fail-fast, not fail-crash, by explicit design; the source makes no further attempt to reap or signal a process that has already survived the forceful termination signal; such a process is left running, the process-level counterpart of abandoned-pipe-write-end.
**Approved**: pending

**Decision**: The outcome's timed-out and aborted markers are two distinct fields rather than one combined "was terminated early" flag.
**Rationale**: Per the doc comment on the aborted field, the two "report differently: a timeout says how long the caller waited, an abort says which limit the caller set was reached" — the archive-unpacking caller relies on exactly this distinction to choose between throwing an expansion-timed-out error and an expansion-too-large error, two errors with different messages and different remediation for a user.
**Approved**: pending

**Decision**: The post-exit wait for each stream's drain-completion signal is bounded to the termination grace period rather than left unbounded.
**Rationale** (Swift implementation): Per the comment at the wait site, both write ends are ordinarily already closed by the time this code runs, so the wait is "on an end-of-file that has already been posted" and the bound exists only "in case a grandchild inherited one of them." The source accepts a small, fixed risk of returning slightly truncated output in that specific, named case rather than risk the run-to-completion operation itself hanging on a drain that has nothing left to signal it (see abandoned-pipe-write-end above).
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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/processes/. |
