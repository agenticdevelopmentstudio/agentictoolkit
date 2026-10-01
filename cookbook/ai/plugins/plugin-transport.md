---
id: 7d5c5a1f-30df-460e-b6c4-7cfe9ab42784
title: Plugin Transport
domain: agentictoolkit://cookbook/ai/plugins/plugin-transport
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Drives one request specification to completion over HTTP or a local
  subprocess and streams the decoded stream events, owning all networking and
  process I/O.
platforms:
- swift
- macos
tags:
- ai-plugin
- transport
- streaming
- subprocess
- concurrency
depends-on:
- agentictoolkit://cookbook/ai/plugins/ai-plugin
- agentictoolkit://cookbook/ai/plugins/request-spec
- agentictoolkit://cookbook/ai/plugins/stream-event
related:
- agentictoolkit://cookbook/ai/chat/daemon-ai-chat
references: []
approved-by: ''
approved-date: ''
---

# Plugin Transport

## Overview

The plugin transport is the engine that drives one request specification to
completion and streams the decoded stream events back to the host, regardless
of whether the plugin that built the spec chose an HTTP request or a local
subprocess. It is the one place in the plugin kit that performs actual
networking or spawns a process; a plugin conformer only describes a request
(the request specification) and decodes the response bytes (its stream
decoder), and running a spec through the transport is the sole operation that
turns that description into an HTTP request or a subprocess-driven child
process. It enforces the spec's timeout as a true wall-clock budget over the
whole request, maps that budget's expiry into its own timed-out error, and,
for the command transport, delegates the actual child-process lifecycle to a
subprocess channel.

## Behavioral Requirements

- **single-entry-point**: The plugin transport MUST expose exactly one public
  operation — running a request specification against a plugin, which
  returns a stream of stream events — as the sole way to drive a request.
- **stateless-invocation**: The plugin transport MUST hold no stored state of
  its own — it is a stateless namespace of operations, not an instance — so
  two concurrent, independent calls to run a spec MUST NOT interfere with one
  another; each call creates its own unit of work, its own decoder, and (for
  a command spec) its own subprocess channel.
- **transport-dispatch**: Running a request specification MUST dispatch on
  the spec's transport kind — HTTP to the HTTP path, command to the command
  path — and MUST NOT perform both for a single spec.
- **wall-clock-enforcement**: Running a request specification MUST wrap
  whichever transport path it dispatches to in a wall-clock budget bounded by
  the spec's timeout, bounding the entire request — connection, streaming,
  and (for a command) process exit — by wall-clock time rather than by an
  idle timeout that resets on every received byte.
- **timeout-error-mapping**: Running a request specification MUST catch a
  thrown budget-exceeded condition and finish the returned stream with a
  timed-out error carrying the elapsed seconds in its place, never surfacing
  the budget-exceeded condition itself to the caller.
- **error-passthrough**: Running a request specification MUST propagate any
  error other than the budget-exceeded condition to the stream's consumer
  unchanged, without wrapping it in a transport-error case.
- **stream-completion-on-success**: Running a request specification MUST
  finish the stream with no error once the dispatched transport path returns
  without throwing.
- **consumer-cancellation-propagation**: Running a request specification MUST
  cancel its internal unit of work when the returned stream's consumer stops
  iterating or is cancelled.
- **http-request-construction**: The HTTP path MUST build a request from the
  spec's URL, setting its method to the spec's method, applying every header
  entry, and setting the request body to the spec's body.
- **http-idle-timeout-set**: The HTTP path MUST also set the request's own
  idle-timeout value to the spec's timeout, even though this alone is an idle
  timeout that resets on every received byte and is therefore insufficient
  as a wall-clock bound — the wall-clock guarantee comes only from
  wall-clock-enforcement above.
- **http-streaming-fetch**: The HTTP path MUST fetch the response by
  streaming its bytes as they arrive rather than buffering the complete
  response before any processing begins.
- **http-response-type-check**: The HTTP path MUST throw an invalid-response
  error if the received response is not a well-formed HTTP response.
