---
id: 2dd6133a-1d6c-4ee5-9e37-308a11966433
title: RPC
domain: agentictoolkit://cookbook/foundation/networking/rpc
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/ai/plugins/plugin-transport
references: []
approved-by: ''
approved-date: ''
---

# RPC

## Overview

This component is the non-UI logic root for talking to a child process as
if it were an RPC peer. It has four parts:

- A framing scheme describing how a byte stream is split into discrete
  messages: newline-delimited (a frame is the byte-exact slice up to and
  including its trailing linefeed byte), content-length-prefixed (a frame
  is the body only, with its `Content-Length: <n>\r\n...\r\n\r\n` header
  consumed and discarded), and unframed (a stream with no message
  boundaries at all, where a "frame" is whatever chunk of bytes arrived).
  Encoding a message for a given scheme is the framing operation.
- An incremental decoder that turns arbitrary byte chunks (never aligned to
  message boundaries) into complete frames, one chunk at a time, and
  flushes any end-of-stream remainder on request. It caps any single
  buffered frame at 16 MiB and recovers from a peer that exceeds that cap
  without losing frames already completed in the same call or letting the
  rejected frame's own bytes resynchronize the stream.
- The subprocess channel that spawns a child process and exposes its
  standard output as an asynchronous stream of frames decoded by the
  framing decoder, its standard input as a place to send framed or raw
  bytes, and its standard error as a continuously drained, capped buffer.
  It owns launch, environment policy, and a termination sequence (a
  graceful signal, then a forceful one, then reader teardown) that
  distinguishes a child ending its own output from one this operation
  killed.
- A one-shot run operation and a general wall-clock race — a one-shot
  helper that launches a channel, drains all of standard output as
  unframed regardless of the caller's configured framing, and returns a
  run result; and the general wall-clock race it (and the plugin
  transport, see `related`) uses to bound any asynchronous operation,
  cancelling — never awaiting — the loser.

This is the one shared replacement for what had been several independent
process-plus-three-pipes implementations in the codebase.

## Behavioral Requirements

- **framing-cases**: The framing scheme MUST support exactly three cases —
  newline-delimited, content-length-prefixed, unframed — each defining a
  distinct encode/decode contract.
- **newline-frame-encoding**: Encoding a message under the
  newline-delimited scheme MUST append a single linefeed byte (`0x0A`) to
  the message, unless the message already ends in a linefeed byte, in
  which case it MUST return the message unchanged.
- **content-length-frame-encoding**: Encoding a message under the
  content-length-prefixed scheme MUST prepend `Content-Length:
  <n>\r\n\r\n` in ASCII to the message, where `<n>` is the message's byte
  count, with no other header.
- **unframed-frame-encoding**: Encoding a message under the unframed
  scheme MUST return the message unchanged, with no envelope added.
- **frame-boundary-completeness**: Consuming a chunk MUST return every
  frame the buffer newly completes, in arrival order, and MUST NOT return
  a partial frame.
- **newline-frame-shape**: Under the newline-delimited scheme, each
  decoded frame MUST be the byte-exact slice up to and including its
  trailing linefeed byte, preserving that byte rather than stripping it.
- **content-length-frame-shape**: Under the content-length-prefixed
  scheme, each decoded frame MUST be the body only; the `Content-Length:
  <n>\r\n...\r\n\r\n` header MUST be consumed and discarded, never
  included in the frame.
- **unframed-decoding**: Under the unframed scheme, consuming a chunk MUST
  hand back each non-empty chunk as its own frame, unmodified, the moment
  it arrives, and MUST return an empty array for an empty chunk; no bytes
  are ever buffered for this case, and the frame-size cap below MUST NOT
  apply to it.
- **content-length-header-parsed-once**: Under the content-length-prefixed
  scheme, the header MUST be parsed exactly once, at the moment its
  blank-line terminator is seen, and MUST NOT be reparsed while the body
  is still arriving in later chunks.
- **content-length-header-line-parsing**: Each header line MUST be split
  on its first colon into a key and a trimmed value; a header key MUST be
  matched case-insensitively against `Content-Length`; any other header
  (for example `Content-Type`) MUST be tolerated and discarded without
  error.
- **content-length-malformed-header**: Header parsing MUST throw a
  malformed-header failure when a header line is not valid UTF-8, when a
  header line has no colon separator, or when the `Content-Length` value
  is not a non-negative integer.
- **content-length-missing-header**: Header parsing MUST throw a
  missing-content-length failure when no header line's key matches
  `Content-Length`.
- **frame-size-cap**: Under the newline-delimited and content-length-
  prefixed schemes, the decoder MUST enforce a 16,777,216-byte (16 MiB)
  cap on any single frame's buffered bytes.
- **cap-violation-preserves-prior-frames**: When consuming one chunk both
  completes one or more valid frames and then begins an oversized one,
  that call MUST return the completed frames and MUST defer the frame-
  size-exceeded failure to the decoder's next call, rather than losing the
  valid frames to the same failure.
