---
id: 91bd3986-da9d-418e-a969-c878efa88d50
title: Mock Chat Session
domain: agentictoolkit://cookbook/ai/chat/mock-chat-session
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Scripted, in-memory ChatSession test double that echoes a sent turn, then
  streams a fixed reply in character chunks.
platforms:
- swift
- macos
tags:
- chat-session
- mock
- streaming
depends-on: []
related:
- agentictoolkit://cookbook/ai/chat/chat-window/chat-view
references: []
approved-by: ''
approved-date: ''
---

# Mock Chat Session

## Overview

This component is a scripted, in-memory `ChatSession` implementation for tests, previews, and demos. Its stated role is plain: it is a scripted `ChatSession` for tests, previews, and demos, and on send it echoes the user turn, then streams a canned reply in fixed-size chunks, with no network and no subprocess. A caller constructs it with a fixed `reply` string, hands it to a chat view model exactly as it would any other `ChatSession` implementation (an ordinary in-memory feed, or a real network- or subprocess-backed session), and gets a realistic-looking streamed turn back for every `send(_:)` call, with no external dependency of any kind. It never fails a turn and never performs I/O; it exists purely to exercise the full `ChatSession`/`ChatEvent` contract deterministically.

## Behavioral Requirements

- **chat-session-conformance**: The component MUST implement `ChatSession`'s `events()`, `send(_:)`, `interrupt()`, and `close()`. It MUST NOT provide its own `clear()`, so a caller invoking `clear()` on it MUST see only the shared no-op default behavior `ChatSession` specifies for any implementation that does not override it: "Clear the conversation history. Does not affect the active turn."
- **construction-defaults**: Constructing the component with any of its three parameters omitted MUST default `reply` to `"This is a mock reply."`, `chunkSize` to `3`, and `interChunkDelay` to 10 milliseconds.
- **ready-on-subscribe**: Each call to `events()` MUST yield exactly one `.stateChanged(.ready)` event immediately, before the event stream itself finishes being set up and returns control to the caller.
- **send-requires-active-subscription**: `send(_:)` MUST check, under the same protection described in **continuation-access-is-lock-protected**, whether a subscriber handle is currently stored and, when none is (no prior `events()` call has yet run), MUST return immediately without yielding any event.
- **send-echoes-user-text-verbatim**: On a `send(_ text:)` call that does have an active subscriber, the component MUST yield `.userMessage(ChatMessage(role: .user, text: text))` using the caller's `text` completely unmodified — not trimmed, and with no requirement that it be non-empty. `ChatMessage`'s default field values then supply that message's `id` as a freshly generated unique identifier string, `timestamp` as the current time, `isStreaming` as `false`, `delivery` as `.settled`, and `attribution` as `nil`.
- **send-transitions-to-responding**: Immediately after yielding `.userMessage`, `send(_:)` MUST yield `.stateChanged(.responding)`.
- **reply-independent-of-input**: The assistant reply streamed for a turn MUST always be exactly the `reply` string supplied at construction and MUST NOT depend on, incorporate, or vary with the `text` argument passed to `send(_:)` — the chunks streamed are computed from the stored `reply` alone, using the chunking behavior described below.
- **response-started-unconditional**: The live turn MUST yield `.responseStarted(messageID:)`, carrying a freshly generated unique identifier string, before evaluating any chunk, and MUST do so even if the turn has already been cancelled by the time it begins running — the cancellation check does not gate this yield.
- **chunking-is-character-based**: The chunking operation MUST split `reply` using character-count offsets — grapheme-cluster-aware indexing — never raw UTF-8 byte or UTF-16 offsets. Every chunk boundary it produces MUST therefore fall on an extended grapheme cluster boundary and MUST NOT split a multi-scalar character.
- **chunk-size-non-positive-single-chunk**: When the chunk size is zero or negative, the chunking operation MUST return the entire reply as a single chunk, including when the reply is itself the empty string, which yields one empty-string chunk.
- **chunk-size-positive-empty-reply-no-chunks**: When the chunk size is positive and `reply` is the empty string, the chunking operation MUST return no chunks at all. The live turn then yields no `.responseDelta` event at all for that turn.
- **final-chunk-may-be-short**: When `reply`'s character count is not an exact multiple of the chunk size, the last chunk the chunking operation returns MUST be shorter than the chunk size.
- **delta-events-ordered-and-delayed**: For each chunk the chunking operation returns, the live turn MUST yield `.responseDelta(messageID:, text: chunk)` for that chunk, in order, and MUST await an inter-chunk delay of `interChunkDelay`, swallowing a cancellation error raised by that wait, before moving to the next chunk.
- **cancellation-stops-only-remaining-chunks**: When the live turn is cancelled — via `interrupt()` or otherwise — it MUST stop yielding further `.responseDelta` events at its next cancellation check. This MUST NOT prevent the same live turn from then yielding `.responseFinished(messageID:, stopReason: "end_turn")` and `.stateChanged(.ready)`, since both are yielded unconditionally rather than being gated by that check. A cancelled turn therefore still reports as normally finished and the session still returns to `.ready`.
- **response-finished-stop-reason-fixed**: Every turn's `.responseFinished` event MUST carry the literal stop reason `"end_turn"`; the component has no code path that produces any other value.
- **turn-ends-with-ready**: The live turn MUST end, in every case it runs to completion (cancelled or not), by yielding `.stateChanged(.ready)`.
- **interrupt-cancels-live-turn**: `interrupt()` MUST cancel the in-flight turn's task handle, if any, and take no other action. Calling it while no turn is in flight MUST be a safe no-op, matching `ChatSession.interrupt()`'s documented contract: "Interrupt the in-flight assistant response. No-op if none is running."
- **close-cancels-and-finishes**: `close()` MUST cancel the current in-flight turn, if any, and MUST end the event stream `events()` returned, if a subscriber is currently stored.
- **termination-cancels-live-turn**: Whenever the event stream `events()` returns is torn down through any termination path, that teardown MUST itself cancel the in-flight turn — this fires independently of, and in addition to, `close()`'s own cancellation.
- **clear-is-inert**: Because the component implements no `clear()` of its own, a caller's call to `clear()` MUST resolve to `ChatSession`'s shared default behavior, which does nothing; it MUST NOT reset `reply`, `chunkSize`, `interChunkDelay`, the stored subscriber handle, or the in-flight turn's task handle.
- **no-turn-failed-emission**: The component MUST NOT ever yield a `.turnFailed` event. No code path in `send(_:)` or its live turn constructs a `ChatError`, consistent with its stated role as an always-succeeding scripted double rather than a network- or subprocess-backed session.
- **no-io-side-effects**: The component MUST perform no file, network, process, or notification side effect. Its stated role is "No network, no subprocess", and its implementation touches only in-memory state — `reply`, `chunkSize`, `interChunkDelay`, the stored subscriber handle, and the in-flight turn's task handle — plus ordinary identifier-generation, concurrency, and locking primitives.
- **continuation-access-is-lock-protected**: Every read or write of the stored subscriber handle MUST be protected against concurrent access, so two callers touching it from different threads MUST NOT race with each other.
- **second-subscription-silently-supersedes-first**: Because `events()` only ever overwrites the single stored subscriber handle, calling `events()` a second time on the same instance MUST replace it without ending the event stream the first call returned. The first stream MUST then simply stop receiving any further event — it is never itself ended by the second subscription. `ChatSession.events()`'s own documented contract already scopes usage to "Subscribe once", so this is that documented single-subscriber contract's actual failure mode when violated, not a defect specific to this component.
- **live-turn-synchronization**: NEEDS REVIEW: Not implemented in source. The in-flight turn's task handle is read or written without the same protection the stored subscriber handle receives, in four places: assigning a new live turn on `send(_:)`, and cancelling it from `interrupt()`, `close()`, and the event stream's own termination handling — while the component declares itself safe for concurrent use some other way. The stored subscriber handle receives exactly that protection (see **continuation-access-is-lock-protected**); the in-flight turn's task handle does not. Two of these four sites racing — for example, `send(_:)` assigning a new live turn on one thread while `interrupt()` reads the old value on another — is an unsynchronized data race with no ordering rule between them. Settling this needs either bringing every access to the in-flight turn's task handle under the same protection the stored subscriber handle already uses, or an explicit statement from the maintainer that this component is intended for single-thread/single-isolation-domain use only (which nothing in its declared conformance states).

