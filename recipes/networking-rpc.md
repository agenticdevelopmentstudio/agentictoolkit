---
id: 2dd6133a-1d6c-4ee5-9e37-308a11966433
title: Networking RPC
domain: agentictoolkit://recipes/networking-rpc
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Frames a byte stream into discrete messages, drives a child process over
  stdin/stdout/stderr, and races any operation against a wall-clock budget.
platforms:
- swift
- macos
tags:
- rpc
- subprocess
- framing
- concurrency
- networking
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-plugin-transport
references: []
approved-by: ''
approved-date: ''
---

# Networking RPC

## Overview

Networking RPC is the non-UI logic root, under `packages/apple/AgenticToolkit/Core/RPC/`, for talking to a child process as if it were an RPC peer. It has four parts:

- `MessageFraming` — the `Sendable` enum naming how a byte stream is split into discrete messages: `.newlineDelimited` (a frame is the byte-exact slice up to and including its trailing `0x0A`), `.contentLength` (a frame is the body only, with its `Content-Length: <n>\r\n...\r\n\r\n` header consumed and discarded), and `.unframed` (a stream with no message boundaries at all, where a "frame" is whatever chunk of bytes arrived). Its `frame(_:)` method encodes a message for a given case.
- `MessageFramingDecoder` — the incremental, mutating `struct` that turns arbitrary byte chunks (never aligned to message boundaries) into complete frames, one call to `consume(_:)` at a time, and flushes any end-of-stream remainder via `finish()`. It caps any single buffered frame at 16 MiB and recovers from a peer that exceeds that cap without losing frames already completed in the same call or letting the rejected frame's own bytes resynchronize the stream.
- `SubprocessChannel` — the `actor` that spawns a child process (`Process`, three `Pipe`s) and exposes its stdout as an `AsyncThrowingStream` of frames decoded by a `MessageFramingDecoder`, its stdin as a place to `send(_:)`/`sendRaw(_:)` bytes, and its stderr as a continuously drained, capped buffer. It owns launch, environment policy, and a `terminate()` sequence (SIGTERM, then SIGKILL, then reader teardown) that distinguishes a child ending its own output from one this method killed.
- `SubprocessChannel.run(_:budget:)` and `withWallClockBudget(_:_:)` (`SubprocessChannel+Run.swift`, `WallClockBudget.swift`) — a one-shot helper that launches a channel, drains all of stdout as `.unframed` regardless of the caller's configured framing, and returns a `RunResult`; and the general wall-clock race it (and `PluginTransport`, see `related`) uses to bound any `async` operation, cancelling — never awaiting — the loser.

This is the one shared replacement, per `SubprocessChannel.swift`'s own doc comment, for what had been several independent `Process` + three-`Pipe` implementations in the codebase.

## Behavioral Requirements

