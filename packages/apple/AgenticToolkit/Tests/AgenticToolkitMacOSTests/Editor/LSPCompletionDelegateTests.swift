//
//  LSPCompletionDelegateTests.swift
//  AgenticToolkit
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// The bridge between `CodeEditSourceEditor`'s completion window and a language
/// server.
///
/// Every test here drives the delegate through the protocol methods the package
/// actually calls, with a real `TextViewController` and a real `TextDocument`,
/// because the defects this code can have are all conversion defects: an offset
/// read from the wrong half of a `CursorPosition`, a replacement range computed
/// against the wrong text, a snippet inserted with its markup intact.
@Suite("LSPCompletionDelegate")
@MainActor
struct LSPCompletionDelegateTests {

    // MARK: - Fixtures

    /// `let x = prin`, with the caret at the end of `prin` (offset 12).
    ///
    /// The identifier starts at offset 8, which is the anchor every cached-set
    /// assertion below is written against.
    private static let sampleText = "let x = prin"
    private static let caretOffset = 12
    private static let identifierStart = 8

    private func makeDelegate(
        document: TextDocument,
        fixture: LSPEditorFixture
    ) -> LSPCompletionDelegate {
        LSPCompletionDelegate(document: document, registry: fixture.registry)
    }

    private func items(_ labels: [String]) -> CompletionResponse {
        .optionA(labels.map { CompletionItem(label: $0) })
    }

    // MARK: - 7. No session

    @Test("a request with no server for the document's language returns nil")
    func noSessionReturnsNil() async throws {
        let fixture = LSPEditorFixture(registersConfiguration: false)
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let result = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )

