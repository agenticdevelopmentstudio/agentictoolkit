---
id: 82065ef6-9f0a-424f-aa32-3814d9cb843f
title: Language Services
domain: agentictoolkit://cookbook/workspace/language/language-services
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The text-document model, the app-wide open-document registry, and the debounced autosave scheduler behind every LSP-backed editor pane, plus the one shared URL-to-DocumentUri conversion point.
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
- agentictoolkit://cookbook/workspace/files/file-editor-view
- agentictoolkit://cookbook/workspace/documents/document-editor-view
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

# Language Services

## Overview

Language Services is the core behind every LSP-backed editor pane: a text-document model (one open file's URI, language id, monotonically increasing version, text, and dirty flag, with a cached line index for UTF-16 offset/position conversion), a document store (the reference-counted registry of currently-open text documents, shared by every editor pane so two panes on the same file share one buffer), a save scheduler (a per-URI debounced autosave that never drops a failed write), and a URL-to-document-URI conversion (the single conversion from a local file URL to the `DocumentUri` string two independent call sites must agree on). The whole surface is usable from a headless background process as well as from a windowed host. LSP addresses text in UTF-16 code units, not user-perceived characters or bytes — the text-document model is built around that fact, including the emoji-and-accented-character-counts-as-more-than-one-unit consequence of it. The save scheduler wraps a generic per-key debounce-and-retry helper this component depends on but does not define.

## Behavioral Requirements

- **utf16-based-addressing**: every offset and `Position` this component deals in MUST be a UTF-16 code-unit offset, matching LSP's own `Position.character` semantics — never based on grapheme clusters (user-perceived characters) and never byte-based.
- **init-defaults**: creating a text document MUST default its version to `0` and MUST initialize its dirty flag to `false`.
- **offset-position-round-trip**: converting a UTF-16 offset to a position, and converting a position back to a UTF-16 offset, MUST be inverse operations over every offset from `0` through the document's current UTF-16 length.
- **offset-clamping**: converting a UTF-16 offset to a position MUST clamp an offset below `0` or beyond the document's UTF-16 length into `[0, utf16Length]` rather than crashing.
- **position-clamping**: converting a position to a UTF-16 offset MUST clamp an out-of-range `Position.line` into `[0, lastLine]` and MUST clamp `Position.character` into `[0, that line's content length]` rather than crashing.
- **character-past-line-end-stops-at-terminator**: a `Position.character` past a line's own content length MUST resolve to that line's content end, before its terminator, never past the terminator and into the next line — LSP's own "defaults back to the line length" rule.
- **boundary-rounding**: converting between a UTF-16 offset and a position MUST round an offset that would otherwise split a UTF-16 surrogate pair or a CRLF terminator down to the nearest valid boundary, rather than returning an offset that lands inside either.
- **line-index-rebuilt-on-mutation**: the text document MUST rebuild its cached line-start offsets, line-content-end offsets, and UTF-16 length from a single scan of its text on every edit-apply and full-replace operation, so converting between offsets and positions never rescans the text itself.
- **apply-batch-single-version-bump**: applying a batch of edits MUST treat the entire batch as one version bump — the version increases by exactly `1` regardless of how many edits the batch contains — and MUST return an empty list of change events, bump no version, and notify no handler for an empty batch.
- **apply-preresolves-offsets**: applying a batch of edits MUST resolve every edit's `Position` range against the pre-edit document before mutating any text, so a later edit's offset is never computed against a partially-mutated string.
- **apply-descending-splice-order**: applying a batch of edits MUST splice its edits back-to-front by descending start offset, with ties broken by descending caller-supplied index, so an earlier edit's already-resolved offset stays valid while a later one is spliced in.
- **change-events-built-before-mutation-in-splice-order**: the `TextDocumentContentChangeEvent`s that applying a batch of edits returns MUST be built, before any splice runs, from the same descending-order sequence used to mutate the text — never from the caller's original array order — so each event's range stays valid against the document the previous event in the returned list produced, per LSP's `didChange` contract.
- **co-located-edits-preserve-caller-order**: for two or more edits in a batch that share the same start offset, applying the batch MUST splice them so the resulting text reads in the caller's array order (an opening paren, then its argument, then the closing paren MUST produce the parenthesized form, not a scrambled one).
- **change-events-report-mutated-range**: applying a batch of edits MUST report each returned event's range and `rangeLength` from the offsets it actually mutated after clamping, never from the caller's original out-of-range request.
- **overlapping-edits-clamp-not-trap**: when a batch contains edits whose ranges overlap — which the protocol forbids a well-behaved server from sending but does not prevent a misbehaving one from sending — applying the batch MUST clamp the resulting splice to the text's current bounds rather than crashing.
- **apply-sets-dirty-and-notifies**: applying a batch of edits MUST set the dirty flag to `true` and invoke every registered change handler with the new version and the returned events, after the mutation and line-index rebuild.
- **replaceAll-contract**: the full-replace operation MUST replace the document's text outright, bump the version by `1`, clear the dirty flag, and notify every change handler with exactly one `TextDocumentContentChangeEvent` whose `range` and `rangeLength` are both `null` — LSP's own wire form for "the document is now this text."
- **markClean-contract**: marking the document clean MUST clear the dirty flag without changing the text or version and MUST raise no content-change notification; it MUST notify dirty-state handlers if the dirty flag was `true` beforehand.
- **dirty-state-transitions-only**: a registered dirty-state handler MUST be invoked only when the dirty flag's value actually changes — never on a call, such as a second consecutive mark-clean call, that leaves it unchanged.
- **change-observation-multi-slot**: the text document MUST support more than one concurrent change handler and more than one concurrent dirty-state handler, each independently keyed and independently removable.
- **document-observation-token-teardown**: adding a change handler or a dirty-state handler MUST return an observation token, and dropping that token MUST unregister exactly the one handler it registered, with no explicit unsubscribe call required.
- **document-confined-to-primary-thread**: the text document MUST be usable only from the application's primary execution context, so its entire public surface is already serialized by that confinement with no additional locking.
- **store-open-first-caller-authoritative**: opening a URI MUST create a new text document and emit an opened event only for the URI's first open; every subsequent open before a matching close MUST return the exact same text-document instance, increment its open count, and MUST ignore that call's language id and text — the text already open is authoritative, not the text a later open call supplies.
- **store-open-refcounting**: the document store MUST reference-count opens per URI, so two openers of the same file share one text document, and it is torn down only once every opener has closed it.
- **store-close-decrements-and-guards**: closing a URI MUST decrement the URI's open count and, only once it reaches zero or below, remove the document and emit a closed event; closing a URI with no open entry MUST be a no-op.
- **store-forwards-document-events**: while a document is open, the document store MUST forward its content and dirty-state notifications as store-level changed and dirty-state-changed events, each carrying the document's URI alongside the document's own version, changes, or dirty-flag payload.
- **store-observer-multi-slot-and-teardown**: adding an observer MUST support more than one concurrent observer, each independently keyed, and MUST return an observation token whose dropping unregisters exactly that observer.
- **store-open-documents-snapshot**: the set of open documents MUST contain exactly one text document per currently-open URI, regardless of that URI's open count.
- **store-confined-to-primary-thread**: the document store MUST be usable only from the application's primary execution context.
- **scheduler-debounces-per-uri**: scheduling a save MUST debounce per document URI — repeated schedule calls for the same URI inside the debounce window MUST collapse into exactly one write once the window elapses, against the most recently scheduled text-document instance.
- **scheduler-noop-when-clean**: scheduling a save MUST arm no timer and perform no write when the document's dirty flag is `false` at the time of the call.
- **scheduler-write-injected-and-async**: the persistence operation MUST be caller-injected rather than hardcoded, and per its own documentation MUST run its actual I/O off the primary execution context, so a large or network-volume write does not block interaction.
- **scheduler-markClean-version-guarded**: after an injected write returns without failing, the scheduler MUST mark the document clean only if its version is unchanged from the version captured immediately before the write began; if the version changed while the write was suspended, the document MUST remain dirty and MUST NOT be marked clean.
- **scheduler-failed-write-stays-pending**: a write that fails MUST leave its URI pending in the scheduler (never removed) and MUST leave the document dirty with its text unmodified; the scheduler MUST re-arm that URI with exponential backoff, capped at a maximum retry interval, rather than dropping the edit.
- **scheduler-failure-logged-not-otherwise-surfaced**: a failed write MUST be logged, at error level, through the scheduler's own logger, and MUST NOT be surfaced to the caller of the schedule operation in any other way — scheduling a save produces no return value, and cancel/flush operations report only which URIs are still pending, never an error value.
- **scheduler-cancel-drops-without-writing**: cancelling a URI's pending save MUST drop it without performing its write.
- **scheduler-flushPendingSave-is-per-uri**: flushing a single URI's pending save MUST write only that URI's pending save and MUST leave every other pending URI's debounce timer armed and untouched.
- **scheduler-flushPendingSave-no-double-write**: two overlapping calls that both resolve to flushing the same URI — a second flush of that URI, or one racing that URI's debounce elapsing — MUST produce exactly one write; the later caller MUST await the write already in flight rather than starting a second one.
- **scheduler-flushPendingSaves-reports-still-failing**: flushing all pending saves MUST attempt every pending URI's write, one at a time, and MUST return exactly the URIs whose write is still pending once every attempt completes.
- **scheduler-pendingURIs-reflects-full-lifecycle**: the set of pending URIs MUST list every URI that is scheduled, currently writing, or awaiting a backoff retry after a failed write.
- **scheduler-confined-to-primary-thread**: the save scheduler MUST be usable only from the application's primary execution context.
- **documentUri-single-conversion-point**: the URL-to-document-URI conversion MUST return the URL's absolute string form, and MUST be the one place in the component a local file URL is converted to the `DocumentUri` string (LSP's `file://` string form) it is opened under, so two independent call sites addressing "the same file" — the file editor opening a document, and the file tree looking that document back up to show a dirty indicator — read exactly the same string.