- **framing-cases**: `MessageFraming` MUST support exactly three cases — `.newlineDelimited`, `.contentLength`, `.unframed` — each defining a distinct encode/decode contract.
- **newline-frame-encoding**: `MessageFraming.frame(_:)` for `.newlineDelimited` MUST append a single `0x0A` byte to `message`, unless `message` already ends in `0x0A`, in which case it MUST return `message` unchanged.
- **content-length-frame-encoding**: `frame(_:)` for `.contentLength` MUST prepend `Content-Length: \(message.count)\r\n\r\n` in ASCII to `message`, with no other header.
- **unframed-frame-encoding**: `frame(_:)` for `.unframed` MUST return `message` unchanged, with no envelope added.
- **frame-boundary-completeness**: `MessageFramingDecoder.consume(_:)` MUST return every frame the buffer newly completes, in arrival order, and MUST NOT return a partial frame.
- **newline-frame-shape**: For `.newlineDelimited`, each decoded frame MUST be the byte-exact slice up to and including its trailing `0x0A`, preserving that byte rather than stripping it.
- **content-length-frame-shape**: For `.contentLength`, each decoded frame MUST be the body only; the `Content-Length: <n>\r\n...\r\n\r\n` header MUST be consumed and discarded, never included in the frame.
- **unframed-decoding**: For `.unframed`, `consume(_:)` MUST hand back each non-empty chunk as its own frame, unmodified, the moment it arrives, and MUST return an empty array for an empty chunk; no bytes are ever buffered for this case, and the frame-size cap below MUST NOT apply to it.
- **content-length-header-parsed-once**: For `.contentLength`, the header MUST be parsed exactly once, at the moment its `\r\n\r\n` terminator is seen, and MUST NOT be reparsed while the body is still arriving in later chunks.
- **content-length-header-line-parsing**: Each header line MUST be split on its first `:` into a key and a trimmed value; a header key MUST be matched case-insensitively against `Content-Length`; any other header (for example `Content-Type`) MUST be tolerated and discarded without error.
- **content-length-malformed-header**: Header parsing MUST throw `MessageFramingError.malformedHeader` when a header line is not valid UTF-8, when a header line has no `:` separator, or when the `Content-Length` value is not a non-negative integer.
- **content-length-missing-header**: Header parsing MUST throw `MessageFramingError.missingContentLength` when no header line's key matches `Content-Length`.
- **frame-size-cap**: For `.newlineDelimited` and `.contentLength`, `MessageFramingDecoder` MUST enforce a 16,777,216-byte (16 MiB) cap, `MessageFramingDecoder.maximumFrameBytes`, on any single frame's buffered bytes.
- **cap-violation-preserves-prior-frames**: When a single `consume(_:)` call's chunk both completes one or more valid frames and then begins an oversized one, `consume(_:)` MUST return the completed frames from that call and MUST defer the `MessageFramingError.frameSizeExceeded` throw to the decoder's next call, rather than losing the valid frames to the same throw.
- **newline-cap-recovery**: When a `.newlineDelimited` buffer exceeds the cap, the decoder MUST discard every byte up to and including the next `0x0A` it receives (dropping the oversized line in full) before resuming normal framing, and MUST NOT ever deliver that oversized line as a frame.
- **content-length-cap-recovery**: When a `.contentLength` header declares a body length greater than the cap, the decoder MUST discard exactly that many body bytes before resuming header scanning, so a `Content-Length`-shaped line inside the rejected body cannot resynchronize the stream onto a boundary the peer chose.
- **finish-newline-remainder**: `MessageFramingDecoder.finish()` for `.newlineDelimited` MUST return the buffer's trailing unterminated remainder as one final frame when the buffer is non-empty, and MUST return an empty array when the buffer is empty.
- **finish-content-length-truncated**: `finish()` for `.contentLength` MUST throw `MessageFramingError.truncatedMessage(expected:received:)` when a header has already been parsed and stripped but the buffer holds fewer than the declared number of body bytes.
- **finish-content-length-malformed**: `finish()` for `.contentLength` MUST throw `MessageFramingError.malformedHeader` when the buffer is non-empty but no complete header was ever parsed.
- **finish-unframed-noop**: `finish()` for `.unframed` MUST always return an empty array and MUST NOT throw, because `.unframed` never holds anything back.
- **finish-during-discard**: `finish()` called while the decoder is mid-discard (skipping an over-cap line or the remainder of an over-cap body) MUST return an empty array and MUST clear all buffered and discard state, rather than returning a fragment of the rejected frame or reporting its unarrived bytes as a truncated message.
- **decoder-value-type-single-owner**: `MessageFramingDecoder` MUST be a Swift `struct` with mutating methods; a channel's message pump MUST create and hold exactly one instance per stream, consumed only from that pump's own task, never shared concurrently across tasks.
- **actor-serializes-channel**: `SubprocessChannel` MUST be declared as a Swift `actor`, so every actor-isolated method call against one instance (`launch`, `messages`, `send`, `sendRaw`, `closeInput`, `standardErrorText`, `standardErrorData`, `terminate`) is serialized by that actor; `waitUntilExit` MUST be `nonisolated` so awaiting it never blocks the actor for the life of a long-running child.
- **configuration-and-result-sendable**: `SubprocessChannel.Configuration` and `SubprocessChannel.RunResult` MUST be declared `Sendable` value types, so a caller MAY construct and pass either freely across concurrency domains.
- **single-stdout-reader**: `SubprocessChannel.messages()` MUST throw `ChannelError.notLaunched` if called before `launch()` has succeeded, and MUST throw `ChannelError.alreadyConsumed` if called a second time on the same channel; a channel MUST expose exactly one reader over the child's stdout.
- **launch-idempotency**: `launch()` MUST throw `ChannelError.alreadyLaunched` if called on a channel that has already launched successfully.
- **launch-sigpipe-suppression**: `launch()` MUST disable `SIGPIPE` via `fcntl`'s `F_SETNOSIGPIPE`, scoped specifically to the child's stdin write descriptor, before calling `process.run()`, and MUST throw `ChannelError.launchFailed` without spawning the process if that `fcntl` call fails.
- **environment-replace-policy**: Under `EnvironmentPolicy.replace`, a non-empty `configuration.environment` MUST become the child's entire environment; an empty `configuration.environment` MUST leave the child inheriting the parent process's environment untouched.
- **environment-merge-policy**: Under `EnvironmentPolicy.mergeOverParent`, a non-empty `configuration.environment` MUST be merged over `ProcessInfo.processInfo.environment`, with `configuration.environment`'s values winning on key collision; an empty `configuration.environment` MUST leave that merge a no-op.
- **send-applies-framing**: `send(_:)` MUST frame `message` via `configuration.framing.frame(_:)` before writing it to the child's stdin.
- **send-raw-unframed**: `sendRaw(_:)` MUST write `bytes` to the child's stdin exactly as given, with no delimiter or header added, regardless of `configuration.framing`.
- **send-call-order-preserved**: Two or more concurrent calls to `send(_:)`/`sendRaw(_:)` on the same channel MUST reach the child's stdin descriptor in the order those calls were made, because each call's write is submitted synchronously, while the actor is held, before the caller suspends to await completion.
- **write-after-close-throws**: A `sendRaw(_:)` (or `send(_:)`) call made after the child's stdin has been closed (by `closeInput()` or by `terminate()`) MUST throw `ChannelError.inputClosed`; a write attempted after the child has exited MUST throw a Swift error derived from `EPIPE` rather than raising the `SIGPIPE` signal, because `launch()` has disabled `SIGPIPE` on that one descriptor.
- **close-input-orderly**: `closeInput()` MUST flush every byte already submitted via a prior `sendRaw(_:)`/`send(_:)` call to the child before releasing the stdin descriptor, so the child observes those bytes and only then EOF.
- **stderr-continuous-drain**: `SubprocessChannel` MUST drain the child's stderr continuously on its own task, independent of both the actor and the stdout message pump, rather than reading it only once at exit.
- **stderr-tail-cap**: The accumulated stderr buffer MUST be capped at 1,048,576 bytes (1 MiB), `SubprocessChannel.maximumStandardErrorBytes`; once exceeded, the buffer MUST retain the most recently written bytes (the tail) and discard the oldest, and MUST record that truncation occurred.
- **stderr-text-decoding**: `standardErrorText()` MUST decode the buffered stderr bytes as UTF-8, and MUST fall back to Latin-1 decoding (which accepts every byte) when the buffer is not valid UTF-8, rather than returning an empty string.
- **stderr-text-diagnostic-prefixes**: `standardErrorText()` MUST prepend `"[stderr truncated to the last 1048576 bytes]\n"` when the tail cap trimmed the buffer, and MUST prepend `"[stderr capture incomplete: the drain did not finish within 0.5s]\n"` when the bounded drain wait lapsed before the drain task finished; either, neither, or both prefixes MAY appear together.
- **stderr-data-raw**: `standardErrorData()` MUST return the buffered stderr bytes exactly as captured, with no decoding, no re-encoding, and no diagnostic prefix of any kind.
- **stderr-drain-bounded-wait**: `standardErrorText()` and `standardErrorData()` MUST wait no more than 0.5 seconds (`SubprocessChannel.standardErrorDrainGraceSeconds`) for the stderr drain task to finish before answering with whatever has been buffered so far; expiry of that wait MUST NOT be treated as an error.
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