- **http-success-range**: The HTTP path MUST treat a response as successful
  if and only if its status code falls in 200–299; every other status code
  MUST be treated as a failure.
- **http-error-body-drain**: On a non-2xx status, the HTTP path MUST fully
  drain the response body into a buffer before asking the plugin to describe
  the error from it.
- **http-error-message-fallback**: On a non-2xx status, the HTTP path MUST
  use the plugin's error-description operation's returned string as the
  resulting error's message when it is non-empty, and MUST fall back to the
  literal string "HTTP <status>" when the plugin declines to describe it,
  then MUST throw an HTTP-failure error carrying the status and message.
- **http-success-decode**: On a 2xx status, the HTTP path MUST ask the plugin
  for a fresh decoder exactly once and pass the still-streaming response
  bytes and that decoder to the byte-pumping logic.
- **command-channel-configuration**: The command path MUST construct its
  subprocess channel with a replace-the-environment policy and
  newline-delimited framing, using the spec's executable path, arguments, and
  environment verbatim.
- **command-launch**: The command path MUST launch the child process before
  writing any standard input or reading any output.
- **command-stdin-write**: The command path MUST write a non-empty standard
  input payload to the channel unframed, never through the framing-aware
  send operation, so no delimiter is appended to the payload.
- **command-stdin-close**: The command path MUST close the channel's input
  unconditionally immediately after the standard-input write step, whether
  or not standard input was supplied, so the child always sees end-of-file on
  its input.
- **command-frame-consumption**: The command path MUST ask the plugin for a
  fresh decoder exactly once, then feed every frame produced by the
  channel's message stream to that decoder and yield each returned event to
  the continuation, in the order the frames arrive.
- **command-finish-before-status**: The command path MUST check for
  cancellation, and — only if that check does not throw — flush the
  decoder's trailing state and yield its events, before awaiting the child's
  exit status, so a completed answer is always delivered before the
  transport asks whether the child succeeded.
- **command-finish-skipped-on-cancellation**: If that cancellation check
  throws at that checkpoint, the command path MUST propagate the resulting
  error and MUST NOT flush the decoder's trailing state — a cancelled run
  never receives a flush of the decoder's trailing state.
- **command-exit-status-check**: The command path MUST await the child's
  exit status and treat exactly a zero status as success.
- **command-terminate-always**: The command path MUST terminate the channel
  once the exit status is known, on both the success and the failure branch
  of the status check, and MUST terminate it again from its outer
  failure-recovery step if any earlier step throws, so termination runs
  exactly once on the success path and again as cleanup on every throwing
  path.
- **command-nonzero-exit-error**: On a nonzero exit status, the command path
  MUST fetch the child's raw standard-error bytes — never a decoded text
  form — and pass them unmodified to the plugin's error-description
  operation, falling back to the literal string "Command exited with status
  <status>" when the plugin declines to describe it, then MUST throw a
  command-failure error carrying the status and message.
- **command-cleanup-rethrows-original-error**: The command path's outer
  failure-recovery step MUST terminate the channel and then rethrow the
  original caught error unchanged — it MUST NOT substitute or wrap that
  error.
- **byte-pump-line-framing**: The byte-pumping logic MUST accumulate incoming
  bytes into a buffer and, on each byte equal to the newline byte, feed the
  decoder the buffer including that trailing newline byte, then clear the
  buffer.
- **byte-pump-cancellation-check**: The byte-pumping logic MUST check for
  cancellation once for every byte received, before appending it to the
  buffer.
- **byte-pump-trailing-remainder**: Once the byte sequence ends, the
  byte-pumping logic MUST feed the decoder any remaining non-empty,
  unterminated buffer content; it MUST NOT feed the decoder an empty buffer.
- **byte-pump-finish-call**: The byte-pumping logic MUST flush the decoder's
  trailing state and yield its events exactly once, after the
  trailing-remainder step, whenever the byte loop completes without
  throwing.
- **byte-pump-cancellation-skips-finish**: If the cancellation check throws
  inside the byte loop, the byte-pumping logic MUST propagate that error
  immediately and MUST NOT reach the trailing-remainder or flush steps.
