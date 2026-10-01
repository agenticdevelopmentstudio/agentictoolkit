---
id: 2067e249-4f97-4575-b8ed-8f55f6dc96df
title: Stream Event
domain: agentictoolkit://cookbook/ai/plugins/stream-event
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A value type describing one event in an AI provider's response
  stream, plus the decoder role that turns raw bytes into a sequence of
  them.
platforms:
- swift
- macos
tags:
- ai-plugin
- streaming
- decoder
depends-on: []
related:
- agentictoolkit://cookbook/ai/plugins/ai-plugin
references: []
approved-by: ''
approved-date: ''
---

# Stream Event

## Overview

The stream event type defines the shape of one event in an assistant
response stream, and the decoder role defines the interface that produces a
sequence of them from a provider's raw bytes. A plugin's request-building
operation describes the outgoing request; a fresh decoder it creates via its
decoder-construction operation then turns whatever bytes the host's
transport receives into stream events, which the host renders. Neither type
performs I/O itself — decoding only transforms bytes already in hand into a
typed event sequence.

## Behavioral Requirements

- **case-set**: The stream event type MUST have exactly three cases — a
  text-delta case carrying a text chunk, a tool-use case carrying an
  identifier, a name, and the raw arguments payload, and an end case
  carrying an optional stop reason.
- **event-concurrent-share-safety**: The stream event type MUST be safe to
  share across concurrent execution contexts, so a decoded value MAY cross
  concurrency domains — e.g. yielded from a background streaming operation
  into an event sequence that a single-context-confined consumer such as a
  local chat session or a plugin chat backend iterates.
- **text-delta-payload**: text-delta's payload MUST be a chunk of assistant
  text and nothing else; this type imposes no constraint on chunk size or
  boundaries — that is each decoder's own choice.
- **tool-use-payload**: tool-use's payload MUST be an identifier, a name,
  and a raw arguments payload, where the arguments payload MUST be the raw,
  undecoded JSON arguments the model supplied — a decoder MUST NOT parse or
  validate that JSON before emitting the event.
- **end-stop-reason-optional**: end's stop-reason value MUST be optional, so
  a decoder MAY report none when the provider gives no reason for stopping.
- **decoder-reference-semantics**: The decoder role MUST require reference
  semantics, so only a reference-identity type may conform — a
  value-semantics conformer MUST fail to satisfy the contract.
- **decoder-single-context-state**: The decoder role MUST NOT require
  safety for sharing across concurrent execution contexts; a conforming
  type MAY hold mutable per-response parsing state without any
  synchronization of its own.
- **stream-decoder-isolation-domain**: Because the decoder role carries no
  cross-context sharing safety, a conforming instance MUST stay within the
  single execution context that created it via the decoder-construction
  operation — strict concurrency checking rejects passing such a decoder
  across a suspension point into a different execution context. The plugin
  transport's HTTP and command paths both create the decoder inside the
  same execution context that then drives every consume/finish call on it.
- **fresh-decoder-per-request**: A new request MUST use a newly created
  decoder instance, per the documented contract "a fresh decoder is created
  per request"; the plugin transport's HTTP and command paths each call
  the decoder-construction operation exactly once, inside the streaming
  operation, before consuming any bytes.
- **single-response-isolation**: One decoder instance MUST be used to
  decode a single response stream only and MUST NOT be shared across two
  concurrent responses, since it holds per-response state and requires no
  thread-safety of its own.
- **consume-accepts-incremental-bytes**: consume MUST accept newly received
  bytes and return the events that can now be fully decoded from them.
- **consume-buffers-partial-frame**: consume MUST retain any partial
  trailing frame internally rather than discard it or error on it, because
  the host MAY split a single logical frame across multiple consume calls.
- **consume-returns-decodable-only**: consume MUST return only the events
  fully decodable from the bytes accumulated so far — it MUST NOT return a
  partial or speculative event for data it has not finished decoding.