## Appearance

Not applicable — this is a subprocess/RPC networking engine (byte-stream framing, process I/O, and wall-clock timeout racing), not a visual component.

## States

Not applicable — this is a subprocess/RPC networking engine, not a visual component; its runtime state machines (a channel's launched/consuming/terminated lifecycle, and a decoder's buffering/discarding lifecycle) are captured under Behavioral Requirements above, not in a UI visual-state table.

## Accessibility

Not applicable — this is a subprocess/RPC networking engine with no user interface of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| networking-rpc-001 | newline-frame-shape, frame-boundary-completeness | Three newline-terminated lines fed as one chunk to a `.newlineDelimited` decoder (`MessageFramingTests.newlineThreeCompleteLinesYieldThreeFrames`). | `consume(_:)` returns exactly three frames, each ending in its own `0x0A`, in the order the lines appeared. |
| networking-rpc-002 | frame-boundary-completeness | A single message's bytes fed across three separate `consume(_:)` calls, split mid-word, under `.newlineDelimited` (`newlineMessageSplitAcrossThreeChunks`). | The first two calls return no frames; the third call, which delivers the `0x0A`, returns exactly one frame containing the complete message. |
| networking-rpc-003 | finish-newline-remainder | A `.newlineDelimited` decoder fed a message with no trailing newline, then `finish()` called twice (`newlineFinishEmitsRemainderOnce`). | The first `finish()` returns the unterminated remainder as one frame; the second `finish()` returns an empty array. |
| networking-rpc-004 | content-length-frame-shape | A well-formed `Content-Length: <n>\r\n\r\n<body>` message fed to a `.contentLength` decoder (`contentLengthWellFormedMessageDecodesToBodyOnly`). | `consume(_:)` returns exactly one frame equal to `<body>`, with no header bytes present. |
| networking-rpc-005 | content-length-header-parsed-once, content-length-header-line-parsing | An extra, non-Content-Length header line appears before or after the `Content-Length` line, in either order (`contentLengthExtraHeadersInEitherOrderStillParse`, parameterized). | Both orderings decode to the same body frame; the extra header is tolerated and discarded. |
| networking-rpc-006 | content-length-frame-shape | A body containing multi-byte UTF-8 characters, with `Content-Length` declared in bytes rather than characters (`contentLengthCountsBytesNotCharacters`). | The decoded frame's byte length equals the declared `Content-Length` value, not the character count. |
| networking-rpc-007 | finish-content-length-truncated | A `.contentLength` decoder given a header declaring a body longer than what has arrived, then `finish()` called (`contentLengthFinishWithPartialBodyThrowsTruncatedMessage`). | `finish()` throws `MessageFramingError.truncatedMessage(expected:received:)` carrying the declared and actually-received byte counts. |
| networking-rpc-008 | content-length-missing-header | A header block containing `\r\n\r\n` but no `Content-Length` line (`contentLengthHeaderWithNoContentLengthThrowsMissingContentLength`). | `consume(_:)` throws `MessageFramingError.missingContentLength`. |
| networking-rpc-009 | unframed-decoding | Three chunks fed to a `.unframed` decoder, one of which is empty (`unframedChunksPassStraightThrough`, `unframedEmptyChunkYieldsNoFrame`). | Each non-empty chunk is returned as its own frame, byte-exactly and in order; the empty chunk yields no frame. |
| networking-rpc-010 | frame-size-cap, unframed-decoding | A byte sequence larger than `maximumFrameBytes` with no delimiter anywhere in it, fed to a `.unframed` decoder (`unframedDelimiterlessOutputPastTheCapDecodes`). | The oversized bytes decode successfully with no thrown error, because the 16 MiB cap does not apply to `.unframed`. |
| networking-rpc-011 | cap-violation-preserves-prior-frames, newline-cap-recovery | A chunk containing one complete newline-terminated frame immediately followed by the start of an oversized, still-unterminated line (`newlineOversizedTrailerDoesNotSwallowPriorCompleteFrames`). | That `consume(_:)` call returns the complete frame; the decoder's very next call throws `frameSizeExceeded`, and the oversized line is never delivered as a frame. |
| networking-rpc-012 | content-length-cap-recovery | A `Content-Length` header declares a body above the cap, and the rejected body itself contains a byte sequence shaped like a `Content-Length` header line (`contentLengthOverCapBodyIsDiscardedNotReframed`). | The embedded look-alike header inside the discarded body is never parsed as a new frame boundary; framing resumes correctly once the declared, oversized body has been fully skipped. |
| networking-rpc-013 | run-forces-unframed, run-captures-full-output | `SubprocessChannel.run(_:budget:)` invoked against a configuration whose `framing` is `.newlineDelimited`, running a command whose output is delimiter-free and larger than `maximumFrameBytes` (`SubprocessChannelRunTests`, "captures delimiter-free output larger than the framing cap" / "ignores the configured framing"). | `RunResult.standardOutput` contains the complete output byte-for-byte, with no `frameSizeExceeded` thrown, proving the configured framing was overridden to `.unframed`. |
| networking-rpc-014 | run-result-shape, run-does-not-interpret-exit-status | `SubprocessChannel.run(_:budget:)` against a command that writes known output and exits `0`, and separately against one that exits non-zero (`SubprocessChannelRunTests`, "captures standard output and a zero exit status" / "reports a non-zero exit status without throwing"). | The zero-exit case returns a `RunResult` with `exitStatus == 0` and matching `standardOutput`; the non-zero case returns a `RunResult` carrying that status rather than throwing. |
| networking-rpc-015 | run-budget-enforcement, run-terminates-on-every-path | `SubprocessChannel.run(_:budget:)` against a long-running command with a `budget` shorter than the command's natural duration (`SubprocessChannelRunTests`, "throws WallClockBudgetExceeded when the budget elapses"). | `run` throws `WallClockBudgetExceeded`, and the child process is terminated rather than left running. |
| networking-rpc-016 | single-stdout-reader | `messages()` called a second time on the same launched channel (`SubprocessChannelTests`, "a second call to messages() throws alreadyConsumed — the stream is single-consumer"). | The second call throws `ChannelError.alreadyConsumed`; the first call's stream is unaffected. |
| networking-rpc-017 | termination-preserves-trailing-frame-on-natural-eof | A child that writes a final unterminated line then exits on its own, under `.newlineDelimited` framing (`SubprocessChannelTests`, "a child that exits on its own still delivers its trailing unterminated line"). | The trailing unterminated line is delivered as the last frame on `messages()`. |
| networking-rpc-018 | termination-suppresses-flush-on-forced-teardown | `terminate()` called mid-message against a child under `.newlineDelimited` and, separately, `.contentLength` framing that has written a partial frame (`SubprocessChannelTests`, "terminate() does not turn a partial line into a frame on a newline-delimited stream" / "terminate() mid-message finishes a .contentLength stream cleanly rather than throwing"). | The message stream finishes cleanly with no partial frame delivered and no `MessageFramingError` thrown. |
| networking-rpc-019 | environment-replace-policy, environment-merge-policy | A channel launched with `.replace` and a non-empty `environment`, versus one launched with `.mergeOverParent` and the same `environment`, against a parent process with a distinguishing environment variable already set (`SubprocessChannelTests`, ".replace isolates the child from the parent's environment" / ".mergeOverParent merges the override over the parent's environment"). | Under `.replace`, the child's environment contains only the configured variables; under `.mergeOverParent`, the child's environment contains both the parent's distinguishing variable and the configured override. |
| networking-rpc-020 | budget-nan-starts-no-timer, budget-caller-cancellation-propagates | `withWallClockBudget(.nan) { ... }` wrapping a long-running operation, and separately the awaiting task cancelled mid-operation (`WallClockBudgetTests`, "a NaN budget does not become a zero-second one" / "cancelling the awaiting task propagates into the budget instead of waiting it out"). | The NaN case lets the operation run to completion with no immediate `WallClockBudgetExceeded`; the cancellation case throws `CancellationError` promptly, well before the operation or the budget would otherwise resolve. |

