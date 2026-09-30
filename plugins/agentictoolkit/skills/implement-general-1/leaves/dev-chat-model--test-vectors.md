<!-- leaf: implement-general-1/dev-chat-model--test-vectors · source: dev-chat-model.md -->

# MockChatSession

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