- **decoder-per-request**: Both the HTTP path and the command path MUST ask
  the plugin for a fresh decoder exactly once per run invocation, never
  reusing a decoder instance across two requests.
- **decoder-task-confinement**: The decoder created for one run invocation
  MUST be created and consumed only inside the single unstructured unit of
  work that running a request specification starts — never handed to, or
  invoked from, any other concurrent execution context — matching the
  decoder's own not-shareable-across-contexts contract (see the sibling
  stream-event recipe).
- **single-attempt**: Running a request specification MUST perform the
  described request exactly once per invocation; there is no retry loop,
  backoff, or repeated attempt at either transport path for a single run
  invocation.
- **subprocess-cancellation-eager-kill**: For a command request, cancelling
  the task that iterates the returned stream MUST terminate the child
  process eagerly rather than waiting for it to exit on its own terms —
  cancelling that task cancels the frame-consuming loop over the channel's
  message stream, whose termination cancels the subprocess channel's own
  internal pump, whose cancellation handler signals the child.
- **raw-error-passthrough**: Any failure that is neither a non-2xx HTTP
  status nor a nonzero subprocess exit (for example a connectivity failure,
  or a launch failure from the subprocess channel itself) MUST reach the
  stream's consumer as its original, unwrapped error, with neither transport
  path catching or reclassifying it further.

## Appearance

Not applicable — this is a request-transport engine (HTTP and subprocess
I/O), not a visual component.

## States

Not applicable — this is a request-transport engine, not a visual component;
its only runtime state machine is the request lifecycle described under
Behavioral Requirements above (dispatch → stream → success/timeout/error),
not a UI visual-state table.

## Accessibility

Not applicable — this is a request-transport engine with no user interface
of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| plugin-transport-001 | wall-clock-enforcement, timeout-error-mapping | A command request running a shell command that prints "tick" every 0.05s indefinitely, given a 0.5s timeout. | The transport throws a timed-out error; at least one text-delta event was yielded before the cut-off; total elapsed time is well under the trickle's natural duration, proving the cut-off is wall-clock, not idle-based. |
| plugin-transport-002 | command-frame-consumption, byte-pump-finish-call (command path) | A command request running a shell command that prints "hello" once, given a 10s timeout. | The stream completes normally; the concatenated text-delta text contains "hello". |
| plugin-transport-003 | command-stdin-write, command-stdin-close | A command request running a pass-through command (echoing stdin to stdout) with standard input set to a two-line payload whose second line has no trailing newline. | The reassembled reply equals the payload exactly, byte for byte, with no appended newline — proving the unframed write was used, and that closing input ran so the child could reach end-of-file. |
| plugin-transport-004 | command-exit-status-check, command-nonzero-exit-error | A command request running a shell command that writes "boom" to standard error and exits with status 3, against a plugin whose error-description operation echoes the status and body. | Throws a command-failure error carrying status 3 and a message containing "boom". |
| plugin-transport-005 | command-nonzero-exit-error | A command request running a shell command that writes specific non-UTF-8 bytes to standard error and exits with status 3, against a plugin recording the exact bytes handed to its error-description operation. | The plugin's recorded body equals the exact byte sequence written to standard error, including the invalid byte, unmodified — proving the raw-bytes form, not a decoded-text form, was used. |
| plugin-transport-006 | command-channel-configuration | A command request naming one environment variable, run with a distinct parent-only environment variable set beforehand in the host process. | The child's reported environment contains the given variable and does not contain the parent-only variable — confirming the replace (not merge) environment policy. |
| plugin-transport-007 | command-frame-consumption, byte-pump-line-framing (framing parity), command-finish-before-status | A command request running a shell command that prints three newline-terminated lines followed by an unterminated trailing chunk, against a decoder that logs every payload it consumes and its flush call. | The decoder receives exactly the three lines (each including its newline) followed by the unterminated trailing chunk, in order, followed by exactly one flush call; the reassembled reply matches the full output exactly. |
| plugin-transport-008 | command-frame-consumption | A command request running a shell command that prints two newline-terminated lines with no trailing content after the final newline. | The decoder receives exactly the two lines — no spurious empty trailing frame for output that already ends in a newline. |
| plugin-transport-009 | http-response-type-check | An HTTP request whose response is not a well-formed HTTP response. | Throws an invalid-response error before any bytes reach a decoder. |
| plugin-transport-010 | http-success-range, http-error-message-fallback | An HTTP request that receives a 404 response with an empty body, against a plugin whose error-description operation returns nothing. | Throws an HTTP-failure error carrying status 404 and message "HTTP 404" — the literal fallback string, since the plugin declined to describe it. |
| plugin-transport-011 | http-error-body-drain, http-error-message-fallback | An HTTP request that receives a 500 response whose body is a JSON error payload, against a plugin whose error-description operation returns "rate limited" when it recognizes that shape. | Throws an HTTP-failure error carrying status 500 and message "rate limited" — the full body reached the plugin's error-description operation before the throw. |
| plugin-transport-012 | consumer-cancellation-propagation, subprocess-cancellation-eager-kill | A command request running a 30-second sleep with a 60-second timeout; the consuming loop's enclosing task is cancelled shortly after starting. | The child process is terminated well before its natural 30-second sleep completes and before the 60-second budget would otherwise expire. |
| plugin-transport-013 | timeout-error-mapping, error-passthrough | Running a request specification whose internal operation throws a plugin-defined error unrelated to the budget-exceeded condition. | The returned stream finishes with that exact error instance, not a transport-error case. |