## Appearance

Not applicable — this is a text-document model, an open-document registry, and a debounced autosave scheduler, not a visual component.

## States

Not applicable — this is a text-document model, an open-document registry, and a debounced autosave scheduler, not a visual component. Its runtime state machines — the dirty flag's true/false lifecycle, a save's scheduled/running/retrying lifecycle in the save scheduler — are captured under Behavioral Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a text-document model, an open-document registry, and a debounced autosave scheduler, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| language-services-001 | offset-position-round-trip | A text document containing `"ab\ncde\nf"`; convert every offset from `0` through the text's UTF-16 length to a position and back to an offset | Every offset round-trips to itself |
| language-services-002 | utf16-based-addressing | A text document containing `"let x = \"😀\"\nlet y = 1"`; measure the UTF-16 range of the emoji | The emoji's UTF-16 range has length `2` (a surrogate pair), and the positions immediately before and after it differ by `2` characters |
| language-services-003 | boundary-rounding | A text document containing `"a😀b"`; convert offset `2` (inside the surrogate pair) to a position, then convert that position back to an offset | Rounds down to line `0`, character `1` (offset `1`, before the pair) and round-trips stably |
| language-services-004 | boundary-rounding | A text document containing `"a\r\nb"`; convert offset `2` (between the carriage return and the line feed) to a position, then round-trip | Rounds down to offset `1`, before the CRLF pair, and round-trips stably |
| language-services-005 | offset-clamping, position-clamping | A text document containing `"abc"`; convert offset `9999` and offset `-50` to positions; convert `Position(line: 999, character: 999)` to an offset for a document containing `"ab\ncd"` | `9999` clamps to line `0`, character `3`; `-50` clamps to line `0`, character `0`; the far-beyond position clamps to offset `5`, the text's total length |
| language-services-006 | character-past-line-end-stops-at-terminator | A text document containing `"ab\ncd"`; convert `Position(line: 0, character: 999)` to an offset | Returns `2`, the offset of the newline, not past it |
| language-services-007 | apply-batch-single-version-bump, apply-descending-splice-order | A text document containing `"abcdef"`; apply a batch of edits — insert `"XY"` at `(0,1)-(0,1)`, replace `(0,4)-(0,5)` with `"Z"` — passed in ascending order | The text becomes `"aXYbcdZf"`, and the version increased by exactly `1` |
| language-services-008 | overlapping-edits-clamp-not-trap | A text document containing `"abcdefghijkl"`; apply a batch of edits whose ranges overlap — delete `(0,4)-(0,12)`, replace `(0,0)-(0,8)` with `"X"` | The text becomes `"X"` with no crash |
| language-services-009 | change-events-built-before-mutation-in-splice-order | A text document containing `"alpha beta gamma"`; apply a batch of three edits handed in ascending order — `(0,0)-(0,5)`→`"ALPHA"`, `(0,6)-(0,10)`→`"BETA"`, `(0,11)-(0,16)`→`"GAMMA"`; replay the returned change events one at a time onto a fresh document seeded with the original text | The replayed result equals the document's own text (`"ALPHA BETA GAMMA"`) |
| language-services-010 | co-located-edits-preserve-caller-order | A text document containing `"foo\n"`; apply a batch of edits inserting `"("`, then `"bar"`, then `")"`, all at the same position `(0,3)-(0,3)` | The text becomes `"foo(bar)\n"`, not a scrambled ordering |
| language-services-011 | change-events-report-mutated-range | A text document containing `"abc"`; apply an edit at `(0,10)-(0,20)`, a range entirely past the end of the text, replacing it with `"X"` | The returned event's range is the clamped `(0,3)-(0,3)`, not the requested `(0,10)-(0,20)` |
| language-services-012 | replaceAll-contract, dirty-state-transitions-only | A text document containing `"abc"`; apply an edit (the dirty flag becomes `true`), then fully replace its text with `"fresh from disk"` | The dirty flag is `false` after the replace, and the dirty-state handler observes exactly `[true, false]` |
| language-services-013 | markClean-contract, document-observation-token-teardown | A text document containing `"abc"`; register a dirty-state handler and a change handler; apply an edit; mark the document clean | The dirty handler observes `[true, false]`; the change handler's fire count stays at `1` (the save that changed no text raises no content event) |
| language-services-014 | store-open-first-caller-authoritative | A document store; open `file:///a.swift` with language id `"swift"` and text `"one"`, then open the same URI again with text `"two"` | Both calls return the identical text document; its text is still `"one"`; exactly one opened event is emitted |
| language-services-015 | store-open-refcounting, store-close-decrements-and-guards | A document store; open the same URI twice, then close it once, then again | After the first close, the document for that URI is still returned and no closed event fires; after the second close, no document is returned and the closed event fires |
| language-services-016 | store-forwards-document-events | A document store; open a document, then apply an edit to the returned document instance | The store's observer receives a changed event carrying the same URI and the document's new version |
| language-services-017 | store-observer-multi-slot-and-teardown | Register an observer, drop its observation token, then open a second URI | No event is delivered for the second open |
| language-services-018 | scheduler-debounces-per-uri, scheduler-markClean-version-guarded | A save scheduler with a 50ms debounce; schedule the same dirty document ten times, 5ms apart; wait past the debounce | The write is recorded exactly once for that URI, and the document's dirty flag is `false` afterward |
| language-services-019 | scheduler-failed-write-stays-pending | Schedule a dirty document whose injected write always fails; wait past the debounce and the first retry attempt | No write is recorded, the document's dirty flag stays `true`, its text is unchanged, and it remains in the set of pending URIs |
| language-services-020 | scheduler-failed-write-stays-pending, scheduler-flushPendingSaves-reports-still-failing | After the write above starts failing, stop it from failing, then flush all pending saves | The write now succeeds, the document's dirty flag is `false`, and the returned still-failing list is empty |
| language-services-021 | scheduler-markClean-version-guarded | Schedule a dirty document with a write that suspends before completing; while it is suspended, apply another edit to the document; then let the write complete | The dirty flag stays `true` after the write completes, because the document's version moved past the version captured when the write began |
| language-services-022 | scheduler-flushPendingSave-is-per-uri | Schedule three distinct dirty documents on one scheduler, then flush only one of their URIs | Only that URI's document is written and marked clean; the other two remain dirty and remain in the set of pending URIs |
| language-services-023 | scheduler-cancel-drops-without-writing | Schedule a document, then immediately cancel that URI's pending save; wait past the debounce | No write is recorded, and the set of pending URIs is empty |
| language-services-024 | documentUri-single-conversion-point | Convert the URL `file:///Users/me/notes.txt` to its document URI | Equals `"file:///Users/me/notes.txt"`, the URL's absolute string form verbatim |

