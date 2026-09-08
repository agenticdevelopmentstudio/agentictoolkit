//
//  LSPCompletionDelegateTests.swift
//  AgenticToolkit
//

import AppKit
import CodeEditSourceEditor
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
}