- **non-throwing-decode**: consume and finish MUST NOT raise an error —
  both are declared without a failure path — so a decoder that cannot make
  sense of its buffered bytes MUST signal that by omitting an event, not by
  raising an error.
- **finish-returns-final-events**: finish MUST return whatever final events
  the decoder was still holding once the stream closes.
- **finish-default-empty**: A conforming type that does not implement
  finish MUST receive a default implementation that returns an empty list.
- **finish-called-once-per-stream**: The host MUST call finish exactly once
  per response stream, after the stream closes, to flush any trailing
  state.
- **sequential-delivery**: The host MUST deliver bytes to consume and the
  terminating finish call in strict arrival order on one instance, never
  out of order and never interleaved with another response's bytes — this
  is the only ordering guarantee this component's design (per-instance
  mutable state, no cross-context sharing safety) makes workable.
- **host-framing-contract**: The one host in this codebase, the plugin
  transport, MUST feed consume newline-delimited frames — each complete
  line including its trailing newline byte, or one final unterminated
  remainder — rather than arbitrary byte chunks. The decoder role itself
  imposes no such framing; its own documented contract promises only "raw
  bytes... possibly splitting a single logical frame across calls."
- **no-persistence-or-caching**: This component MUST NOT persist any event
  or cache decoder state beyond the data and decoder-instance lifetimes
  already described above — the source contains no file, database, or
  secure-storage write of its own.
- **decode-failure-signal**: NEEDS REVIEW: Not implemented in source.
  Neither the stream event type nor the decoder role defines a case or
  return path meaning "this frame is malformed and will never decode" — a
  permanently corrupt frame (e.g. JSON truncated by a dropped connection,
  or bytes that fail text decoding) is indistinguishable from a frame that
  is merely incomplete and awaiting more bytes; both currently yield an
  empty list from consume with no signal reaching the host. What is
  missing: an explicit decode-error case or failure path the host could
  observe and surface. What would settle it: a design decision on whether
  "permanently malformed" should ever be observable, given every current
  provider's wire format (server-sent-event lines, newline-delimited JSON,
  plain text) is line-oriented and naturally resynchronizes on the next
  frame regardless of one bad line.

## Appearance

Not applicable — this is a value type describing one event and a
stream-decoding role, not a visual component.

## States

Not applicable — this is a value type describing one event and a
stream-decoding role, not a visual component.

## Accessibility

