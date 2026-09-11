//
//  SemanticTokenHighlightProviderTests.swift
//  AgenticToolkit
//

import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitCore
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// What the semantic-token provider paints, and — more of the file than that —
/// what it does about time.
///
/// Almost every assertion here is about ordering rather than content, because
/// content is the easy half: a response arrives, it decodes, it paints. The
/// hard half is that a query **must** call its completion exactly once, that a
/// completion never called leaves the range in `HighlightProviderState`'s
/// `pendingSet` forever (and `getNextRange()` subtracts that set, so no re-query
/// is ever issued for it), and that a provider outside `CodeEditSourceEditor`
/// has no way to push an invalidation and ask again.
@Suite("Semantic token highlight provider")
@MainActor
struct SemanticTokenHighlightProviderTests {

    // MARK: - Fixtures

    /// The legend every test here uses unless it is testing the legend itself.
    ///
    /// Small and *not* in the order `SemanticTokenTypes` declares them: a token
    /// carries an index into this array, so a provider that ignored the legend
    /// and assumed the standard order would still pass a test whose legend
    /// happened to match it.
    private static let legend = SemanticTokensLegend(
        tokenTypes: ["comment", "function", "type", "parameter"],
        tokenModifiers: []
    )

    /// One entry of the relative-delta wire encoding, in source order.
    private struct WireToken {
        let deltaLine: Int
        let deltaStartChar: Int
        let length: Int
        let typeIndex: Int
    }

    private static func makeTokens(_ tokens: [WireToken]) -> SemanticTokens {
        SemanticTokens(data: tokens.flatMap {
            [UInt32($0.deltaLine), UInt32($0.deltaStartChar), UInt32($0.length), UInt32($0.typeIndex), 0]
        })
    }

    /// A provider wired to a fake server, its text view, and the fake itself.
    ///
    /// The text view is a real `TextViewController`'s, holding the same text as
    /// the document: `queryHighlightsFor` and `applyEdit` are handed one by the
    /// package, and `applyEdit` asks it for `documentRange`.
    @MainActor
    private struct Harness {
        let provider: SemanticTokenHighlightProvider
        let controller: TextViewController
        let fixture: LSPEditorFixture
        let session: FakeEditorLanguageServerSession
        let document: TextDocument

        var textView: TextView { controller.textView }

        /// How many `semanticTokensFull` requests the server has received.
        var requestCount: Int {
            fixture.log.events.filter { $0.hasPrefix("semanticTokensFull(") }.count
        }
    }

