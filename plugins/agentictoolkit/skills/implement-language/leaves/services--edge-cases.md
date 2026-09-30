<!-- leaf: implement-language/services--edge-cases · source: language-services.md -->

# LanguageServices

**Rules** (cite as `implement-language/services--edge-cases#<slug>`):

- `empty-edit-batch` MUST — apply([]) MUST return [] and MUST NOT bump version, rebuild the line index, or notify any handler — the guard …
- `empty-document-text` MUST — TextDocument(text: "") MUST report exactly one line, starting at offset 0; position(forUTF16Offset: 0) and …
- `trailing-terminator` MUST — text ending in \n (or \r\n) MUST produce one more, empty, final line, addressable one past the text's own length — e.g. …
- `whole-line-replacement` MUST — a range whose end character is far beyond the line's actual length (LSP's own idiom for "to the end of this line," e.g. …
- `a-batch-handed-to-apply-out-of-the-order-it-must-be-spliced-in` MUST — apply(_:) MUST NOT assume the caller's array is already sorted by position; it resolves and reorders internally, and …
- `a-large-scrambled-batch` MUST — with enough edits (past sorted(by:)'s small-array fast path) for a non-total ordering comparator to actually reorder …
- `opening-a-uri-that-is-already-open` MUST — TextDocumentStore.open(uri:languageId:text:) MUST NOT re-read or replace the existing document's text, even if the new …
- `closing-a-uri-that-was-never-opened-or-already-fully-closed` MUST — TextDocumentStore.close(uri:) MUST be a no-op — it does not decrement below what an entry has, raise an error, or emit …
- `closing-a-document-that-is-still-dirty` MUST — TextDocumentStore.close(uri:) performs no autosave, flush, or coordination with TextDocumentSaveScheduler of any kind — …
- `two-concurrent-flushes-of-the-same-pending-uri` MUST — flushPendingSave(uri:) (via the underlying debouncer) MUST NOT start a second write while one is already in flight for …
- `flushpendingsaves-with-nothing-pending` MUST — MUST complete without writing anything and MUST return an empty array.

## Edge Cases

- **Empty edit batch**: `apply([])` MUST return `[]` and MUST NOT bump `version`, rebuild the line index, or notify any handler — the `guard !edits.isEmpty else { return [] }` at the top of `apply(_:)`.
- **Empty document text**: `TextDocument(text: "")` MUST report exactly one line, starting at offset `0`; `position(forUTF16Offset: 0)` and `utf16Offset(for: Position(line: 0, character: 0))` both resolve to that single empty line.
- **Trailing terminator**: text ending in `\n` (or `\r\n`) MUST produce one more, empty, final line, addressable one past the text's own length — e.g. `"a\n"` has a valid `Position(line: 1, character: 0)` at offset `2`.
- **Whole-line replacement**: a range whose end character is far beyond the line's actual length (LSP's own idiom for "to the end of this line," e.g. character `999`) MUST replace only the line's content, never consuming its `\n` or `\r\n` terminator — replacing such a range must not join two lines together.
- **A batch handed to `apply(_:)` out of the order it must be spliced in**: `apply(_:)` MUST NOT assume the caller's array is already sorted by position; it resolves and reorders internally, and MUST still emit events in the LSP-required, self-consistent order regardless of the caller's original order.
- **A large, scrambled batch**: with enough edits (past `sorted(by:)`'s small-array fast path) for a non-total ordering comparator to actually reorder equal elements, `apply(_:)` MUST still splice deterministically by the documented tiebreak (descending caller index) and MUST still produce events that replay to the same text on a fresh document.
- **Opening a URI that is already open**: `TextDocumentStore.open(uri:languageId:text:)` MUST NOT re-read or replace the existing document's text, even if the new call's `text` differs from what is currently open.
- **Closing a URI that was never opened, or already fully closed**: `TextDocumentStore.close(uri:)` MUST be a no-op — it does not decrement below what an entry has, raise an error, or emit `.closed` for a URI with no tracked entry.
- **Closing a document that is still dirty**: `TextDocumentStore.close(uri:)` performs no autosave, flush, or coordination with `TextDocumentSaveScheduler` of any kind — the two types hold no reference to each other in the given sources; a caller that wants a dirty document's pending edits saved before it disappears MUST call `TextDocumentSaveScheduler.flushPendingSave(uri:)` itself first (see Design Decisions).
- **Dropping an observation token while its handler is mid-delivery**: `TextDocumentObservation`/`TextDocumentStoreObservation`'s `isolated deinit` hops to the main actor before removing the handler, so teardown is itself serialized with any in-flight notification on that same actor — no separate synchronization is needed or provided.
- **A save write that suspends across an edit**: covered by `scheduler-markClean-version-guarded`; the document is never incorrectly marked clean, and the edit made during the suspension schedules its own follow-up save via the normal change-handler path, so it is not lost.
- **A write that keeps failing indefinitely**: the scheduler's underlying `KeyedDebouncer` never gives up on a failing key — it re-arms at an exponentially growing interval capped at a fixed ceiling (`.seconds(30)` by default) rather than abandoning the entry, so `flushPendingSaves()` at app termination can still find and report it.
- **Two concurrent flushes of the same pending `uri`**: `flushPendingSave(uri:)` (via the underlying debouncer) MUST NOT start a second write while one is already in flight for that key; the second caller awaits the first write's result instead.
- **`flushPendingSaves()` with nothing pending**: MUST complete without writing anything and MUST return an empty array.
- **A URL whose `absoluteString` differs from another URL naming the same file on disk** (e.g. a symlink, a trailing slash, or a differently-percent-encoded path): `URL.documentUri` performs no normalization of any kind; two such URLs produce two different `DocumentUri` strings, and reconciling them (if needed at all) is a concern of a layer outside this file, per its own doc comment's narrower claim — see Design Decisions.
