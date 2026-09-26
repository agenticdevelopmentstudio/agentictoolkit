---
id: 91bd3986-da9d-418e-a969-c878efa88d50
title: MockChatSession
domain: agentictoolkit://cookbook/dev-chat-model
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- foundation
- sendable
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/ai-chat-window/chat-view
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a headless, in-memory test double for a chat engine, not a visual component.

## States

Not applicable — this is a headless, in-memory test double for a chat engine, not a visual component. Its runtime lifecycle is expressed through the `ChatEvent.stateChanged(ChatSessionState)` events it emits (`.ready`, `.responding`; it never emits `.connecting`, `.failed`, or `.closed`), which are captured under Behavioral Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a headless, in-memory test double for a chat engine, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dev-chat-model-001 | ready-on-subscribe | Fresh `MockChatSession()`; subscribe via `events()` and take the first event | First event received is `.stateChanged(.ready)` (`MockChatSessionTests.streamsScriptedReply`) |
| dev-chat-model-002 | send-echoes-user-text-verbatim, send-transitions-to-responding, reply-independent-of-input, delta-events-ordered-and-delayed, response-finished-stop-reason-fixed, turn-ends-with-ready | `MockChatSession(reply: "Hi there", chunkSize: 3)`; subscribe, then `send("hello")` | Received events include, in order: `.stateChanged(.ready)`, `.userMessage` with `text == "hello"`, `.stateChanged(.responding)`, `.responseStarted`, a run of `.responseDelta` events whose `text` values concatenate to exactly `"Hi there"`, `.responseFinished(stopReason: "end_turn")`, `.stateChanged(.ready)` (`MockChatSessionTests.streamsScriptedReply`) |
| dev-chat-model-003 | chunk-size-positive-empty-reply-no-chunks | `MockChatSession(reply: "", chunkSize: 3)`; subscribe, then `send("x")` | `.responseStarted` is followed immediately by `.responseFinished(stopReason: "end_turn")` with zero `.responseDelta` events between them (`chunk(_:size:)`, `stride(from: 0, to: 0, by: 3)` yields no steps) |
| dev-chat-model-004 | chunk-size-non-positive-single-chunk | `MockChatSession(reply: "Hi", chunkSize: 0)`; subscribe, then `send("x")` | Exactly one `.responseDelta` event, whose `text` equals the full string `"Hi"` (`chunk(_:size:)`, `guard size > 0 else { return [str] }`) |
| dev-chat-model-005 | send-requires-active-subscription | Fresh `MockChatSession()`; call `send("hello")` before ever calling `events()` | No event of any kind is produced — `continuation` is `nil` so `send(_:)` returns at its guard |
| dev-chat-model-006 | interrupt-cancels-live-turn | Fresh, subscribed `MockChatSession()` with no turn in flight; call `interrupt()` | No event is yielded and no crash occurs; `liveTurn` remains `nil` throughout |
| dev-chat-model-007 | cancellation-stops-only-remaining-chunks, turn-ends-with-ready | `MockChatSession(reply: "abcdefghi", chunkSize: 1, interChunkDelay: .seconds(5))`; subscribe, `send("x")`, then call `interrupt()` before the first `interChunkDelay` elapses | At most the first `.responseDelta` is observed before the loop's next cancellation check breaks it, but `.responseFinished(stopReason: "end_turn")` and a trailing `.stateChanged(.ready)` are still yielded |
| dev-chat-model-008 | close-cancels-and-finishes | Subscribed `MockChatSession()` mid-turn; call `close()` | The `AsyncStream` returned by `events()` terminates (its consuming `for await` loop returns) and no further event is yielded afterward |
| dev-chat-model-009 | clear-is-inert | Subscribed `MockChatSession()` after one or more turns have completed; call `clear()`, then `send("next")` | `clear()` yields no event; the subsequent `send("next")` behaves exactly as **dev-chat-model-002** describes, unaffected by the `clear()` call (`ChatSession.swift`) |
| dev-chat-model-010 | second-subscription-silently-supersedes-first | Subscribed `MockChatSession()` via a first `events()` call, held as stream A; call `events()` a second time, held as stream B; then `send("hi")` | Stream B receives the full `.stateChanged(.ready)` plus the full turn sequence; stream A receives nothing further after the second `events()` call and is never finished by it |

