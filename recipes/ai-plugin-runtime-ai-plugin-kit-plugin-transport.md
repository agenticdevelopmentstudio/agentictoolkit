---
id: 7d5c5a1f-30df-460e-b6c4-7cfe9ab42784
title: PluginTransport
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-plugin-transport
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Drives one AIRequestSpec to completion over HTTP or a local subprocess and
  streams the decoded AIStreamEvents, owning all networking and process I/O.
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
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-request-spec
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-stream-event
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-daemon-ai-chat
references: []
approved-by: ''
approved-date: ''
---

# PluginTransport

## Overview

`PluginTransport` (`packages/apple/AgenticToolkit/AIPluginKit/PluginTransport.swift`) is the Foundation-only Swift `enum` that drives one `AIRequestSpec` to completion and streams the decoded `AIStreamEvent`s back to the host, regardless of whether the plugin that built the spec chose an HTTP request or a local subprocess. It is the one place in `AIPluginKit` that performs actual networking or spawns a process; an `AIPlugin` conformer only *describes* a request (`AIRequestSpec`) and *decodes* the response bytes (`AIStreamDecoder`), and `PluginTransport.run(spec:plugin:)` is the sole caller that turns that description into an `URLSession` request or a `SubprocessChannel`-driven child process. It enforces `spec.timeout` as a true wall-clock budget over the whole request, maps that budget's expiry into its own `TransportError.timedOut`, and, for the command transport, delegates the actual child-process lifecycle to `SubprocessChannel` (`packages/apple/AgenticToolkit/Core/RPC/SubprocessChannel.swift`).

## Behavioral Requirements