- **newline-cap-recovery**: When a newline-delimited buffer exceeds the
  cap, the decoder MUST discard every byte up to and including the next
  linefeed byte it receives (dropping the oversized line in full) before
  resuming normal framing, and MUST NOT ever deliver that oversized line
  as a frame.
- **content-length-cap-recovery**: When a content-length header declares a
  body length greater than the cap, the decoder MUST discard exactly that
  many body bytes before resuming header scanning, so a Content-Length-
  shaped line inside the rejected body cannot resynchronize the stream
  onto a boundary the peer chose.
- **finish-newline-remainder**: Flushing at end-of-stream, under the
  newline-delimited scheme, MUST return the buffer's trailing unterminated
  remainder as one final frame when the buffer is non-empty, and MUST
  return an empty array when the buffer is empty.
- **finish-content-length-truncated**: Flushing at end-of-stream, under
  the content-length-prefixed scheme, MUST throw a truncated-message
  failure (carrying the expected and received byte counts) when a header
  has already been parsed and stripped but the buffer holds fewer than the
  declared number of body bytes.
- **finish-content-length-malformed**: Flushing at end-of-stream, under
  the content-length-prefixed scheme, MUST throw a malformed-header
  failure when the buffer is non-empty but no complete header was ever
  parsed.
- **finish-unframed-noop**: Flushing at end-of-stream, under the unframed
  scheme, MUST always return an empty array and MUST NOT throw, because
  the unframed scheme never holds anything back.
- **finish-during-discard**: Flushing at end-of-stream while the decoder
  is mid-discard (skipping an over-cap line or the remainder of an
  over-cap body) MUST return an empty array and MUST clear all buffered
  and discard state, rather than returning a fragment of the rejected
  frame or reporting its unarrived bytes as a truncated message.
- **decoder-single-owner**: The framing decoder MUST be a mutable value
  with no shared ownership; a channel's message pump MUST create and hold
  exactly one instance per stream, consumed only from that pump's own
  execution context, never shared concurrently across contexts.
- **channel-calls-serialized**: The subprocess channel MUST serialize
  every call made against one instance (launch, read messages, send, send
  raw, close input, read standard-error text, read standard-error bytes,
  terminate) so no two such calls run concurrently against the same
  instance; waiting for exit MUST be exempt from that serialization, so
  awaiting it never blocks the channel for the life of a long-running
  child.
- **configuration-and-result-thread-safe**: The channel's configuration
  and its run result MUST be safe to share across concurrent callers, so a
  caller MAY construct and pass either freely across concurrency domains.
- **single-stdout-reader**: Reading the message stream MUST throw a
  not-launched failure if called before launch has succeeded, and MUST
  throw an already-consumed failure if called a second time on the same
  channel; a channel MUST expose exactly one reader over the child's
  standard output.
- **launch-idempotency**: Launching MUST throw an already-launched failure
  if called on a channel that has already launched successfully.
- **launch-sigpipe-suppression**: Launching MUST disable the SIGPIPE
  signal, scoped specifically to the child's standard-input write
  descriptor, before starting the process, and MUST throw a launch-failed
  failure without spawning the process if that step fails.
- **environment-replace-policy**: Under the replace environment policy, a
  non-empty configured environment MUST become the child's entire
  environment; an empty configured environment MUST leave the child
  inheriting the parent process's environment untouched.
- **environment-merge-policy**: Under the merge-over-parent environment
  policy, a non-empty configured environment MUST be merged over the
  parent process's own environment, with the configured values winning on
  key collision; an empty configured environment MUST leave that merge a
  no-op.
- **send-applies-framing**: Sending a message MUST frame it using the
  channel's configured framing scheme before writing it to the child's
  standard input.
- **send-raw-unframed**: Sending raw bytes MUST write them to the child's
  standard input exactly as given, with no delimiter or header added,
  regardless of the channel's configured framing scheme.
- **send-call-order-preserved**: Two or more concurrent calls to send a
  message or send raw bytes on the same channel MUST reach the child's
  standard-input descriptor in the order those calls were made, because
  each call's write is submitted synchronously, while the channel is
  held, before the caller suspends to await completion.
- **write-after-close-throws**: A raw-bytes (or framed) send call made
  after the child's standard input has been closed (by closing input or by
  terminating) MUST throw an input-closed failure; a write attempted
  after the child has exited MUST throw an error derived from a
  broken-pipe condition rather than raising the SIGPIPE signal, because
  launching has already disabled SIGPIPE on that one descriptor.
- **close-input-orderly**: Closing input MUST flush every byte already
  submitted via a prior send call to the child before releasing the
  standard-input descriptor, so the child observes those bytes and only
  then end-of-file.
- **stderr-continuous-drain**: The channel MUST drain the child's standard
  error continuously on its own execution context, independent of both
  the channel's serialized calls and the standard-output message pump,
  rather than reading it only once at exit.
- **stderr-tail-cap**: The accumulated standard-error buffer MUST be
  capped at 1,048,576 bytes (1 MiB); once exceeded, the buffer MUST retain
  the most recently written bytes (the tail) and discard the oldest, and
  MUST record that truncation occurred.
