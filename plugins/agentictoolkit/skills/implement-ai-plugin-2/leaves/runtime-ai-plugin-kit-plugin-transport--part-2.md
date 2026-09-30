<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-plugin-transport--part-2 · source: ai-plugin-runtime-ai-plugin-kit-plugin-transport.md -->

# PluginTransport — continued (part 2)

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-plugin-transport--part-2#<slug>`):

- `data-handled` MAY — spec.transport's headers, body, stdin, and environment MAY each carry a credential a plugin embedded into the request …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `spec` (parameter to `run(spec:plugin:)`) | `AIRequestSpec` | none — required | Describes the HTTP or subprocess request to perform, including its wall-clock `timeout` (see the sibling `AIRequestSpec` recipe). |
| `plugin` (parameter to `run(spec:plugin:)`) | `any AIPlugin` | none — required | Supplies `makeDecoder()` for turning response bytes into `AIStreamEvent`s and `describeError(status:body:)` for translating a failure into a human-readable message (see the sibling `AIPlugin` recipe). |

`PluginTransport.swift` defines no environment variable and no settings key of its own; every value it operates on arrives as one of the two parameters above, ultimately sourced from the `AIRequestSpec` the caller supplies.

## Localization

`PluginTransport.swift` contains hardcoded, unlocalized English string literals presented to callers via `TransportError.errorDescription` and the `describeError`-fallback paths. There is no string-catalog key for any of them; the literal itself is both the value and its own identifier.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no catalog key) | "The server returned an invalid response." | `TransportError.invalidResponse.errorDescription` |
| (none — literal, no catalog key) | "The request exceeded its %gs budget." | `TransportError.timedOut(after:).errorDescription`, interpolated with the elapsed seconds |
| (none — literal, no catalog key) | "HTTP %d" | Fallback message for `TransportError.http` when `plugin.describeError` returns `nil` |
| (none — literal, no catalog key) | "Command exited with status %d" | Fallback message for `TransportError.commandFailed` when `plugin.describeError` returns `nil` |

## Privacy