## Edge Cases

- **Null/empty input**: An empty headers map MUST leave the request with no
  additional header fields set beyond its own defaults. An empty body MUST
  produce a request with no body. An empty standard-input payload MUST cause
  the command path to skip the write step but still MUST close the channel's
  input (command-stdin-close). An empty arguments list and an empty
  environment map MUST be accepted as ordinary, valid values — an empty
  arguments list runs the executable with none, and an empty environment
  leaves the child inheriting the host's own environment per the replace
  policy's own documented behavior for an empty value.
- **Boundary values**: A timeout at or below zero MUST cause the wall-clock
  budget to expire immediately, per the wall-clock budget's own documented
  mapping ("at or below zero → expire immediately") — the transport passes
  the timeout through unvalidated. A timeout at or above roughly one year,
  or a non-finite value, MUST start no timer at all, per the same mapping's
  "no budget" case, so the request MUST run to natural completion or to the
  caller's own cancellation with no timed-out error ever thrown.
- **Concurrent access**: The transport MUST support an arbitrary number of
  concurrent, independent run invocations without interference, per
  stateless-invocation — each call owns its own unit of work, decoder
  instance, and (for a command spec) its own subprocess channel, with no
  state shared across calls.
- **Error states**: A non-2xx HTTP status MUST surface as an HTTP-failure
  error; a nonzero subprocess exit MUST surface as a command-failure error;
  a malformed HTTP response MUST surface as an invalid-response error; any
  other failure (a connectivity error, a channel launch failure, a framing
  error from the subprocess channel) MUST surface unwrapped, per
  raw-error-passthrough.
- **Offline/disconnected state**: If the HTTP byte stream throws mid-transfer
  (e.g. a dropped connection), the byte-pumping logic's iteration MUST
  propagate that error immediately; the trailing-remainder feed and the
  flush step MUST NOT run — any bytes still buffered in the pump's own
  accumulator are discarded, and the decoder's own internal buffer is
  likewise never flushed. For the command transport, if the channel's
  message-stream iteration throws (e.g. a framing failure surfaced by the
  subprocess channel), the command path's outer failure-recovery step MUST
  terminate the channel and rethrow that error unchanged.
- **Cancellation**: Cancelling the task that iterates the stream returned by
  running a request specification MUST cancel that run's internal unit of
  work (consumer-cancellation-propagation), which for a command request MUST
  terminate the child process eagerly (subprocess-cancellation-eager-kill)
  rather than waiting for a natural exit; in both transports, a cancellation
  observed at the cancellation-check checkpoint MUST prevent the trailing
  flush from ever running (command-finish-skipped-on-cancellation,
  byte-pump-cancellation-skips-finish) — a cancelled run never receives a
  flush of the decoder's trailing state, only whatever events were already
  yielded.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Request specification | request specification value | none — required | Describes the HTTP or subprocess request to perform, including its wall-clock timeout (see the sibling request specification recipe). |