## Edge Cases

- **Empty edit batch**: applying an empty batch of edits MUST return an empty list and MUST NOT bump the version, rebuild the line index, or notify any handler.
- **Empty document text**: a text document containing an empty string MUST report exactly one line, starting at offset `0`; converting offset `0` to a position, and converting `Position(line: 0, character: 0)` back to an offset, both resolve to that single empty line.
- **Trailing terminator**: text ending in a line feed (or a carriage-return/line-feed pair) MUST produce one more, empty, final line, addressable one past the text's own length — e.g. `"a\n"` has a valid position at line `1`, character `0`, at offset `2`.
- **Whole-line replacement**: a range whose end character is far beyond the line's actual length (LSP's own idiom for "to the end of this line," e.g. character `999`) MUST replace only the line's content, never consuming its terminator — replacing such a range must not join two lines together.
- **A batch of edits handed in out of the order it must be spliced in**: applying a batch of edits MUST NOT assume the caller's array is already sorted by position; it resolves and reorders internally, and MUST still emit events in the LSP-required, self-consistent order regardless of the caller's original order.
- **A large, scrambled batch**: with enough edits for a non-total ordering comparator to actually reorder equal elements, applying a batch of edits MUST still splice deterministically by the documented tiebreak (descending caller index) and MUST still produce events that replay to the same text on a fresh document.
- **Opening a URI that is already open**: opening a URI MUST NOT re-read or replace the existing document's text, even if the new call's text differs from what is currently open.
- **Closing a URI that was never opened, or already fully closed**: closing a URI MUST be a no-op — it does not decrement below what an entry has, raise an error, or emit a closed event for a URI with no tracked entry.
- **Closing a document that is still dirty**: closing a URI performs no autosave, flush, or coordination with the save scheduler of any kind — the document store and the save scheduler hold no reference to each other; a caller that wants a dirty document's pending edits saved before it disappears MUST flush that URI's pending save itself first (see Design Decisions).
- **Dropping an observation token while its handler is mid-delivery**: dropping an observation token MUST serialize its teardown with any in-flight notification on the same execution context, so no separate synchronization is needed or provided.
- **A save write that suspends across an edit**: covered by `scheduler-markClean-version-guarded`; the document is never incorrectly marked clean, and the edit made during the suspension schedules its own follow-up save via the normal change-handler path, so it is not lost.
- **A write that keeps failing indefinitely**: the scheduler's underlying debounce-and-retry helper never gives up on a failing key — it re-arms at an exponentially growing interval capped at a fixed ceiling (30 seconds by default) rather than abandoning the entry, so flushing all pending saves at application termination can still find and report it.
- **Two concurrent flushes of the same pending URI**: flushing a single URI's pending save MUST NOT start a second write while one is already in flight for that key; the second caller awaits the first write's result instead.
- **Flushing all pending saves with nothing pending**: MUST complete without writing anything and MUST return an empty list.
- **A URL whose absolute string form differs from another URL naming the same file on disk** (e.g. a symlink, a trailing slash, or a differently-percent-encoded path): the URL-to-document-URI conversion performs no normalization of any kind; two such URLs produce two different `DocumentUri` strings, and reconciling them (if needed at all) is a concern of a layer outside this component, per its own narrower contract — see Design Decisions.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `uri` | `DocumentUri` (string) | none (required) | The document's identity throughout the text-document model, the document store, and the save scheduler; conventionally an LSP `file://` string produced by the URL-to-document-URI conversion. |
| `languageId` | string | none (required, document creation/open only) | Passed through and stored verbatim; nothing in this component validates or interprets it. |
| `text` | string | none (required, document creation/open only) | The document's initial content; a duplicate open call's text is ignored (see `store-open-first-caller-authoritative`). |
| `version` | integer | `0` | The text document's starting version; bumped by applying edits and by a full replace thereafter. |
| `debounce` | time interval | 1 second | The save scheduler's per-key quiet period before a pending save runs. |
| `write` | function (an injected, asynchronous persistence operation) | none (required) | The caller-injected persistence operation; the scheduler decides only *when* it runs, never *how*. |
| `maximumRetryInterval` | time interval (internal default) | 30 seconds | Ceiling on the exponential backoff applied after a failed write; not exposed as a construction parameter today — a caller cannot currently override it without constructing its own debounce-and-retry helper. |

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigable destination — `DocumentUri` is an LSP wire-format identifier, not a navigation link.