- **single-entry-point**: `PluginTransport` MUST expose exactly one public operation, `run(spec: AIRequestSpec, plugin: any AIPlugin) -> AsyncThrowingStream<AIStreamEvent, Error>`, as the sole way to drive a request.
- **stateless-invocation**: `PluginTransport` MUST hold no stored state of its own — it is declared as a `public enum` with no cases, used purely as a namespace for `static` functions — so two concurrent, independent calls to `run(spec:plugin:)` MUST NOT interfere with one another; each call creates its own `Task`, its own decoder, and (for a command spec) its own `SubprocessChannel`.
- **transport-dispatch**: `run(spec:plugin:)` MUST dispatch on `spec.transport` — `.http` to `runHTTP`, `.command` to `runCommand` — and MUST NOT perform both for a single `spec`.
- **wall-clock-enforcement**: `run(spec:plugin:)` MUST wrap whichever transport path it dispatches to in `withWallClockBudget(spec.timeout) { ... }`, bounding the *entire* request — connection, streaming, and (for a command) process exit — by wall-clock time rather than by an idle timeout that resets on every received byte.
- **timeout-error-mapping**: `run(spec:plugin:)` MUST catch a thrown `WallClockBudgetExceeded` and finish the returned stream with `TransportError.timedOut(after: expired.seconds)` in its place, never surfacing `WallClockBudgetExceeded` itself to the caller.
- **error-passthrough**: `run(spec:plugin:)` MUST propagate any error other than `WallClockBudgetExceeded` to the stream's consumer unchanged, via `continuation.finish(throwing: error)`, without wrapping it in a `TransportError` case.
- **stream-completion-on-success**: `run(spec:plugin:)` MUST call `continuation.finish()` with no error once the dispatched transport path returns without throwing.
- **consumer-cancellation-propagation**: `run(spec:plugin:)` MUST cancel its internal `Task` when the returned stream's consumer stops iterating or is cancelled, via `continuation.onTermination = { _ in task.cancel() }`.
- **http-request-construction**: `runHTTP` MUST build a `URLRequest` from the spec's `url`, setting `httpMethod` to `method.rawValue`, applying every `headers` entry via `setValue(_:forHTTPHeaderField:)`, and setting `httpBody` to `body`.
- **http-idle-timeout-set**: `runHTTP` MUST also set `URLRequest`'s own `timeoutInterval` to `spec.timeout`, even though the source's own doc comment states this alone is an idle timeout that resets on every received byte and is therefore insufficient as a wall-clock bound — the wall-clock guarantee comes only from `wall-clock-enforcement` above.
- **http-streaming-fetch**: `runHTTP` MUST fetch the response via `URLSession.shared.bytes(for:)`, streaming the body byte by byte rather than buffering the complete response before any processing begins.
- **http-response-type-check**: `runHTTP` MUST throw `TransportError.invalidResponse` if the received response cannot be cast to `HTTPURLResponse`.
- **http-success-range**: `runHTTP` MUST treat a response as successful if and only if its status code falls in `200..<300`; every other status code MUST be treated as a failure.
- **http-error-body-drain**: On a non-2xx status, `runHTTP` MUST fully drain the response body into a `Data` buffer before calling `plugin.describeError(status:body:)` with it.
- **http-error-message-fallback**: On a non-2xx status, `runHTTP` MUST use `plugin.describeError(status:body:)`'s returned string as `TransportError.http`'s message when it is non-nil, and MUST fall back to the literal string `"HTTP \(http.statusCode)"` when `describeError` returns `nil`, then MUST throw `TransportError.http(status:message:)`.
- **http-success-decode**: On a 2xx status, `runHTTP` MUST call `plugin.makeDecoder()` exactly once and pass the still-streaming response bytes and that decoder to `pump(bytes:through:into:)`.
- **command-channel-configuration**: `runCommand` MUST construct its `SubprocessChannel` with `environmentPolicy: .replace` and `framing: .newlineDelimited`, using the spec's `executableURL`, `arguments`, and `environment` verbatim.
- **command-launch**: `runCommand` MUST call `channel.launch()` before writing any stdin or reading any output.
- **command-stdin-write**: `runCommand` MUST write a non-nil `stdin` to the channel via `sendRaw(_:)`, never via the framing `send(_:)`, so no delimiter is appended to the payload.
- **command-stdin-close**: `runCommand` MUST call `channel.closeInput()` unconditionally immediately after the stdin write step, whether or not `stdin` was `nil`, so the child always sees EOF on stdin.
- **command-frame-consumption**: `runCommand` MUST call `plugin.makeDecoder()` exactly once, then feed every frame produced by `channel.messages()` to that decoder's `consume(_:)` and yield each returned event to the continuation, in the order the frames arrive.
- **command-finish-before-status**: `runCommand` MUST call `Task.checkCancellation()`, and — only if it does not throw — call `decoder.finish()` and yield its events, *before* awaiting the child's exit status, so a completed answer is always delivered before the transport asks whether the child succeeded.
- **command-finish-skipped-on-cancellation**: If `Task.checkCancellation()` throws at that checkpoint, `runCommand` MUST propagate the resulting error and MUST NOT call `decoder.finish()` — a cancelled run never receives a flush of the decoder's trailing state.
- **command-exit-status-check**: `runCommand` MUST await `channel.waitUntilExit()` and treat exactly `status == 0` as success.
- **command-terminate-always**: `runCommand` MUST call `channel.terminate()` once `waitUntilExit()` returns, on both the success and the failure branch of the status check, and MUST call it again from its outer `catch` block if any step of the `do` block throws, so `terminate()` runs exactly once on the success path and again as cleanup on every throwing path.
- **command-nonzero-exit-error**: On a nonzero exit status, `runCommand` MUST fetch the child's raw stderr bytes via `channel.standardErrorData()` — never `standardErrorText()` — and pass them unmodified to `plugin.describeError(status:body:)`, falling back to the literal string `"Command exited with status \(status)"` when `describeError` returns `nil`, then MUST throw `TransportError.commandFailed(status:message:)`.
- **command-cleanup-rethrows-original-error**: `runCommand`'s outer `catch` block MUST call `channel.terminate()` and then rethrow the original caught error unchanged — it MUST NOT substitute or wrap that error.
- **byte-pump-line-framing**: `pump(bytes:through:into:)` MUST accumulate incoming bytes into a buffer and, on each byte equal to `0x0A`, call `decoder.consume(_:)` with the buffer including that trailing `0x0A` byte, then clear the buffer.
- **byte-pump-cancellation-check**: `pump(bytes:through:into:)` MUST call `Task.checkCancellation()` once for every byte received, before appending it to the buffer.
- **byte-pump-trailing-remainder**: Once the byte sequence ends, `pump(bytes:through:into:)` MUST call `decoder.consume(_:)` with any remaining non-empty, unterminated buffer content; it MUST NOT call `consume(_:)` with an empty buffer.
- **byte-pump-finish-call**: `pump(bytes:through:into:)` MUST call `decoder.finish()` and yield its events exactly once, after the trailing-remainder step, whenever the byte loop completes without throwing.
- **byte-pump-cancellation-skips-finish**: If `Task.checkCancellation()` throws inside the byte loop, `pump(bytes:through:into:)` MUST propagate that error immediately and MUST NOT reach the trailing-remainder or `finish()` steps.
- **decoder-per-request**: Both `runHTTP` and `runCommand` MUST call `plugin.makeDecoder()` exactly once per `run(spec:plugin:)` invocation, never reusing a decoder instance across two requests.
- **decoder-task-confinement**: The decoder created by `makeDecoder()` MUST be created and consumed only inside the single unstructured `Task` that `run(spec:plugin:)` starts — never handed to, or invoked from, any other concurrency domain — matching `AIStreamDecoder`'s non-`Sendable` contract (see the sibling `AIStreamEvent` recipe).
- **single-attempt**: `run(spec:plugin:)` MUST perform the described request exactly once per invocation; the source contains no retry loop, backoff, or repeated call to `runHTTP`/`runCommand` for a single `run(spec:plugin:)` call.
- **subprocess-cancellation-eager-kill**: For a `.command` request, cancelling the task that iterates the returned stream MUST terminate the child process eagerly rather than waiting for it to exit on its own terms — cancelling that task cancels the frame-consuming loop over `channel.messages()`, whose termination cancels `SubprocessChannel`'s own pump task, whose cancellation handler signals the child (`PluginTransport.swift`'s own doc comment).
- **raw-error-passthrough**: Any failure that is neither a non-2xx HTTP status nor a nonzero subprocess exit (for example a `URLSession` connectivity failure, or an error from `SubprocessChannel` itself such as `.launchFailed`) MUST reach the stream's consumer as its original, unwrapped error type — `run(spec:plugin:)`'s outer `catch` re-throws every such error unchanged, and neither `runHTTP` nor `runCommand` catches or reclassifies it further.

