---
id: 2067e249-4f97-4575-b8ed-8f55f6dc96df
title: AIStreamEvent
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-stream-event
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Sendable enum of one event in an AI provider's response stream, plus AIStreamDecoder,
  the protocol that turns raw bytes into a sequence of them.
platforms:
- swift
- macos
tags:
- ai-plugin
- streaming
- decoder
- sendable
- foundation
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-plugin
references: []
approved-by: ''
approved-date: ''
---

# AIStreamEvent

## Overview

`AIStreamEvent.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift`) defines the shape of one event in an assistant response stream (`AIStreamEvent`, a `Sendable` enum) and the protocol that produces a sequence of them from a provider's raw bytes (`AIStreamDecoder`). An `AIPlugin` conformer's `buildRequest(_:)` describes the outgoing request; a fresh `AIStreamDecoder` it creates via `makeDecoder()` then turns whatever bytes the host's transport receives into `AIStreamEvent`s, which the host renders. Neither type performs I/O itself — decoding only transforms bytes already in hand into a typed event sequence.

## Behavioral Requirements

- **case-set**: `AIStreamEvent` MUST have exactly three cases — `textDelta(String)`, `toolUse(id: String, name: String, argumentsJSON: Data)`, and `end(stopReason: String?)` (`AIStreamEvent.swift`, lines 907-917).
- **event-sendable**: `AIStreamEvent` MUST conform to `Sendable` (line 907), so a decoded value MAY cross concurrency domains — e.g. yielded from `PluginTransport.run`'s background `Task` into an `AsyncThrowingStream<AIStreamEvent, Error>` that a `@MainActor`-isolated consumer such as `LocalChatSession` or `AIPluginChatBackend` iterates.
- **text-delta-payload**: `textDelta`'s associated value MUST be a chunk of assistant text and nothing else (line 909-910); this type imposes no constraint on chunk size or boundaries — that is each decoder's own choice.
- **tool-use-payload**: `toolUse`'s associated values MUST be `id: String`, `name: String`, and `argumentsJSON: Data`, where `argumentsJSON` MUST be the raw, undecoded JSON arguments the model supplied (line 912-913, "the raw JSON arguments") — a decoder MUST NOT parse or validate that JSON before emitting the event.
- **end-stop-reason-optional**: `end`'s `stopReason` MUST be an `Optional<String>`, so a decoder MAY report `nil` when the provider gives no reason for stopping (line 915-916).
- **decoder-class-bound**: `AIStreamDecoder` MUST require `AnyObject` (line 928), so only a reference type (a `class`) may conform — a `struct` conformer fails to compile.
- **decoder-non-sendable-state**: `AIStreamDecoder` MUST NOT require `Sendable` conformance; a conforming type MAY hold mutable per-response parsing state without any synchronization of its own (lines 926-927, "may hold mutable per-response parsing state").
- **stream-decoder-isolation-domain**: Because `AIStreamDecoder` declares no `Sendable` conformance, a conforming instance MUST stay within the single concurrency domain (`Task`) that created it via `makeDecoder()` — Swift's strict concurrency checking (`SWIFT_STRICT_CONCURRENCY: complete`) rejects passing a non-`Sendable` decoder across an `await` boundary into a different isolation domain. `PluginTransport.runHTTP`/`runCommand` both create the decoder inside the same task that then drives every `consume(_:)`/`finish()` call on it.
- **fresh-decoder-per-request**: A new request MUST use a newly created `AIStreamDecoder` instance, per the doc comment "a fresh decoder is created per request (see `AIPlugin.makeDecoder()`)" (line 926); `PluginTransport.runHTTP` and `runCommand` each call `plugin.makeDecoder()` exactly once, inside the streaming task, before consuming any bytes.
- **single-response-isolation**: One `AIStreamDecoder` instance MUST be used to decode a single response stream only and MUST NOT be shared across two concurrent responses, since it holds per-response state (line 927) and requires no thread-safety of its own.
- **consume-accepts-incremental-bytes**: `consume(_ data: Data) -> [AIStreamEvent]` MUST accept newly received bytes and return the events that can now be fully decoded from them (lines 930-932).
- **consume-buffers-partial-frame**: `consume(_:)` MUST retain any partial trailing frame internally rather than discard it or error on it, because the host MAY split a single logical frame across multiple `consume(_:)` calls (lines 921-923, 931).
- **consume-returns-decodable-only**: `consume(_:)` MUST return only the events fully decodable from the bytes accumulated so far — it MUST NOT return a partial or speculative event for data it has not finished decoding (line 923, "returning only the events it can fully decode").
- **non-throwing-decode**: `consume(_:)` and `finish()` MUST NOT throw — both are declared without `throws` (lines 932, 935) — so a decoder that cannot make sense of its buffered bytes MUST signal that by omitting an event, not by raising an error.
- **finish-returns-final-events**: `finish() -> [AIStreamEvent]` MUST return whatever final events the decoder was still holding once the stream closes (lines 934-935).
- **finish-default-empty**: A conforming type that does not implement `finish()` MUST receive the protocol extension's default implementation, which returns `[]` (lines 938-939).
- **finish-called-once-per-stream**: The host MUST call `finish()` exactly once per response stream, after the stream closes, to flush any trailing state (line 924, "the host calls `finish()` once to flush any trailing state").
- **sequential-delivery**: The host MUST deliver bytes to `consume(_:)` and the terminating `finish()` call in strict arrival order on one instance, never out of order and never interleaved with another response's bytes — this is the only ordering guarantee this component's design (per-instance mutable state, no `Sendable`) makes workable.
- **host-framing-contract**: The one host in this codebase, `PluginTransport`, MUST feed `consume(_:)` newline-delimited frames — each complete line including its trailing `0x0A` byte, or one final unterminated remainder — rather than arbitrary byte chunks (`PluginTransport.pump(bytes:through:into:)` for HTTP, and its `SubprocessChannel`-backed `.newlineDelimited` framing for a command). `AIStreamDecoder` itself imposes no such framing; its own doc comment promises only "raw bytes... possibly splitting a single logical frame across calls."
- **no-persistence-or-caching**: `AIStreamEvent.swift` MUST NOT persist any event or cache decoder state beyond the `Data` and decoder-instance lifetimes already described above — the source contains no file, database, `UserDefaults`, or Keychain write of its own.
- **decode-failure-signal**: NEEDS REVIEW: Not implemented in source. Neither `AIStreamEvent` nor `AIStreamDecoder` defines a case or return path meaning "this frame is malformed and will never decode" — a permanently corrupt frame (e.g. JSON truncated by a dropped connection, or bytes that fail `String(data:encoding:.utf8)`) is indistinguishable from a frame that is merely incomplete and awaiting more bytes; both currently yield `[]` from `consume(_:)` with no signal reaching the host. What is missing: an explicit decode-error case or throwing path the host could observe and surface (e.g. a `case error(Error)` on `AIStreamEvent`, or `consume(_:) throws -> [AIStreamEvent]`). What would settle it: a design decision on whether "permanently malformed" should ever be observable, given every current provider's wire format (SSE `data:` lines, newline-delimited JSON, plain text) is line-oriented and naturally resynchronizes on the next frame regardless of one bad line.

