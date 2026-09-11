//
//  SemanticTokenHighlightProvider.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import AgenticToolkitLanguage
import CodeEditLanguages
// `@preconcurrency`: `HighlightProviding`'s two callbacks are declared
// `@escaping @MainActor (Result<…>) -> Void`, and the package is not built in
// Swift 6 language mode, so those function types are not `@Sendable` there.
// This module is, which makes an identically-spelled `@MainActor` closure
// implicitly `@Sendable` here — a *stricter* type than the protocol requires,
// which is why the conformance is rejected rather than accepted. Nothing about
// the requirement is actually unsafe: every call is on the main actor. The
// attribute says so without weakening any checking this file does of its own
// state, which stays fully isolated to `@MainActor`.
@preconcurrency import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import os

/// Paints one document with `textDocument/semanticTokens/full`, on top of
/// tree-sitter.
///
/// One instance **per open document**, not per pane and not per project: every
/// `LSPRange` the server sends is resolved against one `TextDocument`, and that
/// document is the only authority in this codebase for offset↔`Position`
/// conversion. `FileEditorState.Slot` owns it, because
/// `HighlightProviderState.highlightProvider` is a `weak var` and something
/// outside the package has to hold it for as long as the editor is mounted.
///
/// **Order matters, and it is the opposite of what "layered over" suggests.**
/// This provider is handed to `SourceEditor` at index **0**, ahead of the
/// `TreeSitterClient`: `StyledRangeContainer` prioritises the *lower* provider
/// id, and an id is the provider's index in that array. Appended instead, it
/// would compile, run, send requests, and be invisible.
///
/// **The caching invariant, which everything below exists to hold:** *the token
/// data a query answers from is never older than the document version whose
/// edits the text view has already applied, and a superseded fetch never
/// overwrites data derived from newer information.* See `fetchClock`.
@MainActor
final class SemanticTokenHighlightProvider: HighlightProviding {

    /// How long after an edit to ask the server again.
    ///
    /// A full-document request on every keystroke is a request per keystroke —
    /// the server reparses the file each time and every answer but the last is
    /// thrown away. 300 ms is above a fast typist's inter-keystroke interval
    /// (~100-150 ms), so a burst of typing collapses to one request, and below
    /// the ~500 ms at which a pause stops feeling instant.
    static let defaultRefetchDebounce: Duration = .milliseconds(300)

    /// How long a query waits for token data before answering with none.
    ///
    /// Generous on purpose. A query that gives up answers `.success([])`, and
    /// the package then marks that range *valid* — and a provider outside the
    /// package cannot push an invalidation (`Highlighter.invalidate()` is only
    /// reachable through `TextViewController.highlighter`, which is internal),
    /// so the range is not asked about again until the next edit. Giving up
    /// early therefore costs a screen of highlighting until the user types. The
    /// ceiling exists only so a wedged server cannot leave the range pending
    /// forever, which blocks even the next edit's re-query.
    static let defaultQueryTimeout: Duration = .seconds(5)

    private let document: TextDocument
    private let registry: LanguageServerRegistry
    private let refetchDebounce: Duration
    private let queryTimeout: Duration

    /// Held weakly for the same reason the package holds it weakly: the text
    /// view owns the editor, not the other way round.
    private weak var textView: TextView?

    /// The highlights the last settled fetch produced, ascending and
    /// non-overlapping, in the text storage's own UTF-16 offsets.
    ///
    /// `nil` is not "none" — it is **not known yet**, and it is what makes a
    /// query wait rather than answer empty. A fetch that finds no server, no
    /// capability, or an error stores `[]`, which *is* settled: that document
    /// contributes nothing until it is edited.
    private var highlights: [HighlightRange]?