## Edge Cases

- **Null/empty input**: An empty chunk fed to a `.unframed` decoder's `consume(_:)` MUST yield an empty array. A zero-length message passed to `frame(_:)` for `.contentLength` MUST still produce a valid `Content-Length: 0\r\n\r\n` header with an empty body; a decoder reading that header back MUST immediately yield one empty `Data` frame, since a declared body length of `0` already satisfies "the whole body has arrived." An empty `environment` (`[:]`) MUST be treated as "inherit the parent unchanged" under `.replace` and as "a no-op merge" under `.mergeOverParent`, never as "clear the child's environment." A `nil` `currentDirectoryURL` MUST let the child inherit the parent's working directory.
- **Boundary values**: A frame or declared body length exactly equal to `maximumFrameBytes` (16,777,216 bytes) MUST decode successfully — the cap is exceeded only when the buffered byte count is strictly greater than the limit — while one byte more MUST throw `frameSizeExceeded`. A `budget` `seconds` value exactly equal to `maximumWallClockBudgetSeconds` (31,536,000) MUST start no timer, per the inclusive `seconds < maximumWallClockBudgetSeconds` guard, while a `seconds` value of exactly `0` MUST expire immediately rather than "start no timer" — the zero-versus-unbounded boundary is asymmetric with the NaN/ceiling boundary above it.
- **Concurrent access**: `SubprocessChannel` is an `actor`, so every actor-isolated call against one instance is serialized by Swift's actor executor; two concurrent `send(_:)`/`sendRaw(_:)` calls are still ordered by call order, not by which happens to reach the descriptor first, per `send-call-order-preserved`. Two concurrent `terminate()` calls on the same channel MUST both observe the single teardown, per `termination-idempotent`. Two concurrent `waitUntilExit()` calls MUST both resolve to the same status once the child exits, and cancelling one MUST NOT affect the other, per `exit-status-multi-waiter-independence`. `withWallClockBudget(_:_:)` supports an arbitrary number of independent, concurrent invocations, because each call constructs its own race state and its own pair of tasks.
- **Error states**: A malformed `Content-Length` header (a non-UTF-8 line, a line with no `:` separator, or a non-integer or negative value) MUST throw `MessageFramingError.malformedHeader`; a header block with no `Content-Length` field MUST throw `MessageFramingError.missingContentLength`; an oversized frame MUST throw `MessageFramingError.frameSizeExceeded(limit:)`. A failed process launch — the `F_SETNOSIGPIPE` `fcntl` call failing, or `Process.run()` itself throwing — MUST throw `ChannelError.launchFailed` and MUST leave no child running. A write after stdin has closed MUST throw `ChannelError.inputClosed`.
- **Offline/disconnected state**: This component has no network transport of its own — `SubprocessChannel`'s I/O is local pipes to a child process, not a socket — so there is no "connectivity lost" case for it directly. The closest analogue the source itself handles is a child that backgrounds a grandchild holding the stderr write end open indefinitely (an `npx` or `sh -c "… &"` wrapper): `standardErrorText()`/`standardErrorData()` MUST NOT hang waiting for that end-of-file; per `stderr-drain-bounded-wait`, they MUST return whatever is buffered once the 0.5-second drain grace elapses, and MUST mark that capture as incomplete. `withWallClockBudget(_:_:)` is the general mechanism any caller — including a networked one, such as `PluginTransport`'s HTTP path (see `related`) — uses to bound an operation that has no notion of "offline" of its own.

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