## Appearance

Not applicable — this is a Sendable event enum and a stream-decoding protocol, not a visual component.

## States

Not applicable — this is a Sendable event enum and a stream-decoding protocol, not a visual component.

## Accessibility

Not applicable — this is a Sendable event enum and a stream-decoding protocol, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-stream-event-001 | case-set, event-sendable | Inspect `AIStreamEvent.swift` lines 907-917. | Exactly three cases — `textDelta`, `toolUse`, `end` — and the enum declaration itself states `Sendable` conformance. |
| ai-stream-event-002 | text-delta-payload | `AIStreamEvent.textDelta("Hello")`, pattern-matched as `PluginDecoderTests.textDeltas(_:)` does with `if case let .textDelta(text) = event`. | `text == "Hello"`, with no other payload carried. |
| ai-stream-event-003 | tool-use-payload | `AIStreamEvent.toolUse(id: "call_1", name: "search", argumentsJSON: Data("{\"q\":\"cats\"}".utf8))`, pattern-matched as `LocalChatSession.swift`'s `case .toolUse(let id, let name, let args):` does. | `id == "call_1"`, `name == "search"`, and `args` equals the exact `Data` given, byte for byte, unparsed. |
| ai-stream-event-004 | end-stop-reason-optional | Construct `AIStreamEvent.end(stopReason: nil)`. | Constructs without error; `stopReason` is `nil`. |
| ai-stream-event-005 | consume-buffers-partial-frame, non-throwing-decode | `ClaudeSSEDecoder().consume(Data("data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"Hel".utf8))` (`PluginDecoderTests.claudeSSEDecoderBuffersFrames`). | Returns `[]` and does not throw — no `0x0A` has completed the line yet. |
| ai-stream-event-006 | consume-buffers-partial-frame, consume-returns-decodable-only | Continuing vector 005: `decoder.consume(Data("lo\"}}\n".utf8))`. | Returns `[.textDelta("Hello")]` — the buffered partial frame plus the new bytes decode into exactly one event. |
| ai-stream-event-007 | finish-default-empty | `LineDecoder` (`PluginTransportTests.swift`) implements only `consume(_:)`. `LineDecoder().finish()`. | Returns `[]`, from the protocol extension's default. |
| ai-stream-event-008 | finish-called-once-per-stream, fresh-decoder-per-request, host-framing-contract | Run `PluginTransport.run(spec:plugin:)` for `printf 'a\nb\nc\ntail'` against a `RecordingDecoder`/`RecordingPlugin` (`PluginTransportFramingTests.commandFramingMatchesOldBytePump`). | `consume(_:)` receives exactly `["a\n", "b\n", "c\n", "tail"]`, in order; `finish()` is recorded as called exactly once, after all four; `makeDecoder()` was called exactly once for the run. |
| ai-stream-event-009 | non-throwing-decode, decode-failure-signal | `ClaudeSSEDecoder().consume(Data("data: not-json\n".utf8))`. | Returns `[]` — the unparseable line produces neither an event nor a thrown error, and is indistinguishable from a still-incomplete frame. |
| ai-stream-event-010 | single-response-isolation, decoder-non-sendable-state | Create two decoders from one plugin's `makeDecoder()` (as `ai-plugin-004` in the sibling `AIPlugin` recipe does); feed bytes to only the first, then call `finish()` on both. | The fed decoder's `finish()` reflects its buffered content; the untouched decoder's `finish()` yields `[]` — the two instances' state is independent. |
| ai-stream-event-011 | end-stop-reason-optional | `ClaudeSSEDecoder().consume(Data("data: {\"type\":\"message_stop\"}\n".utf8))` and, separately, `...consume(Data("data: [DONE]\n".utf8))` (`PluginDecoderTests.claudeSSEDecoderEnds`). | Both calls' returned arrays contain an `.end` event. |
| ai-stream-event-012 | host-framing-contract | `printf 'one\ntwo\n'` run through the command transport (`PluginTransportFramingTests.trailingNewlineProducesNoEmptyFrame`). | `consume(_:)` receives exactly `["one\n", "two\n"]` — no spurious empty trailing frame is produced for output that already ends in a newline. |
| ai-stream-event-013 | decoder-class-bound | Attempt `struct BadDecoder: AIStreamDecoder { func consume(_ data: Data) -> [AIStreamEvent] { [] } }`. | Fails to compile: `AIStreamDecoder: AnyObject` requires a reference type. |
| ai-stream-event-014 | sequential-delivery, host-framing-contract | In `PluginTransport.pump`, feed bytes for `"hello\n"` one byte at a time. | `consume(_:)` is invoked only once `0x0A` (the final byte) is appended — i.e. once per complete line, not once per byte — and `finish()` follows only after the loop over all bytes ends. |
| ai-stream-event-015 | stream-decoder-isolation-domain, fresh-decoder-per-request | Inspect `PluginTransport.runHTTP`/`runCommand`: `plugin.makeDecoder()` is called inside the same `Task` closure that later calls `consume(_:)`/`finish()` on the result. | The decoder is never constructed outside, or handed across, the task that consumes it — consistent with `AIStreamDecoder` carrying no `Sendable` conformance. |

