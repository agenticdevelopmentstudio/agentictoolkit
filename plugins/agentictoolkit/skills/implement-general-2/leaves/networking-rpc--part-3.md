<!-- leaf: implement-general-2/networking-rpc--part-3 · source: networking-rpc.md -->

# Networking RPC — continued (part 3)

**Rules** (cite as `implement-general-2/networking-rpc--part-3#<slug>`):

- `exit-status-no-invented-value` MUST
- `exit-status-multi-waiter-independence` MUST
- `termination-sequence` MUST
- `termination-idempotent` MUST
- `termination-uncancellable` MUST
- `termination-preserves-trailing-frame-on-natural-eof` MUST
- `termination-suppresses-flush-on-forced-teardown` MUST
- `termination-signal-scope` MUST
- `run-forces-unframed` MUST
- `run-captures-full-output` MUST
- `run-tolerates-exited-case` MUST
- `run-budget-enforcement` MUST
- `run-terminates-on-every-path` MUST
- `run-result-shape` MUST
- `run-does-not-interpret-exit-status` MUST
- `decoder-feed-chunk-sized-input` SHOULD
- `budget-race-not-scoped-join` MUST
- `budget-cancels-not-awaits-loser` MUST
- `budget-caller-cancellation-propagates` MUST
- `budget-nan-starts-no-timer` MUST
- `budget-ceiling-starts-no-timer` MUST
- `budget-nonpositive-expires-immediately` MUST