- **stderr-text-decoding**: Reading standard-error text MUST decode the
  buffered bytes as UTF-8, and MUST fall back to Latin-1 decoding (which
  accepts every byte) when the buffer is not valid UTF-8, rather than
  returning an empty string.
- **stderr-text-diagnostic-prefixes**: Reading standard-error text MUST
  prepend `"[stderr truncated to the last 1048576 bytes]\n"` when the tail
  cap trimmed the buffer, and MUST prepend `"[stderr capture incomplete:
  the drain did not finish within 0.5s]\n"` when the bounded drain wait
  lapsed before the drain finished; either, neither, or both prefixes MAY
  appear together.
- **stderr-data-raw**: Reading standard-error bytes MUST return the
  buffered bytes exactly as captured, with no decoding, no re-encoding,
  and no diagnostic prefix of any kind.
- **stderr-drain-bounded-wait**: Reading standard-error text or bytes MUST
  wait no more than 0.5 seconds for the standard-error drain to finish
  before answering with whatever has been buffered so far; expiry of that
  wait MUST NOT be treated as an error.
- **exit-status-no-invented-value**: Waiting for exit MUST throw a
  not-launched failure when called on a channel that was never launched,
  and MUST throw a cancellation signal when the awaiting context is
  cancelled before the child exits; it MUST NOT return `0`, or any other
  value, for either case.
- **exit-status-multi-waiter-independence**: Cancelling one caller's
  wait-for-exit call MUST leave every other concurrent caller's
  wait-for-exit call on the same channel parked and unaffected, and MUST
  NOT touch the child process.
- **termination-sequence**: Terminating MUST perform, in order: stop the
  standard-input writer, cancelling any write in flight; send the
  graceful termination signal (SIGTERM) to the child if it is still
  running; wait up to 2.0 seconds for it to exit; send the forceful
  termination signal (SIGKILL) if it is still running after that wait;
  stop both standard-output/standard-error readers (the only point at
  which their descriptors close); then wait up to 0.5 seconds for the
  standard-output message pump to finish flushing and finishing the
  message stream.
- **termination-idempotent**: Terminating MUST be idempotent: a channel on
  which it has already run, or on which it is already running, MUST let
  every caller — concurrent or subsequent — observe the same completed
  teardown rather than starting a second one.
- **termination-uncancellable**: The work terminating performs MUST run
  independent of the calling context's own cancellation, so a caller that
  is itself cancelled while awaiting termination MUST NOT cause the child
  to be abandoned mid-teardown.
- **termination-preserves-trailing-frame-on-natural-eof**: When the
  child's standard output reaches end-of-file on its own — not because
  terminating tore the descriptor down — the message pump MUST flush the
  decoder's end-of-stream remainder and yield any frame it returns before
  finishing the message stream.
- **termination-suppresses-flush-on-forced-teardown**: When terminating
  itself ends the child's standard output (a forced teardown), the
  message pump MUST finish the message stream without flushing the
  decoder's end-of-stream remainder, so a partial newline-delimited line
  is never delivered as a whole frame and a content-length-prefixed
  shutdown is never reported as a truncated-message transport error.
- **termination-signal-scope**: Terminating's graceful and forceful
  signals MUST each target only the direct child process, never a process
  group; a grandchild the child itself spawned and backgrounds MUST NOT
  receive either signal from this operation — a caller that needs
  grandchildren reaped MUST arrange it in the command it launches, since
  this component exposes no process-group spawn option to use instead.
- **run-forces-unframed**: The one-shot run operation MUST set the framing
  scheme to unframed before constructing its channel, regardless of the
  framing value supplied in the configuration passed in.
- **run-captures-full-output**: The one-shot run operation MUST launch the
  channel, close its standard input immediately, and concatenate every
  chunk yielded by the message stream in arrival order to form the run
  result's standard output, reproducing the child's raw standard output
  byte-for-byte.
- **run-tolerates-exited-case**: The one-shot run operation MUST catch an
  exited failure thrown while draining the message stream and treat it as
  a normal end of that iteration rather than propagating it, tolerating a
  case the message stream does not currently throw but could in the
  future; every other channel failure thrown from that drain MUST
  propagate.
- **run-budget-enforcement**: The one-shot run operation MUST wrap its
  launch, drain, and exit-wait sequence in the wall-clock budget race, so
  a budget-exceeded failure thrown by that race propagates from the run
  operation unchanged.
- **run-terminates-on-every-path**: The one-shot run operation MUST
  terminate the channel on any thrown error including a budget-exceeded
  failure, before rethrowing.
- **run-result-shape**: On success, the one-shot run operation MUST return
  a run result whose standard error comes from reading standard-error
  text, whose exit status comes from waiting for exit, and whose duration
  is the wall-clock time elapsed between just before the run began and the
  moment the run result is constructed.
- **run-does-not-interpret-exit-status**: The one-shot run operation MUST
  NOT throw on a non-zero exit status in its run result; callers MAY treat
  a non-zero exit as success or failure at their own discretion, since the
  subprocess channel itself defines no notion of a non-zero exit being an
  error.
