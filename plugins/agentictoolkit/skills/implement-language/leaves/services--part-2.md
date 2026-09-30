<!-- leaf: implement-language/services--part-2 · source: language-services.md -->

# LanguageServices — continued (part 2)

**Rules** (cite as `implement-language/services--part-2#<slug>`):

- `utf16-based-addressing` MUST
- `init-defaults` MUST
- `offset-position-round-trip` MUST
- `offset-clamping` MUST
- `position-clamping` MUST
- `character-past-line-end-stops-at-terminator` MUST
- `boundary-rounding` MUST
- `line-index-rebuilt-on-mutation` MUST
- `apply-batch-single-version-bump` MUST
- `apply-preresolves-offsets` MUST
- `apply-descending-splice-order` MUST
- `change-events-built-before-mutation-in-splice-order` MUST
- `co-located-edits-preserve-caller-order` MUST
- `change-events-report-mutated-range` MUST
- `overlapping-edits-clamp-not-trap` MUST
- `apply-sets-dirty-and-notifies` MUST
- `replaceall-contract` MUST — replaceAll(with:) MUST replace text outright, bump version by 1, clear isDirty, and notify every change handler with …
- `markclean-contract` MUST — markClean() MUST clear isDirty without changing text or version and MUST raise no content-change notification; it MUST …
- `dirty-state-transitions-only` MUST
- `change-observation-multi-slot` MUST
- `document-observation-token-teardown` MUST
- `document-mainactor-isolation` MUST
- `store-open-first-caller-authoritative` MUST
- `store-open-refcounting` MUST
- `store-close-decrements-and-guards` MUST
- `store-forwards-document-events` MUST
- `store-observer-multi-slot-and-teardown` MUST
- `store-open-documents-snapshot` MUST
- `store-mainactor-isolation` MUST
- `scheduler-debounces-per-uri` MUST
- `scheduler-noop-when-clean` MUST
- `scheduler-write-injected-and-async` MUST
- `scheduler-markclean-version-guarded` MUST — after an injected write returns without throwing, the scheduler MUST call document.markClean() only if document.version …
- `scheduler-failed-write-stays-pending` MUST
- `scheduler-failure-logged-not-otherwise-surfaced` MUST
- `scheduler-cancel-drops-without-writing` MUST

## Behavioral Requirements

