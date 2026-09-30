<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-stream-event--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-stream-event.md -->

# AIStreamEvent

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-stream-event--edge-cases#<slug>`):

- `null-empty-input` SHOULD — consume(Data()) SHOULD return [] — every conformer in this repository (PlainTextDecoder, ClaudeSSEDecoder, …
- `concurrent-access` MUST — Two tasks MUST NOT call consume(_:) or finish() on the same AIStreamDecoder instance concurrently for two different …
- `error-states` MUST — A malformed or unrecognizable frame (invalid JSON, bytes that fail UTF-8 decoding, an unrecognized SSE type) MUST NOT …
- `offline-disconnected-state` MUST — When the underlying byte stream throws before ending normally (e.g. URLSession.shared.bytes(for:) interrupted by a …
- `cancellation` MUST — PluginTransport.pump checks Task.checkCancellation() once per byte inside its loop; a cancelled consuming task MUST …

## Edge Cases

- **Null / empty input**: `consume(Data())` SHOULD return `[]` — every conformer in this repository (`PlainTextDecoder`, `ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`) does, and `PluginDecoderTests.plainTextDecoder` asserts it for `PlainTextDecoder` explicitly — but `AIStreamDecoder` itself imposes no such requirement, so this is each decoder's own consistent convention, not a protocol guarantee.
- **Boundary values**: Not applicable in the numeric sense — this contract defines no size-limited field of its own (no maximum `data` length, no cap on buffered bytes). Any upper bound on how large an unresolved frame may grow before `0x0A` appears is a decision made by the host that drives `consume(_:)` (`PluginTransport`), not by this component.
- **Concurrent access**: Two tasks MUST NOT call `consume(_:)` or `finish()` on the same `AIStreamDecoder` instance concurrently for two different responses; the protocol carries no `Sendable` conformance and its per-response state is unprotected by design (MUST, per `decoder-non-sendable-state` and `single-response-isolation` above).
- **Error states**: A malformed or unrecognizable frame (invalid JSON, bytes that fail UTF-8 decoding, an unrecognized SSE `type`) MUST NOT cause `consume(_:)` or `finish()` to throw — the source declares neither method as `throws`, so a decoder MUST fall back to returning `[]` for that frame, as `ClaudeSSEDecoder.parse(_:)` does for every unparseable or unrecognized `data:` line. See the open question on decode-failure-signal for the genuine gap this leaves.
- **Offline / disconnected state**: When the underlying byte stream throws before ending normally (e.g. `URLSession.shared.bytes(for:)` interrupted by a dropped connection), `PluginTransport.pump`'s `for try await byte in bytes` loop MUST propagate that error immediately, and in doing so it MUST NOT reach either the trailing-partial-line `consume(_:)` call or the final `finish()` call — any bytes a decoder was still buffering internally are discarded without ever reaching the returned event sequence; only the thrown error, not any partial content, reaches the stream's consumer.
- **Cancellation**: `PluginTransport.pump` checks `Task.checkCancellation()` once per byte inside its loop; a cancelled consuming task MUST therefore be able to stop delivery to `consume(_:)` mid-frame, and in that case `finish()` MUST NOT be called either — cancellation and a dropped connection produce the same outcome for this component: no flush, only whatever events were already yielded before the cancellation was observed.