- **decoder-feed-chunk-sized-input**: Callers SHOULD feed the decoder
  chunks of realistic size rather than one byte at a time; per-byte
  feeding does not change the frames produced, but it defeats the
  decoder's scan-cursor optimization and turns every call into mostly
  wasted overhead.
- **budget-race-not-scoped-join**: The wall-clock budget race MUST
  implement its race between the operation and a timer as two
  independent, unstructured executions resumed through a single
  continuation, resumed exactly once, and MUST NOT use a structured join
  that would implicitly await the losing side before a timeout could ever
  be observed.
- **budget-cancels-not-awaits-loser**: When the timer wins the race, the
  wall-clock budget race MUST cancel the operation and throw a
  budget-exceeded failure (carrying the elapsed seconds) immediately,
  without awaiting that operation's completion.
- **budget-caller-cancellation-propagates**: Cancelling the context
  awaiting the wall-clock budget race MUST cancel both the operation and
  the timer and MUST rethrow a cancellation signal promptly, rather than
  waiting out either one.
- **budget-nan-starts-no-timer**: A `seconds` value of not-a-number MUST
  start no timer — the operation runs to completion or to the caller's own
  cancellation, unbounded by this call — rather than being treated as a
  zero-second budget.
- **budget-ceiling-starts-no-timer**: A `seconds` value at or above
  31,536,000 (60 × 60 × 24 × 365, one year), including positive infinity
  and the largest representable value, MUST start no timer.
- **budget-nonpositive-expires-immediately**: A `seconds` value at or
  below `0` (including negative infinity) MUST be treated as an immediate
  expiry — a zero-duration wait — not as "no budget."
- **descriptor-close-failure-signal**: NEEDS REVIEW: Not implemented in
  source. Closing a descriptor discards whatever error code the
  underlying close reports; a descriptor that fails to close (for example
  a double close, or a bad-file-descriptor error) is therefore never
  logged, thrown, or otherwise surfaced to any caller, and no test
  exercises a failing close to say what the intended behavior is.

## Appearance

Not applicable — this is a subprocess/RPC networking engine (byte-stream framing, process I/O, and wall-clock timeout racing), not a visual component.

## States

Not applicable — this is a subprocess/RPC networking engine, not a visual component; its runtime state machines (a channel's launched/consuming/terminated lifecycle, and a decoder's buffering/discarding lifecycle) are captured under Behavioral Requirements above, not in a UI visual-state table.

## Accessibility

