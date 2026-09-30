<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-stream-event · source: ai-plugin-runtime-ai-plugin-kit-ai-stream-event.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-stream-event#<slug>`):

- `case-set` MUST
- `event-sendable` MUST
- `text-delta-payload` MUST
- `tool-use-payload` MUST
- `end-stop-reason-optional` MUST
- `decoder-class-bound` MUST
- `decoder-non-sendable-state` MUST
- `stream-decoder-isolation-domain` MUST
- `fresh-decoder-per-request` MUST
- `single-response-isolation` MUST
- `consume-accepts-incremental-bytes` MUST
- `consume-buffers-partial-frame` MUST
- `consume-returns-decodable-only` MUST
- `non-throwing-decode` MUST
- `finish-returns-final-events` MUST
- `finish-default-empty` MUST
- `finish-called-once-per-stream` MUST
- `sequential-delivery` MUST
- `host-framing-contract` MUST
- `no-persistence-or-caching` MUST
- `data-handled` MAY — A textDelta or toolUse event MAY carry conversation content or tool-call arguments the provider or model produced for …

# AIStreamEvent

## Overview

`AIStreamEvent.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIStreamEvent.swift`) defines the shape of one event in an assistant response stream (`AIStreamEvent`, a `Sendable` enum) and the protocol that produces a sequence of them from a provider's raw bytes (`AIStreamDecoder`). An `AIPlugin` conformer's `buildRequest(_:)` describes the outgoing request; a fresh `AIStreamDecoder` it creates via `makeDecoder()` then turns whatever bytes the host's transport receives into `AIStreamEvent`s, which the host renders. Neither type performs I/O itself — decoding only transforms bytes already in hand into a typed event sequence.

## Behavioral Requirements

