<!-- leaf: implement-general-1/dev-chat-model · source: dev-chat-model.md -->

**Rules** (cite as `implement-general-1/dev-chat-model#<slug>`):

- `chat-session-conformance` MUST
- `sendable-declaration` MUST
- `construction-defaults` MUST
- `ready-on-subscribe` MUST
- `send-requires-active-subscription` MUST
- `send-echoes-user-text-verbatim` MUST
- `send-transitions-to-responding` MUST
- `reply-independent-of-input` MUST
- `response-started-unconditional` MUST
- `chunking-is-character-based` MUST
- `chunk-size-non-positive-single-chunk` MUST
- `chunk-size-positive-empty-reply-no-chunks` MUST
- `final-chunk-may-be-short` MUST
- `delta-events-ordered-and-delayed` MUST
- `cancellation-stops-only-remaining-chunks` MUST
- `response-finished-stop-reason-fixed` MUST
- `turn-ends-with-ready` MUST
- `interrupt-cancels-live-turn` MUST
- `close-cancels-and-finishes` MUST
- `termination-cancels-live-turn` MUST
- `clear-is-inert` MUST
- `no-turn-failed-emission` MUST
- `no-io-side-effects` MUST
- `continuation-access-is-lock-protected` MUST
- `second-subscription-silently-supersedes-first` MUST

# MockChatSession

## Overview

`MockChatSession` (`packages/apple/AgenticToolkit/Core/Chat/MockChatSession.swift`) is a scripted, in-memory `ChatSession` conformer for tests, previews, and demos. Its doc comment states its whole job plainly: "A scripted `ChatSession` for tests, previews, and demos. On `send`, it echoes the user turn, then streams a canned reply in fixed-size chunks. No network, no subprocess.". A caller constructs it with a fixed `reply` string, hands it to `AIChatViewModel(session:)` exactly as it would any other `ChatSession` conformer (`FeedChatSession`, a real network- or subprocess-backed session), and gets a realistic-looking streamed turn back for every `send(_:)` call, with no external dependency of any kind. It never fails a turn and never performs I/O; it exists purely to exercise the full `ChatSession`/`ChatEvent` contract deterministically.

## Behavioral Requirements