Not applicable — this is a subprocess/RPC networking engine with no user interface of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| networking-rpc-001 | newline-frame-shape, frame-boundary-completeness | Three newline-terminated lines fed as one chunk to a newline-delimited decoder. | Consuming that chunk returns exactly three frames, each ending in its own linefeed byte, in the order the lines appeared. |
| networking-rpc-002 | frame-boundary-completeness | A single message's bytes fed across three separate consume calls, split mid-word, under the newline-delimited scheme. | The first two calls return no frames; the third call, which delivers the linefeed byte, returns exactly one frame containing the complete message. |
| networking-rpc-003 | finish-newline-remainder | A newline-delimited decoder fed a message with no trailing newline, then end-of-stream flushed twice. | The first flush returns the unterminated remainder as one frame; the second flush returns an empty array. |
| networking-rpc-004 | content-length-frame-shape | A well-formed `Content-Length: <n>\r\n\r\n<body>` message fed to a content-length-prefixed decoder. | Consuming it returns exactly one frame equal to the body, with no header bytes present. |
| networking-rpc-005 | content-length-header-parsed-once, content-length-header-line-parsing | An extra, non-Content-Length header line appears before or after the Content-Length line, in either order. | Both orderings decode to the same body frame; the extra header is tolerated and discarded. |
| networking-rpc-006 | content-length-frame-shape | A body containing multi-byte UTF-8 characters, with Content-Length declared in bytes rather than characters. | The decoded frame's byte length equals the declared Content-Length value, not the character count. |
| networking-rpc-007 | finish-content-length-truncated | A content-length-prefixed decoder given a header declaring a body longer than what has arrived, then end-of-stream flushed. | The flush throws a truncated-message failure carrying the declared and actually-received byte counts. |
| networking-rpc-008 | content-length-missing-header | A header block containing the blank-line terminator but no Content-Length line. | Consuming it throws a missing-content-length failure. |
| networking-rpc-009 | unframed-decoding | Three chunks fed to an unframed decoder, one of which is empty. | Each non-empty chunk is returned as its own frame, byte-exactly and in order; the empty chunk yields no frame. |
| networking-rpc-010 | frame-size-cap, unframed-decoding | A byte sequence larger than the frame-size cap with no delimiter anywhere in it, fed to an unframed decoder. | The oversized bytes decode successfully with no thrown error, because the 16 MiB cap does not apply to the unframed scheme. |
| networking-rpc-011 | cap-violation-preserves-prior-frames, newline-cap-recovery | A chunk containing one complete newline-terminated frame immediately followed by the start of an oversized, still-unterminated line. | That call returns the complete frame; the decoder's very next call throws a frame-size-exceeded failure, and the oversized line is never delivered as a frame. |
| networking-rpc-012 | content-length-cap-recovery | A Content-Length header declares a body above the cap, and the rejected body itself contains a byte sequence shaped like a Content-Length header line. | The embedded look-alike header inside the discarded body is never parsed as a new frame boundary; framing resumes correctly once the declared, oversized body has been fully skipped. |
| networking-rpc-013 | run-forces-unframed, run-captures-full-output | The one-shot run operation invoked against a configuration whose framing is newline-delimited, running a command whose output is delimiter-free and larger than the frame-size cap. | The run result's standard output contains the complete output byte-for-byte, with no frame-size-exceeded failure thrown, proving the configured framing was overridden to unframed. |
| networking-rpc-014 | run-result-shape, run-does-not-interpret-exit-status | The one-shot run operation against a command that writes known output and exits 0, and separately against one that exits non-zero. | The zero-exit case returns a run result with exit status 0 and matching standard output; the non-zero case returns a run result carrying that status rather than throwing. |
| networking-rpc-015 | run-budget-enforcement, run-terminates-on-every-path | The one-shot run operation against a long-running command with a budget shorter than the command's natural duration. | The run throws a budget-exceeded failure, and the child process is terminated rather than left running. |
| networking-rpc-016 | single-stdout-reader | Reading the message stream called a second time on the same launched channel. | The second call throws an already-consumed failure; the first call's stream is unaffected. |
| networking-rpc-017 | termination-preserves-trailing-frame-on-natural-eof | A child that writes a final unterminated line then exits on its own, under the newline-delimited scheme. | The trailing unterminated line is delivered as the last frame on the message stream. |
| networking-rpc-018 | termination-suppresses-flush-on-forced-teardown | Terminating called mid-message against a child under the newline-delimited scheme and, separately, the content-length-prefixed scheme, that has written a partial frame. | The message stream finishes cleanly with no partial frame delivered and no framing failure thrown. |
| networking-rpc-019 | environment-replace-policy, environment-merge-policy | A channel launched with the replace policy and a non-empty environment, versus one launched with the merge-over-parent policy and the same environment, against a parent process with a distinguishing environment variable already set. | Under the replace policy, the child's environment contains only the configured variables; under the merge-over-parent policy, the child's environment contains both the parent's distinguishing variable and the configured override. |
| networking-rpc-020 | budget-nan-starts-no-timer, budget-caller-cancellation-propagates | The wall-clock budget race given a not-a-number budget wrapping a long-running operation, and separately the awaiting context cancelled mid-operation. | The not-a-number case lets the operation run to completion with no immediate budget-exceeded failure; the cancellation case throws a cancellation signal promptly, well before the operation or the budget would otherwise resolve. |

## Edge Cases