## Localization

Not applicable: this component produces no user-facing string. The one string literal it produces for display — the save scheduler's autosave-failure message — is a diagnostic log line, never shown to a user (see Logging).

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: this component declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: this component contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: the text document holds exactly the caller-supplied text for the file at its URI — in practice, the full content of whatever file a user has open in an editor pane, plus that file's path (as a `DocumentUri`). Neither the text document, the document store, nor the save scheduler inspects, parses, or interprets that content beyond UTF-16 offset bookkeeping.
- **Storage**: held only in memory (the document's own text, and the document store's open-documents map) for as long as the document stays open; the save scheduler writes it back to disk only through the caller-injected persistence operation, which this component does not implement — persistence, encryption, and location are entirely that operation's responsibility.
- **Transmission**: this component performs no network call of its own.
- **Retention**: a document's text and dirty state persist in memory until closing its URI removes the last open reference to it; a save that keeps failing leaves its bytes only in memory, retried in the background with no time limit, until it succeeds or is explicitly cancelled.

## Logging

Subsystem: the host application's bundle identifier | Category: the save scheduler

| Event | Level | Message |
|-------|-------|---------|
| An autosave write fails | error | `Auto-save failed for <uri>: <reason> — still pending, will retry` |

The text document, the document store, and the URL-to-document-URI conversion make no logging call of their own; only the save scheduler logs, and only on a failed write.