## Appearance

Not applicable — this is a Foundation-only request-transport engine (HTTP and subprocess I/O), not a visual component.

## States

Not applicable — this is a Foundation-only request-transport engine, not a visual component; its only runtime state machine is the request lifecycle described under Behavioral Requirements above (dispatch → stream → success/timeout/error), not a UI visual-state table.

## Accessibility

Not applicable — this is a Foundation-only request-transport engine with no user interface of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| plugin-transport-001 | wall-clock-enforcement, timeout-error-mapping | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "while :; do echo tick; sleep 0.05; done"], timeout: 0.5)` run through `PluginTransport.run` (`PluginTransportTests.wallClockBudgetCutsTricklingCommand`). | Throws `TransportError.timedOut`; at least one `.textDelta` event was yielded before the cut-off; total elapsed time is well under the trickle's natural duration, proving the cut-off is wall-clock, not idle-based. |
| plugin-transport-002 | command-frame-consumption, byte-pump-finish-call (command path) | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "printf 'hello\\n'"], timeout: 10)` (`PluginTransportTests.commandWithinBudgetStreamsToCompletion`). | Stream completes normally; concatenated `.textDelta` text contains `"hello"`. |
| plugin-transport-003 | command-stdin-write, command-stdin-close | `AIRequestSpec.command(executableURL: "/bin/cat", stdin: Data("first line\nsecond line, no trailing newline".utf8), timeout: 10)` (`PluginTransportTests.stdinIsWrittenUnframedAndThenClosed`). | The reassembled reply equals the payload exactly, byte for byte, with no appended `0x0A` — proving `sendRaw`, not `send`, was used, and that `closeInput()` ran so `cat` could reach EOF. |
| plugin-transport-004 | command-exit-status-check, command-nonzero-exit-error | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "echo boom >&2; exit 3"], timeout: 10)` against a plugin whose `describeError` echoes `status`/`body` (`PluginTransportTests.nonZeroExitCarriesStatusAndStandardError`). | Throws `TransportError.commandFailed(status: 3, message:)` where `message` contains `"boom"`. |
| plugin-transport-005 | command-nonzero-exit-error | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "printf 'boom\\377\\n' >&2; exit 3"], timeout: 10)` against a plugin recording the exact bytes handed to `describeError` (`PluginTransportTests.describeErrorReceivesRawStandardErrorBytes`). | The plugin's recorded `body` equals `Data([0x62,0x6F,0x6F,0x6D,0xFF,0x0A])` exactly — the invalid-UTF-8 byte `0xFF` reaches `describeError` unmodified, proving `standardErrorData()`, not `standardErrorText()`, was used. |
| plugin-transport-006 | command-channel-configuration | `AIRequestSpec.command(executableURL: "/usr/bin/env", environment: ["WHIPPET_PLUGIN_PROBE": "present"], timeout: 10)` run with a distinct parent-only environment variable set beforehand (`PluginTransportTests.environmentReplacesRatherThanMergesOverTheParent`). | The child's reported environment contains `WHIPPET_PLUGIN_PROBE=present` and does **not** contain the parent-only variable — confirming `environmentPolicy: .replace`. |
| plugin-transport-007 | command-frame-consumption, byte-pump-line-framing (framing parity), command-finish-before-status | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "printf 'a\\nb\\nc\\ntail'"], timeout: 10)` against a decoder that logs every `consume(_:)` payload and its `finish()` call (`PluginTransportFramingTests.commandFramingMatchesOldBytePump`). | The decoder receives exactly `["a\n", "b\n", "c\n", "tail"]`, in order, followed by exactly one `finish()` call; the reassembled reply is `"a\nb\nc\ntail"`. |
| plugin-transport-008 | command-frame-consumption | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "printf 'one\\ntwo\\n'"], timeout: 10)` (`PluginTransportFramingTests.trailingNewlineProducesNoEmptyFrame`). | The decoder receives exactly `["one\n", "two\n"]` — no spurious empty trailing frame for output that already ends in a newline. |
| plugin-transport-009 | http-response-type-check | Source-derived (no dedicated test in the given sources): `runHTTP` receives a `URLResponse` that is not an `HTTPURLResponse`. | Throws `TransportError.invalidResponse` before any bytes reach a decoder. |
| plugin-transport-010 | http-success-range, http-error-message-fallback | Source-derived: `runHTTP` receives a `404` response with an empty body from a plugin whose `describeError` returns `nil`. | Throws `TransportError.http(status: 404, message: "HTTP 404")` — the literal fallback string, since `describeError` declined to describe it. |
| plugin-transport-011 | http-error-body-drain, http-error-message-fallback | Source-derived: `runHTTP` receives a `500` response whose body is `{"error":"rate limited"}`, against a plugin whose `describeError(status:body:)` returns `"rate limited"` when it recognizes that JSON shape. | Throws `TransportError.http(status: 500, message: "rate limited")` — the full body reached `describeError` before the throw. |
| plugin-transport-012 | consumer-cancellation-propagation, subprocess-cancellation-eager-kill | `AIRequestSpec.command(executableURL: "/bin/sh", arguments: ["-c", "sleep 30"], timeout: 60)`; the consuming `for try await` loop's enclosing `Task` is cancelled shortly after starting. | The child process is terminated well before its natural 30-second sleep completes and before the 60-second budget would otherwise expire. |
| plugin-transport-013 | timeout-error-mapping, error-passthrough | Source-derived: `run(spec:plugin:)`'s internal operation throws a plugin-defined custom `Error` unrelated to `WallClockBudgetExceeded`. | The returned stream finishes with that exact error instance, not a `TransportError`. |