## Edge Cases

- **Null/empty input to `send(_:)`**: An empty string or whitespace-only `text` MUST be echoed and processed exactly like any other input — `send(_:)` performs no trimming or emptiness guard of its own, unlike the sibling `FeedChatSession.send(_:)`, which trims and rejects an empty trimmed string before doing anything. MUST.
- **Empty `reply`**: The turn's chunking behavior for an empty `reply` differs by `chunkSize`'s sign — see **chunk-size-positive-empty-reply-no-chunks** (zero `.responseDelta` events when `chunkSize > 0`) versus **chunk-size-non-positive-single-chunk** (one empty-string `.responseDelta` event when `chunkSize <= 0`). MUST.
- **Boundary `chunkSize` values**: `chunkSize <= 0` collapses to one chunk holding the entire `reply`; a `chunkSize` larger than `reply`'s character count also collapses to one chunk, since the stride's single step is capped at `str.endIndex` via `limitedBy:`. MUST.
- **Boundary `interChunkDelay` values**: `MockChatSession` places no lower or upper bound on `interChunkDelay`. A value of `.zero` MUST still pass through one `try? await Task.sleep(for: .zero)` per chunk; an arbitrarily large delay MUST simply hold the turn open between deltas, with no timeout of its own that would end it early. MUST.
- **Concurrent access — two `events()` subscriptions**: see **second-subscription-silently-supersedes-first** above. MUST.
- **Concurrent access — `liveTurn` racing across threads**: this is the open question recorded under **live-turn-synchronization**.
- **Error states**: Not applicable in the sense of an external dependency failing — `MockChatSession` has none (no network, no subprocess, no file I/O; doc comment) and never yields `.turnFailed` (see **no-turn-failed-emission**). The only failure mode this component can enter is the unresolved `liveTurn` race noted above.
- **Offline/disconnected state**: Not applicable — `MockChatSession` performs no networking of any kind; its entire purpose is to stand in for a connected session in tests, previews, and demos (doc comment).
- **Cancellation mid-turn**: see **cancellation-stops-only-remaining-chunks** and Conformance Test Vector dev-chat-model-007. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `reply` | `String` | `"This is a mock reply."` | The full assistant reply text streamed back for every turn, regardless of what the caller sends. |
| `chunkSize` | `Int` | `3` | The number of `Character`s per `.responseDelta` chunk. A value at or below `0` yields the whole reply as one chunk. |
| `interChunkDelay` | `Duration` | `.milliseconds(10)` | The delay awaited between successive `.responseDelta` chunks. |

`MockChatSession.swift` defines no environment variable and no settings key of its own — every value it operates on arrives as one of the three constructor parameters above.

## Deep Linking

Not applicable: `MockChatSession.swift` defines no URL scheme, route, or navigation destination — it is a headless chat-engine test double, not a navigable surface.

## Localization

- **hardcoded-default-reply-string**: The default `reply` parameter value, `"This is a mock reply."`, is a hardcoded English literal with no `String(localized:)`, `NSLocalizedString`, or other localization mechanism wrapping it. A caller that does not override `reply` MUST see exactly that literal English text rendered in the transcript by whatever view consumes it. MUST (stated as an observed fact, not a proposal).
- **stop-reason-not-user-facing**: The literal stop reason `"end_turn"` is an internal `ChatEvent` payload value passed between the session and its view model, not text rendered to a reader, so it carries no localization concern.

## Accessibility Options

Not applicable: `MockChatSession.swift` presents no UI, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `MockChatSession.swift` contains no feature-flag or settings-key reference of its own.

## Analytics

Not applicable: `MockChatSession.swift` contains no analytics or event-tracking call.

## Privacy

