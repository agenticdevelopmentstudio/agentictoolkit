---
id: 82065ef6-9f0a-424f-aa32-3814d9cb843f
title: LanguageServices
domain: agentictoolkit://recipes/language-services
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The MainActor text-document model, the app-wide open-document registry, and the debounced autosave scheduler behind every LSP-backed editor pane, plus the one shared URL-to-DocumentUri conversion point.
platforms:
- swift
- macos
tags:
- language-server
- text-document
- autosave
- debounce
- document-store
- lsp
- utf-16
depends-on: []
related:
- agentictoolkit://recipes/file-editor-view
- agentictoolkit://recipes/document-editor-view-controller
references:
- packages/apple/AgenticToolkit/Language/TextDocument.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/TextDocumentSaveScheduler.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/TextDocumentStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/URL+DocumentUri.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Concurrency/KeyedDebouncer.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/TextDocumentTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/TextDocumentSaveSchedulerTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/TextDocumentStoreTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# LanguageServices

## Overview

`LanguageServices` is the Foundation-only, `@MainActor` core behind every LSP-backed editor pane in `packages/apple/AgenticToolkit/Language/`: `TextDocument` (one open file's URI, language id, monotonically increasing version, text, and dirty flag, with a cached line index for UTF-16 offset/`Position` conversion), `TextDocumentStore` (the reference-counted registry of currently-open `TextDocument`s, shared by every editor pane so two panes on the same file share one buffer), `TextDocumentSaveScheduler` (a per-URI debounced autosave that never drops a failed write), and `URL.documentUri` (the single conversion from a local file `URL` to the `DocumentUri` string two independent call sites must agree on). None of the four imports AppKit, UIKit, or SwiftUI, so the whole surface is usable from the headless daemon process as well as from a windowed host. LSP addresses text in UTF-16 code units, not `Character`s or bytes — `TextDocument` is built around that fact, including the emoji-and-accented-character-counts-as-more-than-one-unit consequence of it. `TextDocumentSaveScheduler` wraps `KeyedDebouncer<DocumentUri>` (`Core/Concurrency/KeyedDebouncer.swift`), a generic per-key debounce-and-retry helper this file depends on but does not define.

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
- **scheduler-flushPendingSave-is-per-uri**: `flushPendingSave(uri:)` MUST write only the named `uri`'s pending save and MUST leave every other pending `uri`'s debounce timer armed and untouched.
- **scheduler-flushPendingSave-no-double-write**: two overlapping calls that both resolve to flushing the same `uri` — a second `flushPendingSave(uri:)`, or one racing that `uri`'s debounce elapsing — MUST produce exactly one write; the later caller MUST await the write already in flight rather than starting a second one.
- **scheduler-flushPendingSaves-reports-still-failing**: `flushPendingSaves()` MUST attempt every pending `uri`'s write, one at a time, and MUST return exactly the `uri`s whose write is still pending once every attempt completes.
- **scheduler-pendingURIs-reflects-full-lifecycle**: `pendingURIs` MUST list every `uri` that is scheduled, currently writing, or awaiting a backoff retry after a failed write.
- **scheduler-mainactor-isolation**: `TextDocumentSaveScheduler` MUST be usable only from the main actor.
- **documentUri-single-conversion-point**: `URL.documentUri` MUST return `absoluteString`, and MUST be the one place in the framework a local file `URL` is converted to the `DocumentUri` (LSP's `file://` string form) it is opened under, so two independent call sites addressing "the same file" — the file editor opening a document, and the file tree looking that document back up to show a dirty indicator — read exactly the same string.

## Appearance

Not applicable — this is a text-document model, an open-document registry, and a debounced autosave scheduler, not a visual component.

## States

Not applicable — this is a text-document model, an open-document registry, and a debounced autosave scheduler, not a visual component. Its runtime state machines — `isDirty`'s true/false lifecycle, a save's scheduled/running/retrying lifecycle in `TextDocumentSaveScheduler` — are captured under Behavioral Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a text-document model, an open-document registry, and a debounced autosave scheduler, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| language-services-001 | offset-position-round-trip | `TextDocument(text: "ab\ncde\nf")`; call `position(forUTF16Offset:)` then `utf16Offset(for:)` for every offset `0` through the text's UTF-16 length | Every offset round-trips to itself — mirrors `TextDocumentTests.roundTripsEveryOffset` |
| language-services-002 | utf16-based-addressing | `TextDocument(text: "let x = \"😀\"\nlet y = 1")`; measure the range of the emoji | The emoji's UTF-16 range has length `2` (a surrogate pair), and `position(forUTF16Offset:)` before/after it differ by `2` characters — mirrors `TextDocumentTests.multiByteContentCountsUTF16Units` |
| language-services-003 | boundary-rounding | `TextDocument(text: "a😀b")`; `position(forUTF16Offset: 2)` (inside the surrogate pair) then round-trip back through `utf16Offset(for:)` | Rounds down to `Position(line: 0, character: 1)` (offset `1`, before the pair) and round-trips stably — mirrors `TextDocumentTests.surrogatePairOffsetRoundsDownAndRoundTrips` |
| language-services-004 | boundary-rounding | `TextDocument(text: "a\r\nb")`; `position(forUTF16Offset: 2)` (between `\r` and `\n`) then round-trip | Rounds down to offset `1`, before the CRLF pair, and round-trips stably — mirrors `TextDocumentTests.crlfSplitOffsetRoundsDownAndRoundTrips` |
| language-services-005 | offset-clamping, position-clamping | `TextDocument(text: "abc")`; `position(forUTF16Offset: 9999)` and `position(forUTF16Offset: -50)`; `utf16Offset(for: Position(line: 999, character: 999))` on `"ab\ncd"` | `9999` clamps to `Position(line: 0, character: 3)`; `-50` clamps to `Position(line: 0, character: 0)`; the far-beyond `Position` clamps to offset `5`, the text's total length — mirrors `TextDocumentTests.outOfRangeOffsetClamps`/`outOfRangePositionClamps` |
| language-services-006 | character-past-line-end-stops-at-terminator | `TextDocument(text: "ab\ncd")`; `utf16Offset(for: Position(line: 0, character: 999))` | Returns `2`, the offset of the newline, not past it — mirrors `TextDocumentTests.characterPastLineEndStopsBeforeTheNewline` |
| language-services-007 | apply-batch-single-version-bump, apply-descending-splice-order | `TextDocument(text: "abcdef")`; `apply([insert "XY" at (0,1)-(0,1), replace (0,4)-(0,5) with "Z"])`, passed in ascending order | `document.text == "aXYbcdZf"`, and `version` increased by exactly `1` — mirrors `TextDocumentTests.applyTwoEditsBackToFront` |
| language-services-008 | overlapping-edits-clamp-not-trap | `TextDocument(text: "abcdefghijkl")`; `apply([delete (0,4)-(0,12), replace (0,0)-(0,8) with "X"])`, whose ranges overlap | `document.text == "X"` with no trap — mirrors `TextDocumentTests.applyOverlappingEditsDoesNotTrap` |
| language-services-009 | change-events-built-before-mutation-in-splice-order | `TextDocument(text: "alpha beta gamma")`; `apply([edit(0,0,0,5,"ALPHA"), edit(0,6,0,10,"BETA"), edit(0,11,0,16,"GAMMA")])` handed in ascending order; replay the returned events one at a time onto a fresh document seeded with the original text | The replayed "server view" equals `document.text` (`"ALPHA BETA GAMMA"`) — mirrors `TextDocumentTests.ascendingBatchRoundTripsToTheServer` |
| language-services-010 | co-located-edits-preserve-caller-order | `TextDocument(text: "foo\n")`; `apply([insert "(" at (0,3)-(0,3), insert "bar" at (0,3)-(0,3), insert ")" at (0,3)-(0,3)])` | `document.text == "foo(bar)\n"`, not a scrambled ordering — mirrors `TextDocumentTests.coLocatedEditsKeepTheCallersOrder` |
| language-services-011 | change-events-report-mutated-range | `TextDocument(text: "abc")`; `apply([edit at (0,10)-(0,20) with "X"])`, a range entirely past the end of the text | The returned event's range is the clamped `(0,3)-(0,3)`, not the requested `(0,10)-(0,20)` — mirrors `TextDocumentTests.applyReportsTheClampedRangeNotTheRequestedRange` |
| language-services-012 | replaceAll-contract, dirty-state-transitions-only | `TextDocument(text: "abc")`; `apply(...)` (dirty becomes `true`), then `replaceAll(with: "fresh from disk")` | `isDirty == false` after `replaceAll`, and the dirty-state handler observes exactly `[true, false]` — mirrors `TextDocumentTests.isDirtyLifecycle`/`replaceAllReportsCleanTransition` |
| language-services-013 | markClean-contract, document-observation-token-teardown | `TextDocument(text: "abc")`; register a dirty-state handler and a change handler; `apply(...)`; call `markClean()` | Dirty handler observes `[true, false]`; the change-handler's fire count stays at `1` (the save that changed no text raises no content event) — mirrors `TextDocumentTests.markCleanNotifiesDirtyStateObservers` |
| language-services-014 | store-open-first-caller-authoritative | `TextDocumentStore().open(uri: "file:///a.swift", languageId: "swift", text: "one")`, then `.open(uri: "file:///a.swift", languageId: "swift", text: "two")` | Both calls return the identical `TextDocument`; its `text` is still `"one"`; exactly one `.opened` event is emitted — mirrors `TextDocumentStoreTests.openTwiceReturnsSameDocument` |
| language-services-015 | store-open-refcounting, store-close-decrements-and-guards | Open the same `uri` twice on one `TextDocumentStore`, then call `close(uri:)` once, then again | After the first `close`, `document(for:)` still returns the document and no `.closed` fires; after the second `close`, `document(for:)` returns `nil` and `.closed` fires — mirrors `TextDocumentStoreTests.closeIsReferenceCounted` |
| language-services-016 | store-forwards-document-events | Open a document on a `TextDocumentStore`; call `document.apply(...)` on the returned instance | The store's observer receives a `.changed` event carrying the same `uri` and the document's new `version` — mirrors `TextDocumentStoreTests.applyEmitsChangedWithNewVersion` |
| language-services-017 | store-observer-multi-slot-and-teardown | Register an observer, drop its `TextDocumentStoreObservation` token, then `open` a second URI | No event is delivered for the second `open` — mirrors `TextDocumentStoreTests.droppingTokenStopsDelivery` |
| language-services-018 | scheduler-debounces-per-uri, scheduler-markClean-version-guarded | `TextDocumentSaveScheduler(debounce: 50ms, write: recordingWriter)`; call `schedule(document)` ten times, 5ms apart, on the same dirty document; wait past the debounce | The writer records exactly one write for that `uri`, and `document.isDirty == false` afterward — mirrors `TextDocumentSaveSchedulerTests.tenSchedulesInsideDebounceProduceOneWrite` |
| language-services-019 | scheduler-failed-write-stays-pending | Schedule a dirty document whose injected write always throws; wait past the debounce and the first retry attempt | `writer.writtenURIs` stays empty, `document.isDirty == true`, `document.text` is unchanged, and `scheduler.pendingURIs` still contains the `uri` — mirrors `TextDocumentSaveSchedulerTests.failedWriteLeavesTheDocumentPending` |
| language-services-020 | scheduler-failed-write-stays-pending, scheduler-flushPendingSaves-reports-still-failing | After the write above starts failing, stop it from throwing, then call `flushPendingSaves()` | The write now succeeds, `document.isDirty == false`, and the returned still-failing array is empty — mirrors `TextDocumentSaveSchedulerTests.failedWriteIsRetriedByALaterFlush` |
| language-services-021 | scheduler-markClean-version-guarded | Schedule a dirty document with a write that suspends; while it is suspended, call `document.apply(...)` again; then let the write complete | `document.isDirty` stays `true` after the write completes, because `document.version` moved past the version captured when the write began — mirrors `TextDocumentSaveSchedulerTests.typingDuringASuspendedWriteKeepsTheDocumentDirty` |
| language-services-022 | scheduler-flushPendingSave-is-per-uri | Schedule three distinct dirty documents on one scheduler, then call `flushPendingSave(uri:)` for only one of them | Only that `uri`'s document is written and marked clean; the other two remain dirty and remain in `pendingURIs` — mirrors `TextDocumentSaveSchedulerTests.perURIFlushWritesOnlyThatDocument` |
| language-services-023 | scheduler-cancel-drops-without-writing | `schedule(document)` then immediately `cancel(uri: document.uri)`; wait past the debounce | The writer records no write, and `pendingURIs` is empty — mirrors `TextDocumentSaveSchedulerTests.cancelBeforeDebounceProducesNoWrite` |
| language-services-024 | documentUri-single-conversion-point | `URL(string: "file:///Users/me/notes.txt")!.documentUri` | Equals `"file:///Users/me/notes.txt"`, the URL's `absoluteString` verbatim |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `uri` | `DocumentUri` (`String`) | none (required) | The document's identity throughout `TextDocument`, `TextDocumentStore`, and `TextDocumentSaveScheduler`; conventionally an LSP `file://` string produced by `URL.documentUri`. |
| `languageId` | `String` | none (required, `TextDocument.init`/`TextDocumentStore.open` only) | Passed through and stored verbatim; neither type validates or interprets it. |
| `text` | `String` | none (required, `TextDocument.init`/`TextDocumentStore.open` only) | The document's initial content; a duplicate `open` call's `text` is ignored (see `store-open-first-caller-authoritative`). |
| `version` | `Int` | `0` | `TextDocument.init`'s starting version; bumped by `apply(_:)` and `replaceAll(with:)` thereafter. |
| `debounce` | `Duration` | `.seconds(1)` | `TextDocumentSaveScheduler.init`'s per-key quiet period before a pending save runs. |
| `write` | `TextDocumentSaveScheduler.Write` (`@MainActor (TextDocument) async throws -> Void`) | none (required) | The caller-injected persistence closure; the scheduler decides only *when* it runs, never *how*. |
| `maximumRetryInterval` | `Duration` (internal `KeyedDebouncer` default) | `.seconds(30)` | Ceiling on the exponential backoff applied after a failed write; not exposed as a `TextDocumentSaveScheduler.init` parameter — a caller cannot currently override it without constructing its own `KeyedDebouncer`. |

## Deep Linking

Not applicable: none of `TextDocument.swift`, `TextDocumentSaveScheduler.swift`, `TextDocumentStore.swift`, or `URL+DocumentUri.swift` defines a URL scheme, route, or navigable destination — `DocumentUri` is an LSP wire-format identifier, not a navigation link.

## Localization

Not applicable: the given sources contain no user-facing string literal. The one string literal any of them produces for display — `TextDocumentSaveScheduler`'s autosave-failure message — is a diagnostic log line, never shown to a user (see Logging).

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: the given sources declare no feature-flag key and contain no conditional feature-gating logic.

## Analytics

Not applicable: the given sources contain no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `TextDocument` holds exactly the caller-supplied `text` for the file at `uri` — in practice, the full content of whatever file a user has open in an editor pane, plus that file's path (as a `DocumentUri`). Neither `TextDocument`, `TextDocumentStore`, nor `TextDocumentSaveScheduler` inspects, parses, or interprets that content beyond UTF-16 offset bookkeeping.
- **Storage**: held only in memory (`TextDocument.text`, and `TextDocumentStore`'s `documentsByURI` map) for as long as the document stays open; `TextDocumentSaveScheduler` writes it back to disk only through the caller-injected `write` closure, which this component does not implement — persistence, encryption, and location are entirely that closure's responsibility.
- **Transmission**: none of the four files performs any network call; each imports only `Foundation` (plus `LanguageServerProtocol` for shared LSP types, and `os` for logging in `TextDocumentSaveScheduler`).
- **Retention**: a document's text and dirty state persist in memory until `TextDocumentStore.close(uri:)` removes the last open reference to it; a save that keeps failing leaves its bytes only in memory, retried in the background with no time limit, until it succeeds or is explicitly `cancel`led.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: `TextDocumentSaveScheduler`

| Event | Level | Message |
|-------|-------|---------|
| An autosave write throws | error | `Auto-save failed for <uri>: <reason> — still pending, will retry` |

`TextDocument.swift`, `TextDocumentStore.swift`, and `URL+DocumentUri.swift` make no logging call of their own; only `TextDocumentSaveScheduler` logs, through its `Loggable` conformance, and only on a failed write.

## Platform Notes

- **SwiftUI**: not a dependency of any of the four files — each imports only `Foundation` (plus `LanguageServerProtocol`, and `os` for the scheduler's logger). A SwiftUI editor view consumes `TextDocument`/`TextDocumentStore`/`TextDocumentSaveScheduler` through injected instances and its own `@State`/`@Observable` wiring around the change/dirty-state handler tokens, not through anything this component provides directly.
- **AppKit / UIKit**: this is the source. All four files live in `packages/apple/AgenticToolkit/Language/`, part of the `AgenticToolkitLanguage` framework target (`project.yml` declares `platform: macOS`, no iOS target today), depending on `AgenticToolkitCore`, `JSONRPC`, `LanguageServerProtocol`, and `LanguageClient`. None imports AppKit or UIKit, so the type is equally usable from the headless daemon process or a windowed host.
- **Compose**: Kotlin's `String` is UTF-16-backed like Swift's, so `TextDocument`'s offset/`Position` math (including the surrogate-pair and CRLF boundary rounding) ports with direct code-unit arithmetic over `CharSequence`, not a `codePoint`-aware API. Model the refcounted registry as a class holding a `MutableMap<String, Entry>` confined to a single `CoroutineDispatcher` (the direct analogue of `@MainActor`), and port `TextDocumentSaveScheduler`/`KeyedDebouncer` as a `Job`-per-key debounce (`launch { delay(debounceMs) }`) with the same generation-bump-on-reschedule and exponential-backoff-on-failure bookkeeping, since Kotlin coroutines offer no built-in debounce-with-retry primitive.
- **React/Web**: JavaScript strings are UTF-16 internally (`String.prototype.length`/`charCodeAt` already operate on UTF-16 code units), so the offset/position math ports almost unchanged. Model the debounced autosave with a `Map<uri, { timer, generation, failures }>` and `setTimeout`/`clearTimeout` in place of `KeyedDebouncer`'s `Task`-based timers, and the refcounted store as a `Map<string, { document, openCount }>`; persistence goes through the File System Access API or a backend endpoint, wrapped in the same never-remove-on-failure retry loop.
- **WinUI 3**: .NET's `System.String` is also UTF-16 (`Length`/the string indexer are UTF-16 code units, matching Swift's `text.utf16`), so `TextDocument`'s offset/`Position` conversion, including surrogate-pair and CRLF boundary rounding, ports with direct index arithmetic and no encoding translation. Model `TextDocumentStore`'s refcounted registry as a `Dictionary<string, Entry>` confined to the UI thread's `DispatcherQueue` (the closest analogue to `@MainActor`), and port `TextDocumentSaveScheduler`/`KeyedDebouncer` with a `DispatcherQueueTimer` or `Task.Delay`-based per-key debounce that keeps a failed key's entry — mirroring `retry-ceiling-default-and-floor`-style backoff — until a write via `System.IO.File.WriteAllTextAsync` succeeds or is explicitly cancelled.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |

`separation-of-concerns` passes because each of the four files owns exactly one concern — offset/position math and mutation (`TextDocument`), open/close reference counting (`TextDocumentStore`), debounced persistence timing (`TextDocumentSaveScheduler`, with the actual write injected by its caller), and one string conversion (`URL.documentUri`) — with no file reaching into another's internals. `unit-test-coverage` passes on the strength of `TextDocumentTests`, `TextDocumentSaveSchedulerTests`, and `TextDocumentStoreTests`, which exercise round-tripping, clamping, the edit-ordering contract, debounce coalescing, failed-write retention, and refcounted open/close with meaningful assertions, not placeholders. `explicit-error-handling` passes because a failed autosave write is never silently swallowed: it is logged, the document stays dirty, and the entry stays pending for a later retry or flush to discover. `idempotent-operations` passes because a retried autosave write always persists the document's current full text rather than an incremental delta, so repeating a write after a transient failure produces the same on-disk result as the first attempt would have. `data-integrity` is partial: the version-staleness check in `scheduler-markClean-version-guarded` prevents the dirty flag from lying about whether the in-memory buffer matches what was written, but nothing in the given sources verifies that the bytes the injected `write` closure produced actually landed correctly on disk — success or failure is entirely whatever that closure reports. `unicode-support` passes because `TextDocument`'s offset and position math is built explicitly around UTF-16 code units, surrogate pairs (including emoji), and CRLF terminators, with dedicated boundary-rounding logic and tests for exactly those cases.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