## Deep Linking

Not applicable: none of these sources define a URL scheme, route, or navigation destination — a `Content-Length`-style header and a subprocess's file-descriptor plumbing address a byte stream and a child process, not an app deep link.

## Localization

`MessageFraming.swift`, `SubprocessChannel.swift`, and `WallClockBudget.swift` contain hardcoded, unlocalized English string literals surfaced via `LocalizedError.errorDescription` and two diagnostic prefixes; none has a string-catalog key — the literal is both the value and its own identifier.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "Malformed frame header: %@" | `MessageFramingError.malformedHeader(_:).errorDescription`, interpolated with the specific reason |
| (none — literal, no catalog key) | "Frame header is missing a Content-Length field." | `MessageFramingError.missingContentLength.errorDescription` |
| (none — literal, no catalog key) | "Truncated message: expected %d body bytes, received %d." | `MessageFramingError.truncatedMessage(expected:received:).errorDescription` |
| (none — literal, no catalog key) | "Frame exceeds the %d-byte cap." | `MessageFramingError.frameSizeExceeded(limit:).errorDescription` |
| (none — literal, no catalog key) | "The subprocess channel has not been launched yet." | `ChannelError.notLaunched.errorDescription` |
| (none — literal, no catalog key) | "The subprocess channel has already been launched." | `ChannelError.alreadyLaunched.errorDescription` |
| (none — literal, no catalog key) | "messages() has already been called; only one reader is supported." | `ChannelError.alreadyConsumed.errorDescription` |
| (none — literal, no catalog key) | "The subprocess channel's standard input has been closed." | `ChannelError.inputClosed.errorDescription` |
| (none — literal, no catalog key) | "Failed to launch the subprocess: %@" | `ChannelError.launchFailed(_:).errorDescription`, interpolated with the failure reason |
| (none — literal, no catalog key) | "The subprocess exited with status %d: %@" | `ChannelError.exited(status:standardError:).errorDescription` |
| (none — literal, no catalog key) | "The operation exceeded its %gs budget." | `WallClockBudgetExceeded.errorDescription`, interpolated with the elapsed seconds |
| (none — literal, no catalog key) | "[stderr truncated to the last 1048576 bytes]\n" | Prefix `standardErrorText()` prepends when the tail cap trimmed the buffer |
| (none — literal, no catalog key) | "[stderr capture incomplete: the drain did not finish within 0.5s]\n" | Prefix `standardErrorText()` prepends when the drain grace lapsed |