## Appearance

Not applicable — this is a headless, in-memory test double for a chat engine, not a visual component.

## States

Not applicable — this is a headless, in-memory test double for a chat engine, not a visual component. Its runtime lifecycle is expressed through the `ChatEvent.stateChanged(ChatSessionState)` events it emits (`.ready`, `.responding`; it never emits `.connecting`, `.failed`, or `.closed`), which are captured under Behavioral Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a headless, in-memory test double for a chat engine, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dev-chat-model-001 | ready-on-subscribe | A freshly constructed instance of the component; subscribe via `events()` and take the first event | First event received is `.stateChanged(.ready)` (`MockChatSessionTests.streamsScriptedReply`) |
| dev-chat-model-002 | send-echoes-user-text-verbatim, send-transitions-to-responding, reply-independent-of-input, delta-events-ordered-and-delayed, response-finished-stop-reason-fixed, turn-ends-with-ready | An instance constructed with `reply: "Hi there"` and `chunkSize: 3`; subscribe, then `send("hello")` | Received events include, in order: `.stateChanged(.ready)`, `.userMessage` with `text == "hello"`, `.stateChanged(.responding)`, `.responseStarted`, a run of `.responseDelta` events whose `text` values concatenate to exactly `"Hi there"`, `.responseFinished(stopReason: "end_turn")`, `.stateChanged(.ready)` (`MockChatSessionTests.streamsScriptedReply`) |
| dev-chat-model-003 | chunk-size-positive-empty-reply-no-chunks | An instance constructed with `reply: ""` and `chunkSize: 3`; subscribe, then `send("x")` | `.responseStarted` is followed immediately by `.responseFinished(stopReason: "end_turn")` with zero `.responseDelta` events between them (the chunking operation produces no chunks for an empty reply with a positive chunk size) |
| dev-chat-model-004 | chunk-size-non-positive-single-chunk | An instance constructed with `reply: "Hi"` and `chunkSize: 0`; subscribe, then `send("x")` | Exactly one `.responseDelta` event, whose `text` equals the full string `"Hi"` (the chunking operation returns the whole reply as one chunk when the chunk size is not positive) |
| dev-chat-model-005 | send-requires-active-subscription | A freshly constructed instance of the component; call `send("hello")` before ever calling `events()` | No event of any kind is produced — no subscriber handle is stored, so `send(_:)` returns immediately |
| dev-chat-model-006 | interrupt-cancels-live-turn | A freshly constructed and subscribed instance with no turn in flight; call `interrupt()` | No event is yielded and no crash occurs; the in-flight turn's task handle remains unset throughout |
| dev-chat-model-007 | cancellation-stops-only-remaining-chunks, turn-ends-with-ready | An instance constructed with `reply: "abcdefghi"`, `chunkSize: 1`, and `interChunkDelay` of 5 seconds; subscribe, `send("x")`, then call `interrupt()` before the first inter-chunk delay elapses | At most the first `.responseDelta` is observed before the next cancellation check breaks the loop, but `.responseFinished(stopReason: "end_turn")` and a trailing `.stateChanged(.ready)` are still yielded |
| dev-chat-model-008 | close-cancels-and-finishes | A subscribed instance, mid-turn; call `close()` | The event stream returned by `events()` terminates (a consumer awaiting further events sees the stream end) and no further event is yielded afterward |
| dev-chat-model-009 | clear-is-inert | A subscribed instance, after one or more turns have completed; call `clear()`, then `send("next")` | `clear()` yields no event; the subsequent `send("next")` behaves exactly as **dev-chat-model-002** describes, unaffected by the `clear()` call |
| dev-chat-model-010 | second-subscription-silently-supersedes-first | A subscribed instance via a first `events()` call, held as stream A; call `events()` a second time, held as stream B; then `send("hi")` | Stream B receives the full `.stateChanged(.ready)` plus the full turn sequence; stream A receives nothing further after the second `events()` call and is never ended by it |

