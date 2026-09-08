//
//  FileEditorHighlightProviderTests.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// Which highlight providers a cached document's editor is built with, and in
/// what order.
///
/// The order is the entire feature and it is invisible in a screenshot until a
/// real server is attached: `StyledRangeContainer` resolves an overlap in favour
/// of the *lower* provider id, and a provider's id is its index in the array
/// `SourceEditor` was handed. A semantic provider appended after tree-sitter
/// compiles, runs, sends requests, and never paints a character.
@Suite("File editor highlight providers")
@MainActor
struct FileEditorHighlightProviderTests {

    private func makeTemporaryFile() throws -> URL {
        // `FileEditorState.load` builds a `CodeLanguage`, which is what needs
        // CodeEditLanguages' resource bundle located under the test host.
        ensureEditorLanguageResourcesLocated()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileEditorHighlightProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("A.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func makeLoadedState(
        at fileURL: URL,
        withLanguageServices: Bool
    ) async -> FileEditorState {
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: { _ in })
        var services: ProjectLanguageServices?
        if withLanguageServices {
            let fixture = LSPEditorFixture(workspaceURL: fileURL.deletingLastPathComponent())
            services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        }
        let state = FileEditorState(
            documentStore: store,
            saveScheduler: scheduler,
            languageServices: services,
            openFile: nil
        )
        state.load(from: fileURL)
        await state.awaitPendingLoad()
        return state
    }

    @Test("the semantic provider comes first and tree-sitter second")
    func semanticProviderIsAheadOfTreeSitter() async throws {
        let fileURL = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let state = await makeLoadedState(at: fileURL, withLanguageServices: true)

        let providers = try #require(state.highlightProviders(for: fileURL.documentUri))
        try #require(providers.count == 2)

        // Asserted by *index*, not by membership: swapping the two leaves the
        // array with exactly the same contents, and it is the swap that turns
        // this feature off. `#expect(providers.contains { $0 is … })` would pass
        // either way round.
        #expect(providers[0] is SemanticTokenHighlightProvider)
        #expect(providers[1] is TreeSitterClient)
    }

    @Test("the same URI is given the same provider objects on every call")
    func providersAreStableAcrossCalls() async throws {
        let fileURL = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let state = await makeLoadedState(at: fileURL, withLanguageServices: true)
        let uri = fileURL.documentUri

        let first = try #require(state.highlightProviders(for: uri))
        let second = try #require(state.highlightProviders(for: uri))

        // Object identity, not equality. `SourceEditor.paramsAreEqual` compares
        // highlight providers by `ObjectIdentifier`, and `makeEditor` is called
        // again on every SwiftUI update — so a fresh pair per call would look
        // like a different editor every time and tear the whole `Highlighter`
        // down, mid-parse, on every render.
        #expect(first.map { ObjectIdentifier($0) } == second.map { ObjectIdentifier($0) })
    }

    @Test("a pane with no language services keeps the package's own default")
    func noLanguageServicesMeansNoProviderArray() async throws {
        let fileURL = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let state = await makeLoadedState(at: fileURL, withLanguageServices: false)

        // `nil`, not `[TreeSitterClient()]`. `SourceEditor` resolves `nil` to a
        // tree-sitter client of its own, and building one here would only add a
        // fresh object per render for `paramsAreEqual` to notice.
        #expect(state.highlightProviders(for: fileURL.documentUri) == nil)
    }
}