| Plugin | plugin reference | none — required | Supplies a fresh decoder for turning response bytes into stream events, and an error-description operation for translating a failure into a human-readable message (see the sibling plugin recipe). |

This component defines no environment variable and no settings key of its
own; every value it operates on arrives as one of the two parameters above,
ultimately sourced from the request specification the caller supplies.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination — the address it uses reaches an AI provider's HTTP endpoint,
not an app deep link.

## Localization

This component contains hardcoded, unlocalized English string literals
presented to callers via its own error descriptions and the plugin's
error-description fallback paths. There is no string-catalog key for any of
them; the literal itself is both the value and its own identifier.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "The server returned an invalid response." | The invalid-response error's description |
| (none — literal, no catalog key) | "The request exceeded its %gs budget." | The timed-out error's description, interpolated with the elapsed seconds |
| (none — literal, no catalog key) | "HTTP %d" | Fallback message for the HTTP-failure error when the plugin's error-description operation returns nothing |
| (none — literal, no catalog key) | "Command exited with status %d" | Fallback message for the command-failure error when the plugin's error-description operation returns nothing |

## Accessibility Options

Not applicable: this component presents no UI, so it responds to no Reduce
Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this component contains no feature-flag or settings-key
reference of its own.

## Analytics

Not applicable: this component contains no analytics or event-tracking call.

## Privacy

- **Data handled**: A request specification's headers, body, standard input,
  and environment MAY each carry a credential a plugin embedded into the
  request description (see the sibling request specification recipe's own
  Privacy section); this component itself has no knowledge of which values
  are secret — it forwards every one of them to the outgoing request or to
  the spawned subprocess exactly as given, and forwards every response byte
  and every standard-error byte to the plugin's decoder and
  error-description operation exactly as received, with no inspection of
  its own.
- **Storage**: This component performs no storage of its own — it holds
  request and response data only in memory, for the lifetime of one run
  invocation.
- **Transmission**: For an HTTP request, the transport transmits the headers
  and body to the given address; for a command request, it writes standard
  input and environment only to a locally spawned child process — no network
  transmission occurs for the command path itself, only whatever the spawned
  process independently performs.
- **Retention**: None. A response's bytes and any decoded stream events exist
  only for the duration of the stream a caller iterates; nothing is cached
  or retained past that iteration, except for the subprocess channel's own
  bounded (1 MB) standard-error buffer, which is released with the channel.

## Logging