- **utf16-based-addressing**: every offset and `Position` this component deals in MUST be a UTF-16 code-unit offset, matching LSP's own `Position.character` semantics — never `Character`-based and never byte-based.
- **init-defaults**: `TextDocument.init(uri:languageId:text:version:)` MUST default `version` to `0` and MUST initialize `isDirty` to `false`.
- **offset-position-round-trip**: `position(forUTF16Offset:)` and `utf16Offset(for:)` MUST be inverse operations over every offset from `0` through the document's current UTF-16 length.
- **offset-clamping**: `position(forUTF16Offset:)` MUST clamp an offset below `0` or beyond the document's UTF-16 length into `[0, utf16Length]` rather than trapping.
- **position-clamping**: `utf16Offset(for:)` MUST clamp an out-of-range `Position.line` into `[0, lastLine]` and MUST clamp `Position.character` into `[0, that line's content length]` rather than trapping.
- **character-past-line-end-stops-at-terminator**: a `Position.character` past a line's own content length MUST resolve to that line's content end, before its terminator, never past the terminator and into the next line — LSP's own "defaults back to the line length" rule.
- **boundary-rounding**: `position(forUTF16Offset:)` and `utf16Offset(for:)` MUST round an offset that would otherwise split a UTF-16 surrogate pair or a CRLF terminator down to the nearest valid boundary, rather than returning an offset that lands inside either.
- **line-index-rebuilt-on-mutation**: `TextDocument` MUST rebuild its cached `lineStarts`, `lineContentEnds`, and `utf16Length` from a single scan of `text` on every `apply(_:)` and `replaceAll(with:)` call, so `position(forUTF16Offset:)`/`utf16Offset(for:)` never rescan `text` themselves.
- **apply-batch-single-version-bump**: `apply(_:)` MUST treat an entire batch of `TextEdit`s as one version bump — `version` increases by exactly `1` regardless of how many edits the batch contains — and MUST return `[]`, bump no version, and notify no handler for an empty batch.
- **apply-preresolves-offsets**: `apply(_:)` MUST resolve every edit's `Position` range against the pre-edit document before mutating any text, so a later edit's offset is never computed against a partially-mutated string.
- **apply-descending-splice-order**: `apply(_:)` MUST splice its edits back-to-front by descending start offset, with ties broken by descending caller-supplied index, so an earlier edit's already-resolved offset stays valid while a later one is spliced in.
- **change-events-built-before-mutation-in-splice-order**: the `TextDocumentContentChangeEvent`s `apply(_:)` returns MUST be built, before any splice runs, from the same descending-order sequence used to mutate the text — never from the caller's original array order — so each event's range stays valid against the document the previous event in the returned list produced, per LSP's `didChange` contract.
- **co-located-edits-preserve-caller-order**: for two or more edits in a batch that share the same start offset, `apply(_:)` MUST splice them so the resulting text reads in the caller's array order (an opening paren, then its argument, then the closing paren MUST produce the parenthesized form, not a scrambled one).
- **change-events-report-mutated-range**: `apply(_:)` MUST report each returned event's range and `rangeLength` from the offsets it actually mutated after clamping, never from the caller's original out-of-range request.
- **overlapping-edits-clamp-not-trap**: when a batch contains edits whose ranges overlap — which the protocol forbids a well-behaved server from sending but does not prevent a misbehaving one from sending — `apply(_:)` MUST clamp the resulting splice to the text's current bounds rather than trapping.
- **apply-sets-dirty-and-notifies**: `apply(_:)` MUST set `isDirty` to `true` and invoke every registered change handler with the new `version` and the returned events, after the mutation and line-index rebuild.
- **replaceAll-contract**: `replaceAll(with:)` MUST replace `text` outright, bump `version` by `1`, clear `isDirty`, and notify every change handler with exactly one `TextDocumentContentChangeEvent` whose `range` and `rangeLength` are both `nil` — LSP's own wire form for "the document is now this text."
- **markClean-contract**: `markClean()` MUST clear `isDirty` without changing `text` or `version` and MUST raise no content-change notification; it MUST notify dirty-state handlers if `isDirty` was `true` beforehand.
- **dirty-state-transitions-only**: a handler registered through `addDirtyStateHandler(_:)` MUST be invoked only when `isDirty`'s value actually changes — never on a call, such as a second consecutive `markClean()`, that leaves it unchanged.
- **change-observation-multi-slot**: `TextDocument` MUST support more than one concurrent change handler and more than one concurrent dirty-state handler, each independently keyed and independently removable.
- **document-observation-token-teardown**: `addChangeHandler(_:)` and `addDirtyStateHandler(_:)` MUST return a `TextDocumentObservation` whose `isolated deinit` unregisters exactly the one handler that token registered, with no explicit unsubscribe call required.
- **document-mainactor-isolation**: `TextDocument` MUST be usable only from the main actor (`@MainActor final class`), so its entire public surface is already serialized by actor isolation with no additional locking.
- **store-open-first-caller-authoritative**: `TextDocumentStore.open(uri:languageId:text:)` MUST create a new `TextDocument` and emit `.opened` only for the URI's first open; every subsequent open before a matching `close` MUST return the exact same `TextDocument` instance, increment its open count, and MUST ignore that call's `languageId` and `text` — the text already open is authoritative, not the text a later open call supplies.
- **store-open-refcounting**: `TextDocumentStore` MUST reference-count opens per URI, so two openers of the same file share one `TextDocument` and it is torn down only once every opener has called `close`.
- **store-close-decrements-and-guards**: `close(uri:)` MUST decrement the URI's open count and, only once it reaches zero or below, remove the document and emit `.closed`; `close(uri:)` on a URI with no open entry MUST be a no-op.
- **store-forwards-document-events**: while a document is open, `TextDocumentStore` MUST forward its content and dirty-state notifications as store-level `.changed` and `.dirtyStateChanged` events, each carrying the document's `uri` alongside the document's own version, changes, or `isDirty` payload.
- **store-observer-multi-slot-and-teardown**: `addObserver(_:)` MUST support more than one concurrent observer, each independently keyed, and MUST return a `TextDocumentStoreObservation` whose `isolated deinit` unregisters exactly that observer.
- **store-open-documents-snapshot**: `openDocuments` MUST return exactly one `TextDocument` per currently-open URI, regardless of that URI's open count.
- **store-mainactor-isolation**: `TextDocumentStore` MUST be usable only from the main actor.
- **scheduler-debounces-per-uri**: `schedule(_:)` MUST debounce per document URI — repeated `schedule(_:)` calls for the same `uri` inside the debounce window MUST collapse into exactly one write once the window elapses, against the most recently scheduled `TextDocument` instance.
- **scheduler-noop-when-clean**: `schedule(_:)` MUST arm no timer and perform no write when `document.isDirty` is `false` at the time of the call.
- **scheduler-write-injected-and-async**: the persistence operation MUST be caller-injected (`Write = @MainActor (TextDocument) async throws -> Void`) rather than hardcoded, and per its own documentation MUST leave the main actor for its actual I/O, so a large or network-volume write does not block the UI.
- **scheduler-markClean-version-guarded**: after an injected write returns without throwing, the scheduler MUST call `document.markClean()` only if `document.version` is unchanged from the version captured immediately before the write began; if the version changed while the write was suspended, the document MUST remain dirty and MUST NOT be marked clean.
- **scheduler-failed-write-stays-pending**: a write that throws MUST leave its `uri` pending in the scheduler (never removed) and MUST leave the document dirty with its text unmodified; the scheduler MUST re-arm that `uri` with exponential backoff, capped at a maximum retry interval, rather than dropping the edit.
- **scheduler-failure-logged-not-otherwise-surfaced**: a failed write MUST be logged, at error level, through `TextDocumentSaveScheduler.logger`, and MUST NOT be surfaced to the caller of `schedule(_:)` in any other way — `schedule(_:)` returns `Void`, and `cancel`/flush operations report only which URIs are still pending, never an error value.
- **scheduler-cancel-drops-without-writing**: `cancel(uri:)` MUST drop `uri`'s pending save without performing its write.
