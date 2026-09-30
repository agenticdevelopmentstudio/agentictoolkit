<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-plugin-transport · source: ai-plugin-runtime-ai-plugin-kit-plugin-transport.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-plugin-transport#<slug>`):

- `single-entry-point` MUST
- `stateless-invocation` MUST
- `transport-dispatch` MUST
- `wall-clock-enforcement` MUST
- `timeout-error-mapping` MUST
- `error-passthrough` MUST
- `stream-completion-on-success` MUST
- `consumer-cancellation-propagation` MUST
- `http-request-construction` MUST
- `http-idle-timeout-set` MUST
- `http-streaming-fetch` MUST
- `http-response-type-check` MUST
- `http-success-range` MUST
- `http-error-body-drain` MUST
- `http-error-message-fallback` MUST
- `http-success-decode` MUST
- `command-channel-configuration` MUST
- `command-launch` MUST
- `command-stdin-write` MUST
- `command-stdin-close` MUST
- `command-frame-consumption` MUST
- `command-finish-before-status` MUST
- `command-finish-skipped-on-cancellation` MUST
- `command-exit-status-check` MUST
- `command-terminate-always` MUST
- `command-nonzero-exit-error` MUST
- `command-cleanup-rethrows-original-error` MUST
- `byte-pump-line-framing` MUST
- `byte-pump-cancellation-check` MUST
- `byte-pump-trailing-remainder` MUST
- `byte-pump-finish-call` MUST
- `byte-pump-cancellation-skips-finish` MUST
- `decoder-per-request` MUST
- `decoder-task-confinement` MUST
- `single-attempt` MUST
- `subprocess-cancellation-eager-kill` MUST
- `raw-error-passthrough` MUST

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