## Platform Notes

- **SwiftUI**: not a dependency of any of the four files — each imports only `Foundation` (plus `LanguageServerProtocol`, and `os` for the scheduler's logger). A SwiftUI editor view consumes `TextDocument`/`TextDocumentStore`/`TextDocumentSaveScheduler` through injected instances and its own `@State`/`@Observable` wiring around the change/dirty-state handler tokens, not through anything this component provides directly.
- **AppKit / UIKit**: this is the source. All four files live in `packages/apple/AgenticToolkit/Language/`, part of the `AgenticToolkitLanguage` framework target (`project.yml` declares `platform: macOS`, no iOS target today), depending on `AgenticToolkitCore`, `JSONRPC`, `LanguageServerProtocol`, and `LanguageClient`. None imports AppKit or UIKit, so the type is equally usable from the headless daemon process or a windowed host. `TextDocument`, `TextDocumentStore`, and `TextDocumentSaveScheduler` are each declared `@MainActor final class`, so the primary-execution-context confinement in the behavioral requirements above is Swift actor isolation, not a locking convention this repo built by hand; an observation token's teardown is an `isolated deinit`, which itself hops back onto the main actor before unregistering its handler. The save scheduler's injected write closure is typed `@MainActor (TextDocument) async throws -> Void`, and it wraps a generic `KeyedDebouncer<DocumentUri>` (`Core/Concurrency/KeyedDebouncer.swift`) for its debounce/retry bookkeeping. Its failure log line goes through `Loggable` conformance, with subsystem `Bundle.main.bundleIdentifier` and category `TextDocumentSaveScheduler`, using the `os` unified logging framework. In `apply(_:)`'s edit-reordering step, Swift's `sorted(by:)` uses a small-array insertion-sort fast path that happens to preserve a non-total-order comparator's original relative order below a size threshold; the "large, scrambled batch" edge case exists to exercise the general-purpose sort path beyond that threshold, where such preservation is not guaranteed by the standard library and must instead come from the documented descending-caller-index tiebreak.
- **Compose**: Kotlin's `String` is UTF-16-backed like Swift's, so the offset/position math (including the surrogate-pair and CRLF boundary rounding) ports with direct code-unit arithmetic over `CharSequence`, not a `codePoint`-aware API. Model the refcounted registry as a class holding a `MutableMap<String, Entry>` confined to a single `CoroutineDispatcher` (the direct analogue of `@MainActor`), and port the save scheduler/debounce-and-retry helper as a `Job`-per-key debounce (`launch { delay(debounceMs) }`) with the same generation-bump-on-reschedule and exponential-backoff-on-failure bookkeeping, since Kotlin coroutines offer no built-in debounce-with-retry primitive.
- **React/Web**: JavaScript strings are UTF-16 internally (`String.prototype.length`/`charCodeAt` already operate on UTF-16 code units), so the offset/position math ports almost unchanged. Model the debounced autosave with a `Map<uri, { timer, generation, failures }>` and `setTimeout`/`clearTimeout` in place of the native debounce-and-retry helper, and the refcounted store as a `Map<string, { document, openCount }>`; persistence goes through the File System Access API or a backend endpoint, wrapped in the same never-remove-on-failure retry loop.
- **WinUI 3**: .NET's `System.String` is also UTF-16 (`Length`/the string indexer are UTF-16 code units, matching Swift's `text.utf16`), so the offset/position conversion, including surrogate-pair and CRLF boundary rounding, ports with direct index arithmetic and no encoding translation. Model the document store's refcounted registry as a `Dictionary<string, Entry>` confined to the UI thread's `DispatcherQueue` (the closest analogue to `@MainActor`), and port the save scheduler/debounce-and-retry helper with a `DispatcherQueueTimer` or `Task.Delay`-based per-key debounce that keeps a failed key's entry — mirroring `retry-ceiling-default-and-floor`-style backoff — until a write via `System.IO.File.WriteAllTextAsync` succeeds or is explicitly cancelled.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Language/TextDocument.swift` |
| apple | `packages/apple/AgenticToolkit/Language/TextDocumentSaveScheduler.swift` |
| apple | `packages/apple/AgenticToolkit/Language/TextDocumentStore.swift` |
| apple | `packages/apple/AgenticToolkit/Language/URL+DocumentUri.swift` |