- **Data handled**: The `text` argument passed to `send(_:)` and the configured `reply` string are the only content this file touches; both are held only in memory as `ChatMessage.text` values yielded through the `AsyncStream` `events()` returns. `MockChatSession.swift` defines no credential, token, or other sensitive field.
- **Storage**: `MockChatSession.swift` performs no storage of any kind — no file, database, `UserDefaults`, or Keychain write (doc comment, "No network, no subprocess").
- **Transmission**: None. `MockChatSession` never opens a network connection or spawns a process; every event is produced and consumed entirely in-process.
- **Retention**: None beyond the lifetime of an `events()` subscription. `MockChatSession` holds no transcript array of its own — once a `ChatMessage` is yielded, the instance retains no copy of it (contrast `FeedChatSession`, which does hold `loaded`/`pending` arrays).

## Logging

Not applicable: `MockChatSession.swift` contains no logging call of any kind (no `os_log`, `Logger`, or `print` statement) across its full 74-line source.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/Chat/MockChatSession.swift`, part of the Foundation-only `AgenticToolkitCore` framework — it imports no UI framework. A SwiftUI host consumes it identically to an AppKit host: construct `MockChatSession(reply:chunkSize:interChunkDelay:)` and hand it to `AIChatViewModel(session:)`, which folds its `ChatEvent`s (via `ChatTranscriptReducer`) into the observable state a SwiftUI chat view would bind to.
- **Compose**: Model `ChatSession` as a Kotlin interface (`fun events(): Flow<ChatEvent>`, `fun send(text: String)`, `fun interrupt()`, `fun close()`, with a default no-op `fun clear()`). Implement the equivalent of `MockChatSession` with a `MutableSharedFlow<ChatEvent>` (or a `Channel<ChatEvent>`) in place of `AsyncStream` plus its `NSLock`-guarded continuation — `emit`/`trySend` on those types is already safe for concurrent producers. Replace the unsynchronized `liveTurn: Task<Void, Never>?` with a `Job?` guarded by a `Mutex` (or stored in an `AtomicReference`), fixing rather than reproducing the source's unsynchronized `liveTurn` access recorded as the open question under **live-turn-synchronization**. Chunk with a grapheme-cluster-aware split (Kotlin `String`'s code-point-aware iteration, not raw UTF-16 `substring`), and use `delay(interChunkDelayMillis)` in place of `Task.sleep(for:)`.
- **React/Web**: Model `ChatSession` with `events()` returning an `AsyncGenerator<ChatEvent>` (or an RxJS `Observable<ChatEvent>`); `send(text)` yields a `userMessage` event, then an `async function*` `yield`s each delta chunk after an `await sleep(interChunkDelayMs)`, mirroring the source's `for`-loop-plus-`Task.sleep`. `interrupt()` becomes an `AbortController.abort()` whose `signal.aborted` the chunk-emitting generator checks each iteration, in place of `Task.isCancelled`. Chunk `reply` with `Array.from(reply)` (an array of Unicode code points) rather than slicing the raw UTF-16 `string`, so a chunk boundary cannot split a surrogate pair — the same guarantee the source's `Character`-based `chunk(_:size:)` gives against splitting a grapheme cluster.
- **AppKit/UIKit**: Identical to the SwiftUI note above — `MockChatSession` is UI-framework-agnostic; only the application embedding `AgenticToolkitCore` differs, never this contract.
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

**Decision**: `MockChatSession` is declared `@unchecked Sendable`, but only `continuation` is consistently accessed under its `lock`; `liveTurn` is not.
**Rationale**: This is the same gap as the open question recorded under **live-turn-synchronization**, not a considered design choice — it is recorded here because `@unchecked Sendable` is exactly the kind of "trust me, it's synchronized elsewhere" declaration that Source Fidelity requires calling out rather than smoothing over, and because a port that copies the Swift structure literally (rather than the fixes proposed in Platform Notes) would carry the same race into its target platform.
**Approved**: pending

**Decision**: `chunk(_:size:)` splits on `Character` count, not byte or UTF-16 count.
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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