## Edge Cases

- **Null/empty input to `send(_:)`**: An empty string or whitespace-only `text` MUST be echoed and processed exactly like any other input — `send(_:)` performs no trimming or emptiness guard of its own, unlike a sibling network- or subprocess-backed `ChatSession` implementation's `send(_:)`, which trims and rejects an empty trimmed string before doing anything. MUST.
- **Empty `reply`**: The turn's chunking behavior for an empty `reply` differs by `chunkSize`'s sign — see **chunk-size-positive-empty-reply-no-chunks** (zero `.responseDelta` events when `chunkSize > 0`) versus **chunk-size-non-positive-single-chunk** (one empty-string `.responseDelta` event when `chunkSize <= 0`). MUST.
- **Boundary `chunkSize` values**: `chunkSize <= 0` collapses to one chunk holding the entire `reply`; a `chunkSize` larger than `reply`'s character count also collapses to one chunk, since the chunking operation's single step is capped at the end of the string. MUST.
- **Boundary `interChunkDelay` values**: The component places no lower or upper bound on `interChunkDelay`. A value of zero MUST still pass through one inter-chunk delay wait per chunk, even though that wait resolves immediately; an arbitrarily large delay MUST simply hold the turn open between deltas, with no timeout of its own that would end it early. MUST.
- **Concurrent access — two `events()` subscriptions**: see **second-subscription-silently-supersedes-first** above. MUST.
- **Concurrent access — the in-flight turn's task handle racing across threads**: this is the open question recorded under **live-turn-synchronization**.
- **Error states**: Not applicable in the sense of an external dependency failing — the component has none (no network, no subprocess, no file I/O) and never yields `.turnFailed` (see **no-turn-failed-emission**). The only failure mode this component can enter is the unresolved in-flight-turn race noted above.
- **Offline/disconnected state**: Not applicable — the component performs no networking of any kind; its entire purpose is to stand in for a connected session in tests, previews, and demos.
- **Cancellation mid-turn**: see **cancellation-stops-only-remaining-chunks** and Conformance Test Vector dev-chat-model-007. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `reply` | `String` | `"This is a mock reply."` | The full assistant reply text streamed back for every turn, regardless of what the caller sends. |
| `chunkSize` | `Int` | `3` | The number of `Character`s per `.responseDelta` chunk. A value at or below `0` yields the whole reply as one chunk. |
| `interChunkDelay` | `Duration` | `.milliseconds(10)` | The delay awaited between successive `.responseDelta` chunks. |

