<!-- leaf: implement-language/services-editor--part-4 · source: language-services-editor.md -->

# LanguageServicesEditor — continued (part 4)

**Rules** (cite as `implement-language/services-editor--part-4#<slug>`):

- `semantic-setup-resets-on-language-change` MUST
- `semantic-deinit-completes-parked-queries` MUST
- `semantic-unmapped-and-overlap-narrowings-recorded` MUST
- `semantic-decline-lexical-types-tree-sitter-already-handles` MUST
- `semantic-modifiers-discarded-and-recorded-once` MUST
- `semantic-full-capability-requires-explicit-true-or-object` MUST
- `semantic-clip-preserves-end-to-end-layout` MUST
- `coordinator-terminate-stops-reloader-before-flush` MUST
- `coordinator-unsaved-documents-logged-only-when-nonempty` MUST
- `coordinator-default-debounce-one-second` MUST
- `coordinator-reloader-started-at-init` MUST
- `storage-local-edit-guard-prevents-reentrant-rewrite` MUST
- `storage-document-updated-before-edited-notification` MUST
- `storage-range-converted-before-backing-store-mutated` MUST
- `storage-external-change-full-rewrite-not-partial-replay` MUST
- `storage-main-thread-only-primitives-fail-loudly` MUST
- `storage-external-change-application-count-testable` MUST

- **semantic-setup-resets-on-language-change**: Setup MUST clear the stored highlights, advance the fetch clock and stamp past every fetch already in flight, and start a fresh fetch, so a second setup call, such as a language change, cannot be answered from the previous language's tokens (SemanticTokenHighlightProvider.swift).
- **semantic-deinit-completes-parked-queries**: Teardown MUST cancel the in-flight fetch task and complete every parked query exactly once rather than leaving any uncalled (SemanticTokenHighlightProvider.swift).
- **semantic-unmapped-and-overlap-narrowings-recorded**: Decoding MUST tally unmapped token types and out-of-range lines and record each as one divergence-ledger entry per fetch, not per token, and MUST both log and record a dropped-overlap entry when a token's range does not start at or after the previous token's end (SemanticTokenHighlightProvider.swift).
- **semantic-decline-lexical-types-tree-sitter-already-handles**: `SemanticTokenCaptureMapping.capture(for:)` MUST map only identifier-role token types to a highlight capture and MUST return `nil` for lexical types such as keyword, string, number, comment, and operator, leaving those to the existing tree-sitter highlighter (SemanticTokenCaptureMapping.swift).
- **semantic-modifiers-discarded-and-recorded-once**: Decoding MUST discard every token's modifier bits from the emitted highlight range and MUST record a single modifiers-ignored ledger entry, with a positive count, when any token in the response carried a non-zero modifier bitmask (SemanticTokenHighlightProvider.swift).
- **semantic-full-capability-requires-explicit-true-or-object**: The full-request legend lookup MUST return `nil` when the client's declared full-request capability is a bare `false` or absent, and MUST return the legend for a bare `true` or an object value (SemanticTokenHighlightProvider.swift).
- **semantic-clip-preserves-end-to-end-layout**: Clipping stored highlight ranges to a queried range MUST intersect each range with the query and MUST drop any resulting empty intersection, because the caller lays the returned ranges end to end (SemanticTokenHighlightProvider.swift).
- **coordinator-terminate-stops-reloader-before-flush**: `terminate()` MUST stop the reloader before awaiting the save scheduler's final flush, so a reload landing between the flush and process exit cannot rewrite a buffer nothing will save again (TextDocumentCoordinator.swift).
- **coordinator-unsaved-documents-logged-only-when-nonempty**: `terminate()` MUST log, naming the count and the joined list of unsaved documents, when the final flush reports a non-empty list, and MUST log nothing when it reports an empty one (TextDocumentCoordinator.swift).
- **coordinator-default-debounce-one-second**: The coordinator's initializer MUST default its save debounce to one second when the caller supplies none (TextDocumentCoordinator.swift).
- **coordinator-reloader-started-at-init**: Initialization MUST start the reloader unconditionally as its last step, registering the document-store observer before any host code can open a document through this coordinator (TextDocumentCoordinator.swift).
- **storage-local-edit-guard-prevents-reentrant-rewrite**: `replaceCharacters(in:with:)` MUST set its local-edit guard only around the call that pushes the change into the `TextDocument`, and the external-change handler MUST return immediately while that guard is set, so pushing a local edit into the document cannot re-enter and corrupt the storage the user is mid-edit in (TextDocumentStorage.swift).
- **storage-document-updated-before-edited-notification**: `replaceCharacters(in:with:)` MUST update the `TextDocument` before calling AppKit's `edited(...)`, so an observer re-entering from inside editing notification processing, such as the annotation coordinator or the highlight provider, converts ranges against a document that already reflects the edit (TextDocumentStorage.swift).
- **storage-range-converted-before-backing-store-mutated**: `replaceCharacters(in:with:)` MUST convert the incoming range against the `TextDocument` before mutating the backing string storage, because the document still describes the pre-edit text at that point and the backing store would not (TextDocumentStorage.swift).
- **storage-external-change-full-rewrite-not-partial-replay**: The external-change handler MUST rewrite the backing string wholesale from the document's current text rather than replaying the incoming change's own range, since by the time it fires the document has already applied every change in that batch (TextDocumentStorage.swift).
- **storage-main-thread-only-primitives-fail-loudly**: The storage's string accessor, attribute accessor, and `replaceCharacters(in:with:)` MUST each assert that they are running on the main queue before touching the backing store (TextDocumentStorage.swift).
- **storage-external-change-application-count-testable**: The external-change application counter MUST increment exactly once per call that actually rewrites the backing store, and MUST NOT increment for a call turned away by the local-edit guard or carrying no change (TextDocumentStorage.swift).
- **lsp-request-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. Every catch around a language-server request in this family discards the thrown error with no logging call at all — `LSPCompletionDelegate.completionSuggestionsRequested`'s completion-request catch, `LSPHoverController.present`'s hover-request catch, `LSPJumpToDefinitionDelegate.queryLinks`'s definition-request catch, and `SemanticTokenHighlightProvider.fetch`'s semantic-tokens-request catch — even though `LSPCompletionDelegate` and `SemanticTokenHighlightProvider` both conform to `Loggable` and log elsewhere, while `LSPHoverController` and `LSPJumpToDefinitionDelegate` conform to `Loggable` nowhere in either file; what is missing is a log call, or a comment stating the silence is intentional because the user-visible fallback (no completions, no hover, no jump target, no highlights) is itself considered sufficient signal, and either would settle it.
- **document-read-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. `OpenDocumentReloader.reloadIfNeeded`'s catch around its injected file reader discards the thrown read error with no logging call, unlike the dirty-conflict path in the very same file, `apply(_:to:uri:readAt:)`, which logs via `Self.logger.notice`; what is missing is a log call on the caught path, or a comment saying why a transient read failure between the stat and the read needs no signal beyond the next event's retry, and either would settle it.
## Configuration