Not applicable — this is a value type describing one event and a
stream-decoding role, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-stream-event-001 | case-set, event-concurrent-share-safety | Inspect the stream event type's declaration. | Exactly three cases — text-delta, tool-use, end — and the declaration itself states safety for sharing across concurrent execution contexts. |
| ai-stream-event-002 | text-delta-payload | Construct a text-delta event with text "Hello", then pattern-match it. | The matched text equals "Hello", with no other payload carried. |
| ai-stream-event-003 | tool-use-payload | Construct a tool-use event with id "call_1", name "search", and raw arguments payload {"q":"cats"}, then pattern-match it. | id equals "call_1", name equals "search", and the arguments payload equals the exact bytes given, byte for byte, unparsed. |
| ai-stream-event-004 | end-stop-reason-optional | Construct an end event with stop-reason none. | Constructs without error; stop-reason is none. |
| ai-stream-event-005 | consume-buffers-partial-frame, non-throwing-decode | Feed a decoder the partial bytes `data: {"type":"content_block_delta","delta":{"text":"Hel` (no trailing newline yet). | Returns an empty list and does not raise an error — no newline byte has completed the line yet. |
| ai-stream-event-006 | consume-buffers-partial-frame, consume-returns-decodable-only | Continuing vector 005: feed the same decoder the remaining bytes `lo"}}` followed by a newline. | Returns exactly one text-delta event carrying "Hello" — the buffered partial frame plus the new bytes decode into exactly one event. |
| ai-stream-event-007 | finish-default-empty | A minimal decoder implementing only consume; call finish on it. | Returns an empty list, from the default implementation. |
| ai-stream-event-008 | finish-called-once-per-stream, fresh-decoder-per-request, host-framing-contract | Run the plugin transport against a command producing the lines "a", "b", "c" followed by an unterminated remainder "tail". | consume receives exactly the frames ["a\n", "b\n", "c\n", "tail"], in order; finish is recorded as called exactly once, after all four; the decoder-construction operation was called exactly once for the run. |
| ai-stream-event-009 | non-throwing-decode, decode-failure-signal | Feed a decoder the bytes `data: not-json` followed by a newline. | Returns an empty list — the unparseable line produces neither an event nor a raised error, and is indistinguishable from a still-incomplete frame. |
| ai-stream-event-010 | single-response-isolation, decoder-single-context-state | Create two decoder instances from one plugin's decoder-construction operation; feed bytes to only the first, then call finish on both. | The fed decoder's finish reflects its buffered content; the untouched decoder's finish yields an empty list — the two instances' state is independent. |
| ai-stream-event-011 | end-stop-reason-optional | Feed a decoder the bytes for a stop-message frame, and, separately, a distinct terminal-marker frame. | Both calls' returned lists contain an end event. |
| ai-stream-event-012 | host-framing-contract | Run two lines "one" and "two", each newline-terminated, through the command transport. | consume receives exactly the frames ["one\n", "two\n"] — no spurious empty trailing frame is produced for output that already ends in a newline. |
| ai-stream-event-013 | decoder-reference-semantics | Attempt to conform a value-semantics type to the decoder role. | Fails: the decoder role requires reference semantics. |
| ai-stream-event-014 | sequential-delivery, host-framing-contract | Feed bytes for "hello\n" to the transport's byte pump one byte at a time. | consume is invoked only once the newline byte (the final byte) is appended — i.e. once per complete line, not once per byte — and finish follows only after the loop over all bytes ends. |
| ai-stream-event-015 | stream-decoder-isolation-domain, fresh-decoder-per-request | Inspect the plugin transport's HTTP and command paths: the decoder-construction operation is called inside the same execution context that later calls consume/finish on the result. | The decoder is never constructed outside, or handed across, the execution context that consumes it — consistent with the decoder role carrying no cross-context sharing safety. |

## Edge Cases

- **Null / empty input**: consume with no bytes SHOULD return an empty
  list — every conformer in this repository does — but the decoder role
  itself imposes no such requirement, so this is each decoder's own
  consistent convention, not a role guarantee.
- **Boundary values**: Not applicable in the numeric sense — this contract
  defines no size-limited field of its own (no maximum byte-buffer length,
  no cap on buffered bytes). Any upper bound on how large an unresolved
  frame may grow before a newline appears is a decision made by the host
  that drives consume, not by this component.
- **Concurrent access**: Two execution contexts MUST NOT call consume or
  finish on the same decoder instance concurrently for two different
  responses; the decoder role carries no cross-context sharing safety and
  its per-response state is unprotected by design (MUST, per
  decoder-single-context-state and single-response-isolation above).
- **Error states**: A malformed or unrecognizable frame (invalid JSON,
  bytes that fail text decoding, an unrecognized event type) MUST NOT cause
  consume or finish to raise an error — the source declares neither
  operation as failure-raising, so a decoder MUST fall back to returning an
  empty list for that frame. See the open question on decode-failure-signal
  for the genuine gap this leaves.
- **Offline / disconnected state**: When the underlying byte stream fails
  before ending normally (e.g. a network read interrupted by a dropped
  connection), the host's byte pump MUST propagate that error immediately,
  and in doing so it MUST NOT reach either the trailing-partial-line
  consume call or the final finish call — any bytes a decoder was still
  buffering internally are discarded without ever reaching the returned
  event sequence; only the raised error, not any partial content, reaches
  the stream's consumer.