    private func makeHarness(
        text: String,
        capabilities: ServerCapabilities?,
        response: SemanticTokensResponse = nil,
        error: LanguageServerSessionError? = nil,
        refetchDebounce: Duration = .zero,
        queryTimeout: Duration = .seconds(5)
    ) async throws -> Harness {
        ensureEditorLanguageResourcesLocated()
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: capabilities,
                semanticTokensResponse: response,
                semanticTokensError: error
            )
        )
        let session = try await fixture.startedSession()
        let document = makeEditorDocument(text: text)
        let provider = SemanticTokenHighlightProvider(
            document: document,
            registry: fixture.registry,
            refetchDebounce: refetchDebounce,
            queryTimeout: queryTimeout
        )
        return Harness(
            provider: provider,
            controller: makeEditorTextViewController(text: text),
            fixture: fixture,
            session: session,
            document: document
        )
    }

    /// Yields until `condition` holds, or gives up.
    ///
    /// A poll rather than a continuation because what is being waited for is a
    /// request *arriving inside an actor on another executor* — there is no
    /// handle to await, and the alternative is a fixed sleep that is either
    /// flaky or slow. Bounded so a regression fails the test rather than hanging
    /// the suite.
    private func waitUntil(
        _ description: String,
        _ condition: () async -> Bool
    ) async throws {
        // `for _ in 0..<400 where await !condition()` reads like this and is
        // not: `where` is a filter on the iteration, not a break, so the loop
        // runs all four hundred times and sleeps through most of them long
        // after the condition became true.
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        // One last look: the final sleep may have been the one the condition
        // was waiting on.
        try #require(await condition(), "timed out waiting for: \(description)")
    }

    /// Runs one query and returns what its completion was called with, asserting
    /// it was called exactly once.
    private func query(
        _ harness: Harness,
        range: NSRange? = nil
    ) throws -> [HighlightRange] {
        var results: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(
            textView: harness.textView,
            range: range ?? harness.textView.documentRange
        ) { results.append($0) }
        try #require(results.count == 1, "expected exactly one completion call, got \(results.count)")
        return try results[0].get()
    }

    // MARK: - Decoding and conversion

    @Test("a single-line token at a legend index becomes the range it names")
    func singleLineTokenBecomesItsRange() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            // `value`, at line 0 character 4, five units long, legend index 3
            // (`parameter`).
            response: Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        let highlights = try query(harness)
        #expect(highlights.count == 1)
        #expect(highlights.first?.range == NSRange(location: 4, length: 5))
        #expect(highlights.first?.capture == .parameter)
        // F3: modifiers are dead in two independent places downstream, so this
        // is `[]` on purpose rather than by omission.
        #expect(highlights.first?.modifiers == [])
    }

    /// ★ The test that fails if any offset conversion happens outside
    /// `TextDocument`.
    ///
    /// LSP counts in UTF-16 code units. `"🐕"` is two of them and one
    /// `Character`; `"é"` written as e + combining acute is two code units and
    /// one `Character` as well. A `String.Index` walk would put the token two
    /// units early, a byte offset four, and both would still land *inside* the
    /// line — which is exactly why this is worth a test rather than a reading.
    @Test("a token after a multi-byte character lands where a human would point")
    func multiByteCharactersConvertThroughTheDocument() async throws {
        // Counted the way a server counts: "let " is 4 UTF-16 units, "🐕" is 2,
        // " = " is 3 — so `name` begins at 9 and runs 4. A `Character` walk
        // would say 8 and paint "= nam"; the assertion below is what a human
        // pointing at the word would draw.
        let text = "let 🐕 = name\n"
        #expect((text as NSString).substring(with: NSRange(location: 9, length: 4)) == "name")

        let harness = try await makeHarness(
            text: text,
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 9, length: 4, typeIndex: 1)])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        let highlights = try query(harness)
        #expect(highlights.count == 1)
        #expect(highlights.first?.range == NSRange(location: 9, length: 4))
        #expect(highlights.first?.capture == .function)
    }

    /// What this pins is `TokenRepresentation`'s truncation, not our own line
    /// guard — and the name says so because the distinction decides what a
    /// failure here means.
    ///
    /// `decodeTokens` is handed the whole-document range and `break`s at the
    /// first token whose start is at or past its end, so the out-of-range token
    /// below never reaches `nsRange(for:)` at all. The guard on that line is
    /// unreachable by construction today (see its comment) and this test does
    /// not cover it; what it does cover is the dependency's behaviour, which we
    /// do not own and which a package bump could change to clamping. Clamping
    /// would paint a span of text that has nothing to do with the symbol, and
    /// this is where that would be caught.
    @Test("the decoder truncates at the end of the document and the earlier tokens still arrive")
    func tokensPastTheEndAreTruncatedByTheDecoder() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([
                WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3),
                // Line 50 of a two-line file.
                WireToken(deltaLine: 50, deltaStartChar: 0, length: 3, typeIndex: 2)
            ])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        let highlights = try query(harness)
        #expect(highlights.count == 1)
        #expect(highlights.first?.range == NSRange(location: 4, length: 5))
    }

    @Test("a legend index past the end of the legend produces no token and shifts nothing")
    func outOfRangeLegendIndexProducesNoToken() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([
                // Index 9 into a four-entry legend. The token is dropped whole;
                // what matters is that the *next* one still decodes at its own
                // offsets rather than inheriting this one's.
                WireToken(deltaLine: 0, deltaStartChar: 0, length: 3, typeIndex: 9),
                WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)
            ])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        let highlights = try query(harness)
        #expect(highlights.count == 1)
        #expect(highlights.first?.range == NSRange(location: 4, length: 5))
        #expect(highlights.first?.capture == .parameter)
    }

    // MARK: - Provider behaviour

    @Test("a server that does not advertise semantic tokens is never asked, and the query answers empty")
    func noCapabilityMeansNoRequest() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            // A server that answers completions and nothing else — the ordinary
            // case, not an exotic one.
            capabilities: makeCompletingCapabilities()
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        #expect(try query(harness).isEmpty)
        #expect(harness.requestCount == 0)
    }

    @Test("a server that advertises semantic tokens has its tokens painted")
    func advertisedCapabilityIsQueriedAndPainted() async throws {
        let harness = try await makeHarness(
            text: "func run(value: Int) {}\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([
                WireToken(deltaLine: 0, deltaStartChar: 5, length: 3, typeIndex: 1),
                WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3),
                WireToken(deltaLine: 0, deltaStartChar: 7, length: 3, typeIndex: 2)
            ])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        let highlights = try query(harness)
        #expect(harness.requestCount == 1)
        #expect(highlights.map(\.range) == [
            NSRange(location: 5, length: 3),
            NSRange(location: 9, length: 5),
            NSRange(location: 16, length: 3)
        ])
        #expect(highlights.map(\.capture) == [.function, .parameter, .type])
    }

    /// ★ The test that fails if a query that cannot be answered yet answers
    /// empty and hopes to be asked again.
    ///
    /// It will not be asked again. The package moves the range from `pendingSet`
    /// to `validSet` the moment the completion runs, and nothing outside
    /// `CodeEditSourceEditor` can reach `Highlighter.invalidate()` to move it
    /// back. An empty answer here is an answer for the life of the buffer.
    @Test("a query issued before the first fetch resolves is answered once, with the fetched data")
    func queryBeforeTheFirstFetchIsAnsweredWithRealData() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)])
        )
        await harness.session.holdNextSemanticTokens(1)

        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the first request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        var results: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(
            textView: harness.textView,
            range: harness.textView.documentRange
        ) { results.append($0) }
        // Nothing yet: the point of the whole parked-query mechanism.
        #expect(results.isEmpty)

        await harness.session.releaseHeldSemanticTokens()
        await harness.provider.awaitPendingFetch()

        try #require(results.count == 1, "expected exactly one completion call, got \(results.count)")
        let highlights = try results[0].get()
        #expect(highlights.map(\.range) == [NSRange(location: 4, length: 5)])
    }

    /// ★ The ordering guard, exercised the only way it can be: with two fetches
    /// carrying different data, resolved out of order.
    ///
    /// The stamp is minted synchronously before the first suspension, recorded
    /// with the answer, and admitted only when it is at least the recorded one —
    /// `LSPCompletionDelegate`'s shape, for the same reason. Delete the guard and
    /// the *older* server answer is what the editor paints, on text that has
    /// since been edited.
    @Test("a superseded fetch released late does not overwrite newer data")
    func supersededFetchDoesNotOverwriteNewerData() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend)
        )
        await harness.session.enqueueSemanticTokensResponses([
            // The stale answer: `let`, at offset 0.
            Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 0, length: 3, typeIndex: 2)]),
            // The current one: `value`, at offset 4.
            Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)])
        ])
        await harness.session.holdNextSemanticTokens(1)

        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the first request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        // An edit supersedes the held fetch and schedules its own. The parked
        // first fetch is still inside the server call at this point.
        var editCompletions = 0
        harness.provider.applyEdit(
            textView: harness.textView,
            range: NSRange(location: 0, length: 0),
            delta: 0
        ) { _ in editCompletions += 1 }
        #expect(editCompletions == 1)

        // Deterministic, not a poll: `applyEdit` replaced the in-flight fetch
        // synchronously, so this awaits the *second* one to completion.
        await harness.provider.awaitPendingFetch()
        #expect(try query(harness).map(\.range) == [NSRange(location: 4, length: 5)])

        // Now let the stale one finish. It carries the older stamp, so it is
        // refused rather than applied.
        await harness.session.releaseHeldSemanticTokens()
        // A fixed wait, unusually, because the assertion is an *absence*: the
        // stale fetch's task was cancelled and replaced, so there is no handle
        // left to await, and there is no state that changes when it declines to
        // write. This is long enough for an actor resume plus a main-actor hop
        // by orders of magnitude.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(try query(harness).map(\.range) == [NSRange(location: 4, length: 5)])
    }

    @Test("applyEdit answers without waiting for the refetch")
    func applyEditDoesNotWaitForTheRefetch() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)])
        )
        await harness.session.holdNextSemanticTokens(1)
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the first request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        var invalidated: IndexSet?
        harness.provider.applyEdit(
            textView: harness.textView,
            range: NSRange(location: 4, length: 0),
            delta: 0
        ) { invalidated = try? $0.get() }

        // Answered while the server is still holding a response: a refetch
        // awaited here would be a server round trip on the keystroke path.
        #expect(await harness.session.heldSemanticTokensCount == 1)
        // The whole document, because every stored offset moved with the edit —
        // not only the edited span.
        #expect(invalidated == IndexSet(integersIn: harness.textView.documentRange))

        await harness.session.releaseHeldSemanticTokens()
    }

    @Test("two edits in quick succession collapse to one refetch")
    func rapidEditsCollapseToOneRefetch() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)]),
            // Long enough that two synchronous edits are unambiguously inside
            // one window, short enough not to pad the suite.
            refetchDebounce: .milliseconds(120)
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()
        #expect(harness.requestCount == 1)

        for _ in 0..<2 {
            harness.provider.applyEdit(
                textView: harness.textView,
                range: NSRange(location: 4, length: 0),
                delta: 0
            ) { _ in }
        }
        await harness.provider.awaitPendingFetch()

        // One more than the fetch `setUp` made, not two: a full-document request
        // per keystroke is a reparse per keystroke, and every answer but the
        // last is thrown away.
        #expect(harness.requestCount == 2)
    }

    @Test("a query whose fetch never answers is still completed exactly once")
    func aQueryThatIsNeverAnsweredStillCompletes() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)]),
            queryTimeout: .milliseconds(50)
        )
        await harness.session.holdNextSemanticTokens(1)
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the first request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        var results: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(
            textView: harness.textView,
            range: harness.textView.documentRange
        ) { results.append($0) }

        try await waitUntil("the parked query to time out") { results.count == 1 }
        #expect(try results[0].get().isEmpty)

        // And releasing the wedged request afterwards must not answer it a
        // second time — the entry is gone, taken by whichever path reached it
        // first.
        await harness.session.releaseHeldSemanticTokens()
        await harness.provider.awaitPendingFetch()
        await Task.yield()
        #expect(results.count == 1)
    }

    /// ★ The test that fails, by crashing the whole test runner, if the token
    /// array is handed to the decoder unvalidated.
    ///
    /// `TokenRepresentation.decodeTokens` strides by five and indexes
    /// `data[i + 3]` with no bound check, so seven values is not "one and a bit
    /// tokens", it is an out-of-bounds read on the second stride — a trap, in
    /// the app, not an error in this pane. A truncated write, a proxy that split
    /// a frame, or a server bug is all it takes.
    ///
    /// The second half of the assertion matters as much as the first: the query
    /// must fail with `operationCancelled` rather than succeed with `[]`.
    /// `HighlightProviderState` marks a range valid on *any* success and only
    /// re-invalidates on that one error, so an empty answer here would claim
    /// "there is nothing to paint in this document" for the life of the buffer
    /// on the strength of a response we could not read a single token of.
    @Test("a token array whose count is not a multiple of five is refused rather than decoded")
    func aRaggedTokenArrayIsRefusedRatherThanDecoded() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            // One whole token (`value`, legend index 3) and two stray values.
            // Enough to prove the response is refused as a unit: there is no
            // knowing *which* five-tuple lost values, so the readable-looking
            // prefix is not readable either.
            response: SemanticTokens(data: [0, 4, 5, 3, 0, 0, 4])
        )
        await harness.session.holdNextSemanticTokens(1)

        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the first request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        // Parked before the malformed answer lands, so this is the query the
        // failure has to reach.
        var results: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(
            textView: harness.textView,
            range: harness.textView.documentRange
        ) { results.append($0) }
        #expect(results.isEmpty)

        await harness.session.releaseHeldSemanticTokens()
        await harness.provider.awaitPendingFetch()

        try #require(results.count == 1, "expected exactly one completion call, got \(results.count)")
        guard case .failure(let error) = results[0] else {
            Issue.record(
                """
                the query succeeded; any success marks the range permanently valid, which is the one \
                thing a response we could not read a single token of must not do
                """
            )
            return
        }
        // Matched rather than compared: `HighlightProvidingError` is not
        // `Equatable`, and it is the *identity* of this case that matters —
        // `operationCancelled` is the only result `HighlightProviderState`
        // re-invalidates and re-queries on.
        guard case .operationCancelled? = error as? HighlightProvidingError else {
            Issue.record("expected HighlightProvidingError.operationCancelled, got \(error)")
            return
        }
    }

    /// ★ The stamp guard on the *failure* path — the one terminus of
    /// `fetch(stamp:)` that used to skip it.
    ///
    /// Every other ending writes through `store(_:stamp:)` and its
    /// `guard stamp >= highlightsStamp`. `abandonFetch(stamp:)` writes nothing,
    /// which is why it looked exempt — but it still reaches shared state: it
    /// fails every parked query. After an edit those queries belong to the fetch
    /// the edit started, not to the one still sitting inside a server call, so an
    /// unguarded abandon lets a stale fetch cancel an answer a newer fetch is
    /// about to give correctly.
    ///
    /// Self-healing but not free. `operationCancelled` is the one result
    /// `HighlightProviderState` re-invalidates and re-queries on, so the range
    /// does come back — after an invalidate-and-re-query round trip, and after a
    /// frame in which the text is painted by tree-sitter alone.
    @Test("a superseded fetch that abandons does not cancel a newer fetch's parked query")
    func anAbandonedFetchDoesNotCancelANewerFetchsParkedQuery() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend)
        )
        // The fake picks a response when the call *arrives*, before it parks, so
        // these belong to the fetches in start order however they resume: the
        // ragged one to the fetch already in flight, the readable one to the
        // fetch the edit is about to start.
        await harness.session.enqueueSemanticTokensResponses([
            SemanticTokens(data: [0, 4, 5, 3, 0, 0, 4]),
            Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)])
        ])
        await harness.session.holdNextSemanticTokens(2)

        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the first request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        // Moves the bar past the in-flight fetch and starts its own.
        harness.provider.applyEdit(
            textView: harness.textView,
            range: NSRange(location: 0, length: 0),
            delta: 0
        ) { _ in }
        try await waitUntil("the second request to reach the server") {
            await harness.session.heldSemanticTokensCount == 2
        }

        // Parked with both fetches inside the server call, so it belongs to the
        // second one — `applyEdit` failed everything that was parked before it.
        var results: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(
            textView: harness.textView,
            range: harness.textView.documentRange
        ) { results.append($0) }
        #expect(results.isEmpty)

        // Released together, in arrival order, so the superseded fetch resumes
        // first and gets its chance to fail the query before the newer one
        // answers it. That ordering is what makes this a test rather than a
        // coin toss: remove the guard and the first resume wins.
        await harness.session.releaseHeldSemanticTokens()
        await harness.provider.awaitPendingFetch()

        try #require(results.count == 1, "expected exactly one completion call, got \(results.count)")
        guard case .success(let highlights) = results[0] else {
            Issue.record(
                """
                the parked query was cancelled by the superseded fetch; it belongs to the fetch the \
                edit started, which was holding a readable answer for it
                """
            )
            return
        }
        #expect(highlights.map(\.range) == [NSRange(location: 4, length: 5)])
    }

    @Test("a server error settles as no highlights rather than leaving the query parked")
    func aServerErrorSettlesAsNoHighlights() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            error: .notRunning
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        #expect(try query(harness).isEmpty)
    }

    @Test("a server that advertises semantic tokens but refuses full requests is never asked")
    func fullFalseMeansNoRequest() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            // A bare `false` is a declaration that full-document requests are
            // not served, which is not the same as omitting the key — and the
            // full request is the only one this provider makes.
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend, full: false)
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        #expect(try query(harness).isEmpty)
        #expect(harness.requestCount == 0)
    }

    @Test("a query is answered clipped to the range it asked about")
    func answersAreClippedToTheQueriedRange() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: Self.makeTokens([
                WireToken(deltaLine: 0, deltaStartChar: 0, length: 3, typeIndex: 2),
                WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)
            ])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        // `StyledRangeContainer.applyHighlightResult` lays the returned runs end
        // to end *inside* the range it asked about, so a run reaching past it
        // corrupts every following run's offset.
        let highlights = try query(harness, range: NSRange(location: 6, length: 4))
        #expect(highlights.map(\.range) == [NSRange(location: 6, length: 3)])
    }

    // MARK: - Lifecycle resets (F27, F28, F31)

    /// ★ F27. What it catches: a provider that abandons a fetch and then has no
    /// way back — `highlights` still `nil` and `fetchTask` still non-`nil`, so
    /// every query after the unreadable response parks for the full
    /// `queryTimeout` before being answered with the same `[]` it could have
    /// been answered with at once.
    ///
    /// The eventual answer is deliberately unchanged by the fix: a response we
    /// could not read a single token of settles as "no semantic highlights" and
    /// tree-sitter paints the pane. What changes is that the user does not wait
    /// five seconds per range to be told so, and that the only recovery is no
    /// longer "type something", which a reader never does.
    ///
    /// `query(_:range:)` is the assertion: it requires the completion to have
    /// run before it returns, so a parked query fails this test rather than
    /// slowing it down.
    @Test("a query after an unreadable response is answered at once rather than parked for the timeout")
    func aQueryAfterAnAbandonedFetchIsAnsweredAtOnce() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            // One whole token and two stray values — the ragged array that
            // `fetch(stamp:)` refuses as a unit.
            response: SemanticTokens(data: [0, 4, 5, 3, 0, 0, 4])
        )
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()

        let highlights = try query(harness)
        #expect(highlights.isEmpty)
        // And the abandon did not turn into a retry loop against a server that
        // just proved it cannot be read.
        #expect(harness.requestCount == 1)
    }

    /// ★ F27, re-entrantly. What it catches: the same stall one step further
    /// on. `abandonFetch` fails the parked queries, and
    /// `HighlightProviderState` answers `operationCancelled` by invalidating
    /// the range and re-querying **synchronously, from inside the completion**
    /// — so a provider that drops its fetch handle *after* failing the queries
    /// hands the retry the very state the fix exists to remove, and the retry
    /// parks for the full timeout.
    ///
    /// Written as a re-query issued from inside the failure completion because
    /// that is exactly the package's own control flow (`invalidate(_:)` →
    /// `highlightInvalidRanges()` → `queryHighlightsFor`), and nothing else
    /// reproduces the ordering.
    @Test("a query re-issued from inside the cancellation is answered at once, not parked again")
    func aReQueryFromInsideTheCancellationIsAnsweredAtOnce() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
            response: SemanticTokens(data: [0, 4, 5, 3, 0, 0, 4])
        )
        await harness.session.holdNextSemanticTokens(1)
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        // Parked while the ragged response is still inside the server, which is
        // the only way to be holding a query when `abandonFetch` runs.
        let range = harness.textView.documentRange
        var reQueryResults: [Result<[HighlightRange], Error>] = []
        var firstResults: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(textView: harness.textView, range: range) { result in
            firstResults.append(result)
            // What `HighlightProviderState` does with `operationCancelled`,
            // synchronously, right here.
            harness.provider.queryHighlightsFor(textView: harness.textView, range: range) {
                reQueryResults.append($0)
            }
        }
        #expect(firstResults.isEmpty)

        await harness.session.releaseHeldSemanticTokens()
        await harness.provider.awaitPendingFetch()

        try #require(firstResults.count == 1)
        #expect(throws: HighlightProvidingError.operationCancelled) { try firstResults[0].get() }
        try #require(reQueryResults.count == 1, "the retry parked instead of being answered")
        #expect(try reQueryResults[0].get().isEmpty)
    }

    /// ★ F28. What it catches: `setUp` starting a fetch without discarding what
    /// the last one stored. `setUp` runs again on a language change, and the
    /// tokens already in hand describe the text that was there before it — so a
    /// query arriving inside the round trip is answered from an array keyed to
    /// a document that is no longer on screen.
    ///
    /// Asserted as "the query waits", not as "the query is empty": the point is
    /// that the provider has nothing to say until the new fetch answers, and an
    /// empty answer would be a settled one (`HighlightProviderState` marks the
    /// range valid on any success and never asks again).
    @Test("a second setUp does not answer from the tokens the first one fetched")
    func setUpDiscardsThePreviousTokens() async throws {
        let harness = try await makeHarness(
            text: "let value = 1\n",
            capabilities: makeSemanticTokenCapabilities(legend: Self.legend)
        )
        await harness.session.enqueueSemanticTokensResponses([
            Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)]),
            Self.makeTokens([WireToken(deltaLine: 0, deltaStartChar: 0, length: 3, typeIndex: 1)])
        ])

        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        await harness.provider.awaitPendingFetch()
        let firstAnswer = try query(harness)
        #expect(firstAnswer.map(\.range) == [NSRange(location: 4, length: 5)])

        // The second setup's request is held inside the server, which is the
        // whole window this defect lives in.
        await harness.session.holdNextSemanticTokens(1)
        harness.provider.setUp(textView: harness.textView, codeLanguage: .default)
        try await waitUntil("the second request to reach the server") {
            await harness.session.heldSemanticTokensCount == 1
        }

        var results: [Result<[HighlightRange], Error>] = []
        harness.provider.queryHighlightsFor(
            textView: harness.textView,
            range: harness.textView.documentRange
        ) { results.append($0) }
        #expect(results.isEmpty, "the query was answered from the previous setup's tokens")

        await harness.session.releaseHeldSemanticTokens()
        await harness.provider.awaitPendingFetch()

        try #require(results.count == 1, "expected exactly one completion call, got \(results.count)")
        #expect(try results[0].get().map(\.range) == [NSRange(location: 0, length: 3)])
    }

    /// ★ F31. What it catches: a `deinit` that cancels the timeout which would
    /// have answered a parked query and then drops the query with it. A
    /// completion never called leaves its range in `HighlightProviderState`'s
    /// `pendingSet`, and `getNextRange()` subtracts that set — so if that state
    /// object outlives the provider, the range is never queried again.
    ///
    /// The setup is contrived in one respect only, and it has to be: a fetch
    /// suspended *inside* the server call holds `self` in its own frame, so the
    /// provider cannot be released while one is in flight. A fetch still
    /// sleeping out its debounce holds nothing — `[weak self]` is resolved
    /// after the sleep — which is the state this drives to.
    @Test("a provider released with a query parked completes it rather than dropping it")
    func releasingTheProviderCompletesParkedQueries() async throws {
        ensureEditorLanguageResourcesLocated()
        let text = "let value = 1\n"
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeSemanticTokenCapabilities(legend: Self.legend),
                semanticTokensResponse: Self.makeTokens([
                    WireToken(deltaLine: 0, deltaStartChar: 4, length: 5, typeIndex: 3)
                ])
            )
        )
        _ = try await fixture.startedSession()
        let controller = makeEditorTextViewController(text: text)
        var provider: SemanticTokenHighlightProvider? = SemanticTokenHighlightProvider(
            document: makeEditorDocument(text: text),
            registry: fixture.registry,
            refetchDebounce: .seconds(60),
            queryTimeout: .seconds(60)
        )

        provider?.setUp(textView: controller.textView, codeLanguage: .default)
        await provider?.awaitPendingFetch()
        // Discards the fetched tokens and arms a refetch that will still be
        // sleeping when the provider goes away.
        provider?.applyEdit(
            textView: controller.textView,
            range: NSRange(location: 0, length: 0),
            delta: 0
        ) { _ in }

        var results: [Result<[HighlightRange], Error>] = []
        provider?.queryHighlightsFor(
            textView: controller.textView,
            range: controller.textView.documentRange
        ) { results.append($0) }
        #expect(results.isEmpty)

        provider = nil
        // `isolated deinit` runs synchronously when the last release happens on
        // the actor it is isolated to, which is where this test is — but the
        // assertion is written as a wait so that a runtime that hops instead
        // reports the real defect rather than a timing artefact.
        try await waitUntil("the parked query to be completed on teardown") { results.count == 1 }

        try #require(results.count == 1, "the parked query was dropped rather than completed")
        guard case .failure(let error) = results[0] else {
            Issue.record(
                """
                the parked query succeeded on teardown; any success marks the range permanently valid, \
                and this provider never had an answer to give
                """
            )
            return
        }
        // `operationCancelled` is the one result `HighlightProviderState`
        // re-invalidates and re-queries on, which is what a teardown owes a
        // query it cannot answer.
        guard case .operationCancelled? = error as? HighlightProvidingError else {
            Issue.record("expected HighlightProvidingError.operationCancelled, got \(error)")
            return
        }
    }
}
