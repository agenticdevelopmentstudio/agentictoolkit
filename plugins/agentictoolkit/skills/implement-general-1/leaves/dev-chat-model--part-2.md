<!-- leaf: implement-general-1/dev-chat-model--part-2 · source: dev-chat-model.md -->

# MockChatSession — continued (part 2)

**Rules** (cite as `implement-general-1/dev-chat-model--part-2#<slug>`):

- `hardcoded-default-reply-string` MUST

## Localization

- **hardcoded-default-reply-string**: The default `reply` parameter value, `"This is a mock reply."`, is a hardcoded English literal with no `String(localized:)`, `NSLocalizedString`, or other localization mechanism wrapping it. A caller that does not override `reply` MUST see exactly that literal English text rendered in the transcript by whatever view consumes it. MUST (stated as an observed fact, not a proposal).
- **stop-reason-not-user-facing**: The literal stop reason `"end_turn"` is an internal `ChatEvent` payload value passed between the session and its view model, not text rendered to a reader, so it carries no localization concern.

## Privacy

- **Data handled**: The `text` argument passed to `send(_:)` and the configured `reply` string are the only content this file touches; both are held only in memory as `ChatMessage.text` values yielded through the `AsyncStream` `events()` returns. `MockChatSession.swift` defines no credential, token, or other sensitive field.
- **Storage**: `MockChatSession.swift` performs no storage of any kind — no file, database, `UserDefaults`, or Keychain write (doc comment, "No network, no subprocess").
- **Transmission**: None. `MockChatSession` never opens a network connection or spawns a process; every event is produced and consumed entirely in-process.
- **Retention**: None beyond the lifetime of an `events()` subscription. `MockChatSession` holds no transcript array of its own — once a `ChatMessage` is yielded, the instance retains no copy of it (contrast `FeedChatSession`, which does hold `loaded`/`pending` arrays).

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/Core/Chat/MockChatSession.swift`, part of the Foundation-only `AgenticToolkitCore` framework — it imports no UI framework. A SwiftUI host consumes it identically to an AppKit host: construct `MockChatSession(reply:chunkSize:interChunkDelay:)` and hand it to `AIChatViewModel(session:)`, which folds its `ChatEvent`s (via `ChatTranscriptReducer`) into the observable state a SwiftUI chat view would bind to.
- **Compose**: Model `ChatSession` as a Kotlin interface (`fun events(): Flow<ChatEvent>`, `fun send(text: String)`, `fun interrupt()`, `fun close()`, with a default no-op `fun clear()`). Implement the equivalent of `MockChatSession` with a `MutableSharedFlow<ChatEvent>` (or a `Channel<ChatEvent>`) in place of `AsyncStream` plus its `NSLock`-guarded continuation — `emit`/`trySend` on those types is already safe for concurrent producers. Replace the unsynchronized `liveTurn: Task<Void, Never>?` with a `Job?` guarded by a `Mutex` (or stored in an `AtomicReference`), fixing rather than reproducing the source's unsynchronized `liveTurn` access recorded as the open question under **live-turn-synchronization**. Chunk with a grapheme-cluster-aware split (Kotlin `String`'s code-point-aware iteration, not raw UTF-16 `substring`), and use `delay(interChunkDelayMillis)` in place of `Task.sleep(for:)`.
- **React/Web**: Model `ChatSession` with `events()` returning an `AsyncGenerator<ChatEvent>` (or an RxJS `Observable<ChatEvent>`); `send(text)` yields a `userMessage` event, then an `async function*` `yield`s each delta chunk after an `await sleep(interChunkDelayMs)`, mirroring the source's `for`-loop-plus-`Task.sleep`. `interrupt()` becomes an `AbortController.abort()` whose `signal.aborted` the chunk-emitting generator checks each iteration, in place of `Task.isCancelled`. Chunk `reply` with `Array.from(reply)` (an array of Unicode code points) rather than slicing the raw UTF-16 `string`, so a chunk boundary cannot split a surrogate pair — the same guarantee the source's `Character`-based `chunk(_:size:)` gives against splitting a grapheme cluster.
- **AppKit/UIKit**: Identical to the SwiftUI note above — `MockChatSession` is UI-framework-agnostic; only the application embedding `AgenticToolkitCore` differs, never this contract.
- **WinUI 3**: Model `ChatSession` as a C# interface — `IAsyncEnumerable<ChatEvent> Events(); void Send(string text); void Interrupt(); void Close();` plus a default-implemented `void Clear() { }` (C# 8+ default interface members mirror the Swift protocol extension's default `clear()`). Implement `MockChatSession`'s equivalent using a `System.Threading.Channels.Channel<ChatEvent>` in place of `AsyncStream`'s manually-locked continuation — `ChannelWriter<ChatEvent>.TryWrite` is itself thread-safe, which removes the need for a hand-rolled `lock` around it entirely. For the in-flight turn, hold the current `Task`/`CancellationTokenSource` pair behind one `lock (_gate)` block covering every read and write to it — `Send`'s assignment, `Interrupt`'s and `Close`'s cancellation calls, and any stream-teardown handler alike — so a WinUI 3 port does not reproduce this source's unsynchronized `liveTurn` access (see the open question under **live-turn-synchronization**); call `cts.Cancel()` from `Interrupt()`/`Close()`, and `await Task.Delay(interChunkDelay, cts.Token)` between chunks in place of `Task.sleep(for:)`. Chunk `reply` with `System.Globalization.StringInfo`'s text-element enumeration (`StringInfo.GetTextElementEnumerator`/`SubstringByTextElements`) rather than plain `string` indexing, since C# `string` indexing is UTF-16-code-unit-based and — unlike Swift's `Character`-based `String.Index` — can split a surrogate pair or a combining grapheme cluster mid-character.

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