    /// Orders writes to `highlights` by the age of the information they came
    /// from, not by which continuation happens to resume first.
    ///
    /// The shape is `LSPCompletionDelegate`'s, deliberately: a stamp minted
    /// synchronously *before the first suspension*, recorded alongside the
    /// answer it produced, and a write admitted only when its stamp is at least
    /// the recorded one. Because the bar moves only inside the guarded write, a
    /// stamp nobody spends blocks nobody.
    ///
    /// A private clock rather than `TextDocument.version`: two fetches can
    /// easily be issued at the same version — the first fetch and a refetch
    /// after a cancelled debounce both are — and equal stamps under `>=` would
    /// let the older one land last. `version` also does not move when the
    /// *information* moved but the text did not.
    ///
    /// `applyEdit` advances the bar as well, with a stamp of its own. That is
    /// the half of the invariant about the document: an edit is newer
    /// information than any fetch begun before it, because those fetches
    /// describe text that has since moved, so every one of them is refused when
    /// it resumes.
    private var fetchClock = 0
    private var highlightsStamp = 0

    /// The fetch in flight, including its debounce delay. Cancelled and
    /// replaced by the next one; the stamps, not this, are what keep a
    /// cancelled-but-still-running fetch from writing.
    private var fetchTask: Task<Void, Never>?

    /// The stamp of the fetch `fetchTask` is running.
    ///
    /// Only `abandonFetch` reads it, and only to answer one question: *is the
    /// task I am about to drop still mine?* `highlightsStamp` cannot answer it
    /// — that bar moves only when a fetch writes, so it says nothing about
    /// which fetch is currently in flight — and without the distinction a
    /// fetch resuming with an unreadable response would drop the handle to a
    /// newer fetch that is about to answer correctly, turning that newer
    /// fetch's parked queries into permanent empties.
    private var fetchTaskStamp = 0

    /// Queries that arrived before there was anything to answer them with.
    ///
    /// A query **must** call its completion exactly once. Parking them here
    /// rather than awaiting inside `queryHighlightsFor` keeps every resolution
    /// synchronous on the main actor, so "exactly once" is enforced by removing
    /// the entry rather than by racing two paths that each want to call it.
    private var pendingQueries: [PendingQuery] = []
    private var queryClock = 0

    private struct PendingQuery {
        let id: Int
        let range: NSRange
        let completion: @MainActor (Result<[HighlightRange], Error>) -> Void
        /// The task that will answer this query if nothing else does.
        ///
        /// Held so that resolution can cancel it. Left running it would sleep
        /// out the full timeout after the query it guards has already been
        /// answered, and sustained typing issues a query per invalidation —
        /// so the steady-state count is the typing rate times five seconds, of
        /// tasks that exist only to find nothing and return.
        var timeout: Task<Void, Never>?
    }

    init(
        document: TextDocument,
        registry: LanguageServerRegistry,
        refetchDebounce: Duration = SemanticTokenHighlightProvider.defaultRefetchDebounce,
        queryTimeout: Duration = SemanticTokenHighlightProvider.defaultQueryTimeout
    ) {
        self.document = document
        self.registry = registry
        self.refetchDebounce = refetchDebounce
        self.queryTimeout = queryTimeout
    }

    // Isolated explicitly (SE-0371): a `@MainActor` class's `deinit` is
    // nonisolated by default, and `fetchTask` is main-actor state. The same
    // spelling `FileEditorState.deinit` uses, for the same reason.
    isolated deinit {
        fetchTask?.cancel()
        // Every parked query is *completed*, not merely un-timed-out. A query
        // whose completion is never called leaves its range in
        // `HighlightProviderState`'s `pendingSet` forever, and `getNextRange()`
        // subtracts that set — so if that state object outlives this provider,
        // as it does whenever the language changes rather than the pane
        // closing, the range is never asked about again by anybody.
        // Cancelling the timeouts alone is exactly that: it removes the one
        // thing that would have answered them.
        //
        // `failPendingQueries()` rather than a teardown of its own, because
        // `operationCancelled` is the one result the package retries, and
        // "retry" is the honest answer from an object that is going away
        // without having learned anything.
        failPendingQueries()
    }

    // MARK: - HighlightProviding