This component defines no environment variable and no settings key of its own — every value it operates on arrives as one of the three constructor parameters above.

## Deep Linking

Not applicable: the component defines no URL scheme, route, or navigation destination — it is a headless chat-engine test double, not a navigable surface.

## Localization

- **hardcoded-default-reply-string**: The default `reply` parameter value, `"This is a mock reply."`, is a hardcoded English literal with no localization mechanism wrapping it. A caller that does not override `reply` MUST see exactly that literal English text rendered in the transcript by whatever view consumes it. MUST (stated as an observed fact, not a proposal).
- **stop-reason-not-user-facing**: The literal stop reason `"end_turn"` is an internal `ChatEvent` payload value passed between the session and its view model, not text rendered to a reader, so it carries no localization concern.

## Accessibility Options

Not applicable: the component presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: the component contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: the component contains no analytics or event-tracking call.

## Privacy

- **Data handled**: The `text` argument passed to `send(_:)` and the configured `reply` string are the only content this component touches; both are held only in memory as `ChatMessage.text` values yielded through the event stream `events()` returns. The component defines no credential, token, or other sensitive field.
- **Storage**: The component performs no storage of any kind — no file, database, settings-store, or credential-store write ("No network, no subprocess").
- **Transmission**: None. The component never opens a network connection or spawns a process; every event is produced and consumed entirely in-process.
- **Retention**: None beyond the lifetime of an `events()` subscription. The component holds no transcript array of its own — once a `ChatMessage` is yielded, the instance retains no copy of it (contrast a sibling network- or subprocess-backed `ChatSession` implementation, which does hold loaded/pending message arrays).

## Logging

