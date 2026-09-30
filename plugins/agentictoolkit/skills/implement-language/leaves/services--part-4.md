<!-- leaf: implement-language/services--part-4 · source: language-services.md -->

# LanguageServices — continued (part 4)

## Design Decisions

**Decision**: `TextDocumentSaveScheduler` delegates all per-key debounce, retry, and backoff bookkeeping to the generic `KeyedDebouncer<DocumentUri>` rather than implementing its own.
**Rationale**: per the source's own doc comment, three prior copies of this exact pattern — `NotesManager`'s save scheduling, this type's own earlier shape, and `SemanticTokenHighlightProvider`'s one-shot variant — were "structurally identical and independently wrong in the same place": each removed a pending entry from its map before attempting the write and only logged on failure, so a write that hit a full disk or a revoked network volume silently lost the edit. Extracting the shared debouncer fixes that failure mode once for every caller instead of three times.
**Approved**: pending

**Decision**: `TextDocumentStore.open(uri:languageId:text:)` ignores a duplicate open's `text` and `languageId`, returning the already-open `TextDocument` unchanged.
**Rationale**: the source's own doc comment states "the text already open is authoritative, not the text of a later open call" — favoring the in-memory buffer, which may already carry unsaved edits from one pane, over whatever a second opener happens to read from disk, rather than silently discarding the first pane's edits when a second pane opens the same file.
**Approved**: pending

**Decision**: `TextDocumentSaveScheduler` marks a document clean only if its `version` is unchanged from the version captured immediately before the write began, rather than unconditionally after a successful write returns.
**Rationale**: the write is `async` and suspends, so the user can type between the snapshot and the write landing. Per the doc comment, marking clean unconditionally "would clear the dirty indicator over a buffer that is genuinely newer than the file"; declining does not lose the edit, because `TextDocument`'s own change handler has already scheduled the next save for it. The cost is one extra debounce cycle in the rare case the user types during a write.
**Approved**: pending

**Decision**: `TextDocumentStore` performs no coordination at all with `TextDocumentSaveScheduler` — `close(uri:)` neither flushes nor cancels any pending autosave for the URI it closes.
**Rationale**: the two types hold no reference to each other anywhere in the given sources; each is independently injectable and independently testable. Wiring "close implies flush" is left to a caller — the sibling `file-editor-view` recipe documents its own call to `flushPendingSave(uri:)` before discarding a pane's document — rather than being built into either lower-level type. Recorded here as an architectural boundary between "what is open" and "what is scheduled to be saved," not as a defect in either type.
**Approved**: pending

**Decision**: `URL.documentUri` returns `absoluteString` verbatim, with no normalization of symlinks, trailing slashes, or differing percent-encoding between two URLs that name the same file on disk.
**Rationale**: the extension's own doc comment states a narrower contract than full URL equivalence — it exists so "two independent call sites... agree on exactly this string for exactly the same file," i.e. so the *same* `URL` value converts consistently, not so that two *different* string representations of the same on-disk file converge to one `DocumentUri`. Any such normalization, where a caller needs it, happens at a different layer outside this file.
**Approved**: pending