| Setting | Default | Effect |
|---|---|---|
| Hover request debounce | injected per `LSPHoverController` instance | Delays issuing a hover request after pointer movement to avoid a request per pixel of movement. |
| Semantic-token refetch debounce | 300 ms (`SemanticTokenHighlightProvider`) | Collapses consecutive edits into one `semanticTokens/full` request. |
| Semantic-token query timeout | 5 seconds (`SemanticTokenHighlightProvider`) | Bounds how long a parked highlight query waits for an in-flight fetch before answering empty. |
| Save debounce | 1 second, overridable at `init` (`TextDocumentCoordinator`) | Bounds how long a dirty document's write is delayed before it is flushed to disk. |
| Directory watcher factory | injected `DirectoryWatching`-conforming type (`OpenDocumentReloader`) | Substitutable for tests; production uses an FSEvents-backed implementation. |
| File reader | injected closure (`OpenDocumentReloader`) | Substitutable for tests; production reads the file at the given URL. |

## Localization

All server-authored text (hover contents, completion labels and detail, diagnostic messages) is displayed as the server sent it and is not translated by this family. The one locally authored string surface is `TextDocumentCoordinator.terminate()`'s unsaved-documents log message, which is a developer-facing log line, not user-facing UI text, and is therefore not localized.

## Feature Flags

None of these twelve types is gated behind a feature flag; each capability (completion, hover, jump-to-definition, semantic highlighting) is instead gated per-document by the connected server's own declared capabilities, checked at the point of use (`declaresHoverProvider`, `declaresDefinitionProvider`, `fullRequestLegend`).

## Analytics

None of these twelve types emits analytics events. `LanguageServerStatusModel`'s published rows exist for a status UI to render, not for telemetry, and are not otherwise recorded.

## Privacy

Document text, completion prefixes, and hover/diagnostic content pass through this family only in memory, addressed to the language server already configured for that document's project; none of these twelve types persists, logs, or forwards document content to any destination other than that server. `TextDocumentCoordinator`'s unsaved-documents log message names document identifiers, not their content.