- **exit-status-no-invented-value**: `waitUntilExit()` MUST throw `ChannelError.notLaunched` when called on a channel that was never launched, and MUST throw `CancellationError` when the awaiting task is cancelled before the child exits; it MUST NOT return `0`, or any other value, for either case.
- **exit-status-multi-waiter-independence**: Cancelling one caller's `waitUntilExit()` call MUST leave every other concurrent caller's `waitUntilExit()` call on the same channel parked and unaffected, and MUST NOT touch the child process.
- **termination-sequence**: `terminate()` MUST perform, in order: stop the stdin writer, cancelling any write in flight; send SIGTERM to the child if it is still running; wait up to 2.0 seconds (`SubprocessChannel.terminationGraceSeconds`) for it to exit; send SIGKILL if it is still running after that wait; stop both stdout/stderr readers (the only point at which their descriptors close); then wait up to 0.5 seconds (`SubprocessChannel.messagePumpDrainGraceSeconds`) for the stdout message pump to finish flushing and finishing the message stream.
- **termination-idempotent**: `terminate()` MUST be idempotent: a channel on which it has already run, or on which it is already running, MUST let every caller — concurrent or subsequent — observe the same completed teardown rather than starting a second one.
- **termination-uncancellable**: The work `terminate()` performs MUST run in a task that does not inherit the calling task's cancellation, so a caller that is itself cancelled while awaiting `terminate()` MUST NOT cause the child to be abandoned mid-teardown.
- **termination-preserves-trailing-frame-on-natural-eof**: When the child's stdout reaches end-of-file on its own — not because `terminate()` tore the descriptor down — the message pump MUST flush `MessageFramingDecoder.finish()` and yield any frame it returns before finishing the message stream.
- **termination-suppresses-flush-on-forced-teardown**: When `terminate()` itself ends the child's stdout (a forced teardown), the message pump MUST finish the message stream without calling `MessageFramingDecoder.finish()`, so a partial `.newlineDelimited` line is never delivered as a whole frame and a `.contentLength` shutdown is never reported as a `truncatedMessage` transport error.
- **termination-signal-scope**: `terminate()`'s SIGTERM and SIGKILL MUST each target only the direct child process ID, never a process group; a grandchild the child itself spawned and backgrounds MUST NOT receive either signal from this method — a caller that needs grandchildren reaped MUST arrange it in the command it launches, since `Process` exposes no process-group spawn option for this component to use instead.
- **run-forces-unframed**: `SubprocessChannel.run(_:budget:)` MUST set `configuration.framing` to `.unframed` before constructing its `SubprocessChannel`, regardless of the framing value supplied in the configuration passed in.
- **run-captures-full-output**: `run(_:budget:)` MUST launch the channel, close its stdin immediately, and concatenate every chunk yielded by `channel.messages()` in arrival order to form `RunResult.standardOutput`, reproducing the child's raw stdout byte-for-byte.
- **run-tolerates-exited-case**: `run(_:budget:)` MUST catch a `ChannelError.exited` thrown while draining `channel.messages()` and treat it as a normal end of that iteration rather than propagating it, tolerating a case `messages()` does not currently throw but could in the future; every other `ChannelError` thrown from that drain MUST propagate.
- **run-budget-enforcement**: `run(_:budget:)` MUST wrap its launch, drain, and exit-wait sequence in `withWallClockBudget(budget:)`, so a `WallClockBudgetExceeded` thrown by that budget propagates from `run(_:budget:)` unchanged.
- **run-terminates-on-every-path**: `run(_:budget:)` MUST call `channel.terminate()` in a `catch` around the whole `withWallClockBudget(budget:)` call, on any thrown error including `WallClockBudgetExceeded`, before rethrowing.
- **run-result-shape**: On success, `run(_:budget:)` MUST return a `RunResult` whose `standardError` comes from `channel.standardErrorText()`, whose `exitStatus` comes from `channel.waitUntilExit()`, and whose `duration` is the wall-clock time elapsed between just before the run began and the moment `RunResult` is constructed.
- **run-does-not-interpret-exit-status**: `run(_:budget:)` MUST NOT throw on a non-zero `RunResult.exitStatus`; callers MAY treat a non-zero exit as success or failure at their own discretion, since `SubprocessChannel` itself defines no notion of a non-zero exit being an error.
- **decoder-feed-chunk-sized-input**: Callers SHOULD feed `MessageFramingDecoder.consume(_:)` chunks of realistic size — for example via `read(upToCount:)` — rather than one byte at a time; per-byte feeding does not change the frames produced, but it defeats the decoder's scan-cursor optimization and turns every call into mostly wasted overhead.
- **budget-race-not-scoped-join**: `withWallClockBudget(_:_:)` MUST implement its race between the operation and a timer as two unstructured tasks resumed through a single continuation, resumed exactly once, and MUST NOT use `withThrowingTaskGroup`, whose implicit join on scope exit would await the losing task before a timeout could ever be observed.
- **budget-cancels-not-awaits-loser**: When the timer wins the race, `withWallClockBudget(_:_:)` MUST cancel the operation task and throw `WallClockBudgetExceeded(seconds:)` immediately, without awaiting that task's completion.
- **budget-caller-cancellation-propagates**: Cancelling the task awaiting `withWallClockBudget(_:_:)` MUST cancel both the operation task and the timer task and MUST rethrow `CancellationError` promptly, rather than waiting out either one.
- **budget-nan-starts-no-timer**: A `seconds` value of `.nan` MUST start no timer — the operation runs to completion or to the caller's own cancellation, unbounded by this call — rather than being treated as a zero-second budget.
- **budget-ceiling-starts-no-timer**: A `seconds` value at or above 31,536,000 (60 × 60 × 24 × 365, one year), including `.infinity` and `.greatestFiniteMagnitude`, MUST start no timer.
- **budget-nonpositive-expires-immediately**: A `seconds` value at or below `0` (including `-.infinity`) MUST be treated as an immediate expiry — a zero-nanosecond sleep — not as "no budget."
- **descriptor-close-failure-signal**: NEEDS REVIEW: Not implemented in source. `HandleCloser.close()` (`SubprocessChannel.swift`) calls `try? handle.close()`, and each `DispatchIO` cleanup handler that invokes it (on both the stdin writer and the stdout/stderr readers) discards the error code `DispatchIO` itself reports to that handler; a descriptor that fails to close (for example a double close, or `EBADF`) is therefore never logged, thrown, or otherwise surfaced to any caller, and no test in `SubprocessChannelTests.swift` exercises a failing close to say what the intended behavior is.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `executableURL` | `URL` | none — required | `SubprocessChannel.Configuration.executableURL`; the child executable to launch. |
| `arguments` | `[String]` | `[]` | Arguments passed to the child. |
| `environment` | `[String: String]` | `[:]` | Environment variables applied per `environmentPolicy`. |
| `environmentPolicy` | `SubprocessChannel.EnvironmentPolicy` | `.replace` | `.replace` or `.mergeOverParent`; see `environment-replace-policy`/`environment-merge-policy`. |
| `framing` | `MessageFraming` | `.newlineDelimited` | How the child's stdout is split into frames; ignored by `run(_:budget:)`, which forces `.unframed`. |
| `currentDirectoryURL` | `URL?` | `nil` (inherit the parent's) | The child's working directory. |
| `budget` (parameter to `run(_:budget:)`) | `TimeInterval` | none — required | The wall-clock bound for the whole one-shot run. |
| `MessageFramingDecoder.maximumFrameBytes` | `Int` (public static constant) | `16777216` (16 MiB) | Per-frame buffering cap for `.newlineDelimited`/`.contentLength`. |
| `SubprocessChannel.readChunkSize` (private static constant) | `Int` | `65536` (64 KiB) | `DispatchIO` high-water mark for both the stdout pump and the stderr drain. |
| `SubprocessChannel.terminationGraceSeconds` (private static constant) | `TimeInterval` | `2.0` | SIGTERM grace period before `terminate()` escalates to SIGKILL. |
| `SubprocessChannel.standardErrorDrainGraceSeconds` (private static constant) | `TimeInterval` | `0.5` | Bounded wait for the stderr drain in `standardErrorText()`/`standardErrorData()`. |
| `SubprocessChannel.messagePumpDrainGraceSeconds` (private static constant) | `TimeInterval` | `0.5` | Bounded wait, inside `terminate()`, for the stdout pump to flush and finish. |
| `SubprocessChannel.maximumStandardErrorBytes` (private static constant) | `Int` | `1048576` (1 MiB) | Tail-retaining cap on the buffered stderr capture. |
| `maximumWallClockBudgetSeconds` (file-private constant, `WallClockBudget.swift`) | `TimeInterval` | `31536000` (one year) | The ceiling above which a budget is treated as "no deadline" rather than converted to a trapping nanosecond sleep. |