- **Cancellation**: the host's byte pump checks for cancellation once per
  byte inside its loop; a cancelled consuming operation MUST therefore be
  able to stop delivery to consume mid-frame, and in that case finish MUST
  NOT be called either — cancellation and a dropped connection produce the
  same outcome for this component: no flush, only whatever events were
  already yielded before the cancellation was observed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| data (parameter to consume) | byte payload | none — required | Newly received bytes for the response currently being decoded; MAY be a full frame, a partial frame, or an empty buffer. |
| decoder instance | abstract decoder role | none — required | Supplied per request by the conforming plugin's decoder-construction operation (see the sibling plugin recipe); this component neither creates nor configures a decoder itself. |

This component defines no environment variable and no settings key of its
own — every value it operates on arrives as a parameter, either the raw
bytes handed to consume or the decoder instance itself.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination — it decodes response bytes into events, not app navigation.

## Localization

Not applicable: this component contains no user-facing string literal of
its own — text-delta's text and tool-use's name/arguments payload are
opaque provider- or model-produced content passed through unmodified, not a
string this component authors, formats, or displays.

## Accessibility Options

Not applicable: this component presents no UI, so it responds to no Reduce
Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this component contains no feature-flag or settings-key
reference of its own.

## Analytics

Not applicable: this component contains no analytics or event-tracking
call.

## Privacy

- **Data handled**: A text-delta or tool-use event MAY carry conversation
  content or tool-call arguments the provider or model produced for one
  chat turn; this component itself defines no credential or token field —
  those live in the sibling provider-configuration and chat-context types,
  not here.
- **Storage**: This component performs no storage of its own — see
  no-persistence-or-caching above; a decoder's buffered bytes and any
  decoded events live only in memory for the duration of one response
  stream.
- **Transmission**: This component never transmits data; it only decodes
  bytes the host's transport has already received.
- **Retention**: None — a stream event is not retained past the
  event-sequence iteration that consumes it, and a decoder's internal
  buffer is discarded with the decoder instance once its one response
  stream ends.

## Logging

Not applicable: this component contains no logging call; it is a pure
data-and-role declaration with no side effects of its own.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift`. Nothing here is SwiftUI-specific — `AIStreamEvent` and `AIStreamDecoder` are Foundation-only and consumed identically by a SwiftUI or AppKit host through `PluginTransport`'s `AsyncThrowingStream<AIStreamEvent, Error>`. Concretely, `AIStreamEvent` is a `Sendable` enum (`public enum AIStreamEvent: Sendable`) with cases `textDelta(String)`, `toolUse(id: String, name: String, argumentsJSON: Data)`, and `end(stopReason: String?)` — the event-concurrent-share-safety requirement above is this `Sendable` conformance. `AIStreamDecoder` is declared `public protocol AIStreamDecoder: AnyObject` with no `Sendable` conformance: the `AnyObject` bound is the decoder-reference-semantics requirement (only a `class` may conform), and the absent `Sendable` is the decoder-single-context-state requirement, enforced by Swift's strict concurrency checking (`SWIFT_STRICT_CONCURRENCY: complete`) rejecting a non-`Sendable` value crossing an `await` boundary.
- **Compose**: Model `AiStreamEvent` as a Kotlin `sealed interface` with data classes `TextDelta(val text: String)`, `ToolUse(val id: String, val name: String, val argumentsJson: ByteArray)`, and `End(val stopReason: String?)`; enumerate over it with a `when` expression, which the compiler treats as exhaustive the way Swift's `switch` does. `AiStreamDecoder` becomes an interface with `fun consume(data: ByteArray): List<AiStreamEvent>` and a default `fun finish(): List<AiStreamEvent> = emptyList()`, mirroring the Swift protocol extension's default.
- **React/Web**: Represent `AIStreamEvent` as a discriminated union — `{ kind: 'textDelta', text: string } | { kind: 'toolUse', id: string, name: string, argumentsJSON: Uint8Array } | { kind: 'end', stopReason?: string }` — and `AIStreamDecoder` as an interface with `consume(data: Uint8Array): AIStreamEvent[]` and an optional `finish?(): AIStreamEvent[]`. A web port could instead lean on the platform's native streaming primitive, a `TransformStream<Uint8Array, AIStreamEvent>`, rather than the manual `consume`/`finish` pair, since the browser's `ReadableStream` already models incremental delivery plus an explicit close.
- **AppKit / UIKit**: Identical to the SwiftUI note — this component is UI-framework-agnostic; only the application embedding `AIPluginKit` differs, never this contract.
- **WinUI 3**: Model `AiStreamEvent` as an abstract `record` with three sealed derived records — `TextDelta(string Text)`, `ToolUse(string Id, string Name, byte[] ArgumentsJson)`, `End(string? StopReason)` — enabling exhaustive `switch` pattern matching over `is` patterns, the closest .NET analogue to Swift's closed enum. Declare `IAiStreamDecoder` as `IReadOnlyList<AiStreamEvent> Consume(byte[] data);` plus a C# 8+ default interface method `IReadOnlyList<AiStreamEvent> Finish() => Array.Empty<AiStreamEvent>();` to mirror the Swift protocol extension's default `finish()`. Because `AIStreamDecoder` is deliberately non-`Sendable` and holds mutable per-response state, a WinUI 3 port MUST construct a fresh `IAiStreamDecoder` per request and MUST NOT register one as a singleton or reuse it across `HttpClient` calls, matching `fresh-decoder-per-request` and `single-response-isolation` above. Use `System.Text.Json`'s `Utf8JsonReader`/`JsonDocument` in place of `JSONSerialization` inside a concrete decoder, and drive `Consume` from `HttpClient.GetStreamAsync`/`Stream.CopyToAsync` with a manual byte-buffer loop (or `System.IO.Pipelines.PipeReader` for a more idiomatic incremental read) in place of `URLSession.shared.bytes(for:)` as the byte source `PluginTransport`'s pump supplies.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift` |