## Edge Cases

- **Null / empty input**: `consume(Data())` SHOULD return `[]` — every conformer in this repository (`PlainTextDecoder`, `ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`) does, and `PluginDecoderTests.plainTextDecoder` asserts it for `PlainTextDecoder` explicitly — but `AIStreamDecoder` itself imposes no such requirement, so this is each decoder's own consistent convention, not a protocol guarantee.
- **Boundary values**: Not applicable in the numeric sense — this contract defines no size-limited field of its own (no maximum `data` length, no cap on buffered bytes). Any upper bound on how large an unresolved frame may grow before `0x0A` appears is a decision made by the host that drives `consume(_:)` (`PluginTransport`), not by this component.
- **Concurrent access**: Two tasks MUST NOT call `consume(_:)` or `finish()` on the same `AIStreamDecoder` instance concurrently for two different responses; the protocol carries no `Sendable` conformance and its per-response state is unprotected by design (MUST, per `decoder-non-sendable-state` and `single-response-isolation` above).
- **Error states**: A malformed or unrecognizable frame (invalid JSON, bytes that fail UTF-8 decoding, an unrecognized SSE `type`) MUST NOT cause `consume(_:)` or `finish()` to throw — the source declares neither method as `throws`, so a decoder MUST fall back to returning `[]` for that frame, as `ClaudeSSEDecoder.parse(_:)` does for every unparseable or unrecognized `data:` line. See the `decode-failure-signal` marker above for the genuine gap this leaves.
- **Offline / disconnected state**: When the underlying byte stream throws before ending normally (e.g. `URLSession.shared.bytes(for:)` interrupted by a dropped connection), `PluginTransport.pump`'s `for try await byte in bytes` loop MUST propagate that error immediately, and in doing so it MUST NOT reach either the trailing-partial-line `consume(_:)` call or the final `finish()` call — any bytes a decoder was still buffering internally are discarded without ever reaching the returned event sequence; only the thrown error, not any partial content, reaches the stream's consumer.
- **Cancellation**: `PluginTransport.pump` checks `Task.checkCancellation()` once per byte inside its loop; a cancelled consuming task MUST therefore be able to stop delivery to `consume(_:)` mid-frame, and in that case `finish()` MUST NOT be called either — cancellation and a dropped connection produce the same outcome for this component: no flush, only whatever events were already yielded before the cancellation was observed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data` (parameter to `consume(_:)`) | `Data` | none — required | Newly received bytes for the response currently being decoded; MAY be a full frame, a partial frame, or an empty buffer. |
| decoder instance | `any AIStreamDecoder` | none — required | Supplied per request by the conforming `AIPlugin`'s `makeDecoder()` (see the sibling `AIPlugin` recipe); `AIStreamEvent.swift` neither creates nor configures a decoder itself. |

This file defines no environment variable and no settings key of its own — every value it operates on arrives as a parameter, either the raw `Data` handed to `consume(_:)` or the decoder instance itself.

## Deep Linking

Not applicable: `AIStreamEvent.swift` defines no URL scheme, route, or navigation destination — it decodes response bytes into events, not app navigation.

## Localization

Not applicable: `AIStreamEvent.swift` contains no user-facing string literal of its own — `textDelta`'s text and `toolUse`'s `name`/`argumentsJSON` are opaque provider- or model-produced content passed through unmodified, not a string this file authors, formats, or displays.

## Accessibility Options

Not applicable: `AIStreamEvent.swift` presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `AIStreamEvent.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `AIStreamEvent.swift` contains no analytics or event-tracking call.