## Edge Cases

- **Null/empty input**: `headers: [:]` MUST leave the `URLRequest` with no additional header fields set beyond `URLRequest`'s own defaults (the `for` loop over an empty dictionary is a no-op). `body: nil` MUST produce a request with `httpBody == nil`. `stdin: nil` MUST cause `runCommand` to skip the `sendRaw` call but still MUST call `closeInput()` (`command-stdin-close`). `arguments: []` and `environment: [:]` MUST be accepted as ordinary, valid values — an empty `arguments` runs the executable with none, and an empty `environment` leaves the child inheriting the host's own environment per `SubprocessChannel`'s `EnvironmentPolicy.replace`.
- **Boundary values**: `spec.timeout` at or below `0` MUST cause the wall-clock budget to expire immediately, per `WallClockBudget.swift`'s documented mapping (`wallClockBudgetNanoseconds`, "at or below zero → expire immediately") — `PluginTransport` passes `spec.timeout` through unvalidated. `spec.timeout` at or above roughly one year, `.infinity`, or `.nan` MUST start no timer at all, per the same mapping's "no budget" case, so the request MUST run to natural completion or to the caller's own cancellation with no `TransportError.timedOut` ever thrown.
- **Concurrent access**: `PluginTransport` MUST support an arbitrary number of concurrent, independent `run(spec:plugin:)` calls without interference, per `stateless-invocation` — each call owns its own `Task`, decoder instance, and (for a command spec) its own `SubprocessChannel`, with no state shared across calls.
- **Error states**: A non-2xx HTTP status MUST surface as `TransportError.http`; a nonzero subprocess exit MUST surface as `TransportError.commandFailed`; a non-`HTTPURLResponse` MUST surface as `TransportError.invalidResponse`; any other failure (a `URLSession` connectivity error, a `SubprocessChannel.ChannelError` such as `.launchFailed`, a framing error from `SubprocessChannel`) MUST surface unwrapped, per `raw-error-passthrough`.
- **Offline/disconnected state**: If the HTTP byte stream throws mid-transfer (e.g. a dropped connection), `pump(bytes:through:into:)`'s `for try await byte in bytes` loop MUST propagate that error immediately; the trailing-remainder `consume(_:)` call and the `finish()` call MUST NOT run — any bytes still buffered inside `pump`'s own `line` accumulator are discarded, and the decoder's own internal buffer is likewise never flushed. For the command transport, if `channel.messages()`'s iteration throws (e.g. a framing failure surfaced by `SubprocessChannel`), `runCommand`'s outer `catch` MUST call `channel.terminate()` and rethrow that error unchanged.
- **Cancellation**: Cancelling the task that iterates the stream returned by `run(spec:plugin:)` MUST cancel `run`'s internal `Task` (`consumer-cancellation-propagation`), which for a command request MUST terminate the child process eagerly (`subprocess-cancellation-eager-kill`) rather than waiting for a natural exit; in both transports, a cancellation observed at the `Task.checkCancellation()` checkpoint MUST prevent `decoder.finish()` from ever being called (`command-finish-skipped-on-cancellation`, `byte-pump-cancellation-skips-finish`) — a cancelled run never receives a flush of the decoder's trailing state, only whatever events were already yielded.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `spec` (parameter to `run(spec:plugin:)`) | `AIRequestSpec` | none — required | Describes the HTTP or subprocess request to perform, including its wall-clock `timeout` (see the sibling `AIRequestSpec` recipe). |
| `plugin` (parameter to `run(spec:plugin:)`) | `any AIPlugin` | none — required | Supplies `makeDecoder()` for turning response bytes into `AIStreamEvent`s and `describeError(status:body:)` for translating a failure into a human-readable message (see the sibling `AIPlugin` recipe). |