## Design Decisions

**Decision**: `consume(_:)` and `finish()` are both non-throwing; a frame that cannot be decoded simply yields no event, with no distinct error signal.
**Rationale**: This keeps every conforming decoder simple — none of the five shipped decoders (`ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`, `PlainTextDecoder`) needs error-propagation plumbing — but it means a genuinely malformed, unrecoverable frame is indistinguishable from one that is merely incomplete and awaiting more bytes; both currently vanish silently. This is the same gap the open question on decode-failure-signal documents.
**Approved**: pending

**Decision**: `AIStreamEvent` declares three cases — `textDelta`, `toolUse`, `end` — even though no `AIStreamDecoder` shipped in this repository (`ClaudeSSEDecoder`, `OpenAIReplyDecoder`, `GeminiReplyDecoder`, `ChatReplyDecoder`, `PlainTextDecoder`) ever returns a `.toolUse` event.
**Rationale**: Every consumer's `switch` over `AIStreamEvent` (`LocalChatSession.swift`, `AIPluginChatBackend.swift`, `AIPluginLanguageModelProvider.swift`, `ChatBackendSession.swift`) already handles `.toolUse` exhaustively, so the case is part of the declared contract in preparation for a future tool-calling-capable decoder, not dead code — a source-fidelity note rather than a gap, since nothing here needs `.toolUse` to be produced today.
**Approved**: pending

**Decision**: `AIStreamDecoder` deliberately omits `Sendable`, unlike the sibling `AIPlugin` protocol, which requires it. (Apple platform implementation.)
**Rationale**: A decoder's whole purpose is to hold mutable per-response parsing state (buffered bytes, partial JSON); requiring `Sendable` would force every conformer to add locking for state that is, by design, never touched from more than one task. `AIPlugin` instances, by contrast, are commonly cached and reused across concurrent requests (see the sibling `AIPlugin` recipe's `concurrent-invocation-safety` requirement), so it needs `Sendable` where a decoder does not.
**Approved**: pending

**Decision**: `finish()` provides a default no-op implementation via a protocol extension rather than being a required method every conformer must implement. (Apple platform implementation.)
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
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.3 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.4 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