## Design Decisions

**Decision**: the save scheduler delegates all per-key debounce, retry, and backoff bookkeeping to a generic per-key debounce-and-retry helper (on Apple platforms, `KeyedDebouncer<DocumentUri>`) rather than implementing its own.
**Rationale**: per the Swift source's own doc comment, three prior copies of this exact pattern — a notes-saving scheduler, this component's own earlier shape, and a semantic-highlighting provider's one-shot variant — were "structurally identical and independently wrong in the same place": each removed a pending entry from its map before attempting the write and only logged on failure, so a write that hit a full disk or a revoked network volume silently lost the edit. Extracting the shared debounce-and-retry helper fixes that failure mode once for every caller instead of three times.
**Approved**: pending

**Decision**: opening a URI a second time ignores that call's text and language id, returning the already-open text document unchanged.
**Rationale**: the source's own doc comment states "the text already open is authoritative, not the text of a later open call" — favoring the in-memory buffer, which may already carry unsaved edits from one pane, over whatever a second opener happens to read from disk, rather than silently discarding the first pane's edits when a second pane opens the same file.
**Approved**: pending

**Decision**: the save scheduler marks a document clean only if its version is unchanged from the version captured immediately before the write began, rather than unconditionally after a successful write returns.
**Rationale**: the write runs asynchronously and can suspend, so the user can type between the snapshot and the write landing. Per the doc comment, marking clean unconditionally "would clear the dirty indicator over a buffer that is genuinely newer than the file"; declining does not lose the edit, because the text document's own change handler has already scheduled the next save for it. The cost is one extra debounce cycle in the rare case the user types during a write.
**Approved**: pending

**Decision**: the document store performs no coordination at all with the save scheduler — closing a URI neither flushes nor cancels any pending autosave for it.
**Rationale**: the two components hold no reference to each other anywhere in the given sources; each is independently injectable and independently testable. Wiring "close implies flush" is left to a caller — the sibling `file-editor-view` recipe documents its own call to flush a URI's pending save before discarding a pane's document — rather than being built into either lower-level component. Recorded here as an architectural boundary between "what is open" and "what is scheduled to be saved," not as a defect in either component.
**Approved**: pending

**Decision**: the URL-to-document-URI conversion returns the URL's absolute string form verbatim, with no normalization of symlinks, trailing slashes, or differing percent-encoding between two URLs that name the same file on disk.
**Rationale**: the extension's own doc comment states a narrower contract than full URL equivalence — it exists so "two independent call sites... agree on exactly this string for exactly the same file," i.e. so the *same* URL value converts consistently, not so that two *different* string representations of the same on-disk file converge to one `DocumentUri`. Any such normalization, where a caller needs it, happens at a different layer outside this component.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/language/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