## Accessibility Options

Not applicable: these sources present no UI, so they respond to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `MessageFraming.swift`, `SubprocessChannel.swift`, and `WallClockBudget.swift` contain no feature-flag or settings-key reference.

## Analytics

Not applicable: these sources contain no analytics or event-tracking call.

## Privacy

- **Data handled**: `SubprocessChannel.Configuration`'s `arguments`, `environment`, and any bytes sent via `send(_:)`/`sendRaw(_:)` MAY carry a credential a caller placed into the child's command line, environment, or stdin; the child's stdout and stderr MAY likewise echo one back. None of these sources inspects any of that data — every byte is forwarded to `Process`/`Pipe` or handed back to the caller exactly as given or received, with no logging, redaction, or classification of its own.
- **Storage**: None of these sources performs storage. `SubprocessChannel` holds stdout frames only until a consumer reads them from the `AsyncThrowingStream`, and holds stderr only in its capped, in-memory buffer for the channel's lifetime.
- **Transmission**: None of these sources performs network transmission; all I/O is local — pipes between this process and a spawned child.
- **Retention**: A decoded frame is retained only until its consumer reads it from the message stream; `SubprocessChannel`'s stderr buffer is retained, capped at 1 MiB (tail-only), for the life of the channel and is released with it. `MessageFramingDecoder`'s own buffer never exceeds `maximumFrameBytes` (16 MiB) for `.newlineDelimited`/`.contentLength`, and holds nothing at all for `.unframed`.

## Logging