- **Data handled**: `spec.transport`'s `headers`, `body`, `stdin`, and `environment` MAY each carry a credential a plugin embedded into the request description (see the sibling `AIRequestSpec` recipe's own Privacy section); `PluginTransport.swift` itself has no knowledge of which values are secret — it forwards every one of them to `URLRequest` or to the spawned subprocess exactly as given, and forwards every response byte and every stderr byte to the plugin's `makeDecoder()`/`describeError(status:body:)` exactly as received, with no inspection of its own.
- **Storage**: `PluginTransport.swift` performs no storage of its own — it holds request and response data only in memory, for the lifetime of one `run(spec:plugin:)` call.
- **Transmission**: For an `.http` request, `PluginTransport` transmits `headers` and `body` to `url` via `URLSession.shared.bytes(for:)`; for a `.command` request, it writes `stdin` and `environment` only to a locally spawned child process via `SubprocessChannel` — no network transmission occurs for the command path itself, only whatever the spawned process independently performs.
- **Retention**: None. A response's bytes and any decoded `AIStreamEvent`s exist only for the duration of the `AsyncThrowingStream` a caller iterates; nothing is cached or retained past that iteration, except for `SubprocessChannel`'s own bounded (1 MB) stderr buffer, which is released with the channel.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/PluginTransport.swift`, consumed by `DaemonAIChat.swift` (same directory) and by every host chat backend that drives an `AIPlugin`. It depends on `Foundation`'s `URLSession`/`URLRequest`, on `AgenticToolkitCore`'s `SubprocessChannel` and `withWallClockBudget`, and is itself UI-framework-agnostic — a SwiftUI host consumes the `AsyncThrowingStream<AIStreamEvent, Error>` it returns identically to an AppKit one.
- **Compose**: Model `runHTTP` with OkHttp's `Call` and a streaming `ResponseBody` source, wrapped in `kotlinx.coroutines.withTimeout(spec.timeoutMillis)` to reproduce the wall-clock (not idle) bound `withWallClockBudget` provides — OkHttp's own `callTimeout`/`readTimeout` settings are per-operation, idle-style timeouts, the same gap the source's own doc comment calls out for `URLRequest.timeoutInterval`. Model `runCommand` with `ProcessBuilder`/`Runtime.exec`, writing to the process's output stream then closing it for EOF, and draining stdout line-by-line (matching `.newlineDelimited`) on a background dispatcher; note that most Android app sandboxes cannot spawn arbitrary executables, so a Compose/Android port would typically support only the HTTP path, as the sibling `AIRequestSpec` recipe's Compose note also observes. Use `callbackFlow`/`channelFlow` with `awaitClose` as the `AsyncThrowingStream` equivalent, cancelling the underlying `Call` or `Process` from `awaitClose` the way `continuation.onTermination` cancels `PluginTransport`'s internal `Task`.
- **React/Web**: In a Node.js or Electron host (a browser has no subprocess primitive), model `runHTTP` with `fetch` plus a `ReadableStream` reader, tying an `AbortController` both to consumer cancellation and to a `setTimeout(timeout)` for the wall-clock bound — matching the sibling `AIRequestSpec` recipe's own React/Web note. Model `runCommand` with `child_process.spawn`, writing to `.stdin` then calling `.stdin.end()` for EOF, and reading `.stdout` through a `readline.createInterface` (or manual `\n`-splitting) to reproduce `.newlineDelimited` framing; read `.stderr` as a `Buffer` (never decoded to a string) to preserve `command-nonzero-exit-error`'s raw-bytes guarantee. Represent the returned sequence as an `async function*` generator or a `ReadableStream<AIStreamEvent>`, calling `AbortController.abort()`/killing the child process when the consumer stops iterating, in place of `continuation.onTermination`.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model `runHTTP` with `System.Net.Http.HttpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead)`, reading the response via `Content.ReadAsStreamAsync()` so the body streams rather than buffers, exactly as `URLSession.shared.bytes(for:)` does; bound the whole call — not just `HttpClient.Timeout`, which is a per-operation idle-style timeout with the same insufficiency the source's doc comment calls out for `URLRequest.timeoutInterval` — with a `CancellationTokenSource` whose `CancelAfter(spec.Timeout)` is passed to `SendAsync`, reproducing `wall-clock-enforcement` without porting the source's custom `withWallClockBudget` race. Model `runCommand` with `System.Diagnostics.Process`/`ProcessStartInfo`, setting `RedirectStandardInput`/`RedirectStandardOutput`/`RedirectStandardError` to `true` and, per `command-channel-configuration`'s replace semantics, calling `ProcessStartInfo.EnvironmentVariables.Clear()` before copying in a non-empty `environment` (since `EnvironmentVariables` starts pre-populated with the parent's own variables, the opposite of the source's default); write `stdin` to `StandardInput.BaseStream` then call `StandardInput.Close()` for the EOF `command-stdin-close` requires, read `StandardError.BaseStream` into a `byte[]` (never `StandardError.ReadToEndAsync()`'s decoded `string`) to reproduce `command-nonzero-exit-error`'s raw-bytes guarantee, and await exit via `Process.WaitForExitAsync(cancellationToken)` rather than the blocking `WaitForExit()`. Represent the returned sequence as an `IAsyncEnumerable<AiStreamEvent>` built over a `System.Threading.Channels.Channel<AiStreamEvent>` (unbounded, matching the source's own unbounded `AsyncThrowingStream` buffering policy) in place of Swift's `AsyncThrowingStream`, and call `Process.Kill()` from the `CancellationToken`'s registration to reproduce `subprocess-cancellation-eager-kill` — noting that Windows has no SIGTERM-equivalent graceful-then-forceful escalation the way `SubprocessChannel.terminate()` does, so a port that wants an analogous grace period must implement its own (e.g. `Process.CloseMainWindow()` followed by a timed `Process.Kill()`).