- **case-set**: `AIStreamEvent` MUST have exactly three cases — `textDelta(String)`, `toolUse(id: String, name: String, argumentsJSON: Data)`, and `end(stopReason: String?)` (`AIStreamEvent.swift`).
- **event-sendable**: `AIStreamEvent` MUST conform to `Sendable`, so a decoded value MAY cross concurrency domains — e.g. yielded from `PluginTransport.run`'s background `Task` into an `AsyncThrowingStream<AIStreamEvent, Error>` that a `@MainActor`-isolated consumer such as `LocalChatSession` or `AIPluginChatBackend` iterates.
- **text-delta-payload**: `textDelta`'s associated value MUST be a chunk of assistant text and nothing else; this type imposes no constraint on chunk size or boundaries — that is each decoder's own choice.
- **tool-use-payload**: `toolUse`'s associated values MUST be `id: String`, `name: String`, and `argumentsJSON: Data`, where `argumentsJSON` MUST be the raw, undecoded JSON arguments the model supplied ("the raw JSON arguments") — a decoder MUST NOT parse or validate that JSON before emitting the event.
- **end-stop-reason-optional**: `end`'s `stopReason` MUST be an `Optional<String>`, so a decoder MAY report `nil` when the provider gives no reason for stopping.
- **decoder-class-bound**: `AIStreamDecoder` MUST require `AnyObject`, so only a reference type (a `class`) may conform — a `struct` conformer fails to compile.
- **decoder-non-sendable-state**: `AIStreamDecoder` MUST NOT require `Sendable` conformance; a conforming type MAY hold mutable per-response parsing state without any synchronization of its own ("may hold mutable per-response parsing state").
- **stream-decoder-isolation-domain**: Because `AIStreamDecoder` declares no `Sendable` conformance, a conforming instance MUST stay within the single concurrency domain (`Task`) that created it via `makeDecoder()` — Swift's strict concurrency checking (`SWIFT_STRICT_CONCURRENCY: complete`) rejects passing a non-`Sendable` decoder across an `await` boundary into a different isolation domain. `PluginTransport.runHTTP`/`runCommand` both create the decoder inside the same task that then drives every `consume(_:)`/`finish()` call on it.
- **fresh-decoder-per-request**: A new request MUST use a newly created `AIStreamDecoder` instance, per the doc comment "a fresh decoder is created per request (see `AIPlugin.makeDecoder()`)"; `PluginTransport.runHTTP` and `runCommand` each call `plugin.makeDecoder()` exactly once, inside the streaming task, before consuming any bytes.
- **single-response-isolation**: One `AIStreamDecoder` instance MUST be used to decode a single response stream only and MUST NOT be shared across two concurrent responses, since it holds per-response state and requires no thread-safety of its own.
- **consume-accepts-incremental-bytes**: `consume(_ data: Data) -> [AIStreamEvent]` MUST accept newly received bytes and return the events that can now be fully decoded from them.
- **consume-buffers-partial-frame**: `consume(_:)` MUST retain any partial trailing frame internally rather than discard it or error on it, because the host MAY split a single logical frame across multiple `consume(_:)` calls.
- **consume-returns-decodable-only**: `consume(_:)` MUST return only the events fully decodable from the bytes accumulated so far — it MUST NOT return a partial or speculative event for data it has not finished decoding ("returning only the events it can fully decode").
- **non-throwing-decode**: `consume(_:)` and `finish()` MUST NOT throw — both are declared without `throws` — so a decoder that cannot make sense of its buffered bytes MUST signal that by omitting an event, not by raising an error.
- **finish-returns-final-events**: `finish() -> [AIStreamEvent]` MUST return whatever final events the decoder was still holding once the stream closes.
- **finish-default-empty**: A conforming type that does not implement `finish()` MUST receive the protocol extension's default implementation, which returns `[]`.
- **finish-called-once-per-stream**: The host MUST call `finish()` exactly once per response stream, after the stream closes, to flush any trailing state ("the host calls `finish()` once to flush any trailing state").
- **sequential-delivery**: The host MUST deliver bytes to `consume(_:)` and the terminating `finish()` call in strict arrival order on one instance, never out of order and never interleaved with another response's bytes — this is the only ordering guarantee this component's design (per-instance mutable state, no `Sendable`) makes workable.
- **host-framing-contract**: The one host in this codebase, `PluginTransport`, MUST feed `consume(_:)` newline-delimited frames — each complete line including its trailing `0x0A` byte, or one final unterminated remainder — rather than arbitrary byte chunks (`PluginTransport.pump(bytes:through:into:)` for HTTP, and its `SubprocessChannel`-backed `.newlineDelimited` framing for a command). `AIStreamDecoder` itself imposes no such framing; its own doc comment promises only "raw bytes... possibly splitting a single logical frame across calls."
- **no-persistence-or-caching**: `AIStreamEvent.swift` MUST NOT persist any event or cache decoder state beyond the `Data` and decoder-instance lifetimes already described above — the source contains no file, database, `UserDefaults`, or Keychain write of its own.
- **decode-failure-signal**: NEEDS REVIEW: Not implemented in source. Neither `AIStreamEvent` nor `AIStreamDecoder` defines a case or return path meaning "this frame is malformed and will never decode" — a permanently corrupt frame (e.g. JSON truncated by a dropped connection, or bytes that fail `String(data:encoding:.utf8)`) is indistinguishable from a frame that is merely incomplete and awaiting more bytes; both currently yield `[]` from `consume(_:)` with no signal reaching the host. What is missing: an explicit decode-error case or throwing path the host could observe and surface (e.g. a `case error(Error)` on `AIStreamEvent`, or `consume(_:) throws -> [AIStreamEvent]`). What would settle it: a design decision on whether "permanently malformed" should ever be observable, given every current provider's wire format (SSE `data:` lines, newline-delimited JSON, plain text) is line-oriented and naturally resynchronizes on the next frame regardless of one bad line.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data` (parameter to `consume(_:)`) | `Data` | none — required | Newly received bytes for the response currently being decoded; MAY be a full frame, a partial frame, or an empty buffer. |
| decoder instance | `any AIStreamDecoder` | none — required | Supplied per request by the conforming `AIPlugin`'s `makeDecoder()` (see the sibling `AIPlugin` recipe); `AIStreamEvent.swift` neither creates nor configures a decoder itself. |

This file defines no environment variable and no settings key of its own — every value it operates on arrives as a parameter, either the raw `Data` handed to `consume(_:)` or the decoder instance itself.

## Privacy

- **Data handled**: A `textDelta` or `toolUse` event MAY carry conversation content or tool-call arguments the provider or model produced for one chat turn; `AIStreamEvent.swift` itself defines no credential or token field — those live in the sibling `AIPluginConfig`/`AIChatContext` types, not here.
- **Storage**: `AIStreamEvent.swift` performs no storage of its own — see `no-persistence-or-caching` above; a decoder's buffered bytes and any decoded events live only in memory for the duration of one response stream.
- **Transmission**: This component never transmits data; it only decodes bytes the host's transport (`PluginTransport`) has already received.
- **Retention**: None — an `AIStreamEvent` is not retained past the `AsyncThrowingStream` iteration that consumes it, and a decoder's internal buffer is discarded with the decoder instance once its one response stream ends.

