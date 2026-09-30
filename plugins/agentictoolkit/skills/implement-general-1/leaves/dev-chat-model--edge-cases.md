<!-- leaf: implement-general-1/dev-chat-model--edge-cases · source: dev-chat-model.md -->

# MockChatSession

**Rules** (cite as `implement-general-1/dev-chat-model--edge-cases#<slug>`):

- `null-empty-input-to-send` MUST — An empty string or whitespace-only text MUST be echoed and processed exactly like any other input — send(_:) performs …
- `empty-reply` MUST — The turn's chunking behavior for an empty reply differs by chunkSize's sign — see …
- `boundary-chunksize-values` MUST — chunkSize <= 0 collapses to one chunk holding the entire reply; a chunkSize larger than reply's character count also …
- `boundary-interchunkdelay-values` MUST — MockChatSession places no lower or upper bound on interChunkDelay. A value of .zero MUST still pass through one try? …
- `concurrent-access-two-events-subscriptions` MUST — see second-subscription-silently-supersedes-first above. MUST.
- `cancellation-mid-turn` MUST — see cancellation-stops-only-remaining-chunks and Conformance Test Vector dev-chat-model-007. MUST.

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
