//
//  LSPCompletionSnippetTests.swift
//  AgenticToolkit
//

import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitCore
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// Extension snippets merged into the completion list.
///
/// Kept apart from `LSPCompletionDelegateTests` because the subject is
/// different: those tests are about the conversation with the server, these
/// about what happens to a second source of items alongside it. Both drive the
/// real delegate through the protocol method the package calls.
@Suite
@MainActor
struct LSPCompletionSnippetTests {

    private static let sampleText = "let x = prin"
    private static let caretOffset = 12

    // MARK: - Store fixture

    /// A store holding one snippet — prefix `log` — for `language`.
    ///
    /// Built by applying a real extension directory rather than by reaching
    /// inside the store: `apply` is the only way a snippet ever gets in, and a
    /// fixture that bypassed it would be testing a state the app cannot reach.
    private func makeStore(language: String, in directory: URL) throws -> SnippetStore {
        let file = directory.appendingPathComponent("snippets.json")
        try #"{"Log": {"prefix": "log", "body": "print(${1:value})$0", "description": "Print a value"}}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let json = """
        {
            "name": "snippets",
            "publisher": "acme",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "contributes": { "snippets": [{ "language": "\(language)", "path": "./snippets.json" }] }
        }
        """
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        let store = SnippetStore()
        try store.apply(try #require(manifest.contributes), from: manifest, at: directory)
        return store
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LSPCompletionSnippetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFixture(serverLabels: [String]) -> LSPEditorFixture {
        LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                completionResponse: .optionA(serverLabels.map { CompletionItem(label: $0) })
            )
        )
    }

    private func request(
        snippets: SnippetStore?,
        fixture: LSPEditorFixture
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        let document = makeEditorDocument(text: Self.sampleText)
        let delegate = LSPCompletionDelegate(
            document: document,
            registry: fixture.registry,
            snippets: snippets
        )
        let controller = makeEditorTextViewController(text: Self.sampleText)
        return await delegate.completionSuggestionsRequested(
            textView: controller,
            cursorPosition: makeCursor(atOffset: Self.caretOffset)
        )
    }

    // MARK: - Merging

    @Test("a document's snippets appear after the server's items")
    func snippetsFollowServerItems() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(language: "swift", in: directory)
        let fixture = makeFixture(serverLabels: ["print", "println"])
        _ = try await fixture.startedSession()

        let result = try #require(await request(snippets: store, fixture: fixture))

        // Last, at equal relevance: the server knows the document, a snippet
        // file does not.
        #expect(result.items.map(\.label) == ["print", "println", "log"])

        let entry = try #require(result.items.last as? LSPCompletionEntry)
        // `.snippet` is what routes it through the existing flattening insert
        // rather than pasting the markup in literally.
        #expect(entry.item.insertTextFormat == .snippet)
        #expect(entry.item.insertText == "print(${1:value})$0")
        #expect(entry.item.kind == .snippet)
        // Same request range the server's own rangeless items got: the token
        // being completed, so applying it overwrites `prin`.
        let serverEntry = try #require(result.items.first as? LSPCompletionEntry)
        #expect(entry.requestRange == serverEntry.requestRange)
    }

    @Test("snippets for another language do not appear")
    func snippetsForAnotherLanguageAreAbsent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The document is `swift` (the fixture's default); these are Python's.
        let store = try makeStore(language: "python", in: directory)
        let fixture = makeFixture(serverLabels: ["print"])
        _ = try await fixture.startedSession()

        let result = try #require(await request(snippets: store, fixture: fixture))

        #expect(result.items.map(\.label) == ["print"])
    }

    @Test("with no store the list is exactly the server's")
    func noStoreChangesNothing() async throws {
        let fixture = makeFixture(serverLabels: ["print", "println"])
        _ = try await fixture.startedSession()

        let result = try #require(await request(snippets: nil, fixture: fixture))

        #expect(result.items.map(\.label) == ["print", "println"])
    }

    @Test("snippets alone are enough to open the window")
    func snippetsAloneOpenTheWindow() async throws {
        // A server with nothing to say at this caret must not silence the
        // snippets the user installed for exactly these places.
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(language: "swift", in: directory)
        let fixture = makeFixture(serverLabels: [])
        _ = try await fixture.startedSession()

        let result = try #require(await request(snippets: store, fixture: fixture))

        #expect(result.items.map(\.label) == ["log"])
    }

    @Test("an empty store leaves the window closed when the server has nothing")
    func emptyStoreAndEmptyServerCloseTheWindow() async throws {
        let fixture = makeFixture(serverLabels: [])
        _ = try await fixture.startedSession()

        let result = await request(snippets: SnippetStore(), fixture: fixture)

        #expect(result == nil)
    }
}