- **Null/empty input**: An empty chunk fed to an unframed decoder's consume operation MUST yield an empty array. A zero-length message passed to the content-length-prefixed encoding operation MUST still produce a valid `Content-Length: 0\r\n\r\n` header with an empty body; a decoder reading that header back MUST immediately yield one empty frame, since a declared body length of `0` already satisfies "the whole body has arrived." An empty configured environment MUST be treated as "inherit the parent unchanged" under the replace policy and as "a no-op merge" under the merge-over-parent policy, never as "clear the child's environment." No configured working directory MUST let the child inherit the parent's working directory.
- **Boundary values**: A frame or declared body length exactly equal to the frame-size cap (16,777,216 bytes) MUST decode successfully — the cap is exceeded only when the buffered byte count is strictly greater than the limit — while one byte more MUST throw a frame-size-exceeded failure. A budget `seconds` value exactly equal to the one-year ceiling MUST start no timer, per the inclusive less-than guard, while a `seconds` value of exactly `0` MUST expire immediately rather than "start no timer" — the zero-versus-unbounded boundary is asymmetric with the not-a-number/ceiling boundary above it.
- **Concurrent access**: The subprocess channel serializes every call against one instance; two concurrent send calls are still ordered by call order, not by which happens to reach the descriptor first. Two concurrent terminate calls on the same channel MUST both observe the single teardown. Two concurrent wait-for-exit calls MUST both resolve to the same status once the child exits, and cancelling one MUST NOT affect the other. The wall-clock budget race supports an arbitrary number of independent, concurrent invocations, because each call constructs its own race state.
- **Error states**: A malformed Content-Length header (a non-UTF-8 line, a line with no colon separator, or a non-integer or negative value) MUST throw a malformed-header failure; a header block with no Content-Length field MUST throw a missing-content-length failure; an oversized frame MUST throw a frame-size-exceeded failure (carrying the limit). A failed process launch — the SIGPIPE-disabling step failing, or starting the process itself throwing — MUST throw a launch-failed failure and MUST leave no child running. A write after standard input has closed MUST throw an input-closed failure.
- **Offline/disconnected state**: This component has no network transport of its own — its I/O is local pipes to a child process, not a socket — so there is no "connectivity lost" case for it directly. The closest analogue the source itself handles is a child that backgrounds a grandchild holding the standard-error write end open indefinitely (a wrapper command that spawns a background job): reading standard-error text or bytes MUST NOT hang waiting for that end-of-file; they MUST return whatever is buffered once the 0.5-second drain grace elapses, and MUST mark that capture as incomplete. The wall-clock budget race is the general mechanism any caller — including a networked one, such as the plugin transport's HTTP path (see `related`) — uses to bound an operation that has no notion of "offline" of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| executable path | string (file path) | none — required | The child executable to launch. |
| arguments | list of strings | `[]` | Arguments passed to the child. |
| environment | key-value map of strings | `{}` | Environment variables applied per environment policy. |
| environment policy | enumeration (replace / merge-over-parent) | replace | See environment-replace-policy / environment-merge-policy. |
| framing | enumeration (newline-delimited / content-length-prefixed / unframed) | newline-delimited | How the child's standard output is split into frames; ignored by the one-shot run operation, which forces unframed. |
| working directory | string (file path), optional | none (inherit the parent's) | The child's working directory. |
| budget (parameter to the one-shot run operation) | number (seconds) | none — required | The wall-clock bound for the whole one-shot run. |
| maximum frame bytes (internal constant, not configurable) | integer (bytes) | `16777216` (16 MiB) | Per-frame buffering cap for the newline-delimited and content-length-prefixed schemes. |
| read chunk size (internal constant, not configurable) | integer (bytes) | `65536` (64 KiB) | High-water mark for both the standard-output pump and the standard-error drain. |
| termination grace seconds (internal constant, not configurable) | number (seconds) | `2.0` | Graceful-signal grace period before escalating to the forceful signal. |
| standard-error drain grace seconds (internal constant, not configurable) | number (seconds) | `0.5` | Bounded wait for the standard-error drain when reading standard-error text or bytes. |
| message-pump drain grace seconds (internal constant, not configurable) | number (seconds) | `0.5` | Bounded wait, during termination, for the standard-output pump to flush and finish. |
| maximum standard-error bytes (internal constant, not configurable) | integer (bytes) | `1048576` (1 MiB) | Tail-retaining cap on the buffered standard-error capture. |
| maximum wall-clock budget seconds (internal constant, not configurable) | number (seconds) | `31536000` (one year) | The ceiling above which a budget is treated as "no deadline" rather than converted to a trapping zero-duration wait. |

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation destination — a content-length-style header and a subprocess's file-descriptor plumbing address a byte stream and a child process, not an app deep link.

## Localization

This component's failure descriptions and two diagnostic prefixes are hardcoded, unlocalized English string literals; none has a string-catalog key — the literal is both the value and its own identifier.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "Malformed frame header: %@" | The malformed-header failure's description, interpolated with the specific reason |
| (none — literal, no catalog key) | "Frame header is missing a Content-Length field." | The missing-content-length failure's description |
| (none — literal, no catalog key) | "Truncated message: expected %d body bytes, received %d." | The truncated-message failure's description |
| (none — literal, no catalog key) | "Frame exceeds the %d-byte cap." | The frame-size-exceeded failure's description |
| (none — literal, no catalog key) | "The subprocess channel has not been launched yet." | The not-launched failure's description |
| (none — literal, no catalog key) | "The subprocess channel has already been launched." | The already-launched failure's description |
| (none — literal, no catalog key) | "messages() has already been called; only one reader is supported." | The already-consumed failure's description |
| (none — literal, no catalog key) | "The subprocess channel's standard input has been closed." | The input-closed failure's description |
| (none — literal, no catalog key) | "Failed to launch the subprocess: %@" | The launch-failed failure's description, interpolated with the failure reason |
| (none — literal, no catalog key) | "The subprocess exited with status %d: %@" | The exited failure's description |
| (none — literal, no catalog key) | "The operation exceeded its %gs budget." | The budget-exceeded failure's description, interpolated with the elapsed seconds |
| (none — literal, no catalog key) | "[stderr truncated to the last 1048576 bytes]\n" | Prefix prepended to standard-error text when the tail cap trimmed the buffer |
| (none — literal, no catalog key) | "[stderr capture incomplete: the drain did not finish within 0.5s]\n" | Prefix prepended to standard-error text when the drain grace lapsed |

## Accessibility Options

Not applicable: this component presents no UI, so it responds to no platform display-accessibility setting.

## Feature Flags

Not applicable: this component contains no feature-flag or settings-key reference.

## Analytics

Not applicable: this component contains no analytics or event-tracking call.

## Privacy

- **Data handled**: The channel's configured arguments, environment, and any bytes sent to the child MAY carry a credential a caller placed into the child's command line, environment, or standard input; the child's standard output and standard error MAY likewise echo one back. Nothing in this component inspects any of that data — every byte is forwarded to the child process or handed back to the caller exactly as given or received, with no logging, redaction, or classification of its own.
- **Storage**: Nothing in this component performs storage. The channel holds standard-output frames only until a consumer reads them from the message stream, and holds standard error only in its capped, in-memory buffer for the channel's lifetime.
- **Transmission**: Nothing in this component performs network transmission; all I/O is local — pipes between this process and a spawned child.
- **Retention**: A decoded frame is retained only until its consumer reads it from the message stream; the channel's standard-error buffer is retained, capped at 1 MiB (tail-only), for the life of the channel and is released with it. The framing decoder's own buffer never exceeds 16 MiB for the newline-delimited and content-length-prefixed schemes, and holds nothing at all for the unframed scheme.

## Logging

Not applicable: this component contains no logging call of any kind — every diagnostic it produces is a typed failure or one of the two standard-error-text prefix strings described under Localization, not a log line.

## Platform Notes

- **SwiftUI**: The sources are `packages/apple/AgenticToolkit/Core/RPC/MessageFraming.swift`, `SubprocessChannel.swift`, `SubprocessChannel+Run.swift`, and `WallClockBudget.swift`, consumed directly by `PluginTransport.swift` (`AIPluginKit`, see `related`) and available to any other Foundation-based caller in the host app or a plugin bundle. They depend on `Foundation` (`Process`, `Pipe`, `FileHandle`, `Data`), `Dispatch` (`DispatchIO`, `DispatchQueue`), and `Darwin` (`fcntl`, `SIGTERM`/`SIGKILL`), and are themselves UI-framework-agnostic — a SwiftUI host consumes `SubprocessChannel`'s `AsyncThrowingStream<Data, Error>` identically to an AppKit one.
- **Compose**: `Process` has no Android/JVM equivalent for spawning arbitrary executables in most app sandboxes, so a Compose port of `SubprocessChannel` is realistically a JVM/desktop-only (not Android) concern — model it with `ProcessBuilder`/`Process`, writing to `outputStream` then closing it for EOF, and draining `inputStream`/`errorStream` on separate `Dispatchers.IO` coroutines rather than blocking the main dispatcher, matching the source's continuous-drain requirement for stderr. Reproduce `.newlineDelimited` with `BufferedReader.readLine()` (re-appending the stripped `\n`) or, for byte-exact fidelity, a manual scan for `0x0A`; reproduce `.contentLength` by scanning for the `\r\n\r\n` terminator manually, since no standard library type parses this framing directly. Model `withWallClockBudget` with two coroutines raced via `select`, cancelling — not joining — the loser, since `withTimeout`'s implicit cancellation-and-rethrow does not by itself let a caller distinguish "the operation lost the race" from "the operation was itself cancelled by something else," a distinction `WallClockBudgetExceeded` makes explicit.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive), model `SubprocessChannel` with `child_process.spawn`, writing to `.stdin` then calling `.stdin.end()` for the EOF `close-input-orderly` requires, and reading `.stdout`/`.stderr` as `Buffer` chunks (never decoded to a string on the stderr path, to preserve `stderr-data-raw`'s raw-bytes guarantee). Reproduce `.newlineDelimited` with a manual byte accumulator split on `0x0A` (not `readline.createInterface`, which strips the delimiter this contract requires kept) and `.contentLength` with a manual scan for `\r\n\r\n`. Model `withWallClockBudget` with `Promise.race` between the operation and a `setTimeout`-backed promise, paired with an `AbortController` so the losing side is actually cancelled rather than left running unobserved — `Promise.race` alone only stops awaiting the loser, it does not cancel it, which is the exact gap `budget-cancels-not-awaits-loser` requires closing.
- **AppKit / UIKit**: These sources are UI-framework-agnostic like the SwiftUI note above; only the application embedding them differs, never this contract. `MessageFraming` is a `Sendable` enum with cases `.newlineDelimited`, `.contentLength`, `.unframed`, each backing a `frame(_:)` encoding method; `MessageFramingDecoder` is a `struct` with `mutating` methods (`consume(_:)`, `finish()`), created and held as exactly one instance per stream, consumed only from that stream's own pump task, matching **decoder-single-owner**. `SubprocessChannel` is declared as a Swift `actor`, spawning a child via `Process` and three `Pipe`s; every actor-isolated method call against one instance (`launch`, `messages`, `send`, `sendRaw`, `closeInput`, `standardErrorText`, `standardErrorData`, `terminate`) is serialized by that actor, matching **channel-calls-serialized**, while `waitUntilExit` is declared `nonisolated` so awaiting it never blocks the actor. `SubprocessChannel.Configuration` and `SubprocessChannel.RunResult` are declared `Sendable` value types, matching **configuration-and-result-thread-safe**. `launch()` disables `SIGPIPE` via `fcntl`'s `F_SETNOSIGPIPE`, scoped to the child's stdin write descriptor, before calling `process.run()` (**launch-sigpipe-suppression**); `EnvironmentPolicy.mergeOverParent` merges the configured environment over `ProcessInfo.processInfo.environment`. The stdout pump and stderr drain use `DispatchIO` at a 64 KiB high-water mark (`SubprocessChannel.readChunkSize`), and every named constant in Configuration above (`maximumFrameBytes`, `terminationGraceSeconds`, `standardErrorDrainGraceSeconds`, `messagePumpDrainGraceSeconds`, `maximumStandardErrorBytes`, `maximumWallClockBudgetSeconds`) is a Swift static constant on `MessageFramingDecoder`, `SubprocessChannel`, or `WallClockBudget.swift` respectively (public where a caller reads it, private/file-private otherwise). `HandleCloser.close()` (`SubprocessChannel.swift`) calls `try? handle.close()`, silently discarding whatever error each `DispatchIO` cleanup handler reports — the gap tracked by **descriptor-close-failure-signal**. `Process` is unavailable on iOS, so a UIKit host on iOS cannot use `SubprocessChannel` as written; only the `MessageFraming`/`MessageFramingDecoder`/`WallClockBudget` parts port to iOS. `withWallClockBudget(_:_:)` races two unstructured `Task`s resumed through a single `CheckedContinuation`, never a `withThrowingTaskGroup` (**budget-race-not-scoped-join**), and every failure type mentioned above — `MessageFramingError` (`.malformedHeader`, `.missingContentLength`, `.truncatedMessage`, `.frameSizeExceeded`), `ChannelError` (`.notLaunched`, `.alreadyLaunched`, `.alreadyConsumed`, `.inputClosed`, `.launchFailed`, `.exited`), and `WallClockBudgetExceeded` — conforms to `LocalizedError`, with `errorDescription` producing the literal strings in Localization above.
- **WinUI 3**: Model `SubprocessChannel` with `System.Diagnostics.Process`/`ProcessStartInfo`, setting `RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` to `true`; per `environment-replace-policy`'s replace semantics, call `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `environment`, since `EnvironmentVariables` starts pre-populated with the parent's own variables — the opposite of this source's default. Write to `StandardInput.BaseStream` then call `StandardInput.Close()` for `close-input-orderly`'s EOF, and read `StandardError.BaseStream` into a `byte[]` (never `StandardError.ReadToEndAsync()`'s decoded `string`) to reproduce `stderr-data-raw`'s raw-bytes guarantee; await exit via `Process.WaitForExitAsync(cancellationToken)` rather than the blocking `WaitForExit()`, matching `exit-status-no-invented-value`'s throw-rather-than-invent contract. Represent the stdout message stream as an `IAsyncEnumerable<byte[]>` built over an unbounded `System.Threading.Channels.Channel<byte[]>`, matching this source's own unbounded `AsyncThrowingStream` buffering policy, and call `Process.Kill()` (not `Process.Kill(entireProcessTree: true)`, to preserve `termination-signal-scope`'s direct-child-only rule) from a `CancellationToken` registration in place of `terminate()` — noting Windows has no SIGTERM-equivalent graceful-then-forceful escalation, so a port that wants `termination-sequence`'s two-stage grace period must implement its own (for example `CloseMainWindow()` followed by a timed `Kill()`). Model `MessageFramingDecoder` as a mutable class or a `struct` with `ref`-like usage confined to one owner, matching `decoder-single-owner`. Model `withWallClockBudget` with `Task.WhenAny` racing the operation `Task` against `Task.Delay(TimeSpan, CancellationToken)`, explicitly calling `Cancel()` on a `CancellationTokenSource` tied to the losing task rather than relying on `Task.WhenAny` alone, which — like `Promise.race` — only stops awaiting the loser and does not cancel it by itself.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/RPC/` |

## Design Decisions

**Decision**: `MessageFramingDecoder`'s newline scan tracks a `scanCursor` that is shifted (not reset to `0`) every time completed frames are cut off the front of the buffer, so a subsequent `consume(_:)` call resumes scanning from where the previous call left off rather than rescanning the buffer's unconsumed tail from the start.
**Rationale** (Swift implementation): `MessageFraming.swift`'s own doc comment states the alternative was measured at 114 seconds to decode a single 256 KB line — an O(n²) cost from rescanning already-examined bytes on every call. The cursor is what makes decoding linear in the number of bytes fed rather than quadratic, and is why `decoder-feed-chunk-sized-input` is phrased as a SHOULD for callers rather than a correctness requirement: feeding the decoder one byte at a time still produces correct frames, it is only slow.
**Approved**: pending

**Decision**: `terminate()` distinguishes a child's own end-of-file from a teardown-induced one (`DescriptorReader.reachedEndOfStreamNaturally`) by recording "a teardown has begun" (`markTornDown()`) *before* sending SIGTERM, and only flushes `MessageFramingDecoder.finish()` on the pump's exit when that flag was never set for a live, un-EOF'd descriptor.
**Rationale** (Swift implementation): SIGTERM kills an ordinary child, the kernel closes its write end, and a genuine end-of-file arrives well before `terminate()`'s own `stopAll()` closes anything — so end-of-file alone cannot tell the pump whether the child finished speaking on its own or was shot mid-sentence. Reading every end-of-file as "natural" would flush the decoder on exactly the forced-shutdown path this distinction exists to protect, fabricating a whole message out of half of one for `.newlineDelimited`, or turning an orderly kill into a thrown `truncatedMessage` for `.contentLength`.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/networking/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