`PluginTransport.swift` defines no environment variable and no settings key of its own; every value it operates on arrives as one of the two parameters above, ultimately sourced from the `AIRequestSpec` the caller supplies.

## Deep Linking

Not applicable: `PluginTransport.swift` defines no URL scheme, route, or navigation destination — the `URL` it uses addresses an AI provider's HTTP endpoint, not an app deep link.

## Localization

`PluginTransport.swift` contains hardcoded, unlocalized English string literals presented to callers via `TransportError.errorDescription` and the `describeError`-fallback paths. There is no string-catalog key for any of them; the literal itself is both the value and its own identifier.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "The server returned an invalid response." | `TransportError.invalidResponse.errorDescription` |
| (none — literal, no catalog key) | "The request exceeded its %gs budget." | `TransportError.timedOut(after:).errorDescription`, interpolated with the elapsed seconds |
| (none — literal, no catalog key) | "HTTP %d" | Fallback message for `TransportError.http` when `plugin.describeError` returns `nil` |
| (none — literal, no catalog key) | "Command exited with status %d" | Fallback message for `TransportError.commandFailed` when `plugin.describeError` returns `nil` |

## Accessibility Options

Not applicable: `PluginTransport.swift` presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `PluginTransport.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `PluginTransport.swift` contains no analytics or event-tracking call.

## Privacy

- **Data handled**: `spec.transport`'s `headers`, `body`, `stdin`, and `environment` MAY each carry a credential a plugin embedded into the request description (see the sibling `AIRequestSpec` recipe's own Privacy section); `PluginTransport.swift` itself has no knowledge of which values are secret — it forwards every one of them to `URLRequest` or to the spawned subprocess exactly as given, and forwards every response byte and every stderr byte to the plugin's `makeDecoder()`/`describeError(status:body:)` exactly as received, with no inspection of its own.
- **Storage**: `PluginTransport.swift` performs no storage of its own — it holds request and response data only in memory, for the lifetime of one `run(spec:plugin:)` call.
- **Transmission**: For an `.http` request, `PluginTransport` transmits `headers` and `body` to `url` via `URLSession.shared.bytes(for:)`; for a `.command` request, it writes `stdin` and `environment` only to a locally spawned child process via `SubprocessChannel` — no network transmission occurs for the command path itself, only whatever the spawned process independently performs.
- **Retention**: None. A response's bytes and any decoded `AIStreamEvent`s exist only for the duration of the `AsyncThrowingStream` a caller iterates; nothing is cached or retained past that iteration, except for `SubprocessChannel`'s own bounded (1 MB) stderr buffer, which is released with the channel.

## Logging

Not applicable: `PluginTransport.swift` contains no logging call (`print`, `os_log`, or otherwise) — it is I/O and control-flow logic with no diagnostic side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/PluginTransport.swift`, consumed by `DaemonAIChat.swift` (same directory) and by every host chat backend that drives an `AIPlugin`. It depends on `Foundation`'s `URLSession`/`URLRequest`, on `AgenticToolkitCore`'s `SubprocessChannel` and `withWallClockBudget`, and is itself UI-framework-agnostic — a SwiftUI host consumes the `AsyncThrowingStream<AIStreamEvent, Error>` it returns identically to an AppKit one.
- **Compose**: Model `runHTTP` with OkHttp's `Call` and a streaming `ResponseBody` source, wrapped in `kotlinx.coroutines.withTimeout(spec.timeoutMillis)` to reproduce the wall-clock (not idle) bound `withWallClockBudget` provides — OkHttp's own `callTimeout`/`readTimeout` settings are per-operation, idle-style timeouts, the same gap the source's own doc comment calls out for `URLRequest.timeoutInterval`. Model `runCommand` with `ProcessBuilder`/`Runtime.exec`, writing to the process's output stream then closing it for EOF, and draining stdout line-by-line (matching `.newlineDelimited`) on a background dispatcher; note that most Android app sandboxes cannot spawn arbitrary executables, so a Compose/Android port would typically support only the HTTP path, as the sibling `AIRequestSpec` recipe's Compose note also observes. Use `callbackFlow`/`channelFlow` with `awaitClose` as the `AsyncThrowingStream` equivalent, cancelling the underlying `Call` or `Process` from `awaitClose` the way `continuation.onTermination` cancels `PluginTransport`'s internal `Task`.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive), model `runHTTP` with `fetch` plus a `ReadableStream` reader, tying an `AbortController` both to consumer cancellation and to a `setTimeout(timeout)` for the wall-clock bound — matching the sibling `AIRequestSpec` recipe's own React/Web note. Model `runCommand` with `child_process.spawn`, writing to `.stdin` then calling `.stdin.end()` for EOF, and reading `.stdout` through a `readline.createInterface` (or manual `\n`-splitting) to reproduce `.newlineDelimited` framing; read `.stderr` as a `Buffer` (never decoded to a string) to preserve `command-nonzero-exit-error`'s raw-bytes guarantee. Represent the returned sequence as an `async function*` generator or a `ReadableStream<AIStreamEvent>`, calling `AbortController.abort()`/killing the child process when the consumer stops iterating, in place of `continuation.onTermination`.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model `runHTTP` with `System.Net.Http.HttpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead)`, reading the response via `Content.ReadAsStreamAsync()` so the body streams rather than buffers, exactly as `URLSession.shared.bytes(for:)` does; bound the whole call — not just `HttpClient.Timeout`, which is a per-operation idle-style timeout with the same insufficiency the source's doc comment calls out for `URLRequest.timeoutInterval` — with a `CancellationTokenSource` whose `CancelAfter(spec.Timeout)` is passed to `SendAsync`, reproducing `wall-clock-enforcement` without porting the source's custom `withWallClockBudget` race. Model `runCommand` with `System.Diagnostics.Process`/`ProcessStartInfo`, setting `RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` to `true` and, per `command-channel-configuration`'s replace semantics, calling `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `environment` (since `EnvironmentVariables` starts pre-populated with the parent's own variables, the opposite of the source's default); write `stdin` to `StandardInput.BaseStream` then call `StandardInput.Close()` for the EOF `command-stdin-close` requires, read `StandardError.BaseStream` into a `byte[]` (never `StandardError.ReadToEndAsync()`'s decoded `string`) to reproduce `command-nonzero-exit-error`'s raw-bytes guarantee, and await exit via `Process.WaitForExitAsync(cancellationToken)` rather than the blocking `WaitForExit()`. Represent the returned sequence as an `IAsyncEnumerable<AiStreamEvent>` built over a `System.Threading.Channels.Channel<AiStreamEvent>` (unbounded, matching the source's own unbounded `AsyncThrowingStream` buffering policy) in place of Swift's `AsyncThrowingStream`, and call `Process.Kill()` from the `CancellationToken`'s registration to reproduce `subprocess-cancellation-eager-kill` — noting that Windows has no SIGTERM-equivalent graceful-then-forceful escalation the way `SubprocessChannel.terminate()` does, so a port that wants an analogous grace period must implement its own (e.g. `Process.CloseMainWindow()` followed by a timed `Process.Kill()`).

