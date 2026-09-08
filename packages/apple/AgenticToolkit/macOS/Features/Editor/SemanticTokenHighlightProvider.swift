//
//  SemanticTokenHighlightProvider.swift
//  AgenticToolkit
//

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
    }

    // MARK: - HighlightProviding

    /// Called once, from `HighlightProviderState.init`, and again if the
    /// language changes.
    func setUp(textView: TextView, codeLanguage: CodeLanguage) {
        self.textView = textView
        // Started here rather than lazily on the first query because the first
        // query arrives immediately after this and would otherwise have nothing
        // to wait for.
        startFetch(afterDelay: nil)
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
            // Nothing is known and nothing is coming. Only reachable before
            // `setUp`, which the package always calls first.
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
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            self?.resolvePendingQuery(id: id)
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

        store(decode(response, legend: legend), stamp: stamp)
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
            // `StyledRangeContainer.applyHighlightResult` requires ascending,
            // non-overlapping ranges and silently *skips* anything that
            // overlaps what came before, which would shift every following run.
            // Enforced here rather than trusted: the ordering is the server's.
            guard range.location >= lastEnd else { continue }
            // Modifiers are dead end to end, in two independent places:
            // `TokenRepresentation.makeToken` hardcodes `modifiers: Set()` and
            // never reads the bitmask at `data[i + 4]`, and
            // `EditorTheme.mapCapture(_:)` ignores `CaptureModifierSet`
            // entirely. Decoding them would change no colour, weight or slant.
            result.append(HighlightRange(range: range, capture: capture, modifiers: []))
            lastEnd = range.upperBound
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
        // Belt and braces, and deliberately so: `decodeTokens` also `break`s at
        // the first token starting at or after the end of the range it is given,
        // and the range given above is the whole document — so today a token
        // past the end never reaches here. That is a fact about the *package's*
        // loop, not about this conversion, and it is the loop that would have to
        // keep being true for the clamp to stay harmless. This guard is what
        // makes the clamp harmless here instead.
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
        query.completion(.success(Self.clip(highlights ?? [], to: query.range)))
    }

    private func resolveAllPendingQueries() {
        // Taken and cleared before any completion runs: a completion can
        // re-enter this class, and an entry answered twice is the defect this
        // whole mechanism exists to prevent.
        let queries = pendingQueries
        pendingQueries = []
        for query in queries {
            query.completion(.success(Self.clip(highlights ?? [], to: query.range)))
        }
    }

    private func failPendingQueries() {
        let queries = pendingQueries
        pendingQueries = []
        for query in queries {
            query.completion(.failure(HighlightProvidingError.operationCancelled))
        }
    }
}