## Privacy

- **Data handled**: A `textDelta` or `toolUse` event MAY carry conversation content or tool-call arguments the provider or model produced for one chat turn; `AIStreamEvent.swift` itself defines no credential or token field — those live in the sibling `AIPluginConfig`/`AIChatContext` types, not here.
- **Storage**: `AIStreamEvent.swift` performs no storage of its own — see `no-persistence-or-caching` above; a decoder's buffered bytes and any decoded events live only in memory for the duration of one response stream.
- **Transmission**: This component never transmits data; it only decodes bytes the host's transport (`PluginTransport`) has already received.
- **Retention**: None — an `AIStreamEvent` is not retained past the `AsyncThrowingStream` iteration that consumes it, and a decoder's internal buffer is discarded with the decoder instance once its one response stream ends.

## Logging

Not applicable: `AIStreamEvent.swift` contains no logging call; it is a pure data-and-protocol declaration with no side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift`. Nothing here is SwiftUI-specific — `AIStreamEvent` and `AIStreamDecoder` are Foundation-only and consumed identically by a SwiftUI or AppKit host through `PluginTransport`'s `AsyncThrowingStream<AIStreamEvent, Error>`.
- **Compose**: Model `AiStreamEvent` as a Kotlin `sealed interface` with data classes `TextDelta(val text: String)`, `ToolUse(val id: String, val name: String, val argumentsJson: ByteArray)`, and `End(val stopReason: String?)`; enumerate over it with a `when` expression, which the compiler treats as exhaustive the way Swift's `switch` does. `AiStreamDecoder` becomes an interface with `fun consume(data: ByteArray): List<AiStreamEvent>` and a default `fun finish(): List<AiStreamEvent> = emptyList()`, mirroring the Swift protocol extension's default.
- **React/Web**: Represent `AIStreamEvent` as a discriminated union — `{ kind: 'textDelta', text: string } | { kind: 'toolUse', id: string, name: string, argumentsJSON: Uint8Array } | { kind: 'end', stopReason?: string }` — and `AIStreamDecoder` as an interface with `consume(data: Uint8Array): AIStreamEvent[]` and an optional `finish?(): AIStreamEvent[]`. A web port could instead lean on the platform's native streaming primitive, a `TransformStream<Uint8Array, AIStreamEvent>`, rather than the manual `consume`/`finish` pair, since the browser's `ReadableStream` already models incremental delivery plus an explicit close.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model `AiStreamEvent` as an abstract `record` with three sealed derived records — `TextDelta(string Text)`, `ToolUse(string Id, string Name, byte[] ArgumentsJson)`, `End(string? StopReason)` — enabling exhaustive `switch` pattern matching over `is` patterns, the closest .NET analogue to Swift's closed enum. Declare `IAiStreamDecoder` as `IReadOnlyList<AiStreamEvent> Consume(byte[] data);` plus a C# 8+ default interface method `IReadOnlyList<AiStreamEvent> Finish() => Array.Empty<AiStreamEvent>();` to mirror the Swift protocol extension's default `finish()`. Because `AIStreamDecoder` is deliberately non-`Sendable` and holds mutable per-response state, a WinUI 3 port MUST construct a fresh `IAiStreamDecoder` per request and MUST NOT register one as a singleton or reuse it across `HttpClient` calls, matching `fresh-decoder-per-request` and `single-response-isolation` above. Use `System.Text.Json`'s `Utf8JsonReader`/`JsonDocument` in place of `JSONSerialization` inside a concrete decoder, and drive `Consume` from `HttpClient.GetStreamAsync`/`Stream.CopyToAsync` with a manual byte-buffer loop (or `System.IO.Pipelines.PipeReader` for a more idiomatic incremental read) in place of `URLSession.shared.bytes(for:)` as the byte source `PluginTransport`'s pump supplies.

## Design Decisions

**Decision**: `consume(_:)` and `finish()` are both non-throwing; a frame that cannot be decoded simply yields no event, with no distinct error signal.
**Rationale**: This keeps every conforming decoder simple — none of the five shipped decoders (`ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`, `PlainTextDecoder`) needs error-propagation plumbing — but it means a genuinely malformed, unrecoverable frame is indistinguishable from one that is merely incomplete and awaiting more bytes; both currently vanish silently. This is the same gap the `decode-failure-signal` marker above documents.
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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |

Notes: separation-of-concerns passes because the event enum (`AIStreamEvent`) is kept separate from the decoding protocol (`AIStreamDecoder`), and decoding itself is kept separate from the host's transport and framing — `PluginTransport` supplies the bytes, this file only turns bytes already in hand into typed events. unit-test-coverage passes because `PluginDecoderTests.swift`, `PluginTransportTests.swift`, and `PluginTransportFramingTests.swift` exercise every shipped decoder and the framing contract directly. explicit-error-handling fails because a malformed or unparseable frame is silently swallowed as `[]` from `consume(_:)`/`finish()` with no distinct signal reaching the host, per the open question on decode-failure-signal. fault-tolerance is partial because `consume(_:)` and `finish()` never throw or crash on unexpected byte input — every shipped decoder falls back to returning no event — but a permanently malformed frame stays indistinguishable from one that is merely incomplete, the same gap covered by the open question on decode-failure-signal.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