        #expect(result == nil)
        // Nothing was sent, either: a registry with no session must not be
        // reached through some other path.
        #expect(fixture.log.events.isEmpty)
    }

    // MARK: - 8. No completion capability

    @Test("a request to a server that advertises no completionProvider returns nil")
    func noCompletionProviderReturnsNil() async throws {
        // A server that does definitions but not completion — the realistic
        // shape of this case, not an empty capabilities object.
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeDefiningCapabilities(),
                completionResponse: items(["print"])
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let result = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )

        #expect(result == nil)
        // The gate is the point: no `textDocument/completion` was sent to a
        // server that said it does not answer them.
        #expect(!fixture.log.events.contains("completion"))
    }

    // MARK: - 9. Entries, in the server's order

    @Test("entries come back in the server's order, with the server's labels")
    func returnsEntriesInServerOrder() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: items(["print", "println", "abs"])
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let result = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))

        // Server order, not sorted: the server has already ranked them, and
        // re-sorting here would throw that ranking away.
        #expect(result.items.map(\.label) == ["print", "println", "abs"])
        // The window is anchored at the start of the token being completed, so
        // it stays put as the user keeps typing.
        #expect(result.windowPosition.range.location == Self.identifierStart)
    }

    // MARK: - 10. Position conversion

    @Test("the request's position is the one the document computes for the caret offset")
    func sendsTheDocumentsOwnPosition() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: items(["alpha"])
            )
        )
        let session = try await fixture.startedSession()
        // Two lines, so a delegate that forgot about lines entirely would send
        // a character offset and fail here.
        let text = "let alpha = 1\nlet beta = al"
        let offset = (text as NSString).length
        let document = makeEditorDocument(text: text)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: text)

        _ = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: offset)
        )

        let params = try #require(await session.lastCompletionParams)
        // Asserted against the document's own converter, so writing a second
        // offset -> Position conversion anywhere in the delegate fails here
        // even if that second one happens to agree today.
        #expect(params.position == document.position(forUTF16Offset: offset))
        #expect(params.position == Position(line: 1, character: 13))
        #expect(params.textDocument.uri == document.uri)
    }

    // MARK: - 11. Filtering the cached set

    @Test("the cached set is filtered by what has been typed, and dropped once the caret leaves it")
    func filtersCachedEntries() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: items(["print", "println", "abs"])
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        _ = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))

        // `prin` is what lies between the anchor (8) and the caret (12).
        let filtered = try #require(delegate.completionOnCursorMove(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))
        #expect(filtered.map(\.label) == ["print", "println"])

        // Before the anchor the cache describes a different token, so it does
        // not apply — and the window has to close rather than show stale rows.
        let outside = delegate.completionOnCursorMove(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 4)
        )
        #expect(outside == nil)
    }

    // MARK: - 12. Applying a completion

    @Test("an item with a textEdit replaces exactly the edit's range")
    func appliesTextEditRange() async throws {
        // The edit deliberately names a range that is *not* the token under the
        // caret: a delegate that ignored `textEdit` and used the identifier
        // prefix would replace `prin` instead of `x`.
        let edit = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 4), end: Position(line: 0, character: 5)),
            newText: "y"
        )
        let item = CompletionItem(label: "y", textEdit: .optionA(edit))
        let controller = try await applyFirstItem(response: .optionA([item]), cursorPosition: nil)

        #expect(controller.textView.string == "let y = prin")
    }

    @Test("an item with only insertText replaces the token under the caret with it")
    func appliesInsertText() async throws {
        let item = CompletionItem(label: "print", insertText: "printed")
        let controller = try await applyFirstItem(response: .optionA([item]), cursorPosition: nil)

        #expect(controller.textView.string == "let x = printed")
    }

    @Test("an entry of a foreign type is left alone, and does not crash")
    func ignoresForeignEntry() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(capabilities: makeCompletingCapabilities())
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        delegate.completionWindowApplyCompletion(
            item: ForeignSuggestionEntry(),
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )

        #expect(controller.textView.string == Self.sampleText)
    }

    // MARK: - 13. Snippets

    @Test("a snippet item inserts plain text with its placeholder syntax removed")
    func appliesSnippetAsPlainText() async throws {
        let item = CompletionItem(
            label: "print",
            insertText: "print(${1:items})$0",
            insertTextFormat: .snippet
        )
        let controller = try await applyFirstItem(response: .optionA([item]), cursorPosition: nil)

        // Placeholder defaults kept, bare tabstops dropped, no `${…}` markup
        // left in the buffer. Tabstop navigation is a deliberate omission.
        #expect(controller.textView.string == "let x = print(items)")
    }

    // MARK: - 16. A caret that moved while the window was open

    @Test("a completion applied after the user kept typing swallows what was typed")
    func replacesThroughTheLiveCaret() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: .optionA([CompletionItem(label: "print", insertText: "print")])
            )
        )
        _ = try await fixture.startedSession()

        // The request is made after `pr`…
        let atRequest = "let x = pr"
        let document = makeEditorDocument(text: atRequest)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: atRequest)

        let result = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 10)
        ))

        // …and the user types `in` while the window is open, in both the buffer
        // and the model that mirrors it.
        controller.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: "in")
        document.replaceAll(with: "let x = prin")

        let entry = try #require(result.items.first)
        delegate.completionWindowApplyCompletion(
            item: entry,
            textView: controller,
            cursorPosition: makeCursor(atOffset: 12)
        )

        // A delegate that trusted the request-time range alone would leave
        // `let x = printin`.
        #expect(controller.textView.string == "let x = print")
    }

    // MARK: - Fix round 1, finding 1: trigger characters

    @Test("the server's trigger characters are resolved without a completion request having been made")
    func resolvesTriggerCharactersEagerly() async throws {
        // Deliberately not sourcekit-lsp's `.`, `(`, `:`: a hardcoded default
        // would pass a test written against the common answer and be wrong for
        // every other server, which is the whole reason the set is asked for.
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"])
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)

        #expect(delegate.completionTriggerCharacters().isEmpty)

        let resolved = await delegate.resolveTriggerCharacters()

        #expect(resolved == ["@", "#"])
        #expect(delegate.completionTriggerCharacters() == ["@", "#"])
        // Resolved from the handshake, not by asking for completions: the
        // request path is only reached once the window is already open.
        #expect(!fixture.log.events.contains("completion"))
    }

    @Test("a server that advertises no completionProvider resolves to no trigger characters")
    func resolvesNoTriggerCharactersWithoutACompletionProvider() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(capabilities: makeDefiningCapabilities())
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)

        #expect(await delegate.resolveTriggerCharacters().isEmpty)
    }

    // MARK: - Fix round 3, item 1: overlapping trigger resolutions

    @Test("a superseded trigger resolution cannot overwrite a newer one's answer")
    func supersededTriggerResolutionCannotClobberNewerAnswer() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"])
            )
        )
        let session = try await fixture.startedSession()
        // The older resolution's answer, then the newer one's. Two answers
        // rather than one because a clobber is only observable when the stale
        // write differs — the reachable shape is a server disabled and quickly
        // re-enabled, where the second session's answer is the current one.
        await session.enqueueCapabilities([
            makeCompletingCapabilities(triggerCharacters: ["@"]),
            makeCompletingCapabilities(triggerCharacters: ["#"])
        ])
        await session.holdNextCapabilities(1)

        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)

        // Parked inside the server, exactly as the `$sessions` sink leaves a
        // resolution when a second publication arrives before the first
        // returns. Its continuation still runs: neither await in
        // `resolveTriggerCharacters` is a cancellation point.
        let older = Task { @MainActor in await delegate.resolveTriggerCharacters() }
        try await waitForParkedCapabilityCall(on: session)

        let newer = await delegate.resolveTriggerCharacters()
        #expect(newer == ["#"])
        #expect(delegate.completionTriggerCharacters() == ["#"])

        await session.releaseHeldCapabilities()
        let staleAnswer = await older.value

        // Without the generation guard the older continuation's unconditional
        // write lands here and both of these are `["@"]` — the trigger set the
        // retired server declared, cached as the current one and published to
        // the editor by whoever called the superseded resolution.
        #expect(delegate.completionTriggerCharacters() == ["#"])
        #expect(staleAnswer == ["#"])
    }

    // MARK: - Fix round 4: a resolution overtaken by a request that writes nothing

    @Test("a trigger resolution suspended across a request that returns early still lands its answer")
    func suspendedResolutionSurvivesAnEarlyReturningRequest() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"])
            )
        )
        let session = try await fixture.startedSession()
        // The resolution reads the real capabilities and parks inside the
        // server. The request that overtakes it meets the *second* queued
        // answer — a server that has not finished its handshake — which is one
        // of the two early returns that write nothing.
        await session.enqueueCapabilities([
            makeCompletingCapabilities(triggerCharacters: ["@", "#"]),
            nil
        ])
        await session.holdNextCapabilities(1)

        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let resolution = Task { @MainActor in await delegate.resolveTriggerCharacters() }
        try await waitForParkedCapabilityCall(on: session)

        // The user types while the resolution is still in flight. The request
        // returns nil without ever sending `textDocument/completion`.
        let request = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )
        #expect(request == nil)
        #expect(!fixture.log.events.contains("completion"))

        await session.releaseHeldCapabilities()
        let resolved = await resolution.value

        // The cache is the assertion that matters: a call that wrote nothing
        // must not have starved the one that had an answer. Order overlapping
        // calls by a claimed generation instead and the request's unused claim
        // makes this empty — the editor is handed no trigger characters at all,
        // nothing re-asks, and `.` silently stops opening the window.
        #expect(delegate.completionTriggerCharacters() == ["@", "#"])
        // Deliberately not the discriminator: the refusal branch's fallback
        // hands a superseded caller its own set back when the cache is empty,
        // so this reads correctly even when the cache did not get written.
        #expect(resolved == ["@", "#"])
    }

    // MARK: - Task 3.7: a dead server keeps its trigger characters

    /// What Task 3.7 fixes: the cache hit at the top of
    /// `resolveTriggerCharacters()` used to ask only "is this still the same
    /// session object?" A session that dies without being replaced is still
    /// that same object — `LanguageServerRegistry.reconcile`'s retire loop
    /// only reacts to a changed descriptor, never to a session's own outcome —
    /// so the stale, once-correct set kept coming back forever.
    @Test("a failed session's cached trigger characters are dropped, not merely bypassed once")
    func failedSessionDropsCachedTriggerCharacters() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"])
            )
        )
        let session = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)

        let resolved = await delegate.resolveTriggerCharacters()
        #expect(resolved == ["@", "#"])

        await session.transition(to: .failed(LanguageServerFailure(
            error: LanguageServerSessionError.serverExited(status: 1),
            standardErrorText: "error: crashed\n"
        )))
        await waitForRegistryToRecordFailure(of: session, in: fixture)

        // The same session object still serves this document — nothing
        // retires it — so a cache keyed only on identity would still hit here
        // and hand back `["@", "#"]`.
        let resolvedAfterFailure = await delegate.resolveTriggerCharacters()
        #expect(resolvedAfterFailure.isEmpty)
        // Not merely bypassed for this one call: `completionTriggerCharacters()`
        // reads the same stored cache, so a stale set surviving anywhere would
        // show up here too.
        #expect(delegate.completionTriggerCharacters().isEmpty)
    }

    // MARK: - Fix round 1, finding 2: overlapping requests

    @Test("a superseded request cannot wipe the cache a newer one published")
    func supersededRequestCannotWipeNewerCache() async throws {
        // The older request answers with nothing — what a one-character prefix
        // on a cold index usually produces, and the response that sends the
        // delegate down its `clearCache` path.
        let overlap = try await startOverlappingRequests(
            olderResponse: items([]),
            newerResponse: items(["print", "println"])
        )
        _ = await overlap.older.value

        let cached = try #require(overlap.delegate.completionOnCursorMove(
            textView: overlap.controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))
        // Without a request generation the older continuation's `clearCache()`
        // runs here and this is `nil` — the window closing under the user's
        // hands as they type.
        #expect(cached.map(\.label) == ["print", "println"])
    }

    @Test("a superseded request cannot overwrite the cache a newer one published")
    func supersededRequestCannotOverwriteNewerCache() async throws {
        let overlap = try await startOverlappingRequests(
            olderResponse: items(["stale"]),
            newerResponse: items(["print", "println"])
        )
        _ = await overlap.older.value

        let cached = try #require(overlap.delegate.completionOnCursorMove(
            textView: overlap.controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))
        // The older set is anchored at an older caret, so its entries would be
        // filtered against a prefix they were never requested for.
        #expect(cached.map(\.label) == ["print", "println"])
    }

    // MARK: - Fix round 1, finding 4: the request throws

    @Test("a completion request that throws returns nil and leaves nothing cached")
    func thrownRequestReturnsNil() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: items(["print"]),
                completionError: .notRunning
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let result = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )

        // `nil`, never an empty item list: an empty window swallows the user's
        // Return key instead of closing.
        #expect(result == nil)
        // The request really was sent — this is the error path, not the gate.
        #expect(fixture.log.events.contains("completion"))
        #expect(delegate.completionOnCursorMove(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ) == nil)
    }

    // MARK: - Fix round 1, finding 6: a textEdit range through a live caret

    @Test("a server-supplied textEdit range is extended forward to the live caret")
    func appliesTextEditRangeThroughTheLiveCaret() async throws {
        // sourcekit-lsp answers member completions this way: a `textEdit` whose
        // range starts before the caret, replacing the partial token.
        let edit = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 8), end: Position(line: 0, character: 10)),
            newText: "print"
        )
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: .optionA([CompletionItem(label: "print", textEdit: .optionA(edit))])
            )
        )
        _ = try await fixture.startedSession()

        let atRequest = "let x = pr"
        let document = makeEditorDocument(text: atRequest)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: atRequest)

        let result = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 10)
        ))

        // The user keeps typing while the window is open.
        controller.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: "in")
        document.replaceAll(with: "let x = prin")

        delegate.completionWindowApplyCompletion(
            item: try #require(result.items.first),
            textView: controller,
            cursorPosition: makeCursor(atOffset: 12)
        )

        // The replacement has to run from the edit's own start (8) through the
        // live caret (12). Honouring the edit's end alone leaves `printin`;
        // swapping the operands of the `max` leaves the same.
        #expect(controller.textView.string == "let x = print")
    }

    // MARK: - F12: additionalTextEdits

    /// ★ F12. What it catches: an item's `additionalTextEdits` being read off
    /// the wire, carried all the way to the apply, and then never written.
    ///
    /// This is the finding's whole point, so the assertion is on the buffer
    /// rather than on a field being read: an import a completion promised and
    /// did not add leaves code that does not compile, and the user has no way
    /// to know the completion was supposed to add it.
    @Test("a completion's additionalTextEdits land in the buffer alongside the insertion")
    func appliesAdditionalTextEdits() async throws {
        let item = CompletionItem(
            label: "print",
            insertText: "print",
            additionalTextEdits: [
                TextEdit(
                    range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0)),
                    newText: "import Foo\n"
                )
            ]
        )
        let applied = try await applyFirstItem(
            text: Self.sampleText,
            caretOffset: Self.caretOffset,
            response: .optionA([item])
        )

        #expect(applied.controller.textView.string == "import Foo\nlet x = print")
    }

    /// ★ F12, the co-located half. An additional edit whose insertion point is
    /// exactly the start of the range the completion itself replaces is *not* a
    /// conflict — LSP forbids overlap, and an insert at a boundary overlaps
    /// nothing — but it is the one arrangement where "back to front" is not
    /// enough on its own. Both edits start at the same offset, so the tiebreak
    /// decides, and the wrong one splices the insert in first and then lets the
    /// replacement eat the front of it.
    ///
    /// The rule the tiebreak encodes: at equal offsets the *replacement* goes
    /// first, because a zero-length splice at that offset is still valid
    /// afterwards while a replacement's range is not.
    @Test("an additional edit at the very start of the replaced range lands in front of it")
    func appliesAnAdditionalEditColocatedWithTheInsertion() async throws {
        let item = CompletionItem(
            label: "print",
            insertText: "print",
            additionalTextEdits: [
                TextEdit(
                    range: LSPRange(start: Position(line: 0, character: 8), end: Position(line: 0, character: 8)),
                    newText: "/*x*/"
                )
            ]
        )
        let applied = try await applyFirstItem(
            text: Self.sampleText,
            caretOffset: Self.caretOffset,
            response: .optionA([item])
        )

        #expect(applied.controller.textView.string == "let x = /*x*/print")
    }

    /// ★ F12, the ordering half. Every edit in the set names a range in the
    /// *pre-edit* document — that is what LSP guarantees and the only thing a
    /// server can promise — so applying them front-to-back makes every later
    /// range wrong by the length delta of every earlier one.
    ///
    /// Written across two lines with an insert above the insertion point and a
    /// replacement below it, because that is the arrangement an "add the import
    /// and fix the call" completion actually produces, and it is the one where
    /// ascending order silently lands in the wrong place instead of trapping.
    @Test("additional edits are applied back-to-front so each range still means what the server meant")
    func appliesAdditionalTextEditsBackToFront() async throws {
        let text = "let x = prin\nlet y = 0\n"
        let item = CompletionItem(
            label: "print",
            insertText: "print",
            additionalTextEdits: [
                // Ascending on purpose: the delegate must not depend on the
                // server having sorted them, and the spec does not require it.
                TextEdit(
                    range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0)),
                    newText: "import Foo\n"
                ),
                TextEdit(
                    range: LSPRange(start: Position(line: 1, character: 8), end: Position(line: 1, character: 9)),
                    newText: "42"
                )
            ]
        )
        let applied = try await applyFirstItem(
            text: text,
            caretOffset: 12,
            response: .optionA([item])
        )

        // Front-to-back would put the `42` one character late — inside
        // `"let y = 0"` rather than over the `0` — and the eleven characters of
        // the import would have moved it ten further still.
        #expect(applied.controller.textView.string == "import Foo\nlet x = print\nlet y = 42\n")
    }

    /// ★ F12, the malformed-server half. LSP requires additional edits to
    /// overlap neither the main edit nor each other; a server that breaks that
    /// hands us two writes to the same characters, and applying both produces
    /// text neither edit describes.
    ///
    /// Dropped rather than applied, and dropped rather than the whole item
    /// refused: the primary insertion is what the user chose and it is still
    /// well-defined on its own.
    @Test("an additional edit overlapping the insertion is dropped rather than doubled")
    func dropsAdditionalTextEditsThatOverlapTheInsertion() async throws {
        let item = CompletionItem(
            label: "print",
            insertText: "print",
            additionalTextEdits: [
                // Over `in` — inside the `prin` the insertion itself replaces.
                TextEdit(
                    range: LSPRange(start: Position(line: 0, character: 10), end: Position(line: 0, character: 12)),
                    newText: "XX"
                )
            ]
        )
        let applied = try await applyFirstItem(
            text: Self.sampleText,
            caretOffset: Self.caretOffset,
            response: .optionA([item])
        )

        #expect(applied.controller.textView.string == "let x = print")
    }

    /// ★ F12, the undo half. Two `replaceCharacters` calls are two mutations,
    /// and `CEUndoManager` groups by adjacency — an import at offset 0 and an
    /// insertion at offset 8 are not adjacent, so they land in two groups and
    /// one ⌘Z leaves the import behind without the call that needed it.
    ///
    /// `undoCount` is the assertion because it is the one observable that says
    /// how many times the user has to press the key.
    @Test("a completion with additional edits is one undo step, not two")
    func additionalTextEditsAreOneUndoStep() async throws {
        let item = CompletionItem(
            label: "print",
            insertText: "print",
            additionalTextEdits: [
                TextEdit(
                    range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0)),
                    newText: "import Foo\n"
                )
            ]
        )
        // The harness controller has no undo manager at all — `TextView`'s is
        // installed by `TextViewController` only when it builds its own view
        // hierarchy — so one is supplied here.
        let undoManager = CEUndoManager()
        let applied = try await applyFirstItem(
            text: Self.sampleText,
            caretOffset: Self.caretOffset,
            response: .optionA([item]),
            undoManager: undoManager
        )

        #expect(applied.controller.textView.string == "import Foo\nlet x = print")
        #expect(undoManager.undoCount == 1)
    }

    // MARK: - F13: CompletionList.isIncomplete

    /// ★ F13. What it catches: `isIncomplete` being thrown away by
    /// `response?.items`.
    ///
    /// An incomplete list is the server saying "this is what I could compute in
    /// the time I had — ask me again when you know more". Filtering it locally
    /// instead narrows a set that was never complete, so the item the user is
    /// typing towards is missing and stays missing no matter how much more they
    /// type.
    ///
    /// `nil` from `completionOnCursorMove` is the re-request: the package's
    /// `cursorsUpdated(..., presentIfNot: true)` closes the window on `nil` and
    /// immediately calls `showCompletions` again, which is the only channel
    /// this delegate has for asking the server a second time.
    @Test("an incomplete list is re-requested rather than filtered locally")
    func anIncompleteListIsReRequested() async throws {
        let text = "let x = print"
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(capabilities: makeCompletingCapabilities())
        )
        let session = try await fixture.startedSession()
        await session.enqueueCompletionResponses([
            .optionB(CompletionList(isIncomplete: true, items: [CompletionItem(label: "print")])),
            .optionA([CompletionItem(label: "print"), CompletionItem(label: "printerName")])
        ])
        let document = makeEditorDocument(text: text)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: text)

        _ = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 12)
        ))

        // One more character typed. A complete list would be filtered here —
        // test 11 asserts exactly that — and an incomplete one must not be.
        let moved = delegate.completionOnCursorMove(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 13)
        )
        #expect(moved == nil, "an incomplete list was filtered locally instead of being re-requested")

        // And the re-request says *why* it is being made, which is what lets a
        // server compute the narrowed set rather than repeat the truncated one.
        _ = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 13)
        )
        #expect(await session.lastCompletionParams?.context?.triggerKind == .triggerForIncompleteCompletions)
    }

    @Test("a complete list is filtered locally rather than re-requested")
    func aCompleteListIsFilteredLocally() async throws {
        let text = "let x = print"
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: .optionB(
                    CompletionList(isIncomplete: false, items: [CompletionItem(label: "print")])
                )
            )
        )
        let session = try await fixture.startedSession()
        let document = makeEditorDocument(text: text)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: text)

        _ = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 12)
        ))
        let moved = delegate.completionOnCursorMove(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 13)
        )
        #expect(moved?.map(\.label) == ["print"])

        // Nothing about a complete list makes the *next* request an
        // incomplete-completions refresh.
        _ = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: 13)
        )
        #expect(await session.lastCompletionParams?.context?.triggerKind == .invoked)
    }

    // MARK: - F30: the request's triggerKind

    /// ★ F30. What it catches: `triggerKind: .invoked` hardcoded, so every
    /// request claims the user pressed the completion key.
    ///
    /// `.` after an expression is the case that matters: sourcekit-lsp and
    /// clangd both use the context to decide between "members of this type" and
    /// "everything in scope", and an `.invoked` claim asks for the second when
    /// the user typed the first.
    @Test("a request made after a trigger character says so, and says which character")
    func sendsTheTriggerCharacterContext() async throws {
        let text = "let x = foo."
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: [".", ":"]),
                completionResponse: items(["bar"])
            )
        )
        let session = try await fixture.startedSession()
        let document = makeEditorDocument(text: text)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: text)

        _ = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: (text as NSString).length)
        )

        let context = try #require(await session.lastCompletionParams?.context)
        #expect(context.triggerKind == .triggerCharacter)
        #expect(context.triggerCharacter == ".")
    }

    @Test("a request made mid-identifier is invoked, with no trigger character")
    func sendsTheInvokedContextMidIdentifier() async throws {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: [".", ":"]),
                completionResponse: items(["print"])
            )
        )
        let session = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        _ = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )

        let context = try #require(await session.lastCompletionParams?.context)
        // `n` is not a trigger character, and `.` being *in* the set must not
        // be enough to claim one was typed.
        #expect(context.triggerKind == .invoked)
        #expect(context.triggerCharacter == nil)
    }

    /// A character the *server* did not declare is not a trigger character,
    /// however punctuation-shaped it looks. The set is per-server for a reason.
    @Test("a character the server did not declare is not treated as a trigger")
    func anUndeclaredCharacterIsNotATrigger() async throws {
        let text = "let x = foo;"
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["."]),
                completionResponse: items(["bar"])
            )
        )
        let session = try await fixture.startedSession()
        let document = makeEditorDocument(text: text)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: text)

        _ = await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: (text as NSString).length)
        )

        let context = try #require(await session.lastCompletionParams?.context)
        #expect(context.triggerKind == .invoked)
        #expect(context.triggerCharacter == nil)
    }

    // MARK: - Shared driver

    /// Runs one full request/apply cycle against `Self.sampleText` and returns
    /// the controller so the caller can assert on the buffer.
    ///
    /// The entries are the delegate's own, produced by a real request, rather
    /// than hand-built: the replacement range it uses is computed during that
    /// request and carried on the entry, so building the entry in the test
    /// would test the test.
    private func applyFirstItem(
        response: CompletionResponse,
        cursorPosition: CursorPosition?
    ) async throws -> TextViewController {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: response
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let result = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))
        let entry = try #require(result.items.first)
        delegate.completionWindowApplyCompletion(
            item: entry,
            textView: controller,
            cursorPosition: cursorPosition
        )
        return controller
    }

    /// What one request-and-apply cycle leaves behind.
    private struct AppliedCompletion {
        let controller: TextViewController
        let delegate: LSPCompletionDelegate
        let document: TextDocument
    }

    /// The same cycle as `applyFirstItem(response:cursorPosition:)`, over text
    /// the test chooses.
    ///
    /// A second driver rather than more parameters on the first: every existing
    /// caller of that one is written against `sampleText` and its two derived
    /// offsets, and threading them through would put the fixture's own
    /// constants into thirty call sites that do not care about them.
    private func applyFirstItem(
        text: String,
        caretOffset: Int,
        response: CompletionResponse,
        undoManager: CEUndoManager? = nil
    ) async throws -> AppliedCompletion {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: response
            )
        )
        _ = try await fixture.startedSession()
        let document = makeEditorDocument(text: text)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: text)
        if let undoManager {
            controller.textView.setUndoManager(undoManager)
        }

        let result = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: caretOffset)
        ))
        delegate.completionWindowApplyCompletion(
            item: try #require(result.items.first),
            textView: controller,
            cursorPosition: nil
        )
        return AppliedCompletion(controller: controller, delegate: delegate, document: document)
    }

    // MARK: - Overlapping-request driver

    /// What `startOverlappingRequests` hands back: the delegate both requests
    /// were made against, the controller they were made through, and the older
    /// request's task, already released and only needing to be awaited.
    private struct OverlappingRequests {
        let delegate: LSPCompletionDelegate
        let controller: TextViewController
        let older: Task<Void, Never>
    }

    /// Starts a completion request, parks it inside the server, runs a second
    /// one to completion, and releases the parked one.
    ///
    /// The interleaving is the point, and it is not reachable by awaiting two
    /// requests in turn: `SuggestionViewModel` cancels the previous request's
    /// task but only checks cancellation *after* the delegate call returns, so
    /// an abandoned request's continuation always runs — which is what makes an
    /// unguarded write from it reach the cache.
    private func startOverlappingRequests(
        olderResponse: CompletionResponse,
        newerResponse: CompletionResponse
    ) async throws -> OverlappingRequests {
        let fixture = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(capabilities: makeCompletingCapabilities())
        )
        let session = try await fixture.startedSession()
        await session.enqueueCompletionResponses([olderResponse, newerResponse])
        await session.holdNextCompletions(1)

        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = makeDelegate(document: document, fixture: fixture)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        // The older request, made one keystroke earlier than the newer one.
        let older = Task { @MainActor in
            _ = await delegate.completionSuggestionsRequested(
                textView: controller,
                cursorPosition: makeCursor(atOffset: Self.caretOffset - 1)
            )
        }
        try await waitForParkedRequest(on: session)

        let newer = try #require(await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        ))
        #expect(!newer.items.isEmpty)

        await session.releaseHeldCompletions()
        return OverlappingRequests(delegate: delegate, controller: controller, older: older)
    }

    /// Waits until the older request has actually reached the server, so the
    /// two requests are genuinely overlapping rather than accidentally ordered.
    private func waitForParkedRequest(on session: FakeEditorLanguageServerSession) async throws {
        for _ in 0..<500 {
            if await session.heldCompletionCount > 0 { return }
            try await Task.sleep(for: .milliseconds(4))
        }
        Issue.record("the first completion request never reached the server")
    }

    /// The same, for a parked `capabilities()` call.
    private func waitForParkedCapabilityCall(on session: FakeEditorLanguageServerSession) async throws {
        for _ in 0..<500 {
            if await session.heldCapabilityCount > 0 { return }
            try await Task.sleep(for: .milliseconds(4))
        }
        Issue.record("the first trigger resolution never reached the server")
    }

    /// Waits until the registry's per-session reader has recorded a session's
    /// transition to `.failed`.
    ///
    /// `LanguageServerRegistry.observeState(of:id:)` consumes
    /// `session.stateChanges` off the actor that yields it, so a read of
    /// `registry.sessionStates` immediately after `transition(to:)` can still
    /// see the state from before the transition.
    private func waitForRegistryToRecordFailure(
        of session: FakeEditorLanguageServerSession,
        in fixture: LSPEditorFixture
    ) async {
        for _ in 0..<500 {
            if case .failed = fixture.registry.sessionStates[session.id] { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
        Issue.record("the registry never recorded the session's failure")
    }
}