    /// Called once, from `HighlightProviderState.init`, and again if the
    /// language changes.
    ///
    /// Resets exactly as `applyEdit` does, and for the same reason stated the
    /// other way round: a second `setUp` is new information about *what this
    /// provider is describing*, so everything derived from the old answer is
    /// stale the moment it arrives. Without the reset, a query arriving inside
    /// the new fetch's round trip is answered from the previous language's
    /// tokens — settled, because any success moves the range into the package's
    /// `validSet` — and a fetch still in flight from before could still store
    /// over the new one.
    func setUp(textView: TextView, codeLanguage: CodeLanguage) {
        self.textView = textView
        // The stored ranges describe a document this provider is no longer
        // being asked about, and the bar is advanced past every fetch already
        // in flight so none of them can land as though it were current.
        highlights = nil
        fetchClock += 1
        highlightsStamp = fetchClock

        // Started here rather than lazily on the first query because the first
        // query arrives immediately after this and would otherwise have nothing
        // to wait for.
        startFetch(afterDelay: nil)

        // Empty on the first call, which is what makes this a no-op there.
        failPendingQueries()
    }

    func queryHighlightsFor(
        textView: TextView,
        range: NSRange,
        completion: @escaping @MainActor (Result<[HighlightRange], Error>) -> Void
    ) {
        if let highlights {
            completion(.success(Self.clip(highlights, to: range)))
            return
        }
        guard fetchTask != nil else {
            // Nothing is known and nothing is coming: either `setUp` has not
            // run yet — the package always calls it first, so that window is
            // narrow — or a fetch ended in a response we could not read a
            // single token of and dropped its handle on the way out (see
            // `abandonFetch`). Both are settled answers, and `[]` is the same
            // answer parking would have reached once the timeout expired.
            completion(.success([]))
            return
        }

        // Waited for rather than answered empty: this range is now in the
        // package's `pendingSet` and will be moved to its `validSet` the moment
        // we answer, and there is no channel by which we could ask for it back
        // (see `defaultQueryTimeout`). An empty answer here is an answer for
        // the life of the buffer.
        queryClock += 1
        let id = queryClock
        pendingQueries.append(PendingQuery(id: id, range: range, completion: completion))

        let timeout = queryTimeout
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            // Cancelled means the query was already answered and this entry is
            // gone; `resolvePendingQuery` would find nothing, but not waking
            // the main actor at all is the point of the cancellation.
            guard !Task.isCancelled else { return }
            self?.resolvePendingQuery(id: id)
        }
        // Recorded after the fact because the task needs the id and the entry
        // needs the task. Nothing can have removed the entry in between — the
        // task's first act is a sleep and this is the same synchronous
        // main-actor region — but if that ever stops being true, the entry is
        // gone and the task has nothing to guard.
        if let index = pendingQueries.firstIndex(where: { $0.id == id }) {
            pendingQueries[index].timeout = task
        } else {
            task.cancel()
        }
    }

    /// The only channel by which this provider can ask to be queried again.
    ///
    /// `Highlighter.invalidate()` is `public` but reachable only through
    /// `TextViewController.highlighter`, which is internal to the package — so
    /// the `IndexSet` returned here is it. The refetch is *not* awaited: doing
    /// that would put a server round trip inside the edit pipeline, on every
    /// keystroke.
    func applyEdit(
        textView: TextView,
        range: NSRange,
        delta: Int,
        completion: @escaping @MainActor (Result<IndexSet, Error>) -> Void
    ) {
        // The stored ranges describe text that has moved. Discarded rather than
        // adjusted — a shifted range is a guess about a file the server has not
        // seen — and the bar is advanced past every fetch already in flight, so
        // none of them can land as though it were current.
        highlights = nil
        fetchClock += 1
        highlightsStamp = fetchClock

        startFetch(afterDelay: refetchDebounce)

        // Every parked query was asked about pre-edit offsets, so its answer
        // would be applied to the wrong characters. `operationCancelled` is the
        // package's own word for exactly this, and it is the one case the
        // package retries: `HighlightProviderState` clears the range from its
        // pending set and invalidates it, which re-queries — and the re-query
        // parks again, against the fetch that is now on its way.
        failPendingQueries()

        // The whole document, not just the edited span. The stored ranges were
        // all discarded above, so every one of them is now a lie — including
        // the ones the edit did not touch, whose offsets moved with it.
        // `HighlightProviderState` intersects this with the visible set before
        // re-querying, so the cost is a screenful, not a file.
        completion(.success(IndexSet(integersIn: textView.documentRange)))
    }

    // MARK: - Test seams

    /// Awaits whatever fetch is in flight, including its debounce.
    ///
    /// A seam rather than a poll: these tests assert on what a *settled* fetch
    /// stored, and polling for it would turn a deadlock into a slow pass.
    func awaitPendingFetch() async {
        await fetchTask?.value
    }

    // MARK: - Fetching

    /// Replaces the fetch in flight with a new one, optionally after a delay.
    ///
    /// The stamp is minted here, synchronously, before the task exists — so it
    /// dates the moment this fetch was decided on, which is the age of the
    /// information it is about to read. The delay is inside the task rather
    /// than before this call so that a query parked during the debounce has
    /// something to await.
    private func startFetch(afterDelay delay: Duration?) {
        fetchTask?.cancel()
        fetchClock += 1
        let stamp = fetchClock
        fetchTaskStamp = stamp
        fetchTask = Task { @MainActor [weak self] in
            if let delay {
                // A cancelled sleep is the debounce doing its job: a newer edit
                // has already scheduled the fetch this one would have made.
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            await self.fetch(stamp: stamp)
        }
    }

    private func fetch(stamp: Int) async {
        guard let session = registry.session(forLanguageId: document.languageId) else {
            store([], stamp: stamp)
            return
        }
        // Joined, not initiated: the registry starts every session in a `Task`
        // of its own, and a session still initialising answers `capabilities()`
        // with `nil`. `start()` on a running session returns immediately.
        try? await session.start()

        guard let capabilities = await session.capabilities(),
              let legend = Self.fullRequestLegend(of: capabilities.semanticTokensProvider) else {
            // Either the handshake has not finished, or this server does not do
            // semantic tokens — or does them only as a delta or a range
            // request, neither of which this task implements. Settled as "no
            // highlights" either way, and no request is sent.
            store([], stamp: stamp)
            return
        }

        let response: SemanticTokensResponse
        do {
            response = try await session.semanticTokensFull(
                SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: document.uri))
            )
        } catch {
            store([], stamp: stamp)
            return
        }

        // The token array is untrusted input and `TokenRepresentation` trusts it
        // completely: `decodeTokens` strides by five and indexes `data[i + 1]`,
        // `data[i + 2]` and `data[i + 3]` with no bound check at all. A ragged
        // array — a truncated write, a proxy that split a frame, a server bug —
        // therefore does not produce bad colours, it traps, and the trap takes
        // the whole app down rather than this pane. Five values per token is the
        // wire format; a count that is not a multiple of five is not a response
        // we can read any part of, because we cannot know which part is missing.
        if let tokens = response, !tokens.data.count.isMultiple(of: 5) {
            Self.logger.error(
                """
                Language server \(session.name, privacy: .public) answered \
                semanticTokens/full with \(tokens.data.count, privacy: .public) values, \
                which is not a multiple of 5. Discarding the response.
                """
            )
            abandonFetch(stamp: stamp)
            return
        }

        store(decode(response, legend: legend), stamp: stamp)
    }

    /// Ends a fetch that produced nothing readable, **without** settling the
    /// document.
    ///
    /// Deliberately not `store([])`. An empty answer is a *settled* answer: the
    /// package moves the queried range into its `validSet` the moment the
    /// completion runs and, because nothing outside `CodeEditSourceEditor` can
    /// reach `Highlighter.invalidate()`, never asks about that range again. So
    /// claiming "no highlights here" on the strength of a response we could not
    /// read would paint that claim for the life of the buffer.
    /// `operationCancelled` is the one result the package retries, so parked
    /// queries are failed with it and their ranges go back to being invalid.
    ///
    /// `highlights` and `highlightsStamp` are left untouched: this fetch learned
    /// nothing, so it has no business moving a bar that would refuse a fetch
    /// that did. The guard reads the bar without moving it — the bar advances
    /// only on an actual write, which is what makes it mean "the newest answer
    /// anyone has recorded" rather than "the newest fetch anyone has run".
    ///
    /// Guarded on the stamp for the same reason `store(_:stamp:)` is, and it is
    /// the same rule stated for a failure instead of an answer: **a fetch may
    /// only act on state no newer fetch has claimed.** Without it, a slow fetch
    /// resuming with a ragged response fails whatever is parked *now* — which,
    /// after an edit, is a query belonging to a newer fetch that was about to
    /// answer it correctly. That self-heals, because `operationCancelled` is a
    /// retry rather than an answer, but it costs an invalidate-and-re-query
    /// round trip and it is the one place an answer derived from stale
    /// information would reach state a newer fetch owns.
    private func abandonFetch(stamp: Int) {
        guard stamp >= highlightsStamp else { return }
        // The handle goes **before** the queries are failed, not after,
        // because failing them re-enters this class synchronously:
        // `HighlightProviderState` answers `operationCancelled` by invalidating
        // the range, and `invalidate(_:)` calls `highlightInvalidRanges()`
        // straight through to `queryHighlightsFor` inside the completion.
        // Dropping the handle afterwards would hand that retry the exact state
        // this is removing — `highlights` nil, `fetchTask` non-nil — and it
        // would park for the full timeout.
        //
        // The handle goes at all because otherwise this provider is stalled
        // rather than settled: `highlights` is still `nil` and `fetchTask` is
        // still non-`nil`, which is precisely the state
        // `queryHighlightsFor` reads as "an answer is coming". Nothing is
        // coming — this fetch was the answer, and it is over — so every query
        // from here on parks for the full `queryTimeout` before being handed
        // the same `[]` the timeout would have produced anyway. Dropping the
        // handle makes that answer immediate.
        //
        // No re-fetch is armed. A server that answered once with an
        // unreadable frame will answer the same way again, and a provider that
        // retried on its own would loop against it for the life of the pane.
        // `applyEdit` and `setUp` both start a fresh fetch, so the next edit —
        // or the next language change — is the recovery, and that is the same
        // recovery this path has always had, minus the five-second wait in
        // front of every query until then.
        //
        // Guarded on the *task's* stamp rather than the write bar: a fetch
        // superseded while it was suspended must not drop its successor's
        // handle. `store(_:stamp:)` has no such guard and needs none — it is
        // already refused by `highlightsStamp` — but the bar this one moves is
        // a different bar.
        if stamp == fetchTaskStamp {
            fetchTask = nil
        }
        failPendingQueries()
    }

    /// Records a fetch's answer unless newer information has already landed,
    /// and hands the answer to every query still parked.
    ///
    /// The comparison and both writes are one synchronous statement on the main
    /// actor, so nothing interleaves between deciding to write and writing. A
    /// stamp is never issued twice, so `>=` admits only strictly newer
    /// information.
    private func store(_ newHighlights: [HighlightRange], stamp: Int) {
        guard stamp >= highlightsStamp else { return }
        highlights = newHighlights
        highlightsStamp = stamp
        resolveAllPendingQueries()
    }

    // MARK: - Decoding

    /// The legend to decode with, if this server answers `semanticTokens/full`
    /// at all.
    ///
    /// The capability is a `TwoTypeOption` of two structs that carry the same
    /// two fields, and `full` is itself a `TwoTypeOption` — a bare `false`
    /// there is a declaration that full requests are *not* served, which is not
    /// the same as omitting the key.
    private static func fullRequestLegend(
        of provider: TwoTypeOption<SemanticTokensOptions, SemanticTokensRegistrationOptions>?
    ) -> SemanticTokensLegend? {
        let legend: SemanticTokensLegend
        let full: SemanticTokensClientCapabilities.Requests.FullOption?
        switch provider {
        case .optionA(let options):
            legend = options.legend
            full = options.full
        case .optionB(let options):
            legend = options.legend
            full = options.full
        case nil:
            return nil
        }
        switch full {
        case .optionA(let serves):
            return serves ? legend : nil
        case .optionB:
            return legend
        case nil:
            return nil
        }
    }

    /// Turns one `semanticTokens/full` response into the highlights this
    /// provider will answer from until the next edit.
    ///
    /// Decoded through `TokenRepresentation`, which owns the relative-position
    /// encoding, and thrown away immediately: it is a mutable class with no
    /// `Sendable` conformance, and nothing here needs it to survive the call.
    private func decode(_ response: SemanticTokensResponse, legend: SemanticTokensLegend) -> [HighlightRange] {
        let representation = TokenRepresentation(legend: legend)
        _ = representation.applyResponse(response)

        let text = document.text as NSString
        let whole = document.range(for: NSRange(location: 0, length: text.length))

        var result: [HighlightRange] = []
        var lastEnd = 0
        var overlapping = 0
        for token in representation.decodeTokens(in: whole) {
            guard let capture = SemanticTokenCaptureMapping.captureName(forTokenType: token.tokenType) else {
                // Ruling AU: a token we have nothing to say about produces no
                // `HighlightRange` at all. An empty-capture range would in fact
                // also let tree-sitter's capture through — the merge is
                // `self.capture ?? other?.capture` — but reporting a range we
                // decline to describe is a claim we do not mean.
                continue
            }
            guard let range = nsRange(for: token.range) else { continue }
            // We declare `overlappingTokenSupport: false`, so a conforming
            // server does not send overlap and this never fires. It is kept
            // because a server is free to ignore what we declared, and
            // `StyledRangeContainer.applyHighlightResult` would then `continue`
            // past the overlapping run — dropping it just as silently, one layer
            // further from anyone who could diagnose it. Counted and logged
            // below rather than dropped without a word: a server sending what we
            // said we could not take is a fact worth being able to find.
            guard range.location >= lastEnd else {
                overlapping += 1
                continue
            }
            // Modifiers are dead end to end, in two independent places:
            // `TokenRepresentation.makeToken` hardcodes `modifiers: Set()` and
            // never reads the bitmask at `data[i + 4]`, and
            // `EditorTheme.mapCapture(_:)` ignores `CaptureModifierSet`
            // entirely. Decoding them would change no colour, weight or slant.
            result.append(HighlightRange(range: range, capture: capture, modifiers: []))
            lastEnd = range.upperBound
        }
        if overlapping > 0 {
            Self.logger.error(
                """
                Dropped \(overlapping, privacy: .public) overlapping semantic token(s) for \
                \(self.document.uri, privacy: .public); the client declares \
                overlappingTokenSupport: false.
                """
            )
        }
        return result
    }

    /// The text-storage range a token names, or `nil` if it names one this
    /// document does not have.
    ///
    /// Converted **only** through `TextDocument`, which is the single authority
    /// for offset↔`Position` in this codebase and the reason a file with an
    /// emoji, an accented character or CRLF line endings does not paint
    /// garbage: LSP counts in UTF-16 code units and so does that type, while a
    /// `String.Index` walk counts `Character`s and a byte offset counts neither.
    private func nsRange(for range: LSPRange) -> NSRange? {
        // `TextDocument`'s conversion clamps rather than failing — it has to,
        // because a server legitimately answers with a range from a version it
        // has and we no longer do. Clamping is right for a diagnostic, which
        // should still be shown somewhere; it is wrong for a highlight, which
        // would paint an unrelated span at the end of the file. So a token
        // naming a line this document does not have is dropped, detected by
        // round-tripping the line through the same conversion. `decodeTokens`
        // always ends a token on the line it started on, so the start line is
        // the whole question.
        //
        // **Unreachable by construction today, and kept anyway.** The proof is
        // three facts about the caller and the dependency, all of which have to
        // hold together: `decodeTokens` is handed a range derived from *this
        // document's current text* — `whole`, built from `document.text` in
        // `decode`; it `break`s at the first token whose start is at or after
        // that range's end; and a token's line is non-decreasing through that
        // loop, because `deltaLine` is a `UInt32`. So the first token naming a
        // line past the last one ends the loop, and no token after it can name
        // an earlier line. Nothing with an out-of-range line reaches this
        // function.
        //
        // Every one of those three is a fact about a package we do not own,
        // reached through a range this file chooses, so this guard is what makes
        // `TextDocument`'s clamping conversion harmless if any of them changes.
        //
        // **What would break fact 1 is not what it looks like.** Switching to a
        // `semanticTokens/range` request would *not*: `decodeTokens` bounds
        // tokens against whatever range it is given, so a sub-range of this
        // document bounds them at least as tightly as `whole` does. What breaks
        // it is handing that function a range which is not this document's
        // current text — a sentinel or unbounded range standing in for "no
        // limit", or a `whole` computed from a snapshot while this function
        // converts against the live document. Either way a token can name a line
        // the document does not have, and only this guard stands between
        // `TextDocument`'s clamp and a span of unrelated text painted at the end
        // of the file. It costs one round trip per token.
        // `tokensPastTheEndAreTruncatedByTheDecoder` pins the dependency half.
        let lineStart = document.utf16Offset(for: Position(line: range.start.line, character: 0))
        guard document.position(forUTF16Offset: lineStart).line == range.start.line else { return nil }

        let converted = document.nsRange(for: range)
        // A zero-length token paints nothing and would only cost the container
        // a run. Servers do emit them for a synthesised or zero-width symbol.
        return converted.length > 0 ? converted : nil
    }

    /// The stored highlights, clipped to one queried range.
    ///
    /// Clipping is not tidiness: `applyHighlightResult` lays the returned runs
    /// end to end inside `rangeToHighlight`, so a range extending past it
    /// corrupts every following run's offset.
    private static func clip(_ highlights: [HighlightRange], to range: NSRange) -> [HighlightRange] {
        highlights.compactMap { highlight in
            guard let clipped = highlight.range.intersection(range), clipped.length > 0 else { return nil }
            return HighlightRange(range: clipped, capture: highlight.capture, modifiers: highlight.modifiers)
        }
    }

    // MARK: - Parked queries

    /// Answers one parked query, if it is still parked.
    ///
    /// Removal by id is what makes "exactly once" true: whichever of the
    /// timeout and the fetch gets here first takes the entry, and the other
    /// finds nothing.
    private func resolvePendingQuery(id: Int) {
        guard let index = pendingQueries.firstIndex(where: { $0.id == id }) else { return }
        let query = pendingQueries.remove(at: index)
        query.timeout?.cancel()
        query.completion(.success(Self.clip(highlights ?? [], to: query.range)))
    }

    private func resolveAllPendingQueries() {
        // Taken and cleared before any completion runs: a completion can
        // re-enter this class, and an entry answered twice is the defect this
        // whole mechanism exists to prevent.
        let queries = pendingQueries
        pendingQueries = []
        for query in queries {
            query.timeout?.cancel()
            query.completion(.success(Self.clip(highlights ?? [], to: query.range)))
        }
    }

    private func failPendingQueries() {
        let queries = pendingQueries
        pendingQueries = []
        for query in queries {
            query.timeout?.cancel()
            query.completion(.failure(HighlightProvidingError.operationCancelled))
        }
    }
}

extension SemanticTokenHighlightProvider: Loggable {
    static nonisolated let logger = makeLogger()
}