- **chat-session-conformance**: `MockChatSession` MUST conform to `ChatSession` (`MockChatSession.swift`), implementing `events()`, `send(_:)`, `interrupt()`, and `close()`. It MUST NOT override `clear()`, so a caller invoking `clear()` on it MUST receive only `ChatSession`'s protocol-extension default no-op (`ChatSession.swift`), whose doc comment reads "Clear the conversation history. Does not affect the active turn." (`ChatSession.swift`).
- **sendable-declaration**: `MockChatSession` MUST be declared `final class MockChatSession: ChatSession, @unchecked Sendable`. `@unchecked Sendable` disables the compiler's own cross-isolation-domain checking for this type, so every guarantee of safe concurrent use rests entirely on the type's own locking rather than on anything Swift's concurrency checker verifies for it.
- **construction-defaults**: `MockChatSession.init(reply:chunkSize:interChunkDelay:)` MUST default `reply` to `"This is a mock reply."`, `chunkSize` to `3`, and `interChunkDelay` to `.milliseconds(10)` when a caller omits any of the three.
- **ready-on-subscribe**: Each call to `events()` MUST yield exactly one `.stateChanged(.ready)` event immediately, before the enclosing `AsyncStream` initializer returns control to the caller.
- **send-requires-active-subscription**: `send(_:)` MUST read the stored `continuation` under `lock` and, when none is stored (no prior `events()` call has yet run), MUST return immediately without yielding any event.
- **send-echoes-user-text-verbatim**: On a `send(_ text:)` call that does have an active continuation, the component MUST yield `.userMessage(ChatMessage(role: .user, text: text))` using the caller's `text` completely unmodified — not trimmed, and with no requirement that it be non-empty. `ChatMessage.init`'s defaults then supply that message's `id` as a fresh `UUID().uuidString`, `timestamp` as the current `Date()`, `isStreaming` as `false`, `delivery` as `.settled`, and `attribution` as `nil` (`ChatMessage.swift`).
- **send-transitions-to-responding**: Immediately after yielding `.userMessage`, `send(_:)` MUST yield `.stateChanged(.responding)`.
- **reply-independent-of-input**: The assistant reply streamed for a turn MUST always be exactly the `reply` string supplied at construction and MUST NOT depend on, incorporate, or vary with the `text` argument passed to `send(_:)` — the chunk array is computed as `Self.chunk(reply, size: chunkSize)`, reading only the stored `reply`.
- **response-started-unconditional**: The live turn's `Task` MUST yield `.responseStarted(messageID:)`, carrying a freshly generated `UUID().uuidString`, before evaluating any chunk, and MUST do so even if the `Task` is already cancelled by the time it begins running — the cancellation check does not gate this yield.
- **chunking-is-character-based**: `Self.chunk(_:size:)` MUST split `reply` using `Character`-count offsets — `str.count` and `str.index(_:offsetBy:)` — never UTF-8 byte or UTF-16 offsets. Every chunk boundary it produces MUST therefore fall on an extended grapheme cluster boundary and MUST NOT split a multi-scalar character.
- **chunk-size-non-positive-single-chunk**: When `size <= 0`, `chunk(_:size:)` MUST return the entire `str` as a single-element array, `[str]`, including the case where `str` is itself the empty string, which yields `[""]`.
- **chunk-size-positive-empty-reply-no-chunks**: When `size > 0` and `reply` is the empty string, `chunk(_:size:)` MUST return an empty array, `[]`, because `stride(from: 0, to: 0, by: size)` produces no steps. The live turn then yields no `.responseDelta` event at all for that turn.
- **final-chunk-may-be-short**: When `reply`'s character count is not an exact multiple of `size`, the last chunk `chunk(_:size:)` returns MUST be shorter than `size` characters, since `end` falls back to `str.endIndex` via `limitedBy:`.
- **delta-events-ordered-and-delayed**: For each chunk `chunk(_:size:)` returned, the live turn MUST yield `.responseDelta(messageID:, text: chunk)` for that chunk, in the array's order, and MUST await `Task.sleep(for: interChunkDelay)` (with any thrown `CancellationError` swallowed via `try?`) before moving to the next chunk.
- **cancellation-stops-only-remaining-chunks**: When the live turn's `Task` is cancelled — via `interrupt()` or otherwise — the `for` loop MUST stop yielding further `.responseDelta` events at its next `Task.isCancelled` check. This MUST NOT prevent the same `Task` from then yielding `.responseFinished(messageID:, stopReason: "end_turn")` and `.stateChanged(.ready)`, since both calls sit unconditionally outside the loop. A cancelled turn therefore still reports as normally finished and the session still returns to `.ready`.
- **response-finished-stop-reason-fixed**: Every turn's `.responseFinished` event MUST carry the literal stop reason `"end_turn"`; `MockChatSession` has no code path that produces any other value.
- **turn-ends-with-ready**: The live turn's `Task` MUST end, in every case it runs to completion (cancelled or not), by yielding `.stateChanged(.ready)`.
- **interrupt-cancels-live-turn**: `interrupt()` MUST call `liveTurn?.cancel()` and take no other action. Calling it while no turn is in flight (`liveTurn` is `nil`) MUST be a safe no-op, matching `ChatSession.interrupt()`'s documented contract, "Interrupt the in-flight assistant response. No-op if none is running." (`ChatSession.swift`).
- **close-cancels-and-finishes**: `close()` MUST cancel the current `liveTurn`, if any, and MUST call `finish()` on the stored continuation, if any, ending the `AsyncStream` `events()` returned.
- **termination-cancels-live-turn**: Whenever the `AsyncStream` returned by `events()` is torn down through any termination path, its `onTermination` handler MUST cancel `liveTurn` — this fires independently of, and in addition to, `close()`'s own cancellation.
- **clear-is-inert**: Because `MockChatSession` implements no `clear()` of its own, a caller's call to `clear()` MUST resolve to `ChatSession`'s default extension implementation, which does nothing (`ChatSession.swift`); it MUST NOT reset `reply`, `chunkSize`, `interChunkDelay`, `continuation`, or `liveTurn`.
- **no-turn-failed-emission**: `MockChatSession` MUST NOT ever yield a `.turnFailed` event. No code path in `send(_:)` or its live-turn `Task` constructs a `ChatError`, consistent with the type's stated role as an always-succeeding scripted double rather than a network- or subprocess-backed session (doc comment).
- **no-io-side-effects**: `MockChatSession` MUST perform no file, network, process, or notification side effect. Its doc comment states "No network, no subprocess", and its implementation touches only in-memory state (`reply`, `chunkSize`, `interChunkDelay`, `continuation`, `liveTurn`) plus Foundation's `UUID`, `Task`, and `NSLock`.
- **continuation-access-is-lock-protected**: Every read or write of `continuation` MUST go through the `lock`-protected `withLock` helper (`send(_:)`; `close()`) or the equivalent manual `lock.lock()`/`unlock()` pair (`events()`), so two callers touching `continuation` from different threads MUST NOT race with each other.
- **second-subscription-silently-supersedes-first**: Because `events()` only ever overwrites the single stored `continuation`, calling `events()` a second time on the same instance MUST replace it without finishing the `AsyncStream` the first call returned. The first stream MUST then simply stop receiving any further event — it is never itself finished by the second subscription. `ChatSession.events()`'s own doc comment already scopes usage to "Subscribe once" (`ChatSession.swift`), so this is the documented single-subscriber contract's actual failure mode when that contract is violated, not a defect specific to `MockChatSession`.
- **live-turn-synchronization**: NEEDS REVIEW: Not implemented in source. `liveTurn` is read or written without holding `lock` in four places: `send(_:)`'s assignment `liveTurn = Task { ... }`, `interrupt()`'s `liveTurn?.cancel()`, `close()`'s `liveTurn?.cancel()`, and the `onTermination` closure's `self?.liveTurn?.cancel()` — while the enclosing type is declared `@unchecked Sendable`, a promise that concurrent cross-thread access has been made safe some other way. `continuation` receives exactly that treatment (see **continuation-access-is-lock-protected**); `liveTurn` does not. Two of these four sites racing — for example, `send(_:)` assigning a new `Task` on one thread while `interrupt()` reads the old value on another — is an unsynchronized data race on a `var` with no ordering rule between them. Settling this needs either bringing every `liveTurn` access under the same `lock` `continuation` already uses, or an explicit statement from the maintainer that `MockChatSession` is intended for single-isolation-domain use only (which nothing in its declared conformance states).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `reply` | `String` | `"This is a mock reply."` | The full assistant reply text streamed back for every turn, regardless of what the caller sends. |
| `chunkSize` | `Int` | `3` | The number of `Character`s per `.responseDelta` chunk. A value at or below `0` yields the whole reply as one chunk. |
| `interChunkDelay` | `Duration` | `.milliseconds(10)` | The delay awaited between successive `.responseDelta` chunks. |

`MockChatSession.swift` defines no environment variable and no settings key of its own — every value it operates on arrives as one of the three constructor parameters above.