Not applicable: the component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/Chat/MockChatSession.swift`, part of the Foundation-only `AgenticToolkitCore` framework — it imports no UI framework. A SwiftUI host consumes it identically to an AppKit host: construct `MockChatSession(reply:chunkSize:interChunkDelay:)` and hand it to `AIChatViewModel(session:)`, which folds its `ChatEvent`s (via `ChatTranscriptReducer`) into the observable state a SwiftUI chat view would bind to.
- **Compose**: Model `ChatSession` as a Kotlin interface (`fun events(): Flow<ChatEvent>`, `fun send(text: String)`, `fun interrupt()`, `fun close()`, with a default no-op `fun clear()`). Implement the equivalent of `MockChatSession` with a `MutableSharedFlow<ChatEvent>` (or a `Channel<ChatEvent>`) in place of `AsyncStream` plus its `NSLock`-guarded continuation — `emit`/`trySend` on those types is already safe for concurrent producers. Replace the unsynchronized `liveTurn: Task<Void, Never>?` with a `Job?` guarded by a `Mutex` (or stored in an `AtomicReference`), fixing rather than reproducing the source's unsynchronized `liveTurn` access recorded as the open question under **live-turn-synchronization**. Chunk with a grapheme-cluster-aware split (Kotlin `String`'s code-point-aware iteration, not raw UTF-16 `substring`), and use `delay(interChunkDelayMillis)` in place of `Task.sleep(for:)`.
- **React/Web**: Model `ChatSession` with `events()` returning an `AsyncGenerator<ChatEvent>` (or an RxJS `Observable<ChatEvent>`); `send(text)` yields a `userMessage` event, then an `async function*` `yield`s each delta chunk after an `await sleep(interChunkDelayMs)`, mirroring the source's `for`-loop-plus-`Task.sleep`. `interrupt()` becomes an `AbortController.abort()` whose `signal.aborted` the chunk-emitting generator checks each iteration, in place of `Task.isCancelled`. Chunk `reply` with `Array.from(reply)` (an array of Unicode code points) rather than slicing the raw UTF-16 `string`, so a chunk boundary cannot split a surrogate pair — the same guarantee the source's `Character`-based `chunk(_:size:)` gives against splitting a grapheme cluster.
- **AppKit/UIKit**: The reference implementation is `packages/apple/AgenticToolkit/Core/Chat/MockChatSession.swift`, part of the Foundation-only `AgenticToolkitCore` framework — it is UI-framework-agnostic, and only the application embedding it differs, never this contract. It is declared `final class MockChatSession: ChatSession, @unchecked Sendable`; `@unchecked Sendable` disables the compiler's own cross-isolation-domain checking, so every guarantee of safe concurrent use rests entirely on the type's own locking rather than on anything Swift's concurrency checker verifies. The stored subscriber handle referenced under **continuation-access-is-lock-protected** is the type's `continuation: AsyncStream<ChatEvent>.Continuation?` property, and "protected against concurrent access" means every read or write of it goes through an `NSLock`-backed `withLock` helper (`send(_:)`, `close()`) or the equivalent manual `lock.lock()`/`unlock()` pair (`events()`). The in-flight turn's task handle is the `liveTurn: Task<Void, Never>?` property; as recorded under **live-turn-synchronization**, its four access sites — `send(_:)`'s assignment, and the cancellations in `interrupt()`, `close()`, and the `AsyncStream`'s `onTermination` closure — do not go through that same lock. The live turn itself is built on `AsyncStream`, `Task`, `Task.sleep(for:)` (with a thrown `CancellationError` swallowed via `try?`), and `Task.isCancelled` checks between chunks. "A freshly generated unique identifier string" and "the current time" are `UUID().uuidString` and `Date()`. The chunking operation, `Self.chunk(_:size:)`, splits using `Character`-count offsets (`str.count`, `str.index(_:offsetBy:)`), never UTF-8 byte or UTF-16 offsets, and its stride-based loop (`stride(from: 0, to: str.count, by: size)`) caps its final step at `str.endIndex` via `limitedBy:`.
- **WinUI 3**: Model `ChatSession` as a C# interface — `IAsyncEnumerable<ChatEvent> Events(); void Send(string text); void Interrupt(); void Close();` plus a default-implemented `void Clear() { }` (C# 8+ default interface members mirror the Swift protocol extension's default `clear()`). Implement `MockChatSession`'s equivalent using a `System.Threading.Channels.Channel<ChatEvent>` in place of `AsyncStream`'s manually-locked continuation — `ChannelWriter<ChatEvent>.TryWrite` is itself thread-safe, which removes the need for a hand-rolled `lock` around it entirely. For the in-flight turn, hold the current `Task`/`CancellationTokenSource` pair behind one `lock (_gate)` block covering every read and write to it — `Send`'s assignment, `Interrupt`'s and `Close`'s cancellation calls, and any stream-teardown handler alike — so a WinUI 3 port does not reproduce this source's unsynchronized `liveTurn` access (see the open question under **live-turn-synchronization**); call `cts.Cancel()` from `Interrupt()`/`Close()`, and `await Task.Delay(interChunkDelay, cts.Token)` between chunks in place of `Task.sleep(for:)`. Chunk `reply` with `System.Globalization.StringInfo`'s text-element enumeration (`StringInfo.GetTextElementEnumerator`/`SubstringByTextElements`) rather than plain `string` indexing, since C# `string` indexing is UTF-16-code-unit-based and — unlike Swift's `Character`-based `String.Index` — can split a surrogate pair or a combining grapheme cluster mid-character.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Chat/ChatEvent.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ChatMessage.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ChatSession.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ChatSessionState.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ChatToolSource.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ChatTranscriptReducer.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ConversationsSelectionMode.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/ConversationsSessionFilter.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/FeedChatSession.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Chat/MockChatSession.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/ConversationsWindow/ConversationFocusOverlay.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/ConversationsWindow/ConversationsKeyCommands.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionWatcherDataModel/SessionSources.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/SessionWatcher/SessionWatcherDataModel/SessionWatcherSession.swift` |