Not applicable: `MessageFraming.swift`, `SubprocessChannel.swift`, `SubprocessChannel+Run.swift`, and `WallClockBudget.swift` contain no logging call (`print`, `os_log`, or otherwise) — every diagnostic they produce is a typed `Error` case or one of the two `standardErrorText()` prefix strings described under Localization, not a log line.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/RPC/MessageFraming.swift`, `SubprocessChannel.swift`, `SubprocessChannel+Run.swift`, and `WallClockBudget.swift`, consumed directly by `PluginTransport.swift` (`AIPluginKit`, see `related`) and available to any other Foundation-based caller in the host app or a plugin bundle. They depend on `Foundation` (`Process`, `Pipe`, `FileHandle`, `Data`), `Dispatch` (`DispatchIO`, `DispatchQueue`), and `Darwin` (`fcntl`, `SIGTERM`/`SIGKILL`), and are themselves UI-framework-agnostic — a SwiftUI host consumes `SubprocessChannel`'s `AsyncThrowingStream<Data, Error>` identically to an AppKit one.
- **Compose**: `Process` has no Android/JVM equivalent for spawning arbitrary executables in most app sandboxes, so a Compose port of `SubprocessChannel` is realistically a JVM/desktop-only (not Android) concern — model it with `ProcessBuilder`/`Process`, writing to `outputStream` then closing it for EOF, and draining `inputStream`/`errorStream` on separate `Dispatchers.IO` coroutines rather than blocking the main dispatcher, matching the source's continuous-drain requirement for stderr. Reproduce `.newlineDelimited` with `BufferedReader.readLine()` (re-appending the stripped `\n`) or, for byte-exact fidelity, a manual scan for `0x0A`; reproduce `.contentLength` by scanning for the `\r\n\r\n` terminator manually, since no standard library type parses this framing directly. Model `withWallClockBudget` with two coroutines raced via `select`, cancelling — not joining — the loser, since `withTimeout`'s implicit cancellation-and-rethrow does not by itself let a caller distinguish "the operation lost the race" from "the operation was itself cancelled by something else," a distinction `WallClockBudgetExceeded` makes explicit.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive), model `SubprocessChannel` with `child_process.spawn`, writing to `.stdin` then calling `.stdin.end()` for the EOF `close-input-orderly` requires, and reading `.stdout`/`.stderr` as `Buffer` chunks (never decoded to a string on the stderr path, to preserve `stderr-data-raw`'s raw-bytes guarantee). Reproduce `.newlineDelimited` with a manual byte accumulator split on `0x0A` (not `readline.createInterface`, which strips the delimiter this contract requires kept) and `.contentLength` with a manual scan for `\r\n\r\n`. Model `withWallClockBudget` with `Promise.race` between the operation and a `setTimeout`-backed promise, paired with an `AbortController` so the losing side is actually cancelled rather than left running unobserved — `Promise.race` alone only stops awaiting the loser, it does not cancel it, which is the exact gap `budget-cancels-not-awaits-loser` requires closing.
- **AppKit / UIKit**: Identical to the SwiftUI note for the RPC layer itself — these sources are UI-framework-agnostic; only the application embedding them differs, never this contract. Note that `Process` is unavailable on iOS, so a UIKit host on iOS cannot use `SubprocessChannel` as written; only the `MessageFraming`/`MessageFramingDecoder`/`WallClockBudget` parts port to iOS.
- **WinUI 3**: Model `SubprocessChannel` with `System.Diagnostics.Process`/`ProcessStartInfo`, setting `RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` to `true`; per `environment-replace-policy`'s replace semantics, call `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `environment`, since `EnvironmentVariables` starts pre-populated with the parent's own variables — the opposite of this source's default. Write to `StandardInput.BaseStream` then call `StandardInput.Close()` for `close-input-orderly`'s EOF, and read `StandardError.BaseStream` into a `byte[]` (never `StandardError.ReadToEndAsync()`'s decoded `string`) to reproduce `stderr-data-raw`'s raw-bytes guarantee; await exit via `Process.WaitForExitAsync(cancellationToken)` rather than the blocking `WaitForExit()`, matching `exit-status-no-invented-value`'s throw-rather-than-invent contract. Represent the stdout message stream as an `IAsyncEnumerable<byte[]>` built over an unbounded `System.Threading.Channels.Channel<byte[]>`, matching this source's own unbounded `AsyncThrowingStream` buffering policy, and call `Process.Kill()` (not `Process.Kill(entireProcessTree: true)`, to preserve `termination-signal-scope`'s direct-child-only rule) from a `CancellationToken` registration in place of `terminate()` — noting Windows has no SIGTERM-equivalent graceful-then-forceful escalation, so a port that wants `termination-sequence`'s two-stage grace period must implement its own (for example `CloseMainWindow()` followed by a timed `Kill()`). Model `MessageFramingDecoder` as a mutable class or a `struct` with `ref`-like usage confined to one owner, matching `decoder-value-type-single-owner`. Model `withWallClockBudget` with `Task.WhenAny` racing the operation `Task` against `Task.Delay(TimeSpan, CancellationToken)`, explicitly calling `Cancel()` on a `CancellationTokenSource` tied to the losing task rather than relying on `Task.WhenAny` alone, which — like `Promise.race` — only stops awaiting the loser and does not cancel it by itself.

## Design Decisions

