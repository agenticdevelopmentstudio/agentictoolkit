<!-- leaf: implement-general-2/networking-rpc--part-2 · source: networking-rpc.md -->

# Networking RPC — continued (part 2)

**Rules** (cite as `implement-general-2/networking-rpc--part-2#<slug>`):

- `framing-cases` MUST
- `newline-frame-encoding` MUST
- `content-length-frame-encoding` MUST
- `unframed-frame-encoding` MUST
- `frame-boundary-completeness` MUST
- `newline-frame-shape` MUST
- `content-length-frame-shape` MUST
- `unframed-decoding` MUST
- `content-length-header-parsed-once` MUST
- `content-length-header-line-parsing` MUST
- `content-length-malformed-header` MUST
- `content-length-missing-header` MUST
- `frame-size-cap` MUST
- `cap-violation-preserves-prior-frames` MUST
- `newline-cap-recovery` MUST
- `content-length-cap-recovery` MUST
- `finish-newline-remainder` MUST
- `finish-content-length-truncated` MUST
- `finish-content-length-malformed` MUST
- `finish-unframed-noop` MUST
- `finish-during-discard` MUST
- `decoder-value-type-single-owner` MUST
- `actor-serializes-channel` MUST
- `configuration-and-result-sendable` MUST
- `single-stdout-reader` MUST
- `launch-idempotency` MUST
- `launch-sigpipe-suppression` MUST
- `environment-replace-policy` MUST
- `environment-merge-policy` MUST
- `send-applies-framing` MUST
- `send-raw-unframed` MUST
- `send-call-order-preserved` MUST
- `write-after-close-throws` MUST
- `close-input-orderly` MUST
- `stderr-continuous-drain` MUST
- `stderr-tail-cap` MUST
- `stderr-text-decoding` MUST
- `stderr-text-diagnostic-prefixes` MUST
- `stderr-data-raw` MUST
- `stderr-drain-bounded-wait` MUST

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