## Design Decisions

**Decision**: An interrupted turn still yields `.responseFinished(stopReason: "end_turn")` and `.stateChanged(.ready)` — there is no distinct "interrupted" stop reason or session state.
**Rationale**: `MockChatSession` models only the visible effect of an interruption (fewer or zero `.responseDelta` events reaching the transcript); it does not model a `ChatSession` conformer that reports interruption as a distinct outcome. Any UI or test that depends on distinguishing a cleanly finished turn from an interrupted one cannot do so from this component's events alone.
**Approved**: pending

**Decision**: On the AppKit/UIKit implementation, `MockChatSession` is declared `@unchecked Sendable`, but only `continuation` is consistently accessed under its `lock`; `liveTurn` is not.
**Rationale**: This is the same gap as the open question recorded under **live-turn-synchronization**, not a considered design choice — it is recorded here because `@unchecked Sendable` is exactly the kind of "trust me, it's synchronized elsewhere" declaration that Source Fidelity requires calling out rather than smoothing over, and because a port that copies the Swift structure literally (rather than the fixes proposed in Platform Notes) would carry the same race into its target platform.
**Approved**: pending

**Decision**: On the AppKit/UIKit implementation, `chunk(_:size:)` splits on `Character` count, not byte or UTF-16 count.
**Rationale**: This keeps chunk boundaries safely on grapheme cluster boundaries for any input, including multi-scalar characters and emoji, at essentially no extra code — Swift's `String.Index`-based `offsetBy:` is `Character`-aware by default. A port on a platform whose native string indexing is UTF-16-code-unit-based (JavaScript, C#) needs an explicit code-point- or text-element-aware split to keep the same guarantee; see Platform Notes.
**Approved**: pending

**Decision**: `send(_:)` performs no trimming or emptiness guard on its `text` argument, unlike the sibling `FeedChatSession.send(_:)`, which trims and rejects an empty trimmed string.
**Rationale**: `MockChatSession` is a scripted double whose reply never depends on the sent text (see **reply-independent-of-input**), so an empty or whitespace-only send has no failure mode to guard against here the way it does for `FeedChatSession`, which writes the text into a real destination and must not write nothing. The two types intentionally diverge on this point rather than sharing one send-validation rule.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: no-hardcoded-strings fails because the default `reply`, `"This is a mock reply."`, is a hardcoded English literal with no localization mechanism (see Localization). unit-test-coverage is partial because `MockChatSessionTests.swift` contains exactly one test, covering only the happy-path scripted reply (dev-chat-model-002 above); it exercises neither `interrupt()`, `close()`, an empty `reply`, a non-positive `chunkSize`, nor a second `events()` subscription. data-integrity is partial because of the unsynchronized `liveTurn` access recorded as the open question under **live-turn-synchronization** — a `var` mutated and read from multiple call sites with no lock, on a type declared `@unchecked Sendable`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/chat/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