Not applicable: this component contains no logging call of any kind — it is
I/O and control-flow logic with no diagnostic side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/PluginTransport.swift`, consumed by `DaemonAIChat.swift` (same directory) and by every host chat backend that drives an `AIPlugin`. It depends on `Foundation`'s `URLSession`/`URLRequest`, on `AgenticToolkitCore`'s `SubprocessChannel` and `withWallClockBudget`, and is itself UI-framework-agnostic — a SwiftUI host consumes the `AsyncThrowingStream<AIStreamEvent, Error>` it returns identically to an AppKit one. Concretely: the transport type is the enum `PluginTransport`; its single entry point is `run(spec:plugin:) -> AsyncThrowingStream<AIStreamEvent, Error>`; the timeout-error and error-passthrough requirements are enforced through `withWallClockBudget`, `WallClockBudgetExceeded`, and the case `TransportError.timedOut(after:)`; the HTTP path is `runHTTP`, using `URLRequest`, `URLSession.shared.bytes(for:)`, `HTTPURLResponse`, and throwing `TransportError.invalidResponse` / `TransportError.http(status:message:)`; the command path is `runCommand`, using `SubprocessChannel` (`environmentPolicy: .replace`, `framing: .newlineDelimited`), `channel.launch()`, `sendRaw(_:)`, `closeInput()`, `channel.messages()`, `channel.waitUntilExit()`, `channel.terminate()`, `channel.standardErrorData()`, and throwing `TransportError.commandFailed(status:message:)`; the byte-pumping logic is the free function `pump(bytes:through:into:)`; and every cancellation check is `Task.checkCancellation()` inside the one unstructured `Task` the call starts.
- **Compose**: Model `runHTTP` with OkHttp's `Call` and a streaming `ResponseBody` source, wrapped in `kotlinx.coroutines.withTimeout(spec.timeoutMillis)` to reproduce the wall-clock (not idle) bound `withWallClockBudget` provides — OkHttp's own `callTimeout`/`readTimeout` settings are per-operation, idle-style timeouts, the same gap the source's own doc comment calls out for `URLRequest.timeoutInterval`. Model `runCommand` with `ProcessBuilder`/`Runtime.exec`, writing to the process's output stream then closing it for EOF, and draining stdout line-by-line (matching `.newlineDelimited`) on a background dispatcher; note that most Android app sandboxes cannot spawn arbitrary executables, so a Compose/Android port would typically support only the HTTP path, as the sibling `AIRequestSpec` recipe's Compose note also observes. Use `callbackFlow`/`channelFlow` with `awaitClose` as the `AsyncThrowingStream` equivalent, cancelling the underlying `Call` or `Process` from `awaitClose` the way `continuation.onTermination` cancels `PluginTransport`'s internal `Task`.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive), model `runHTTP` with `fetch` plus a `ReadableStream` reader, tying an `AbortController` both to consumer cancellation and to a `setTimeout(timeout)` for the wall-clock bound — matching the sibling `AIRequestSpec` recipe's own React/Web note. Model `runCommand` with `child_process.spawn`, writing to `.stdin` then calling `.stdin.end()` for EOF, and reading `.stdout` through a `readline.createInterface` (or manual `\n`-splitting) to reproduce `.newlineDelimited` framing; read `.stderr` as a `Buffer` (never decoded to a string) to preserve `command-nonzero-exit-error`'s raw-bytes guarantee. Represent the returned sequence as an `async function*` generator or a `ReadableStream<AIStreamEvent>`, calling `AbortController.abort()`/killing the child process when the consumer stops iterating, in place of `continuation.onTermination`.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model `runHTTP` with `System.Net.Http.HttpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead)`, reading the response via `Content.ReadAsStreamAsync()` so the body streams rather than buffers, exactly as `URLSession.shared.bytes(for:)` does; bound the whole call — not just `HttpClient.Timeout`, which is a per-operation idle-style timeout with the same insufficiency the source's doc comment calls out for `URLRequest.timeoutInterval` — with a `CancellationTokenSource` whose `CancelAfter(spec.Timeout)` is passed to `SendAsync`, reproducing `wall-clock-enforcement` without porting the source's custom `withWallClockBudget` race. Model `runCommand` with `System.Diagnostics.Process`/`ProcessStartInfo`, setting `RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` to `true` and, per `command-channel-configuration`'s replace semantics, calling `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `environment` (since `EnvironmentVariables` starts pre-populated with the parent's own variables, the opposite of the source's default); write `stdin` to `StandardInput.BaseStream` then call `StandardInput.Close()` for the EOF `command-stdin-close` requires, read `StandardError.BaseStream` into a `byte[]` (never `StandardError.ReadToEndAsync()`'s decoded `string`) to reproduce `command-nonzero-exit-error`'s raw-bytes guarantee, and await exit via `Process.WaitForExitAsync(cancellationToken)` rather than the blocking `WaitForExit()`. Represent the returned sequence as an `IAsyncEnumerable<AiStreamEvent>` built over a `System.Threading.Channels.Channel<AiStreamEvent>` (unbounded, matching the source's own unbounded `AsyncThrowingStream` buffering policy) in place of Swift's `AsyncThrowingStream`, and call `Process.Kill()` from the `CancellationToken`'s registration to reproduce `subprocess-cancellation-eager-kill` — noting that Windows has no SIGTERM-equivalent graceful-then-forceful escalation the way `SubprocessChannel.terminate()` does, so a port that wants an analogous grace period must implement its own (e.g. `Process.CloseMainWindow()` followed by a timed `Process.Kill()`).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/PluginTransport.swift` |

## Design Decisions

**Decision**: The command transport's stderr is read via `channel.standardErrorData()` — raw, undecoded bytes — rather than `channel.standardErrorText()`, and the same raw-`Data` contract is used for the HTTP transport's error body. (Apple platform implementation.)
**Rationale**: `standardErrorText()` prepends diagnostic prefixes (a truncation or drain-incompleteness marker) and falls back to Latin-1 for non-UTF-8 content, re-encoding every byte at or above `0x80`; a plugin's `describeError(status:body:)` parses the provider's or child's own error format, and handing it channel bookkeeping or a re-encoded byte stream instead of the child's actual bytes would corrupt exactly the diagnosis it is trying to make (`PluginTransport.swift`, which states this explicitly).
**Approved**: pending

**Decision**: `runCommand` writes `stdin` via `sendRaw(_:)`, which appends no delimiter, rather than the framing-aware `send(_:)`. (Apple platform implementation.)
**Rationale**: The stdin payload is an opaque blob (a prompt, a file) with no message boundary of its own to declare; framing it with `.newlineDelimited`'s appended `0x0A` would append a byte the child never received before, which the source's own doc comment states directly.
**Approved**: pending

**Decision**: `PluginTransport` performs no retry or backoff of any kind — a failed request (an HTTP error, a nonzero exit, a timeout, or any other thrown error) is reported to the caller exactly once, on the first and only attempt.
**Rationale**: The type's scope, per its own doc comment, is to drive one described request to completion and report the outcome; whether and how to retry is a decision the host or caller can make with full knowledge of the failure (its `TransportError` case, or the original unwrapped error per `raw-error-passthrough`), not one `PluginTransport` can make on the caller's behalf without also owning a retry policy (backoff duration, retry count, which failures are retryable) that the source never expresses.
**Approved**: pending

**Decision**: When `spec.timeout` expires, the returned stream finishes with `TransportError.timedOut` immediately, but the underlying HTTP transfer or child process is only cancelled — not awaited — by the timed-out racer, so cleanup (closing the connection, or `SubprocessChannel.terminate()`'s SIGTERM-then-SIGKILL escalation, which can take up to roughly 2.5 seconds) continues asynchronously after the caller has already received the error. (Apple platform implementation.)
**Rationale**: `WallClockBudget.swift`'s own doc comment states this is deliberate: awaiting the loser would mean a budget that "genuinely bounds wall-clock time" only when the operation it wraps happens to cooperate with cancellation promptly, which blocking I/O and a `Process` wait cannot guarantee. The trade is that a `TransportError.timedOut` observed by the caller does not guarantee the child process or HTTP connection has already been torn down at that instant — only that teardown has been requested.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

`separation-of-concerns` passes because `PluginTransport` is, by its own doc comment, "the one place in the system that performs networking or spawns a process" — every `AIPlugin` conformer only describes and decodes. `explicit-error-handling` passes because every failure path maps to a named `TransportError` case or is deliberately passed through unwrapped (`raw-error-passthrough`), with no silent catch-and-ignore anywhere in the source. `test-pyramid` is partial because `PluginTransportTests.swift` and `PluginTransportFramingTests.swift` exercise the command transport thoroughly with hermetic `/bin/sh` children, but the given sources contain no equivalent unit test for `runHTTP`. `input-sanitization` is partial because `runHTTP` and `runCommand` forward `headers`, `body`, `executableURL`, `arguments`, and `environment` to `URLRequest`/`Process` without any validation of their own — the open question of whether that should happen here rather than in the plugin or the host is the same one the sibling `AIRequestSpec` recipe records. `fault-tolerance` passes because every defined failure mode (non-2xx status, nonzero exit, invalid response, budget expiry) degrades to a typed, thrown error rather than a hang or a crash. `error-recovery` fails because, per the `single-attempt` Design Decision above, no failure is ever retried or recovered from within this component. `no-pii-in-logs` passes trivially, since the component performs no logging at all. `string-externalization` fails because the four literals under Localization above are hardcoded English with no string-catalog key.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