## Design Decisions

**Decision**: The command transport's stderr is read via `channel.standardErrorData()` — raw, undecoded bytes — rather than `channel.standardErrorText()`, and the same raw-`Data` contract is used for the HTTP transport's error body.
**Rationale**: `standardErrorText()` prepends diagnostic prefixes (a truncation or drain-incompleteness marker) and falls back to Latin-1 for non-UTF-8 content, re-encoding every byte at or above `0x80`; a plugin's `describeError(status:body:)` parses the provider's or child's own error format, and handing it channel bookkeeping or a re-encoded byte stream instead of the child's actual bytes would corrupt exactly the diagnosis it is trying to make (`PluginTransport.swift`, which states this explicitly).
**Approved**: pending

**Decision**: `runCommand` writes `stdin` via `sendRaw(_:)`, which appends no delimiter, rather than the framing-aware `send(_:)`.
**Rationale**: The stdin payload is an opaque blob (a prompt, a file) with no message boundary of its own to declare; framing it with `.newlineDelimited`'s appended `0x0A` would append a byte the child never received before, which the source's own doc comment states directly.
**Approved**: pending

**Decision**: `PluginTransport` performs no retry or backoff of any kind — a failed request (an HTTP error, a nonzero exit, a timeout, or any other thrown error) is reported to the caller exactly once, on the first and only attempt.
**Rationale**: The type's scope, per its own doc comment, is to drive one described request to completion and report the outcome; whether and how to retry is a decision the host or caller can make with full knowledge of the failure (its `TransportError` case, or the original unwrapped error per `raw-error-passthrough`), not one `PluginTransport` can make on the caller's behalf without also owning a retry policy (backoff duration, retry count, which failures are retryable) that the source never expresses.
**Approved**: pending

**Decision**: When `spec.timeout` expires, the returned stream finishes with `TransportError.timedOut` immediately, but the underlying HTTP transfer or child process is only cancelled — not awaited — by the timed-out racer, so cleanup (closing the connection, or `SubprocessChannel.terminate()`'s SIGTERM-then-SIGKILL escalation, which can take up to roughly 2.5 seconds) continues asynchronously after the caller has already received the error.
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
