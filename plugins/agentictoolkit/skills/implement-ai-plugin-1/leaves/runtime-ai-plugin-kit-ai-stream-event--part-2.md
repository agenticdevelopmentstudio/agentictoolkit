<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-stream-event--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-stream-event.md -->

# AIStreamEvent — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-stream-event--part-2#<slug>`):

- `winui-3` MUST — Model AiStreamEvent as an abstract record with three sealed derived records — TextDelta(string Text), ToolUse(string …

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift`. Nothing here is SwiftUI-specific — `AIStreamEvent` and `AIStreamDecoder` are Foundation-only and consumed identically by a SwiftUI or AppKit host through `PluginTransport`'s `AsyncThrowingStream<AIStreamEvent, Error>`.
- **Compose**: Model `AiStreamEvent` as a Kotlin `sealed interface` with data classes `TextDelta(val text: String)`, `ToolUse(val id: String, val name: String, val argumentsJson: ByteArray)`, and `End(val stopReason: String?)`; enumerate over it with a `when` expression, which the compiler treats as exhaustive the way Swift's `switch` does. `AiStreamDecoder` becomes an interface with `fun consume(data: ByteArray): List<AiStreamEvent>` and a default `fun finish(): List<AiStreamEvent> = emptyList()`, mirroring the Swift protocol extension's default.
- **React/Web**: Represent `AIStreamEvent` as a discriminated union — `{ kind: 'textDelta', text: string } | { kind: 'toolUse', id: string, name: string, argumentsJSON: Uint8Array } | { kind: 'end', stopReason?: string }` — and `AIStreamDecoder` as an interface with `consume(data: Uint8Array): AIStreamEvent[]` and an optional `finish?(): AIStreamEvent[]`. A web port could instead lean on the platform's native streaming primitive, a `TransformStream<Uint8Array, AIStreamEvent>`, rather than the manual `consume`/`finish` pair, since the browser's `ReadableStream` already models incremental delivery plus an explicit close.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model `AiStreamEvent` as an abstract `record` with three sealed derived records — `TextDelta(string Text)`, `ToolUse(string Id, string Name, byte[] ArgumentsJson)`, `End(string? StopReason)` — enabling exhaustive `switch` pattern matching over `is` patterns, the closest .NET analogue to Swift's closed enum. Declare `IAiStreamDecoder` as `IReadOnlyList<AiStreamEvent> Consume(byte[] data);` plus a C# 8+ default interface method `IReadOnlyList<AiStreamEvent> Finish() => Array.Empty<AiStreamEvent>();` to mirror the Swift protocol extension's default `finish()`. Because `AIStreamDecoder` is deliberately non-`Sendable` and holds mutable per-response state, a WinUI 3 port MUST construct a fresh `IAiStreamDecoder` per request and MUST NOT register one as a singleton or reuse it across `HttpClient` calls, matching `fresh-decoder-per-request` and `single-response-isolation` above. Use `System.Text.Json`'s `Utf8JsonReader`/`JsonDocument` in place of `JSONSerialization` inside a concrete decoder, and drive `Consume` from `HttpClient.GetStreamAsync`/`Stream.CopyToAsync` with a manual byte-buffer loop (or `System.IO.Pipelines.PipeReader` for a more idiomatic incremental read) in place of `URLSession.shared.bytes(for:)` as the byte source `PluginTransport`'s pump supplies.

## Design Decisions

**Decision**: `consume(_:)` and `finish()` are both non-throwing; a frame that cannot be decoded simply yields no event, with no distinct error signal.
**Rationale**: This keeps every conforming decoder simple — none of the five shipped decoders (`ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`, `PlainTextDecoder`) needs error-propagation plumbing — but it means a genuinely malformed, unrecoverable frame is indistinguishable from one that is merely incomplete and awaiting more bytes; both currently vanish silently. This is the same gap the open question on decode-failure-signal documents.
**Approved**: pending

**Decision**: `AIStreamEvent` declares three cases — `textDelta`, `toolUse`, `end` — even though no `AIStreamDecoder` shipped in this repository (`ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`, `PlainTextDecoder`) ever returns a `.toolUse` event.
**Rationale**: Every consumer's `switch` over `AIStreamEvent` (`LocalChatSession.swift`, `AIPluginChatBackend.swift`, `AIPluginLanguageModelProvider.swift`, `ChatBackendSession.swift`) already handles `.toolUse` exhaustively, so the case is part of the declared contract in preparation for a future tool-calling-capable decoder, not dead code — a source-fidelity note rather than a gap, since nothing here needs `.toolUse` to be produced today.
**Approved**: pending

**Decision**: `AIStreamDecoder` deliberately omits `Sendable`, unlike the sibling `AIPlugin` protocol, which requires it.
**Rationale**: A decoder's whole purpose is to hold mutable per-response parsing state (buffered bytes, partial JSON); requiring `Sendable` would force every conformer to add locking for state that is, by design, never touched from more than one task. `AIPlugin` instances, by contrast, are commonly cached and reused across concurrent requests (see the sibling `AIPlugin` recipe's `concurrent-invocation-safety` requirement), so it needs `Sendable` where a decoder does not.
**Approved**: pending

**Decision**: `finish()` provides a default no-op implementation via a protocol extension rather than being a required method every conformer must implement.
**Rationale**: A buffered whole-response decoder like `OpenAIReplyDecoder` needs an explicit `finish()` to emit its accumulated reply, but a decoder with no trailing state to flush (such as `LineDecoder` in `PluginTransportTests.swift`) has nothing useful to say when the stream closes; the default lets such a decoder omit the method entirely instead of writing a body that only returns `[]`.
**Approved**: pending
