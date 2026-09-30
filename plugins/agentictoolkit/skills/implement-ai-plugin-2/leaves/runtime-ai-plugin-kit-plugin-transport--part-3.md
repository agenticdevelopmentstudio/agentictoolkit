<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-plugin-transport--part-3 · source: ai-plugin-runtime-ai-plugin-kit-plugin-transport.md -->

# PluginTransport — continued (part 3)

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