**Decision**: `MessageFramingDecoder`'s newline scan tracks a `scanCursor` that is shifted (not reset to `0`) every time completed frames are cut off the front of the buffer, so a subsequent `consume(_:)` call resumes scanning from where the previous call left off rather than rescanning the buffer's unconsumed tail from the start.
**Rationale**: `MessageFraming.swift`'s own doc comment states the alternative was measured at 114 seconds to decode a single 256 KB line — an O(n²) cost from rescanning already-examined bytes on every call. The cursor is what makes decoding linear in the number of bytes fed rather than quadratic, and is why `decoder-feed-chunk-sized-input` is phrased as a SHOULD for callers rather than a correctness requirement: feeding the decoder one byte at a time still produces correct frames, it is only slow.
**Approved**: pending

**Decision**: `terminate()` distinguishes a child's own end-of-file from a teardown-induced one (`DescriptorReader.reachedEndOfStreamNaturally`) by recording "a teardown has begun" (`markTornDown()`) *before* sending SIGTERM, and only flushes `MessageFramingDecoder.finish()` on the pump's exit when that flag was never set for a live, un-EOF'd descriptor.
**Rationale**: SIGTERM kills an ordinary child, the kernel closes its write end, and a genuine end-of-file arrives well before `terminate()`'s own `stopAll()` closes anything — so end-of-file alone cannot tell the pump whether the child finished speaking on its own or was shot mid-sentence. Reading every end-of-file as "natural" would flush the decoder on exactly the forced-shutdown path this distinction exists to protect, fabricating a whole message out of half of one for `.newlineDelimited`, or turning an orderly kill into a thrown `truncatedMessage` for `.contentLength`.
**Approved**: pending

**Decision**: `SubprocessChannel.run(_:budget:)` always decodes as `.unframed`, discarding whatever `MessageFraming` value the caller's `configuration` specifies.
**Rationale**: `SubprocessChannel+Run.swift`'s own doc comment states this directly: a one-shot run has no messages to frame, it hands back one `Data` holding all of stdout, and honoring a caller's framing here would subject a plain capture to a streaming protocol's malformed-peer guard — the 16 MiB cap that fires when no delimiter has arrived in that many bytes — which would incorrectly reject delimiter-free output (the doc comment's own example is git's NUL-terminated, newline-free machine-readable status on a large repository) that was never malformed to begin with.
**Approved**: pending

**Decision**: `withWallClockBudget(_:_:)` cancels the losing task on either outcome (timeout or caller cancellation) but never awaits it before resuming its own continuation.
**Rationale**: `WallClockBudget.swift`'s own doc comment states that awaiting the loser would make the function's guarantee only as good as the wrapped operation's cooperation with cancellation — which blocking I/O and a synchronous `Process` wait cannot promise. The trade this decision accepts is that a caller observing `WallClockBudgetExceeded` (or, in `SubprocessChannel.terminate()`, the grace-period expiry built on this same primitive) has only *requested* the loser's teardown, not confirmed it has finished, at the moment its own `async` call returns.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

`separation-of-concerns` passes because the four sources each own one job — framing rules, incremental decoding, process/descriptor lifecycle, and wall-clock racing — with no file reaching into another's internal state. `explicit-error-handling` passes because every defined failure path maps to a named, typed error case (`MessageFramingError`, `ChannelError`, `WallClockBudgetExceeded`) rather than a silent catch, with the one open question tracked as the descriptor-close-failure-signal marker above. `unit-test-coverage` and `test-pyramid` both pass because `MessageFramingTests.swift`, `SubprocessChannelTests.swift`, `SubprocessChannelRunTests.swift`, and `WallClockBudgetTests.swift` exercise every framing case, every cap-recovery path, and every termination ordering with hermetic, fast unit tests against real (but tiny, deterministic) child processes — no integration or end-to-end layer is needed for this component's contract. `fault-tolerance` passes because every defined failure mode degrades to a typed thrown error or a bounded wait rather than a hang, deadlock, or crash — the continuous stderr drain in particular exists specifically to avoid the 64 KB pipe-buffer deadlock its own doc comment names. `timeout-handling` passes because `withWallClockBudget(_:_:)` gives every wrapped operation a genuine wall-clock bound, including the explicit non-bound cases (`NaN`, the one-year ceiling) that are decisions rather than fallout of the arithmetic. `idempotent-operations` passes because `terminate()` is documented and tested as safe to call any number of times, concurrently or sequentially, with every caller observing the one completed teardown. `error-recovery` fails because none of these four sources retries, backs off, or otherwise recovers from a failure at its own layer — a `frameSizeExceeded`, a `launchFailed`, or a `WallClockBudgetExceeded` is reported once and left for the caller to act on. `string-externalization` fails because every string listed under Localization above is a hardcoded English literal with no catalog key.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
