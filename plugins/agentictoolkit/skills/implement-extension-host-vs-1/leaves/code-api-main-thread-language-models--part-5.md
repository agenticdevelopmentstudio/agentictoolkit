<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-language-models--part-5 · source: extension-host-vs-code-api-main-thread-language-models.md -->

# MainThreadLanguageModels — continued (part 5)

## Design Decisions

**Decision**: `.end`'s `stopReason` is dropped rather than surfaced through any member of the JS-visible response object.
**Rationale**: `vscode.LanguageModelChatResponse` declares only `stream` and `text`, neither of which has anywhere to carry a stop reason; the loss is upstream's own type shape, not a gap this file introduces, so `.end` is buffered like any other part internally but never yielded as a value on either cursor.
**Approved**: pending

**Decision**: `dispose()` does not clear `liveRequests`.
**Rationale**: a request whose response object has already been handed to the extension can still receive a `next()` call after `dispose()` runs. Clearing `liveRequests` would let that call fall through to deallocated state and answer with `undefined` or crash; retaining the entry lets it be rejected with the correct torn-down wording instead, at the cost of keeping that request's buffer allocated for the rest of the adaptor's lifetime.
**Approved**: pending

**Decision**: a response part that fails to bridge into JavaScript on the `stream` cursor now fails that cursor with `LanguageModelPartBridgingFailure`, rather than being silently skipped.
**Rationale**: silently dropping a part would let a shorter, incomplete response masquerade as a successful one; failing the cursor makes the data loss observable to the extension that would otherwise trust an under-delivered result.
**Approved**: pending

**Decision**: a message `role` is validated with `Int32(exactly:)`, never `toInt32()`.
**Rationale**: `toInt32()` implements ECMAScript's `ToInt32`, which wraps modulo 2³² and truncates fractions, so a value like `4294967297` would read as the in-range integer `1` and be silently accepted as `.user` when it is not a role JavaScript ever meant to send. `Int32(exactly:)` answers `nil` for any value that is not exactly representable, so `sendRequest` refuses the whole call instead of accepting a role value that only looks valid after wraparound.
**Approved**: pending

**Decision**: `options.modelOptions`, `options.tools`, and `options.toolMode` are recorded into `notImplementedLedger` by presence alone and never passed to `provider.streamResponse`.
**Rationale**: no provider conformer given to this file honours any of the three yet; passing them through unread would misrepresent them as handled, while inventing partial handling here would guess at a contract the seam does not define. Recording presence in the shared ledger keeps the gap visible to whoever inspects it without this file pretending to close it.
**Approved**: pending

**Decision**: `LanguageModelCancellation` duck-types a `CancellationToken` by checking only for `isCancellationRequested` and a callable `onCancellationRequested`, leaving any other shape permanently un-cancelled rather than raising.
**Rationale**: `token` is optional in `vscode.d.ts`'s own `sendRequest` signature, and an extension may pass `undefined` or an object that merely resembles a token; failing the call over an absent or malformed cancellation mechanism would reject requests the declared API contract allows through, so this file treats anything it cannot duck-type as "never cancelled" instead.
**Approved**: pending
